import Foundation

enum ChapterContentCacheRegression {
    private actor Gate {
        var calls = 0
        private var open = false
        private var waiting: [CheckedContinuation<Void, Never>] = []
        private var started: [CheckedContinuation<Void, Never>] = []
        func load(_ raw: String) async -> String {
            calls += 1
            let starts = started; started.removeAll()
            starts.forEach { $0.resume() }
            if !open { await withCheckedContinuation { waiting.append($0) } }
            return raw
        }
        func waitForStart() async {
            if calls == 0 { await withCheckedContinuation { started.append($0) } }
        }
        func release() {
            open = true
            let waits = waiting; waiting.removeAll()
            waits.forEach { $0.resume() }
        }
    }
    private actor Counter {
        var calls = 0
        func hit(_ raw: String) -> String { calls += 1; return raw }
    }
    private enum FixtureError: Error { case unavailable }

    static func run(_ check: (Bool, String) -> Void) async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("reader-cache-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let cache = ChapterContentCache(directory: folder)
        let key = ChapterContentKey(sourceURL: "source-a", bookURL: "book-a", chapterURL: "2")
        let raw = "正文<comment count=\"82\" onClick=\"open()\"/>"
        let gate = Gate()
        let prefetch = Task { try await cache.content(for: key, priority: .utility) { await gate.load(raw) } }
        await gate.waitForStart()
        let foreground = Task { try await cache.content(for: key) { await gate.load("不应二次抓取") } }
        // 使用 actor 诊断等待真正的在途合并，不靠固定 sleep 猜测任务时序。
        let deadline = Date().addingTimeInterval(3)
        while await cache.coalescedRequestCount == 0 && Date() < deadline { await Task.yield() }
        let joined = await cache.coalescedRequestCount
        check(joined == 1, "预读：前台加入同一个正在抓取的任务")
        // 用户换章会取消旧预取队列，但已开始且被前台等待的正文不能丢失。
        prefetch.cancel()
        await gate.release()
        let foregroundRaw = try await foreground.value
        check(foregroundRaw == raw, "预读：前台拿到原始正文且保留段评标记")
        let requestCount = await gate.calls
        check(requestCount == 1, "预读：同章只进行一次网络加载")
        do { _ = try await prefetch.value } catch is CancellationError { }
        let reuse = Counter()
        let memoryRaw = try await cache.content(for: key) { await reuse.hit("错误") }
        check(memoryRaw == raw, "缓存：读过或预读完成的章节立即复用")
        let reload = ChapterContentCache(directory: folder, memoryLimit: 0)
        let diskRaw = try await reload.content(for: key) { await reuse.hit("错误") }
        let hits = await reuse.calls
        check(diskRaw == raw && hits == 0, "缓存：新实例直接读磁盘而不重新下载")
        let otherSource = ChapterContentKey(sourceURL: "source-b", bookURL: "book-a", chapterURL: "2")
        let otherBook = ChapterContentKey(sourceURL: "source-a", bookURL: "book-b", chapterURL: "2")
        let missingSource = await reload.cached(for: otherSource)
        let missingBook = await reload.cached(for: otherBook)
        check(missingSource == nil && missingBook == nil, "缓存：书源和书籍隔离，不串用相同章节地址")
        let failKey = ChapterContentKey(sourceURL: "s", bookURL: "b", chapterURL: "fail")
        do {
            _ = try await cache.content(for: failKey) { throw FixtureError.unavailable }
            check(false, "缓存：下载失败应向前台报错")
        } catch { check(true, "缓存：失败不伪装成成功正文") }
        let failureCached = await cache.cached(for: failKey)
        check(failureCached == nil, "缓存：失败不写入成功缓存")
        let retried = try await cache.content(for: failKey) { "重新成功" }
        check(retried == "重新成功", "缓存：失败任务清理后可重新请求")
        let emptyKey = ChapterContentKey(sourceURL: "s", bookURL: "b", chapterURL: "empty")
        do {
            _ = try await cache.content(for: emptyKey) { " \n " }
            check(false, "缓存：空正文应拒绝缓存")
        } catch { check(true, "缓存：空结果不会锁死后续重试") }
        let emptyCached = await cache.cached(for: emptyKey)
        let filled = try await cache.content(for: emptyKey) { "有效正文" }
        check(emptyCached == nil && filled == "有效正文", "缓存：空正文后重新获取有效结果")

        // 目录标识：hasCached 只查存在性，不读取正文、不占用内存 LRU。
        let flagKey = ChapterContentKey(sourceURL: "s", bookURL: "b", chapterURL: "flag")
        let before = await cache.hasCached(for: flagKey)
        check(before == false, "目录标识：未缓存的章节不显示标识")
        _ = try await cache.content(for: flagKey) { "标记正文" }
        let after = await cache.hasCached(for: flagKey)
        check(after == true, "目录标识：缓存后的章节可识别")
        let diskOnly = ChapterContentCache(directory: folder, memoryLimit: 0)
        let diskFlag = await diskOnly.hasCached(for: flagKey)
        let memoryEntries = await diskOnly.memoryEntryCount
        check(diskFlag == true && memoryEntries == 0, "目录标识：新实例从磁盘识别且不占用内存")
        // Targeted eviction must preserve unrelated chapter cache entries.
        try await cache.removeChapter(for: flagKey)
        let removed = await cache.cached(for: flagKey)
        let removedDisk = await diskOnly.hasCached(for: flagKey)
        let kept = await cache.cached(for: key)
        check(removed == nil && !removedDisk && kept == raw, "章节清缓存：只删除目标章，保留其他章")
        let fresh = try await cache.content(for: flagKey) { "重新下载正文" }
        check(fresh == "重新下载正文", "章节清缓存：清除后重新执行下载")
        let missKey = ChapterContentKey(sourceURL: "s", bookURL: "b", chapterURL: "never")
        let missFlag = await diskOnly.hasCached(for: missKey)
        check(missFlag == false, "目录标识：不存在的章节不误报")
        _ = try await diskOnly.content(for: missKey) { "会被清掉" }
        _ = await diskOnly.invalidate {
            _ = try? FileManager.default.removeItem(at: folder)
            return true
        }
        let clearedFlag = await diskOnly.hasCached(for: missKey)
        check(clearedFlag == false, "目录标识：清空缓存后不再显示标识")
    }
}
