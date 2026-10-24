import Foundation

/// 书架下拉刷新（下划更新）的纯逻辑：挑出需要联网刷新的书、把新元数据合并回书架条目，
/// 并按并发上限逐本刷新。网络细节由调用方注入，便于离线断言。
enum ShelfRefresh {
    /// 一本书的刷新结果。
    struct Result {
        var bookUrl: String
        /// 合并后的书架条目（保留阅读进度与时间戳）；失败时为 nil。
        var book: Book?
        var chapters: [BookChapter] = []
        var succeeded: Bool { book != nil }
    }

    /// 需要联网刷新的书架条目：本地书籍与找不到书源的书跳过（它们没有可更新的远端信息）。
    static func targets(_ books: [Book], localOrigin: String, hasSource: (Book) -> Bool) -> [Book] {
        books.filter { $0.origin != localOrigin && hasSource($0) }
    }

    /// 用刚取到的书籍信息更新书架条目：只接受远端字段，
    /// 阅读进度、章内位置、加入时间与最后阅读时间一律沿用书架上的旧值。
    static func merge(_ latest: Book, into existing: Book) -> Book {
        var updated = latest
        updated.bookUrl = existing.bookUrl
        updated.origin = existing.origin
        updated.durChapterIndex = existing.durChapterIndex
        updated.durChapterPos = existing.durChapterPos
        updated.durChapterTitle = existing.durChapterTitle
        updated.addedAt = existing.addedAt
        updated.lastReadAt = existing.lastReadAt
        return updated
    }

    /// 逐本刷新，最多 concurrency 本并行；每完成一本回调一次（按完成顺序）。
    /// 返回（成功数，失败数）。取消后不再启动新的书。
    @discardableResult
    static func run(_ books: [Book], concurrency: Int = 4,
                    load: @escaping @MainActor @Sendable (Book) async -> Result,
                    onResult: @escaping @MainActor @Sendable (Result) -> Void) async -> (updated: Int, failed: Int) {
        var updated = 0
        var failed = 0
        await withTaskGroup(of: Result.self) { group in
            var iterator = books.makeIterator()
            func addNext() {
                guard !Task.isCancelled, let book = iterator.next() else { return }
                group.addTask { await load(book) }
            }
            for _ in 0..<max(1, concurrency) { addNext() }
            for await result in group {
                if result.succeeded { updated += 1 } else { failed += 1 }
                await onResult(result)
                addNext()
            }
        }
        return (updated, failed)
    }

    /// 结果文案：给界面显示用，不掺入具体书名或错误细节。
    static func summary(updated: Int, failed: Int, skipped: Int) -> String {
        if updated == 0 && failed == 0 { return skipped > 0 ? "没有可更新的在线书籍" : "书架是空的" }
        return failed == 0 ? "已更新 \(updated) 本" : "已更新 \(updated) 本，\(failed) 本失败"
    }
}
