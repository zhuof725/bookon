import Foundation
import Network

/// 书源批量校验（对齐 Legado 原版「校验书源」：CheckSource / CheckSourceService）。
///
/// 语义与原版一致：
/// - 依次校验 域名可达（可选）→ 搜索 → 发现 → 详情 → 目录 → 正文；
/// - 任一步失败不改写原规则，只把 搜索失效 / 发现失效 / …目录失效 / …正文失效 /
///   校验超时 / js失效 / 网站失效 追加进 bookSourceGroup（逗号分隔，与原版 splitGroupRegex 一致）；
/// - 失败原因按需写入 `// Error: …` 注释，检查开始时清掉上次的错误注释；
/// - 结束时若存在失效分组，整体判为失败，消息为失效分组名；耗时写入 respondTime。
enum SourceCheck {

    enum CheckError: Error, LocalizedError {
        case timeout
        case domainNotHTTP
        case domainUnreachable
        case tocEmpty
        case contentEmpty
        case noUsableChapter
        case invalidGroups(String)

        var errorDescription: String? {
            switch self {
            case .timeout: return "校验超时"
            case .domainNotHTTP: return "源地址不是http链接"
            case .domainUnreachable: return "源地址不可访问"
            case .tocEmpty: return "目录为空"
            case .contentEmpty: return "正文为空"
            case .noUsableChapter: return "目录中没有可用章节"
            case .invalidGroups(let names): return names
            }
        }
    }

    struct Options {
        var keyword: String = "我的"
        var timeout: TimeInterval = 180
        var concurrency: Int = 2
        var checkDomain: Bool = false
        var checkSearch: Bool = true
        var checkDiscovery: Bool = true
        var checkInfo: Bool = true
        var checkCategory: Bool = true
        var checkContent: Bool = true
        var writeComment: Bool = true

        /// 与原版校验设置摘要一致的文案（项目前有空格，同原版字符串拼接）。
        var summary: String {
            var items = ""
            if checkDomain { items += " 域名" }
            if checkSearch { items += " 搜索" }
            if checkDiscovery { items += " 发现" }
            if checkInfo { items += " 详情" }
            if checkCategory { items += " 目录" }
            if checkContent { items += " 正文" }
            return "校验超时：\(Int(timeout))秒\n校验项目：\(items)"
        }
    }

    struct Result {
        var bookSourceUrl: String
        var name: String
        var success: Bool
        /// 与原版 updateFinalMessage 一致：`校验成功` / `校验失败:原因`。
        var message: String
        /// 失败时追加的分组（校验超时 / js失效 / 网站失效）；分组失效时为空（过程里已写入）。
        var group: String?
        /// 检查后书源上的失效分组。
        var groups: [String]
        /// 耗时毫秒，与原版 respondTime 一样写回书源。
        var respondTime: Int
        /// 用户中途停止：不改写书源，也不计成功失败（与原版取消时 ensureActive 中断一致）。
        var cancelled: Bool = false
        var updatedSource: BookSource
    }

    /// 取数钩子；回归测试离线注入，不动网络。
    struct Hooks {
        var search: (BookSource, String) async throws -> [Book]
        var explore: (BookSource, String) async throws -> [Book]
        var bookInfo: (BookSource, Book) async throws -> Book
        var chapters: (BookSource, Book) async throws -> [BookChapter]
        var content: (BookSource, BookChapter, String?, Book?) async throws -> String
        var domainReachable: (String) async -> Bool

        static let live = Hooks(
            search: { try await WebBook.search(source: $0, key: $1) },
            explore: { try await SourceDiagnostics.explore(source: $0, url: $1) },
            bookInfo: { try await WebBook.bookInfo(source: $0, book: $1) },
            chapters: { try await WebBook.chapters(source: $0, book: $1) },
            content: { try await WebBook.content(source: $0, chapter: $1, nextChapterUrl: $2, book: $3) },
            domainReachable: { await SourceCheck.isDomainReachable($0) }
        )
    }

    /// 批量校验：并发数与原版线程池一致可配；onStart / onResult 在调用方上下文里顺序回调。
    static func runAll(_ list: [BookSource], options: Options, hooks: Hooks = .live,
                       onStart: ((BookSource) -> Void)? = nil,
                       onResult: @escaping (Result) -> Void) async -> [Result] {
        var results: [Result] = []
        await withTaskGroup(of: Result.self) { group in
            var iterator = list.makeIterator()
            func addNext() {
                guard !Task.isCancelled, let s = iterator.next() else { return }
                onStart?(s)
                group.addTask { await checkOne(s, options: options, hooks: hooks) }
            }
            for _ in 0..<max(1, options.concurrency) { addNext() }
            for await r in group {
                results.append(r)
                onResult(r)
                addNext()
            }
        }
        return results
    }

    /// 单个书源校验：超时→“校验超时”，脚本异常→“js失效”，其它→“网站失效”。
    static func checkOne(_ origin: BookSource, options: Options, hooks: Hooks = .live) async -> Result {
        var source = origin
        let started = Date()
        var success = false
        var group: String?
        var detail = ""

        func checkBook(book: Book, bookType: String) async throws {
            do {
                if options.checkInfo {
                    var info = book
                    if info.tocUrl?.isEmpty ?? true {
                        info = try await hooks.bookInfo(source, info)
                    }
                    if options.checkCategory, source.bookSourceType != 3 {
                        let toc = try await hooks.chapters(source, info)
                        guard !toc.isEmpty else { throw CheckError.tocEmpty }
                        let usable = toc.filter { !($0.isVolume && $0.url.hasPrefix($0.title)) }
                        guard let first = usable.first else { throw CheckError.noUsableChapter }
                        let next = usable.count > 1 ? usable[1].url : first.url
                        if options.checkContent {
                            let text = try await hooks.content(source, first, next, info)
                            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                throw CheckError.contentEmpty
                            }
                        }
                    }
                }
            } catch let e as CheckError {
                switch e {
                case .tocEmpty:
                    source.addGroup("\(bookType)目录失效")
                    return
                case .contentEmpty:
                    source.addGroup("\(bookType)正文失效")
                    return
                default:
                    throw e
                }
            }
            // 检查成功（或按设置跳过）：清掉旧失效分组。
            source.removeGroup("\(bookType)目录失效")
            source.removeGroup("\(bookType)正文失效")
        }

        func doCheck() async throws {
            source.removeInvalidGroups()
            if options.writeComment { source.removeErrorComment() }

            if options.checkDomain {
                let domain = source.bookSourceUrl
                guard domain.lowercased().hasPrefix("http") else {
                    source.addGroup("域名失效")
                    throw CheckError.domainNotHTTP
                }
                if await hooks.domainReachable(domain) {
                    source.removeGroup("域名失效")
                } else {
                    source.addGroup("域名失效")
                    throw CheckError.domainUnreachable
                }
            }

            if options.checkSearch {
                let word = source.checkKeyword(fallback: options.keyword)
                if source.searchUrl?.isEmpty == false {
                    source.removeGroup("搜索链接规则为空")
                    let books = try await hooks.search(source, word)
                    if books.isEmpty {
                        source.addGroup("搜索失效")
                    } else {
                        source.removeGroup("搜索失效")
                        try await checkBook(book: books[0], bookType: "搜索")
                    }
                } else {
                    source.addGroup("搜索链接规则为空")
                }
            }

            if options.checkDiscovery, source.exploreUrl?.isEmpty == false {
                let url = SourceDiagnostics.exploreKinds(source: source).first { !($0.url ?? "").isEmpty }?.url
                if let url, !url.isEmpty {
                    source.removeGroup("发现规则为空")
                    let books = try await hooks.explore(source, url)
                    if books.isEmpty {
                        source.addGroup("发现失效")
                    } else {
                        source.removeGroup("发现失效")
                        try await checkBook(book: books[0], bookType: "发现")
                    }
                } else {
                    source.addGroup("发现规则为空")
                }
            }

            let invalid = source.invalidGroupNames
            if !invalid.isEmpty {
                throw CheckError.invalidGroups(invalid.joined(separator: ","))
            }
        }

        do {
            try await withTimeout(options.timeout) { try await doCheck() }
            success = true
        } catch let e as CheckError {
            switch e {
            case .timeout:
                group = "校验超时"
                detail = e.errorDescription ?? "校验超时"
                source.addGroup("校验超时")
            case .invalidGroups(let names):
                detail = names // 失效分组已在检查过程中写入，与原版 NoStackTraceException 分支一致
            case .domainNotHTTP, .domainUnreachable:
                // “域名失效”已在检查过程中写入；原版这一支不再追加“网站失效”。
                detail = e.errorDescription ?? "网站失效"
            case .tocEmpty, .contentEmpty, .noUsableChapter:
                group = "网站失效"
                detail = e.errorDescription ?? "网站失效"
                source.addGroup("网站失效")
            }
        } catch let e as LoginScriptError {
            group = "js失效"
            detail = e.message
            source.addGroup("js失效")
        } catch {
            if Task.isCancelled { return cancelledResult(origin) } // 用户停止：不改写书源
            group = "网站失效"
            detail = error.localizedDescription
            source.addGroup("网站失效")
        }
        if Task.isCancelled { return cancelledResult(origin) } // 用户停止：不改写书源

        let elapsed = Int((Date().timeIntervalSince(started) * 1000).rounded())
        source.respondTime = elapsed
        if !success, options.writeComment { source.addErrorComment(detail) }
        return Result(bookSourceUrl: origin.bookSourceUrl,
                      name: origin.bookSourceName,
                      success: success,
                      message: success ? "校验成功" : "校验失败:\(detail)",
                      group: group,
                      groups: source.invalidGroupNames,
                      respondTime: elapsed,
                      updatedSource: source)
    }

    private static func cancelledResult(_ origin: BookSource) -> Result {
        Result(bookSourceUrl: origin.bookSourceUrl, name: origin.bookSourceName,
               success: false, message: "已取消", group: nil,
               groups: origin.invalidGroupNames, respondTime: 0, cancelled: true,
               updatedSource: origin)
    }

    /// 源地址可达性：与原版一样有 2 秒级上限；https 连 443、http 连 80（原版一律用 80）。
    static func isDomainReachable(_ raw: String) async -> Bool {
        let plain = raw.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? raw
        guard let comps = URLComponents(string: plain), let host = comps.host, !host.isEmpty else { return false }
        let defaultPort = (comps.scheme?.lowercased() == "https") ? 443 : 80
        guard let port = NWEndpoint.Port(rawValue: UInt16(clamping: comps.port ?? defaultPort)) else { return false }
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let lock = NSLock()
            var finished = false
            let connection = NWConnection(host: NWEndpoint.Host(host), port: port, using: .tcp)
            func finish(_ ok: Bool) {
                lock.lock()
                if finished { lock.unlock(); return }
                finished = true
                lock.unlock()
                connection.cancel()
                continuation.resume(returning: ok)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: finish(true)
                case .failed, .cancelled: finish(false)
                default: break
                }
            }
            connection.start(queue: .global())
            DispatchQueue.global().asyncAfter(deadline: .now() + 1.6) { finish(false) }
        }
    }

    private static func withTimeout<T>(_ seconds: TimeInterval, _ op: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await op() }
            group.addTask {
                let ns = UInt64(max(0.01, seconds) * 1_000_000_000)
                try await Task.sleep(nanoseconds: ns)
                throw CheckError.timeout
            }
            let value = try await group.next()!
            group.cancelAll()
            return value
        }
    }
}

// MARK: - 分组与注释（与原版 BookSource 的 addGroup/removeGroup/addErrorComment 一致）

extension BookSource {
    /// 与原版 AppPattern.splitGroupRegex 一致：英文/中文逗号、分号。
    static var groupSeparators: CharacterSet { CharacterSet(charactersIn: ",;，；") }

    var sourceGroupNames: [String] {
        (bookSourceGroup ?? "")
            .components(separatedBy: Self.groupSeparators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// 并集去重后以逗号回写（原版 HashSet + TextUtils.join）。
    mutating func addGroup(_ group: String) {
        var names = sourceGroupNames
        for g in group.components(separatedBy: Self.groupSeparators) {
            let t = g.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty, !names.contains(t) { names.append(t) }
        }
        bookSourceGroup = names.joined(separator: ",")
    }

    mutating func removeGroup(_ group: String) {
        let removal = Set(group.components(separatedBy: Self.groupSeparators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty })
        bookSourceGroup = sourceGroupNames.filter { !removal.contains($0) }.joined(separator: ",")
    }

    /// 与原版 getInvalidGroupNames 一致：含“失效”或等于“校验超时”。
    var invalidGroupNames: [String] {
        sourceGroupNames.filter { $0.contains("失效") || $0 == "校验超时" }
    }

    mutating func removeInvalidGroups() {
        let invalid = Set(invalidGroupNames)
        guard !invalid.isEmpty else { return }
        bookSourceGroup = sourceGroupNames.filter { !invalid.contains($0) }.joined(separator: ",")
    }

    mutating func removeErrorComment() {
        guard let comment = bookSourceComment else { return }
        let kept = comment.components(separatedBy: "\n\n").filter { !$0.hasPrefix("// Error: ") }
        bookSourceComment = kept.joined(separator: "\n")
    }

    mutating func addErrorComment(_ message: String) {
        let entry = "// Error: \(message)"
        if let old = bookSourceComment, !old.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            bookSourceComment = entry + "\n\n" + old
        } else {
            bookSourceComment = entry
        }
    }

    /// 与原版 getCheckKeyword 一致：仅当 checkKeyWord 是普通关键字时才使用。
    func checkKeyword(fallback: String) -> String {
        if let k = ruleSearch?.checkKeyWord?.trimmingCharacters(in: .whitespacesAndNewlines),
           !k.isEmpty, !k.contains("http"), !k.contains("::"), !k.contains("++"), !k.contains("--") {
            return k
        }
        return fallback
    }
}
