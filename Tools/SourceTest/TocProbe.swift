import Foundation

/// 线上目录诊断：把「搜索 → 详情 → 目录」链路中目录页的原始内容、规则拆分结果、
/// 节点类型与标题/地址规则输出打印出来，便于定位「列表有 N 项但 0 章」的问题。
enum TocProbe {
    static func run(file: String, key: String) async throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: file))
        let sources = try JSONDecoder().decode([BookSource].self, from: data)
        guard let s = sources.first else { print("书源为空"); return }
        print("书源: \(s.bookSourceName) \(s.bookSourceUrl)")
        let context = RuleContext(source: s)

        let searchURL = AnalyzeUrl(rawUrl: s.searchUrl ?? "", key: key, page: 1,
                                   baseUrl: s.bookSourceUrl, sourceHeader: s.header,
                                   context: context, jsLib: s.jsLib)
        let (searchBody, searchFinal) = try await searchURL.fetch()
        let books = WebBook.parseBookList(source: s, body: searchBody, baseUrl: searchFinal,
                                          rule: s.ruleSearch ?? SearchRule(), context: context)
        print("搜索结果: \(books.count)")
        guard let first = books.first(where: { $0.name.contains(key) }) ?? books.first else { return }
        print("第一本: \(first.name) / \(first.author)")
        print("  bookUrl: \(first.bookUrl.prefix(160))")

        let info = try await WebBook.bookInfo(source: s, book: first)
        print("详情: name=\(info.name) tocUrl=\(info.tocUrl ?? "-")")
        guard let toc = s.ruleToc else { print("无目录规则"); return }

        let tocURL = AnalyzeUrl(rawUrl: info.tocUrl ?? "", baseUrl: s.bookSourceUrl,
                                sourceHeader: s.header, context: RuleContext(source: s, book: info),
                                jsLib: s.jsLib)
        print("目录请求: \(tocURL.method) \(tocURL.url.prefix(200))")
        let (body, finalURL) = try await tocURL.fetch()
        print("目录响应: \(body.count) 字符 url=\(finalURL.prefix(160))")
        print("  开头: \(String(body.prefix(160)).replacingOccurrences(of: "\n", with: "⏎"))")

        let ar = AnalyzeRule(content: body, baseUrl: finalURL, jsLib: s.jsLib,
                             context: RuleContext(source: s, book: info))
        print("chapterList 规则尾部: \(String((toc.chapterList ?? "").suffix(120)).replacingOccurrences(of: "\n", with: "⏎"))")
        let nodes = ar.getElements(toc.chapterList)
        print("nodes = \(nodes.count)")
        for (i, n) in nodes.prefix(3).enumerated() {
            print("  node[\(i)] \(type(of: n)): \(String(describing: n).prefix(220))")
            let title = ar.getString(toc.chapterName, from: n)
            let url = ar.getString(toc.chapterUrl, from: n)
            print("    chapterName(\(toc.chapterName ?? "-")) = \(title)")
            print("    chapterUrl = \(String(url.prefix(200)))")
        }
        let chapters = WebBook.parseChapterNodes(nodes, rule: toc, ar: ar, baseUrl: finalURL)
        print("parseChapterNodes = \(chapters.count) 章")
        for c in chapters.prefix(3) { print("  \(c.title) -> \(String(c.url.prefix(120)))") }

        // 走真实链路（WebBook.chapters 内部含旧版书源兜底），确认目录真的能取到。
        let real = try await WebBook.chapters(source: s, book: info)
        print("WebBook.chapters = \(real.count) 章")
        for c in real.prefix(3) { print("  \(c.title) -> \(String(c.url.prefix(120)))") }
        if let first = real.first {
            let text = try await WebBook.content(source: s, chapter: first, nextChapterUrl: nil, book: info)
            print("正文 \(text.count) 字符，开头: \(String(text.prefix(80)))")
        }
    }
}
