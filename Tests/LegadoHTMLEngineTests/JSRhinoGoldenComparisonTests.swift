// 规则/输入均为合成样本；Java 结果来自真实 Rhino 1.8.1 golden artifact。
// 不将 JS 内部 String(x) 与 Kotlin/Java raw.toString() 混为一谈。
import XCTest
@testable import LegadoBookSource

final class JSRhinoGoldenComparisonTests: XCTestCase {
    private struct Envelope: Decodable { let jsResults: [Result] }
    private struct Result: Decodable {
        let name: String
        let js: String
        let result: String?
        let rawType: String?
        let evalType: String?
        let getString: String?
        let inlineString: String?
        let error: String?
    }

    private func cases() throws -> [Result] {
        let resource = try XCTUnwrap(Bundle.module.resourceURL)
        let expected = resource.appendingPathComponent("golden/js_rhino.json")
        var file: URL? = FileManager.default.fileExists(atPath: expected.path) ? expected : nil
        if file == nil, let enumerator = FileManager.default.enumerator(at: resource, includingPropertiesForKeys: nil) {
            for case let url as URL in enumerator where url.lastPathComponent == "js_rhino.json" {
                file = url
                break
            }
        }
        guard let file = file else {
            // CI golden 缺失必须失败。也要求本地运行此套测试先生成 golden，不静默跳过。
            XCTFail("Rhino 1.8.1 golden 缺失：golden/js_rhino.json（不允许 XCTSkip）")
            return []
        }
        let envelope = try JSONDecoder().decode(Envelope.self, from: Data(contentsOf: file))
        XCTAssertEqual(envelope.jsResults.count, 70, "Rhino golden 应保留全部 70 条合成片段")
        XCTAssertEqual(Set(envelope.jsResults.map { $0.name }).count, envelope.jsResults.count)
        return envelope.jsResults
    }

    private func report(_ c: Result, path: String, java: String?, swift: String) -> String {
        """
        [JS Rhino/\(c.name) \(path)]
          js: \(c.js)
          result binding: \(c.result ?? "<null>")
          rawType: \(c.rawType ?? "<missing>") (evalType: \(c.evalType ?? "<missing>"))
          Java: \(java.debugDescription) error: \(c.error ?? "<none>")
          Swift: \(swift.debugDescription)
        """
    }

    func testGoldenJSGetString() throws {
        for c in try cases() {
            let a = AnalyzeRule()
            let binding: RuleValue = c.result.map { .string($0) } ?? .null
            // getString 调度要求非空 content；无 result 的片段均不读 result，此处用合成 content。
            try a.setContent("synthetic")
            do {
                let raw = try a.evalJS(c.js, result: binding)
                let swiftRaw = raw.isNull ? "" : raw.stringValue
                XCTAssertEqual(swiftRaw, c.getString, report(c, path: "evalJS raw.toString", java: c.getString, swift: swiftRaw))
                let rules = try a.splitSourceRule("@js:" + c.js)
                let swiftFinal = try a.getString(ruleList: rules, mContent: c.result.map { .string($0) }, unescape: false)
                XCTAssertEqual(swiftFinal, c.getString, report(c, path: "getString Mode.Js", java: c.getString, swift: swiftFinal))
                XCTAssertNil(c.error, report(c, path: "Java eval error", java: c.getString, swift: swiftFinal))
            } catch {
                XCTFail(report(c, path: "getString throw", java: c.getString, swift: String(describing: error)))
            }
        }
    }

    func testGoldenJSInlineMakeUpRule() throws {
        for c in try cases() {
            let a = AnalyzeRule()
            try a.setContent("synthetic")
            let binding: RuleValue = c.result.map { .string($0) } ?? .null
            do {
                // 直接测 SourceRule.makeUpRule：不会把最终文字误作 CSS，也避免额外实体解码。
                let rule = try SourceRule("{{" + c.js + "}}", owner: a)
                try rule.makeUpRule(binding)
                XCTAssertEqual(rule.rule, c.inlineString, report(c, path: "inline {{}}", java: c.inlineString, swift: rule.rule))
                XCTAssertNil(c.error, report(c, path: "Java eval error", java: c.inlineString, swift: rule.rule))
            } catch {
                XCTFail(report(c, path: "inline throw", java: c.inlineString, swift: String(describing: error)))
            }
        }
    }
}
