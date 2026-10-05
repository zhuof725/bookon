//
//  WebBookDebugTests.swift
//  LegadoBookSource
//
//  第 7 步 A 段：Debug.startDebug 五路分发 + 链式调试 + DebugLogger 日志/响应留存测试。
//  全部为合成书源规则 + 合成 HTML（非真实站点）。
//

import XCTest
@testable import LegadoBookSource

final class WebBookDebugTests: XCTestCase {

    private func basicSource(searchUrl: String = "http://synthetic.test/search") -> BookSource {
        SynthSources.basic(searchUrl: searchUrl)
    }

    private func fullNetwork() -> MockWebBookNetwork {
        MockWebBookNetwork([
            "http://synthetic.test/search": WebBookResponse(url: "http://synthetic.test/search", status: 200, body: Fixtures.searchBasic),
            "http://synthetic.test/book/1": WebBookResponse(url: "http://synthetic.test/book/1", status: 200, body: Fixtures.detailBasic),
            "http://synthetic.test/toc/1": WebBookResponse(url: "http://synthetic.test/toc/1", status: 200, body: Fixtures.tocBasic),
            "http://synthetic.test/c/1": WebBookResponse(url: "http://synthetic.test/c/1", status: 200, body: Fixtures.contentBasic)
        ])
    }

    private func recording() -> (DebugLogger, RecordingSink) {
        let logger = DebugLogger()
        let sink = RecordingSink()
        logger.callback = sink
        return (logger, sink)
    }

    func testStartDebugAbsUrlChainInfoTocContent() async {
        let src = basicSource()
        let (logger, sink) = recording()
        let opts = WebBookOptions(logger: logger, network: fullNetwork())
        await Debug.startDebug(bookSource: src, key: "http://synthetic.test/book/1", options: opts)
        XCTAssertTrue(sink.contains("⇒开始访问详情页"))
        XCTAssertTrue(sink.contains("︾开始解析详情页"))
        XCTAssertTrue(sink.contains("︾开始解析目录页"))
        XCTAssertTrue(sink.contains("︾开始解析正文页"))
        XCTAssertTrue(sink.states.contains(DebugLogState.finished))
    }

    func testStartDebugSearchChain() async {
        let src = basicSource()
        let (logger, sink) = recording()
        let opts = WebBookOptions(logger: logger, network: fullNetwork())
        await Debug.startDebug(bookSource: src, key: "斗罗", options: opts)
        XCTAssertTrue(sink.contains("⇒开始搜索关键字"))
        XCTAssertTrue(sink.contains("︽搜索页解析完成"))
        XCTAssertTrue(sink.contains("︾开始解析详情页"))
    }

    func testStartDebugTrimsWhitespaceKey() async {
        let src = basicSource()
        let (logger, sink) = recording()
        let opts = WebBookOptions(logger: logger, network: fullNetwork())
        await Debug.startDebug(bookSource: src, key: "  斗罗  ", options: opts)
        XCTAssertTrue(sink.contains("⇒开始搜索关键字:斗罗"))
    }

    func testStartDebugInfoSkipWhenTocUrlPresent() async {
        let src = basicSource()
        let (logger, sink) = recording()
        let opts = WebBookOptions(logger: logger, network: fullNetwork())
        await Debug.startDebug(bookSource: src, key: "++http://synthetic.test/toc/1", options: opts)
        XCTAssertTrue(sink.contains("⇒开始访目录页"))
        XCTAssertTrue(sink.contains("︾开始解析目录页"))
    }

    func testLoggerFormatTimePrefix() {
        let logger = DebugLogger()
        logger.beginDebug(sourceUrl: "http://synthetic.test")
        let sink = RecordingSink()
        logger.callback = sink
        logger.log("http://synthetic.test", "测试消息")
        // 时间前缀格式 [mm:ss.SSS]
        XCTAssertTrue(sink.messages.first?.hasPrefix("[") == true)
    }

    func testLoggerCapturesStageResponses() async throws {
        let src = basicSource()
        let logger = DebugLogger()
        let net = fullNetwork()
        let opts = WebBookOptions(logger: logger, network: net)
        _ = try await WebBook.searchBookAwait(bookSource: src, key: "x", options: opts)
        let cap = logger.capturedResponse(stage: .search)
        XCTAssertEqual(cap?.statusCode, 200)
        XCTAssertEqual(cap?.url, "http://synthetic.test/search")
    }

    func testLoggerCancelDebugDestroy() {
        let logger = DebugLogger()
        logger.beginDebug(sourceUrl: "http://synthetic.test")
        logger.cancelDebug(destroy: true)
        XCTAssertNil(logger.debugSource)
    }

    func testDebugVerbosityErrorsOnlyFiltersNormal() {
        let logger = DebugLogger()
        logger.beginDebug(sourceUrl: "http://synthetic.test")
        logger.verbosity = .errorsOnly
        let sink = RecordingSink()
        logger.callback = sink
        logger.log("http://synthetic.test", "普通消息")
        logger.log("http://synthetic.test", "错误消息", state: DebugLogState.error)
        XCTAssertFalse(sink.contains("普通消息"))
        XCTAssertTrue(sink.contains("错误消息"))
    }
}
