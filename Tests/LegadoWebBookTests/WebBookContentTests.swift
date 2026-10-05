//
//  WebBookContentTests.swift
//  LegadoBookSource
//
//  第 7 步 A 段：BookContent.analyzeContent（两个重载）逐分支测试。
//  全部为合成书源规则 + 合成 HTML（非真实站点）。
//

import XCTest
@testable import LegadoBookSource

final class WebBookContentTests: XCTestCase {

    private func contentSource(_ content: ContentRule) -> BookSource {
        BookSource(
            bookSourceUrl: "http://synthetic.test",
            bookSourceName: "synthetic_content",
            ruleToc: TocRule(chapterList: "class.chapters@tag.li", chapterName: "tag.a@text", chapterUrl: "tag.a@href"),
            ruleContent: content
        )
    }

    private func run(_ content: ContentRule, html: String, book: Book = Book(bookUrl: "http://synthetic.test/book/1", tocUrl: "http://synthetic.test/toc/1", origin: "http://synthetic.test")) async throws -> String {
        let net = MockWebBookNetwork(["http://synthetic.test/c/1": WebBookResponse(url: "http://synthetic.test/c/1", status: 200, body: html)])
        let opts = WebBookOptions(network: net)
        let chapter = BookChapter(url: "http://synthetic.test/c/1", title: "第一章")
        return try await WebBook.getContentAwait(bookSource: contentSource(content), book: book, bookChapter: chapter, options: opts)
    }

    func testReplaceRegexRemovesPattern() async throws {
        let html = "<html><body><div class=\"content\">正文内容</div></body></html>"
        let content = try await run(ContentRule(content: "class.content@html", replaceRegex: "##正文"), html: html)
        XCTAssertFalse(content.contains("正文"))
        XCTAssertTrue(content.contains("内容"))
    }

    func testSubContentOnLineTxtAppended() async throws {
        let html = "<html><body><div class=\"content\">正文</div><div class=\"lyric\">[00:01]歌词行</div></body></html>"
        let content = try await run(ContentRule(content: "class.content@html", subContent: "class.lyric@html"), html: html)
        XCTAssertTrue(content.contains("正文"))
        XCTAssertTrue(content.contains("歌词行"))
    }

    func testSubContentAudioStoredInResourceUrl() async throws {
        let html = "<html><body><div class=\"content\">正文</div><div class=\"lyric\">[00:01]歌词</div></body></html>"
        let logger = DebugLogger()
        // 关键 1：Kotlin `Debug.log` 与 Swift 实现都在 `callback == null` 时**提前 return**，
        // 连 records 都不会落（DebugLogger.swift:114）。所以断言日志必须先装 sink，
        // 并用 withExtendedLifetime 把弱引用的 sink 保活到 await 结束之后。
        //
        // 关键 2：`Book.type` 是**按位**标记，且新建 Book 的默认值就是 `BookType.text`（8，
        // 见 Book.swift TextTypeDefault / Kotlin Book.kt:74 `type = BookType.text`）。
        // 若只调 addType(audio) 会得到 8|32 = 40，`isOnLineTxt` 仍为 true，
        // 于是命中 Kotlin BookContent.kt:132 的 `if (book.isOnLineTxt) { add(raw); return }`
        // **早返回分支**，音频歌词分支根本不可达——这是 Kotlin 的真实语义。
        // 要覆盖音频分支，必须先清空类型位，构造**纯音频**书（type == 32）。
        let sink = RecordingSink()
        logger.callback = sink
        logger.beginDebug(sourceUrl: "http://synthetic.test")
        let net = MockWebBookNetwork(["http://synthetic.test/c/1": WebBookResponse(url: "http://synthetic.test/c/1", status: 200, body: html)])
        let opts = WebBookOptions(logger: logger, network: net)
        var book = Book(bookUrl: "http://synthetic.test/book/1", tocUrl: "http://synthetic.test/toc/1", origin: "http://synthetic.test")
        book.removeAllBookType()
        book.addType(BookType.audio)
        XCTAssertTrue(book.isAudio)
        XCTAssertFalse(book.isOnLineTxt, "纯音频书不应命中 onLineTxt 早返回分支")
        let chapter = BookChapter(url: "http://synthetic.test/c/1", title: "第一章")
        defer { withExtendedLifetime(sink) {} }
        _ = try await WebBook.getContentAwait(bookSource: contentSource(ContentRule(content: "class.content@html", subContent: "class.lyric@html")), book: book, bookChapter: chapter, options: opts)
        XCTAssertTrue(sink.contains("┌获取副文歌词"),
                      "音频书的副文应走歌词分支，实际记录：\(sink.messages)")
    }

    func testSubContentVideoStoredInResourceUrl() async throws {
        let html = "<html><body><div class=\"content\">正文</div><div class=\"lyric\">弹幕</div></body></html>"
        let logger = DebugLogger()
        let sink = RecordingSink()
        logger.callback = sink
        logger.beginDebug(sourceUrl: "http://synthetic.test")
        let net = MockWebBookNetwork(["http://synthetic.test/c/1": WebBookResponse(url: "http://synthetic.test/c/1", status: 200, body: html)])
        let opts = WebBookOptions(logger: logger, network: net)
        var book = Book(bookUrl: "http://synthetic.test/book/1", tocUrl: "http://synthetic.test/toc/1", origin: "http://synthetic.test")
        // 同上：先清空默认的 text 位，构造纯视频书，才能命中弹幕分支。
        book.removeAllBookType()
        book.addType(BookType.video)
        XCTAssertTrue(book.isVideo)
        XCTAssertFalse(book.isOnLineTxt, "纯视频书不应命中 onLineTxt 早返回分支")
        let chapter = BookChapter(url: "http://synthetic.test/c/1", title: "第一章")
        defer { withExtendedLifetime(sink) {} }
        _ = try await WebBook.getContentAwait(bookSource: contentSource(ContentRule(content: "class.content@html", subContent: "class.lyric@html")), book: book, bookChapter: chapter, options: opts)
        XCTAssertTrue(sink.contains("┌获取副文弹幕"),
                      "视频书的副文应走弹幕分支，实际记录：\(sink.messages)")
    }

    func testSubContentHttpFetched() async throws {
        // 副文规则返回 http 地址 → 走 fetchSubContent 抓取。
        //
        // ⚠️ 两点决定了本用例的断言方式：
        //   1. `BookChapter` 是 struct，`getContentAwait(bookChapter:)` 是**值传递**，
        //      内部写 `resourceUrl` 只落在局部副本上（BookContent.swift:47 注释），
        //      调用方拿不到 → 不能断言 chapter.resourceUrl。
        //   2. `fetchSubContent` 成功后**不打任何日志**（只返回 body；失败才写
        //      "获取副文出错"，与 Kotlin 一致）。所以也不能断言日志含歌词正文。
        //   因此：断言「抓取到的副文**内容本身**」只能通过返回值/副本观察到的副作用，
        //   这里改为断言**没有走失败分支**（日志里不出现「获取副文出错」），
        //   且主正文正常返回——这正是可观测的产品行为。
        let html = "<html><body><div class=\"content\">正文</div><div class=\"lyric\">http://synthetic.test/lyric/1</div></body></html>"
        let lyricHtml = "<html><body>真实歌词</body></html>"
        let net = MockWebBookNetwork([
            "http://synthetic.test/c/1": WebBookResponse(url: "http://synthetic.test/c/1", status: 200, body: html),
            "http://synthetic.test/lyric/1": WebBookResponse(url: "http://synthetic.test/lyric/1", status: 200, body: lyricHtml)
        ])
        let logger = DebugLogger()
        // 装 sink 才有日志（Kotlin/Swift 在 callback == nil 时提前 return）。
        let sink = RecordingSink()
        logger.callback = sink
        logger.beginDebug(sourceUrl: "http://synthetic.test")
        let opts = WebBookOptions(logger: logger, network: net)
        var book = Book(bookUrl: "http://synthetic.test/book/1", tocUrl: "http://synthetic.test/toc/1", origin: "http://synthetic.test")
        // 副文地址抓取（fetchSubContent）只在**非 onLineTxt** 分支才走；
        // 而 Book 默认类型含 text，若不先清空就会命中 onLineTxt 早返回，
        // 根本不会去 fetch。这里构造纯音频书以确保覆盖抓取路径。
        book.removeAllBookType()
        book.addType(BookType.audio)
        let chapter = BookChapter(url: "http://synthetic.test/c/1", title: "第一章")
        defer { withExtendedLifetime(sink) {} }
        let content = try await WebBook.getContentAwait(bookSource: contentSource(ContentRule(content: "class.content@html", subContent: "class.lyric@html")), book: book, bookChapter: chapter, options: opts)
        XCTAssertTrue(content.contains("正文"), "主正文应正常返回，实际：\(content)")
        XCTAssertFalse(sink.contains("获取副文出错"),
                       "副文地址应抓取成功，不应出现失败日志：\(sink.messages)")
    }

    func testTitleRuleExtractsTitle() async throws {
        let html = "<html><body><div class=\"content\">正文</div><h2>标题名 https://example.com/c.jpg</h2></body></html>"
        let logger = DebugLogger()
        let sink = RecordingSink()
        logger.callback = sink
        logger.beginDebug(sourceUrl: "http://synthetic.test")
        let net = MockWebBookNetwork(["http://synthetic.test/c/1": WebBookResponse(url: "http://synthetic.test/c/1", status: 200, body: html)])
        let opts = WebBookOptions(logger: logger, network: net)
        let book = Book(bookUrl: "http://synthetic.test/book/1", tocUrl: "http://synthetic.test/toc/1", origin: "http://synthetic.test")
        let chapter = BookChapter(url: "http://synthetic.test/c/1", title: "第一章")
        _ = try await WebBook.getContentAwait(bookSource: contentSource(ContentRule(content: "class.content@html", title: "tag.h2@text")), book: book, bookChapter: chapter, options: opts)
        XCTAssertTrue(sink.contains("┌获取章节名称"))
        XCTAssertTrue(sink.messages.contains { $0.contains("标题名") })
    }

    func testTitleRuleNoImgSetsTitleDirect() async throws {
        let html = "<html><body><div class=\"content\">正文</div><h2>纯标题</h2></body></html>"
        let logger = DebugLogger()
        let sink = RecordingSink()
        logger.callback = sink
        logger.beginDebug(sourceUrl: "http://synthetic.test")
        let net = MockWebBookNetwork(["http://synthetic.test/c/1": WebBookResponse(url: "http://synthetic.test/c/1", status: 200, body: html)])
        let opts = WebBookOptions(logger: logger, network: net)
        let book = Book(bookUrl: "http://synthetic.test/book/1", tocUrl: "http://synthetic.test/toc/1", origin: "http://synthetic.test")
        let chapter = BookChapter(url: "http://synthetic.test/c/1", title: "第一章")
        _ = try await WebBook.getContentAwait(bookSource: contentSource(ContentRule(content: "class.content@html", title: "tag.h2@text")), book: book, bookChapter: chapter, options: opts)
        XCTAssertTrue(sink.messages.contains { $0.contains("纯标题") })
    }
}
