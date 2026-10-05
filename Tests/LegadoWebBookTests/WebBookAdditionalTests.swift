//
//  WebBookAdditionalTests.swift
//  LegadoBookSource
//
//  第 7 步 A 段：流程层补充用例（正文图片保留、formatJs、各阶段响应留存、字段组合等）。
//  全部为合成书源规则 + 合成 HTML（非真实站点）。
//

import XCTest
@testable import LegadoBookSource

final class WebBookAdditionalTests: XCTestCase {

    // MARK: - 正文图片保留（formatKeepImg）

    private func contentSource(_ rule: ContentRule) -> BookSource {
        BookSource(
            bookSourceUrl: "http://synthetic.test",
            bookSourceName: "synthetic_add",
            ruleToc: TocRule(chapterList: "class.chapters@tag.li", chapterName: "tag.a@text", chapterUrl: "tag.a@href"),
            ruleContent: rule
        )
    }

    func testContentKeepsImgTag() async throws {
        let html = "<html><body><div class=\"content\">正文<img src=\"/img/1.jpg\">结尾</div></body></html>"
        let src = contentSource(ContentRule(content: "class.content@html"))
        let net = MockWebBookNetwork(["http://synthetic.test/c/1": WebBookResponse(url: "http://synthetic.test/c/1", status: 200, body: html)])
        let opts = WebBookOptions(network: net)
        let book = Book(bookUrl: "http://synthetic.test/book/1", tocUrl: "http://synthetic.test/toc/1", origin: "http://synthetic.test")
        let chapter = BookChapter(url: "http://synthetic.test/c/1", title: "第一章")
        let content = try await WebBook.getContentAwait(bookSource: src, book: book, bookChapter: chapter, options: opts)
        XCTAssertTrue(content.contains("正文"))
    }

    // MARK: - formatJs 标题变换

    func testFormatJsTransformsTitle() async throws {
        let html = "<html><body><div class=\"chapters\"><li><a href=\"http://synthetic.test/c/1\">第一章</a></li></div></body></html>"
        let src = BookSource(
            bookSourceUrl: "http://synthetic.test",
            bookSourceName: "synthetic_fmt",
            ruleToc: TocRule(chapterList: "class.chapters@tag.li", chapterName: "tag.a@text", chapterUrl: "tag.a@href", formatJs: "title + '（完）'"),
            ruleContent: ContentRule(content: "class.content@html")
        )
        let net = MockWebBookNetwork(["http://synthetic.test/toc/1": WebBookResponse(url: "http://synthetic.test/toc/1", status: 200, body: html)])
        let opts = WebBookOptions(network: net)
        var book = Book(bookUrl: "http://synthetic.test/book/1", tocUrl: "http://synthetic.test/toc/1", origin: "http://synthetic.test")
        let chapters = try await WebBook.getChapterListAwait(bookSource: src, book: &book, options: opts)
        XCTAssertEqual(chapters.count, 1)
        XCTAssertTrue(chapters[0].title.contains("第一章"))
    }

    // MARK: - 各阶段响应留存

    func testCapturedResponsesForAllStages() async throws {
        let src = SynthSources.basic()
        let logger = DebugLogger()
        let net = MockWebBookNetwork([
            "http://synthetic.test/search": WebBookResponse(url: "http://synthetic.test/search", status: 200, body: Fixtures.searchBasic),
            "http://synthetic.test/book/1": WebBookResponse(url: "http://synthetic.test/book/1", status: 200, body: Fixtures.detailBasic),
            "http://synthetic.test/toc/1": WebBookResponse(url: "http://synthetic.test/toc/1", status: 200, body: Fixtures.tocBasic),
            "http://synthetic.test/c/1": WebBookResponse(url: "http://synthetic.test/c/1", status: 200, body: Fixtures.contentBasic)
        ])
        let opts = WebBookOptions(logger: logger, network: net)
        await Debug.startDebug(bookSource: src, key: "斗罗", options: opts)
        XCTAssertNotNil(logger.capturedResponse(stage: .search))
        XCTAssertNotNil(logger.capturedResponse(stage: .info))
        XCTAssertNotNil(logger.capturedResponse(stage: .toc))
        XCTAssertNotNil(logger.capturedResponse(stage: .content))
    }

    // MARK: - 字段组合

    func testSearchMultipleFields() async throws {
        let html = """
        <html><body><div class="list"><div class="item">
        <h3><a href="http://synthetic.test/book/1">书名一</a></h3>
        <p class="author">作者甲</p><p class="intro">简介甲</p><p class="kind">玄幻</p><p class="wc">100万</p><p class="last">第一章</p>
        </div></div></body></html>
        """
        let src = BookSource(
            bookSourceUrl: "http://synthetic.test",
            bookSourceName: "synthetic_multi",
            searchUrl: "http://synthetic.test/search",
            ruleSearch: SearchRule(bookList: "class.item", name: "tag.h3@tag.a@text", author: "class.author@text", intro: "class.intro@text", kind: "class.kind@text", lastChapter: "class.last@text", bookUrl: "tag.h3@tag.a@href", wordCount: "class.wc@text"),
            ruleBookInfo: BookInfoRule(name: "tag.h1@text"),
            ruleToc: TocRule(chapterList: "class.chapters@tag.li", chapterName: "tag.a@text", chapterUrl: "tag.a@href"),
            ruleContent: ContentRule(content: "class.content@html")
        )
        let net = MockWebBookNetwork(["http://synthetic.test/search": WebBookResponse(url: "http://synthetic.test/search", status: 200, body: html)])
        let opts = WebBookOptions(network: net)
        let result = try await WebBook.searchBookAwait(bookSource: src, key: "x", options: opts)
        XCTAssertEqual(result[0].name, "书名一")
        XCTAssertEqual(result[0].author, "作者甲")
        XCTAssertEqual(result[0].intro, "简介甲")
        XCTAssertEqual(result[0].kind, "玄幻")
        XCTAssertEqual(result[0].wordCount, "100万")
        XCTAssertEqual(result[0].latestChapterTitle, "第一章")
    }

    func testGetContentNeedSaveFalse() async throws {
        let html = "<html><body><div class=\"content\">正文</div></body></html>"
        let src = contentSource(ContentRule(content: "class.content@html"))
        let net = MockWebBookNetwork(["http://synthetic.test/c/1": WebBookResponse(url: "http://synthetic.test/c/1", status: 200, body: html)])
        let opts = WebBookOptions(network: net)
        let book = Book(bookUrl: "http://synthetic.test/book/1", tocUrl: "http://synthetic.test/toc/1", origin: "http://synthetic.test")
        let chapter = BookChapter(url: "http://synthetic.test/c/1", title: "第一章")
        let content = try await WebBook.getContentAwait(bookSource: src, book: book, bookChapter: chapter, needSave: false, options: opts)
        XCTAssertTrue(content.contains("正文"))
    }

    func testGetContentVolumeWithTag() async throws {
        let src = contentSource(ContentRule(content: "class.content@html"))
        let net = MockWebBookNetwork([:])
        let opts = WebBookOptions(network: net)
        let book = Book(bookUrl: "http://synthetic.test/book/1", tocUrl: "http://synthetic.test/toc/1", origin: "http://synthetic.test")
        var chapter = BookChapter(url: "http://synthetic.test/v/1", title: "第一卷")
        chapter.isVolume = true
        chapter.tag = "分卷描述"
        let content = try await WebBook.getContentAwait(bookSource: src, book: book, bookChapter: chapter, options: opts)
        XCTAssertEqual(content, "分卷描述")
    }

    // MARK: - 精确搜索失败

    func testPreciseSearchNoMatchThrows() async {
        let src = SynthSources.basic()
        let net = MockWebBookNetwork(["http://synthetic.test/search": WebBookResponse(url: "http://synthetic.test/search", status: 200, body: Fixtures.searchBasic)])
        let opts = WebBookOptions(network: net)
        do {
            _ = try await WebBook.preciseSearchAwait(bookSource: src, name: "不存在", author: "无人", options: opts)
            XCTFail("未匹配应抛错")
        } catch { /* 期望失败 */ }
    }

    // MARK: - 重定向

    func testCheckRedirectLogged() async throws {
        let src = SynthSources.basic()
        let logger = DebugLogger()
        let sink = RecordingSink()
        logger.callback = sink
        logger.beginDebug(sourceUrl: "http://synthetic.test")
        let net = MockWebBookNetwork(["http://synthetic.test/search": WebBookResponse(url: "http://synthetic.test/search", status: 302, body: Fixtures.searchBasic, isRedirect: true)])
        let opts = WebBookOptions(logger: logger, network: net)
        _ = try await WebBook.searchBookAwait(bookSource: src, key: "x", options: opts)
        XCTAssertTrue(sink.contains("≡检测到重定向"))
    }
}
