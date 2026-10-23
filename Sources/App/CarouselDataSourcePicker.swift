import SwiftUI

/// 轮播数据源：**先选书源，再在书源里选分类**。
///
/// 选中的分类会成为首页顶部轮播的内容——轮播里滑的就是这个分类下的书籍封面。
/// 对应参考图二：顶部「轮播内容」大图预览，下面「数据源」一行显示书源与分类。
struct CarouselDataSourcePicker: View {
    @ThemePalette private var palette
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    @Binding var config: CustomDiscoverConfig

    @State private var selectedSource: BookSource?
    @State private var kinds: [SourceDiagnostics.ExploreKind] = []
    @State private var loading = false
    @State private var errorText: String?
    /// 预览用：选中的分类拉到的前几本
    @State private var previewBooks: [Book] = []
    @State private var previewLoading = false

    private var sources: [BookSource] { DiscoverCatalog.explorableSources(store.sources) }

    private var selectableKinds: [SourceDiagnostics.ExploreKind] {
        kinds.filter { kind in
            guard (kind.type ?? "").isEmpty else { return false }
            guard let url = kind.url, !url.isEmpty else { return false }
            return !DiscoverCatalog.isDecorativeControlTitle(kind.title)
        }
    }

    /// 当前选中的轮播分类（配置里存的）
    private var currentTitle: String {
        guard let source = store.source(for: config.carouselSourceUrl) else { return "" }
        return "\(source.bookSourceName) · \(config.carouselKindTitle)"
    }

    var body: some View {
        NavigationStack {
            Group {
                if let source = selectedSource {
                    kindList(source)
                } else {
                    mainList
                }
            }
            .navigationTitle(selectedSource?.bookSourceName ?? "配置数据来源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                if selectedSource != nil {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            selectedSource = nil
                            kinds = []
                            pickedReset()
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                    }
                }
            }
            .background { AppThemeCanvas().ignoresSafeArea() }
        }
    }

    // MARK: 主页面：轮播内容 + 数据源

    private var mainList: some View {
        List {
            Section {
                // 轮播预览：直接用选中的模板画，看到的就是首页会长的样子
                if !previewBooks.isEmpty {
                    DiscoverTemplateView(
                        kind: config.effectiveCarouselTemplate,
                        title: "",
                        moreTitle: "",
                        books: previewBooks,
                        count: min(previewBooks.count, DiscoverTemplate.countCeiling)
                    )
                    .allowsHitTesting(false)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                } else {
                    HStack {
                        Spacer()
                        VStack(spacing: 7) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.system(size: 26))
                                .foregroundStyle(palette.secondary.opacity(0.5))
                            Text("还没选轮播数据")
                                .appFont(.system(size: 12))
                                .foregroundStyle(palette.secondary)
                        }
                        Spacer()
                    }
                    .frame(height: 160)
                    .listRowBackground(Color.clear)
                }
            } header: {
                Text("轮播内容")
            }

            Section {
                if config.carouselSourceUrl.isEmpty {
                    Text("未选择")
                        .appFont(.footnote)
                        .foregroundStyle(palette.secondary)
                } else {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(currentTitle)
                                .appFont(.system(size: 15, weight: .semibold))
                            Text("轮播显示这个分类里的书籍")
                                .appFont(.caption)
                                .foregroundStyle(palette.secondary)
                        }
                        Spacer()
                        Button("更换") {
                            selectedSource = nil
                        }
                        .appFont(.system(size: 13, weight: .semibold))
                    }
                }
            } header: {
                Text("数据源")
            }

            Section {
                NavigationLink {
                    DiscoverTemplateLibrary(current: config.carouselTemplate,
                                            dismissOnPick: false) { kind in
                        config.carouselTemplate = kind
                    }
                    .environmentObject(store)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("轮播模板").appFont(.system(size: 15, weight: .semibold))
                            Text(config.effectiveCarouselTemplate.title)
                                .appFont(.caption)
                                .foregroundStyle(palette.secondary)
                        }
                        Spacer()
                        Text("展示库")
                            .appFont(.caption.weight(.semibold))
                            .foregroundStyle(palette.accent)
                    }
                }
            } header: {
                Text("模板")
            } footer: {
                Text("轮播不再是固定大图，而是用这个模板渲染你选的分类。")
            }

            Section {
                Toggle("显示轮播图", isOn: Binding(
                    get: { !config.carouselHidden },
                    set: { config.carouselHidden = !$0 }
                ))
                if !config.carouselSourceUrl.isEmpty {
                    Button("清除轮播数据", role: .destructive) {
                        config.carouselSourceUrl = ""
                        config.carouselKindTitle = ""
                        config.carouselKindUrl = ""
                        previewBooks = []
                    }
                }
            } header: {
                Text("选项")
            } footer: {
                Text("关闭后首页顶部不显示轮播，直接进板块列表。")
            }

            Section {
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
            } header: {
                Text("数据源")
            } footer: {
                Text("先选书源，再在书源里选一个分类作为轮播内容。")
            }
        }
        .scrollContentBackground(.hidden)
        .foregroundStyle(palette.primary)
        .task { await loadPreview() }
    }

    private func carouselPreview(_ book: Book) -> some View {
        ZStack(alignment: .bottomLeading) {
            DeckCoverImage(url: BookCoverLocation.url(for: book))
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            LinearGradient(colors: [.clear, .black.opacity(0.72)],
                           startPoint: .center, endPoint: .bottom)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(book.name)
                    .appFont(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                if !book.author.isEmpty {
                    Text(book.author)
                        .appFont(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.82))
                }
            }
            .padding(12)
        }
        .padding(.horizontal, 16)
    }

    // MARK: 二级：分类

    private func kindList(_ source: BookSource) -> some View {
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
                    .appFont(.footnote).foregroundStyle(palette.secondary)
            } else {
                Section {
                    ForEach(selectableKinds, id: \.self) { item in
                        Button {
                            pick(item, source: source)
                        } label: {
                            HStack(spacing: 10) {
                                Text(item.title).appFont(.body).lineLimit(1)
                                Spacer(minLength: 0)
                                if config.carouselKindUrl == (item.url ?? "") {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(palette.accent)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("选择分类")
                } footer: {
                    Text("轮播里会滑动这个分类下的书籍。")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .foregroundStyle(palette.primary)
        .task(id: source.bookSourceUrl) { await load(source) }
    }

    // MARK: 动作

    private func open(_ source: BookSource) {
        selectedSource = source
        Task { await load(source) }
    }

    private func pickedReset() {
        // 只清预览，不动已保存的配置
    }

    private func pick(_ item: SourceDiagnostics.ExploreKind, source: BookSource) {
        config.carouselSourceUrl = source.bookSourceUrl
        config.carouselKindTitle = item.title
        config.carouselKindUrl = item.url ?? ""
        previewBooks = []
        selectedSource = nil
        Task { await loadPreview(force: true) }
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

    private func loadPreview(force: Bool = false) async {
        guard !config.carouselKindUrl.isEmpty,
              let source = store.source(for: config.carouselSourceUrl) else { return }
        if !force, !previewBooks.isEmpty { return }
        if !force,
           let cached = DiscoverBlockCache.cached(source: config.carouselSourceUrl,
                                                  url: config.carouselKindUrl),
           !cached.isEmpty {
            previewBooks = Array(cached.prefix(6))
            return
        }
        previewLoading = true
        defer { previewLoading = false }
        if let list = try? await SourceDiagnostics.explore(source: source, url: config.carouselKindUrl) {
            previewBooks = Array(list.prefix(6))
        }
    }
}
