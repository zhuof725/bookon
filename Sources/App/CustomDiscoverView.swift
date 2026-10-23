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
    /// 打开编辑页时直接进「添加模板」，而不是先看板块预览。
    @State private var openEditorAdding = false
    /// 左上角按钮：页面管理
    @State private var showPageManager = false
    @State private var selectedBook: Book?
    @State private var fullPage: CustomDiscoverEntry?
    @State private var categoryIndex = 0

    /// 全部读 Store 里预计算好的值，body 不再重复过滤/映射。
    private var categories: [String] { model.categories }

    private var currentCategory: String {
        categories.indices.contains(categoryIndex) ? categories[categoryIndex] : CustomDiscoverConfig.allCategory
    }

    private var sections: [DiscoverSectionModel] {
        model.sectionsByCategory[currentCategory] ?? []
    }

    private var carouselBooks: [Book] { model.carouselBooks }

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background { AppThemeCanvas().ignoresSafeArea() }
        .foregroundStyle(palette.primary)
        .navigationTitle("首页")
        .navigationBarTitleDisplayMode(.inline)
        // 首页的导航栏只用来承载「返回」按钮，自身不显示标题和背景，
        // 让左上角的页面胶囊直接贴在内容上（参考图的形态）。
        .toolbarBackground(.hidden, for: .navigationBar)
        // 左上角的页面按钮直接画在内容上，不走 toolbar。
        // 首页在 TabView 里，而 NavigationStack 包的是整个 TabView，
        // 单个 tab 的 ToolbarItem 在这种结构下不会渲染出来。
        .overlay(alignment: .topLeading) {
            pageSwitchButton
                .padding(.leading, 16)
                .padding(.top, 6)
        }
        // 编辑页改成全屏：板块预览要按真实宽度铺开，sheet 的圆角和留白会打断观感。
        .fullScreenCover(isPresented: $showSettings) {
            CustomDiscoverEditorPage(startAdding: openEditorAdding)
                .environmentObject(store)
                .environmentObject(model)
        }
        .sheet(isPresented: $showPageManager) {
            PageManagerView(onOpenPage: { pageID in
                model.selectPage(pageID)
                // 空页面直接进编辑，能立刻加组件
                if model.pages.currentConfig.isEmpty {
                    openEditorAdding = true
                    showSettings = true
                }
            }, onEditPage: { pageID in
                // 长按「编辑页面」：无论有没有组件都直接进编辑
                model.selectPage(pageID)
                openEditorAdding = false
                showSettings = true
            })
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
            await model.loadCarousel()
            await model.loadInitial()
        }
        // 书架变化（读完一本书、加书、删书）才重算进度，不随滚动触发
        .onChange(of: store.books.count) { _, _ in model.refreshHistoryIfNeeded() }
        .onChange(of: model.revision) { _, _ in
            categoryIndex = min(categoryIndex, max(categories.count - 1, 0))
            Task {
                await model.loadCarousel(force: true)
                await model.loadInitial()
            }
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
            guard categoryIndex != index else { return }
            categoryIndex = index
            // 只加载当前分类的前几个，别一次性把所有分类都拉一遍
            Task { await model.loadCategory(title) }
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
                    // 顶部轮播：用配置里选的模板渲染，内容是该分类下的书
                    if !carouselBooks.isEmpty {
                        carouselBlock
                            .padding(.bottom, 16)
                    }
                    // 分类胶囊条（只在配了多个分类时出现）
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
            .refreshable { await model.refresh(category: currentCategory); await model.loadCarousel(force: true) }
            // 悬浮的页面胶囊浮在内容之上，滚动时内容会从它下面穿过，
            // 这里只在顶部留一条窄边距，不整块挤占。
            .contentMargins(.top, 44, for: .scrollContent)
        }
    }

    /// 左上角：当前页面的图标 + 名字，点开「页面管理」。
    private var pageSwitchButton: some View {
        Button {
            showPageManager = true
        } label: {
            HStack(spacing: 7) {
                PageIconView(page: model.pages.current, size: 15, corner: 4)
                Text(model.pages.current.name)
                    .appFont(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.primary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 11)
            .frame(height: 34)
            // 玻璃胶囊：和底栏、卡片用同一套主题玻璃，
            // 首页内容是滚动的，胶囊浮在上面必须透出一点底下的颜色才像玻璃。
            .modifier(ShelfGlass(shape: Capsule(), isCard: true))
            .overlay {
                Capsule().strokeBorder(palette.primary.opacity(0.10), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.pageSwitch")
        .accessibilityLabel("页面管理：\(model.pages.current.name)")
    }

    /// 顶部轮播：把「轮播数据源」当成一个板块，用它选的模板画。
    ///
    /// 这样轮播不再是固定的大图横滑——选「大型阅读卡片」就是一排白卡，
    /// 选「横滑封面」就是一行大封面，和其他栏目用的是同一套版式。
    private var carouselBlock: some View {
        DiscoverTemplateView(
            kind: model.config.effectiveCarouselTemplate,
            title: "",
            moreTitle: "",
            books: carouselBooks,
            count: min(carouselBooks.count, DiscoverTemplate.countCeiling),
            onMore: nil,
            onSelectBook: { selectedBook = $0 }
        )
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
                cards: section.cards,
                count: section.count,
                scale: section.entry.scale,
                corner: section.entry.corner,
                showNumber: section.entry.showNumber,
                onMore: { fullPage = section.entry },
                onSelectBook: { book in selectedBook = book },
                // 卡片类模板靠它记住滑到第几张
                identity: DeckIdentity(sourceUrl: section.entry.sourceUrl,
                                       kindUrl: section.entry.kindUrl),
                // 多分类竖排榜：勾选的分类 + 拉数据用的书源
                multiKinds: section.entry.multiKinds,
                source: store.source(for: section.entry.sourceUrl)
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

    /// 空首页：四宫格图标 + 标题 + 说明 + 胶囊按钮，整块垂直居中。
    private var emptyState: some View {
        VStack(spacing: 0) {
            // 2×2 圆角方块组成的占位图标
            VStack(spacing: 7) {
                ForEach(0..<2, id: \.self) { row in
                    HStack(spacing: 7) {
                        ForEach(0..<2, id: \.self) { col in
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(palette.secondary.opacity(0.42))
                                .frame(width: 27, height: 27)
                        }
                    }
                }
            }
            .padding(.bottom, 24)

            Text("还没有配置首页")
                .appFont(.system(size: 20, weight: .bold))
                .foregroundStyle(palette.primary)
                .padding(.bottom, 10)

            Text("从书源的发现分类里挑几个板块，各选一个模板，再起个标题。")
                .appFont(.system(size: 13))
                .foregroundStyle(palette.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 44)

            Button {
                openEditorAdding = true
                showSettings = true
            } label: {
                Text("开始配置")
                    .appFont(.system(size: 16, weight: .semibold))
                    .foregroundStyle(palette.onAccent)
                    .padding(.horizontal, 34)
                    .frame(height: 44)
                    .background(palette.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 26)
            .accessibilityIdentifier("home.startConfig")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 40)          // 视觉重心略高于正中，和参考图一致
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
                onSelectBook: { selectedBook = $0 },
                multiKinds: entry.multiKinds,
                source: store.source(for: entry.sourceUrl)
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
