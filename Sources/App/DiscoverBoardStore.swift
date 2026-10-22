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
    @Published private(set) var historyItems: [HistoryItem] = []
    @Published private(set) var config = CustomDiscoverConfig()

    /// 预计算好，给视图直接用。
    @Published private(set) var categories: [String] = []
    /// 分类名 → 该分类下的板块。切分类时不用再过滤。
    @Published private(set) var sectionsByCategory: [String: [DiscoverSectionModel]] = [:]

    /// 配置变更计数：外部改了配置后 bump，页面据此重建。
    @Published private(set) var revision = 0

    private var loadingIDs: Set<String> = []
    /// 章节数缓存：bookUrl → 章数（nil 表示查过但没有目录缓存）
    private var chapterCountCache: [String: Int?] = [:]
    private var appStore: AppStore { AppStore.shared }

    var isEmpty: Bool { sections.isEmpty }

    // MARK: 配置

    func reloadConfig() {
        config = CustomDiscoverStore.load()
        config.refreshNames(from: appStore.sources)
        rebuild()
        revision &+= 1
    }

    func save(_ next: CustomDiscoverConfig) {
        var updated = next
        updated.refreshNames(from: appStore.sources)
        CustomDiscoverStore.save(updated)
        config = updated
        rebuild()
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
        await BlockRequestGate.shared.acquire()
        do {
            let list = try await SourceDiagnostics.explore(source: source, url: model.entry.kindUrl)
            model.setBooks(list)
            DiscoverBlockCache.store(source: model.entry.sourceUrl,
                                     url: model.entry.kindUrl,
                                     books: list)
        } catch {
            model.setFailed(error.localizedDescription)
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
    func refresh(category: String? = nil) async {
        DiscoverBlockCache.clear()
        DiscoverKindsCache.clear()
        chapterCountCache.removeAll()
        revision &+= 1
        refreshHistoryIfNeeded(force: true)
        let list = category.flatMap { sectionsByCategory[$0] } ?? sections
        for model in list {
            await load(model, force: true)
        }
    }
}
