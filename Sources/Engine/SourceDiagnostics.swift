import Foundation

/// 书源调试：输入规则与 Legado 原版 Debug.startDebug 一致。
/// - 绝对网址 → 详情页；`标题::网址` → 发现页；`++网址` → 目录页；`--网址` → 正文页；其它 → 搜索关键字。
/// 日志符号沿用原版（⇒ ︾ ︽ ≡ ◇ ┌ └），每行由 DebugLog 加 [mm:ss.SSS] 时间戳。
enum SourceDiagnostics {
    enum Mode: Equatable {
        case search(String)
        case explore(String)
        case info(String)
        case toc(String)
        case content(String)
    }

    /// 与原版判定顺序一致：先判绝对网址，再判 `::`、`++`、`--`，否则按关键字搜索。
    static func mode(for key: String) -> Mode {
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = k.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") { return .info(k) }
        if let r = k.range(of: "::") { return .explore(String(k[r.upperBound...])) }
        if k.hasPrefix("++") { return .toc(String(k.dropFirst(2))) }
        if k.hasPrefix("--") { return .content(String(k.dropFirst(2))) }
        return .search(k)
    }

    struct ExploreKind: Equatable {
        let title: String
        let url: String?
    }

    /// 解析发现规则文本：JSON 数组按 title/url 取；否则按 `&&` 或换行分组，每组 `标题::网址`（与原版 exploreKinds 一致）。
    static func parseExploreKinds(_ ruleStr: String) -> [ExploreKind] {
        let t = ruleStr.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("["), let data = t.data(using: .utf8),
           let list = try? JSONSerialization.jsonObject(with: data) as? [Any] {
            return list.compactMap { item in
                guard let d = item as? [String: Any] else { return nil }
                let title = (d["title"] as? String) ?? ""
                let url = (d["url"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                return ExploreKind(title: title, url: url)
            }
        }
        guard let re = try? NSRegularExpression(pattern: "(&&|\n)+") else { return [] }
        let ns = t as NSString
        var parts: [String] = []
        var last = 0
        for m in re.matches(in: t, range: NSRange(location: 0, length: ns.length)) {
            parts.append(ns.substring(with: NSRange(location: last, length: m.range.location - last)))
            last = m.range.location + m.range.length
        }
        parts.append(ns.substring(from: last))
        return parts.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.map { part in
            let cfg = part.components(separatedBy: "::")
            let url = cfg.count > 1 ? cfg[1].trimmingCharacters(in: .whitespacesAndNewlines) : nil
            return ExploreKind(title: cfg[0].trimmingCharacters(in: .whitespacesAndNewlines),
                               url: (url?.isEmpty ?? true) ? nil : url)
        }
    }

    /// 读取书源发现分类：`@js:` / `<js>` 先执行脚本得到规则文本；脚本出错时与原版一样返回 `ERROR:` 项。
    static func exploreKinds(source: BookSource) -> [ExploreKind] {
        guard let raw = source.exploreUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return [] }
        var ruleStr = raw
        let lower = raw.lowercased()
        var script: String?
        if lower.hasPrefix("@js:") { script = String(raw.dropFirst(4)) }
        else if lower.hasPrefix("<js>") {
            let body = raw.dropFirst(4)
            if let end = body.range(of: "<", options: .backwards) { script = String(body[..<end.lowerBound]) }
            else { script = String(body) }
        }
        if let script {
            guard let out = JSEngine.shared.evalString(script, baseUrl: source.bookSourceUrl, jsLib: source.jsLib,
                                                       context: RuleContext(source: source)) else {
                return [ExploreKind(title: "ERROR:发现脚本执行失败", url: nil)]
            }
            ruleStr = out
        }
        return parseExploreKinds(ruleStr)
    }

    /// 发现页书籍列表：ruleExplore 优先，缺省时用搜索规则。page 供分类地址里的 {{page}}（加载更多）。
    static func explore(source: BookSource, url: String, page: Int = 1) async throws -> [Book] {
        guard let rule = source.ruleExplore ?? source.ruleSearch else { return [] }
        let context = RuleContext(source: source)
        let au = AnalyzeUrl(rawUrl: url, page: page, baseUrl: source.bookSourceUrl, sourceHeader: source.header,
                            context: context, jsLib: source.jsLib)
        let (body, finalURL) = try await au.fetch()
        DebugLog.recordSource(body, stage: 10)
        return WebBook.parseBookList(source: source, body: body, baseUrl: finalURL, rule: rule,
                                     context: context, isSearch: false)
    }

    static func run(source: BookSource, key: String) async {
        let log = DebugLog.add
        do {
            switch mode(for: key) {
            case .info(let url):
                var book = Book(bookUrl: url, name: "", origin: source.bookSourceUrl)
                book.originName = source.bookSourceName
                log("⇒开始访问详情页:\(DebugLog.url(url))")
                try await infoDebug(source: source, book: book)
            case .explore(let url):
                log("⇒开始访问发现页:\(DebugLog.url(url))")
                log("︾开始解析发现页")
                DebugLog.setStage(10)
                let books = try await explore(source: source, url: url)
                guard let first = books.first else { log("︽未获取到书籍"); return }
                logBookList(books)
                log("︽发现页解析完成")
                log("")
                try await infoDebug(source: source, book: first)
            case .toc(let url):
                var book = Book(bookUrl: url, name: "调试", origin: source.bookSourceUrl)
                book.tocUrl = url
                book.originName = source.bookSourceName
                log("⇒开始访目录页:\(DebugLog.url(url))")
                try await tocDebug(source: source, book: book)
            case .content(let url):
                var book = Book(bookUrl: url, name: "调试", origin: source.bookSourceUrl)
                book.originName = source.bookSourceName
                log("⇒开始访正文页:\(DebugLog.url(url))")
                try await contentDebug(source: source, book: book,
                                       chapter: BookChapter(url: url, title: "调试", index: 0), next: nil)
            case .search(let keyword):
                log("⇒开始搜索关键字:\(keyword)")
                log("︾开始解析搜索页")
                guard source.searchUrl?.isEmpty == false, source.ruleSearch != nil else {
                    log("⇒搜索URL为空"); return
                }
                DebugLog.setStage(10)
                let books = try await WebBook.search(source: source, key: keyword)
                guard let first = books.first else { log("︽未获取到书籍"); return }
                logBookList(books)
                log("︽搜索页解析完成")
                log("")
                try await infoDebug(source: source, book: first)
            }
        } catch is CancellationError {
            log("︽调试已取消")
        } catch {
            let ns = error as NSError
            log("错误：\(ns.domain) / \(ns.code)；\(String(error.localizedDescription.prefix(240)))")
        }
    }

    private static func logBookList(_ books: [Book]) {
        let log = DebugLog.add
        let b = books[0]
        log("┌获取书名"); log("└\(b.name)")
        log("┌获取作者"); log("└\(b.author)")
        log("┌获取分类"); log("└\(b.kind ?? "")")
        log("┌获取字数"); log("└\(b.wordCount ?? "")")
        log("┌获取最新章节"); log("└\(b.lastChapter ?? "")")
        log("┌获取简介"); log("└\(b.intro ?? "")")
        log("┌获取封面链接"); log("└\(b.coverUrl ?? "")")
        log("┌获取详情页链接"); log("└\(DebugLog.url(b.bookUrl))")
        log("◇书籍总数:\(books.count)")
    }

    private static func infoDebug(source: BookSource, book: Book) async throws {
        let log = DebugLog.add
        if let toc = book.tocUrl, !toc.isEmpty {
            log("≡已获取目录链接,跳过详情页")
            log("")
            try await tocDebug(source: source, book: book)
            return
        }
        log("︾开始解析详情页")
        DebugLog.setStage(20)
        let info = try await WebBook.bookInfo(source: source, book: book)
        log("┌获取书名"); log("└\(info.name)")
        log("┌获取作者"); log("└\(info.author)")
        log("┌获取分类"); log("└\(info.kind ?? "")")
        log("┌获取字数"); log("└\(info.wordCount ?? "")")
        log("┌获取最新章节"); log("└\(info.lastChapter ?? "")")
        log("┌获取简介"); log("└\(info.intro ?? "")")
        log("┌获取封面链接"); log("└\(info.coverUrl ?? "")")
        log("┌获取目录链接"); log("└\(DebugLog.url(info.tocUrl ?? info.bookUrl))")
        log("︽详情页解析完成")
        log("")
        try await tocDebug(source: source, book: info)
    }

    private static func tocDebug(source: BookSource, book: Book) async throws {
        let log = DebugLog.add
        log("︾开始解析目录页")
        DebugLog.setStage(30)
        let chapters = try await WebBook.chapters(source: source, book: book)
        log("◇目录总数:\(chapters.count)")
        let toc = chapters.filter { !($0.isVolume && $0.url.hasPrefix($0.title)) && !$0.url.isEmpty }
        if let c = toc.first {
            log("≡首章信息")
            log("◇章节名称:\(c.title)")
            log("◇章节链接:\(DebugLog.url(c.url))")
            if let t = c.updateTime, !t.isEmpty { log("◇章节信息:\(t)") }
            log("◇是否VIP:\(c.isVip)")
        }
        log("︽目录页解析完成")
        log("")
        guard let first = toc.first(where: { !$0.isVolume }) ?? toc.first else {
            log("≡没有正文章节")
            return
        }
        let next = toc.first { $0.index > first.index && !$0.isVolume }?.url ?? first.url
        try await contentDebug(source: source, book: book, chapter: first, next: next)
    }

    private static func contentDebug(source: BookSource, book: Book, chapter: BookChapter, next: String?) async throws {
        let log = DebugLog.add
        log("︾开始解析正文页")
        DebugLog.setStage(40)
        let text = try await WebBook.content(source: source, chapter: chapter, nextChapterUrl: next, book: book)
        log("┌获取章节名称")
        log("└\(chapter.title)")
        log("┌获取正文内容")
        // 正文只显示在本机调试页（与原版一致），不上传、不落盘。
        log("└\n\(text)")
        log("︽正文页解析完成")
    }
}
