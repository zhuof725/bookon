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
                Spacer(minLength: 0)
                DiscoverLayoutMenu(onSettings: { showSettings = true })
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

struct DiscoverSourceView: View {
    @ThemePalette private var palette
    let source: BookSource
    @StateObject private var loader: DiscoverBlockLoader
    @State private var kinds: [SourceDiagnostics.ExploreKind] = []
    @State private var loading = true
    @State private var reloadToken = UUID()
    @State private var selectedKindURL: String?
    @AppStorage(DiscoverSettings.pageLayoutKey) private var pageLayoutRaw = DiscoverSettings.PageLayout.magazine.rawValue
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
    private var sections: [(header: String?, items: [SourceDiagnostics.ExploreKind])] {
        DiscoverCatalog.kindSections(kinds)
    }
    private var flatItems: [SourceDiagnostics.ExploreKind] { sections.flatMap(\.items) }
    private var pageLayout: DiscoverSettings.PageLayout {
        DiscoverSettings.PageLayout(rawValue: pageLayoutRaw) ?? .magazine
    }
    private var rankingMode: DiscoverSettings.RankingMode {
        DiscoverSettings.RankingMode(rawValue: rankingModeRaw) ?? .cycle
    }
    private var keywords: [String] { DiscoverSettings.keywords(from: keywordsRaw) }

    var body: some View {
        Group {
            if pageLayout == .list {
                listLayout
            } else {
                magazineLayout
            }
        }
        .foregroundStyle(palette.primary)
        .background { AppThemeCanvas().ignoresSafeArea() }
        .navigationTitle(source.bookSourceName)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: reloadToken) { await load() }
        .accessibilityIdentifier("discover.source.page")
    }

    // MARK: 杂志布局（榜单平铺）

    private var magazineLayout: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                stateRows
                if !loading, errorText == nil, !sections.isEmpty {
                    ForEach(Array(sections.enumerated()), id: \.offset) { pair in
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

    // MARK: 列表布局（分类筛选 + 书卡列表）

    private var listLayout: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(flatItems, id: \.self) { kind in
                        kindChip(kind)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            Divider().opacity(0.15)
            ScrollView {
                LazyVStack(spacing: 14) {
                    stateRows
                    if let url = selectedKindURL {
                        let books = loader.books(for: url) ?? []
                        if books.isEmpty {
                            if loader.isLoading(url) {
                                HStack(spacing: 8) {
                                    ProgressView().controlSize(.small)
                                    Text("加载中…").appFont(.footnote).foregroundStyle(palette.secondary)
                                }
                            } else if loader.hasFailed(url) {
                                HStack(spacing: 10) {
                                    Text("加载失败").appFont(.footnote).foregroundStyle(palette.secondary)
                                    Button("重试") { Task { await loader.load(url, force: true) } }
                                        .appFont(.footnote.weight(.semibold))
                                }
                            } else {
                                Text("暂无内容").appFont(.footnote).foregroundStyle(palette.secondary)
                            }
                        } else {
                            ForEach(books) { book in
                                NavigationLink {
                                    BookDetailView(book: book)
                                } label: {
                                    DiscoverBookListRow(book: book)
                                }
                                .buttonStyle(.plain)
                                .padding(.horizontal, 16)
                            }
                        }
                    }
                }
                .padding(.vertical, 12)
            }
            .refreshable { await refreshAll() }
        }
    }

    private func kindChip(_ kind: SourceDiagnostics.ExploreKind) -> some View {
        let selected = selectedKindURL == (kind.url ?? "")
        return Button {
            selectedKindURL = kind.url
            if let url = kind.url { Task { await loader.load(url) } }
        } label: {
            Text(kind.title)
                .appFont(.system(size: 13, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? palette.onAccent : palette.primary)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background {
                    if selected {
                        Capsule().fill(palette.accent)
                    } else {
                        ThemeSurface(shape: Capsule())
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("discover.kind.\(kind.title)")
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
        } else if sections.isEmpty {
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
            loading = false
            applyDefaultSelection()
            return
        }
        loading = true
        let result = await Task.detached(priority: .userInitiated) {
            SourceDiagnostics.exploreKinds(source: src)
        }.value
        kinds = result
        loading = false
        if DiscoverCatalog.kindError(result) == nil, !result.isEmpty {
            DiscoverKindsCache.store(source: source.bookSourceUrl, kinds: result)
        }
        applyDefaultSelection()
    }

    private func applyDefaultSelection() {
        let items = DiscoverCatalog.kindSections(kinds).flatMap(\.items)
        guard selectedKindURL == nil, let first = items.first?.url else { return }
        selectedKindURL = first
        if pageLayout == .list {
            Task { await loader.load(first) }
        }
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
        if pageLayout == .list, let url = selectedKindURL {
            await loader.load(url, force: true)
        }
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
