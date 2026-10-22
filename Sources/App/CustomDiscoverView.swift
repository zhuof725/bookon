import SwiftUI

/// 首页：顶部分类（轮播）+ 按配置渲染的板块流。
///
/// 三条约束都体现在这里：
/// 1. 顶部不是书源轮播，而是配置里的「分类」，每个分类一屏板块；
/// 2. 页面本身就是一个 Tab（底栏的「首页」）；
/// 3. 每条板块按自己的模板渲染，外观参数由配置决定。
struct CustomDiscoverView: View {
    @ThemePalette private var palette
    @EnvironmentObject private var store: AppStore
    @ObservedObject private var model = DiscoverBoardStore.shared

    @State private var showSettings = false
    @State private var selectedBook: Book?
    @State private var fullPage: CustomDiscoverEntry?
    @State private var categoryIndex = 0

    private var categories: [String] { model.visibleCategories }

    private var currentCategory: String {
        categories.indices.contains(categoryIndex) ? categories[categoryIndex] : CustomDiscoverConfig.allCategory
    }

    private var sections: [DiscoverSectionModel] {
        model.sections(inCategory: currentCategory)
    }

    /// 轮播页：与分类同序，切轮播也会切分类。
    private var heroes: [CustomDiscoverHero] { model.carouselHeroes }

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background { AppThemeCanvas().ignoresSafeArea() }
        .foregroundStyle(palette.primary)
        .navigationTitle("首页")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSettings = true } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 15, weight: .semibold))
                }
                .accessibilityIdentifier("customdiscover.settings")
            }
        }
        .sheet(isPresented: $showSettings) {
            CustomDiscoverSettingsView()
                .environmentObject(store)
                .environmentObject(model)
        }
        .navigationDestination(item: $selectedBook) { book in
            BookDetailView(book: book)
        }
        .navigationDestination(item: $fullPage) { entry in
            CustomDiscoverFullPage(entry: entry)
                .environmentObject(store)
                .environmentObject(model)
        }
        .task {
            if model.isEmpty { model.reloadConfig() }
            await model.loadInitial()
        }
        .onChange(of: model.revision) { _, _ in
            // 配置变了，分类可能变少：把索引拉回范围内
            categoryIndex = min(categoryIndex, max(categories.count - 1, 0))
            Task { await model.loadInitial() }
        }
        .accessibilityIdentifier("customdiscover.page")
    }

    // MARK: 分类胶囊条

    private var categoryBar: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(categories.enumerated()), id: \.offset) { pair in
                        categoryChip(title: pair.element, index: pair.offset)
                            .id(pair.offset)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
            }
            .onChange(of: categoryIndex) { _, value in
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(value, anchor: .center)
                }
            }
        }
    }

    private func categoryChip(title: String, index: Int) -> some View {
        let selected = index == categoryIndex
        return Button {
            categoryIndex = index
        } label: {
            Text(title)
                .appFont(.system(size: 14, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? palette.onAccent : palette.primary)
                .padding(.horizontal, 14)
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
        .accessibilityIdentifier("home.category.\(title)")
    }

    // MARK: 内容

    @ViewBuilder private var content: some View {
        if model.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    // 顶部轮播：每个分类一屏，滑动即切分类
                    if !heroes.isEmpty {
                        CustomDiscoverCarousel(pages: heroes, index: $categoryIndex)
                            .padding(.bottom, 14)
                    }
                    // 分类胶囊条（轮播的辅助指示，点它也能切）
                    if categories.count > 1 {
                        categoryBar
                            .padding(.bottom, 4)
                    }
                    ForEach(sections) { section in
                        sectionBlock(section)
                    }
                    if sections.isEmpty {
                        Text("这个分类下还没有板块")
                            .appFont(.footnote)
                            .foregroundStyle(palette.secondary)
                            .padding(20)
                    }
                }
                .padding(.bottom, 28)
            }
            .refreshable { await model.refresh() }
        }
    }

    @ViewBuilder private func sectionBlock(_ section: DiscoverSectionModel) -> some View {
        if section.kind == .history {
            DiscoverTemplateView(
                kind: .history,
                title: section.title,
                moreTitle: "全部",
                history: model.historyItems,
                count: section.count,
                onMore: { fullPage = section.entry },
                onSelectHistory: { item in
                    selectedBook = store.books.first { $0.bookUrl == item.id }
                }
            )
        } else if section.failed {
            failedRow(section)
        } else if section.books.isEmpty && section.loading {
            loadingRow(section)
        } else {
            DiscoverTemplateView(
                kind: section.kind,
                title: section.title,
                moreTitle: "全部",
                books: section.books,
                count: section.count,
                scale: section.entry.scale,
                corner: section.entry.corner,
                showNumber: section.entry.showNumber,
                onMore: { fullPage = section.entry },
                onSelectBook: { book in selectedBook = book }
            )
            .task { await model.load(section) }
        }
    }

    private func loadingRow(_ section: DiscoverSectionModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header(section.title)
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("加载中…")
                    .appFont(.system(size: 12))
                    .foregroundStyle(palette.secondary)
            }
            .frame(height: 60)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 18)
    }

    private func failedRow(_ section: DiscoverSectionModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header(section.title)
            HStack(spacing: 10) {
                Text(section.errorText ?? "加载失败")
                    .appFont(.system(size: 12))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(2)
                Button("重试") { Task { await model.load(section, force: true) } }
                    .appFont(.system(size: 12, weight: .semibold))
            }
            .frame(height: 60)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 18)
    }

    private func header(_ title: String) -> some View {
        HStack {
            Text(title)
                .appFont(.system(size: 20, weight: .bold))
                .foregroundStyle(palette.primary)
            Spacer()
        }
    }

    private var emptyState: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 9) {
                Text("还没有配置首页").appFont(.headline)
                Text("点右上角，从书源发现分类里挑几条板块，各选一个模板，加上自己的分类标题。")
                    .appFont(.footnote)
                    .foregroundStyle(palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("开始配置") { showSettings = true }
                    .appFont(.footnote.weight(.semibold))
                    .padding(.top, 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
    }
}

// MARK: - 全部内容页

/// 「全部」：同一条板块，不限数量。
struct CustomDiscoverFullPage: View {
    @ThemePalette private var palette
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var model: DiscoverBoardStore
    let entry: CustomDiscoverEntry
    @State private var selectedBook: Book?
    @State private var extra: [Book] = []
    @State private var loadingMore = false
    @State private var noMore = false
    @State private var page = 1

    private var loaded: [Book] {
        let base = model.sections.first { $0.id == entry.id }?.books ?? []
        return base + extra
    }

    private var supportsMore: Bool { entry.kindUrl.contains("{{page}}") }

    var body: some View {
        ScrollView {
            DiscoverTemplateView(
                kind: entry.template,
                title: "",
                moreTitle: "",
                books: loaded,
                history: model.historyItems,
                count: DiscoverTemplate.unlimited,
                scale: entry.scale,
                corner: entry.corner,
                showNumber: entry.showNumber,
                onSelectBook: { selectedBook = $0 }
            )
            .padding(.top, 8)

            if supportsMore {
                Group {
                    if loadingMore {
                        ProgressView().padding(.vertical, 14)
                    } else if noMore {
                        Text("没有更多了")
                            .appFont(.system(size: 12))
                            .foregroundStyle(palette.secondary)
                            .padding(.vertical, 14)
                    } else {
                        Button("加载更多") { Task { await loadNext() } }
                            .appFont(.system(size: 13, weight: .semibold))
                            .padding(.vertical, 14)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .background { AppThemeCanvas().ignoresSafeArea() }
        .foregroundStyle(palette.primary)
        .navigationTitle(entry.boardTitle)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedBook) { book in
            BookDetailView(book: book)
        }
        .accessibilityIdentifier("customdiscover.full")
    }

    private func loadNext() async {
        guard let source = store.source(for: entry.sourceUrl) else { return }
        loadingMore = true
        defer { loadingMore = false }
        do {
            let next = page + 1
            let list = try await SourceDiagnostics.explore(source: source, url: entry.kindUrl, page: next)
            let known = Set(loaded.map(\.bookUrl))
            let fresh = list.filter { !known.contains($0.bookUrl) }
            page = next
            if fresh.isEmpty { noMore = true } else { extra += fresh }
        } catch {
            noMore = true
        }
    }
}
