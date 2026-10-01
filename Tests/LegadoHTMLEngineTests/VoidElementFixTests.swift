//
//  VoidElementFixTests.swift
//  LegadoHTMLEngineTests
//
//  测试 SwiftSoupVoidElementFix：修正 SwiftSoup 2.9.6 自身把 HTML 语法下的 void 元素
//  （<img>/<br>/<hr> 等）outerHtml 错误渲染为自闭合 `<img ... />` 的 bug，
//  对齐真实 jsoup 的 `<img ...>`（无斜杠）输出。
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

    func testVoidElementFixDirectUnitTest() {
        // 直接测试 SwiftSoupVoidElementFix.fix 的字符串处理逻辑
        XCTAssertEqual(
            SwiftSoupVoidElementFix.fix("<img src=\"x.jpg\" />"),
            "<img src=\"x.jpg\">"
        )
        XCTAssertEqual(
            SwiftSoupVoidElementFix.fix("<br />"),
            "<br>"
        )
        XCTAssertEqual(
            SwiftSoupVoidElementFix.fix("<a href=\"x\" />"),
            // 非 void 标签原样保留（这个输入本不会由 SwiftSoup 产生，仅测试函数自身不误伤）
            "<a href=\"x\" />"
        )
        XCTAssertEqual(
            SwiftSoupVoidElementFix.fix("<div>没有自闭合标签的普通文本</div>"),
            "<div>没有自闭合标签的普通文本</div>"
        )
    }
}
