import SwiftUI

/// 添加 / 编辑一个探索板块。
struct ExploreBoardEditor: View {
    @ThemePalette private var palette
    @EnvironmentObject private var appStore: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var draft: ExploreBoard
    @State private var isNew: Bool
    @State private var splitByCategory = false
    @State private var tagsText: String
    @State private var showSourcePicker = false

    private let onSave: ([ExploreBoard]) -> Void

    init(board: ExploreBoard?, onSave: @escaping ([ExploreBoard]) -> Void) {
        let value = board ?? ExploreBoard()
        _draft = State(initialValue: value)
        _isNew = State(initialValue: board == nil)
        _tagsText = State(initialValue: ExploreFormat.tagText(value.tags))
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            List {
                Section("标题") {
                    TextField("留空则跟随分类名", text: $draft.title)
                        .appFont(.body)
                        .accessibilityIdentifier("explore.editor.title")
                }

                Section {
                    ForEach(ExploreLayout.allCases) { layout in
                        layoutRow(layout)
                    }
                } header: {
                    Text("版式")
                } footer: {
                    Text("带顶部标签的版式会把「分类」里的第 2 个起显示成标签；其它版式只用第一个分类。")
                        .appFont(.caption)
                }

                Section {
                    ForEach(draft.categories) { category in
                        categoryRow(category)
                    }
                    .onDelete { draft.categories.remove(atOffsets: $0) }
                    Button {
                        showSourcePicker = true
                    } label: {
                        Label("添加分类", systemImage: "plus.circle")
                            .appFont(.body)
                    }
                    .accessibilityIdentifier("explore.editor.addCategory")
                } header: {
                    Text("分类")
                } footer: {
                    Text(draft.categories.isEmpty ? "至少选一个书源发现分类。" : "左滑删除；第一个分类是卡片主内容。")
                        .appFont(.caption)
                }

                Section("显示") {
                    Stepper(value: $draft.count, in: 1...30) {
                        Text("显示 \(draft.count) 本").appFont(.body)
                    }
                    if draft.layout.usesSubtitle {
                        TextField(draft.layout.placeholderSubtitle ?? "副标题", text: $draft.subtitle)
                            .appFont(.body)
                    }
                    TextField("标签，用逗号分隔（AI 未接入时的兜底）", text: $tagsText)
                        .appFont(.body)
                    if draft.layout == .forYou, !draft.hiddenBookURLs.isEmpty {
                        Button {
                            draft.hiddenBookURLs.removeAll()
                        } label: {
                            Text("恢复 \(draft.hiddenBookURLs.count) 本被隐藏的书")
                                .appFont(.body)
                        }
                    }
                }

                if isNew {
                    Section {
                        Toggle("每个分类各建一个板块", isOn: $splitByCategory)
                            .appFont(.body)
                    } footer: {
                        Text("打开后按分类名自动挑版式，一次把选中的分类铺成一整页卡片。")
                            .appFont(.caption)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background { AppThemeCanvas().ignoresSafeArea() }
            .navigationTitle(isNew ? "添加板块" : "编辑板块")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(draft.visibleCategories.isEmpty)
                        .accessibilityIdentifier("explore.editor.save")
                }
            }
            .sheet(isPresented: $showSourcePicker) {
                ExploreSourcePicker { categories in
                    for category in categories where !draft.categories.contains(where: { $0.id == category.id }) {
                        draft.categories.append(category)
                    }
                    if draft.count < 1 { draft.count = draft.layout.defaultCount }
                }
                .environmentObject(appStore)
            }
        }
        .accessibilityIdentifier("explore.editor.page")
    }

    private func layoutRow(_ layout: ExploreLayout) -> some View {
        Button {
            select(layout)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: layout.symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(palette.secondary)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(layout.title)
                        .appFont(.system(size: 15, weight: .medium))
                        .foregroundStyle(palette.primary)
                    Text(layout.detail)
                        .appFont(.system(size: 11.5))
                        .foregroundStyle(palette.secondary)
                }
                Spacer(minLength: 6)
                if draft.layout == layout {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.accent)
                }
            }
            .contentShape(Rectangle())
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("explore.editor.layout.\(layout.rawValue)")
    }

    private func categoryRow(_ category: ExploreCategory) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(category.title)
                    .appFont(.system(size: 15))
                    .foregroundStyle(palette.primary)
                    .lineLimit(1)
                Text(appStore.source(for: category.sourceURL)?.bookSourceName ?? "书源已删除")
                    .appFont(.system(size: 11.5))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            if draft.categories.first?.id == category.id {
                Text("主")
                    .appFont(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background { Capsule().fill(palette.selection.opacity(0.55)) }
            }
        }
    }

    /// 换版式时，数量如果还是旧版式的默认值，就跟着换成新版式的默认值。
    private func select(_ layout: ExploreLayout) {
        let wasDefault = draft.count == draft.layout.defaultCount
        draft.layout = layout
        if wasDefault { draft.count = layout.defaultCount }
    }

    private func save() {
        var board = draft
        board.title = board.title.trimmingCharacters(in: .whitespacesAndNewlines)
        board.subtitle = board.subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        board.tags = ExploreFormat.tags(tagsText)
        board.categories = board.visibleCategories
        // 新建的板块永远拿一个新 id：编辑页被重复呈现时不会和上一张撞 id。
        if isNew { board.id = UUID().uuidString }
        if isNew, splitByCategory {
            let boards = board.categories.map { category -> ExploreBoard in
                let layout = ExploreLayout.suggested(forCategory: category.title)
                return ExploreBoard(title: category.title,
                                    layout: layout,
                                    categories: [category],
                                    count: layout.defaultCount,
                                    tags: board.tags)
            }
            onSave(boards)
        } else {
            board.count = min(max(board.count, 1), 30)
            onSave([board])
        }
        dismiss()
    }
}

// MARK: - 选书源

struct ExploreSourcePicker: View {
    @ThemePalette private var palette
    @EnvironmentObject private var appStore: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    let onConfirm: ([ExploreCategory]) -> Void

    private var sources: [BookSource] {
        let all = DiscoverCatalog.explorableSources(appStore.sources)
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return all }
        return all.filter {
            $0.bookSourceName.localizedCaseInsensitiveContains(keyword)
                || $0.bookSourceUrl.localizedCaseInsensitiveContains(keyword)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if sources.isEmpty {
                    Text("没有可用于发现的书源。先在「我的 → 书源管理」里给书源填发现地址。")
                        .appFont(.footnote)
                        .foregroundStyle(palette.secondary)
                        .independentGlassRow()
                } else {
                    ForEach(sources) { source in
                        NavigationLink {
                            ExploreCategoryPicker(source: source,
                                                  onConfirm: { categories in
                                onConfirm(categories)
                                dismiss()
                            })
                        } label: {
                            sourceRow(source)
                        }
                        .independentGlassRow()
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background { AppThemeCanvas().ignoresSafeArea() }
            .navigationTitle("选择书源")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "搜索书源")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
        .accessibilityIdentifier("explore.sourcePicker")
    }

    private func sourceRow(_ source: BookSource) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "books.vertical")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(palette.secondary)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(source.bookSourceName)
                    .appFont(.system(size: 16, weight: .medium))
                    .foregroundStyle(palette.primary)
                    .lineLimit(1)
                Text(DiscoverCatalog.displayDomain(source.bookSourceUrl))
                    .appFont(.system(size: 11.5))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }
}

// MARK: - 选分类（多选）

struct ExploreCategoryPicker: View {
    @ThemePalette private var palette
    @Environment(\.dismiss) private var dismiss

    let source: BookSource
    let onConfirm: ([ExploreCategory]) -> Void

    @State private var categories: [ExploreCategory] = []
    @State private var selected: Set<String> = []
    @State private var loading = true
    @State private var errorText: String?

    var body: some View {
        List {
            if loading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在读取书源的发现分类…")
                        .appFont(.footnote)
                        .foregroundStyle(palette.secondary)
                }
                .independentGlassRow()
            } else if let errorText {
                VStack(alignment: .leading, spacing: 8) {
                    Text(errorText)
                        .appFont(.footnote)
                        .foregroundStyle(palette.secondary)
                    Button("重试") { Task { await load(force: true) } }
                        .appFont(.footnote.weight(.semibold))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .independentGlassRow()
            } else if categories.isEmpty {
                Text("这个书源没有可用的发现分类。")
                    .appFont(.footnote)
                    .foregroundStyle(palette.secondary)
                    .independentGlassRow()
            } else {
                ForEach(categories) { category in
                    Button {
                        toggle(category)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: selected.contains(category.id) ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 18))
                                .foregroundStyle(selected.contains(category.id) ? palette.accent : palette.secondary)
                            Text(category.title)
                                .appFont(.system(size: 15))
                                .foregroundStyle(palette.primary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .independentGlassRow()
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background { AppThemeCanvas().ignoresSafeArea() }
        .navigationTitle(source.bookSourceName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if !categories.isEmpty {
                    Button(selected.count == categories.count ? "清空" : "全选") {
                        if selected.count == categories.count {
                            selected.removeAll()
                        } else {
                            selected = Set(categories.map(\.id))
                        }
                    }
                    .appFont(.footnote)
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("添加 \(selected.count) 个") {
                    let picked = categories.filter { selected.contains($0.id) }
                    onConfirm(picked)
                    dismiss()
                }
                .disabled(selected.isEmpty)
            }
        }
        .task { await load() }
        .accessibilityIdentifier("explore.categoryPicker")
    }

    private func toggle(_ category: ExploreCategory) {
        if selected.contains(category.id) {
            selected.remove(category.id)
        } else {
            selected.insert(category.id)
        }
    }

    private func load(force: Bool = false) async {
        if !force, let cached = DiscoverKindsCache.cached(source: source.bookSourceUrl), !cached.isEmpty {
            apply(cached)
            return
        }
        loading = true
        errorText = nil
        let src = source
        let result = await Task.detached(priority: .userInitiated) {
            SourceDiagnostics.exploreKinds(source: src)
        }.value
        apply(result)
        if DiscoverCatalog.kindError(result) == nil, !result.isEmpty {
            DiscoverKindsCache.store(source: src.bookSourceUrl, kinds: result)
        }
        loading = false
    }

    private func apply(_ kinds: [SourceDiagnostics.ExploreKind]) {
        if let error = DiscoverCatalog.kindError(kinds) {
            categories = []
            errorText = error
            loading = false
            return
        }
        var built: [ExploreCategory] = []
        var index = 0
        for kind in kinds {
            // 控件（text/button/select）是筛选条，没有地址的项是分节标题，都不是分类。
            guard (kind.type ?? "").isEmpty else { continue }
            guard let url = kind.url?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty else { continue }
            index += 1
            let title = kind.title.trimmingCharacters(in: .whitespacesAndNewlines)
            built.append(ExploreCategory(sourceURL: source.bookSourceUrl,
                                         url: url,
                                         title: title.isEmpty ? "分类 \(index)" : title))
        }
        categories = built
        if selected.isEmpty, let first = built.first {
            selected = [first.id]
        }
        loading = false
    }
}
