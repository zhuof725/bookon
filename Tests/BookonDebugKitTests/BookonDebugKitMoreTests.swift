//
//  BookonDebugKitMoreTests.swift
//  BookonDebugKitTests
//
//  第 7 步 B 段：仓库 / 日志存储 / 设置 的补充边界用例。
//

import XCTest
@testable import BookonDebugKit
@testable import LegadoBookSource

final class BookonDebugKitMoreTests: XCTestCase {

    private func tempDir(_ tag: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bookon-\(tag)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - 仓库补充

    func testImportURLFetchFailureThrows() async {
        let r = BookSourceRepository(storageURL: tempDir("repo").appendingPathComponent("s.json"),
                                     fetcher: { _ in throw RuleEngineError.unsupported("网络失败") })
        do {
            _ = try await r.importSources(url: URL(string: "http://x/s.json")!)
            XCTFail("fetch 失败应抛错")
        } catch { /* 期望失败 */ }
    }

    func testImportEmptyArray() throws {
        let r = BookSourceRepository(storageURL: tempDir("repo").appendingPathComponent("s.json"))
        let count = try r.importSources(jsonText: "[]")
        XCTAssertEqual(count, 0)
        XCTAssertTrue(r.sources.isEmpty)
    }

    func testImportEmptySourceNameStillStored() throws {
        let r = BookSourceRepository(storageURL: tempDir("repo").appendingPathComponent("s.json"))
        _ = try r.importSources(jsonText: #"[{"bookSourceUrl":"http://x.test"}]"#)
        XCTAssertEqual(r.sources.count, 1)
        XCTAssertEqual(r.sources[0].bookSourceName, "")
    }

    func testSaveCreatesFile() throws {
        let dir = tempDir("repo")
        let storage = dir.appendingPathComponent("sources.json")
        let r = BookSourceRepository(storageURL: storage)
        _ = try r.importSources(jsonText: #"[{"bookSourceName":"a","bookSourceUrl":"http://a.test"}]"#)
        XCTAssertTrue(FileManager.default.fileExists(atPath: storage.path))
    }

    func testMalformedResourceFileThrows() throws {
        // malformed_sources.json 是非法 JSON，导入应抛错（不崩溃）
        let url = try XCTUnwrap(Bundle.module.url(forResource: "malformed_sources", withExtension: "json"))
        let text = try String(contentsOf: url, encoding: .utf8)
        let r = BookSourceRepository(storageURL: tempDir("repo").appendingPathComponent("s.json"))
        XCTAssertThrowsError(try r.importSources(jsonText: text))
    }

    func testConfig14ResourceImports() throws {
        // 配置文件_14个.json 应可整体导入（8 真实 + 6 合成）
        let url = try XCTUnwrap(Bundle.module.url(forResource: "配置文件_14个", withExtension: "json"))
        let text = try String(contentsOf: url, encoding: .utf8)
        let r = BookSourceRepository(storageURL: tempDir("repo").appendingPathComponent("s.json"))
        let count = try r.importSources(jsonText: text)
        XCTAssertEqual(count, 14)
    }

    func testSearchPersistedAcrossReload() throws {
        let dir = tempDir("repo")
        let storage = dir.appendingPathComponent("sources.json")
        let r1 = BookSourceRepository(storageURL: storage)
        _ = try r1.importSources(jsonText: #"[{"bookSourceName":"alpha","bookSourceUrl":"http://a.test"},{"bookSourceName":"beta","bookSourceUrl":"http://b.test"}]"#)
        let r2 = BookSourceRepository(storageURL: storage)
        r2.search("alpha")
        XCTAssertEqual(r2.filteredSources.count, 1)
    }

    // MARK: - 日志存储补充

    func testSaveLogUnicodeContent() throws {
        let store = DebugLogStore(logsDirectory: tempDir("log"))
        let url = try store.saveLog(sourceName: "中文书源", content: "中文日志 📖 内容")
        let content = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(content.contains("📖"))
    }

    func testAppendLineToMissingFileCreates() throws {
        let dir = tempDir("log")
        let store = DebugLogStore(logsDirectory: dir)
        let url = dir.appendingPathComponent("manual.txt")
        try store.appendLine("第一行", to: url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testListLogsSortedByName() throws {
        let store = DebugLogStore(logsDirectory: tempDir("log"), maxLogFiles: 10)
        _ = try store.saveLog(sourceName: "b", content: "2")
        _ = try store.saveLog(sourceName: "a", content: "1")
        _ = try store.saveLog(sourceName: "c", content: "3")
        let names = store.listLogs().map { $0.lastPathComponent }
        XCTAssertEqual(names, names.sorted())
    }

    func testExportTimestampFormatted() {
        let store = DebugLogStore(logsDirectory: tempDir("log"))
        let header = DebugLogExportHeader(sourceName: "源")
        let text = store.exportContent(header: header, body: "x")
        // 时间字段格式 yyyy-MM-dd HH:mm:ss
        XCTAssertTrue(text.contains("时间: ") )
    }

    func testSourceSnippetLimitZeroMeansFull() {
        let store = DebugLogStore(logsDirectory: tempDir("log"))
        let header = DebugLogExportHeader()
        let text = store.exportContent(header: header, body: "x", sourceSnippet: "abcdef", sourceSnippetLimit: 0)
        XCTAssertTrue(text.contains("abcdef"))
    }

    // MARK: - 设置补充

    func testSettingsVerbosityErrorsOnlyRoundTrip() {
        let suite = "test-v-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        let s1 = DebugSettings(verbosity: .errorsOnly, defaults: d)
        s1.save()
        let s2 = DebugSettings(defaults: d)
        XCTAssertEqual(s2.verbosity, .errorsOnly)
    }

    func testSettingsApplyKeepsLoggerDefaultsForNormal() {
        let s = DebugSettings(defaults: UserDefaults(suiteName: "test-a-\(UUID().uuidString)")!)
        let logger = DebugLogger()
        s.apply(to: logger)
        XCTAssertFalse(logger.recordResponseBody)
        XCTAssertEqual(logger.verbosity, .normal)
    }
}
