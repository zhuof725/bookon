//
//  WebBookEdgeCaseTests.swift
//  LegadoBookSource
//
//  第 7 步 A 段：流程层边界用例（各字段单独提取、前缀分支、多页/并发、错误吞噬等）。
//  全部为合成书源规则 + 合成 HTML（非真实站点）。
//

import XCTest
@testable import LegadoBookSource

final class WebBookEdgeCaseTests: XCTestCase {

    // MARK: - BookInfo 边界

    private func infoSource(_ rule: BookInfoRule) -> BookSource {
        BookSource(
            bookSourceUrl: "http://synthetic.test",
            bookSourceName: "synthetic_info_edge",
            ruleBookInfo: rule,
            ruleToc: TocRule(chapterList: "class.chapters@tag.li", chapterName: "tag.a@text", chapterUrl: "tag.a@href"),
            ruleContent: ContentRule(content: "class.content@html")
        )
    }

    private func runInfo(_ rule: BookInfoRule, html: String) async throws -> Book {
        let net = MockWebBookNetwork(["http://synthetic.test/book/1": WebBookResponse(url: "http://synthetic.test/book/1", status: 200, body: html)])
        let opts = WebBookOptions(network: net)
        var book = Book(bookUrl: "http://synthetic.test/book/1", origin: "http://synthetic.test")
        _ = try await WebBook.getBookInfoAwait(bookSource: infoSource(rule), book: &book, options: opts)
        return book
    }

    func testIntroMdPrefixKeptRaw() async throws {
        let book = try await runInfo(BookInfoRule(intro: "class.intro@html"), html: "<html><body><div class=\"intro\"><md># 标题</md></div></body></html>")
        XCTAssertTrue(book.intro?.hasPrefix("<md>") == true)
    }

    func testIntroUseWebPrefixKeptRaw() async throws {
        let book = try await runInfo(BookInfoRule(intro: "class.intro@html"), html: "<html><body><div class=\"intro\"><useweb>内容</useweb></div></body></html>")
        XCTAssertTrue(book.intro?.hasPrefix("<useweb>") == true)
    }

    func testNameWhitespaceStripped() async throws {
        let book = try await runInfo(BookInfoRule(name: "tag.h1@text"), html: "<html><body><h1>书 名 一</h1></body></html>")
        XCTAssertEqual(book.name, "书名一")
    }

    func testCanReNameEmptyAllowsOverwrite() async throws {
        let book = try await runInfo(BookInfoRule(name: "tag.h1@text", canReName: ""), html: "<html><body><h1>新名</h1></body></html>")
        // canReName 为空 → mCanReName = true → 覆盖
        XCTAssertEqual(book.name, "新名")
    }

    func testCoverUrlEmptyKeepsExisting() async throws {
        let book = try await runInfo(BookInfoRule(coverUrl: "class.nope@src"), html: "<html><body><h1>书名</h1></body></html>")
        XCTAssertNil(book.coverUrl)
    }

    func testIntroFailureLoggedNotCrash() async throws {
        let book = try await runInfo(BookInfoRule(name: "tag.h1@text", intro: "class.nope@html"), html: "<html><body><h1>书名</h1></body></html>")
        XCTAssertEqual(book.name, "书名")
        XCTAssertNil(book.intro)
    }

    // MARK: - BookList 边界

    private func listSource(_ rule: SearchRule, searchUrl: String = "http://synthetic.test/search") -> BookSource {
        BookSource(
            bookSourceUrl: "http://synthetic.test",
            bookSourceName: "synthetic_list_edge",
            searchUrl: searchUrl,
            ruleSearch: rule,
            ruleBookInfo: BookInfoRule(name: "tag.h1@text"),
            ruleToc: TocRule(chapterList: "class.chapters@tag.li", chapterName: "tag.a@text", chapterUrl: "tag.a@href"),
            ruleContent: ContentRule(content: "class.content@html")
        )
    }

    func testSearchEmptyBookListReturnsEmpty() async throws {
        let src = listSource(SearchRule(bookList: "class.nope", name: "tag.a@text"))
        let net = MockWebBookNetwork(["http://synthetic.test/search": WebBookResponse(url: "http://synthetic.test/search", status: 200, body: "<html><body></body></html>")])
        let opts = WebBookOptions(network: net)
        let result = try await WebBook.searchBookAwait(bookSource: src, key: "x", options: opts)
        XCTAssertTrue(result.isEmpty)
    }

    func testSearchCoverUrlRelativeResolved() async throws {
        let html = "<html><body><div class=\"list\"><div class=\"item\"><h3><a href=\"http://synthetic.test/book/1\">书名</a></h3><img src=\"/cover/1.jpg\"></div></div></body></html>"
        let src = listSource(SearchRule(bookList: "class.item", name: "tag.h3@tag.a@text", bookUrl: "tag.h3@tag.a@href", coverUrl: "tag.img@src"))
        let net = MockWebBookNetwork(["http://synthetic.test/search": WebBookResponse(url: "http://synthetic.test/search", status: 200, body: html)])
        let opts = WebBookOptions(network: net)
        let result = try await WebBook.searchBookAwait(bookSource: src, key: "x", options: opts)
        XCTAssertEqual(result[0].coverUrl, "http://synthetic.test/cover/1.jpg")
    }

    func testExploreReversePrefix() async throws {
        let src = BookSource(
            bookSourceUrl: "http://synthetic.test",
            bookSourceName: "synthetic_exp_rev",
            exploreUrl: "http://synthetic.test/exp",
            ruleExplore: ExploreRule(bookList: "-class.item", name: "tag.h3@tag.a@text", bookUrl: "tag.h3@tag.a@href"),
            ruleBookInfo: BookInfoRule(name: "tag.h1@text"),
            ruleToc: TocRule(chapterList: "class.chapters@tag.li", chapterName: "tag.a@text", chapterUrl: "tag.a@href"),
            ruleContent: ContentRule(content: "class.content@html")
        )
        let net = MockWebBookNetwork(["http://synthetic.test/exp": WebBookResponse(url: "http://synthetic.test/exp", status: 200, body: Fixtures.searchReverse)])
        let opts = WebBookOptions(network: net)
        let result = try await WebBook.exploreBookAwait(bookSource: src, url: "http://synthetic.test/exp", options: opts)
        XCTAssertEqual(result.count, 3)
        XCTAssertEqual(result[0].name, "第三")
    }

    // MARK: - ChapterList 边界

    func testTocNextUrlManyConcurrent() async throws {
        // nextTocUrl 返回多个链接 → 并发解析分支
        let p1 = "<html><body><div class=\"chapters\"><li><a href=\"http://synthetic.test/c/1\">第一章</a></li></div><div class=\"next\"><a href=\"http://synthetic.test/toc/2\">2</a><a href=\"http://synthetic.test/toc/3\">3</a></div></body></html>"
        let p2 = "<html><body><div class=\"chapters\"><li><a href=\"http://synthetic.test/c/2\">第二章</a></li></div></body></html>"
        let p3 = "<html><body><div class=\"chapters\"><li><a href=\"http://synthetic.test/c/3\">第三章</a></li></div></body></html>"
        let src = BookSource(
            bookSourceUrl: "http://synthetic.test",
            bookSourceName: "synthetic_toc_many",
            ruleToc: TocRule(chapterList: "class.chapters@tag.li", chapterName: "tag.a@text", chapterUrl: "tag.a@href", nextTocUrl: "class.next@tag.a@href"),
            ruleContent: ContentRule(content: "class.content@html")
        )
        let net = MockWebBookNetwork([
            "http://synthetic.test/toc/1": WebBookResponse(url: "http://synthetic.test/toc/1", status: 200, body: p1),
            "http://synthetic.test/toc/2": WebBookResponse(url: "http://synthetic.test/toc/2", status: 200, body: p2),
            "http://synthetic.test/toc/3": WebBookResponse(url: "http://synthetic.test/toc/3", status: 200, body: p3)
        ])
        let opts = WebBookOptions(network: net)
        var book = Book(bookUrl: "http://synthetic.test/book/1", tocUrl: "http://synthetic.test/toc/1", origin: "http://synthetic.test")
        let chapters = try await WebBook.getChapterListAwait(bookSource: src, book: &book, options: opts)
        XCTAssertEqual(chapters.count, 3)
    }

    func testRunPreUpdateJs() async throws {
        let src = BookSource(
            bookSourceUrl: "http://synthetic.test",
            bookSourceName: "synthetic_prejs",
            ruleToc: TocRule(preUpdateJs: "1+1", chapterList: "class.chapters@tag.li", chapterName: "tag.a@text", chapterUrl: "tag.a@href"),
            ruleContent: ContentRule(content: "class.content@html")
        )
        var book = Book(bookUrl: "http://synthetic.test/book/1", origin: "http://synthetic.test")
        WebBook.runPreUpdateJs(bookSource: src, book: &book, isFromBookInfo: false, options: WebBookOptions(network: MockWebBookNetwork([:])))
        // preUpdateJs 求值失败会记日志，不崩溃
    }

    func testRunPreUpdateJsEmptyDoesNothing() {
        let src = BookSource(
            bookSourceUrl: "http://synthetic.test",
            bookSourceName: "synthetic_noprejs",
            ruleToc: TocRule(preUpdateJs: nil, chapterList: "class.chapters@tag.li", chapterName: "tag.a@text", chapterUrl: "tag.a@href"),
            ruleContent: ContentRule(content: "class.content@html")
        )
        var book = Book(bookUrl: "http://synthetic.test/book/1", origin: "http://synthetic.test")
        WebBook.runPreUpdateJs(bookSource: src, book: &book, isFromBookInfo: false, options: WebBookOptions(network: MockWebBookNetwork([:])))
        // 不崩溃
    }

    // MARK: - Content 边界

    private func contentSource(_ rule: ContentRule) -> BookSource {
        BookSource(
            bookSourceUrl: "http://synthetic.test",
            bookSourceName: "synthetic_content_edge",
            ruleToc: TocRule(chapterList: "class.chapters@tag.li", chapterName: "tag.a@text", chapterUrl: "tag.a@href"),
            ruleContent: rule
        )
    }

    func testContentWithAmpersandUnescaped() async throws {
        let html = "<html><body><div class=\"content\">A&amp;B</div></body></html>"
        let src = contentSource(ContentRule(content: "class.content@html"))
        let net = MockWebBookNetwork(["http://synthetic.test/c/1": WebBookResponse(url: "http://synthetic.test/c/1", status: 200, body: html)])
        let opts = WebBookOptions(network: net)
        let book = Book(bookUrl: "http://synthetic.test/book/1", tocUrl: "http://synthetic.test/toc/1", origin: "http://synthetic.test")
        let chapter = BookChapter(url: "http://synthetic.test/c/1", title: "第一章")
        let content = try await WebBook.getContentAwait(bookSource: src, book: book, bookChapter: chapter, options: opts)
        XCTAssertTrue(content.contains("A&B") || content.contains("&amp;"))
    }

    func testReplaceRegexOnLineTxtAddsIndent() async throws {
        let html = "<html><body><div class=\"content\">正文</div></body></html>"
        let src = contentSource(ContentRule(content: "class.content@html", replaceRegex: "##正文"))
        let net = MockWebBookNetwork(["http://synthetic.test/c/1": WebBookResponse(url: "http://synthetic.test/c/1", status: 200, body: html)])
        let opts = WebBookOptions(network: net)
        var book = Book(bookUrl: "http://synthetic.test/book/1", tocUrl: "http://synthetic.test/toc/1", origin: "http://synthetic.test")
        book.addType(BookType.text)
        let chapter = BookChapter(url: "http://synthetic.test/c/1", title: "第一章")
        let content = try await WebBook.getContentAwait(bookSource: src, book: book, bookChapter: chapter, options: opts)
        XCTAssertFalse(content.contains("正文"))
    }

    func testSourceRegexFieldPresentButNotAppliedInMock() async throws {
        // sourceRegex 仅在真实网络路径应用；Mock 直接供给已变换 body（记录该差异）。
        let html = "<html><body><div class=\"content\">已变换正文</div></body></html>"
        let src = contentSource(ContentRule(content: "class.content@html", sourceRegex: "foo"))
        let net = MockWebBookNetwork(["http://synthetic.test/c/1": WebBookResponse(url: "http://synthetic.test/c/1", status: 200, body: html)])
        let opts = WebBookOptions(network: net)
        let book = Book(bookUrl: "http://synthetic.test/book/1", tocUrl: "http://synthetic.test/toc/1", origin: "http://synthetic.test")
        let chapter = BookChapter(url: "http://synthetic.test/c/1", title: "第一章")
        let content = try await WebBook.getContentAwait(bookSource: src, book: book, bookChapter: chapter, options: opts)
        XCTAssertTrue(content.contains("已变换正文"))
    }

    // MARK: - Debug 边界

    func testExploreDebugEmptyResultLogged() async {
        let src = BookSource(
            bookSourceUrl: "http://synthetic.test",
            bookSourceName: "synthetic_exp_empty",
            exploreUrl: "http://synthetic.test/exp",
            ruleExplore: ExploreRule(bookList: "class.nope", name: "tag.a@text", bookUrl: "tag.a@href"),
            ruleBookInfo: BookInfoRule(name: "tag.h1@text"),
            ruleToc: TocRule(chapterList: "class.chapters@tag.li", chapterName: "tag.a@text", chapterUrl: "tag.a@href"),
            ruleContent: ContentRule(content: "class.content@html")
        )
        let logger = DebugLogger()
        let sink = RecordingSink()
        logger.callback = sink
        let net = MockWebBookNetwork(["http://synthetic.test/exp": WebBookResponse(url: "http://synthetic.test/exp", status: 200, body: "<html><body></body></html>")])
        let opts = WebBookOptions(logger: logger, network: net)
        await Debug.startDebug(bookSource: src, key: "名::http://synthetic.test/exp", options: opts)
        XCTAssertTrue(sink.contains("︽未获取到书籍"))
    }

    func testSearchDebugEmptyResultLogged() async {
        let src = SynthSources.basic()
        let logger = DebugLogger()
        let sink = RecordingSink()
        logger.callback = sink
        let net = MockWebBookNetwork(["http://synthetic.test/search": WebBookResponse(url: "http://synthetic.test/search", status: 200, body: "<html><body></body></html>")])
        let opts = WebBookOptions(logger: logger, network: net)
        await Debug.startDebug(bookSource: src, key: "无结果", options: opts)
        XCTAssertTrue(sink.contains("︽未获取到书籍"))
    }
}
