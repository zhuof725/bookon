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
        let sink = RecordingSink()
        logger.callback = sink
        logger.beginDebug(sourceUrl: "http://synthetic.test")
        let net = MockWebBookNetwork(["http://synthetic.test/c/1": WebBookResponse(url: "http://synthetic.test/c/1", status: 200, body: html)])
        let opts = WebBookOptions(logger: logger, network: net)
        var book = Book(bookUrl: "http://synthetic.test/book/1", tocUrl: "http://synthetic.test/toc/1", origin: "http://synthetic.test")
        book.addType(BookType.audio)
        let chapter = BookChapter(url: "http://synthetic.test/c/1", title: "第一章")
        _ = try await WebBook.getContentAwait(bookSource: contentSource(ContentRule(content: "class.content@html", subContent: "class.lyric@html")), book: book, bookChapter: chapter, options: opts)
        XCTAssertTrue(sink.contains("┌获取副文歌词"))
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
        book.addType(BookType.video)
        let chapter = BookChapter(url: "http://synthetic.test/c/1", title: "第一章")
        _ = try await WebBook.getContentAwait(bookSource: contentSource(ContentRule(content: "class.content@html", subContent: "class.lyric@html")), book: book, bookChapter: chapter, options: opts)
        XCTAssertTrue(sink.contains("┌获取副文弹幕"))
    }

    func testSubContentHttpFetched() async throws {
        // 副文规则返回 http 地址 → 走 fetchSubContent 抓取
        let html = "<html><body><div class=\"content\">正文</div><div class=\"lyric\">http://synthetic.test/lyric/1</div></body></html>"
        let lyricHtml = "<html><body>真实歌词</body></html>"
        let net = MockWebBookNetwork([
            "http://synthetic.test/c/1": WebBookResponse(url: "http://synthetic.test/c/1", status: 200, body: html),
            "http://synthetic.test/lyric/1": WebBookResponse(url: "http://synthetic.test/lyric/1", status: 200, body: lyricHtml)
        ])
        let opts = WebBookOptions(network: net)
        let logger = opts.logger
        let sink = RecordingSink()
        logger.callback = sink
        logger.beginDebug(sourceUrl: "http://synthetic.test")
        let book = Book(bookUrl: "http://synthetic.test/book/1", tocUrl: "http://synthetic.test/toc/1", origin: "http://synthetic.test")
        let chapter = BookChapter(url: "http://synthetic.test/c/1", title: "第一章")
        _ = try await WebBook.getContentAwait(bookSource: contentSource(ContentRule(content: "class.content@html", subContent: "class.lyric@html")), book: book, bookChapter: chapter, options: opts)
        XCTAssertTrue(sink.contains("真实歌词"))
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
