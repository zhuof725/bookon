//
//  HTMLEnginePublicAPITests.swift
//  LegadoHTMLEnginePublicAPITests
//
//  纯 public 接口测试：普通 import（非 @testable）。
//  通过 public 接口调用 AnalyzeByJSoup / AnalyzeByXPath / XPathEvaluator 协议的全部对外方法。
//  若任何对外成员漏 public，本 target 会编译失败。
//
//  ⚠️ 本文件全部 HTML 均为合成样本，非真实数据。
//

import XCTest
import LegadoBookSource
import SwiftSoup

final class HTMLEnginePublicAPITests: XCTestCase {

    func testAnalyzeByJSoupPublicAPI() throws {
        let html = "<div class='a'><p>甲</p><p>乙</p></div><a href='/x'>链接</a>"
        let j = try AnalyzeByJSoup(html)
        XCTAssertEqual(try j.getStringList("class.a@tag.p@text"), ["甲", "乙"])
        XCTAssertEqual(try j.getString("class.a@tag.p@text"), "甲\n乙")
        XCTAssertEqual(try j.getString0("class.a@tag.p@text"), "甲")
        let els = try j.getElements("tag.p")
        XCTAssertEqual(els.size(), 2)

        // 带诊断收集器
        let diag = RuleEngineDiagnostics()
        let j2 = try AnalyzeByJSoup(html, diagnostics: diag)
        _ = try j2.getStringList("class.a@tag.p@text")

        // Element 入参
        let doc = try SwiftSoup.parse(html)
        if let el = try doc.select("div").first() {
            let j3 = try AnalyzeByJSoup(el)
            _ = try j3.getStringList("tag.p@text")
        }

        // 抛错：无效选择器
        XCTAssertThrowsError(try j.getElements("::::bad")) { error in
            guard case RuleEngineError.invalidSelector = error else {
                return XCTFail("应抛 invalidSelector，实际 \(error)")
            }
        }
    }

    func testAnalyzeByXPathPublicAPI() throws {
        let html = "<div><a href='/x'>链接</a><a href='/y'>链接2</a></div>"
        let x = try AnalyzeByXPath(html)
        XCTAssertEqual(try x.getStringList("//a/@href"), ["/x", "/y"])
        XCTAssertEqual(try x.getString("//a[1]/@href"), "/x")
        let els = try x.getElements("//a")
        XCTAssertEqual(els?.count, 2)

        // 显式指定 evaluator 类型 + 诊断收集器
        let diag = RuleEngineDiagnostics()
        let x2 = try AnalyzeByXPath(html, evaluatorType: SwiftSoupXPathEvaluator.self, diagnostics: diag)
        _ = try x2.getStringList("//a/@href")

        // Element / Elements 入参
        let doc = try SwiftSoup.parse(html)
        if let div = try doc.select("div").first() {
            let x3 = try AnalyzeByXPath(div)
            _ = try x3.getStringList(".//a/@href")
        }

        // XPathNode public 成员
        if let node = try x.getElements("//a")?.first {
            _ = node.isElement
            _ = node.asElement()
            _ = node.asString()
            _ = node.toStringValue()
        }
    }

    func testXPathEvaluatorProtocolPublic() throws {
        let doc = try SwiftSoup.parse("<div><p>x</p></div>")
        let evaluator: XPathEvaluator = SwiftSoupXPathEvaluator(roots: [doc])
        let result = try evaluator.evaluate("//p/text()")
        XCTAssertEqual(result.first?.asString(), "x")
    }

    func testRuleEngineErrorHTMLCasesPublic() {
        // 确认新增的 error case 可从模块外访问
        let e1 = RuleEngineError.invalidSelector("x")
        let e2 = RuleEngineError.invalidXPath("y")
        let e3 = RuleEngineError.invalidHTML("z")
        XCTAssertNotNil(e1.errorDescription)
        XCTAssertNotNil(e2.errorDescription)
        XCTAssertNotNil(e3.errorDescription)
    }
}
