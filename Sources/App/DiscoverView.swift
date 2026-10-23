import SwiftUI

/// 「发现」：按分组浏览书源 → 书源的发现分类 → 分类书单 → 书籍详情。
/// 一级/二级的整理规则见 DiscoverCatalog，本文件只负责展示与导航。
struct DiscoverView: View {
    @ThemePalette private var palette
    @EnvironmentObject var store: AppStore
    @AppStorage(SourceListLayout.layoutKey) private var layoutRaw = SourceListLayout.grid.rawValue
    @AppStorage(DiscoverSettings.gridColumnsKey) private var gridColumnsValue = 2
    @AppStorage(DiscoverSettings.homeGroupKey) private var homeGroup = ""
    @State private var showSettings = false
    @State private var autoOpenGroup: String?
    @State private var didAutoOpen = false

    private var sections: [(name: String, sources: [BookSource])] {
        DiscoverCatalog.sections(store.sources)
    }
    private var layout: SourceListLayout { SourceListLayout(rawValue: layoutRaw) ?? .grid }
    private var gridColumns: Int { DiscoverSettings.clampedColumns(gridColumnsValue) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                DiscoverLayoutMenu(onSettings: { showSettings = true })
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            if sections.isEmpty {
                List {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("没有可以浏览的书源").appFont(.headline)
                        Text("在「我的 → 书库管理 → 书源」里给书源填写「发现地址」并保持启用，带发现规则的书源会按分组出现在这里。")
                            .appFont(.footnote).foregroundStyle(palette.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .independentGlassRow()
                }
                .scrollContentBackground(.hidden)
            } else if layout == .grid {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: gridColumns), spacing: 12) {
                        ForEach(sections, id: \.name) { section in
                            NavigationLink {
                                DiscoverGroupView(groupName: section.name)
                            } label: {
                                DiscoverGroupGridCard(name: section.name, count: section.sources.count)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("discover.group.\(section.name)")
                        }
                    }
                    .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 24)
                }
            } else {
                List {
                    ForEach(sections, id: \.name) { section in
                        NavigationLink {
                            DiscoverGroupView(groupName: section.name)
                        } label: {
                            DiscoverGroupCard(name: section.name, count: section.sources.count)
                        }
                        .independentGlassRow()
                        .accessibilityIdentifier("discover.group.\(section.name)")
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .foregroundStyle(palette.primary)
        .background { AppThemeCanvas().ignoresSafeArea() }
        .navigationTitle("发现")
        .toolbar(.visible, for: .navigationBar)
        .sheet(isPresented: $showSettings) {
            DiscoverSettingsView()
                .environmentObject(store)
        }
        .navigationDestination(isPresented: Binding(
            get: { autoOpenGroup != nil },
            set: { if !$0 { autoOpenGroup = nil } }
        )) {
            if let group = autoOpenGroup {
                DiscoverGroupView(groupName: group)
            }
        }
        .onAppear {
            guard !didAutoOpen else { return }
            didAutoOpen = true
            let group = homeGroup.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !group.isEmpty, sections.contains(where: { $0.name == group }) else { return }
            autoOpenGroup = group
        }
        .accessibilityIdentifier("discover.page")
    }
}

// MARK: - 二级：分组里的书源

struct DiscoverGroupView: View {
    @ThemePalette private var palette
    @EnvironmentObject var store: AppStore
    let groupName: String
    @AppStorage(SourceListLayout.layoutKey) private var layoutRaw = SourceListLayout.grid.rawValue
    @AppStorage(DiscoverSettings.gridColumnsKey) private var gridColumnsValue = 2

    private var sources: [BookSource] {
        DiscoverCatalog.sources(inGroup: groupName, from: store.sources)
    }
    private var layout: SourceListLayout { SourceListLayout(rawValue: layoutRaw) ?? .grid }
    private var gridColumns: Int { DiscoverSettings.clampedColumns(gridColumnsValue) }

    var body: some View {
        Group {
            if sources.isEmpty {
                List {
                    Text("这个分组暂时没有可以浏览的书源")
                        .appFont(.footnote).foregroundStyle(palette.secondary)
                        .independentGlassRow()
                }
                .scrollContentBackground(.hidden)
            } else if layout == .grid {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: gridColumns), spacing: 12) {
                        ForEach(sources) { source in
                            NavigationLink {
                                DiscoverSourceView(source: source)
                            } label: {
                                SourceGridCard(source: source,
                                               subtitle: DiscoverCatalog.displayDomain(source.bookSourceUrl))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("discover.source.\(source.bookSourceName)")
                        }
                    }
                    .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 24)
                }
            } else {
                List {
                    ForEach(sources) { source in
                        NavigationLink {
                            DiscoverSourceView(source: source)
                        } label: {
                            DiscoverSourceCard(source: source)
                        }
                        .independentGlassRow()
                        .accessibilityIdentifier("discover.source.\(source.bookSourceName)")
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .foregroundStyle(palette.primary)
        .background { AppThemeCanvas().ignoresSafeArea() }
        .navigationTitle(groupName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 三级：某个书源的发现分类

/// 一个书源的发现页。两种形态：
///  - 列表（默认，对应参考图）：顶部搜索框 →「筛选」里的控件行 → 分组标题 + 分类行；
///  - 杂志：把所有榜单平铺成一屏（老样子，保留给习惯平铺浏览的人）。
///
/// 书源发现规则里的控件三类都要认：`select`（性别/模式/源站…）、`text`（关键词输入）、
/// `button`（搜索/刷新/登录）。以前只取 select，text 和 button 被当成装饰丢掉了。
struct DiscoverSourceView: View {
    @ThemePalette private var palette
    let source: BookSource
    @StateObject private var loader: DiscoverBlockLoader
    @State private var kinds: [SourceDiagnostics.ExploreKind] = []
    @State private var loading = true
    @State private var reloadToken = UUID()
    @State private var controlValues: [String: String] = [:]
    @State private var applyingControl = false
    /// 顶部「搜索发现项目」：只过滤本页的分类行，不发请求。
    @State private var query = ""
    @State private var showLogin = false
    @State private var searchRequest: SourceSearchRequest?
    @AppStorage(DiscoverSettings.pageLayoutKey) private var pageLayoutRaw = DiscoverSettings.PageLayout.list.rawValue
    @AppStorage(DiscoverSettings.rankingModeKey) private var rankingModeRaw = DiscoverSettings.RankingMode.cycle.rawValue
    @AppStorage(DiscoverSettings.rankingKeywordsKey) private var keywordsRaw = ""
    @AppStorage(DiscoverSettings.verticalCountKey) private var verticalCount = DiscoverSettings.defaultVerticalCount
    @AppStorage(DiscoverSettings.horizontalCountKey) private var horizontalCount = DiscoverSettings.defaultHorizontalCount
    @AppStorage(DiscoverSettings.cycleVerticalKey) private var cycleVertical = DiscoverSettings.defaultCycleVertical
    @AppStorage(DiscoverSettings.cycleHorizontalKey) private var cycleHorizontal = DiscoverSettings.defaultCycleHorizontal
    @AppStorage(DiscoverSettings.preloadCountKey) private var preloadCount = DiscoverSettings.defaultPreloadCount

    init(source: BookSource) {
        self.source = source
        _loader = StateObject(wrappedValue: DiscoverBlockLoader(source: source))
    }

    private var errorText: String? { DiscoverCatalog.kindError(kinds) }

    /// 有选项的下拉控件：性别、模式、源站…
    private var selectControls: [SourceDiagnostics.ExploreKind] {
        // 书源脚本可能把同一组控件拼两次，按标题去重，避免同样一行出现两遍
        var seen = Set<String>()
        return kinds.filter { kind in
            guard (kind.type ?? "") == "select", !(kind.chars ?? []).isEmpty else { return false }
            guard !DiscoverCatalog.isDecorativeControlTitle(kind.title) else { return false }
            return seen.insert(kind.title).inserted
        }
    }
    /// 输入控件：关键词之类。
    private var textControls: [SourceDiagnostics.ExploreKind] {
        var seen = Set<String>()
        return kinds.filter { kind in
            guard (kind.type ?? "") == "text", !DiscoverCatalog.isDecorativeControlTitle(kind.title) else { return false }
            return seen.insert(kind.title).inserted
        }
    }
    /// 按钮控件：搜索 / 刷新 / 登录。
    private var buttonControls: [SourceDiagnostics.ExploreKind] {
        var seen = Set<String>()
        return kinds.filter { kind in
            guard (kind.type ?? "") == "button", !DiscoverCatalog.isDecorativeControlTitle(kind.title) else { return false }
            return seen.insert(kind.title).inserted
        }
    }
    private var hasControls: Bool {
        !selectControls.isEmpty || !textControls.isEmpty || !buttonControls.isEmpty
    }

    private var allSections: [(header: String?, items: [SourceDiagnostics.ExploreKind])] {
        DiscoverCatalog.kindSections(kinds)
    }
    /// 搜索框过滤后的分组（标题和条目都参与匹配）。
    private var sections: [(header: String?, items: [SourceDiagnostics.ExploreKind])] {
        let key = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return allSections }
        return allSections.compactMap { section in
            let items = section.items.filter { $0.title.localizedCaseInsensitiveContains(key) }
            if items.isEmpty {
                guard let header = section.header, header.localizedCaseInsensitiveContains(key) else { return nil }
                return (header, section.items)
            }
            return (section.header, items)
        }
    }
    private var flatItems: [SourceDiagnostics.ExploreKind] { allSections.flatMap(\.items) }
    private var pageLayout: DiscoverSettings.PageLayout {
        DiscoverSettings.PageLayout(rawValue: pageLayoutRaw) ?? .list
    }
    private var rankingMode: DiscoverSettings.RankingMode {
        DiscoverSettings.RankingMode(rawValue: rankingModeRaw) ?? .cycle
    }
    private var keywords: [String] { DiscoverSettings.keywords(from: keywordsRaw) }

    var body: some View {
        Group {
            if pageLayout == .list {
                referenceLayout
            } else {
                magazineLayout
            }
        }
        .foregroundStyle(palette.primary)
        .background { AppThemeCanvas().ignoresSafeArea() }
        .navigationTitle(source.bookSourceName)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: reloadToken) { await load() }
        .sheet(isPresented: $showLogin) {
            SourceLoginView(source: source)
        }
        .navigationDestination(item: $searchRequest) { request in
            DiscoverSourceSearchView(source: source, key: request.key)
        }
        .accessibilityIdentifier("discover.source.page")
    }

    // MARK: 列表布局（参考图：搜索框 + 筛选 + 分组行）

    private var referenceLayout: some View {
        List {
            Section {
                searchField
                    .independentGlassRow()
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            }

            if hasControls {
                Section {
                    ForEach(Array(textControls.enumerated()), id: \.offset) { pair in
                        textControlRow(pair.element)
                            .independentGlassRow()
                    }
                    ForEach(Array(selectControls.enumerated()), id: \.offset) { pair in
                        selectControlRow(pair.element)
                            .independentGlassRow()
                    }
                    if !buttonControls.isEmpty {
                        buttonControlRow
                            .independentGlassRow()
                    }
                    if applyingControl {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("正在切换…").appFont(.footnote).foregroundStyle(palette.secondary)
                        }
                        .independentGlassRow()
                    }
                } header: {
                    Text("筛选")
                } footer: {
                    Text("这些是书源自己的筛选与操作，改动会写回书源配置。")
                }
            }

            if loading {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("正在读取发现分类…").appFont(.footnote).foregroundStyle(palette.secondary)
                }
                .independentGlassRow()
            } else if let errorText {
                VStack(alignment: .leading, spacing: 8) {
                    Text(errorText).appFont(.footnote).foregroundStyle(palette.secondary)
                    Button("重试") { reloadToken = UUID() }
                        .appFont(.footnote.weight(.semibold))
                        .accessibilityIdentifier("discover.retry")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .independentGlassRow()
            } else if sections.isEmpty {
                Text(query.isEmpty
                     ? "这个书源暂时没有发现分类；可以在书源编辑里检查「发现地址」。"
                     : "没有匹配「\(query)」的发现项目。")
                    .appFont(.footnote).foregroundStyle(palette.secondary)
                    .independentGlassRow()
            }

            ForEach(Array(sections.enumerated()), id: \.offset) { pair in
                Section {
                    ForEach(pair.element.items, id: \.self) { kind in
                        NavigationLink {
                            DiscoverBooksView(source: source,
                                              kindTitle: kind.title,
                                              kindUrl: kind.url ?? "")
                        } label: {
                            kindRowLabel(kind)
                        }
                        .independentGlassRow()
                        .accessibilityIdentifier("discover.kind.\(kind.title)")
                    } header: {
                        Text(pair.element.header ?? "")
                            .appFont(.system(size: 13, weight: .semibold))
                            .foregroundStyle(palette.secondary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .refreshable { await refreshAll() }
        .accessibilityIdentifier("discover.source.list")
    }

    /// 顶部搜索框：只过滤本页项目，不联网。
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(palette.secondary)
            TextField("", text: $query,
                      prompt: Text("搜索发现项目").foregroundColor(palette.secondary))
                .appFont(.system(size: 15))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("discover.source.search")
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(palette.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜索")
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 42)
        .background {
            Capsule().fill(palette.primary.opacity(0.045))
        }
    }

    /// 分类行：标题 + 右侧箭头（参考图的形态）。
    private func kindRowLabel(_ kind: SourceDiagnostics.ExploreKind) -> some View {
        HStack(spacing: 8) {
            Text(kind.title)
                .appFont(.system(size: 15))
                .foregroundStyle(palette.primary)
                .lineLimit(1)
            Spacer(minLength: 6)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.secondary.opacity(0.6))
        }
        .contentShape(Rectangle())
    }

    /// 下拉控件行：左边标题，右边当前值 + 上下箭头（和图二一致）。
    private func selectControlRow(_ control: SourceDiagnostics.ExploreKind) -> some View {
        let current = controlValues[control.title] ?? control.defaultValue ?? control.chars?.first ?? ""
        return Menu {
            ForEach(control.chars ?? [], id: \.self) { option in
                Button {
                    applyControl(control, value: option)
                } label: {
                    if current == option {
                        Label(option, systemImage: "checkmark")
                    } else {
                        Text(option)
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(DiscoverCatalog.controlTitle(control.title))
                    .appFont(.system(size: 15))
                    .foregroundStyle(palette.primary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text(current)
                    .appFont(.system(size: 14))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.secondary)
            }
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("discover.filter.\(control.title)")
    }

    /// 输入控件行：标题 + 输入框，回车提交 action。
    private func textControlRow(_ control: SourceDiagnostics.ExploreKind) -> some View {
        HStack(spacing: 8) {
            Text(DiscoverCatalog.controlTitle(control.title))
                .appFont(.system(size: 15))
                .foregroundStyle(palette.primary)
                .lineLimit(1)
            Spacer(minLength: 6)
            TextField("", text: Binding(
                get: { controlValues[control.title] ?? "" },
                set: { controlValues[control.title] = $0 }
            ), prompt: Text("书源/作者").foregroundColor(palette.secondary))
                .appFont(.system(size: 14))
                .multilineTextAlignment(.trailing)
                .submitLabel(.search)
                .onSubmit { applyControl(control, value: controlValues[control.title] ?? "") }
                .accessibilityIdentifier("discover.text.\(control.title)")
        }
    }

    /// 按钮控件：搜索 / 刷新 / 登录 一类的操作，一行一个。
    private var buttonControlRow: some View {
        HStack(spacing: 10) {
            ForEach(Array(buttonControls.enumerated()), id: \.offset) { pair in
                Button {
                    let keyword = textControls.first.flatMap { controlValues[$0.title] } ?? ""
                    applyControl(pair.element, value: keyword)
                } label: {
                    Text(DiscoverCatalog.controlTitle(pair.element.title))
                        .appFont(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.accent)
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background { ThemeSurface(shape: Capsule()) }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("discover.button.\(pair.element.title)")
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: 杂志布局（榜单平铺）

    private var magazineLayout: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                filterRows
                stateRows

                if !loading, errorText == nil, !allSections.isEmpty {
                    ForEach(Array(allSections.enumerated()), id: \.offset) { pair in
                        if let header = pair.element.header {
                            Text(header)
                                .appFont(.headline)
                                .foregroundStyle(palette.primary)
                                .padding(.horizontal, 16)
                        }
                        ForEach(pair.element.items, id: \.self) { kind in
                            let vertical = verticalFlag(for: kind)
                            DiscoverSectionBlock(
                                loader: loader,
                                kind: kind,
                                vertical: vertical,
                                itemCount: vertical ? verticalCount : horizontalCount,
                                onAppear: { preload(after: kind) }
                            )
                            .padding(.horizontal, 16)
                        }
                    }
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .refreshable { await refreshAll() }
    }

    @ViewBuilder private var filterRows: some View {
        if !selectControls.isEmpty {
            DiscoverFilterBar(controls: selectControls, values: controlValues) { control, value in
                applyControl(control, value: value)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
        }
        if applyingControl {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("正在切换…").appFont(.footnote).foregroundStyle(palette.secondary)
            }
            .padding(.horizontal, 16)
        }
    }

    @ViewBuilder private var stateRows: some View {
        if loading {
            HStack(spacing: 10) {
                ProgressView()
                Text("正在读取发现分类…").appFont(.footnote).foregroundStyle(palette.secondary)
            }
            .padding(.horizontal, 16)
        } else if let errorText = errorText {
            VStack(alignment: .leading, spacing: 8) {
                Text(errorText).appFont(.footnote).foregroundStyle(palette.secondary)
                Button("重试") { reloadToken = UUID() }
                    .appFont(.footnote.weight(.semibold))
                    .accessibilityIdentifier("discover.retry")
            }
            .padding(.horizontal, 16)
        } else if allSections.isEmpty {
            Text("这个书源暂时没有发现分类；可以在书源编辑里检查「发现地址」。")
                .appFont(.footnote).foregroundStyle(palette.secondary)
                .padding(.horizontal, 16)
        }
    }

    // MARK: 数据

    private func verticalFlag(for kind: SourceDiagnostics.ExploreKind) -> Bool {
        let index = flatItems.firstIndex(of: kind) ?? 0
        return DiscoverSettings.usesVerticalStyle(
            index: index,
            title: kind.title,
            mode: rankingMode,
            keywords: keywords,
            cycleVertical: cycleVertical,
            cycleHorizontal: cycleHorizontal
        )
    }

    private func preload(after kind: SourceDiagnostics.ExploreKind) {
        guard preloadCount > 0, let index = flatItems.firstIndex(of: kind) else { return }
        let end = min(index + preloadCount, flatItems.count - 1)
        guard end > index else { return }
        loader.preload(flatItems[(index + 1)...end].compactMap { $0.url })
    }

    /// 读取发现分类：缓存期内直接用缓存（不重新执行发现脚本），force 用于下拉刷新。
    private func load(force: Bool = false) async {
        let src = source
        if !force, let cached = DiscoverKindsCache.cached(source: source.bookSourceUrl) {
            kinds = cached
            controlValues = Self.controlValues(from: cached)
            loading = false
            return
        }
        loading = true
        let result = await Task.detached(priority: .userInitiated) {
            SourceDiagnostics.exploreKinds(source: src)
        }.value
        kinds = result
        controlValues = Self.controlValues(from: result)
        loading = false
        if DiscoverCatalog.kindError(result) == nil, !result.isEmpty {
            DiscoverKindsCache.store(source: source.bookSourceUrl, kinds: result)
        }
    }

    /// 执行控件 action：写配置 / 刷新分类 / 打开登录 / 发起搜索。
    private func applyControl(_ control: SourceDiagnostics.ExploreKind, value: String) {
        guard let action = control.action, !action.isEmpty else { return }
        var info = controlValues
        info[control.title] = value
        controlValues = info
        applyingControl = true
        let src = source
        Task {
            let ui = await Task.detached(priority: .userInitiated) {
                SourceDiagnostics.applyExploreControl(source: src, action: action, info: info)
            }.value
            if let ui { handle(ui) }
            let result = await Task.detached(priority: .userInitiated) {
                SourceDiagnostics.exploreKinds(source: src)
            }.value
            kinds = result
            if DiscoverCatalog.kindError(result) == nil, !result.isEmpty {
                DiscoverKindsCache.store(source: source.bookSourceUrl, kinds: result)
            }
            var values = Self.controlValues(from: result)
            for (key, v) in info where values[key] == nil { values[key] = v }
            controlValues = values
            applyingControl = false
        }
    }

    /// 脚本想打开的界面：登录页 / 书源内搜索。
    private func handle(_ action: SourceUiAction) {
        switch action {
        case .open(let ui, _, _):
            if ui == "login" { showLogin = true }
        case .search(let key, _):
            let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            searchRequest = SourceSearchRequest(key: trimmed)
        }
    }

    private static func controlValues(from kinds: [SourceDiagnostics.ExploreKind]) -> [String: String] {
        var values: [String: String] = [:]
        for kind in kinds where (kind.type ?? "") == "select" {
            if let def = kind.defaultValue, !def.isEmpty {
                values[kind.title] = def
            } else if let first = kind.chars?.first {
                values[kind.title] = first
            }
        }
        return values
    }

    /// 下拉刷新：清缓存并重新拉取分类与已加载的板块。
    private func refreshAll() async {
        DiscoverBlockCache.clear()
        DiscoverKindsCache.clear()
        let loaded = Array(loader.books.keys)
        await load(force: true)
        for url in loaded {
            await loader.load(url, force: true)
        }
    }
}

/// 书源内搜索的请求（`java.searchBook` 触发）。
struct SourceSearchRequest: Identifiable, Hashable {
    let id = UUID()
    let key: String
}

/// 书源内搜索：直接走这个书源的搜索规则，不再跨源聚合。
struct DiscoverSourceSearchView: View {
    @ThemePalette private var palette
    let source: BookSource
    let key: String

    @State private var books: [Book] = []
    @State private var loading = true
    @State private var errorText: String?

    var body: some View {
        List {
            if loading {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("正在搜索「\(key)」…").appFont(.footnote).foregroundStyle(palette.secondary)
                }
                .independentGlassRow()
            } else if let errorText {
                VStack(alignment: .leading, spacing: 8) {
                    Text(errorText).appFont(.footnote).foregroundStyle(palette.secondary)
                    Button("重试") { Task { await run() } }
                        .appFont(.footnote.weight(.semibold))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .independentGlassRow()
            } else if books.isEmpty {
                Text("没有搜到相关书籍").appFont(.footnote).foregroundStyle(palette.secondary)
                    .independentGlassRow()
            } else {
                ForEach(books) { book in
                    NavigationLink {
                        BookDetailView(book: book)
                    } label: {
                        BookRow(book: book, subtitle: "来源：\(source.bookSourceName)")
                    }
                    .independentGlassRow()
                }
            }
        }
        .scrollContentBackground(.hidden)
        .foregroundStyle(palette.primary)
        .background { AppThemeCanvas().ignoresSafeArea() }
        .navigationTitle(key)
        .navigationBarTitleDisplayMode(.inline)
        .task { await run() }
    }

    private func run() async {
        loading = true
        errorText = nil
        let src = source
        do {
            books = try await WebBook.search(source: src, key: key)
        } catch {
            errorText = "搜索失败：\(error)"
        }
        loading = false
    }
}

// MARK: - 四级：某个分类下的书单

struct DiscoverBooksView: View {
    @ThemePalette private var palette
    let source: BookSource
    let kindTitle: String
    let kindUrl: String

    @State private var books: [Book] = []
    @State private var loading = true
    @State private var loadingMore = false
    @State private var errorText: String?
    @State private var moreError: String?
    @State private var noMore = false
    @State private var page = 1

    private var supportsMore: Bool { kindUrl.contains("{{page}}") }

    var body: some View {
        List {
            if loading {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("正在加载书单…").appFont(.footnote).foregroundStyle(palette.secondary)
                }
                .independentGlassRow()
            } else if let errorText = errorText {
                VStack(alignment: .leading, spacing: 8) {
                    Text(errorText).appFont(.footnote).foregroundStyle(palette.secondary)
                    Button("重试") { Task { await reload() } }
                        .appFont(.footnote.weight(.semibold))
                        .accessibilityIdentifier("discover.books.retry")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .independentGlassRow()
            } else if books.isEmpty {
                Text("没有获取到书籍").appFont(.footnote).foregroundStyle(palette.secondary)
                    .independentGlassRow()
            } else {
                ForEach(books) { book in
                    NavigationLink {
                        BookDetailView(book: book)
                    } label: {
                        BookRow(book: book, subtitle: "来源：\(source.bookSourceName)")
                    }
                    .independentGlassRow()
                }
                footer
            }
        }
        .scrollContentBackground(.hidden)
        .foregroundStyle(palette.primary)
        .background { AppThemeCanvas().ignoresSafeArea() }
        .navigationTitle(kindTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { if books.isEmpty { await reload() } }
        .accessibilityIdentifier("discover.books.page")
    }

    @ViewBuilder private var footer: some View {
        if supportsMore && !noMore {
            VStack(spacing: 8) {
                if let moreError = moreError {
                    Text(moreError).appFont(.caption2).foregroundStyle(palette.secondary)
                        .multilineTextAlignment(.center).lineLimit(3)
                }
                if loadingMore {
                    ProgressView()
                } else {
                    Button(moreError == nil ? "加载更多" : "重试加载") { Task { await loadNextPage() } }
                        .appFont(.footnote.weight(.semibold))
                        .accessibilityIdentifier("discover.books.more")
                }
            }
            .frame(maxWidth: .infinity)
            .independentGlassRow()
        } else {
            Text(noMore ? "没有更多了" : "共 \(books.count) 本")
                .appFont(.caption).foregroundStyle(palette.secondary)
                .frame(maxWidth: .infinity)
                .independentGlassRow()
        }
    }

    private func reload() async {
        loading = true; errorText = nil; moreError = nil; noMore = false; page = 1
        do {
            let list = try await SourceDiagnostics.explore(source: source, url: kindUrl, page: 1)
            books = list
            loading = false
        } catch {
            errorText = error.localizedDescription
            loading = false
        }
    }

    private func loadNextPage() async {
        guard !loadingMore else { return }
        loadingMore = true
        moreError = nil
        defer { loadingMore = false }
        do {
            let next = page + 1
            let list = try await SourceDiagnostics.explore(source: source, url: kindUrl, page: next)
            let known = Set(books.map(\.bookUrl))
            let fresh = list.filter { !known.contains($0.bookUrl) }
            page = next
            if fresh.isEmpty { noMore = true } else { books += fresh }
        } catch {
            moreError = error.localizedDescription
        }
    }
}

// MARK: - 卡片组件

/// 圆角方块头像：名字首字 + 由名字决定的稳定渐变底色。
struct SourceAvatarView: View {
    let name: String
    var size: CGFloat = 46

    private var initial: String {
        let text = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "书" : String(text.prefix(1))
    }
    private var colors: [Color] {
        let hue = DiscoverCatalog.avatarHue(for: name)
        return [Color(hue: hue, saturation: 0.55, brightness: 0.95),
                Color(hue: (hue + 0.09).truncatingRemainder(dividingBy: 1),
                      saturation: 0.72, brightness: 0.80)]
    }

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay {
                Text(initial)
                    .appFont(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }
}

private struct SourceTagPill: View {
    @ThemePalette private var palette
    let text: String

    var body: some View {
        Text(text)
            .appFont(.caption2)
            .foregroundStyle(palette.accent)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(palette.accent.opacity(0.14), in: Capsule())
    }
}

private struct DiscoverGroupCard: View {
    @ThemePalette private var palette
    let name: String
    let count: Int

    var body: some View {
        HStack(spacing: 12) {
            SourceAvatarView(name: name)
            VStack(alignment: .leading, spacing: 4) {
                Text(name).appFont(.headline).lineLimit(1)
                Text(count == 1 ? "1 个书源" : "\(count) 个书源")
                    .appFont(.caption).foregroundStyle(palette.secondary)
            }
            Spacer(minLength: 8)
        }
    }
}

/// 分组网格卡：与书源网格卡同视觉，显示组名与书源数，尺寸随列数自适应。
private struct DiscoverGroupGridCard: View {
    @ThemePalette private var palette
    @AppStorage(DiscoverSettings.gridColumnsKey) private var gridColumnsValue = 2
    let name: String
    let count: Int

    private var columns: Int { DiscoverSettings.clampedColumns(gridColumnsValue) }
    private var avatarSize: CGFloat {
        switch columns {
        case 2: return 62
        case 3: return 48
        case 4: return 40
        default: return 34
        }
    }
    private var titleSize: CGFloat { columns >= 4 ? 12 : (columns == 3 ? 13.5 : 16) }
    private var captionSize: CGFloat { columns >= 4 ? 10 : (columns == 3 ? 11 : 12) }
    private var verticalPadding: CGFloat { columns >= 4 ? 12 : (columns == 3 ? 16 : 20) }

    var body: some View {
        VStack(spacing: columns >= 4 ? 7 : 11) {
            SourceAvatarView(name: name, size: avatarSize)
            VStack(spacing: 3) {
                Text(name)
                    .appFont(.system(size: titleSize, weight: .semibold))
                    .foregroundStyle(palette.primary)
                    .lineLimit(1)
                Text(count == 1 ? "1 个书源" : "\(count) 个书源")
                    .appFont(.system(size: captionSize))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.top, verticalPadding)
        .padding(.bottom, verticalPadding - 4)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .background {
            ThemeSurface(shape: RoundedRectangle(cornerRadius: 20, style: .continuous), isCard: true)
        }
    }
}

private struct DiscoverSourceCard: View {
    @ThemePalette private var palette
    let source: BookSource

    var body: some View {
        HStack(spacing: 12) {
            SourceAvatarView(name: source.bookSourceName)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(source.bookSourceName).appFont(.headline).lineLimit(1)
                    if let tag = source.discoverTypeLabel { SourceTagPill(text: tag) }
                }
                Text(DiscoverCatalog.displayDomain(source.bookSourceUrl))
                    .appFont(.caption).foregroundStyle(palette.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
        }
    }
}

/// 发现页右上角「…」：切换排列方式（网格 / 列表），系统勾选在选项右侧；下方可进入设置。
/// 首页分组与分组里的书源都按所选方式排列。
struct DiscoverLayoutMenu: View {
    @ThemePalette private var palette
    @AppStorage(SourceListLayout.layoutKey) private var layoutRaw = SourceListLayout.grid.rawValue
    var onSettings: () -> Void = {}

    var body: some View {
        Menu {
            Picker("排列方式", selection: $layoutRaw) {
                ForEach(SourceListLayout.allCases, id: \.rawValue) { value in
                    Text(value.title).tag(value.rawValue)
                }
            }
            Divider()
            Button {
                onSettings()
            } label: {
                Label("设置", systemImage: "gearshape")
            }
            .accessibilityIdentifier("discover.settings")
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 20, weight: .bold))
                .frame(width: 44, height: 44)
                .background { ThemeSurface(shape: Circle()) }
        }
        .buttonStyle(.plain)
        .foregroundStyle(palette.primary)
        .accessibilityLabel("排列方式")
        .accessibilityIdentifier("discover.layout.menu")
    }
}
