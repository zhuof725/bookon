//
//  DebugSettingsTests.swift
//  BookonDebugKitTests
//
//  第 7 步 B 段：调试设置（超时 / 记录响应体 / 详细级别）测试。
//

import XCTest
@testable import BookonDebugKit
@testable import LegadoBookSource

final class DebugSettingsTests: XCTestCase {

    private func makeDefaults() -> UserDefaults {
        let suite = "test-settings-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    func testDefaults() {
        let s = DebugSettings(defaults: makeDefaults())
        XCTAssertEqual(s.connectTimeout, 10)
        XCTAssertEqual(s.readTimeout, 60)
        XCTAssertEqual(s.totalTimeout, 60)
        XCTAssertFalse(s.recordResponseBody)
        XCTAssertEqual(s.verbosity, .normal)
    }

    func testCustomInit() {
        let s = DebugSettings(connectTimeout: 3, readTimeout: 4, totalTimeout: 5,
                              recordResponseBody: true, verbosity: .errorsOnly, defaults: makeDefaults())
        XCTAssertEqual(s.connectTimeout, 3)
        XCTAssertEqual(s.readTimeout, 4)
        XCTAssertEqual(s.totalTimeout, 5)
        XCTAssertTrue(s.recordResponseBody)
        XCTAssertEqual(s.verbosity, .errorsOnly)
    }

    func testApplyToLogger() {
        let s = DebugSettings(recordResponseBody: true, verbosity: .errorsOnly, defaults: makeDefaults())
        let logger = DebugLogger()
        s.apply(to: logger)
        XCTAssertTrue(logger.recordResponseBody)
        XCTAssertEqual(logger.verbosity, .errorsOnly)
    }

    func testTimeoutsMilliseconds() {
        let s = DebugSettings(connectTimeout: 2, readTimeout: 3, totalTimeout: 4, defaults: makeDefaults())
        let t = s.timeoutsMilliseconds
        XCTAssertEqual(t.connect, 2000)
        XCTAssertEqual(t.read, 3000)
        XCTAssertEqual(t.total, 4000)
    }

    func testSaveAndLoadRoundTrip() {
        let defaults = makeDefaults()
        let s1 = DebugSettings(connectTimeout: 7, readTimeout: 8, totalTimeout: 9,
                               recordResponseBody: true, verbosity: .errorsOnly, defaults: defaults)
        s1.save()

        let s2 = DebugSettings(defaults: defaults)
        XCTAssertEqual(s2.connectTimeout, 7)
        XCTAssertEqual(s2.readTimeout, 8)
        XCTAssertEqual(s2.totalTimeout, 9)
        XCTAssertTrue(s2.recordResponseBody)
        XCTAssertEqual(s2.verbosity, .errorsOnly)
    }

    func testLoadWithoutSavedValuesKeepsDefaults() {
        let s = DebugSettings(connectTimeout: 99, defaults: makeDefaults())
        XCTAssertEqual(s.connectTimeout, 99)
    }
}
