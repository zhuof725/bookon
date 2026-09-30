//
//  AnalyzeByRegexTests.swift
//  LegadoRuleEngineTests
//
//  AnalyzeByRegex 单元测试（@testable）。≥10 用例：
//  单层、多层（regs 数组）、无匹配返回 nil/空数组、捕获组缺失、多行文本、含中文。
//
//  说明：本文件的输入文本/正则均为「合成样本，非真实数据」。
//

import XCTest
@testable import LegadoBookSource

final class AnalyzeByRegexTests: XCTestCase {

    // 1. getElement 单层：命中，返回 group0 + 各捕获组
    func testGetElementSingle() {
        let r = AnalyzeByRegex.getElement("name=张三", ["name=(.+)"])
        XCTAssertEqual(r, ["name=张三", "张三"])
    }
    // 2. getElement 无匹配 -> nil
    func testGetElementNoMatchNil() {
        XCTAssertNil(AnalyzeByRegex.getElement("abc", ["xyz(.+)"]))
    }
    // 3. getElement 无捕获组：只返回 group0
    func testGetElementNoGroup() {
        XCTAssertEqual(AnalyzeByRegex.getElement("hello", ["h.llo"]), ["hello"])
    }
    // 4. getElement 多层：前一层串接所有 match，再喂给下一层
    func testGetElementMultiLayer() {
        // 第一层匹配所有 <li>..</li> 串接；第二层从串接结果抽出文本
        let html = "<li>A</li><li>B</li>"
        let r = AnalyzeByRegex.getElement(html, ["<li>[^<]*</li>", "<li>([^<]*)</li>"])
        // 第二层 find() 命中第一个，最后一层取 group0+group1
        XCTAssertEqual(r, ["<li>A</li>", "A"])
    }
    // 5. getElement 多行文本
    func testGetElementMultiline() {
        let text = "第一行\n第二行"
        let r = AnalyzeByRegex.getElement(text, ["第.行"])
        XCTAssertEqual(r, ["第一行"])
    }
    // 6. getElement 含中文捕获
    func testGetElementChinese() {
        let r = AnalyzeByRegex.getElement("作者：李四", ["作者：(\\S+)"])
        XCTAssertEqual(r, ["作者：李四", "李四"])
    }

    // 7. getElements 单层：返回所有 match 的分组列表
    func testGetElementsSingle() {
        let html = "<a>1</a><a>2</a><a>3</a>"
        let r = AnalyzeByRegex.getElements(html, ["<a>([^<]*)</a>"])
        XCTAssertEqual(r.count, 3)
        XCTAssertEqual(r[0], ["<a>1</a>", "1"])
        XCTAssertEqual(r[1], ["<a>2</a>", "2"])
        XCTAssertEqual(r[2], ["<a>3</a>", "3"])
    }
    // 8. getElements 无匹配 -> 空数组
    func testGetElementsNoMatchEmpty() {
        XCTAssertEqual(AnalyzeByRegex.getElements("abc", ["z(.+)"]).count, 0)
    }
    // 9. getElements 捕获组缺失 -> 该组取 ""
    func testGetElementsMissingGroupEmpty() {
        // 交替里其中一支不参与匹配，缺失组应为 ""
        let r = AnalyzeByRegex.getElements("X", ["(A)|(X)"])
        XCTAssertEqual(r.count, 1)
        // group0="X", group1(未参与)="", group2="X"
        XCTAssertEqual(r[0], ["X", "", "X"])
    }
    // 10. getElements 多层
    func testGetElementsMultiLayer() {
        let html = "<li><b>甲</b></li><li><b>乙</b></li>"
        let r = AnalyzeByRegex.getElements(html, ["<li>.*?</li>", "<b>([^<]*)</b>"])
        XCTAssertEqual(r.count, 2)
        XCTAssertEqual(r[0], ["<b>甲</b>", "甲"])
        XCTAssertEqual(r[1], ["<b>乙</b>", "乙"])
    }
    // 11. getElements 多行 + 中文
    func testGetElementsMultilineChinese() {
        let text = "标题:一\n标题:二"
        let r = AnalyzeByRegex.getElements(text, ["标题:(\\S)"])
        XCTAssertEqual(r.map { $0[1] }, ["一", "二"])
    }
    // 12. getElement 捕获组缺失 -> 触发致命（对齐 Kotlin NPE）。
    //     这里只验证「所有组都参与」的正常路径不崩，作为缺失分支的对照说明。
    func testGetElementAllGroupsParticipate() {
        let r = AnalyzeByRegex.getElement("AB", ["(A)(B)"])
        XCTAssertEqual(r, ["AB", "A", "B"])
    }
}
