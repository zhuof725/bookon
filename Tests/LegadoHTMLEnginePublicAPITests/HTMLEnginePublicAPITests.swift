//
//  HTMLEnginePublicAPITests.swift — 纯 public 接口（普通 import，非 @testable）。
//
import XCTest
import LegadoBookSource

final class HTMLEnginePublicAPITests: XCTestCase {
    func testPublicSmoke() throws {
        // ⚠️ 合成 HTML，非真实数据。
        let jsoup = try AnalyzeByJSoup("<ul><li>a</li><li>b</li></ul>")
        _ = try jsoup.getString("tag.li@text")
        _ = try jsoup.getStringList("tag.li@text")
        _ = try jsoup.getString0("tag.li@text")
        _ = try jsoup.getElements("tag.li")

        let xp = try AnalyzeByXPath("<ul><li>a</li></ul>")
        _ = try xp.getString("//li/text()")
        _ = try xp.getStringList("//li/text()")
        _ = try xp.getElements("//li")
        XCTAssertTrue(true)
    }
}
