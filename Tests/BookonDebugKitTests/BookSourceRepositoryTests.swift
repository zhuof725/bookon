//
//  BookSourceRepositoryTests.swift
//  BookonDebugKitTests
//
//  第 7 步 B 段：书源仓库（导入 / 持久化 / 启用开关 / 搜索）测试。
//  合成书源规则（synthetic_ 前缀），持久化到临时目录，不触碰真实 Documents。
//

import XCTest
@testable import BookonDebugKit
@testable import LegadoBookSource

final class BookSourceRepositoryTests: XCTestCase {

    private func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bookon-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeSource(name: String, url: String, order: Int = 0) -> BookSource {
        BookSource(bookSourceUrl: url, bookSourceName: name, customOrder: order)
    }

    private func repo(_ dir: URL? = nil) -> BookSourceRepository {
        let storage = (dir ?? tempDir()).appendingPathComponent("sources.json")
        return BookSourceRepository(storageURL: storage)
    }

    private let sampleJSON = """
    [
      {"bookSourceName": "synthetic_a", "bookSourceUrl": "http://a.test", "customOrder": 0},
      {"bookSourceName": "synthetic_b", "bookSourceUrl": "http://b.test", "customOrder": 1}
    ]
    """

    // MARK: - 导入

    func testImportFromJSONText() throws {
        let r = repo()
        let count = try r.importSources(jsonText: sampleJSON)
        XCTAssertEqual(count, 2)
        XCTAssertEqual(r.sources.count, 2)
        XCTAssertEqual(r.sources[0].bookSourceName, "synthetic_a")
    }

    func testImportSingleObject() throws {
        let r = repo()
        let count = try r.importSources(jsonText: #"{"bookSourceName":"single","bookSourceUrl":"http://s.test"}"#)
        XCTAssertEqual(count, 1)
        XCTAssertEqual(r.sources[0].bookSourceName, "single")
    }

    func testImportFromClipboardAlias() throws {
        let r = repo()
        let count = try r.importFromClipboard(sampleJSON)
        XCTAssertEqual(count, 2)
    }

    func testImportFromFileURL() throws {
        let dir = tempDir()
        let file = dir.appendingPathComponent("src.json")
        try Data(sampleJSON.utf8).write(to: file)
        let r = repo(dir)
        let count = try r.importSources(fileURL: file)
        XCTAssertEqual(count, 2)
    }

    func testImportFromURL() async throws {
        let dir = tempDir()
        let r = BookSourceRepository(storageURL: dir.appendingPathComponent("sources.json"), fetcher: { _ in
            Data(self.sampleJSON.utf8)
        })
        let count = try await r.importSources(url: URL(string: "http://remote/sources.json")!)
        XCTAssertEqual(count, 2)
    }

    func testImportInvalidJSONThrows() {
        let r = repo()
        XCTAssertThrowsError(try r.importSources(jsonText: "[{broken"))
    }

    func testImportDuplicateURLOverwrites() throws {
        let r = repo()
        _ = try r.importSources(jsonText: #"[{"bookSourceName":"旧名","bookSourceUrl":"http://x.test"}]"#)
        _ = try r.importSources(jsonText: #"[{"bookSourceName":"新名","bookSourceUrl":"http://x.test"}]"#)
        XCTAssertEqual(r.sources.count, 1)
        XCTAssertEqual(r.sources[0].bookSourceName, "新名")
    }

    // MARK: - 持久化

    func testSaveAndReload() throws {
        let dir = tempDir()
        let storage = dir.appendingPathComponent("sources.json")
        let r1 = BookSourceRepository(storageURL: storage)
        _ = try r1.importSources(jsonText: sampleJSON)

        // 新实例从同一文件加载
        let r2 = BookSourceRepository(storageURL: storage)
        XCTAssertEqual(r2.sources.count, 2)
        XCTAssertEqual(r2.sources[0].bookSourceName, "synthetic_a")
    }

    func testEmptyStorageStartsEmpty() {
        let r = repo()
        XCTAssertTrue(r.sources.isEmpty)
    }

    // MARK: - 启用开关

    func testToggleEnabled() throws {
        let r = repo()
        _ = try r.importSources(jsonText: sampleJSON)
        XCTAssertTrue(r.sources[0].enabled)
        r.toggleEnabled(sourceUrl: "http://a.test")
        XCTAssertFalse(r.sources[0].enabled)
    }

    func testSetEnabled() throws {
        let r = repo()
        _ = try r.importSources(jsonText: sampleJSON)
        r.setEnabled(false, sourceUrl: "http://b.test")
        XCTAssertFalse(r.sources[1].enabled)
        XCTAssertTrue(r.sources[0].enabled)
    }

    func testToggleUnknownURLNoop() throws {
        let r = repo()
        _ = try r.importSources(jsonText: sampleJSON)
        r.toggleEnabled(sourceUrl: "http://nope.test")
        XCTAssertEqual(r.sources.count, 2)
    }

    func testTogglePersisted() throws {
        let dir = tempDir()
        let storage = dir.appendingPathComponent("sources.json")
        let r1 = BookSourceRepository(storageURL: storage)
        _ = try r1.importSources(jsonText: sampleJSON)
        r1.setEnabled(false, sourceUrl: "http://a.test")

        let r2 = BookSourceRepository(storageURL: storage)
        XCTAssertFalse(r2.sources[0].enabled)
    }

    // MARK: - 搜索 / 过滤

    func testSearchByName() throws {
        let r = repo()
        _ = try r.importSources(jsonText: sampleJSON)
        r.search("synthetic_b")
        XCTAssertEqual(r.filteredSources.count, 1)
        XCTAssertEqual(r.filteredSources[0].bookSourceName, "synthetic_b")
    }

    func testSearchByURL() throws {
        let r = repo()
        _ = try r.importSources(jsonText: sampleJSON)
        r.search("a.test")
        XCTAssertEqual(r.filteredSources.count, 1)
        XCTAssertEqual(r.filteredSources[0].bookSourceUrl, "http://a.test")
    }

    func testSearchEmptyQueryReturnsAll() throws {
        let r = repo()
        _ = try r.importSources(jsonText: sampleJSON)
        r.search("  ")
        XCTAssertEqual(r.filteredSources.count, 2)
    }

    func testSearchNoMatchReturnsEmpty() throws {
        let r = repo()
        _ = try r.importSources(jsonText: sampleJSON)
        r.search("不存在")
        XCTAssertTrue(r.filteredSources.isEmpty)
    }

    func testSearchCaseInsensitive() throws {
        let r = repo()
        _ = try r.importSources(jsonText: sampleJSON)
        r.search("SYNTHETIC_A")
        XCTAssertEqual(r.filteredSources.count, 1)
    }

    // MARK: - 排序

    func testMergeSortsByCustomOrder() throws {
        let r = repo()
        _ = try r.importSources(jsonText: #"""
        [
          {"bookSourceName":"c","bookSourceUrl":"http://c.test","customOrder":2},
          {"bookSourceName":"a","bookSourceUrl":"http://a.test","customOrder":0},
          {"bookSourceName":"b","bookSourceUrl":"http://b.test","customOrder":1}
        ]
        """#)
        XCTAssertEqual(r.sources.map { $0.bookSourceName }, ["a", "b", "c"])
    }
}
