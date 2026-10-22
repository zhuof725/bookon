import Foundation

/// 固定样例验证解析器，不借助网络成功率，也不会访问登录或验证码。
enum RuleRegression {
    static func run() async throws {
        var checks = 0
        func check(_ condition: Bool, _ name: String) {
            guard condition else { print("FAIL: \(name)"); exit(1) }
            checks += 1; print("PASS: \(name)")
        }
        let variableContext = RuleContext()
        check(JSEngine.shared.evalString("java.put('bid','123'); java.get('bid')", context: variableContext) == "123", "java.put/get 单参数变量读写")
        check(JSEngine.shared.evalString("java.get('bid')", context: variableContext) == "123", "同一上下文跨 JS 求值保留变量")
        check(JSEngine.shared.evalString("java.get('missing')", context: variableContext) == "", "未定义变量返回空字符串")
        check(JSEngine.shared.evalString("java.put('https://example.invalid/key','stored'); java.get('https://example.invalid/key')", context: variableContext) == "stored", "URL 形状的单参数 get 仍然读取变量")
        check(JSEngine.shared.evalString("java.put('local','value'); java.get('local')") == "value", "无上下文时单次求值内变量可用")
        check(JSEngine.shared.evalString("java.get('bid')", context: RuleContext()) == "", "独立无书源上下文不串变量")
        check(JSEngine.shared.evalString("libValue", result: "payload", baseUrl: "https://example.invalid/", vars: ["key": "测试", "page": 2], jsLib: "var libValue = [result,baseUrl,key,page].join('|');") == "payload|https://example.invalid/|测试|2", "jsLib 初始化可读取请求绑定")
        check(AnalyzeUrl.substitute("{{'searchKey/searchPage'}}", key: "测试", page: 3) == "searchKey/searchPage", "URL 模板不改写 JS 字符串常量")
        check(AnalyzeUrl.substitute("{{searchKey}}/{{searchPage}}", key: "测试", page: 3) == "测试/3", "URL 模板保留搜索参数兼容别名")
        check(AnalyzeUrl.substitute("{{({searchKey: '保留字段'}).searchKey}}", key: "测试", page: 3) == "保留字段", "URL 模板不改写对象属性名")
        check(AnalyzeUrl.evalUrlJS("/search?q={{key}}", key: "测试", page: 1, baseUrl: "https://example.invalid/") == "/search?q={{key}}", "无 JS 的 URL 保持原文等待模板替换")
        check(AnalyzeUrl.evalUrlJS("/start<JS>result + '/next'</JS>", key: nil, page: 1, baseUrl: nil) == "/start/next", "URL JS 标签大小写不敏感")
        check(AnalyzeUrl.evalUrlJS("/start<js>result + '/middle'</js>@result/end", key: nil, page: 1, baseUrl: nil) == "/start/middle/end", "URL 后续字面量通过 @result 保留前段结果")
        check(AnalyzeUrl.evalUrlJS("/a<js>result + '/b'</js>@result/c<js>result + '/d'</js>", key: nil, page: 1, baseUrl: nil) == "/a/b/c/d", "多个 URL 脚本与字面量按出现顺序执行")
        check(AnalyzeUrl.evalUrlJS("@JS:key + '/' + page", key: "测试", page: 3, baseUrl: nil) == "测试/3", "URL @JS 前缀与请求参数绑定")
        let fixtures = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Tools/SourceTest/Fixtures")
        func source(_ file: String) throws -> BookSource {
            try JSONDecoder().decode(BookSource.self, from: Data(contentsOf: fixtures.appendingPathComponent(file)))
        }
        let root: [[String: Any]] = [["name": "甲", "url": "/book/1/a.html"], ["name": "乙", "url": "/book/1/b.html"]]
        check(JsonPath.query(root, "$.[*]").count == 2, "根数组 $.[*]")
        check(JsonPath.query(["chapters": root], "$.chapters.[*]").count == 2, "字段数组 chapters.[*]")
        check(JsonPath.query(root, "$[*]").count == 2, "原有 $[*] 不退化")
        let star = try source("star-source.json")
        let starHTML = """
        <html><body><nav><a href="/book/1/not-chapter.html">首页</a></nav>
        <div class="bookshelf-list"><a href="/book/9197/abc.html">第一章</a><a href="/book/9197/def.html">第二章</a><a href="/">首页</a></div></body></html>
        """
        let sa = AnalyzeRule(content: starHTML, baseUrl: "https://m.xiifan.com/novel/9201.html", context: RuleContext(source: star))
        let starItems = sa.getElements(star.ruleToc?.chapterList)
        check(starItems.count == 2, "星星原始 JS + $.[*] 返回2章")
        if let item = starItems.first {
            check(sa.getString(star.ruleToc?.chapterName, from: item) == "第一章", "星星章节标题")
            check(sa.getString(star.ruleToc?.chapterUrl, from: item) == "/book/9197/abc.html", "星星章节地址")
        }
        let dj = try source("dj-source.json")
        var scopeA = dj
        var scopeB = dj
        let scopeBase = "https://scope.example.invalid/" + UUID().uuidString
        scopeA.bookSourceUrl = scopeBase + "#A"
        scopeB.bookSourceUrl = scopeBase + "#B"
        _ = RuleContext.sourcePut(scopeA.bookSourceUrl, "sourceOnly", "A")
        check(RuleContext.sourceGet(scopeB.bookSourceUrl, "sourceOnly") == "", "同站不同后缀书源的静态存储隔离")
        check(RuleContext(source: scopeA).get("sourceOnly") == "A", "来源静态存储与上下文读取一致")
        let sourceContext = RuleContext(source: scopeA)
        _ = sourceContext.put("shared", "source")
        check(RuleContext(source: scopeA).get("shared") == "source", "同一书源跨上下文保留来源变量")
        check(RuleContext(source: scopeB).get("shared") == "", "来源变量不泄漏到同站另一书源")
        let scopeBook = Book(bookUrl: scopeBase + "/book/1", name: "作用域测试", origin: scopeA.bookSourceUrl)
        let otherBook = Book(bookUrl: scopeBase + "/book/2", name: "另一书籍", origin: scopeA.bookSourceUrl)
        let bookContext = RuleContext(source: scopeA, book: scopeBook)
        _ = bookContext.put("shared", "book")
        check(RuleContext(source: scopeA, book: scopeBook).get("shared") == "book", "书籍变量跨上下文保留并覆盖来源值")
        check(RuleContext(source: scopeA, book: otherBook).get("shared") == "source", "不同书籍不共享书籍变量")
        let scopeChapter = BookChapter(url: scopeBase + "/chapter/1", title: "第一章", index: 0)
        let otherChapter = BookChapter(url: scopeBase + "/chapter/2", title: "第二章", index: 1)
        let chapterContext = RuleContext(source: scopeA, book: scopeBook, chapter: scopeChapter)
        _ = chapterContext.put("shared", "chapter")
        check(RuleContext(source: scopeA, book: scopeBook, chapter: scopeChapter).get("shared") == "chapter", "章节变量跨上下文保留并优先于书籍值")
        check(RuleContext(source: scopeA, book: scopeBook, chapter: otherChapter).get("shared") == "book", "不同章节回退书籍变量而不串值")
        check(chapterContext.get("bookName") == "作用域测试" && chapterContext.get("title") == "第一章", "保留书名与章节标题特殊变量")
        let secondChapterContext = RuleContext(source: scopeA, book: scopeBook, chapter: scopeChapter)
        _ = secondChapterContext.put("shared", "updated")
        check(chapterContext.get("shared") == "updated", "已有上下文可见其他上下文更新而不返回旧缓存")
        _ = secondChapterContext.put("shared", "")
        check(chapterContext.get("shared") == "book", "章节变量为空时回退书籍变量")
        _ = RuleContext(source: scopeA, book: scopeBook).put("shared", "")
        check(bookContext.get("shared") == "source", "书籍变量为空时回退来源变量")
        let switchedContext = RuleContext(source: scopeA, book: scopeBook)
        _ = switchedContext.put("onlyThisBook", "private")
        switchedContext.book = otherBook
        check(switchedContext.get("onlyThisBook") == "", "切换书籍后不残留前一本的实例变量")
        var sameURLDifferentSource = scopeBook
        sameURLDifferentSource.origin = scopeB.bookSourceUrl
        check(RuleContext(source: scopeB, book: sameURLDifferentSource).get("onlyThisBook") == "", "相同书籍 URL 在不同书源下仍然隔离")
        let context = RuleContext(source: dj)
        let searchJSON = """
        {"code":0,"body":{"books":[{"bookId":12385810,"bookName":"测试书籍","url":"/book/12385810","author":"测试作者","desc":"测试简介"}]}}
        """
        let search = AnalyzeRule(content: searchJSON, baseUrl: "https://wechat.idejian.com/api/wechat/search/do", jsLib: dj.jsLib, context: context)
        let searchItems = search.getElements(dj.ruleSearch?.bookList)
        check(searchItems.count == 1, "得间 body.books 简写字段")
        if let item = searchItems.first {
            let bookURL = search.getString(dj.ruleSearch?.bookUrl, from: item)
            check(bookURL == "https://wechat.idejian.com/api/wechat/book/12385810", "得间书籍 URL 使用 jsLib host，不是站点首页")
        }
        let detailsJSON = """
        {"code":0,"body":{"bookInfo":{"bookId":12385810,"bookName":"测试书籍","author":"测试作者","desc":"这是测试简介。","multiCategory":[{"name":"测试分类"}],"tag":"测试标签","bookRating":9.2,"popularity":[100],"like":[20]}}}
        """
        let detail = AnalyzeRule(content: detailsJSON, baseUrl: "https://wechat.idejian.com/api/wechat/book/12385810", jsLib: dj.jsLib, context: context)
        let object = detail.getElements(dj.ruleBookInfo?.`init`).first
        check(object is [String: Any], "得间 body.bookInfo init 保留对象")
        let intro = detail.getString(dj.ruleBookInfo?.intro, from: object)
        check(intro.contains("这是测试简介"), "得间原始混合简介规则取到 desc")
        check(intro.contains("测试分类") && intro.contains("测试标签"), "得间简介嵌套模板与 && 合并")
        check(!intro.contains("{{"), "得间简介无残留模板")
        let toc = detail.getString(dj.ruleBookInfo?.tocUrl, from: object)
        check(toc == "https://wechat.idejian.com/api/wechat/allcatalog/12385810?bookId=12385810&page=1", "得间目录 API 地址")
        let catalog = AnalyzeRule(content: "{\"body\":{\"chapterList\":[{\"name\":\"第一章\",\"url\":\"/chapter/12385810/1.html\"}]}}", baseUrl: toc, jsLib: dj.jsLib, context: context)
        let catalogItems = catalog.getElements(dj.ruleToc?.chapterList)
        check(catalogItems.count == 1, "得间目录列表匹配")
        if let item = catalogItems.first {
            let chapterURL = catalog.getString(dj.ruleToc?.chapterUrl, from: item)
            check(chapterURL == "https://wechat.idejian.com/api/wechat/chapter/12385810/1", "得间章节 API 地址保留 jsLib host")
        }
        let xy = try source("xy-source.json")
        let xyHTML = "<div class=\"bx-random item\"><dl><dt class=\"bx-random\"><a href=\"/txt/abc/\">测试书籍</a></dt></dl><img data-original=\"/cover.jpg\"></div>"
        let xyBooks = WebBook.parseBookList(source: xy, body: xyHTML, baseUrl: "https://min-yuan.com/search/", rule: xy.ruleSearch!)
        check(xyBooks.count == 1 && xyBooks[0].name == "测试书籍", "小原混淆 class 不影响 .item + dt a@text")
        let request = AnalyzeUrl(rawUrl: xy.searchUrl!, key: "测试书籍", baseUrl: xy.bookSourceUrl)
        check(request.method == "POST" && request.body == "searchkey=测试书籍", "小原 POST options 与关键词替换")
        try SourceImportRegression.run(check)
        try JSExtensionsRegression.run(check)
        try await SourceRuntimeRegression.run(check)
        ParserRegression.run(check)
        JSBridgeRegression.run(check)
        BookContextRegression.run(check)
        BookInfoFallbackRegression.run(check)
        try await HTTPResponseRegression.run(check)
        try await BookCoverHTTPRegression.run(check)
        try await BookRequestRefreshRegression.run(check)
        CookieStoreRegression.run(check)
        try await CookieBridgeRegression.run(check)
        SourceLoginRegression.run(check)
        LoginBridgeRegression.run(check)
        PersistentLoginRegression.run(check)
        SourceLoginStatusRegression.run(check)
        VariableStoreRegression.run(check)
        await SourceCheckRegression.run(check)
        try await HTTPTTSRegression.run(check)
        try CookieJarSwitchRegression.run(check)
        try TocParseRegression.run(check)
        try LoginFormRegression.run(check)
        try ServerPanelLoginRegression.run(check)
        try await XiaoliuSourceRegression.run(check)
        try await MufanSourceRegression.run(check)
        try await BookIntroRegression.run(check)
        try ThirteenSourcesRegression.run(check)
        try QimoSourceRegression.run(check)
        try await AudioChapterRegression.run(check)
        try MangaBookRegression.run(check)
        MangaPagingRegression.run(check)
        UpscaleRegression.run(check)
        try ShushanSourceRegression.run(check)
        try LoginToastRegression.run(check)
        ContentLayoutRegression.run(check)
        // 书源调试输入判定与原版 Debug.startDebug 一致。
        check(SourceDiagnostics.mode(for: "系统") == .search("系统"), "调试：关键字走搜索")
        check(SourceDiagnostics.mode(for: "https://a.invalid/book/1") == .info("https://a.invalid/book/1"), "调试：绝对网址走详情页")
        check(SourceDiagnostics.mode(for: "月票::https://a.invalid/r?p={{page}}") == .explore("https://a.invalid/r?p={{page}}"), "调试：标题::网址走发现页")
        check(SourceDiagnostics.mode(for: "++https://a.invalid/toc") == .toc("https://a.invalid/toc"), "调试：++ 走目录页")
        check(SourceDiagnostics.mode(for: "--https://a.invalid/c/1") == .content("https://a.invalid/c/1"), "调试：-- 走正文页")
        let kinds = SourceDiagnostics.parseExploreKinds("玄幻::/x?p={{page}}&&都市::/d\n空分类")
        check(kinds.count == 3 && kinds[0].title == "玄幻" && kinds[1].url == "/d" && kinds[2].url == nil, "调试：发现规则 && 与换行分组")
        let jsonKinds = SourceDiagnostics.parseExploreKinds("[{\"title\":\"榜单\",\"url\":\"/rank\"},{\"title\":\"标题\"}]")
        check(jsonKinds.count == 2 && jsonKinds[0].url == "/rank" && jsonKinds[1].url == nil, "调试：发现规则 JSON 数组")
        check(SourceImportLink.sourceURL(URL(string: "yuedu://booksource/importonline?src=https://v1.vossc.com/data/bookSource.json")!) == "https://v1.vossc.com/data/bookSource.json", "导入链接：yuedu importonline")
        check(SourceImportLink.sourceURL(URL(string: "legado://import/bookSource?src=https://a.invalid/s.json")!) == "https://a.invalid/s.json", "导入链接：legado import/bookSource")
        check(SourceImportLink.sourceURL(URL(string: "yuedu://rsssource/importonline?src=https://a.invalid/r.json")!) == nil, "导入链接：订阅源不按书源导入")
        check(SourceImportLink.sourceURL(URL(string: "https://a.invalid/booksource?src=x")!) == nil, "导入链接：普通网址不拦截")
        check(SourceImportLink.sourceURL(URL(string: "yuedu://booksource/importonline")!) == nil, "导入链接：缺 src 不处理")
        check(DebugLog.formatTime(65.0042) == "[01:05.004]", "调试：时间戳 [mm:ss.SSS]")
        try ShushanPipelineShapeRegression.run(check)
        try ShushanBubbleRegression.run(check)
        await ShelfRefreshRegression.run(check)
        ContentBlocksRegression.run(check)
        CommentCardRegression.run(check)
        ImgSrcRegression.run(check)
        InlineBubbleRegression.run(check)
        ReadingPositionRegression.run(check)
        PaginatorRegression.run(check)
        AloudHighlightRegression.run(check)
        ChapterNavigationRegression.run(check)
        try await ChapterContentCacheRegression.run(check)
        try LocalBookRegression.run(check)
        ReaderBookmarkRegression.run(check)
        SearchRankingRegression.run(check)
        try DiscoverRegression.run(check)
        do {
            var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "Asia/Shanghai")!
            let f = ISO8601DateFormatter()
            let anchor = f.date(from: "2026-10-17T10:00:00+08:00")!
            let week = ReadingStatsEngine.range(period: .week, anchor: anchor, calendar: cal)
            check(ReadingStatsEngine.formatRange(week.start, week.end, period: .week, calendar: cal) == "10.12 - 10.18", "统计：本周区间周一到周日")
            let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("stats-\(UUID().uuidString).json")
            let store = ReadingStatsStore(fileURL: url, calendar: cal)
            let book = Book(bookUrl: "b1", name: "书一", origin: "o")
            store.record(book: book, start: anchor, end: anchor.addingTimeInterval(1), chapters: [0])
            check(store.today(anchor: anchor).seconds == 0, "统计：不足3秒不记")
            store.record(book: book, start: anchor, end: anchor.addingTimeInterval(180), chapters: [0, 1])
            store.record(book: book, start: anchor.addingTimeInterval(-86400 * 2), end: anchor.addingTimeInterval(-86400 * 2 + 60), chapters: [2])
            check(store.today(anchor: anchor).seconds == 180, "统计：今日时长")
            check(store.aggregate(period: .week, anchor: anchor).seconds == 240, "统计：本周合计")
            let bars = store.series(period: .week, anchor: anchor)
            check(bars.count == 7 && bars[5] == 3 && bars[3] == 1, "统计：周柱状按天分桶（分钟）")
            check(store.series(period: .year, anchor: anchor).count == 12, "统计：年按月 12 桶")
            store.flush()
            check(ReadingStatsStore(fileURL: url, calendar: cal).aggregate(period: .week, anchor: anchor).seconds == 240, "统计：重启后读回")
            check(store.highlights(period: .week, anchor: anchor).contains { $0.title == "最常读" && $0.detail == "《书一》" }, "统计：最常读")
            try? FileManager.default.removeItem(at: url)
        }
        NextUrlRegression.run(check)
        CookieDomainRegression.run(check)
        SourceCryptoRegression.run(check)
        CryptoBridgeRegression.run(check)
        ElementsJSRulesRegression.run(check)
        EngineCompatRegression.run(check)
        RhinoCompatRegression.run(check)
        HeadlessWebRegression.run(check)
        AutoDetectRegression.run(check)
        try await DataURLRegression.run(check)
        ReviewBubbleRegression.run(check)
        ReviewClickRegression.run(check)
        CoverSignatureRegression.run(check)
        SourceVariableRegression.run(check)
        // 旧版书源兼容：目录脚本只返回整个响应 JSON（没有后续 `$.data.chapters`）时，
        // getElements 得到 1 个字典，必须能从常见字段里找回章节数组。
        let legacyTocRule = "<js>JSON.stringify({code:0,data:{chapters:[{name:'第一章',id:'abc'}]}})</js>"
        let legacyAR = AnalyzeRule(content: "{}", baseUrl: "https://example.invalid/")
        let legacyNodes = legacyAR.getElements(legacyTocRule)
        check(legacyNodes.count == 1, "旧版目录脚本：无后续选择器时得到 1 个字典")
        check(WebBook.nestedChapterNodes(in: (legacyNodes.first as? [String: Any]) ?? [:])?.count == 1,
              "旧版目录脚本：兜底找到 data.chapters")
        check(WebBook.nestedChapterNodes(in: ["data": ["items": [["title": "甲"]]]])?.count == 1,
              "兜底兼容 data.items + title")
        check(WebBook.nestedChapterNodes(in: ["data": ["list": ["甲", "乙"]]]) == nil,
              "兜底不把非章节数组当章节")
        // 脚本报错时退回规则的文本部分（魔丸书源：文本给真实地址、脚本只包一层 data: 协议）
        let brokenAR = AnalyzeRule(content: "{}", baseUrl: "https://example.invalid/")
        let brokenItem: [String: Any] = ["source": "fanqie", "id": "abc"]
        check(brokenAR.getString("/api/chapter/content?source={{$.source}}&chapter_id={{$.id}}&type=novel\n<js>noSuchFunction(result)</js>", from: brokenItem)
                == "/api/chapter/content?source=fanqie&chapter_id=abc&type=novel",
              "章节地址脚本报错时退回文本部分")
        check(brokenAR.getString("<js>noSuchFunction(result)</js>", from: brokenItem).isEmpty,
              "纯脚本规则报错时仍为空（没有文本可退）")
        check(brokenAR.getString("/plain/{{$.id}}\n<js>result + '!'</js>", from: brokenItem) == "/plain/abc!",
              "脚本正常时仍以脚本结果为准")
        // 结尾引号缺失（复制书源常见）：自动补齐后按原脚本求值
        let truncatedRule = "/api/x/{{$.id}}\n<js>\n`data:;base64,${java.base64Encode(result)},{\"type\":\"mw\"}\n</js>"
        check(brokenAR.getString(truncatedRule, from: brokenItem) == "data:;base64,L2FwaS94L2FiYw==,{\"type\":\"mw\"}",
              "结尾反引号缺失的脚本自动补齐")
        // 魔丸书源实际形态：单引号字符串拼接，结尾少一个 `'`
        let quoteRule = "/api/y/{{$.id}}\n<js>\n'data:;base64,' + java.base64Encode(result) + ',{\"type\":\"mw\"}\n</js>"
        check(brokenAR.getString(quoteRule, from: brokenItem) == "data:;base64,L2FwaS95L2FiYw==,{\"type\":\"mw\"}",
              "结尾单引号缺失的脚本自动补齐（魔丸书源）")
        // GET + "{}" 空 body：书源脚本（光遇聚合等）经 request() 序列化后挂在 GET 上，
        // URLSession 会拒绝带 body 的 GET —— 引擎现在自动剥离（SearchProbe A-仅body 用例验证）。
        print("REGRESSION PASS: \(checks) 项固定断言；不声称真机网络/WebView 已验证。")
    }
}
