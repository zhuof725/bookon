import Foundation
import Combine

/// 「探索」页的数据层：板块配置 + 每个分类的书单。
///
/// - 板块配置落 UserDefaults（顺序即页面顺序）。
/// - 书单复用发现页的 `DiscoverBlockCache`：缓存期内进出页面直接显示本地数据。
/// - 请求并发受 `BlockRequestGate` 限制，和发现页共用同一个闸门。
@MainActor
final class ExploreStore: ObservableObject {
    @Published private(set) var boards: [ExploreBoard]
    @Published private(set) var books: [String: [Book]] = [:]
    @Published private(set) var loading: Set<String> = []
    @Published private(set) var failed: Set<String> = []
    @Published private(set) var refreshing = false
    /// 外部（AI）写入标签/推荐语后 +1，卡片据此重绘。
    @Published private(set) var metaRevision = 0

    init(boards: [ExploreBoard]? = nil) {
        self.boards = boards ?? ExploreBoardStore.load()
    }

    // MARK: - 书单

    func books(for category: ExploreCategory) -> [Book]? { books[category.key] }
    func isLoading(_ category: ExploreCategory) -> Bool { loading.contains(category.key) }
    func hasFailed(_ category: ExploreCategory) -> Bool { failed.contains(category.key) }

    /// 还没开始加载过（既不在 loading 也没有失败）。视图用它显示占位状态。
    func isIdle(_ category: ExploreCategory) -> Bool {
        books[category.key] == nil && !loading.contains(category.key) && !failed.contains(category.key)
    }

    /// 读取一个分类的书单：优先内存/新鲜缓存，`force` 用于下拉刷新与重试。
    func load(_ category: ExploreCategory, force: Bool = false) async {
        let key = category.key
        guard !category.isEmpty else { return }
        if loading.contains(key) { return }
        if !force, books[key] != nil { return }
        if !force, let cached = DiscoverBlockCache.cached(source: category.sourceURL, url: category.url) {
            books[key] = cached
            failed.remove(key)
            return
        }
        guard let source = AppStore.shared.source(for: category.sourceURL) else {
            failed.insert(key)
            return
        }
        loading.insert(key)
        failed.remove(key)
        await BlockRequestGate.shared.acquire()
        do {
            let list = try await SourceDiagnostics.explore(source: source, url: category.url, page: 1)
            books[key] = list
            DiscoverBlockCache.store(source: category.sourceURL, url: category.url, books: list)
        } catch {
            // 已经有数据就保留：网络抖动不该把整页打成「加载失败」。
            if books[key] == nil { failed.insert(key) }
        }
        await BlockRequestGate.shared.release()
        loading.remove(key)
    }

    /// 只重试失败过的分类，不动已经成功的板块。
    func retryFailed() async {
        guard !refreshing else { return }
        refreshing = true
        let categories = boards.flatMap(\.visibleCategories).filter { failed.contains($0.key) }
        await withTaskGroup(of: Void.self) { group in
            for category in categories {
                group.addTask { await self.load(category, force: true) }
            }
        }
        refreshing = false
    }

    /// 下拉刷新：重新取所有板块里的分类。缓存先留着，新数据回来再替换，页面不会白屏。
    func refreshAll() async {
        guard !refreshing else { return }
        refreshing = true
        let categories = boards.flatMap(\.visibleCategories)
        await withTaskGroup(of: Void.self) { group in
            for category in categories {
                group.addTask { await self.load(category, force: true) }
            }
        }
        refreshing = false
    }

    // MARK: - 板块配置

    func add(_ board: ExploreBoard) {
        boards.append(board)
        save()
    }

    func add(_ newBoards: [ExploreBoard]) {
        guard !newBoards.isEmpty else { return }
        // 编辑页的 @State 在重复呈现时可能保留上一份草稿（同一个 id）：
        // 追加前修掉重复 id，否则 ForEach 会把两张卡当成同一张只画一张。
        boards = ExploreBoardStore.uniqueIDs(boards + newBoards)
        save()
    }

    /// 有则原地替换，没有则插入（AI 推荐板块用，保证只有一个）。
    func upsert(_ board: ExploreBoard, atFront: Bool = false) {
        if let index = boards.firstIndex(where: { $0.id == board.id }) {
            boards[index] = board
        } else if atFront {
            boards.insert(board, at: 0)
        } else {
            boards.append(board)
        }
        save()
    }

    func update(_ board: ExploreBoard) {
        guard let index = boards.firstIndex(where: { $0.id == board.id }) else { return }
        boards[index] = board
        save()
    }

    func remove(id: String) {
        boards.removeAll { $0.id == id }
        save()
    }

    func remove(at offsets: IndexSet) {
        boards.remove(atOffsets: offsets)
        save()
    }

    func move(from offsets: IndexSet, to destination: Int) {
        boards.move(fromOffsets: offsets, toOffset: destination)
        save()
    }

    /// 「猜你喜欢」点 ×：记住这本书，不再出现在该板块。
    func hide(bookURL: String, in boardID: String) {
        guard let index = boards.firstIndex(where: { $0.id == boardID }) else { return }
        boards[index] = boards[index].hiding(bookURL: bookURL)
        save()
    }

    func save() {
        ExploreBoardStore.save(boards)
    }

    /// 标签 / 推荐语被外部改写后调用：卡片重绘。
    func reloadMeta() {
        metaRevision &+= 1
    }
}
