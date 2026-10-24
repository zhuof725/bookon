import SwiftUI

/// 添加板块：**一页搞定**。
///
/// 从上到下：模板列表（左图右文，带封面预览）→ 书源 → 分类 → 添加按钮。
/// 点加号 push 进这一页，不弹窗、不套娃，选完直接添加。
struct AddBoardPage: View {
    @ThemePalette private var palette
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore

    /// 添加成功回调（由编辑页写入草稿）
    var onAdd: ([CustomDiscoverEntry]) -> Void
    /// 从模板库进来时已经选好的模板。
    /// 有值时这一页只负责选书源和分类（模板那一段整块隐藏）；
    /// 为 nil 时才需要在这里挑模板。
    var initialTemplate: DiscoverTemplateKind?

    @State private var template: DiscoverTemplateKind = .deck
    @State private var templateReady = false
    @State private var sourceUrl: String = ""
    @State private var kinds: [SourceDiagnostics.ExploreKind] = []
    @State private var kindsLoading = false
    @State private var kindsError: String?
    @State private var picked: Set<String> = []
    /// 切换书源/分类时给一点淡入，避免内容「啪」地跳出来
    @State private var contentVisible = false
    /// 书源自己的筛选控件（性别 / 模式 / 源站 / 晋江标签…）与当前值
    @State private var controls = SourceControlSet()
    @State private var applyingControl = false
    /// 改筛选后的说明（书源没跟着变时给一句提示）
    @State private var controlNote: String?
    @State private var showLogin = false
    @State private var searchRequest: SourceSearchRequest?

    private var sources: [BookSource] { DiscoverCatalog.explorableSources(store.sources) }

    private var selectedSource: BookSource? {
        sources.first { $0.bookSourceUrl == sourceUrl }
    }

    private var selectableKinds: [SourceDiagnostics.ExploreKind] {
        kinds.filter { kind in
            guard (kind.type ?? "").isEmpty else { return false }
            guard let url = kind.url, !url.isEmpty else { return false }
            return !DiscoverCatalog.isDecorativeControlTitle(kind.title)
        }
    }

    /// 可选分类按书源自己的分组切段（「男频榜单」「男频分类」…）。
    private var kindGroups: [(header: String?, items: [SourceDiagnostics.ExploreKind])] {
        DiscoverCatalog.selectableKindSections(kinds)
    }

    private var canAdd: Bool {
        template.dataSource == .readingProgress || !picked.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if initialTemplate == nil {
                    templateSection
                }
                if template.dataSource == .bookList {
                    sourceSection
                    controlSection
                    kindSection
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 120)
        }
        .background { AppThemeCanvas().ignoresSafeArea() }
        .foregroundStyle(palette.primary)
        .navigationTitle(initialTemplate == nil ? "添加栏目" : "选择分类")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            addBar
        }
        .sheet(isPresented: $showLogin) {
            if let source = selectedSource { SourceLoginView(source: source) }
        }
        .navigationDestination(item: $searchRequest) { request in
            if let source = selectedSource {
                DiscoverSourceSearchView(source: source, key: request.key)
            }
        }
        .task {
            if !templateReady {
                templateReady = true
                if let initialTemplate { template = initialTemplate }
            }
            await preloadFirstSource()
        }
    }

    // MARK: 模板（当前选择 + 展示库入口）

    private var templateSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("选择模板")

            NavigationLink {
                DiscoverTemplateLibrary(current: template,
                                        onPick: { kind in
                    withAnimation(.easeInOut(duration: 0.2)) { template = kind }
                }, dismissOnPick: false)
            } label: {
                HStack(spacing: 12) {
                    // 左：当前模板的缩略预览
                    DiscoverTemplateThumbnail(kind: template)
                        .frame(width: 104, height: 78)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .strokeBorder(palette.accent, lineWidth: 1.5)
                        }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(template.title)
                            .appFont(.system(size: 15, weight: .semibold))
                            .foregroundStyle(palette.primary)
                        Text(template.detail)
                            .appFont(.system(size: 11.5))
                            .foregroundStyle(palette.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)

                    HStack(spacing: 3) {
                        Text("展示库")
                            .appFont(.system(size: 12, weight: .semibold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(palette.accent)
                }
                .padding(9)
                .background {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(palette.accent.opacity(0.07))
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("add.template.library")

            Text("展示库里每个模板按真实尺寸铺开，点一个就换过来。")
                .appFont(.system(size: 11))
                .foregroundStyle(palette.secondary)
                .padding(.leading, 2)
        }
    }

    // MARK: 书源

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("选择书源")

            if sources.isEmpty {
                Text("没有可用的书源。需要书源启用、启用发现、并填写了发现地址。")
                    .appFont(.system(size: 12))
                    .foregroundStyle(palette.secondary)
            } else {
                Menu {
                    ForEach(sources) { source in
                        Button {
                            switchSource(source)
                        } label: {
                            if sourceUrl == source.bookSourceUrl {
                                Label(source.bookSourceName, systemImage: "checkmark")
                            } else {
                                Text(source.bookSourceName)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "square.stack.3d.up")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(palette.accent)
                        Text(selectedSource?.bookSourceName ?? "点这里选书源")
                            .appFont(.system(size: 15, weight: selectedSource == nil ? .regular : .semibold))
                            .foregroundStyle(selectedSource == nil ? palette.secondary : palette.primary)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.secondary)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 48)
                    .background {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(palette.primary.opacity(0.045))
                    }
                }
                .accessibilityIdentifier("add.sourceMenu")
            }
        }
    }

    // MARK: 筛选（书源自己的控件）

    /// 书源发现规则里的控件：性别 / 模式 / 源站 / 晋江标签 这类下拉，
    /// 关键词输入，以及搜索 / 刷新 / 登录按钮。改一个就执行它的 action
    /// 再重读分类，下面的网格会跟着换一批。
    private var controlSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !controls.isEmpty {
                HStack(spacing: 6) {
                    sectionTitle("筛选")
                    if applyingControl {
                        ProgressView().controlSize(.mini)
                    }
                    Spacer(minLength: 0)
                }

                VStack(spacing: 0) {
                    ForEach(Array(rowControls.enumerated()), id: \.offset) { pair in
                        controlRow(pair.element)
                        if pair.offset < rowControls.count - 1 {
                            Divider().opacity(0.35).padding(.leading, 14)
                        }
                    }
                }
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(palette.primary.opacity(0.028))
                }
                .disabled(applyingControl)

                if let controlNote {
                    Text(controlNote)
                        .appFont(.system(size: 11.5))
                        .foregroundStyle(palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 2)
                }
            }
        }
    }

    /// 行里依次排：下拉、输入、按钮（按钮放最后，和参考图一致）。
    private var rowControls: [SourceDiagnostics.ExploreKind] {
        controls.selects + controls.texts + controls.buttons
    }

    @ViewBuilder private func controlRow(_ control: SourceDiagnostics.ExploreKind) -> some View {
        let type = (control.type ?? "").lowercased()
        if type == "button" {
            SourceControlRow(control: control,
                             value: .constant(""),
                             onChange: { _ in },
                             onTap: { runButton(control) },
                             disabled: applyingControl)
                .padding(.horizontal, 14)
                .frame(minHeight: 46)
        } else {
            SourceControlRow(control: control,
                             value: Binding(
                                get: { controls.values[control.title] ?? "" },
                                set: { controls.values[control.title] = $0 }
                             ),
                             onChange: { newValue in runControl(control, value: newValue) },
                             disabled: applyingControl)
                .padding(.horizontal, 14)
                .frame(minHeight: 46)
        }
    }

    /// 下拉/输入变化：执行 action，再重读分类。
    private func runControl(_ control: SourceDiagnostics.ExploreKind, value: String) {
        guard let source = selectedSource, !applyingControl else { return }
        controls.values[control.title] = value
        applyingControl = true
        let previousKinds = kinds
        // 闭包里只带值类型，别把整个 View 拖进 detached 任务
        let snapshot = controls.values
        Task {
            let ui = await Task.detached(priority: .userInitiated) {
                SourceControlSet.apply(control, value: value, allValues: snapshot, source: source)
            }.value
            if let ui { handle(ui) }
            await loadKinds(force: true, keepSelection: true)
            // 书源脚本有可能忽略这次改动（例如书山聚合只按「源站」切分类，
            // 单独改「模式」不会换分类）。分类一条没变时说清楚，别让人以为没生效。
            if kinds == previousKinds {
                controlNote = "「\(DiscoverCatalog.controlTitle(control.title))」已记为 \(value)，但这个书源的分类没有因此变化——它的脚本可能只在某些组合下才换分类。"
            } else {
                controlNote = nil
            }
            applyingControl = false
        }
    }

    /// 按钮：搜索用当前关键词，其它按钮执行自己的 action。
    private func runButton(_ control: SourceDiagnostics.ExploreKind) {
        guard let source = selectedSource, !applyingControl else { return }
        applyingControl = true
        let keyword = controls.keyword
        let snapshot = controls.values
        Task {
            let ui = await Task.detached(priority: .userInitiated) {
                SourceControlSet.apply(control, value: keyword, allValues: snapshot, source: source)
            }.value
            if let ui { handle(ui) }
            if !SourceControlSet.isRefreshOnly(control) {
                await loadKinds(force: true, keepSelection: true)
            }
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

    // MARK: 分类

    /// 分类网格的列数：手机上三列最紧凑又不挤，「都市人生」这种四个字一行放得下。
    private var kindColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)
    }

    private var kindSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                sectionTitle("选择分类")
                if kindsLoading {
                    ProgressView().controlSize(.mini)
                        .transition(.opacity)
                }
                Spacer(minLength: 0)
                if !picked.isEmpty {
                    HStack(spacing: 6) {
                        Text("已选 \(picked.count)")
                            .appFont(.system(size: 11.5))
                            .foregroundStyle(palette.accent)
                        Button("清空") {
                            withAnimation(.easeInOut(duration: 0.15)) { picked.removeAll() }
                        }
                        .appFont(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(palette.secondary)
                    }
                }
            }

            if sourceUrl.isEmpty {
                hintRow("先选一个书源")
            } else if let kindsError {
                VStack(alignment: .leading, spacing: 8) {
                    Text(kindsError)
                        .appFont(.system(size: 12))
                        .foregroundStyle(palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("重试") { Task { await loadKinds(force: true) } }
                        .appFont(.system(size: 12, weight: .semibold))
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(palette.primary.opacity(0.035))
                }
            } else if selectableKinds.isEmpty && !kindsLoading {
                hintRow("这个书源没有可用的发现分类")
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    if kindsLoading && selectableKinds.isEmpty {
                        LazyVGrid(columns: kindColumns, spacing: 8) {
                            ForEach(0..<9, id: \.self) { _ in kindCellSkeleton }
                        }
                    } else {
                        ForEach(Array(kindGroups.enumerated()), id: \.offset) { pair in
                            VStack(alignment: .leading, spacing: 8) {
                                if let header = pair.element.header {
                                    Text(header)
                                        .appFont(.system(size: 11.5, weight: .semibold))
                                        .foregroundStyle(palette.secondary)
                                        .padding(.leading, 2)
                                }
                                LazyVGrid(columns: kindColumns, spacing: 8) {
                                    ForEach(pair.element.items, id: \.self) { item in
                                        kindCell(item)
                                    }
                                }
                            }
                        }
                    }
                }
                .opacity(contentVisible ? 1 : 0)
                .animation(.easeOut(duration: 0.22), value: contentVisible)
            }
        }
    }

    /// 网格里的一个分类：整块可点，选中后描边加底色，右上角一个勾。
    private func kindCell(_ item: SourceDiagnostics.ExploreKind) -> some View {
        let url = item.url ?? ""
        let on = picked.contains(url)
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                if on { picked.remove(url) } else { picked.insert(url) }
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                Text(item.title)
                    .appFont(.system(size: 13.5, weight: on ? .semibold : .regular))
                    .foregroundStyle(on ? palette.accent : palette.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .padding(.horizontal, 6)

                if on {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(palette.accent)
                        .padding(4)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .background {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(on ? palette.accent.opacity(0.10) : palette.primary.opacity(0.028))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(on ? palette.accent.opacity(0.55) : Color.clear, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("add.kind.\(item.title)")
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }

    /// 加载占位：和真实格子同高，避免网格跳变。
    private var kindCellSkeleton: some View {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(palette.primary.opacity(0.05))
            .frame(height: 44)
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(palette.primary.opacity(0.07))
                    .frame(width: 44, height: 10)
            }
            .redacted(reason: .placeholder)
    }

    private func hintRow(_ text: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "info.circle")
                .font(.system(size: 12))
            Text(text).appFont(.system(size: 12))
        }
        .foregroundStyle(palette.secondary)
        .padding(.horizontal, 14)
        .frame(height: 44)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(palette.primary.opacity(0.028))
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .appFont(.system(size: 13, weight: .semibold))
            .foregroundStyle(palette.secondary)
    }

    // MARK: 底部添加

    private var addBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(palette.primary.opacity(0.06))
                .frame(height: 0.5)
            Button {
                add()
            } label: {
                Text(addTitle)
                    .appFont(.system(size: 16, weight: .semibold))
                    .foregroundStyle(canAdd ? palette.onAccent : palette.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(canAdd ? palette.accent : palette.primary.opacity(0.07))
                    }
            }
            .buttonStyle(.plain)
            .disabled(!canAdd)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .animation(.easeInOut(duration: 0.18), value: canAdd)
        }
        .background(.ultraThinMaterial)
    }

    private var addTitle: String {
        if template.dataSource == .readingProgress { return "添加「继续阅读」" }
        let n = picked.count
        return n > 0 ? "添加 \(n) 个板块" : "添加"
    }

    // MARK: 动作

    private func switchSource(_ source: BookSource) {
        guard sourceUrl != source.bookSourceUrl else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            sourceUrl = source.bookSourceUrl
            kinds = []
            picked = []
            kindsError = nil
            controls = SourceControlSet()
            contentVisible = false
        }
        Task { await loadKinds(force: true) }
    }

    private func preloadFirstSource() async {
        guard sourceUrl.isEmpty, let first = sources.first else { return }
        sourceUrl = first.bookSourceUrl
        await loadKinds()
    }

    /// 读取书源的发现分类与控件。
    /// - Parameter keepSelection: 改筛选后重读时保留已选分类（书源分类会整组换掉时，
    ///   保留下来的那几条仍然有效），切书源时不保留。
    private func loadKinds(force: Bool = false, keepSelection: Bool = false) async {
        guard let source = selectedSource else { return }
        if !force, !kinds.isEmpty {
            contentVisible = true
            return
        }
        if !keepSelection, let cached = DiscoverKindsCache.cached(source: source.bookSourceUrl), !cached.isEmpty {
            apply(kinds: cached)
            kindsLoading = false
            contentVisible = true
            return
        }
        withAnimation(.easeInOut(duration: 0.15)) { kindsLoading = true }
        kindsError = nil
        defer { kindsLoading = false }

        let result = await Task.detached(priority: .userInitiated) {
            SourceDiagnostics.exploreKinds(source: source)
        }.value

        // 只接受当前书源的结果：快速切源时旧请求可能晚到
        guard sourceUrl == source.bookSourceUrl else { return }
        apply(kinds: result, keepSelection: keepSelection)
        if let err = DiscoverCatalog.kindError(result) {
            kindsError = err
        } else if !result.isEmpty {
            DiscoverKindsCache.store(source: source.bookSourceUrl, kinds: result)
        }
        withAnimation(.easeOut(duration: 0.22)) { contentVisible = true }
    }

    /// 写入分类与控件；已选分类如果在新结果里还在就保留。
    private func apply(kinds result: [SourceDiagnostics.ExploreKind], keepSelection: Bool = false) {
        kinds = result
        let fresh = SourceControlSet(kinds: result)
        if keepSelection {
            // 保留用户刚改过的值（书源脚本重启后可能又把默认值写回来）
            var merged = fresh
            for (key, value) in controls.values where merged.values[key] != nil {
                merged.values[key] = value
            }
            controls = merged
        } else {
            controls = fresh
        }
        guard keepSelection else { return }
        let valid = Set(result.compactMap { kind -> String? in
            guard (kind.type ?? "").isEmpty else { return nil }
            guard let url = kind.url, !url.isEmpty else { return nil }
            return url
        })
        picked = picked.filter { valid.contains($0) }
    }

    private func add() {
        if template.dataSource == .readingProgress {
            onAdd([CustomDiscoverEntry(
                sourceUrl: "",
                sourceName: "书架",
                kindTitle: "继续阅读",
                kindUrl: "history://shelf",
                template: .history,
                count: DiscoverTemplate.template(for: .history).defaultCount
            )])
            dismiss()
            return
        }
        guard let source = selectedSource else { return }
        // 按勾选顺序取，而不是按书源原始顺序——用户先点哪个，标签就排在前面。
        let chosen = selectableKinds.filter { picked.contains($0.url ?? "") }

        // 多分类竖排榜：勾选的多个分类合成**一个**板块（标签页切换），
        // 而不是每个分类各加一个板块。
        if template == .multiRank {
            guard let first = chosen.first else { return }
            let entry = CustomDiscoverEntry(
                sourceUrl: source.bookSourceUrl,
                sourceName: source.bookSourceName,
                kindTitle: first.title,
                kindUrl: first.url ?? "",
                template: .multiRank,
                count: DiscoverTemplate.template(for: .multiRank).defaultCount,
                multiKinds: chosen.map { MultiRankKind(title: $0.title, url: $0.url ?? "") }
            )
            onAdd([entry])
            dismiss()
            return
        }

        let entries = chosen.map { item in
            CustomDiscoverEntry(
                sourceUrl: source.bookSourceUrl,
                sourceName: source.bookSourceName,
                kindTitle: item.title,
                kindUrl: item.url ?? "",
                template: template,
                count: DiscoverTemplate.template(for: template).defaultCount
            )
        }
        guard !entries.isEmpty else { return }
        onAdd(entries)
        dismiss()
    }
}
