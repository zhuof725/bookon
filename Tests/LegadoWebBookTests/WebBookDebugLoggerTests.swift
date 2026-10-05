//
//  WebBookDebugLoggerTests.swift
//  LegadoBookSource
//
//  第 7 步 A 段：DebugLogger（日志格式/符号/状态码/时间前缀/生命周期/响应留存）单元测试。
//  对应 Kotlin model/Debug.kt 的书源调试部分。
//

import XCTest
@testable import LegadoBookSource

final class WebBookDebugLoggerTests: XCTestCase {

    private func makeLogger() -> (DebugLogger, RecordingSink) {
        let logger = DebugLogger()
        let sink = RecordingSink()
        logger.callback = sink
        return (logger, sink)
    }

    func testDefaultStateIsNormal() {
        let (logger, sink) = makeLogger()
        logger.beginDebug(sourceUrl: "http://x")
        logger.log("http://x", "消息")
        XCTAssertEqual(sink.states.last, DebugLogState.normal)
    }

    func testStateCodes() {
        let (logger, sink) = makeLogger()
        logger.beginDebug(sourceUrl: "http://x")
        logger.log("http://x", "搜索", state: DebugLogState.searchSource)
        logger.log("http://x", "详情", state: DebugLogState.infoSource)
        logger.log("http://x", "目录", state: DebugLogState.tocSource)
        logger.log("http://x", "正文", state: DebugLogState.contentSource)
        logger.log("http://x", "完成", state: DebugLogState.finished)
        logger.log("http://x", "错误", state: DebugLogState.error)
        XCTAssertEqual(sink.states, [10, 20, 30, 40, 1000, -1])
    }

    func testTimePrefixFormat() {
        let logger = DebugLogger()
        logger.beginDebug(sourceUrl: "http://x")
        let sink = RecordingSink()
        logger.callback = sink
        logger.log("http://x", "消息")
        let msg = sink.messages[0]
        // 格式 [mm:ss.SSS]
        XCTAssertTrue(msg.hasPrefix("["))
        XCTAssertTrue(msg.hasSuffix("] 消息") || msg.contains("] 消息"))
    }

    func testShowTimeFalseOmitsPrefix() {
        let (logger, sink) = makeLogger()
        logger.beginDebug(sourceUrl: "http://x")
        logger.log("http://x", "消息", showTime: false)
        XCTAssertEqual(sink.messages[0], "消息")
    }

    func testPrintFalseSuppresses() {
        let (logger, sink) = makeLogger()
        logger.beginDebug(sourceUrl: "http://x")
        logger.log("http://x", "消息", printLog: false)
        XCTAssertTrue(sink.messages.isEmpty)
    }

    func testDebugSourceMismatchSuppresses() {
        let (logger, sink) = makeLogger()
        logger.beginDebug(sourceUrl: "http://x")
        logger.log("http://other", "消息")
        XCTAssertTrue(sink.messages.isEmpty)
    }

    func testLogWithoutSourceUsesDebugSource() {
        let (logger, sink) = makeLogger()
        logger.beginDebug(sourceUrl: "http://x")
        logger.log("消息")
        XCTAssertEqual(sink.messages.count, 1)
    }

    func testBeginDebugResetsRecords() {
        let (logger, sink) = makeLogger()
        logger.beginDebug(sourceUrl: "http://x")
        logger.log("http://x", "第一条")
        logger.beginDebug(sourceUrl: "http://x")
        XCTAssertTrue(logger.records.isEmpty)
    }

    func testCancelDebugDestroyClearsSource() {
        let logger = DebugLogger()
        logger.beginDebug(sourceUrl: "http://x")
        logger.cancelDebug(destroy: true)
        XCTAssertNil(logger.debugSource)
    }

    func testCancelDebugWithoutDestroyKeepsSource() {
        let logger = DebugLogger()
        logger.beginDebug(sourceUrl: "http://x")
        logger.cancelDebug(destroy: false)
        XCTAssertEqual(logger.debugSource, "http://x")
    }

    func testNoopSinkDoesNothing() {
        let sink = NoopDebugSink()
        sink.printLog(state: 1, msg: "x")
        // 不崩溃即可
    }

    func testRecordsCaptureRawAndMessage() {
        let (logger, sink) = makeLogger()
        // 必须保留 sink：`DebugLogger.callback` 是 **weak**，
        // 若写成 `let (logger, _) = makeLogger()` 则 sink 立即被释放，
        // `log()` 开头的 `guard let cb = callback else { return }` 会直接返回，
        // records 保持为空——后续 records[0] 就是数组越界崩溃。
        withExtendedLifetime(sink) {
            logger.beginDebug(sourceUrl: "http://x")
            logger.log("http://x", "原始消息", showTime: false)
            XCTAssertEqual(logger.records.count, 1)
            XCTAssertEqual(logger.records.first?.raw, "原始消息")
        }
    }
}
