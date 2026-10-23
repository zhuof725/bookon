import Foundation
import Combine

// MARK: - 一条板块的运行时状态

/// 配置里的条目 + 它当前的书与加载状态。视图只读这个对象。
@MainActor
final class DiscoverSectionModel: ObservableObject, Identifiable {
    @Published private(set) var entry: CustomDiscoverEntry

    @Published private(set) var books: [Book] = []
    @Published private(set) var loading = false
    @Published private(set) var failed = false
    @Published private(set) var errorText: String?

    /// 存成属性而不是计算属性：`Identifiable` 要求能在 main actor 之外读取，
    /// 计算属性会跨 actor 隔离，Swift 6 下是错误。
    let id: String
    var kind: DiscoverTemplateKind { entry.template }
    var title: String { entry.boardTitle }
    var count: Int { entry.count }

    /// 已转好的卡片条目：模板每次刷新都拿这个，避免重复 map/prefix。
    /// `books` 变化时一起更新，视图层就不必在 body 里做转换了。
    @Published private(set) var cards: [DeckItem] = []

    init(entry: CustomDiscoverEntry) {
        self.entry = entry
        self.id = entry.id
    }

    /// 配置改了（标题 / 模板 / 数量），把新值写回，已加载的书保留。
    /// 只在真正变化时才重新生成卡片，避免无谓的重绘。
    func update(entry newEntry: CustomDiscoverEntry) {
        let changed = newEntry != entry
        entry = newEntry
        if changed { rebuildCards() }
    }

    func setBooks(_ list: [Book]) {
        books = list
        failed = false
        errorText = nil
        loading = false
        rebuildCards()
    }

    func setFailed(_ message: String?) {
        failed = true
        errorText = message
        loading = false
    }

    func beginLoading() {
        loading = true
        failed = false
        errorText = nil
    }

    /// 请求被取消：不算失败，只是没拿到结果。
    /// 保留已有的书（刷新失败时不要把上一屏内容清空），退出加载态即可。
    func endLoadingWithoutResult() {
        loading = false
    }

    /// 把书转成卡片，一次算好。数量上限在配置里，这里截断避免模板自己 prefix。
    private func rebuildCards() {
        let limit = entry.count
        let limitCount = limit == DiscoverTemplate.unlimited ? books.count : min(max(limit, 0), books.count)
        cards = books.prefix(limitCount).map { DeckItem(book: $0) }
    }
}

// MARK: - 首页数据源

/// 把「配置 + 书源」变成可渲染的板块。
///
/// 性能上做了三件事：
/// 1. 分类、轮播、可视板块列表都缓存成 @Published 属性，视图 body 里不再重复计算；
/// 2. 书架进度只在「我的」或书架变化时刷新，不在每次排版时读磁盘；
/// 3. 章节数按 bookUrl 缓存在内存，避免每本书都 md5 + 读 JSON。
@MainActor
final class DiscoverBoardStore: ObservableObject {
    static let shared = DiscoverBoardStore()

    @Published private(set) var sections: [DiscoverSectionModel] = []
    /// 刷新代号：每次下拉刷新加一，旧请求回来后据此丢弃结果。
    private var refreshToken: Int = 0
    @Published private(set) var historyItems: [HistoryItem] = []
    @Published private(set) var config = CustomDiscoverConfig()

    /// 全部首页页面 + 当前选中的那一页。
    @Published private(set) var pages = CustomDiscoverPages()

    /// 预计算好，给视图直接用。
    @Published private(set) var categories: [String] = []
    /// 分类名 → 该分类下的板块。切分类时不用再过滤。
    @Published private(set) var sectionsByCategory: [String: [DiscoverSectionModel]] = [:]

    /// 配置变更计数：外部改了配置后 bump，页面据此重建。
    @Published private(set) var revision = 0

    private var loadingIDs: Set<String> = []

    /// 编辑页预览用：草稿里的条目还没保存，不在 sections 里，
    /// 这里单独维护「条目 id → 运行时模型」，让预览也能拉到真实书单。
    @Published private(set) var previewSections: [String: DiscoverSectionModel] = [:]
    /// 章节数缓存：bookUrl → 章数（nil 表示查过但没有目录缓存）
    private var chapterCountCache: [String: Int?] = [:]
    private var appStore: AppStore { AppStore.shared }

    var isEmpty: Bool { sections.isEmpty }

    // MARK: 配置

    func reloadConfig() {
        pages = CustomDiscoverStore.loadPages()
        var current = pages.currentConfig
        current.refreshNames(from: appStore.sources)
        pages.saveCurrentConfig(current)
        config = current
        rebuild()
        revision &+= 1
    }

    /// 保存当前页的配置，并把整份页面表写盘。
    func save(_ next: CustomDiscoverConfig) {
        var updated = next
        updated.refreshNames(from: appStore.sources)
        pages.saveCurrentConfig(updated)
        CustomDiscoverStore.savePages(pages)
        config = updated
        rebuild()
        revision &+= 1
    }

    // MARK: 多页面

    /// 切到某一页。
    func selectPage(_ id: String) {
        guard id != pages.currentID else { return }
        pages.setCurrent(id)
        var current = pages.currentConfig
        current.refreshNames(from: appStore.sources)
        pages.saveCurrentConfig(current)
        CustomDiscoverStore.savePages(pages)
        config = current
        // 切页等于换了一整套板块，把运行时状态清干净再重建
        sections = []
        loadingIDs.removeAll()
        rebuild()
        revision &+= 1
        Task { await loadCarousel(force: true) }
    }

    /// 加一个空白自定义页面并切过去。
    func addPage() {
        let page = pages.addPage()
        config = page.config
        sections = []
        loadingIDs.removeAll()
        CustomDiscoverStore.savePages(pages)
        rebuild()
        revision &+= 1
        Task { await loadCarousel(force: true) }
    }

    func removePage(_ id: String) {
        pages.removePage(id)
        var current = pages.currentConfig
        current.refreshNames(from: appStore.sources)
        pages.saveCurrentConfig(current)
        CustomDiscoverStore.savePages(pages)
        config = current
        sections = []
        loadingIDs.removeAll()
        rebuild()
        revision &+= 1
        Task { await loadCarousel(force: true) }
    }

    /// 改页面本身（名字 / 图标）。
    func renamePage(_ page: CustomDiscoverPage) {
        pages.update(page)
        CustomDiscoverStore.savePages(pages)
        revision &+= 1
    }

    func movePages(fromOffsets source: IndexSet, toOffset destination: Int) {
        pages.move(fromOffsets: source, toOffset: destination)
        CustomDiscoverStore.savePages(pages)
        revision &+= 1
    }

    /// 把某一页挪到最前面（长按菜单「设为首页」），当前页不变。
    func movePageToFront(_ id: String) {
        guard let index = pages.pages.firstIndex(where: { $0.id == id }), index > 0 else { return }
        pages.move(fromOffsets: IndexSet(integer: index), toOffset: 0)
        CustomDiscoverStore.savePages(pages)
        revision &+= 1
    }

    // MARK: 重建

    /// 配置或书源变化后重建列表。已加载的书会复用，不会整页重刷。
    private func rebuild() {
        let entries = config.visibleEntries(from: appStore.sources)
        let existing = Dictionary(sections.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        sections = entries.map { entry in
            if let model = existing[entry.id] {
                model.update(entry: entry)
                return model
            }
            return DiscoverSectionModel(entry: entry)
        }
        recomputeIndex()
        refreshHistoryIfNeeded()
    }

    /// 一次性算好分类、每分类的板块、轮播页。
    private func recomputeIndex() {
        let names = config.effectiveCategories
        if names.isEmpty {
            categories = []
        } else if config.categories.isEmpty {
            categories = [CustomDiscoverConfig.allCategory] + names
        } else {
            categories = names
        }

        // 分类 → 板块：先把条目按分类分组（一次遍历），再按 id 集合筛板块
        let grouped = config.entriesByCategory()
        let byID = Dictionary(sections.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var index: [String: [DiscoverSectionModel]] = [:]
        index.reserveCapacity(categories.count)
        for category in categories {
            guard let list = grouped[category], !list.isEmpty else {
                // 手写了一个匹配不到的分类：退回全量，别让页面空着
                index[category] = sections
                continue
            }
            let models = list.compactMap { byID[$0.id] }
            index[category] = models.isEmpty ? sections : models
        }
        sectionsByCategory = index
    }

    // MARK: 轮播

    /// 顶部轮播：内容来自配置里选定的「书源 + 分类」，滑的是这个分类下的书。
    /// 对应参考图二：先选书源，再选分类。没配或关掉时为空。
    @Published private(set) var carouselBooks: [Book] = []

    private var carouselLoading = false

    func loadCarousel(force: Bool = false) async {
        guard config.hasCarousel else {
            carouselBooks = []
            return
        }
        guard let source = appStore.source(for: config.carouselSourceUrl) else {
            carouselBooks = []
            return
        }
        if !force, !carouselBooks.isEmpty { return }
        if !force,
           let cached = DiscoverBlockCache.cached(source: config.carouselSourceUrl,
                                                  url: config.carouselKindUrl),
           !cached.isEmpty {
            carouselBooks = Array(cached.prefix(12))
            return
        }
        guard !carouselLoading else { return }
        carouselLoading = true
        defer { carouselLoading = false }
        if let list = try? await SourceDiagnostics.explore(source: source, url: config.carouselKindUrl) {
            carouselBooks = Array(list.prefix(12))
            DiscoverBlockCache.store(source: config.carouselSourceUrl,
                                     url: config.carouselKindUrl,
                                     books: list)
        }
    }

    // MARK: 继续阅读

    /// 书架进度：只在书架变化或手动刷新时重算，不在每帧调用。
    private var lastHistorySignature: Int = 0

    private func historySignature() -> Int {
        // 书架数量 + 最近一次阅读时间足够判断是否需要重算
        var hasher = Hasher()
        hasher.combine(appStore.books.count)
        for book in appStore.books.prefix(24) {
            hasher.combine(book.bookUrl)
            hasher.combine(book.durChapterIndex)
            hasher.combine(book.lastReadAt.timeIntervalSince1970)
        }
        return hasher.finalize()
    }

    func refreshHistoryIfNeeded(force: Bool = false) {
        let signature = historySignature()
        guard force || signature != lastHistorySignature else { return }
        lastHistorySignature = signature
        refreshHistory()
    }

    /// 继续阅读：取书架里最近读的若干本。章节数走内存缓存。
    func refreshHistory() {
        let books = appStore.books.sorted { $0.lastReadAt > $1.lastReadAt }
        historyItems = books.map { book in
            HistoryItem(book: book,
                        chapterCount: chapterCount(for: book),
                        cover: BookCoverLocation.url(for: book))
        }
    }

    private func chapterCount(for book: Book) -> Int? {
        if let cached = chapterCountCache[book.bookUrl] { return cached }
        let toc = appStore.isLocal(book) ? appStore.localToc(book) : appStore.cachedToc(book)
        let count = (toc?.isEmpty == false) ? toc?.count : nil
        chapterCountCache[book.bookUrl] = count
        return count
    }

    /// 目录更新后（比如进了阅读器）清掉对应缓存。
    func invalidateChapterCount(for bookUrl: String) {
        chapterCountCache.removeValue(forKey: bookUrl)
    }

    // MARK: 加载

    /// 加载一个板块（有缓存直接用，force 时重新拉）。
    func load(_ model: DiscoverSectionModel, force: Bool = false) async {
        guard model.kind.dataSource == .bookList else { return }
        guard let source = appStore.source(for: model.entry.sourceUrl) else {
            model.setFailed("书源已不存在")
            return
        }
        if loadingIDs.contains(model.id) { return }
        if !force, !model.books.isEmpty { return }
        if !force, let cached = DiscoverBlockCache.cached(source: model.entry.sourceUrl,
                                                          url: model.entry.kindUrl) {
            model.setBooks(cached)
            // 缓存的目录可能变了，顺手清掉进度缓存
            chapterCountCache.removeAll()
            return
        }

        loadingIDs.insert(model.id)
        model.beginLoading()
        let token = refreshToken
        await BlockRequestGate.shared.acquire()
        do {
            let list = try await SourceDiagnostics.explore(source: source, url: model.entry.kindUrl)
            // 请求期间用户又下拉刷新了一次：这次结果已经过期，不能盖掉新的一轮
            guard token == refreshToken else {
                model.endLoadingWithoutResult()
                await BlockRequestGate.shared.release()
                loadingIDs.remove(model.id)
                return
            }
            model.setBooks(list)
            DiscoverBlockCache.store(source: model.entry.sourceUrl,
                                     url: model.entry.kindUrl,
                                     books: list)
        } catch is CancellationError {
            // 滚动 / 下拉刷新会把正在跑的请求取消掉。这不是书源出错，
            // 界面上不该出现「Swift.CancellationError error 1」这种话，
            // 退出加载态让它下次正常重试即可。
            model.endLoadingWithoutResult()
        } catch let error as URLError where error.code == .cancelled {
            model.endLoadingWithoutResult()
        } catch {
            model.setFailed(Self.readableMessage(error))
        }
        await BlockRequestGate.shared.release()
        loadingIDs.remove(model.id)
    }

    /// 首屏：只加载「全部」也就是第一个分类的前几个板块，其余滚动到再加载。
    /// 多个分类同时拉会让首屏排队等网络，反而更慢。
    func loadInitial(maxSections: Int = 3) async {
        let category = categories.first ?? CustomDiscoverConfig.allCategory
        await loadCategory(category, maxSections: maxSections)
    }

    /// 进入某个分类时按需加载它的板块。
    func loadCategory(_ category: String, maxSections: Int = 3) async {
        let list = sectionsByCategory[category] ?? []
        for model in list.prefix(maxSections) {
            await load(model)
        }
    }

    /// 下拉刷新：清缓存后重拉当前分类可见板块。
    ///
    /// 三个「转了圈但没动」的坑，这里逐个堵上：
    ///  1. `loadingIDs` 里还挂着上一轮的请求（滚动时触发的），force 会在 load() 开头
    ///     被直接挡回来 → 先清空，并让旧请求回来后自动失效；
    ///  2. 书源发现脚本里 `java.refreshExplore()` 代表「配置变了、分类要重读」，
    ///     分类缓存必须一起清，否则刷新拿到的还是旧分类；
    ///  3. 板块的书单缓存清了，但轮播是单独存的，也要重拉。
    func refresh(category: String? = nil) async {
        DiscoverBlockCache.clear()
        DiscoverKindsCache.clear()
        chapterCountCache.removeAll()
        refreshHistoryIfNeeded(force: true)
        // 上一轮可能还有请求在飞（比如刚滚过一圈），不清掉的话
        // force 刷新会在 load() 开头被 loadingIDs 直接挡回来，看起来像「刷新没用」。
        loadingIDs.removeAll()
        // 每次刷新换一个代号：旧请求回来时发现代号变了就不再写回界面，
        // 避免「刷完了又被上一轮的旧数据盖回去」。
        refreshToken &+= 1
        revision &+= 1
        let list = category.flatMap { sectionsByCategory[$0] } ?? sections
        for model in list {
            await load(model, force: true)
        }
        await loadCarousel(force: true)
    }

    // MARK: 编辑页预览

    /// 草稿里某条板块的运行时模型（没有就现建一个，并自动开始拉数据）。
    func sectionFor(_ entry: CustomDiscoverEntry) -> DiscoverSectionModel? {
        previewSections[entry.id]
    }

    /// 给没加载过的草稿板块拉一次数据。重复调用无副作用。
    func loadLive(_ entry: CustomDiscoverEntry) async {
        if previewSections[entry.id] == nil {
            previewSections[entry.id] = DiscoverSectionModel(entry: entry)
        }
        guard let model = previewSections[entry.id] else { return }
        model.update(entry: entry)
        await load(model)
    }

    /// 草稿里删掉一条板块时同步清掉它的预览模型。
    func dropPreview(_ entryID: String) {
        previewSections.removeValue(forKey: entryID)
    }

    /// 把底层错误翻成人话：原始 NSError 描述里带着类型名和 error 编号，
    /// 直接铺在界面上既看不懂也不知道该做什么。
    static func readableMessage(_ error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return "网络连接已断开"
            case .timedOut:
                return "请求超时，书源没有响应"
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return "连不上这个书源"
            default:
                return "请求失败（\(urlError.code.rawValue)）"
            }
        }
        let text = error.localizedDescription
        if text.contains("CancellationError") { return "请求被中断" }
        return text
    }
}
