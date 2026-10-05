//
//  WebBookChapterListTests.swift
//  LegadoBookSource
//
//  第 7 步 A 段：BookChapterList.analyzeChapterList（两个重载）+ upChapterInfo 逐分支测试。
//  全部为合成书源规则 + 合成 HTML（非真实站点）。
//

import XCTest
@testable import LegadoBookSource

final class WebBookChapterListTests: XCTestCase {

    private func tocSource(toc: TocRule) -> BookSource {
        BookSource(
            bookSourceUrl: "http://synthetic.test",
            bookSourceName: "synthetic_toc",
            ruleToc: toc,
            ruleContent: ContentRule(content: "class.content@html")
        )
    }

    private func run(toc: TocRule, html: String, url: String = "http://synthetic.test/toc/1") async throws -> [BookChapter] {
        let net = MockWebBookNetwork([url: WebBookResponse(url: url, status: 200, body: html)])
        let opts = WebBookOptions(network: net)
        var book = Book(bookUrl: "http://synthetic.test/book/1", tocUrl: url, origin: "http://synthetic.test")
        return try await WebBook.getChapterListAwait(bookSource: tocSource(toc: toc), book: &book, options: opts)
    }

    func testIsVipAndIsPay() async throws {
        let html = """
        <html><body><div class="chapters">
        <li><a href="http://synthetic.test/c/1">第一章</a><span class="vip">true</span><span class="pay">1</span></li>
        <li><a href="http://synthetic.test/c/2">第二章</a><span class="vip">false</span><span class="pay">0</span></li>
        </div></body></html>
        """
        let toc = TocRule(chapterList: "class.chapters@tag.li", chapterName: "tag.a@text", chapterUrl: "tag.a@href",
                          isVip: "class.vip@text", isPay: "class.pay@text")
        let chapters = try await run(toc: toc, html: html)
        XCTAssertEqual(chapters.count, 2)
        XCTAssertTrue(chapters[0].isVip)
        XCTAssertTrue(chapters[0].isPay)
        XCTAssertFalse(chapters[1].isVip)
        XCTAssertFalse(chapters[1].isPay)
    }

    func testIsVolumeWithUpdateTime() async throws {
        let html = """
        <html><body><div class="chapters">
        <li><a href="http://synthetic.test/v/1">第一卷</a><span class="vol">true</span><span class="time">2024-01-01</span></li>
        </div></body></html>
        """
        let toc = TocRule(chapterList: "class.chapters@tag.li", chapterName: "tag.a@text", chapterUrl: "tag.a@href",
                          isVolume: "class.vol@text", updateTime: "class.time@text")
        let chapters = try await run(toc: toc, html: html)
        XCTAssertEqual(chapters.count, 1)
        XCTAssertTrue(chapters[0].isVolume)
        XCTAssertEqual(chapters[0].tag, "2024-01-01")
    }

    func testUpdateTimeAsTagWhenNotVolume() async throws {
        let html = """
        <html><body><div class="chapters">
        <li><a href="http://synthetic.test/c/1">第一章</a><span class="vol">false</span><span class="time">2024-02-02</span></li>
        </div></body></html>
        """
        let toc = TocRule(chapterList: "class.chapters@tag.li", chapterName: "tag.a@text", chapterUrl: "tag.a@href",
                          isVolume: "class.vol@text", updateTime: "class.time@text")
        let chapters = try await run(toc: toc, html: html)
        XCTAssertEqual(chapters.count, 1)
        XCTAssertFalse(chapters[0].isVolume)
        XCTAssertEqual(chapters[0].tag, "2024-02-02")
    }

    func testFormatJsIdentity() async throws {
        let html = """
        <html><body><div class="chapters">
        <li><a href="http://synthetic.test/c/1">第一章</a></li>
        </div></body></html>
        """
        let toc = TocRule(chapterList: "class.chapters@tag.li", chapterName: "tag.a@text", chapterUrl: "tag.a@href",
                          formatJs: "title")
        let chapters = try await run(toc: toc, html: html)
        XCTAssertEqual(chapters.count, 1)
        XCTAssertEqual(chapters[0].title, "第一章")
    }

    func testTocUsesTocHtmlWhenBookUrlEqualsTocUrl() async throws {
        let html = Fixtures.tocBasic
        let toc = TocRule(chapterList: "class.chapters@tag.li", chapterName: "tag.a@text", chapterUrl: "tag.a@href")
        let src = tocSource(toc: toc)
        let net = MockWebBookNetwork([:])
        let opts = WebBookOptions(network: net)
        var book = Book(bookUrl: "http://synthetic.test/toc/1", tocUrl: "http://synthetic.test/toc/1", origin: "http://synthetic.test")
        book.tocHtml = html
        let chapters = try await WebBook.getChapterListAwait(bookSource: src, book: &book, options: opts)
        XCTAssertEqual(chapters.count, 3)
    }

    func testDedupByUrl() async throws {
        let html = """
        <html><body><div class="chapters">
        <li><a href="http://synthetic.test/c/1">第一章</a></li>
        <li><a href="http://synthetic.test/c/1">第一章重复</a></li>
        </div></body></html>
        """
        let toc = TocRule(chapterList: "class.chapters@tag.li", chapterName: "tag.a@text", chapterUrl: "tag.a@href")
        let chapters = try await run(toc: toc, html: html)
        XCTAssertEqual(chapters.count, 1)
    }

    func testChapterWithoutUrlUsesBaseUrl() async throws {
        let html = """
        <html><body><div class="chapters">
        <li><a>无链接章节</a></li>
        </div></body></html>
        """
        let toc = TocRule(chapterList: "class.chapters@tag.li", chapterName: "tag.a@text", chapterUrl: "tag.a@href")
        let chapters = try await run(toc: toc, html: html)
        XCTAssertEqual(chapters.count, 1)
        XCTAssertEqual(chapters[0].url, "http://synthetic.test/toc/1")
    }

    func testEmptyTitleChapterSkipped() async throws {
        let html = """
        <html><body><div class="chapters">
        <li><a href="http://synthetic.test/c/1"></a></li>
        <li><a href="http://synthetic.test/c/2">第二章</a></li>
        </div></body></html>
        """
        let toc = TocRule(chapterList: "class.chapters@tag.li", chapterName: "tag.a@text", chapterUrl: "tag.a@href")
        let chapters = try await run(toc: toc, html: html)
        XCTAssertEqual(chapters.count, 1)
        XCTAssertEqual(chapters[0].title, "第二章")
    }
}
