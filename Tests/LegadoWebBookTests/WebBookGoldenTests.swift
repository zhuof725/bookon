//
//  WebBookGoldenTests.swift
//  LegadoBookSource
//
//  第 7 步 A 段：HtmlFormatter.format/formatKeepImg（≥80）与 wordCountFormat（≥30）golden 对照。
//  期望值来自 scripts/golden 的手工 Java 移植（真实 JDK java.util.regex + DecimalFormat("#.#")），
//  由 CI 的 golden job 生成后下载到 Tests/*/Resources/golden/。
//  只校验库行为，不校验 Swift 内部实现。
//

import XCTest
@testable import LegadoBookSource

final class WebBookGoldenTests: XCTestCase {

    private func loadGolden(_ name: String) throws -> [String: Any] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "golden"))
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testHtmlFormatterGolden() throws {
        let doc = try loadGolden("html_formatter_cases")
        let results = try XCTUnwrap(doc["htmlFormatterResults"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(results.count, 80)
        for c in results {
            let name = c["name"] as? String ?? ""
            let html = c["html"] as? String ?? ""
            let mode = c["mode"] as? String ?? "format"
            let expected = c["result"] as? String ?? ""
            let actual: String
            if mode == "formatKeepImg" {
                let redirectUrl = c["redirectUrl"] as? String
                actual = HtmlFormatter.formatKeepImg(html, redirectUrl: redirectUrl)
            } else {
                actual = HtmlFormatter.format(html)
            }
            XCTAssertEqual(actual, expected, "HtmlFormatter 用例 \(name) 不匹配")
        }
    }

    func testWordCountFormatGolden() throws {
        let doc = try loadGolden("word_count_cases")
        let results = try XCTUnwrap(doc["wordCountResults"] as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(results.count, 30)
        for c in results {
            let name = c["name"] as? String ?? ""
            let expected = c["result"] as? String ?? ""
            let actual: String
            if let input = c["input"] as? String {
                actual = LegadoStringUtils2.wordCountFormat(input)
            } else {
                actual = LegadoStringUtils2.wordCountFormat(nil)
            }
            XCTAssertEqual(actual, expected, "wordCountFormat 用例 \(name) 不匹配")
        }
    }
}
