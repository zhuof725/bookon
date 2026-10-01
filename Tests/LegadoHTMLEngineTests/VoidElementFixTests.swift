//
//  VoidElementFixTests.swift
//  LegadoHTMLEngineTests
//
//  Step4-A 更新：原先的字符串级后处理 `SwiftSoupVoidElementFix` 已被删除，void 元素
//  （<img>/<br>/<hr> 等）的自闭合格式问题现在由 `JsoupCompatSerializer` 从零按 jsoup
//  真实算法重新生成 HTML 字符串直接保证正确，不再需要任何后处理补丁。
//  本文件保留的端到端用例（经由 AnalyzeByXPath / AnalyzeByJSoup 走完整规则引擎）继续验证
//  这一行为；原先针对 `SwiftSoupVoidElementFix.fix()` 的直接单元测试已随该类型一起删除。
//
//  ⚠️ 本文件全部 HTML 均为合成样本，非真实数据。
//

import XCTest
@testable import LegadoBookSource
import SwiftSoup

final class VoidElementFixTests: XCTestCase {

    func testImgTagNoSelfClosingSlash() throws {
        let html = "<div><img src='/c/1.jpg'></div>"
        let x = try AnalyzeByXPath(html)
        let r = try x.getStringList("//div")
        XCTAssertEqual(r.count, 1)
        XCTAssertTrue(r[0].contains("<img src=\"/c/1.jpg\">"), "实际: \(r[0])")
        XCTAssertFalse(r[0].contains("/>"), "不应含自闭合斜杠，实际: \(r[0])")
    }

    func testBrTagNoSelfClosingSlash() throws {
        let html = "<p>第一行<br>第二行</p>"
        let j = try AnalyzeByJSoup(html)
        let html2 = try j.getString("tag.p@html")
        XCTAssertNotNil(html2)
        XCTAssertTrue(html2!.contains("<br>"), "实际: \(html2!)")
        XCTAssertFalse(html2!.contains("<br/>") || html2!.contains("<br />"), "实际: \(html2!)")
    }

    func testHrTagNoSelfClosingSlash() throws {
        let html = "<div><hr></div>"
        let j = try AnalyzeByJSoup(html)
        let all = try j.getString("tag.div@all")
        XCTAssertNotNil(all)
        XCTAssertTrue(all!.contains("<hr>"), "实际: \(all!)")
        XCTAssertFalse(all!.contains("<hr/>") || all!.contains("<hr />"), "实际: \(all!)")
    }

    func testMultipleVoidElementsInOneDoc() throws {
        let html = "<div><img src='a.jpg'><br><hr><img src='b.jpg'></div>"
        let x = try AnalyzeByXPath(html)
        let r = try x.getString("//div")
        XCTAssertNotNil(r)
        XCTAssertFalse(r!.contains("/>"), "实际: \(r!)")
        XCTAssertTrue(r!.contains("<img src=\"a.jpg\">"))
        XCTAssertTrue(r!.contains("<img src=\"b.jpg\">"))
        XCTAssertTrue(r!.contains("<br>"))
        XCTAssertTrue(r!.contains("<hr>"))
    }

    func testNonVoidElementUnaffected() throws {
        // 非 void 标签（如 <a>）不应被误改
        let html = "<div><a href='/x'>链接</a></div>"
        let x = try AnalyzeByXPath(html)
        let r = try x.getString("//div")
        XCTAssertEqual(r, "<div>\n <a href=\"/x\">链接</a>\n</div>")
    }
}
