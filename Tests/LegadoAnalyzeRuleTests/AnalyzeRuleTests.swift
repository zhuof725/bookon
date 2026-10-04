//
//  AnalyzeRuleTests.swift
//  LegadoAnalyzeRuleTests
//
//  AnalyzeRule 总调度 @testable 单元测试。
//  样本说明：除标注「真实规则」外，输入 HTML/JSON/规则文本均为【合成样本，非真实数据】。
//

import XCTest
import SwiftSoup
@testable import LegadoBookSource

final class AnalyzeRuleTests: XCTestCase {

    // 便捷构造：纯内存依赖，可选 diagnostics。
    private func rule(diag: RuleEngineDiagnostics? = nil) -> AnalyzeRule {
        return AnalyzeRule(diagnostics: diag)
    }

    // MARK: - Mode / 前缀 判定（splitSourceRule → SourceRule.mode）

    func testMode_defaultCss() throws {
        let a = rule()
        let list = try a.splitSourceRule("@CSS:div.title")
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list[0].mode, .default)
        XCTAssertEqual(list[0].rule, "@CSS:div.title")
    }
    func testMode_cssCaseInsensitive() throws {
        let list = try rule().splitSourceRule("@css:a")
        XCTAssertEqual(list[0].mode, .default)
    }
    func testMode_doubleAt() throws {
        let list = try rule().splitSourceRule("@@div")
        XCTAssertEqual(list[0].mode, .default)
        XCTAssertEqual(list[0].rule, "div")
    }
    func testMode_xpathPrefix() throws {
        let list = try rule().splitSourceRule("@XPath://div")
        XCTAssertEqual(list[0].mode, .xPath)
        XCTAssertEqual(list[0].rule, "//div")
    }
    func testMode_xpathPrefixLower() throws {
        let list = try rule().splitSourceRule("@xpath://a")
        XCTAssertEqual(list[0].mode, .xPath)
    }
    func testMode_jsonPrefix() throws {
        let list = try rule().splitSourceRule("@Json:$.name")
        XCTAssertEqual(list[0].mode, .json)
        XCTAssertEqual(list[0].rule, "$.name")
    }
    func testMode_jsonDollarDot() throws {
        let list = try rule().splitSourceRule("$.data.name")
        XCTAssertEqual(list[0].mode, .json)
    }
    func testMode_jsonDollarBracket() throws {
        let list = try rule().splitSourceRule("$[0].name")
        XCTAssertEqual(list[0].mode, .json)
    }
    func testMode_xpathSlash() throws {
        let list = try rule().splitSourceRule("/html/body/div")
        XCTAssertEqual(list[0].mode, .xPath)
    }
    func testMode_defaultPlain() throws {
        let list = try rule().splitSourceRule("div.a@text")
        XCTAssertEqual(list[0].mode, .default)
    }
    func testMode_allInOneRegexColon() throws {
        let list = try rule().splitSourceRule(":(\\d+)", allInOne: true)
        XCTAssertEqual(list[0].mode, .regex)
    }
    func testMode_jsBlock() throws {
        let list = try rule().splitSourceRule("<js>1+1</js>")
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list[0].mode, .js)
        XCTAssertEqual(list[0].rule, "1+1")
    }
    func testMode_atJs() throws {
        let list = try rule().splitSourceRule("@js:result")
        XCTAssertEqual(list[0].mode, .js)
        XCTAssertEqual(list[0].rule, "result")
    }
    func testMode_webJs() throws {
        let list = try rule().splitSourceRule("@webjs:12345")
        XCTAssertEqual(list[0].mode, .webJs)
        XCTAssertEqual(list[0].rule, "12345")
    }
    func testMode_webJsTooShort() throws {
        // @webjs: 要求 {5,}，不足 5 个字符不匹配 -> 整体当普通规则
        let list = try rule().splitSourceRule("@webjs:1")
        XCTAssertNotEqual(list.first?.mode, .webJs)
    }

    // MARK: - splitSourceRule 混合（前缀 + JS 段）

    func testSplit_textThenJs() throws {
        let list = try rule().splitSourceRule("div@text<js>result</js>")
        XCTAssertEqual(list.count, 2)
        XCTAssertEqual(list[0].mode, .default)
        XCTAssertEqual(list[1].mode, .js)
    }
    func testSplit_empty() throws {
        XCTAssertEqual(try rule().splitSourceRule("").count, 0)
        XCTAssertEqual(try rule().splitSourceRule(nil).count, 0)
    }
}
