import Foundation

/// 书架下拉刷新（下划更新）的离线断言：跳过本地/无书源、合并保留进度、
/// 并发上限、成功/失败计数与结果文案。
enum ShelfRefreshRegression {
    static func run(_ check: (Bool, String) -> Void) async {
        var shelf = Book(bookUrl: "book-a", name: "旧书名", author: "旧作者", origin: "source-a")
        shelf.coverUrl = "https://example.invalid/old.jpg"
        shelf.lastChapter = "第1章"
        shelf.durChapterIndex = 7
        shelf.durChapterPos = 420
        shelf.durChapterTitle = "第七章"
        shelf.addedAt = Date(timeIntervalSince1970: 100)
        shelf.lastReadAt = Date(timeIntervalSince1970: 200)
        let local = Book(bookUrl: "local-b", name: "本地书", origin: "local-origin")
        let noSource = Book(bookUrl: "book-c", name: "无书源", origin: "missing-source")

        let targets = ShelfRefresh.targets([shelf, local, noSource], localOrigin: "local-origin") { $0.origin == "source-a" }
        check(targets.map(\.bookUrl) == ["book-a"],
              "只刷新有书源的在线书籍（实际 \(targets.map(\.bookUrl))）")

        var latest = Book(bookUrl: "book-a", name: "新书名", author: "新作者", origin: "source-a")
        latest.coverUrl = "https://example.invalid/new.jpg"
        latest.lastChapter = "第9章"
        latest.durChapterIndex = 0
        latest.addedAt = Date(timeIntervalSince1970: 0)
        let merged = ShelfRefresh.merge(latest, into: shelf)
        check(merged.name == "新书名" && merged.coverUrl == "https://example.invalid/new.jpg"
              && merged.lastChapter == "第9章", "接受远端的书名/封面/最新章节")
        check(merged.durChapterIndex == 7 && merged.durChapterPos == 420 && merged.durChapterTitle == "第七章",
              "保留阅读进度")
        check(merged.addedAt == shelf.addedAt && merged.lastReadAt == shelf.lastReadAt,
              "保留加入时间与最后阅读时间")
        check(merged.bookUrl == "book-a" && merged.origin == "source-a", "书本身份不变")

        let books = (0..<9).map { Book(bookUrl: "book-\($0)", name: "书\($0)", origin: "source-a") }
        let state = TestConcurrencyState()
        let outcome = await ShelfRefresh.run(books, concurrency: 3) { book in
            state.enter()
            try? await Task.sleep(nanoseconds: 15_000_000)
            state.leave()
            return ShelfRefresh.Result(bookUrl: book.bookUrl, book: book)
        } onResult: { result in
            state.markResult(result.bookUrl)
        }
        let finished = state.finished
        let peak = state.peak
        check(outcome.updated == 9 && outcome.failed == 0,
              "全部刷新成功（\(outcome.updated) 成功 / \(outcome.failed) 失败）")
        check(finished.count == 9, "每本书都回调一次（实际 \(finished.count)）")
        check(peak <= 3, "并发不超过上限（峰值 \(peak)）")

        let failed = await ShelfRefresh.run(Array(books.prefix(2)), concurrency: 2) { book in
            ShelfRefresh.Result(bookUrl: book.bookUrl, book: nil)
        } onResult: { _ in }
        check(failed.updated == 0 && failed.failed == 2, "失败按本计数（\(failed.updated)/\(failed.failed)）")

        check(ShelfRefresh.summary(updated: 2, failed: 0, skipped: 1) == "已更新 2 本", "成功文案")
        check(ShelfRefresh.summary(updated: 2, failed: 1, skipped: 0) == "已更新 2 本，1 本失败", "部分失败文案")
        check(ShelfRefresh.summary(updated: 0, failed: 0, skipped: 3) == "没有可更新的在线书籍",
              "没有在线书时不声称已更新")
        check(ShelfRefresh.summary(updated: 0, failed: 0, skipped: 0) == "书架是空的", "空书架文案")
    }
}
