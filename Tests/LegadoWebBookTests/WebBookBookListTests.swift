//
//  WebBookBookListTests.swift
//  LegadoBookSource
//
//  第 7 步 A 段：BookList.analyzeBookList / getInfoItem / getSearchItem / checkExploreJson 逐分支测试。
//  全部为合成书源规则 + 合成 HTML（非真实站点）。
//

import XCTest
@testable import LegadoBookSource

final class WebBookBookListTests: XCTestCase {

    private func listSource(search: SearchRule, searchUrl: String = "http://synthetic.test/search") -> BookSource {
        BookSource(
            bookSourceUrl: "http://synthetic.test",
            bookSourceName: "synthetic_list",
            searchUrl: searchUrl,
            ruleSearch: search,
            ruleBookInfo: BookInfoRule(name: "tag.h1@text"),
            ruleToc: TocRule(chapterList: "class.chapters@tag.li", chapterName: "tag.a@text", chapterUrl: "tag.a@href"),
            ruleContent: ContentRule(content: "class.content@html")
        )
    }

    private func runSearch(_ src: BookSource, html: String, key: String = "x",
                           filter: ((String, String, String?) -> Bool)? = nil,
                           shouldBreak: ((Int) -> Bool)? = nil) async throws -> [SearchBook] {
        let net = MockWebBookNetwork(["http://synthetic.test/search": WebBookResponse(url: "http://synthetic.test/search", status: 200, body: html)])
        let opts = WebBookOptions(network: net)
        return try await WebBook.searchBookAwait(bookSource: src, key: key, options: opts, filter: filter, shouldBreak: shouldBreak)
    }

    func testFilterClosureKeepsOnlyMatching() async throws {
        let src = listSource(search: SearchRule(bookList: "class.item", name: "tag.h3@tag.a@text", author: "class.author@text", bookUrl: "tag.h3@tag.a@href"))
        let result = try await runSearch(src, html: Fixtures.searchBasic, filter: { name, _, _ in name == "书名二" })
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].name, "书名二")
    }

    func testShouldBreakStopsAfterFirst() async throws {
        let src = listSource(search: SearchRule(bookList: "class.item", name: "tag.h3@tag.a@text", author: "class.author@text", bookUrl: "tag.h3@tag.a@href"))
        let result = try await runSearch(src, html: Fixtures.searchBasic, shouldBreak: { $0 >= 1 })
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].name, "书名一")
    }

    func testBookListPlusPrefixDropsPlus() async throws {
        let src = listSource(search: SearchRule(bookList: "+class.item", name: "tag.h3@tag.a@text", bookUrl: "tag.h3@tag.a@href"))
        let result = try await runSearch(src, html: Fixtures.searchBasic)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].name, "书名一")
    }

    func testRelativeBookUrlResolved() async throws {
        // 相对链接 → getSearchItem(isUrl:true) 解析为绝对地址
        let html = "<html><body><div class=\"list\"><div class=\"item\"><h3><a href=\"/book/9\">相对书</a></h3><p class=\"author\">作者</p></div></div></body></html>"
        let src = listSource(search: SearchRule(bookList: "class.item", name: "tag.h3@tag.a@text", bookUrl: "tag.h3@tag.a@href"))
        let result = try await runSearch(src, html: html)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].bookUrl, "http://synthetic.test/book/9")
    }

    func testGetInfoItemNameEmptyReturnsNil() async throws {
        // 详情页书名规则不命中 → getInfoItem 返回 nil → 列表为空（不崩溃）
        let html = "<html><body><div class=\"detail\">无书名</div></body></html>"
        let src = listSource(search: SearchRule(bookList: "class.item", name: "tag.h3@tag.a@text", bookUrl: "tag.h3@tag.a@href"))
        let net = MockWebBookNetwork(["http://synthetic.test/search": WebBookResponse(url: "http://synthetic.test/search", status: 200, body: html)])
        let opts = WebBookOptions(network: net)
        let result = try await WebBook.searchBookAwait(bookSource: src, key: "x", options: opts)
        XCTAssertEqual(result.count, 0)
    }

    func testSearchNameFormatBookName() async throws {
        // 书名含《》 → formatBookName 去掉
        let html = "<html><body><div class=\"list\"><div class=\"item\"><h3><a href=\"http://synthetic.test/book/1\">《书名》</a></h3><p class=\"author\">作者</p></div></div></body></html>"
        let src = listSource(search: SearchRule(bookList: "class.item", name: "tag.h3@tag.a@text", bookUrl: "tag.h3@tag.a@href"))
        let result = try await runSearch(src, html: html)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].name, "书名")
    }

    func testExploreUsesSearchRuleWhenExploreRuleEmpty() async throws {
        // exploreUrl 无独立 bookList → 回退 searchRule（对应 Kotlin getExploreRule().bookList 为空分支）
        let src = BookSource(
            bookSourceUrl: "http://synthetic.test",
            bookSourceName: "synthetic_exp_fallback",
            exploreUrl: "http://synthetic.test/exp",
            ruleExplore: ExploreRule(bookList: nil, name: nil, bookUrl: nil),
            ruleSearch: SearchRule(bookList: "class.item", name: "tag.h3@tag.a@text", bookUrl: "tag.h3@tag.a@href"),
            ruleBookInfo: BookInfoRule(name: "tag.h1@text"),
            ruleToc: TocRule(chapterList: "class.chapters@tag.li", chapterName: "tag.a@text", chapterUrl: "tag.a@href"),
            ruleContent: ContentRule(content: "class.content@html")
        )
        let net = MockWebBookNetwork(["http://synthetic.test/exp": WebBookResponse(url: "http://synthetic.test/exp", status: 200, body: Fixtures.searchBasic)])
        let opts = WebBookOptions(network: net)
        let result = try await WebBook.exploreBookAwait(bookSource: src, url: "http://synthetic.test/exp", options: opts)
        XCTAssertEqual(result.count, 2)
    }

    func testSearchMissingBookUrlUsesBaseUrl() async throws {
        // 无 bookUrl 规则 → 用 baseUrl（详情页地址）
        let html = "<html><body><div class=\"list\"><div class=\"item\"><h3><a>无链接</a></h3></div></div></body></html>"
        let src = listSource(search: SearchRule(bookList: "class.item", name: "tag.h3@tag.a@text"))
        let result = try await runSearch(src, html: html)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].bookUrl, "http://synthetic.test/search")
    }

    func testSearchMissingCoverUrl() async throws {
        let html = "<html><body><div class=\"list\"><div class=\"item\"><h3><a href=\"http://synthetic.test/book/1\">书名</a></h3></div></div></body></html>"
        let src = listSource(search: SearchRule(bookList: "class.item", name: "tag.h3@tag.a@text", bookUrl: "tag.h3@tag.a@href"))
        let result = try await runSearch(src, html: html)
        XCTAssertEqual(result.count, 1)
        XCTAssertNil(result[0].coverUrl)
    }

    func testCheckExploreJsonValidNoCrash() async throws {
        let src = BookSource(
            bookSourceUrl: "http://synthetic.test",
            bookSourceName: "synthetic_valid_explore",
            exploreUrl: "!![{\"title\":\"分类\",\"url\":\"http://x\"}]::http://synthetic.test/exp",
            ruleExplore: ExploreRule(bookList: "class.item", name: "tag.a@text", bookUrl: "tag.a@href"),
            ruleToc: TocRule(chapterList: "class.chapters@tag.li", chapterName: "tag.a@text", chapterUrl: "tag.a@href"),
            ruleContent: ContentRule(content: "class.content@html")
        )
        let net = MockWebBookNetwork(["http://synthetic.test/exp": WebBookResponse(url: "http://synthetic.test/exp", status: 200, body: Fixtures.searchBasic)])
        let opts = WebBookOptions(network: net)
        let result = try await WebBook.exploreBookAwait(bookSource: src, url: "http://synthetic.test/exp", options: opts)
        XCTAssertEqual(result.count, 2)
    }
}
