//
//  AnalyzeByRegexTests.swift
//  LegadoRuleEngineTests
//
//  AnalyzeByRegex 单元测试（@testable）。≥10 用例：
//  单层、多层（regs 数组）、无匹配返回 nil/空数组、捕获组缺失、多行文本、含中文，
//  以及两个抛错点（正则编译失败、getElement 捕获组未参与）。
//
//  说明：本文件的输入文本/正则均为「合成样本，非真实数据」。
//

import XCTest
@testable import LegadoBookSource

final class AnalyzeByRegexTests: XCTestCase {

    // 1. getElement 单层：命中，返回 group0 + 各捕获组
    func testGetElementSingle() throws {
        let r = try AnalyzeByRegex.getElement("name=张三", ["name=(.+)"])
        XCTAssertEqual(r, ["name=张三", "张三"])
    }
    // 2. getElement 无匹配 -> nil
    func testGetElementNoMatchNil() throws {
        XCTAssertNil(try AnalyzeByRegex.getElement("abc", ["xyz(.+)"]))
    }
    // 3. getElement 无捕获组：只返回 group0
    func testGetElementNoGroup() throws {
        XCTAssertEqual(try AnalyzeByRegex.getElement("hello", ["h.llo"]), ["hello"])
    }
    // 4. getElement 多层：前一层串接所有 match，再喂给下一层
    func testGetElementMultiLayer() throws {
        let html = "<li>A</li><li>B</li>"
        let r = try AnalyzeByRegex.getElement(html, ["<li>[^<]*</li>", "<li>([^<]*)</li>"])
        XCTAssertEqual(r, ["<li>A</li>", "A"])
    }
    // 5. getElement 多行文本
    func testGetElementMultiline() throws {
        let text = "第一行\n第二行"
        let r = try AnalyzeByRegex.getElement(text, ["第.行"])
        XCTAssertEqual(r, ["第一行"])
    }
    // 6. getElement 含中文捕获
    func testGetElementChinese() throws {
        let r = try AnalyzeByRegex.getElement("作者：李四", ["作者：(\\S+)"])
        XCTAssertEqual(r, ["作者：李四", "李四"])
    }

    // 7. getElements 单层：返回所有 match 的分组列表
    func testGetElementsSingle() throws {
        let html = "<a>1</a><a>2</a><a>3</a>"
        let r = try AnalyzeByRegex.getElements(html, ["<a>([^<]*)</a>"])
        XCTAssertEqual(r.count, 3)
        XCTAssertEqual(r[0], ["<a>1</a>", "1"])
        XCTAssertEqual(r[1], ["<a>2</a>", "2"])
        XCTAssertEqual(r[2], ["<a>3</a>", "3"])
    }
    // 8. getElements 无匹配 -> 空数组
    func testGetElementsNoMatchEmpty() throws {
        XCTAssertEqual(try AnalyzeByRegex.getElements("abc", ["z(.+)"]).count, 0)
    }
    // 9. getElements 捕获组缺失 -> 该组取 ""
    func testGetElementsMissingGroupEmpty() throws {
        let r = try AnalyzeByRegex.getElements("X", ["(A)|(X)"])
        XCTAssertEqual(r.count, 1)
        XCTAssertEqual(r[0], ["X", "", "X"])
    }
    // 10. getElements 多层
    func testGetElementsMultiLayer() throws {
        let html = "<li><b>甲</b></li><li><b>乙</b></li>"
        let r = try AnalyzeByRegex.getElements(html, ["<li>.*?</li>", "<b>([^<]*)</b>"])
        XCTAssertEqual(r.count, 2)
        XCTAssertEqual(r[0], ["<b>甲</b>", "甲"])
        XCTAssertEqual(r[1], ["<b>乙</b>", "乙"])
    }
    // 11. getElements 多行 + 中文
    func testGetElementsMultilineChinese() throws {
        let text = "标题:一\n标题:二"
        let r = try AnalyzeByRegex.getElements(text, ["标题:(\\S)"])
        XCTAssertEqual(r.map { $0[1] }, ["一", "二"])
    }
    // 12. getElement 所有组都参与的正常路径
    func testGetElementAllGroupsParticipate() throws {
        let r = try AnalyzeByRegex.getElement("AB", ["(A)(B)"])
        XCTAssertEqual(r, ["AB", "A", "B"])
    }

    // MARK: 抛错点（第 1 点：崩溃收敛为 RuleEngineError）

    // 13. 正则编译失败 -> 抛 RuleEngineError.regexCompileFailed（getElement）
    func testGetElementBadPatternThrows() {
        // 非法正则：未闭合的分组
        XCTAssertThrowsError(try AnalyzeByRegex.getElement("x", ["(unclosed"])) { error in
            guard case RuleEngineError.regexCompileFailed = error else {
                return XCTFail("应抛 regexCompileFailed，实际：\(error)")
            }
        }
    }
    // 14. 正则编译失败 -> 抛 RuleEngineError.regexCompileFailed（getElements）
    func testGetElementsBadPatternThrows() {
        XCTAssertThrowsError(try AnalyzeByRegex.getElements("x", ["("])) { error in
            guard case RuleEngineError.regexCompileFailed = error else {
                return XCTFail("应抛 regexCompileFailed，实际：\(error)")
            }
        }
    }
    // 15. getElement 最后规则里捕获组未参与匹配 -> 抛 RuleEngineError.regexGroupNotParticipated
    func testGetElementMissingGroupThrows() {
        // (A)|(X) 匹配 "X" 时，第 1 组 (A) 未参与；getElement 最后规则收集全部组 -> 抛错
        XCTAssertThrowsError(try AnalyzeByRegex.getElement("X", ["(A)|(X)"])) { error in
            guard case RuleEngineError.regexGroupNotParticipated(let idx, _) = error else {
                return XCTFail("应抛 regexGroupNotParticipated，实际：\(error)")
            }
            XCTAssertEqual(idx, 1)
        }
    }
}
