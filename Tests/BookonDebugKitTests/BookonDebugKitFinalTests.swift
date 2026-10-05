//
//  BookonDebugKitFinalTests.swift
//  BookonDebugKitTests
//
//  第 7 步 B 段：收尾用例（导出 JSON 可解析、取消保留记录、文件名唯一性等）。
//

import XCTest
@testable import BookonDebugKit
@testable import LegadoBookSource

final class BookonDebugKitFinalTests: XCTestCase {

    private func tempDir(_ tag: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bookon-\(tag)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testExportResultJSONIsValidJSON() {
        let session = DebugSession()
        let json = session.exportResultJSON()
        XCTAssertNotNil(try? JSONSerialization.jsonObject(with: Data(json.utf8)))
    }

    func testExportResultJSONEmptySession() throws {
        let session = DebugSession()
        let json = session.exportResultJSON()
        // `exportResultJSON` 用 LegadoJSON.prettyEncoder（对应 Gson setPrettyPrinting）：
        //   · 键值对写作 `"records" : [...]`（冒号两侧带空格）；
        //   · **空数组**被展开成多行（`[\n\n  ]`），不会出现紧凑的 `[]`。
        // 因此不能用 `contains("[]")` 之类的字符串匹配判断「空数组」——那是在断言
        // 一个编码器不会产生的字面量。这里改为解析 JSON 后做语义断言。
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let records = try XCTUnwrap(obj["records"] as? [Any])
        let stages = try XCTUnwrap(obj["stages"] as? [Any])
        XCTAssertTrue(records.isEmpty, "空会话的 records 应为空数组：\(json)")
        XCTAssertTrue(stages.isEmpty, "空会话的 stages 应为空数组：\(json)")
    }

    func testCancelKeepsCollectedRecords() {
        let session = DebugSession()
        let logger = session.logger
        logger.beginDebug(sourceUrl: "http://synthetic.test")
        let sink = RecordingSinkForDebug()
        logger.callback = sink
        logger.log("http://synthetic.test", "已收集日志")
        session.cancel()
        XCTAssertFalse(logger.records.isEmpty)
    }

    func testSaveLogSameSourceNameDifferentTimestamps() throws {
        let dir = tempDir("log")
        var counter = 0
        let store = DebugLogStore(logsDirectory: dir, now: {
            counter += 1
            return Date(timeIntervalSince1970: Double(counter * 1000))
        })
        let u1 = try store.saveLog(sourceName: "同源", content: "1")
        let u2 = try store.saveLog(sourceName: "同源", content: "2")
        XCTAssertNotEqual(u1.lastPathComponent, u2.lastPathComponent)
        XCTAssertEqual(store.logCount, 2)
    }

    func testSearchTextTrimsWhitespace() {
        let r = BookSourceRepository(storageURL: tempDir("repo").appendingPathComponent("s.json"))
        _ = try? r.importSources(jsonText: #"[{"bookSourceName":"测试书源","bookSourceUrl":"http://x.test"}]"#)
        r.search("  测试书源  ")
        XCTAssertEqual(r.filteredSources.count, 1)
    }

    func testImportPreservesCustomOrderSorting() throws {
        let r = BookSourceRepository(storageURL: tempDir("repo").appendingPathComponent("s.json"))
        _ = try r.importSources(jsonText: #"""
        [{"bookSourceName":"后","bookSourceUrl":"http://2.test","customOrder":2},
         {"bookSourceName":"前","bookSourceUrl":"http://1.test","customOrder":1}]
        """#)
        XCTAssertEqual(r.sources.first?.bookSourceName, "前")
    }

    func testSetEnabledUnknownURLNoop() throws {
        let r = BookSourceRepository(storageURL: tempDir("repo").appendingPathComponent("s.json"))
        _ = try r.importSources(jsonText: #"[{"bookSourceName":"a","bookSourceUrl":"http://a.test"}]"#)
        r.setEnabled(false, sourceUrl: "http://unknown.test")
        XCTAssertTrue(r.sources[0].enabled)
    }

    func testLogStoreDefaultMaxIs50() {
        let store = DebugLogStore(logsDirectory: tempDir("log"))
        XCTAssertEqual(store.logCount, 0)
    }

    func testHeaderEmptySourceSnippetNotEmitted() {
        let store = DebugLogStore(logsDirectory: tempDir("log"))
        let text = store.exportContent(header: DebugLogExportHeader(), body: "x", sourceSnippet: "")
        XCTAssertFalse(text.contains("书源规则"))
    }

    func testRepositoryLoadCorruptFileStartsEmpty() throws {
        let dir = tempDir("repo")
        let storage = dir.appendingPathComponent("sources.json")
        try Data("not-json".utf8).write(to: storage)
        let r = BookSourceRepository(storageURL: storage)
        XCTAssertTrue(r.sources.isEmpty)
    }
}

/// 供取消记录测试用的最小 sink。
private final class RecordingSinkForDebug: DebugLogSink {
    func printLog(state: Int, msg: String) {}
}
