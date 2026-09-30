//
//  RuleEnginePublicAPITests.swift
//  LegadoRuleEnginePublicAPITests
//
//  纯 public 接口测试：普通 `import LegadoBookSource`（非 @testable）。
//  只通过 public 接口调用 RuleAnalyzer、AnalyzeByRegex、AnalyzeByJSonPath 的全部对外方法，
//  以及 JSONPathEvaluator / DefaultJSONPathEvaluator / JSONValue / 诊断收集器。
//  若任何对外成员漏 public，本 target 会编译失败。
//

import XCTest
import LegadoBookSource   // 注意：不是 @testable

final class RuleEnginePublicAPITests: XCTestCase {

    // MARK: RuleAnalyzer 全部 public 方法

    func testRuleAnalyzerPublicAPI() {
        // 可变参数版 splitRule
        let r1 = RuleAnalyzer("a&&b&&c")
        let parts1 = r1.splitRule("&&")
        XCTAssertEqual(parts1, ["a", "b", "c"])
        XCTAssertEqual(r1.elementsType, "&&")

        // 数组版 splitRule
        let r2 = RuleAnalyzer("a||b", code: true)
        XCTAssertEqual(r2.splitRule(["&&", "||"]), ["a", "b"])

        // reSetPos + innerRule("{$.") { ... }
        let r3 = RuleAnalyzer("x={$.v}", code: true)
        r3.reSetPos()
        XCTAssertEqual(r3.innerRule("{$.") { _ in "1" }, "x=1")

        // innerRule(start, end) 重载
        let r4 = RuleAnalyzer("a<b>c</b>d")
        XCTAssertEqual(r4.innerRule("<b>", "</b>") { _ in "B" }, "aBd")

        // trim
        let r5 = RuleAnalyzer("@@x")
        r5.trim()
        XCTAssertEqual(r5.splitRule("&&"), ["x"])
    }

    // MARK: AnalyzeByRegex 全部 public 方法

    func testAnalyzeByRegexPublicAPI() {
        let e = AnalyzeByRegex.getElement("k=v", ["k=(.+)"])
        XCTAssertEqual(e, ["k=v", "v"])

        let es = AnalyzeByRegex.getElements("<i>1</i><i>2</i>", ["<i>([^<]*)</i>"])
        XCTAssertEqual(es.count, 2)

        // 带诊断收集器的重载
        let diag = RuleEngineDiagnostics()
        _ = AnalyzeByRegex.getElement("abc", ["z(.+)"], index: 0, diagnostics: diag)
        // 无匹配返回 nil，不产生诊断
        XCTAssertTrue(diag.diagnostics.isEmpty)
    }

    // MARK: AnalyzeByJSonPath 全部 public 方法 + JSONValue + 诊断

    func testAnalyzeByJSonPathPublicAPI() throws {
        let json = #"{ "a": { "b": [1,2,3] }, "s": "hi" }"#

        // 字符串构造
        let a = AnalyzeByJSonPath(json)
        XCTAssertEqual(a.getString("$.s"), "hi")
        XCTAssertEqual(a.getString("$.a.b[*]"), "1\n2\n3")
        XCTAssertEqual(a.getStringList("$.a.b[*]"), ["1", "2", "3"])
        XCTAssertEqual(a.getList("$.a.b[*]")?.count, 3)
        XCTAssertEqual(try a.getObject("$.s"), JSONValue.string("hi"))

        // JSONValue 构造 + parse
        let v = JSONValue.parse(json)!
        let a2 = AnalyzeByJSonPath(v)
        XCTAssertEqual(a2.getString("$.s"), "hi")

        // 显式指定 evaluator 类型 + 诊断收集器
        let diag = RuleEngineDiagnostics()
        let a3 = AnalyzeByJSonPath(v, evaluatorType: DefaultJSONPathEvaluator.self, diagnostics: diag)
        XCTAssertEqual(a3.getString("$.nope"), "")   // 读取失败返回空串
        XCTAssertFalse(diag.diagnostics.isEmpty)      // 失败被记入诊断（默认关闭，这里显式开启）
        let d = diag.diagnostics.first!
        XCTAssertEqual(d.source, "AnalyzeByJSonPath.getString")

        // parse 静态方法
        _ = AnalyzeByJSonPath.parse(json)
        _ = AnalyzeByJSonPath.parse(v)
    }

    // MARK: JSONPathEvaluator 协议 + DefaultJSONPathEvaluator 直接使用

    func testJSONPathEvaluatorProtocolPublic() throws {
        let root = JSONValue.parse(#"{ "arr": [ {"x":1}, {"x":2} ] }"#)!
        let evaluator: JSONPathEvaluator = DefaultJSONPathEvaluator(root: root)
        let result = try evaluator.read("$.arr[*].x")
        if case .list(let vs) = result {
            XCTAssertEqual(vs, [.number(1), .number(2)])
        } else {
            XCTFail("indefinite path 应返回 list")
        }

        // definite path 返回 single
        let single = try evaluator.read("$.arr[0].x")
        XCTAssertEqual(single, .single(.number(1)))

        // JSONValue 的 public 成员
        XCTAssertEqual(JSONValue.number(3).stringValue, "3")
        XCTAssertEqual(JSONValue.bool(false).stringValue, "false")
        _ = JSONValue.string("x").toFoundation()
    }

    // MARK: 诊断结构体 public

    func testDiagnosticsStructPublic() {
        let diag = RuleEngineDiagnostics()
        diag.record(source: "s", rule: "r", message: "m")
        let all = diag.drain()
        XCTAssertEqual(all.first, RuleEngineDiagnostic(source: "s", rule: "r", message: "m"))
        XCTAssertTrue(diag.diagnostics.isEmpty)  // drain 后清空
    }
}
