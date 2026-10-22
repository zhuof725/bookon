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

    init(entry: CustomDiscoverEntry) {
        self.entry = entry
        self.id = entry.id
    }

    /// 配置改了（标题 / 模板 / 数量），把新值写回，已加载的书保留。
    func update(entry newEntry: CustomDiscoverEntry) {
        entry = newEntry
    }

    func setBooks(_ list: [Book]) {
        books = list
        failed = false
        errorText = nil
        loading = false
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
}

// MARK: - 发现页数据源

/// 把「配置 + 书源」变成可渲染的板块。
///
/// 职责单一：读配置、按需拉书、给视图提供 `DiscoverSectionModel`。
/// 不做任何排版决定——排版由模板自己负责。
@MainActor
final class DiscoverBoardStore: ObservableObject {
    static let shared = DiscoverBoardStore()

    @Published private(set) var sections: [DiscoverSectionModel] = []
    @Published private(set) var historyItems: [HistoryItem] = []
    @Published private(set) var config = CustomDiscoverConfig()

    /// 配置变更计数：外部改了配置后 bump，页面据此重建。
    @Published private(set) var revision = 0

    private var loadingIDs: Set<String> = []
    /// 直接用共享实例，避免 unowned 引用在单例场景下的生命周期隐患。
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

    // MARK: 板块

    private func rebuild() {
        let entries = config.visibleEntries(from: appStore.sources)
        // 复用已加载的书，避免配置微调时整页重刷
        let existing = Dictionary(sections.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        sections = entries.map { entry in
            if let model = existing[entry.id] {
                // 同一个板块：把最新配置（标题/模板/数量）写回去，保留已加载的书
                model.update(entry: entry)
                return model
            }
            return DiscoverSectionModel(entry: entry)
        }
        refreshHistory()
    }

    /// 继续阅读：取书架里最近读的若干本。
    func refreshHistory() {
        // 书架里的书都算候选，按最后阅读时间排序
        let books = appStore.books.sorted { $0.lastReadAt > $1.lastReadAt }
        historyItems = books.map { book in
            HistoryItem(book: book,
                        chapterCount: chapterCount(for: book),
                        cover: BookCoverLocation.url(for: book))
        }
    }

    /// 顶部分类：配置里写了就用配置，没写按书源名自动生成，并加「全部」。
    var visibleCategories: [String] {
        let names = config.effectiveCategories
        guard !names.isEmpty else { return [] }
        // 自动生成时没有「全部」，这里补在最前；手写了就不硬塞
        if config.categories.isEmpty {
            return [CustomDiscoverConfig.allCategory] + names
        }
        return names
    }

    /// 某个分类下的板块。
    func sections(inCategory category: String) -> [DiscoverSectionModel] {
        let allowed = Set(config.entries(inCategory: category).map(\.id))
        if allowed.isEmpty { return sections }
        return sections.filter { allowed.contains($0.id) }
    }

    /// 顶部轮播：按分类生成，一屏一个分类。
    ///
    /// 封面取该分类下第一个板块的前三本书；板块还没加载完时先给空槽，
    /// 加载完会随 sections 的 @Published 变化自动刷新。
    var carouselHeroes: [CustomDiscoverHero] {
        visibleCategories.enumerated().map { offset, category in
            let list = sections(inCategory: category)
            let firstBooks = list.first?.books ?? []
            let covers: [URL?] = firstBooks.prefix(3).map { BookCoverLocation.url(for: $0) }

            let count = list.count
            let sub = list.isEmpty ? "" : "\(count) 个板块"

            // 「全部」这一屏用第一个板块的书名做说明；其余用板块名列表
            let detail: String
            if list.isEmpty {
                detail = ""
            } else if category == CustomDiscoverConfig.allCategory {
                detail = list.prefix(3).map(\.title).joined(separator: " · ")
            } else {
                detail = list.prefix(3).map(\.title).joined(separator: " · ")
            }

            return CustomDiscoverHero(
                id: "\(category)-\(offset)",
                title: category,
                subtitle: sub,
                detail: detail,
                covers: covers
            )
        }
    }

    private func chapterCount(for book: Book) -> Int? {
        let toc = appStore.isLocal(book) ? appStore.localToc(book) : appStore.cachedToc(book)
        guard let toc, !toc.isEmpty else { return nil }
        return toc.count
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

    /// 首屏：只加载前面几个板块，滚动到再加载其余。
    func loadInitial(maxSections: Int = 3) async {
        for model in sections.prefix(maxSections) {
            await load(model)
        }
    }

    /// 下拉刷新：清缓存后重拉可见板块。
    func refresh() async {
        DiscoverBlockCache.clear()
        DiscoverKindsCache.clear()
        revision &+= 1
        refreshHistory()
        for model in sections {
            await load(model, force: true)
        }
    }
}
