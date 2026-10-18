import Foundation

/// 漫画书源（武芊漫画，bookSourceType == 2）的识别、图片提取与规则解析。
/// 全程使用离线夹具（真实接口响应），不访问网络。
enum MangaBookRegression {
    static func fixtureDirectory() -> URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Tools/SourceTest/Fixtures")
    }

    static func run(_ check: (Bool, String) -> Void) throws {
        let dir = fixtureDirectory()
        func fixture(_ name: String) throws -> String {
            try String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8)
        }
        let sourceList = try JSONDecoder().decode([BookSource].self,
                                                  from: Data(contentsOf: dir.appendingPathComponent("manga-wuqian.json")))
        guard let source = sourceList.first else {
            check(false, "漫画：书源夹具可解码")
            return
        }

        // 1. 书源类型识别（原版按 bookSourceType == 2 进入漫画阅读器）
        check(source.bookSourceName == "武芊漫画" && source.bookSourceType == 2, "漫画：书源解码，类型为图片源")
        check(MangaBook.isManga(source: source), "漫画：类型 2 识别为漫画源")
        var textSource = BookSource(bookSourceUrl: "https://t.invalid", bookSourceName: "文字")
        textSource.bookSourceType = 0
        check(!MangaBook.isManga(source: textSource), "漫画：文字源不识别")
        check(!MangaBook.isManga(source: nil), "漫画：无书源不识别")
        check(MangaBook.chapterStartTitle("第1话 重生") == "阅读 第1话 重生"
              && MangaBook.chapterEndTitle("第1话 重生") == "已读完 第1话 重生", "漫画：分章标记文案")

        // 2. 图片地址提取（对应原版 BookHelp.flowImages + NetworkUtils.getAbsoluteURL）
        let mixed = """
        <p>文字</p><img src="http://a.invalid/1.jpg"><img src='/rel/2.png'>
        <IMG SRC=/rel3/3.webp><img src="http://a.invalid/1.jpg">
        """
        let extracted = MangaBook.imageURLs(in: mixed, baseURL: "https://comic.mkzcdn.com/chapters/123.html")
        check(extracted == [
            "http://a.invalid/1.jpg",
            "https://comic.mkzcdn.com/rel/2.png",
            "https://comic.mkzcdn.com/rel3/3.webp",
        ], "漫画：双引号 / 单引号 / 无引号 src 提取与相对地址补全，相邻重复只留一个（实际 \(extracted)）")
        check(MangaBook.imageURLs(in: "<img src=\"a.jpg\"><img src=\"b.jpg\"><img src=\"a.jpg\">",
                                  baseURL: "https://h.invalid/p/1.html") == ["https://h.invalid/p/a.jpg",
                                                                             "https://h.invalid/p/b.jpg",
                                                                             "https://h.invalid/p/a.jpg"],
              "漫画：隔位重复的图片保留（原版 distinctUntilChanged）")
        check(MangaBook.imageURLs(in: "<img src=\"javascript:void(0)\">", baseURL: "https://h.invalid/").isEmpty,
              "漫画：javascript: 地址丢弃")
        check(MangaBook.imageURLs(in: "<img src=\"data:image/png;base64,AAAA\">", baseURL: "https://h.invalid/")
              == ["data:image/png;base64,AAAA"], "漫画：data: 地址原样保留")
        check(MangaBook.imageURLs(in: "<p>没有图片</p>", baseURL: "https://h.invalid/").isEmpty,
              "漫画：没有 img 时为空")
        check(MangaBook.imageURLs(in: "<img src=\"http://a.invalid/x?a=1&amp;b=2\">", baseURL: "https://h.invalid/")
              == ["http://a.invalid/x?a=1&b=2"], "漫画：HTML 实体 &amp; 还原为 &")

        // 3. @get:{…} 与 {{…}} 混用的规则替换（漫画 chapterUrl 的写法）
        let mixedContext = RuleContext()
        _ = mixedContext.put("comic_id", "207622")
        let mixedRule = "https://comic.mkzcdn.com/chapter/content/?chapter_id={{$.chapter_id}}&comic_id=@get:{comic_id}"
        let mixedValue = AnalyzeRule(content: "{\"chapter_id\":\"476064\"}", baseUrl: "", context: mixedContext)
            .getString(mixedRule)
        check(mixedValue == "https://comic.mkzcdn.com/chapter/content/?chapter_id=476064&comic_id=207622",
              "漫画：@get 与 {{}} 混用同时替换（得到 \(mixedValue)）")
        let reversed = AnalyzeRule(content: "{\"chapter_id\":\"1\"}", baseUrl: "", context: mixedContext)
            .getString("k=@get:{comic_id}&id={{$.chapter_id}}")
        check(reversed == "k=207622&id=1", "漫画：@get 在前、模板在后也生效")

        // 4. 搜索解析（JSON 接口 + bookUrl 模板）
        let searchBody = try fixture("manga-search.json")
        let books = WebBook.parseBookList(source: source, body: searchBody, baseUrl: source.bookSourceUrl,
                                          rule: source.ruleSearch ?? SearchRule(),
                                          context: RuleContext(source: source))
        check(books.count == 1 && books.first?.name == "妖神记", "漫画：搜索结果解析（\(books.first?.name ?? "空")）")
        check(books.first?.bookUrl == "https://comic.mkzcdn.com/comic/info/?comic_id=207622",
              "漫画：详情地址模板展开")
        check(books.first?.author == "踏雪动漫", "漫画：作者字段")

        // 5. 详情解析（name 规则只 @put 变量、不覆盖书名；tocUrl 模板取 comic_id）
        let infoBody = try fixture("manga-info.json")
        let book = Book(bookUrl: "https://comic.mkzcdn.com/comic/info/?comic_id=207622",
                        name: "妖神记", origin: source.bookSourceUrl)
        let infoContext = RuleContext(source: source, book: book)
        let info = WebBook.parseBookInfo(source: source, book: book, body: infoBody,
                                         url: book.bookUrl, context: infoContext)
        check(info.name == "妖神记", "漫画：@put 规则不覆盖搜索得到的书名")
        check(info.tocUrl == "https://comic.mkzcdn.com/chapter/v1/?comic_id=207622",
              "漫画：目录地址模板展开（实际 \(info.tocUrl ?? "nil")）")
        check(info.kind == "冒险,热血,玄幻", "漫画：分类 JS 译名（实际 \(info.kind)）")

        // 6. 目录解析：@get:{comic_id} 取详情页写入的变量（跨请求仍可见）
        let tocBody = try fixture("manga-toc.json")
        let tocURL = "https://comic.mkzcdn.com/chapter/v1/?comic_id=207622"
        let tocContext = RuleContext(source: source, book: book)
        let tocRule = source.ruleToc ?? TocRule()
        let tocAnalyzer = AnalyzeRule(content: tocBody, baseUrl: tocURL,
                                      jsLib: source.jsLib, context: tocContext)
        let nodes = tocAnalyzer.getElements(tocRule.chapterList)
        check(nodes.count == 80, "漫画：目录列表节点数（\(nodes.count)）")
        let chapters = WebBook.parseChapterNodes(nodes, rule: tocRule, ar: tocAnalyzer, baseUrl: tocURL)
        check(chapters.count == 80, "漫画：目录章节数（\(chapters.count)）")
        check(chapters.first?.title == "第1话 重生", "漫画：第一章标题")
        check(chapters.first?.url == "https://comic.mkzcdn.com/chapter/content/?chapter_id=476064&comic_id=207622",
              "漫画：章节地址 @get:{comic_id} + 模板混用（实际 \(chapters.first?.url ?? "nil")）")
        check(chapters.last?.url.contains("comic_id=207622") == true, "漫画：所有章节都带 comic_id")
        let updateTime = chapters.first?.updateTime ?? ""
        check(updateTime.contains("🕗") && updateTime.contains("2017/"),
              "漫画：updateTime 的 java.timeFormat（实际 \(updateTime)）")

        // 7. 正文解析：图片规则 + JS 包装成 <img>，再按原版方式取地址
        let contentBody = try fixture("manga-content.json")
        let contentURL = "https://comic.mkzcdn.com/chapter/content/?chapter_id=476064&comic_id=207622"
        let contentRule = source.ruleContent ?? ContentRule()
        let contentChapter = BookChapter(url: contentURL, title: "第1话 重生", index: 0)
        let contentAnalyzer = AnalyzeRule(content: contentBody, baseUrl: contentURL,
                                          jsLib: source.jsLib,
                                          context: RuleContext(source: source, book: book, chapter: contentChapter))
        let content = contentAnalyzer.getString(contentRule.content)
        check(content.contains("<img src=\"http://oss.mkzcdn.com/"), "漫画：正文 JS 把图片地址包成 img 标签")
        let urls = MangaBook.imageURLs(in: content, baseURL: contentURL)
        check(urls.count == 14, "漫画：正文图片数量（\(urls.count)）")
        check(urls.first == "http://oss.mkzcdn.com/image/20220420/625f8325dbfde-800x1168.jpg",
              "漫画：第一张图片地址")
    }
}
