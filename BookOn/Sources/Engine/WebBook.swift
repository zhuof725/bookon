import Foundation

struct SearchBook: Identifiable, Hashable {
    var id: String { sourceUrl + "|" + bookUrl }
    var sourceUrl: String
    var sourceName: String
    var name: String
    var author: String
    var kind: String
    var intro: String
    var lastChapter: String
    var coverUrl: String
    var bookUrl: String
    var wordCount: String
    var tocUrl: String = ""
    var infoHtml: String? = nil
    var variables: [String: String] = [:]
}

struct WebChapter: Identifiable, Hashable, Codable {
    var id: Int { index }
    var index: Int
    var title: String
    var url: String
    var isVolume: Bool = false
    var isVip: Bool = false
}

enum WebBookError: LocalizedError {
    case emptyBody(String), noChapters, noContent, noSearchUrl
    var errorDescription: String? {
        switch self {
        case .emptyBody(let u): return "获取网页内容失败: \(u)"
        case .noChapters: return "目录为空"
        case .noContent: return "正文为空"
        case .noSearchUrl: return "书源没有搜索地址"
        }
    }
}

/// 移植 Legado WebBook：搜索 / 详情 / 目录 / 正文
enum WebBook {

    // MARK: 搜索

    static func search(_ source: BookSource, key: String, page: Int = 1) async throws -> [SearchBook] {
        guard !source.searchUrl.isEmpty else { throw WebBookError.noSearchUrl }
        DiagLog.shared.info("搜索", "[\(source.bookSourceName)] key=\(key) page=\(page)")
        let js = JSEngine()
        let analyzer = AnalyzeRule(source: source, js: js)
        let a = AnalyzeUrl(source.searchUrl, key: key, page: page, baseUrl: source.bookSourceUrl, source: source, js: js)
        let resp = try await HttpClient.shared.fetch(a, source: source, js: js)
        let body = resp.text
        guard !body.isEmpty else { throw WebBookError.emptyBody(a.url) }
        return parseBookList(source, analyzer: analyzer, body: body, baseUrl: a.url, redirect: resp.finalUrl, rule: source.search, isSearch: true)
    }

    static func explore(_ source: BookSource, url: String, page: Int = 1) async throws -> [SearchBook] {
        let js = JSEngine()
        let analyzer = AnalyzeRule(source: source, js: js)
        let a = AnalyzeUrl(url, page: page, baseUrl: source.bookSourceUrl, source: source, js: js)
        let resp = try await HttpClient.shared.fetch(a, source: source, js: js)
        let body = resp.text
        guard !body.isEmpty else { throw WebBookError.emptyBody(a.url) }
        let rule = source.explore.bookList.isEmpty ? source.search : source.explore
        return parseBookList(source, analyzer: analyzer, body: body, baseUrl: a.url, redirect: resp.finalUrl, rule: rule, isSearch: false)
    }

    private static func parseBookList(_ source: BookSource, analyzer: AnalyzeRule, body: String, baseUrl: String, redirect: String, rule: SearchRule, isSearch: Bool) -> [SearchBook] {
        analyzer.setContent(body, baseUrl: baseUrl)
        analyzer.setRedirect(redirect)
        var out: [SearchBook] = []

        // 直接跳到了详情页
        if isSearch, !source.bookUrlPattern.isEmpty, baseUrl.range(of: source.bookUrlPattern, options: .regularExpression) != nil {
            if let b = infoItem(source, analyzer, body: body, url: baseUrl) { out.append(b) }
            return out
        }
        var listRule = rule.bookList
        var reverse = false
        if listRule.hasPrefix("-") { reverse = true; listRule.removeFirst() }
        if listRule.hasPrefix("+") { listRule.removeFirst() }
        let items = analyzer.getElements(listRule)
        if items.isEmpty && source.bookUrlPattern.isEmpty {
            if let b = infoItem(source, analyzer, body: body, url: baseUrl) { out.append(b) }
            return out
        }
        let rName = analyzer.splitSourceRule(rule.name), rAuthor = analyzer.splitSourceRule(rule.author)
        let rUrl = analyzer.splitSourceRule(rule.bookUrl), rCover = analyzer.splitSourceRule(rule.coverUrl)
        let rIntro = analyzer.splitSourceRule(rule.intro), rKind = analyzer.splitSourceRule(rule.kind)
        let rLast = analyzer.splitSourceRule(rule.lastChapter), rWords = analyzer.splitSourceRule(rule.wordCount)
        for item in items {
            analyzer.setContent(item)
            let name = clean(analyzer.getString(rName))
            guard !name.isEmpty else { continue }
            var b = SearchBook(sourceUrl: source.bookSourceUrl, sourceName: source.bookSourceName, name: name,
                               author: clean(analyzer.getString(rAuthor)), kind: analyzer.getString(rKind).replacingOccurrences(of: "\n", with: ","),
                               intro: analyzer.getString(rIntro), lastChapter: analyzer.getString(rLast),
                               coverUrl: analyzer.getString(rCover, isUrl: true), bookUrl: analyzer.getString(rUrl, isUrl: true),
                               wordCount: analyzer.getString(rWords))
            if b.bookUrl.isEmpty || b.bookUrl == baseUrl && !rUrl.isEmpty { b.bookUrl = baseUrl }
            if b.bookUrl == baseUrl { b.infoHtml = body }
            out.append(b)
        }
        if reverse { out.reverse() }
        DiagLog.shared.log(out.isEmpty ? .warn : .ok, "搜索", "[\(source.bookSourceName)] 解析到 \(out.count) 本" + (out.first.map { "，首条: \($0.name) / \($0.author) / \($0.bookUrl)" } ?? ""))
        return out
    }

    private static func infoItem(_ source: BookSource, _ analyzer: AnalyzeRule, body: String, url: String) -> SearchBook? {
        let r = source.bookInfo
        analyzer.setContent(body, baseUrl: url)
        if !r.initRule.isEmpty { analyzer.setContent(analyzer.getElements(r.initRule).first ?? body) }
        let name = clean(analyzer.getString(r.name))
        guard !name.isEmpty else { return nil }
        return SearchBook(sourceUrl: source.bookSourceUrl, sourceName: source.bookSourceName, name: name,
                          author: clean(analyzer.getString(r.author)), kind: analyzer.getString(r.kind).replacingOccurrences(of: "\n", with: ","),
                          intro: analyzer.getString(r.intro), lastChapter: analyzer.getString(r.lastChapter),
                          coverUrl: analyzer.getString(r.coverUrl, isUrl: true), bookUrl: url, wordCount: analyzer.getString(r.wordCount),
                          tocUrl: analyzer.getString(r.tocUrl, isUrl: true), infoHtml: body)
    }

    // MARK: 详情

    static func bookInfo(_ source: BookSource, _ book: SearchBook) async throws -> SearchBook {
        DiagLog.shared.info("详情", "[\(source.bookSourceName)] \(book.name) \(book.bookUrl)")
        var b = book
        let js = JSEngine()
        let analyzer = AnalyzeRule(source: source, js: js)
        analyzer.bookVariables = ({ b.variables[$0] }, { k, v in b.variables[k] = v })
        var body = book.infoHtml ?? ""
        var url = book.bookUrl
        if body.isEmpty {
            let a = AnalyzeUrl(book.bookUrl, baseUrl: source.bookSourceUrl, source: source, js: js)
            let resp = try await HttpClient.shared.fetch(a, source: source, js: js)
            body = resp.text; url = resp.finalUrl
            guard !body.isEmpty else { throw WebBookError.emptyBody(a.url) }
        }
        let r = source.bookInfo
        analyzer.setContent(body, baseUrl: book.bookUrl)
        analyzer.setRedirect(url)
        if !r.initRule.isEmpty, let first = analyzer.getElements(r.initRule).first { analyzer.setContent(first) }
        let name = clean(analyzer.getString(r.name)); if !name.isEmpty { b.name = name }
        let author = clean(analyzer.getString(r.author)); if !author.isEmpty { b.author = author }
        let kind = analyzer.getString(r.kind); if !kind.isEmpty { b.kind = kind.replacingOccurrences(of: "\n", with: ",") }
        let intro = analyzer.getString(r.intro); if !intro.isEmpty { b.intro = HtmlFormatter.format(intro) }
        let cover = analyzer.getString(r.coverUrl, isUrl: true); if !cover.isEmpty, cover != source.bookSourceUrl { b.coverUrl = cover }
        let last = analyzer.getString(r.lastChapter); if !last.isEmpty { b.lastChapter = last }
        let wc = analyzer.getString(r.wordCount); if !wc.isEmpty { b.wordCount = wc }
        let toc = analyzer.getString(r.tocUrl, isUrl: true)
        b.tocUrl = toc.isEmpty ? book.bookUrl : toc
        if b.tocUrl == book.bookUrl { b.infoHtml = body } else { b.infoHtml = nil }
        DiagLog.shared.ok("详情", "name=\(b.name) author=\(b.author) tocUrl=\(b.tocUrl) cover=\(DiagLog.preview(b.coverUrl, 80))")
        return b
    }

    // MARK: 目录

    static func chapterList(_ source: BookSource, _ book: SearchBook) async throws -> [WebChapter] {
        let js = JSEngine()
        let analyzer = AnalyzeRule(source: source, js: js)
        var vars = book.variables
        analyzer.bookVariables = ({ vars[$0] }, { k, v in vars[k] = v })
        let tocUrl = book.tocUrl.isEmpty ? book.bookUrl : book.tocUrl
        var body = (tocUrl == book.bookUrl ? book.infoHtml : nil) ?? ""
        var redirect = tocUrl
        if body.isEmpty {
            let a = AnalyzeUrl(tocUrl, baseUrl: source.bookSourceUrl, source: source, js: js)
            let resp = try await HttpClient.shared.fetch(a, source: source, js: js)
            body = resp.text; redirect = resp.finalUrl
            guard !body.isEmpty else { throw WebBookError.emptyBody(a.url) }
        }
        let toc = source.toc
        var listRule = toc.chapterList
        var reverse = false
        if listRule.hasPrefix("-") { reverse = true; listRule.removeFirst() }
        if listRule.hasPrefix("+") { listRule.removeFirst() }

        var (chapters, nextUrls) = parseToc(source, analyzer, body: body, baseUrl: tocUrl, redirect: redirect, listRule: listRule, getNext: true)
        var visited: Set<String> = [tocUrl, redirect]
        if nextUrls.count == 1 {
            var next = nextUrls[0]
            var guardCount = 0
            while !next.isEmpty, !visited.contains(next), guardCount < 300 {
                visited.insert(next); guardCount += 1
                let a = AnalyzeUrl(next, baseUrl: source.bookSourceUrl, source: source, js: js)
                guard let resp = try? await HttpClient.shared.fetch(a, source: source, js: js) else { break }
                let (c, n) = parseToc(source, analyzer, body: resp.text, baseUrl: next, redirect: resp.finalUrl, listRule: listRule, getNext: true)
                chapters += c
                next = n.first ?? ""
            }
        } else if nextUrls.count > 1 {
            // 并发抓多页
            let results = await withTaskGroup(of: (Int, [WebChapter]).self) { group -> [(Int, [WebChapter])] in
                for (i, u) in nextUrls.enumerated() {
                    group.addTask {
                        let a = AnalyzeUrl(u, baseUrl: source.bookSourceUrl, source: source, js: nil)
                        guard let resp = try? await HttpClient.shared.fetch(a, source: source, js: nil) else { return (i, []) }
                        let an = AnalyzeRule(source: source)
                        return (i, parseToc(source, an, body: resp.text, baseUrl: u, redirect: resp.finalUrl, listRule: listRule, getNext: false).0)
                    }
                }
                var r: [(Int, [WebChapter])] = []
                for await x in group { r.append(x) }
                return r
            }
            for (_, c) in results.sorted(by: { $0.0 < $1.0 }) { chapters += c }
        }
        guard !chapters.isEmpty else { DiagLog.shared.error("目录", "[\(source.bookSourceName)] 目录为空 tocUrl=\(tocUrl)"); throw WebBookError.noChapters }
        DiagLog.shared.ok("目录", "[\(source.bookSourceName)] \(chapters.count) 章，首章: \(chapters[0].title) \(chapters[0].url)")
        if reverse { chapters.reverse() }
        // 去重（按 url+title）
        var seen = Set<String>(); var list: [WebChapter] = []
        for c in chapters { let k = c.url + "|" + c.title; if seen.insert(k).inserted { list.append(c) } }
        for i in list.indices { list[i].index = i }
        if !toc.formatJs.isEmpty {
            for i in list.indices {
                js.set("title", list[i].title); js.set("index", i)
                if let t = js.evalString(toc.formatJs), !t.isEmpty { list[i].title = t }
            }
        }
        return list
    }

    private static func parseToc(_ source: BookSource, _ analyzer: AnalyzeRule, body: String, baseUrl: String, redirect: String, listRule: String, getNext: Bool) -> ([WebChapter], [String]) {
        analyzer.setContent(body, baseUrl: baseUrl)
        analyzer.setRedirect(redirect)
        let toc = source.toc
        var next: [String] = []
        if getNext, !toc.nextTocUrl.isEmpty {
            next = (analyzer.getStringList(toc.nextTocUrl, isUrl: true) ?? []).filter { $0 != redirect }
        }
        let items = analyzer.getElements(listRule)
        var out: [WebChapter] = []
        let rName = analyzer.splitSourceRule(toc.chapterName), rUrl = analyzer.splitSourceRule(toc.chapterUrl)
        let rVol = analyzer.splitSourceRule(toc.isVolume), rVip = analyzer.splitSourceRule(toc.isVip)
        for item in items {
            analyzer.setContent(item)
            let title = clean(analyzer.getString(rName))
            guard !title.isEmpty else { continue }
            var url = analyzer.getString(rUrl, isUrl: true)
            if url.isEmpty { url = baseUrl }
            let vol = analyzer.getString(rVol); let vip = analyzer.getString(rVip)
            out.append(WebChapter(index: 0, title: title, url: url,
                                  isVolume: ["true", "1"].contains(vol.lowercased()),
                                  isVip: !vip.isEmpty && !["false", "0"].contains(vip.lowercased())))
        }
        return (out, next)
    }

    // MARK: 正文

    static func content(_ source: BookSource, book: SearchBook, chapter: WebChapter, nextChapterUrl: String?) async throws -> String {
        let js = JSEngine()
        let analyzer = AnalyzeRule(source: source, js: js)
        var vars = book.variables
        analyzer.bookVariables = ({ vars[$0] }, { k, v in vars[k] = v })
        js.set("chapter", ["title": chapter.title, "url": chapter.url, "index": chapter.index])
        js.set("book", ["name": book.name, "author": book.author, "bookUrl": book.bookUrl, "tocUrl": book.tocUrl])
        let rule = source.content
        DiagLog.shared.info("正文", "[\(source.bookSourceName)] \(chapter.title) \(chapter.url)")
        let a = AnalyzeUrl(chapter.url, baseUrl: source.bookSourceUrl, source: source, js: js)
        let resp = try await HttpClient.shared.fetch(a, source: source, js: js)
        var body = resp.text
        guard !body.isEmpty else { throw WebBookError.emptyBody(a.url) }

        var texts: [String] = []
        var visited: Set<String> = [chapter.url, resp.finalUrl]
        var (t, nexts) = parseContent(analyzer, rule, body: body, baseUrl: chapter.url, redirect: resp.finalUrl, first: true)
        texts.append(t)
        var guardCount = 0
        // 单个 next：顺序抓
        while nexts.count == 1, guardCount < 50 {
            let n = nexts[0]
            if n.isEmpty || visited.contains(n) || (nextChapterUrl != nil && n == nextChapterUrl) { break }
            visited.insert(n); guardCount += 1
            let na = AnalyzeUrl(n, baseUrl: source.bookSourceUrl, source: source, js: js)
            guard let r = try? await HttpClient.shared.fetch(na, source: source, js: js) else { break }
            body = r.text
            (t, nexts) = parseContent(analyzer, rule, body: body, baseUrl: n, redirect: r.finalUrl, first: false)
            texts.append(t)
        }
        if nexts.count > 1 {
            let more = await withTaskGroup(of: (Int, String).self) { group -> [(Int, String)] in
                for (i, u) in nexts.enumerated() where !visited.contains(u) {
                    group.addTask {
                        let na = AnalyzeUrl(u, baseUrl: source.bookSourceUrl, source: source, js: nil)
                        guard let r = try? await HttpClient.shared.fetch(na, source: source, js: nil) else { return (i, "") }
                        return (i, parseContent(AnalyzeRule(source: source), rule, body: r.text, baseUrl: u, redirect: r.finalUrl, first: false).0)
                    }
                }
                var arr: [(Int, String)] = []
                for await x in group { arr.append(x) }
                return arr
            }
            for (_, s) in more.sorted(by: { $0.0 < $1.0 }) { texts.append(s) }
        }
        var content = texts.filter { !$0.isEmpty }.joined(separator: "\n")
        if !rule.replaceRegex.isEmpty {
            content = analyzer.getString(rule.replaceRegex, content: content)
        }
        content = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { DiagLog.shared.error("正文", "正文为空，规则: \(DiagLog.preview(rule.content, 120))"); throw WebBookError.noContent }
        DiagLog.shared.ok("正文", "\(content.count) 字，共 \(texts.count) 页")
        return content
    }

    private static func parseContent(_ analyzer: AnalyzeRule, _ rule: ContentRule, body: String, baseUrl: String, redirect: String, first: Bool) -> (String, [String]) {
        analyzer.setContent(body, baseUrl: baseUrl)
        analyzer.setRedirect(redirect)
        var c = analyzer.getString(rule.content, unescape: false)
        c = HtmlFormatter.formatKeepImg(c, baseUrl: redirect)
        var next: [String] = []
        if !rule.nextContentUrl.isEmpty {
            next = (analyzer.getStringList(rule.nextContentUrl, isUrl: true) ?? []).filter { !$0.isEmpty && $0 != redirect && $0 != baseUrl }
        }
        return (c, next)
    }

    // MARK: util

    private static func clean(_ s: String) -> String {
        s.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
