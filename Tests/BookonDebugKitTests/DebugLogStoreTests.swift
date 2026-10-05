//
//  DebugLogStoreTests.swift
//  BookonDebugKitTests
//
//  第 7 步 B 段：调试日志持久化（文件名/写后即刷/保留 50）+ 日志导出测试。
//

import XCTest
@testable import BookonDebugKit

final class DebugLogStoreTests: XCTestCase {

    private func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bookon-logs-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func fixedDate() -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: "2026-01-02 03:04:05")!
    }

    // MARK: - 文件名

    func testFileNameUsesTimestampAndSanitizedSourceName() {
        let name = DebugLogStore.fileName(for: "书源/名:测试", now: fixedDate())
        XCTAssertEqual(name, "20260102-030405-书源_名_测试.txt")
    }

    func testFileNameSanitizesForbiddenChars() {
        XCTAssertEqual(DebugLogStore.sanitize("a/b\\c:d*e?f"), "a_b_c_d_e_f")
    }

    // MARK: - 保存

    func testSaveLogWritesContent() throws {
        let dir = tempDir()
        let store = DebugLogStore(logsDirectory: dir, now: { self.fixedDate() })
        let url = try store.saveLog(sourceName: "测试书源", content: "日志内容")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "日志内容")
    }

    func testSaveLogReturnsFileInLogsDir() throws {
        let dir = tempDir()
        let store = DebugLogStore(logsDirectory: dir)
        let url = try store.saveLog(sourceName: "源", content: "x")
        XCTAssertEqual(url.deletingLastPathComponent(), dir)
    }

    func testAppendLineAppends() throws {
        let dir = tempDir()
        let store = DebugLogStore(logsDirectory: dir)
        let url = try store.saveLog(sourceName: "源", content: "第一行")
        try store.appendLine("第二行", to: url)
        let content = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(content.contains("第一行"))
        XCTAssertTrue(content.contains("第二行"))
    }

    // MARK: - 保留 50

    func testPruneKeepsMaxLogFiles() throws {
        let dir = tempDir()
        let store = DebugLogStore(logsDirectory: dir, maxLogFiles: 3)
        for i in 0..<6 {
            _ = try store.saveLog(sourceName: "源\(i)", content: "内容\(i)")
        }
        XCTAssertEqual(store.logCount, 3)
    }

    func testPruneRemovesOldestFirst() throws {
        let dir = tempDir()
        let store = DebugLogStore(logsDirectory: dir, maxLogFiles: 2, now: { self.fixedDate() })
        _ = try store.saveLog(sourceName: "最旧", content: "1")
        // 模拟更晚的时间戳
        let store2 = DebugLogStore(logsDirectory: dir, maxLogFiles: 2)
        _ = try store2.saveLog(sourceName: "新一", content: "2")
        _ = try store2.saveLog(sourceName: "新二", content: "3")
        XCTAssertEqual(store2.logCount, 2)
        let names = store2.listLogs().map { $0.lastPathComponent }
        XCTAssertFalse(names.contains { $0.contains("最旧") })
    }

    // MARK: - 列表

    func testListLogsOnlyTxtFiles() throws {
        let dir = tempDir()
        let store = DebugLogStore(logsDirectory: dir)
        _ = try store.saveLog(sourceName: "源", content: "x")
        try Data("other".utf8).write(to: dir.appendingPathComponent("not-a-log.json"))
        let logs = store.listLogs()
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs[0].pathExtension, "txt")
    }

    // MARK: - 导出

    func testExportContentContainsHeaderFields() {
        let store = DebugLogStore(logsDirectory: tempDir(), now: { self.fixedDate() })
        let header = DebugLogExportHeader(appVersion: "1.0.0", gitCommit: "abc123", ciRun: "42",
                                          osVersion: "macOS 14.0", sourceName: "书源", key: "斗罗")
        let text = store.exportContent(header: header, body: "正文内容")
        XCTAssertTrue(text.contains("App 版本: 1.0.0"))
        XCTAssertTrue(text.contains("Git 提交: abc123"))
        XCTAssertTrue(text.contains("CI Run: 42"))
        XCTAssertTrue(text.contains("OS: macOS 14.0"))
        XCTAssertTrue(text.contains("书源: 书源"))
        XCTAssertTrue(text.contains("关键字: 斗罗"))
        XCTAssertTrue(text.contains("--- 日志正文 ---"))
        XCTAssertTrue(text.contains("正文内容"))
    }

    func testExportContentWithSourceSnippet() {
        let store = DebugLogStore(logsDirectory: tempDir())
        let header = DebugLogExportHeader(sourceName: "源")
        let text = store.exportContent(header: header, body: "正文", sourceSnippet: "规则文本", sourceSnippetLimit: 2)
        XCTAssertTrue(text.contains("--- 书源规则（前 2 字符）---"))
        XCTAssertTrue(text.contains("规则"))
    }

    func testExportContentNoSnippetOmitsSection() {
        let store = DebugLogStore(logsDirectory: tempDir())
        let header = DebugLogExportHeader(sourceName: "源")
        let text = store.exportContent(header: header, body: "正文")
        XCTAssertFalse(text.contains("书源规则"))
    }

    func testExportEmptyHeaderOmitsOptionalFields() {
        let store = DebugLogStore(logsDirectory: tempDir(), now: { self.fixedDate() })
        let header = DebugLogExportHeader()
        let text = store.exportContent(header: header, body: "正文")
        XCTAssertFalse(text.contains("App 版本:"))
        XCTAssertFalse(text.contains("书源:"))
    }
}
