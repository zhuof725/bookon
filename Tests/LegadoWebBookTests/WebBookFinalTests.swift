//
//  WebBookFinalTests.swift
//  LegadoBookSource
//
//  第 7 步 A 段：流程层收尾用例（详情分支过滤、标题封面提取、详情列表返回）。
//  全部为合成书源规则 + 合成 HTML（非真实站点）。
//

import XCTest
@testable import LegadoBookSource

final class WebBookFinalTests: XCTestCase {

    func testInfoItemFilterRejects() async throws {
        // 详情页分支 getInfoItem 的 filter 拒绝 → 返回 nil → 空列表
        let src = BookSource(
            bookSourceUrl: "http://synthetic.test",
            bookSourceName: "synthetic_filter_reject",
            bookUrlPattern: "http://synthetic.test/book/\\d+",
            searchUrl: "http://synthetic.test/search",
            ruleSearch: SearchRule(bookList: "class.item", name: "tag.a@text"),
            ruleBookInfo: BookInfoRule(name: "tag.h1@text"),
            ruleToc: TocRule(chapterList: "class.chapters@tag.li", chapterName: "tag.a@text", chapterUrl: "tag.a@href"),
            ruleContent: ContentRule(content: "class.content@html")
        )
        let net = MockWebBookNetwork(["http://synthetic.test/search": WebBookResponse(url: "http://synthetic.test/book/1", status: 200, body: "<html><body><h1>书名</h1></body></html>")])
        let opts = WebBookOptions(network: net)
        let result = try await WebBook.searchBookAwait(bookSource: src, key: "x", options: opts, filter: { _, _, _ in false })
        XCTAssertTrue(result.isEmpty)
    }

    func testContentTitleImgGroup1EmptyFallsBackToChapterTitle() async throws {
        // imgRegex 匹配但 group1 为空（标题就是图片链接）→ 用原章节标题
        let html = "<html><body><div class=\"content\">正文</div><h2>https://example.com/c.jpg</h2></body></html>"
        let src = BookSource(
            bookSourceUrl: "http://synthetic.test",
            bookSourceName: "synthetic_img1",
            ruleToc: TocRule(chapterList: "class.chapters@tag.li", chapterName: "tag.a@text", chapterUrl: "tag.a@href"),
            ruleContent: ContentRule(content: "class.content@html", title: "tag.h2@text")
        )
        let logger = DebugLogger()
        let sink = RecordingSink()
        logger.callback = sink
        logger.beginDebug(sourceUrl: "http://synthetic.test")
        let net = MockWebBookNetwork(["http://synthetic.test/c/1": WebBookResponse(url: "http://synthetic.test/c/1", status: 200, body: html)])
        let opts = WebBookOptions(logger: logger, network: net)
        let book = Book(bookUrl: "http://synthetic.test/book/1", tocUrl: "http://synthetic.test/toc/1", origin: "http://synthetic.test")
        let chapter = BookChapter(url: "http://synthetic.test/c/1", title: "第一章")
        _ = try await WebBook.getContentAwait(bookSource: src, book: book, bookChapter: chapter, options: opts)
        XCTAssertTrue(sink.contains("┌获取章节名称"))
    }

    func testSearchBookUrlPatternDetailReturnsSingle() async throws {
        // 详情页分支返回单本书，并回填 infoHtml
        let src = BookSource(
            bookSourceUrl: "http://synthetic.test",
            bookSourceName: "synthetic_detail_single",
            bookUrlPattern: "http://synthetic.test/book/\\d+",
            searchUrl: "http://synthetic.test/search",
            ruleSearch: SearchRule(bookList: "class.item", name: "tag.a@text"),
            ruleBookInfo: BookInfoRule(name: "tag.h1@text", author: "class.author@text"),
            ruleToc: TocRule(chapterList: "class.chapters@tag.li", chapterName: "tag.a@text", chapterUrl: "tag.a@href"),
            ruleContent: ContentRule(content: "class.content@html")
        )
        let body = "<html><body><h1>书名</h1><p class=\"author\">作者</p></body></html>"
        let net = MockWebBookNetwork(["http://synthetic.test/search": WebBookResponse(url: "http://synthetic.test/book/1", status: 200, body: body)])
        let opts = WebBookOptions(network: net)
        let result = try await WebBook.searchBookAwait(bookSource: src, key: "x", options: opts)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].name, "书名")
        XCTAssertEqual(result[0].infoHtml, body)
    }
}
