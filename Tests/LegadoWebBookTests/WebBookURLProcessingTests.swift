//
//  WebBookURLProcessingTests.swift
//  LegadoBookSource
//
//  第 7 步 A 段：流程层 URL 处理（搜索/发现地址里的 {{key}}/{{page}} 替换、相对地址、POST options）。
//  全部为合成书源规则（非真实站点）。
//

import XCTest
@testable import LegadoBookSource

final class WebBookURLProcessingTests: XCTestCase {

    private func source(searchUrl: String) -> BookSource {
        BookSource(
            bookSourceUrl: "http://synthetic.test",
            bookSourceName: "synthetic_url",
            searchUrl: searchUrl,
            ruleSearch: SearchRule(bookList: "class.item", name: "tag.h3@tag.a@text", bookUrl: "tag.h3@tag.a@href"),
            ruleBookInfo: BookInfoRule(name: "tag.h1@text"),
            ruleToc: TocRule(chapterList: "class.chapters@tag.li", chapterName: "tag.a@text", chapterUrl: "tag.a@href"),
            ruleContent: ContentRule(content: "class.content@html")
        )
    }

    private let searchHtml = "<html><body><div class=\"list\"><div class=\"item\"><h3><a href=\"http://synthetic.test/book/1\">书名</a></h3></div></div></body></html>"

    func testSearchUrlKeyPlaceholderReplaced() async throws {
        let src = source(searchUrl: "http://synthetic.test/search?q={{key}}")
        let net = MockWebBookNetwork(["http://synthetic.test/search?q=doupo": WebBookResponse(url: "http://synthetic.test/search?q=doupo", status: 200, body: searchHtml)])
        let opts = WebBookOptions(network: net)
        let result = try await WebBook.searchBookAwait(bookSource: src, key: "doupo", options: opts)
        XCTAssertEqual(result.count, 1)
    }

    func testSearchUrlPagePlaceholderReplaced() async throws {
        let src = source(searchUrl: "http://synthetic.test/search?p={{page}}")
        let net = MockWebBookNetwork(["http://synthetic.test/search?p=2": WebBookResponse(url: "http://synthetic.test/search?p=2", status: 200, body: searchHtml)])
        let opts = WebBookOptions(network: net)
        let result = try await WebBook.searchBookAwait(bookSource: src, key: "doupo", page: 2, options: opts)
        XCTAssertEqual(result.count, 1)
    }

    func testExploreUrlPagePlaceholderReplaced() async throws {
        let src = BookSource(
            bookSourceUrl: "http://synthetic.test",
            bookSourceName: "synthetic_exp_page",
            exploreUrl: "http://synthetic.test/exp?page={{page}}",
            ruleExplore: ExploreRule(bookList: "class.item", name: "tag.a@text", bookUrl: "tag.a@href"),
            ruleToc: TocRule(chapterList: "class.chapters@tag.li", chapterName: "tag.a@text", chapterUrl: "tag.a@href"),
            ruleContent: ContentRule(content: "class.content@html")
        )
        let net = MockWebBookNetwork(["http://synthetic.test/exp?page=3": WebBookResponse(url: "http://synthetic.test/exp?page=3", status: 200, body: searchHtml)])
        let opts = WebBookOptions(network: net)
        let result = try await WebBook.exploreBookAwait(bookSource: src, url: "http://synthetic.test/exp?page={{page}}", page: 3, options: opts)
        XCTAssertEqual(result.count, 1)
    }

    func testSearchUrlMissingThrows() async {
        let src = BookSource(
            bookSourceUrl: "http://synthetic.test",
            bookSourceName: "synthetic_no_search",
            ruleSearch: SearchRule(bookList: "class.item"),
            ruleToc: TocRule(chapterList: "class.chapters@tag.li", chapterName: "tag.a@text", chapterUrl: "tag.a@href"),
            ruleContent: ContentRule(content: "class.content@html")
        )
        let opts = WebBookOptions(network: MockWebBookNetwork([:]))
        do {
            _ = try await WebBook.searchBookAwait(bookSource: src, key: "x", options: opts)
            XCTFail("searchUrl 为空应抛错")
        } catch { /* 期望失败 */ }
    }

    func testRelativeChapterUrlResolvedAgainstTocUrl() async throws {
        let html = "<html><body><div class=\"chapters\"><li><a href=\"/c/1\">第一章</a></li></div></body></html>"
        let src = BookSource(
            bookSourceUrl: "http://synthetic.test",
            bookSourceName: "synthetic_rel_chapter",
            ruleToc: TocRule(chapterList: "class.chapters@tag.li", chapterName: "tag.a@text", chapterUrl: "tag.a@href"),
            ruleContent: ContentRule(content: "class.content@html")
        )
        let net = MockWebBookNetwork(["http://synthetic.test/toc/1": WebBookResponse(url: "http://synthetic.test/toc/1", status: 200, body: html)])
        let opts = WebBookOptions(network: net)
        var book = Book(bookUrl: "http://synthetic.test/book/1", tocUrl: "http://synthetic.test/toc/1", origin: "http://synthetic.test")
        let chapters = try await WebBook.getChapterListAwait(bookSource: src, book: &book, options: opts)
        XCTAssertEqual(chapters.count, 1)
        XCTAssertEqual(chapters[0].url, "http://synthetic.test/c/1")
    }

    func testContentNextPageTerminatesAtNextChapter() async throws {
        // 正文下一页 == 下一章链接时终止循环（不抓取下一章正文）
        let p1 = "<html><body><div class=\"content\">第一页</div><div class=\"next\"><a href=\"http://synthetic.test/c/2\">下一章</a></div></body></html>"
        let src = BookSource(
            bookSourceUrl: "http://synthetic.test",
            bookSourceName: "synthetic_term",
            ruleToc: TocRule(chapterList: "class.chapters@tag.li", chapterName: "tag.a@text", chapterUrl: "tag.a@href"),
            ruleContent: ContentRule(content: "class.content@html", nextContentUrl: "class.next@tag.a@href")
        )
        let net = MockWebBookNetwork(["http://synthetic.test/c/1": WebBookResponse(url: "http://synthetic.test/c/1", status: 200, body: p1)])
        let opts = WebBookOptions(network: net)
        let book = Book(bookUrl: "http://synthetic.test/book/1", tocUrl: "http://synthetic.test/toc/1", origin: "http://synthetic.test")
        let chapter = BookChapter(url: "http://synthetic.test/c/1", title: "第一章")
        let content = try await WebBook.getContentAwait(bookSource: src, book: book, bookChapter: chapter, nextChapterUrl: "http://synthetic.test/c/2", options: opts)
        XCTAssertTrue(content.contains("第一页"))
        XCTAssertFalse(content.contains("下一章正文"))
    }
}
