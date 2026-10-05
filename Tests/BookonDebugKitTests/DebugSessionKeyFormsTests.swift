//
//  DebugSessionKeyFormsTests.swift
//  BookonDebugKitTests
//
//  第 7 步 B 段：DebugSession 的 5 种 key 形式（绝对地址 / :: 发现 / ++ 目录 / -- 正文 / 搜索）。
//

import XCTest
@testable import BookonDebugKit
@testable import LegadoBookSource

final class DebugSessionKeyFormsTests: XCTestCase {

    private func fullSource(exploreUrl: String? = "http://synthetic.test/exp") -> BookSource {
        BookSource(
            bookSourceUrl: "http://synthetic.test",
            bookSourceName: "synthetic_keyforms",
            exploreUrl: exploreUrl,
            ruleExplore: ExploreRule(bookList: "class.item", name: "tag.a@text", bookUrl: "tag.a@href"),
            searchUrl: "http://synthetic.test/search",
            ruleSearch: SearchRule(bookList: "class.item", name: "tag.h3@tag.a@text", bookUrl: "tag.h3@tag.a@href"),
            ruleBookInfo: BookInfoRule(name: "tag.h1@text", tocUrl: "class.toc@tag.a@href"),
            ruleToc: TocRule(chapterList: "class.chapters@tag.li", chapterName: "tag.a@text", chapterUrl: "tag.a@href"),
            ruleContent: ContentRule(content: "class.content@html")
        )
    }

    private let searchHtml = "<html><body><div class=\"list\"><div class=\"item\"><h3><a href=\"http://synthetic.test/book/1\">书名</a></h3></div></div></body></html>"
    private let detailHtml = "<html><body><h1>书名</h1><div class=\"toc\"><a href=\"http://synthetic.test/toc/1\">目录</a></div></body></html>"
    private let tocHtml = "<html><body><div class=\"chapters\"><li><a href=\"http://synthetic.test/c/1\">第一章</a></li></div></body></html>"
    private let contentHtml = "<html><body><div class=\"content\">正文</div></body></html>"

    private func run(_ key: String, net: MockWebBookNetwork) -> DebugSession {
        let session = DebugSession()
        let opts = WebBookOptions(logger: session.logger, network: net)
        session.start(bookSource: fullSource(), key: key, options: opts)
        let deadline = Date().addingTimeInterval(5)
        while session.isRunning && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        return session
    }

    func testAbsUrlKeyGoesToInfo() {
        let net = MockWebBookNetwork([
            "http://synthetic.test/book/1": WebBookResponse(url: "http://synthetic.test/book/1", status: 200, body: detailHtml),
            "http://synthetic.test/toc/1": WebBookResponse(url: "http://synthetic.test/toc/1", status: 200, body: tocHtml)
        ])
        let session = run("http://synthetic.test/book/1", net: net)
        XCTAssertEqual(session.state, .finished)
        XCTAssertNotNil(session.logger.capturedResponse(stage: .info))
    }

    func testExploreColonKey() {
        let net = MockWebBookNetwork([
            "http://synthetic.test/exp": WebBookResponse(url: "http://synthetic.test/exp", status: 200, body: searchHtml)
        ])
        let session = run("分类::http://synthetic.test/exp", net: net)
        XCTAssertEqual(session.state, .finished)
        XCTAssertNotNil(session.logger.capturedResponse(stage: .explore))
    }

    func testTocPlusPlusKey() {
        let net = MockWebBookNetwork([
            "http://synthetic.test/toc/1": WebBookResponse(url: "http://synthetic.test/toc/1", status: 200, body: tocHtml),
            "http://synthetic.test/c/1": WebBookResponse(url: "http://synthetic.test/c/1", status: 200, body: contentHtml)
        ])
        let session = run("++http://synthetic.test/toc/1", net: net)
        XCTAssertEqual(session.state, .finished)
        XCTAssertNotNil(session.logger.capturedResponse(stage: .toc))
    }

    func testContentMinusMinusKey() {
        let net = MockWebBookNetwork([
            "http://synthetic.test/c/1": WebBookResponse(url: "http://synthetic.test/c/1", status: 200, body: contentHtml)
        ])
        let session = run("--http://synthetic.test/c/1", net: net)
        XCTAssertEqual(session.state, .finished)
        XCTAssertNotNil(session.logger.capturedResponse(stage: .content))
    }

    func testSearchKey() {
        let net = MockWebBookNetwork([
            "http://synthetic.test/search": WebBookResponse(url: "http://synthetic.test/search", status: 200, body: searchHtml)
        ])
        let session = run("斗罗", net: net)
        XCTAssertEqual(session.state, .finished)
        XCTAssertNotNil(session.logger.capturedResponse(stage: .search))
    }

    func testErrorKeyDoesNotCrash() {
        let net = MockWebBookNetwork([:])
        let session = run("斗罗", net: net)
        XCTAssertEqual(session.state, .finished)
    }
}
