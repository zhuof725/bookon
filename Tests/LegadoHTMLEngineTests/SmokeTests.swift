//
//  SmokeTests.swift  — 临时冒烟测试，先验证 SwiftSoup 依赖 + 两个后端能编译运行。
//
import XCTest
@testable import LegadoBookSource

final class SmokeTests: XCTestCase {
    func testJSoupBasic() throws {
        // ⚠️ 合成 HTML，非真实数据。
        let html = "<div class='a'><p>甲</p><p>乙</p></div>"
        let jsoup = try AnalyzeByJSoup(html)
        let text = try jsoup.getStringList("class.a@tag.p@text")
        XCTAssertEqual(text, ["甲", "乙"])
    }
    func testXPathBasic() throws {
        // ⚠️ 合成 HTML，非真实数据。
        let html = "<div><a href='/x'>链接</a></div>"
        let xp = try AnalyzeByXPath(html)
        XCTAssertEqual(try xp.getStringList("//a/@href"), ["/x"])
        XCTAssertEqual(try xp.getStringList("//a/text()"), ["链接"])
    }
}
