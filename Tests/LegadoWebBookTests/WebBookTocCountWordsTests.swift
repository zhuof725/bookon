//
//  WebBookTocCountWordsTests.swift
//  LegadoBookSource
//
//  第 7 步 A 段：FlowConfig.tocCountWords / adaptSpecialStyle 与章节字数提取等补充分支。
//  全部为合成书源规则 + 合成 HTML（非真实站点）。
//

import XCTest
@testable import LegadoBookSource

final class WebBookTocCountWordsTests: XCTestCase {

    override func tearDown() {
        FlowConfig.tocCountWords = false
        FlowConfig.adaptSpecialStyle = false
        super.tearDown()
    }

    func testTocCountWordsExtractsWordCount() async throws {
        FlowConfig.tocCountWords = true
        let html = "<html><body><div class=\"chapters\"><li><a href=\"http://synthetic.test/c/1\">第一章</a><span class=\"time\">字数：1234字</span></li></div></body></html>"
        let src = BookSource(
            bookSourceUrl: "http://synthetic.test",
            bookSourceName: "synthetic_tcw",
            ruleToc: TocRule(chapterList: "class.chapters@tag.li", chapterName: "tag.a@text", chapterUrl: "tag.a@href", updateTime: "class.time@text"),
            ruleContent: ContentRule(content: "class.content@html")
        )
        let net = MockWebBookNetwork(["http://synthetic.test/toc/1": WebBookResponse(url: "http://synthetic.test/toc/1", status: 200, body: html)])
        let opts = WebBookOptions(network: net)
        var book = Book(bookUrl: "http://synthetic.test/book/1", tocUrl: "http://synthetic.test/toc/1", origin: "http://synthetic.test")
        let chapters = try await WebBook.getChapterListAwait(bookSource: src, book: &book, options: opts)
        XCTAssertEqual(chapters.count, 1)
        XCTAssertNotNil(chapters[0].wordCount)
    }

    func testTocCountWordsDefaultOffNoWordCount() async throws {
        let html = "<html><body><div class=\"chapters\"><li><a href=\"http://synthetic.test/c/1\">第一章</a><span class=\"time\">字数：1234字</span></li></div></body></html>"
        let src = BookSource(
            bookSourceUrl: "http://synthetic.test",
            bookSourceName: "synthetic_tcw_off",
            ruleToc: TocRule(chapterList: "class.chapters@tag.li", chapterName: "tag.a@text", chapterUrl: "tag.a@href", updateTime: "class.time@text"),
            ruleContent: ContentRule(content: "class.content@html")
        )
        let net = MockWebBookNetwork(["http://synthetic.test/toc/1": WebBookResponse(url: "http://synthetic.test/toc/1", status: 200, body: html)])
        let opts = WebBookOptions(network: net)
        var book = Book(bookUrl: "http://synthetic.test/book/1", tocUrl: "http://synthetic.test/toc/1", origin: "http://synthetic.test")
        let chapters = try await WebBook.getChapterListAwait(bookSource: src, book: &book, options: opts)
        XCTAssertEqual(chapters.count, 1)
        XCTAssertNil(chapters[0].wordCount)
        XCTAssertEqual(chapters[0].tag, "字数：1234字")
    }

    func testVolumeChapterUrlWithTitlePrefix() async throws {
        // 一级目录章节：isVolume 且 url 以 title 开头 → 不解析正文规则
        let src = BookSource(
            bookSourceUrl: "http://synthetic.test",
            bookSourceName: "synthetic_vol_prefix",
            ruleToc: TocRule(chapterList: "class.chapters@tag.li", chapterName: "tag.a@text", chapterUrl: "tag.a@href", isVolume: "class.vol@text"),
            ruleContent: ContentRule(content: "class.content@html")
        )
        let net = MockWebBookNetwork([:])
        let opts = WebBookOptions(network: net)
        let book = Book(bookUrl: "http://synthetic.test/book/1", tocUrl: "http://synthetic.test/toc/1", origin: "http://synthetic.test")
        var chapter = BookChapter(url: "第一卷xxx", title: "第一卷")
        chapter.isVolume = true
        chapter.tag = "卷描述"
        let content = try await WebBook.getContentAwait(bookSource: src, book: book, bookChapter: chapter, options: opts)
        XCTAssertEqual(content, "卷描述")
    }

    func testBookInfoWithInitBlankSkipped() async throws {
        let html = "<html><body><h1>书名</h1></body></html>"
        let src = BookSource(
            bookSourceUrl: "http://synthetic.test",
            bookSourceName: "synthetic_init_blank",
            ruleBookInfo: BookInfoRule(init: "", name: "tag.h1@text"),
            ruleToc: TocRule(chapterList: "class.chapters@tag.li", chapterName: "tag.a@text", chapterUrl: "tag.a@href"),
            ruleContent: ContentRule(content: "class.content@html")
        )
        let net = MockWebBookNetwork(["http://synthetic.test/book/1": WebBookResponse(url: "http://synthetic.test/book/1", status: 200, body: html)])
        let opts = WebBookOptions(network: net)
        var book = Book(bookUrl: "http://synthetic.test/book/1", origin: "http://synthetic.test")
        _ = try await WebBook.getBookInfoAwait(bookSource: src, book: &book, options: opts)
        XCTAssertEqual(book.name, "书名")
    }

    func testBookInfoKindEmptyNotSet() async throws {
        let html = "<html><body><h1>书名</h1></body></html>"
        let src = BookSource(
            bookSourceUrl: "http://synthetic.test",
            bookSourceName: "synthetic_kind_empty",
            ruleBookInfo: BookInfoRule(name: "tag.h1@text", kind: "class.kind@text"),
            ruleToc: TocRule(chapterList: "class.chapters@tag.li", chapterName: "tag.a@text", chapterUrl: "tag.a@href"),
            ruleContent: ContentRule(content: "class.content@html")
        )
        let net = MockWebBookNetwork(["http://synthetic.test/book/1": WebBookResponse(url: "http://synthetic.test/book/1", status: 200, body: html)])
        let opts = WebBookOptions(network: net)
        var book = Book(bookUrl: "http://synthetic.test/book/1", origin: "http://synthetic.test")
        _ = try await WebBook.getBookInfoAwait(bookSource: src, book: &book, options: opts)
        XCTAssertNil(book.kind)
    }

    func testChapterListNextTocUrlEmpty() async throws {
        // nextTocUrl 规则存在但页面无下一页 → 单页目录
        let html = "<html><body><div class=\"chapters\"><li><a href=\"http://synthetic.test/c/1\">第一章</a></li></div></body></html>"
        let src = BookSource(
            bookSourceUrl: "http://synthetic.test",
            bookSourceName: "synthetic_next_empty",
            ruleToc: TocRule(chapterList: "class.chapters@tag.li", chapterName: "tag.a@text", chapterUrl: "tag.a@href", nextTocUrl: "class.next@tag.a@href"),
            ruleContent: ContentRule(content: "class.content@html")
        )
        let net = MockWebBookNetwork(["http://synthetic.test/toc/1": WebBookResponse(url: "http://synthetic.test/toc/1", status: 200, body: html)])
        let opts = WebBookOptions(network: net)
        var book = Book(bookUrl: "http://synthetic.test/book/1", tocUrl: "http://synthetic.test/toc/1", origin: "http://synthetic.test")
        let chapters = try await WebBook.getChapterListAwait(bookSource: src, book: &book, options: opts)
        XCTAssertEqual(chapters.count, 1)
    }

    func testDebugInfoDebugSkipToTocWhenTocUrlPresent() async {
        // startDebug 详情页分支：book.tocUrl 非空 → 跳过详情页，直接目录
        let src = SynthSources.basic()
        let logger = DebugLogger()
        let sink = RecordingSink()
        logger.callback = sink
        let net = MockWebBookNetwork(["http://synthetic.test/toc/1": WebBookResponse(url: "http://synthetic.test/toc/1", status: 200, body: Fixtures.tocBasic)])
        let opts = WebBookOptions(logger: logger, network: net)
        await Debug.startDebug(bookSource: src, key: "++http://synthetic.test/toc/1", options: opts)
        XCTAssertTrue(sink.contains("⇒开始访目录页"))
    }

    func testDebugContentFinishedState() async {
        let src = SynthSources.basic()
        let logger = DebugLogger()
        let sink = RecordingSink()
        logger.callback = sink
        let net = MockWebBookNetwork(["http://synthetic.test/c/1": WebBookResponse(url: "http://synthetic.test/c/1", status: 200, body: Fixtures.contentBasic)])
        let opts = WebBookOptions(logger: logger, network: net)
        await Debug.startDebug(bookSource: src, key: "--http://synthetic.test/c/1", options: opts)
        XCTAssertTrue(sink.states.contains(DebugLogState.finished))
    }

    func testContentEmptyBodyNilThrows() async {
        let src = SynthSources.basic()
        let net = MockWebBookNetwork([:])
        let opts = WebBookOptions(network: net)
        let book = Book(bookUrl: "http://synthetic.test/book/1", tocUrl: "http://synthetic.test/toc/1", origin: "http://synthetic.test")
        let chapter = BookChapter(url: "http://synthetic.test/c/1", title: "第一章")
        do {
            _ = try await WebBook.getContentAwait(bookSource: src, book: book, bookChapter: chapter, options: opts)
            XCTFail("正文获取失败应抛错")
        } catch { /* 期望失败 */ }
    }

    func testChapterListBodyNilThrows() async {
        let src = SynthSources.basic()
        let net = MockWebBookNetwork([:])
        let opts = WebBookOptions(network: net)
        var book = Book(bookUrl: "http://synthetic.test/book/1", tocUrl: "http://synthetic.test/toc/1", origin: "http://synthetic.test")
        do {
            _ = try await WebBook.getChapterListAwait(bookSource: src, book: &book, options: opts)
            XCTFail("目录获取失败应抛错")
        } catch { /* 期望失败 */ }
    }

    func testBookInfoBodyNilThrows() async {
        let src = SynthSources.basic()
        let net = MockWebBookNetwork([:])
        let opts = WebBookOptions(network: net)
        var book = Book(bookUrl: "http://synthetic.test/book/1", origin: "http://synthetic.test")
        do {
            _ = try await WebBook.getBookInfoAwait(bookSource: src, book: &book, options: opts)
            XCTFail("详情获取失败应抛错")
        } catch { /* 期望失败 */ }
    }

    func testSearchNetworkErrorThrows() async {
        let src = SynthSources.basic()
        let net = MockWebBookNetwork([:])
        let opts = WebBookOptions(network: net)
        do {
            _ = try await WebBook.searchBookAwait(bookSource: src, key: "x", options: opts)
            XCTFail("网络失败应抛错")
        } catch { /* 期望失败 */ }
    }

    func testSearchMissingBookUrlPatternDetailBranchEmpty() async throws {
        // bookUrlPattern 命中但 getInfoItem 返回 nil → 空列表
        let src = BookSource(
            bookSourceUrl: "http://synthetic.test",
            bookSourceName: "synthetic_pattern_nil",
            bookUrlPattern: "http://synthetic.test/book/\\d+",
            searchUrl: "http://synthetic.test/search",
            ruleSearch: SearchRule(bookList: "class.item", name: "tag.a@text"),
            ruleBookInfo: BookInfoRule(name: "tag.none@text"),
            ruleToc: TocRule(chapterList: "class.chapters@tag.li", chapterName: "tag.a@text", chapterUrl: "tag.a@href"),
            ruleContent: ContentRule(content: "class.content@html")
        )
        let net = MockWebBookNetwork(["http://synthetic.test/search": WebBookResponse(url: "http://synthetic.test/book/1", status: 200, body: "<html><body><h1>书名</h1></body></html>")])
        let opts = WebBookOptions(network: net)
        let result = try await WebBook.searchBookAwait(bookSource: src, key: "x", options: opts)
        XCTAssertTrue(result.isEmpty)
    }

    func testExploreMissingUrlThrowsOnEmptyResult() async throws {
        // 发现页返回空列表 → exploreBookAwait 返回空（不抛错）
        let src = BookSource(
            bookSourceUrl: "http://synthetic.test",
            bookSourceName: "synthetic_exp_empty2",
            exploreUrl: "http://synthetic.test/exp",
            ruleExplore: ExploreRule(bookList: "class.nope", name: "tag.a@text", bookUrl: "tag.a@href"),
            ruleBookInfo: BookInfoRule(name: "tag.h1@text"),
            ruleToc: TocRule(chapterList: "class.chapters@tag.li", chapterName: "tag.a@text", chapterUrl: "tag.a@href"),
            ruleContent: ContentRule(content: "class.content@html")
        )
        let net = MockWebBookNetwork(["http://synthetic.test/exp": WebBookResponse(url: "http://synthetic.test/exp", status: 200, body: "<html><body></body></html>")])
        let opts = WebBookOptions(network: net)
        let result = try await WebBook.exploreBookAwait(bookSource: src, url: "http://synthetic.test/exp", options: opts)
        XCTAssertTrue(result.isEmpty)
    }
}
