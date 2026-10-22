import SwiftUI

/// 添加板块：**先选模块（模板），再选书源和分类**。
///
/// 顺序反过来是有道理的——用户心里先有「我要一个长什么样的板块」，
/// 再去决定用哪个源的内容喂它。选完模板后，下面的分类列表会按模板的
/// 数据来源过滤（「继续阅读」不吃书源，直接跳过第二步）。
struct CustomDiscoverPicker: View {
    @ThemePalette private var palette
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    var onConfirm: ([CustomDiscoverEntry]) -> Void

    /// 第一步选的模板
    @State private var template: DiscoverTemplateKind?
    /// 第二步：书源 / 分类
    @State private var selectedSource: BookSource?
    @State private var kinds: [SourceDiagnostics.ExploreKind] = []
    @State private var loading = false
    @State private var errorText: String?
    @State private var picked: Set<String> = []
    /// 已勾选的条目跨书源保留：可以一次从多个源里挑分类
    @State private var staged: [CustomDiscoverEntry] = []

    private var sources: [BookSource] {
        DiscoverCatalog.explorableSources(store.sources)
    }

    private var selectableKinds: [SourceDiagnostics.ExploreKind] {
        kinds.filter { kind in
            guard (kind.type ?? "").isEmpty else { return false }
            guard let url = kind.url, !url.isEmpty else { return false }
            return !DiscoverCatalog.isDecorativeControlTitle(kind.title)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let template {
                    if template.dataSource == .readingProgress {
                        progressOnlyPage(template)
                    } else if let source = selectedSource {
                        kindList(source, template: template)
                    } else {
                        sourceList(template)
                    }
                } else {
                    templateList
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(confirmTitle) { confirm() }
                        .fontWeight(.semibold)
                        .disabled(!staged.isEmpty ? false : picked.isEmpty && template == nil)
                }
                if template != nil {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            if selectedSource != nil {
                                selectedSource = nil
                                kinds = []
                                picked = []
                            } else {
                                template = nil
                                picked = []
                            }
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                    }
                }
            }
        }
        .background { AppThemeCanvas().ignoresSafeArea() }
    }

    private var navigationTitle: String {
        if let template {
            if template.dataSource == .readingProgress { return template.title }
            return selectedSource?.bookSourceName ?? "选择书源"
        }
        return "选择模块"
    }

    private var confirmTitle: String {
        let total = staged.count + picked.count
        return total > 0 ? "添加 \(total) 个" : "完成"
    }

    // MARK: 第一步：模板

    private var templateList: some View {
        List {
            Section {
                ForEach(DiscoverTemplate.all) { item in
                    Button {
                        template = item.kind
                    } label: {
                        HStack(spacing: 11) {
                            Image(systemName: DiscoverTemplateIcon.symbol(item.kind))
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(palette.accent)
                                .frame(width: 26)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title).appFont(.headline)
                                Text(item.detail)
                                    .appFont(.caption)
                                    .foregroundStyle(palette.secondary)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(palette.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("picker.template.\(item.kind.rawValue)")
                }
            } header: {
                Text("先选板式")
            } footer: {
                Text("选完再挑书源和分类。不同模板吃的数据不一样，「继续阅读」读书架进度，不用选书源。")
            }
        }
        .scrollContentBackground(.hidden)
        .foregroundStyle(palette.primary)
        .background { AppThemeCanvas().ignoresSafeArea() }
    }

    // MARK: 「继续阅读」不需要书源

    private func progressOnlyPage(_ kind: DiscoverTemplateKind) -> some View {
        List {
            Section {
                Text("这个模板读取书架里每本书的阅读进度，不需要书源。")
                    .appFont(.footnote)
                    .foregroundStyle(palette.secondary)
                Button("添加「继续阅读」板块") {
                    staged = [CustomDiscoverEntry(
                        sourceUrl: "",
                        sourceName: "书架",
                        kindTitle: "继续阅读",
                        kindUrl: "history://shelf",
                        template: .history,
                        count: DiscoverTemplate.template(for: .history).defaultCount
                    )]
                    onConfirm(staged)
                }
                .appFont(.body.weight(.semibold))
            }
        }
        .scrollContentBackground(.hidden)
        .foregroundStyle(palette.primary)
        .background { AppThemeCanvas().ignoresSafeArea() }
    }

    // MARK: 第二步：书源

    private func sourceList(_ kind: DiscoverTemplateKind) -> some View {
        List {
            if !staged.isEmpty {
                Section {
                    ForEach(staged) { entry in
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(palette.accent)
                            Text(entry.boardTitle).lineLimit(1)
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets.sorted(by: >) where staged.indices.contains(index) {
                            staged.remove(at: index)
                        }
                    }
                } header: {
                    Text("已选 \(staged.count) 个")
                }
            }

            Section {
                if sources.isEmpty {
                    Text("没有可用的书源。需要书源启用、启用发现、并填写了发现地址。")
                        .appFont(.footnote)
                        .foregroundStyle(palette.secondary)
                } else {
                    ForEach(sources) { source in
                        Button { open(source) } label: {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(source.bookSourceName).appFont(.headline).lineLimit(1)
                                    Text(DiscoverCatalog.cardSubtitle(source))
                                        .appFont(.caption)
                                        .foregroundStyle(palette.secondary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(palette.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                Text("选书源")
            }
        }
        .scrollContentBackground(.hidden)
        .foregroundStyle(palette.primary)
        .background { AppThemeCanvas().ignoresSafeArea() }
    }

    // MARK: 第三步：分类

    private func kindList(_ source: BookSource, template kind: DiscoverTemplateKind) -> some View {
        List {
            if loading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在读取发现分类…").appFont(.footnote).foregroundStyle(palette.secondary)
                }
            } else if let errorText {
                VStack(alignment: .leading, spacing: 6) {
                    Text(errorText).appFont(.footnote).foregroundStyle(palette.secondary)
                    Button("重试") { Task { await load(source) } }
                        .appFont(.footnote.weight(.semibold))
                }
            } else if selectableKinds.isEmpty {
                Text("这个书源没有可用的发现分类。")
                    .appFont(.footnote)
                    .foregroundStyle(palette.secondary)
            } else {
                Section {
                    ForEach(selectableKinds, id: \.self) { item in
                        Button {
                            let url = item.url ?? ""
                            if picked.contains(url) { picked.remove(url) } else { picked.insert(url) }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: picked.contains(item.url ?? "") ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 17))
                                    .foregroundStyle(picked.contains(item.url ?? "") ? palette.accent
                                                     : palette.secondary.opacity(0.4))
                                Text(item.title).appFont(.body).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 1)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("用「\(kind.title)」渲染这些分类")
                }

                if !picked.isEmpty {
                    Section {
                        Button("先记下这 \(picked.count) 个，再选别的书源") {
                            stageCurrent(source: source, template: kind)
                        }
                        .appFont(.body.weight(.semibold))
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .foregroundStyle(palette.primary)
        .background { AppThemeCanvas().ignoresSafeArea() }
        .task(id: source.bookSourceUrl) { await load(source) }
    }

    // MARK: 动作

    private func open(_ source: BookSource) {
        selectedSource = source
        picked = []
        Task { await load(source) }
    }

    private func load(_ source: BookSource) async {
        if !kinds.isEmpty { return }
        loading = true
        errorText = nil
        if let cached = DiscoverKindsCache.cached(source: source.bookSourceUrl) {
            kinds = cached
            loading = false
            return
        }
        let result = await Task.detached(priority: .userInitiated) {
            SourceDiagnostics.exploreKinds(source: source)
        }.value
        kinds = result
        loading = false
        if let err = DiscoverCatalog.kindError(result) {
            errorText = err
        } else if !result.isEmpty {
            DiscoverKindsCache.store(source: source.bookSourceUrl, kinds: result)
        }
    }

    /// 把当前书源勾的分类暂存起来，清空选择以便接着挑别的源。
    private func stageCurrent(source: BookSource, template kind: DiscoverTemplateKind) {
        staged += makeEntries(source: source, template: kind)
        picked = []
        selectedSource = nil
        kinds = []
    }

    private func makeEntries(source: BookSource, template kind: DiscoverTemplateKind) -> [CustomDiscoverEntry] {
        selectableKinds
            .filter { picked.contains($0.url ?? "") }
            .map { item in
                CustomDiscoverEntry(
                    sourceUrl: source.bookSourceUrl,
                    sourceName: source.bookSourceName,
                    kindTitle: item.title,
                    kindUrl: item.url ?? "",
                    template: kind,
                    count: DiscoverTemplate.template(for: kind).defaultCount
                )
            }
    }

    private func confirm() {
        guard let template else { dismiss(); return }
        var all = staged
        if let source = selectedSource, !picked.isEmpty {
            all += makeEntries(source: source, template: template)
        }
        if !all.isEmpty { onConfirm(all) }
        dismiss()
    }
}
