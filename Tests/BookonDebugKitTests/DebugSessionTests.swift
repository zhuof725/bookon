//
//  DebugSessionTests.swift
//  BookonDebugKitTests
//
//  第 7 步 B 段：调试会话（5 种 key 形式 / 取消 / 计时 / 阶段 / 导出 JSON）测试。
//  合成书源规则 + 合成响应。
//

import XCTest
@testable import BookonDebugKit
@testable import LegadoBookSource

final class DebugSessionTests: XCTestCase {

    private func basicSource() -> BookSource {
        BookSource(
            bookSourceUrl: "http://synthetic.test",
            bookSourceName: "synthetic_session",
            searchUrl: "http://synthetic.test/search",
            ruleSearch: SearchRule(bookList: "class.item", name: "tag.h3@tag.a@text", bookUrl: "tag.h3@tag.a@href"),
            ruleBookInfo: BookInfoRule(name: "tag.h1@text"),
            ruleToc: TocRule(chapterList: "class.chapters@tag.li", chapterName: "tag.a@text", chapterUrl: "tag.a@href"),
            ruleContent: ContentRule(content: "class.content@html")
        )
    }

    private let searchHtml = "<html><body><div class=\"list\"><div class=\"item\"><h3><a href=\"http://synthetic.test/book/1\">书名</a></h3></div></div></body></html>"

    private func network() -> MockWebBookNetwork {
        MockWebBookNetwork([
            "http://synthetic.test/search": WebBookResponse(url: "http://synthetic.test/search", status: 200, body: searchHtml)
        ])
    }

    private func runSession(_ session: DebugSession, source: BookSource, key: String, network: MockWebBookNetwork? = nil) {
        let net = network ?? self.network()
        let opts = WebBookOptions(logger: session.logger, network: net)
        session.start(bookSource: source, key: key, options: opts)
        // 等待 Task 完成（同步测试用 RunLoop 轮询）
        let deadline = Date().addingTimeInterval(5)
        while session.isRunning && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
    }

    func testStartSetsStateRunningThenFinished() {
        let session = DebugSession()
        XCTAssertEqual(session.state, .idle)
        runSession(session, source: basicSource(), key: "斗罗")
        XCTAssertEqual(session.state, .finished)
    }

    func testSearchKeyFormRuns() {
        let session = DebugSession()
        runSession(session, source: basicSource(), key: "斗罗")
        XCTAssertFalse(session.records.isEmpty)
        XCTAssertTrue(session.records.contains { $0.raw.contains("搜索") || $0.raw.contains("获取成功") })
    }

    func testElapsedNonZeroAfterFinish() {
        let session = DebugSession()
        runSession(session, source: basicSource(), key: "斗罗")
        XCTAssertGreaterThanOrEqual(session.elapsed, 0)
        XCTAssertNotNil(session.startTime)
        XCTAssertNotNil(session.endTime)
    }

    func testElapsedZeroBeforeStart() {
        let session = DebugSession()
        XCTAssertEqual(session.elapsed, 0)
    }

    func testExportResultJSONContainsRecords() {
        let session = DebugSession()
        runSession(session, source: basicSource(), key: "斗罗")
        let json = session.exportResultJSON()
        XCTAssertTrue(json.contains("\"records\""))
        XCTAssertTrue(json.contains("\"sourceUrl\""))
    }

    func testExportResultJSONHasStage() {
        let session = DebugSession()
        runSession(session, source: basicSource(), key: "斗罗")
        let json = session.exportResultJSON()
        XCTAssertTrue(json.contains("\"stages\""))
    }

    func testStartWhenRunningIsIgnored() {
        let session = DebugSession()
        runSession(session, source: basicSource(), key: "斗罗")
        XCTAssertEqual(session.state, .finished)
        // 再次 start 应正常开始（非 running 状态）
        runSession(session, source: basicSource(), key: "斗罗")
        XCTAssertEqual(session.state, .finished)
    }

    func testCurrentStageSetDuringRun() {
        let session = DebugSession()
        runSession(session, source: basicSource(), key: "斗罗")
        // 搜索阶段会触发 currentStage = .search
        XCTAssertEqual(session.currentStage, .search)
    }

    func testCancelSetsCancelled() {
        let session = DebugSession()
        let net = network()
        let opts = WebBookOptions(logger: session.logger, network: net)
        session.start(bookSource: basicSource(), key: "斗罗", options: opts)
        session.cancel()
        XCTAssertEqual(session.state, .cancelled)
    }

    func testSourceUrlAndKeyRecorded() {
        let session = DebugSession()
        runSession(session, source: basicSource(), key: "斗罗")
        XCTAssertEqual(session.sourceUrl, "http://synthetic.test")
        XCTAssertEqual(session.debugKey, "斗罗")
    }
}
