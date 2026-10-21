import Foundation

enum WebBook {
    // MARK: Search
    static func search(source: BookSource, key: String, page: Int = 1) async throws -> [Book] {
        guard let su = source.searchUrl, !su.isEmpty, let rule = source.ruleSearch else { return [] }
        let context = RuleContext(source: source)
        let au = AnalyzeUrl(rawUrl: su, key: key, page: page, baseUrl: source.bookSourceUrl, sourceHeader: source.header, context: context, jsLib: source.jsLib)
        let response = try await fetch(au)
        DebugLog.recordSource(response.body, stage: 10)
        return parseBookList(source: source, body: response.body, baseUrl: response.url, rule: rule, context: context)
    }

    /// 书源请求的统一入口：拿到响应后执行 loginCheckJs（原版 WebBook 在每个请求点都做）。
    static func fetch(_ request: AnalyzeUrl, session: URLSession = .shared) async throws -> HTTPResponseData {
        let response = try await request.fetchResponse(session: session)
        return applyLoginCheck(source: request.context?.source, request: request, response: response)
    }

    /// loginCheckJs 的约定：`result` 是 StrResponse，脚本必须返回一个 StrResponse。
    /// 脚本抛错时与原版一样，再用一个 500 响应求值一次（很多源用这个分支弹登录/换线路）。
    static func applyLoginCheck(source: BookSource?, request: AnalyzeUrl? = nil,
                                response: HTTPResponseData) -> HTTPResponseData {
        guard let source, let js = source.loginCheckJs?.trimmingCharacters(in: .whitespacesAndNewlines),
              !js.isEmpty else { return response }
        let context = request?.context ?? RuleContext(source: source)
        func evaluate(_ value: Any) -> Any? {
            JSEngine.shared.eval(js, result: value, baseUrl: response.url,
                                 jsLib: source.jsLib, context: context)
        }
        func converted(_ value: Any?) -> HTTPResponseData? {
            if let r = value as? StrResponse {
                return HTTPResponseData(body: r.body, url: r.url, code: r.code,
                                        headers: r.headers(), rawData: r.bodyBytes)
            }
            // JS 侧包装过的 StrResponse（result.body() 形态）：取回原始负载。
            if let dict = value as? [String: Any],
               let payload = dict["__payload"] as? [String: Any] {
                let body = payload["body"] as? String ?? ""
                let code = (payload["code"] as? NSNumber)?.intValue ?? 0
                let url = payload["url"] as? String ?? response.url
                var headers: [String: String] = [:]
                if let raw = payload["headers"] as? [String: Any] {
                    for (k, v) in raw { headers[k] = "\(v)" }
                }
                return HTTPResponseData(body: body, url: url, code: code, headers: headers, rawData: nil)
            }
            if let text = value as? String {
                return HTTPResponseData(body: text, url: response.url, code: response.code,
                                        headers: response.headers, rawData: nil)
            }
            return nil
        }
        if let value = evaluate(StrResponse(response)) {
            if let converted = converted(value) {
                DebugLog.add("≡loginCheckJs 已重写响应（HTTP \(converted.code)）")
                return converted
            }
        }
        if let error = JSEngine.lastError {
            let failed = HTTPResponseData(body: "loginCheckJs 执行失败：\(error)", url: response.url, code: 500)
            if let second = converted(evaluate(StrResponse(failed))), second.code != 500 {
                DebugLog.add("≡loginCheckJs 在错误分支切换了响应")
                return second
            }
            DebugLog.add("≡loginCheckJs 执行失败，保留原响应：\(error)")
        }
        return response
    }

    /// 与 Kotlin 的 `String.matches(Regex)` 一致：必须整串匹配。
    static func matchesWholly(_ text: String, pattern: String) -> Bool {
        guard let re = RegexLog.compile("^(?:" + pattern + ")$") else { return false }
        return re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    /// 搜索结果页本身就是详情页时（站点精确匹配后跳转），按详情规则取出这一本书。
    static func bookFromInfoPage(source: BookSource, body: String, url: String, listContext: RuleContext) -> [Book] {
        var b = Book(bookUrl: url, name: "", origin: source.bookSourceUrl)
        b.originName = source.bookSourceName
        let infoContext = listContext.forkForBook(b)
        let parsed = parseBookInfo(source: source, book: b, body: body, url: url, context: infoContext)
        // 详情解析会把 tocUrl 兜底成当前页；这里只需要一条搜索结果。
        return parsed.name.isEmpty ? [] : [parsed]
    }

    static func parseBookList(source: BookSource, body: String, baseUrl: String, rule: SearchRule, context: RuleContext? = nil, isSearch: Bool = true,
                              onUnboundResult: ((Book, RuleContext) -> Void)? = nil) -> [Book] {
        let listContext = context ?? RuleContext(source: source)
        let hasPattern = !(source.bookUrlPattern ?? "").isEmpty
        if isSearch, hasPattern, let pattern = source.bookUrlPattern, matchesWholly(baseUrl, pattern: pattern) {
            guard onUnboundResult == nil else { return [] }
            DebugLog.add("≡链接为详情页")
            return bookFromInfoPage(source: source, body: body, url: baseUrl, listContext: listContext)
        }
        let ar = AnalyzeRule(content: body, baseUrl: baseUrl, jsLib: source.jsLib, context: listContext)
        DebugLog.add("┌获取书籍列表")
        let items = ar.getElements(rule.bookList)
        if items.isEmpty, !hasPattern {
            guard onUnboundResult == nil else { return [] }
            DebugLog.add("└列表为空,按详情页解析")
            return bookFromInfoPage(source: source, body: body, url: baseUrl, listContext: listContext)
        }
        DebugLog.add("└列表大小:\(items.count)")
        // 冻结列表阶段变量；每个条目再独立派生，避免循环中的写入串书。
        let snapshot = listContext.forkForBook(Book(bookUrl: "", name: "", origin: source.bookSourceUrl))
        var out: [Book] = []
        for item in items {
            var b = Book(bookUrl: "", name: "", origin: source.bookSourceUrl)
            b.originName = source.bookSourceName
            let itemContext = snapshot.forkForBook(b)
            let itemRule = AnalyzeRule(content: item, baseUrl: baseUrl, jsLib: source.jsLib, context: itemContext)
            // 与 Kotlin getSearchItem 一致；每个字段完成后同步值类型 Book。
            b.name = itemRule.getString(rule.name)
            itemContext.book = b
            if b.name.isEmpty { continue }
            b.author = itemRule.getString(rule.author)
            itemContext.book = b
            b.kind = nilIfEmpty(itemRule.getStringList(rule.kind).joined(separator: ","))
            itemContext.book = b
            b.wordCount = nilIfEmpty(itemRule.getString(rule.wordCount))
            itemContext.book = b
            b.lastChapter = nilIfEmpty(itemRule.getString(rule.lastChapter))
            itemContext.book = b
            b.intro = nilIfEmpty(itemRule.getString(rule.intro))
            itemContext.book = b
            let cover = itemRule.getCoverString(rule.coverUrl)
            b.coverUrl = cover.isEmpty ? nil : AnalyzeUrl.absolute(cover, base: baseUrl)
            itemContext.book = b
            let bookUrl = itemRule.getString(rule.bookUrl)
            b.bookUrl = bookUrl.isEmpty ? baseUrl : AnalyzeUrl.absolute(bookUrl.components(separatedBy: "\n").first ?? bookUrl, base: baseUrl)
            if let onUnboundResult {
                itemContext.book = b
                onUnboundResult(b, itemContext)
            } else {
                itemContext.bindBook(b)
            }
            out.append(b)
        }
        return out
    }

    // MARK: Book info
    static func bookInfo(source: BookSource, book: Book, session: URLSession = .shared) async throws -> Book {
        guard source.ruleBookInfo != nil else { return book }
        let context = RuleContext(source: source, book: book)
        let request = AnalyzeUrl(rawUrl: book.bookUrl, baseUrl: source.bookSourceUrl, sourceHeader: source.header, context: context, jsLib: source.jsLib)
        let canRefresh = BookInfoRequestRefresh.canRefresh(source: source, book: book, request: request)
        // For this saved signed request, try renewal before opening a browser
        // with the same stale headers. All other request callers keep their policy.
        let fetched = try await request.fetchResponse(session: session, deferAuthorizationChallenge: canRefresh)
        try Task.checkCancellation()
        let response = applyLoginCheck(source: source, request: request, response: fetched)
        if canRefresh && [401, 403].contains(response.code) {
            return try await refreshBookInfo(source: source, book: book, previous: request,
                                             failedStatus: response.code, session: session)
        }
        guard response.code == 0 || (200..<300).contains(response.code) else {
            throw BookInfoRequestRefresh.httpError(response.code)
        }
        DebugLog.recordSource(response.body, stage: 20)
        return parseBookInfo(source: source, book: book, body: response.body, url: response.url, context: context)
    }

    /// Legacy shelf entries contain expanded headers, not an executable recipe.
    /// Renew using the actual source search rule, with no guessed IDs/signatures.
    /// There is at most one search and one additional detail request, no recursion.
    private static func refreshBookInfo(source: BookSource, book: Book, previous: AnalyzeUrl,
                                        failedStatus: Int, session: URLSession) async throws -> Book {
        try Task.checkCancellation()
        guard let searchURL = source.searchUrl, let searchRule = source.ruleSearch else {
            throw BookInfoRequestRefresh.httpError(failedStatus)
        }
        DebugLog.add("详情请求返回 HTTP \(failedStatus)，尝试从原书源重新获取同书请求（仅一次）")
        let searchContext = RuleContext(source: source)
        let searchRequest = AnalyzeUrl(rawUrl: searchURL, key: book.name, page: 1,
            baseUrl: source.bookSourceUrl, sourceHeader: source.header, context: searchContext, jsLib: source.jsLib)
        guard !searchRequest.webView, searchRequest.webJs?.isEmpty != false else {
            throw BookInfoRequestRefresh.httpError(failedStatus)
        }
        let response = try await searchRequest.fetchResponse(session: session, allowChallengeFallback: false)
        try Task.checkCancellation()
        guard (200..<300).contains(response.code) else {
            throw BookInfoRequestRefresh.httpError(response.code, stage: "搜索")
        }
        var candidates: [(Book, RuleContext)] = []
        _ = parseBookList(source: source, body: response.body, baseUrl: response.url,
                          rule: searchRule, context: searchContext) { candidate, context in
            candidates.append((candidate, context))
        }
        var matches: [(Book, AnalyzeUrl, RuleContext)] = []
        for (candidate, candidateContext) in candidates {
            try Task.checkCancellation()
            // Reject different metadata before evaluating any candidate URL rule.
            guard candidate.origin == book.origin,
                  BookInfoRequestRefresh.hasSavedHeaders(candidate.bookUrl),
                  BookInfoRequestRefresh.nameKey(candidate.name) == BookInfoRequestRefresh.nameKey(book.name),
                  BookInfoRequestRefresh.nameKey(candidate.author) == BookInfoRequestRefresh.nameKey(book.author) else { continue }
            let request = AnalyzeUrl(rawUrl: candidate.bookUrl, baseUrl: source.bookSourceUrl,
                sourceHeader: source.header, context: candidateContext, jsLib: source.jsLib)
            if BookInfoRequestRefresh.matches(candidate, saved: book, request: request, savedRequest: previous) {
                matches.append((candidate, request, candidateContext))
            }
        }
        guard matches.count == 1, let (_, request, candidateContext) = matches.first,
              BookInfoRequestRefresh.headersChanged(request, from: previous) else {
            throw BookInfoRequestRefresh.httpError(failedStatus,
                note: "未取得可确认属于同一本书的新请求，请更新书源或检查登录状态。")
        }
        let refreshed = try await request.fetchResponse(session: session, allowChallengeFallback: false)
        try Task.checkCancellation()
        guard (200..<300).contains(refreshed.code) else {
            throw BookInfoRequestRefresh.httpError(refreshed.code)
        }
        // Read new search variables, but keep them pending until the detail body
        // itself proves the identity. Never change the persisted bookUrl/key.
        let context = candidateContext.forkForBook(book, preservingExisting: true)
        let result = parseBookInfoResult(source: source, book: book, body: refreshed.body,
                                         url: refreshed.url, context: context)
        try Task.checkCancellation()
        guard BookInfoRequestRefresh.nameKey(result.name) == BookInfoRequestRefresh.nameKey(book.name),
              BookInfoRequestRefresh.nameKey(result.author) == BookInfoRequestRefresh.nameKey(book.author) else {
            throw BookInfoRequestRefresh.invalidDetails()
        }
        context.bindBook(result.book)
        DebugLog.add("同书详情请求已恢复，保留原书架标识及阅读进度")
        return result.book
    }

    /// 解析详情页内容。bookInfo 与“搜索结果直接是详情页”两条路径共用。
    static func parseBookInfo(source: BookSource, book: Book, body: String, url: String, context: RuleContext) -> Book {
        parseBookInfoResult(source: source, book: book, body: body, url: url, context: context).book
    }

    private static func parseBookInfoResult(source: BookSource, book: Book, body: String, url: String,
                                             context: RuleContext) -> (book: Book, name: String, author: String) {
        var b = book
        guard let rule = source.ruleBookInfo else { return (b, "", "") }
        let ar = AnalyzeRule(content: body, baseUrl: url, jsLib: source.jsLib, context: context)
        var root: Any? = nil
        if let i = rule.`init`, !i.isEmpty {
            // Legado 的 init 既可能是纯文本/JS，也可能是 JSON 对象（如得间 body.bookInfo）。
            // 先从整页按字段规则取对象；取不到再退回整页 JS/文本。
            root = ar.getElements(i).first
            if root == nil {
                let initText = ar.getString(i)
                root = AnalyzeRule.parse(initText, baseUrl: url)
            }
            if let parsedString = AnalyzeRule.parse(AnalyzeRule.asString(root ?? ""), baseUrl: url) as? [String: Any] {
                root = parsedString
            } else if let parsedArray = AnalyzeRule.parse(AnalyzeRule.asString(root ?? ""), baseUrl: url) as? [Any] {
                root = parsedArray
            }
        }
        if rule.`init`?.isEmpty == false {
            DebugLog.add(root == nil ? "≡详情页初始化规则未匹配，使用原响应" : "≡执行详情页初始化规则")
        }
        func s(_ r: String?) -> String { ar.getString(r, from: root) }
        let n = s(rule.name); if !n.isEmpty { b.name = n }
        let a = s(rule.author); if !a.isEmpty { b.author = a }
        if let v = BookIntro.normalized(s(rule.intro)) { b.intro = v }
        if let v = nilIfEmpty(ar.getStringList(rule.kind, from: root).joined(separator: ",")) { b.kind = v }
        if let v = nilIfEmpty(s(rule.lastChapter)) { b.lastChapter = v }
        if let v = nilIfEmpty(s(rule.wordCount)) { b.wordCount = v }
        if let v = nilIfEmpty(ar.getCoverString(rule.coverUrl, from: root)) {
            b.coverUrl = AnalyzeUrl.absolute(v, base: url)
        }
        let toc = s(rule.tocUrl)
        b.tocUrl = toc.isEmpty ? url : AnalyzeUrl.absolute(toc, base: url)
        context.book = b
        return (b, n, a)
    }

    // MARK: TOC
    /// 目录规则用 `@get:{…}` 读取详情页 `@put` 的变量（如漫画章节地址里的 comic_id）：
    /// 重新抓目录前必须先跑一次详情页，把变量写进当前会话，否则章节地址会缺参数。
    static func tocRuleUsesVariables(_ source: BookSource) -> Bool {
        (source.ruleToc?.chapterUrl ?? "").range(of: "@get:", options: .caseInsensitive) != nil
    }

    static func chapters(source: BookSource, book: Book) async throws -> [BookChapter] {
        guard let rule = source.ruleToc else { return [] }
        var visited = Set<String>()
        var reverse = false
        var listRule = rule.chapterList ?? ""
        if listRule.hasPrefix("-") { reverse = true; listRule.removeFirst() }
        // 与 Legado BookChapterList 一致：nextTocUrl 返回多个地址时全部抓取（不再逐页追链）；
        // 只有一个地址时沿链继续。地址去重，最多 30 页。
        // 多页串行太慢（如喜马拉雅一次给 8 页、每页 280KB+），按小并发成批抓取、保持页序。
        var wave: [String] = []
        let head = book.tocUrl ?? book.bookUrl
        if !head.isEmpty { wave.append(head) }
        var pages: [[BookChapter]] = []
        while !wave.isEmpty, visited.count < 30 {
            let budget = max(30 - visited.count, 0)
            var batch: [String] = []
            for u in wave where !u.isEmpty && !visited.contains(u) && batch.count < budget {
                visited.insert(u)
                batch.append(u)
            }
            if batch.isEmpty { break }
            let fetched = try await fetchTocBatch(batch, source: source, book: book,
                                                  rule: rule, listRule: listRule)
            var discovered: [String] = []
            for page in fetched {
                pages.append(page.chapters)
                discovered.append(contentsOf: page.nextURLs)
            }
            wave = discovered
        }
        // 正文按 url 判重；分卷保留原位置与标题，不能因复用章链接被去重删除。
        var list = dedupeChapters(pages.flatMap { $0 })
        if reverse { list.reverse() }
        for i in list.indices { list[i].index = i }
        return list
    }

    /// 一批目录页的抓取结果（保持页序）。
    private struct TocPageResult {
        var chapters: [BookChapter]
        var nextURLs: [String]
    }

    /// 并发抓取一批目录页（每批最多 4 个连接）；结果按入参顺序返回。
    private static func fetchTocBatch(_ urls: [String], source: BookSource, book: Book,
                                      rule: TocRule, listRule: String) async throws -> [TocPageResult] {
        var results: [TocPageResult] = []
        results.reserveCapacity(urls.count)
        var start = 0
        while start < urls.count {
            let slice = Array(urls[start..<min(start + 4, urls.count)])
            let batch = try await withThrowingTaskGroup(of: (Int, TocPageResult).self) { group in
                for (offset, u) in slice.enumerated() {
                    group.addTask {
                        (offset, try await fetchTocPage(u, source: source, book: book,
                                                        rule: rule, listRule: listRule))
                    }
                }
                var collected: [(Int, TocPageResult)] = []
                for try await item in group { collected.append(item) }
                return collected.sorted { $0.0 < $1.0 }
            }
            results.append(contentsOf: batch.map { $0.1 })
            start += 4
        }
        return results
    }

    /// 抓取一个目录页：取正文、解析章节、算出下一页地址。
    private static func fetchTocPage(_ u: String, source: BookSource, book: Book,
                                     rule: TocRule, listRule: String) async throws -> TocPageResult {
        let context = RuleContext(source: source, book: book)
        let au = AnalyzeUrl(rawUrl: u, baseUrl: source.bookSourceUrl, sourceHeader: source.header,
                            context: context, jsLib: source.jsLib)
        let response = try await fetch(au)
        let body = response.body, url = response.url
        DebugLog.recordSource(body, stage: 30)
        let ar = AnalyzeRule(content: body, baseUrl: url, jsLib: source.jsLib, context: context)
        DebugLog.add("┌获取目录列表")
        var nodes = ar.getElements(listRule)
        DebugLog.add("└列表大小:\(nodes.count)")
        DebugLog.add("┌解析目录列表")
        // 目录页可能是 data: 伪协议（不能作为相对地址基准），相对章节地址改用书源地址解析。
        let chapterBase = (url.hasPrefix("http://") || url.hasPrefix("https://")) ? url : source.bookSourceUrl
        var parsed = parseChapterNodes(nodes, rule: rule, ar: ar, baseUrl: chapterBase)
        // 兼容旧版书源：目录脚本只返回整个响应 JSON、后面没有 `$.data.chapters` 这类选择器时，
        // getElements 只能拿到 1 个字典，章节全被跳过。这里从常见的章节数组字段里再取一次。
        if parsed.isEmpty, nodes.count == 1, let object = nodes[0] as? [String: Any],
           let nested = nestedChapterNodes(in: object) {
            nodes = nested
            parsed = parseChapterNodes(nested, rule: rule, ar: ar, baseUrl: chapterBase)
            if !parsed.isEmpty {
                DebugLog.add("≡目录列表改从响应 JSON 的嵌套数组解析（\(nested.count) 项）")
            }
        }
        if parsed.isEmpty, let first = nodes.first {
            let typeName = String(describing: type(of: first))
            let keys = (first as? [String: Any])?.keys.sorted().joined(separator: ",") ?? "-"
            let title = ar.getString(rule.chapterName, from: first)
            let link = ar.getString(rule.chapterUrl, from: first)
            DebugLog.add("⚠️目录列表 \(nodes.count) 项未解析出章节（首项 \(typeName)，字段 \(keys)，"
                         + "标题规则\(title.isEmpty ? "为空" : "有值")，地址规则\(link.isEmpty ? "为空" : "有值")）")
            if link.isEmpty {
                DebugLog.add("⚠️章节地址规则原文：\(String((rule.chapterUrl ?? "").prefix(200)))")
            }
        }
        DebugLog.add("└目录列表解析完成")
        let urls = splitNextUrls(ar.getString(rule.nextTocUrl), base: url)
        return TocPageResult(chapters: parsed, nextURLs: urls)
    }

    /// nextTocUrl / nextContentUrl 可能返回多行地址：去空白、转绝对地址、去重并保持顺序。
    static func splitNextUrls(_ raw: String, base: String) -> [String] {
        var seen = Set<String>(), out: [String] = []
        for line in raw.components(separatedBy: "\n") {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { continue }
            let u = AnalyzeUrl.absolute(t, base: base)
            if seen.insert(u).inserted { out.append(u) }
        }
        return out
    }

    /// 把目录列表节点解析成章节（不含去重与反转），便于离线测试。
    static func parseChapterNodes(_ nodes: [Any], rule: TocRule, ar: AnalyzeRule, baseUrl url: String) -> [BookChapter] {
        var out: [BookChapter] = []
        for item in nodes {
            let title = ar.getString(rule.chapterName, from: item)
            if title.isEmpty { continue }
            let vol = ar.getString(rule.isVolume, from: item)
            let isVol = isTruthy(vol)
            var cu = ar.getString(rule.chapterUrl, from: item)
            if cu.isEmpty {
                if !isVol { continue } // 普通章节必须有链接；卷标题可以没有
            } else {
                cu = AnalyzeUrl.absolute(cu, base: url)
            }
            var chapter = BookChapter(url: cu, title: title, index: 0, isVolume: isVol)
            if let vr = rule.isVip, !vr.isEmpty { chapter.isVip = isTruthy(ar.getString(vr, from: item)) }
            if let ur = rule.updateTime, !ur.isEmpty {
                chapter.updateTime = nilIfEmpty(ar.getString(ur, from: item))
            }
            out.append(chapter)
        }
        return out
    }

    /// 旧版书源的目录脚本会把整个响应 JSON 当结果返回（没有再跟 `$.data.chapters`），
    /// 这里在常见字段里找「看起来像章节」的数组，作为兼容兜底；找不到就返回 nil。
    static func nestedChapterNodes(in object: [String: Any]) -> [Any]? {
        let paths = ["data.chapters", "chapters", "data.list", "list",
                     "data.items", "items", "data.data", "result", "rows", "data"]
        for path in paths {
            var current: Any = object
            var matched = true
            for key in path.split(separator: ".") {
                guard let dict = current as? [String: Any], let next = dict[String(key)] else {
                    matched = false
                    break
                }
                current = next
            }
            guard matched, let array = current as? [Any], !array.isEmpty,
                  let first = array.first as? [String: Any],
                  ["name", "title", "chapterName", "chapter_name"].contains(where: { first[$0] != nil })
            else { continue }
            return array
        }
        return nil
    }

    /// 与 Legado 对 isVip/isPay/isVolume 的判定一致：空、false、0、null 为假，其余为真。
    static func isTruthy(_ raw: String) -> Bool {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !(t.isEmpty || t == "false" || t == "0" || t == "null" || t == "undefined")
    }

    /// 正文章节按 url 去重；分卷标题按原位置保留，即使它与正文共享链接。
    static func dedupeChapters(_ list: [BookChapter]) -> [BookChapter] {
        var seen = Set<String>()
        return list.filter { $0.isVolume || $0.url.isEmpty || seen.insert($0.url).inserted }
    }

    // MARK: Content
    static func content(source: BookSource, chapter: BookChapter, nextChapterUrl: String? = nil, book: Book? = nil) async throws -> String {
        let raw = try await rawContent(source: source, chapter: chapter, nextChapterUrl: nextChapterUrl, book: book)
        return cleanText(raw)
    }

    /// 与 content 相同的抓取流程，但保留 <comment>/<img> 标记，供阅读器渲染段评。
    static func contentBlocks(source: BookSource, chapter: BookChapter, nextChapterUrl: String? = nil, book: Book? = nil) async throws -> (raw: String, blocks: [ContentBlock]) {
        let raw = try await rawContent(source: source, chapter: chapter, nextChapterUrl: nextChapterUrl, book: book)
        return (raw, ContentBlocks.parse(raw))
    }

    /// 书源 loginUi 是脚本时，里面常有 java.put('dev', …) 之类的初始化（Legado 打开登录页时才执行）。
    /// 正文规则会读取这些变量，所以抓取前先求值一次，把变量写进书源作用域。每个书源每次启动只执行一次。
    private static var loginUiPrimed = Set<String>()
    private static let primeLock = NSLock()
    static func primeLoginUi(_ source: BookSource) {
        guard let ui = source.loginUi, !ui.isEmpty else { return }
        let raw = ui.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard raw.hasPrefix("@js:") || raw.hasPrefix("<js>") else { return }
        primeLock.lock()
        let first = loginUiPrimed.insert(source.bookSourceUrl).inserted
        primeLock.unlock()
        guard first else { return }
        _ = SourceLoginForm.resolveUiText(ui) { js in
            JSEngine.shared.evalString(js, jsLib: source.jsLib,
                                       loginLib: SourceLoginForm.loginScript(source.loginUrl),
                                       context: RuleContext(source: source))
        }
    }

    static func rawContent(source: BookSource, chapter: BookChapter, nextChapterUrl: String? = nil, book: Book? = nil) async throws -> String {
        primeLoginUi(source)
        guard let rule = source.ruleContent else { return "" }
        var visited = Set<String>()
        var parts: [String] = []
        /// 抓取一页，返回正文与解析出的下一页地址（已过滤、转绝对地址）。
        func loadPage(_ u: String) async throws -> (String, [String]) {
            visited.insert(u)
            let context = RuleContext(source: source, book: book, chapter: chapter)
            var au = AnalyzeUrl(rawUrl: u, baseUrl: source.bookSourceUrl, sourceHeader: source.header, context: context, jsLib: source.jsLib)
            if let wj = rule.webJs, !wj.isEmpty { au.webJs = wj }
            let response = try await fetch(au)
            let body = response.body, url = response.url
            DebugLog.recordSource(body, stage: 40)
            let ar = AnalyzeRule(content: body, baseUrl: url, jsLib: source.jsLib, context: context)
            let text = ar.getString(rule.content)
            let urls = splitNextUrls(ar.getString(rule.nextContentUrl), base: url)
            return (text, urls)
        }
        let first = try await loadPage(chapter.url)
        parts.append(first.0)
        // 与 Legado BookContent 一致：下一页地址若是下一章则停止；
        // 只有一个地址时沿链追到末页；多个地址时按顺序各取一页，不再继续追链。
        let pending = first.1.filter { $0 != nextChapterUrl && !visited.contains($0) }
        if pending.count == 1 {
            var cur: String? = pending[0]
            while let u = cur, !visited.contains(u), u != nextChapterUrl, visited.count < 20 {
                let page = try await loadPage(u)
                parts.append(page.0)
                let more = page.1.filter { $0 != nextChapterUrl && !visited.contains($0) }
                cur = more.first
            }
        } else if pending.count > 1 {
            for u in pending.prefix(19) where !visited.contains(u) {
                try Task.checkCancellation()
                parts.append(try await loadPage(u).0)
            }
        }
        var text = parts.joined(separator: "\n")
        if let rr = rule.replaceRegex, !rr.isEmpty {
            // 替换规则直接作用在正文字符串上：走 HTML 解析再序列化会把段间换行并成空格。
            text = AnalyzeRule(content: text, baseUrl: chapter.url, jsLib: source.jsLib, context: RuleContext(source: source, book: book, chapter: chapter)).getReplacementString(rr, from: text)
        }
        // 段落边界不能因书源而异：有的源把段界只写成 U+3000，整章/整页没有换行，
        // 阅读器会把整段当一段。这里对所有书源统一还原段界。
        text = normalizeParagraphBoundaries(text)
        return text
    }

    /// 正文段落「排版」对所有书源一致：把「句末标点（可带闭引号/括号）+ 全角空格」
    /// 这种只写在 U+3000 里的段界还原成换行。按行处理，避免误伤：
    /// 含 CR 的行、没有 U+3000 的行、以及一行内命中不足两处的行一律原样返回；
    /// 句中普通全角空格与已有换行都不动。
    static func normalizeParagraphBoundaries(_ text: String) -> String {
        guard text.contains("\u{3000}") else { return text }
        var changed = false
        let fixed = text.components(separatedBy: "\n").map { line -> String in
            guard !line.contains("\r"), line.contains("\u{3000}") else { return line }
            let recovered = recoverParagraphBoundaries(in: line)
            if recovered != line { changed = true }
            return recovered
        }
        return changed ? fixed.joined(separator: "\n") : text
    }

    /// 单行内还原段界；至少命中两处才认为这一行真的把段界写成了全角空格，
    /// 否则原样返回（一句中间的单个全角空格不拆段）。
    static func recoverParagraphBoundaries(in line: String) -> String {
        let characters = Array(line)
        let paragraphMarks: Set<Character> = ["。", "！", "？", "!", "?", "…"]
        let closingMarks: Set<Character> = ["”", "’", "」", "』", "》", "〉", "】", "〕", "〗", "〙", "〛", "\"", "'", ")", "]", "}"]
        var output = ""
        var boundaries = 0
        var i = 0
        while i < characters.count {
            output.append(characters[i])
            guard paragraphMarks.contains(characters[i]) else { i += 1; continue }
            var next = i + 1
            while next < characters.count && closingMarks.contains(characters[next]) {
                output.append(characters[next])
                next += 1
            }
            if next < characters.count && characters[next] == "\u{3000}" {
                // 行尾的全角空格不是段界：不加空行，也不计入命中数。
                var after = next + 1
                while after < characters.count && characters[after] == "\u{3000}" { after += 1 }
                if after < characters.count {
                    output.append("\n")
                    boundaries += 1
                    i = after
                } else {
                    i = next
                }
            } else {
                i = next
            }
        }
        return boundaries >= 2 ? output : line
    }

    static func cleanText(_ s: String) -> String {
        var t = s
        t = t.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])
        t = t.replacingOccurrences(of: "</p>", with: "\n", options: .caseInsensitive)
        t = t.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&amp;", with: "&")
        return t.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "\u{3000}"))) }
            .filter { !$0.isEmpty }
            .map { "\u{3000}\u{3000}" + $0 }
            .joined(separator: "\n")
    }

    static func nilIfEmpty(_ s: String) -> String? { s.isEmpty ? nil : s }
}
