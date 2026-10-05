//
//  WebBookPublicAPITests.swift
//  LegadoBookSource
//
//  第 7 步 A 段：流程层纯 public 接口测试（普通 import，非 @testable）。
//  验证对外 API 可见性完整，外部调用方无需 @testable 即可完成搜索/详情/目录/正文/调试。
//  全部为合成书源规则 + 合成 HTML（非真实站点）。
//

import XCTest
import LegadoBookSource

final class WebBookPublicAPITests: XCTestCase {

    private func basicSource(searchUrl: String = "http://synthetic.test/search") -> BookSource {
        BookSource(
            bookSourceUrl: "http://synthetic.test",
            bookSourceName: "synthetic_public",
            searchUrl: searchUrl,
            ruleSearch: SearchRule(
                bookList: "class.item",
                name: "tag.h3@tag.a@text",
                author: "class.author@text",
                bookUrl: "tag.h3@tag.a@href"
            ),
            ruleBookInfo: BookInfoRule(name: "tag.h1@text"),
            ruleToc: TocRule(chapterList: "class.chapters@tag.li", chapterName: "tag.a@text", chapterUrl: "tag.a@href"),
            ruleContent: ContentRule(content: "class.content@html")
        )
    }

    private let searchHtml = """
    <html><body><div class="list"><div class="item"><h3><a href="http://synthetic.test/book/1">书名一</a></h3><p class="author">作者甲</p></div></div></body></html>
    """

    func testPublicSearchBookAwait() async throws {
        let net = MockWebBookNetwork(["http://synthetic.test/search": WebBookResponse(url: "http://synthetic.test/search", status: 200, body: searchHtml)])
        let opts = WebBookOptions(network: net)
        let result = try await WebBook.searchBookAwait(bookSource: basicSource(), key: "斗罗", options: opts)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].name, "书名一")
        XCTAssertEqual(result[0].author, "作者甲")
    }

    func testPublicGetBookInfoAwait() async throws {
        let html = "<html><body><h1>书名一</h1></body></html>"
        let net = MockWebBookNetwork(["http://synthetic.test/book/1": WebBookResponse(url: "http://synthetic.test/book/1", status: 200, body: html)])
        let opts = WebBookOptions(network: net)
        var book = Book(bookUrl: "http://synthetic.test/book/1", origin: "http://synthetic.test")
        _ = try await WebBook.getBookInfoAwait(bookSource: basicSource(), book: &book, options: opts)
        XCTAssertEqual(book.name, "书名一")
    }

    func testPublicGetChapterListAwait() async throws {
        let html = "<html><body><div class=\"chapters\"><li><a href=\"http://synthetic.test/c/1\">第一章</a></li></div></body></html>"
        let net = MockWebBookNetwork(["http://synthetic.test/toc/1": WebBookResponse(url: "http://synthetic.test/toc/1", status: 200, body: html)])
        let opts = WebBookOptions(network: net)
        var book = Book(bookUrl: "http://synthetic.test/book/1", tocUrl: "http://synthetic.test/toc/1", origin: "http://synthetic.test")
        let chapters = try await WebBook.getChapterListAwait(bookSource: basicSource(), book: &book, options: opts)
        XCTAssertEqual(chapters.count, 1)
        XCTAssertEqual(chapters[0].title, "第一章")
    }

    func testPublicGetContentAwait() async throws {
        let html = "<html><body><div class=\"content\">正文内容</div></body></html>"
        let net = MockWebBookNetwork(["http://synthetic.test/c/1": WebBookResponse(url: "http://synthetic.test/c/1", status: 200, body: html)])
        let opts = WebBookOptions(network: net)
        let book = Book(bookUrl: "http://synthetic.test/book/1", tocUrl: "http://synthetic.test/toc/1", origin: "http://synthetic.test")
        let chapter = BookChapter(url: "http://synthetic.test/c/1", title: "第一章")
        let content = try await WebBook.getContentAwait(bookSource: basicSource(), book: book, bookChapter: chapter, options: opts)
        XCTAssertTrue(content.contains("正文内容"))
    }

    func testPublicDebugStartDebug() async throws {
        let net = MockWebBookNetwork(["http://synthetic.test/search": WebBookResponse(url: "http://synthetic.test/search", status: 200, body: searchHtml)])
        let logger = DebugLogger()
        let opts = WebBookOptions(logger: logger, network: net)
        // Debug.startDebug 为 async 且不抛错；此处仅验证可调用、不崩溃。
        await Debug.startDebug(bookSource: basicSource(), key: "斗罗", options: opts)
    }
}
