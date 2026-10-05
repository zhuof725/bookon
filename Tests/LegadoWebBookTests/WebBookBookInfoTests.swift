//
//  WebBookBookInfoTests.swift
//  LegadoBookSource
//
//  第 7 步 A 段：BookInfo.analyzeBookInfo（两个重载）逐字段与逐分支测试。
//  全部为合成书源规则 + 合成 HTML（非真实站点）。
//

import XCTest
@testable import LegadoBookSource

final class WebBookBookInfoTests: XCTestCase {

    private func infoSource(bookInfo: BookInfoRule) -> BookSource {
        BookSource(
            bookSourceUrl: "http://synthetic.test",
            bookSourceName: "synthetic_info",
            ruleBookInfo: bookInfo,
            ruleToc: TocRule(chapterList: "class.chapters@tag.li", chapterName: "tag.a@text", chapterUrl: "tag.a@href"),
            ruleContent: ContentRule(content: "class.content@html")
        )
    }

    private func options(_ body: String, url: String = "http://synthetic.test/book/1") -> WebBookOptions {
        let net = MockWebBookNetwork([url: WebBookResponse(url: url, status: 200, body: body)])
        return WebBookOptions(network: net)
    }

    private func makeBook(_ url: String = "http://synthetic.test/book/1") -> Book {
        Book(bookUrl: url, origin: "http://synthetic.test")
    }

    func testNameFormatRemovesBrackets() async throws {
        let html = "<html><body><h1>《书名（完本）》</h1></body></html>"
        let src = infoSource(bookInfo: BookInfoRule(name: "tag.h1@text"))
        let opts = options(html)
        var book = makeBook()
        _ = try await WebBook.getBookInfoAwait(bookSource: src, book: &book, options: opts)
        XCTAssertEqual(book.name, "书名")
    }

    func testNameEmptyDoesNotOverwriteWhenCanReNameFalse() async throws {
        let html = "<html><body><h1>新名</h1></body></html>"
        let src = infoSource(bookInfo: BookInfoRule(name: "tag.h1@text", canReName: "0"))
        let opts = options(html)
        var book = makeBook()
        book.name = "旧名"
        _ = try await WebBook.getBookInfoAwait(bookSource: src, book: &book, options: opts)
        // canReName 规则非空 → mCanReName=false；书名为非空 → 不覆盖
        XCTAssertEqual(book.name, "旧名")
    }

    func testNameOverwriteWhenEmpty() async throws {
        let html = "<html><body><h1>新名</h1></body></html>"
        let src = infoSource(bookInfo: BookInfoRule(name: "tag.h1@text"))
        let opts = options(html)
        var book = makeBook()
        book.name = ""
        _ = try await WebBook.getBookInfoAwait(bookSource: src, book: &book, options: opts)
        XCTAssertEqual(book.name, "新名")
    }

    func testAuthorExtraction() async throws {
        let html = "<html><body><p class=\"author\">作者甲</p></body></html>"
        let src = infoSource(bookInfo: BookInfoRule(author: "class.author@text"))
        let opts = options(html)
        var book = makeBook()
        _ = try await WebBook.getBookInfoAwait(bookSource: src, book: &book, options: opts)
        XCTAssertEqual(book.author, "作者甲")
    }

    func testKindExtraction() async throws {
        let html = "<html><body><p class=\"kind\">玄幻</p></body></html>"
        let src = infoSource(bookInfo: BookInfoRule(kind: "class.kind@text"))
        let opts = options(html)
        var book = makeBook()
        _ = try await WebBook.getBookInfoAwait(bookSource: src, book: &book, options: opts)
        XCTAssertEqual(book.kind, "玄幻")
    }

    func testWordCountExtraction() async throws {
        let html = "<html><body><p class=\"wc\">100万字</p></body></html>"
        let src = infoSource(bookInfo: BookInfoRule(wordCount: "class.wc@text"))
        let opts = options(html)
        var book = makeBook()
        _ = try await WebBook.getBookInfoAwait(bookSource: src, book: &book, options: opts)
        XCTAssertEqual(book.wordCount, "100万字")
    }

    func testLastChapterExtraction() async throws {
        let html = "<html><body><p class=\"last\">最新章</p></body></html>"
        let src = infoSource(bookInfo: BookInfoRule(lastChapter: "class.last@text"))
        let opts = options(html)
        var book = makeBook()
        _ = try await WebBook.getBookInfoAwait(bookSource: src, book: &book, options: opts)
        XCTAssertEqual(book.latestChapterTitle, "最新章")
    }

    func testIntroNormalUsesHtmlFormatter() async throws {
        let html = "<html><body><p class=\"intro\">简介<b>加粗</b></p></body></html>"
        let src = infoSource(bookInfo: BookInfoRule(intro: "class.intro@html"))
        let opts = options(html)
        var book = makeBook()
        _ = try await WebBook.getBookInfoAwait(bookSource: src, book: &book, options: opts)
        XCTAssertTrue(book.intro?.isEmpty == false)
    }

    func testIntroUseHtmlPrefixKeptRaw() async throws {
        let html = "<html><body><p class=\"intro\"><usehtml>原始片段</usehtml></p></body></html>"
        let src = infoSource(bookInfo: BookInfoRule(intro: "class.intro@html"))
        let opts = options(html)
        var book = makeBook()
        _ = try await WebBook.getBookInfoAwait(bookSource: src, book: &book, options: opts)
        XCTAssertTrue(book.intro?.hasPrefix("<usehtml>") == true)
    }

    func testCoverUrlAbsolute() async throws {
        let html = "<html><body><img src=\"/cover/1.jpg\"></body></html>"
        let src = infoSource(bookInfo: BookInfoRule(coverUrl: "tag.img@src"))
        let opts = options(html)
        var book = makeBook()
        _ = try await WebBook.getBookInfoAwait(bookSource: src, book: &book, options: opts)
        XCTAssertEqual(book.coverUrl, "http://synthetic.test/cover/1.jpg")
    }

    func testTocUrlAbsolute() async throws {
        let html = "<html><body><div class=\"toc\"><a href=\"/toc/1\">目录</a></div></body></html>"
        let src = infoSource(bookInfo: BookInfoRule(tocUrl: "class.toc@tag.a@href"))
        let opts = options(html)
        var book = makeBook()
        _ = try await WebBook.getBookInfoAwait(bookSource: src, book: &book, options: opts)
        XCTAssertEqual(book.tocUrl, "http://synthetic.test/toc/1")
    }

    func testTocUrlEmptyFallsBackToBaseUrl() async throws {
        let html = "<html><body><div class=\"toc\"></div></body></html>"
        let src = infoSource(bookInfo: BookInfoRule(tocUrl: "class.toc@tag.a@href"))
        let opts = options(html)
        var book = makeBook()
        book.tocUrl = ""
        _ = try await WebBook.getBookInfoAwait(bookSource: src, book: &book, options: opts)
        XCTAssertEqual(book.tocUrl, "http://synthetic.test/book/1")
    }

    func testInitRuleExecuted() async throws {
        let html = "<html><body><h1>初始名</h1></body></html>"
        // init 规则把正文替换为 h1 文本（合成：init 用 tag.h1 作为新正文，name 用 tag.h1@text）
        let src = infoSource(bookInfo: BookInfoRule(init: "tag.h1", name: "tag.h1@text"))
        let opts = options(html)
        var book = makeBook()
        _ = try await WebBook.getBookInfoAwait(bookSource: src, book: &book, options: opts)
        XCTAssertEqual(book.name, "初始名")
    }

    func testBodyNilThrows() async {
        let src = infoSource(bookInfo: BookInfoRule(name: "tag.h1@text"))
        let net = MockWebBookNetwork([:])
        let opts = WebBookOptions(network: net)
        var book = Book(bookUrl: "http://synthetic.test/book/1", origin: "http://synthetic.test")
        do {
            _ = try await WebBook.getBookInfoAwait(bookSource: src, book: &book, options: opts)
            XCTFail("无响应应抛错")
        } catch { /* 期望失败 */ }
    }

    func testDownloadUrlsWhenWebFile() async throws {
        let html = "<html><body><h1>下载书</h1><div class=\"dl\"><a href=\"http://synthetic.test/dl/1.txt\">1</a></div></body></html>"
        let src = BookSource(
            bookSourceUrl: "http://synthetic.test",
            bookSourceName: "synthetic_wf",
            bookSourceType: BookType.webFile,
            ruleBookInfo: BookInfoRule(name: "tag.h1@text", downloadUrls: "class.dl@tag.a@href"),
            ruleToc: TocRule(chapterList: "class.chapters@tag.li", chapterName: "tag.a@text", chapterUrl: "tag.a@href"),
            ruleContent: ContentRule(content: "class.content@html")
        )
        let opts = options(html)
        var book = makeBook()
        _ = try await WebBook.getBookInfoAwait(bookSource: src, book: &book, options: opts)
        XCTAssertEqual(book.downloadUrls, ["http://synthetic.test/dl/1.txt"])
    }

    func testDownloadUrlsEmptyThrows() async {
        let html = "<html><body><h1>下载书</h1></body></html>"
        let src = BookSource(
            bookSourceUrl: "http://synthetic.test",
            bookSourceName: "synthetic_wf",
            bookSourceType: BookType.webFile,
            ruleBookInfo: BookInfoRule(name: "tag.h1@text", downloadUrls: "class.dl@tag.a@href"),
            ruleToc: TocRule(chapterList: "class.chapters@tag.li", chapterName: "tag.a@text", chapterUrl: "tag.a@href"),
            ruleContent: ContentRule(content: "class.content@html")
        )
        let opts = options(html)
        var book = makeBook()
        do {
            _ = try await WebBook.getBookInfoAwait(bookSource: src, book: &book, options: opts)
            XCTFail("下载链接为空应抛错")
        } catch { /* 期望失败 */ }
    }

    func testKindFailureLoggedNotCrash() async throws {
        let html = "<html><body><h1>书名</h1></body></html>"
        let src = infoSource(bookInfo: BookInfoRule(name: "tag.h1@text", kind: "class.nope@text"))
        let opts = options(html)
        var book = makeBook()
        _ = try await WebBook.getBookInfoAwait(bookSource: src, book: &book, options: opts)
        XCTAssertEqual(book.name, "书名")
        XCTAssertNil(book.kind)
    }
}
