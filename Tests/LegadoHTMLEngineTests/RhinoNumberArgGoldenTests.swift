//
//  RhinoNumberArgGoldenTests.swift
//  LegadoHTMLEngineTests
//
//  Step 5 收尾：JS number → Java String 参数的真实转换，不再有任何手写假设。
//
//  golden `cases/js_number_args.json` 由真实 Rhino 1.8.1 跑出：把 JsExtensions 同名同签名的
//  探针绑成脚本里的 `java`，执行 `java.<method>(<字面量>)`，记录 Rhino 实际传给 String 参数的
//  那一串（原理见 NumberArgGen.java 顶部注释；legado 走的是同一条 Rhino 转换路径）。
//
//  三个层次逐条比较（全部 0 容忍）：
//   1. JSC 自己的 `String(<literal>)` 必须等于 Rhino 的转换结果 —— 证明两个引擎的
//      Number::toString 一致（这是 `java` 桥接可行性的前提）；
//   2. 本移植实际使用的 `JsNumberFormat.toString(Double(literal))` 必须等于 Rhino 的转换结果
//      —— 这是 `JsExtensionsRuntime.stringify` 真实走的那条路；
//   3. 走完整 AnalyzeRule(`<js>java.xxx(字面量)</js>`) 调用的结果必须等于 golden 的 callResult
//      —— 端到端验证桥接 + 运行时 + 纯算法实现。
//
//  CI 下 golden 缺失必须 fail（不许 XCTSkip）。
//

import XCTest
import JavaScriptCore
@testable import LegadoBookSource

final class RhinoNumberArgGoldenTests: XCTestCase {

    private struct NumberArgCase: Decodable {
        let name: String
        let method: String
        let literal: String
        let javaReceived: String?
        let callResult: String?
        let error: String?
    }

    private struct Envelope: Decodable { let numberArgResults: [NumberArgCase]? }

    private func goldenFile() -> URL? {
        guard let resourceURL = Bundle.module.resourceURL else { return nil }
        let direct = resourceURL.appendingPathComponent("golden/js_number_args.json")
        if FileManager.default.fileExists(atPath: direct.path) { return direct }
        if let en = FileManager.default.enumerator(at: resourceURL, includingPropertiesForKeys: nil) {
            for case let f as URL in en where f.lastPathComponent == "js_number_args.json" { return f }
        }
        return nil
    }

    private func isRunningInCI() -> Bool {
        let env = ProcessInfo.processInfo.environment
        for key in ["CI", "GITHUB_ACTIONS", "GITHUB_WORKFLOW", "GITHUB_RUN_ID", "RUNNER_OS"] {
            if let v = env[key], !v.isEmpty { return true }
        }
        return false
    }

    private func loadCases() throws -> [NumberArgCase] {
        guard let file = goldenFile() else {
            if isRunningInCI() {
                XCTFail("CI 环境下 golden 缺失（js_number_args.json），不允许静默跳过")
            }
            throw XCTSkip("js_number_args.json 缺失（本地未跑 golden job）。")
        }
        let data = try Data(contentsOf: file)
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        guard let cases = envelope.numberArgResults, !cases.isEmpty else {
            if isRunningInCI() {
                XCTFail("CI 环境下 golden 为空（js_number_args.json），不允许静默跳过")
            }
            throw XCTSkip("js_number_args.json 为空。")
        }
        return cases
    }

    /// 1) JSC 的 `String(x)` 与 Rhino 的 Java 参数转换必须一致。
    func testJsEngineStringConversionMatchesRhino() throws {
        let cases = try loadCases()
        var failures: [String] = []
        guard let context = JSContext() else { XCTFail("无法创建 JSContext"); return }
        for c in cases {
            let value = context.evaluateScript("String(\(c.literal))")?.toString()
            if value != c.javaReceived {
                failures.append("[\(c.name)] String(\(c.literal)) JSC=\(value ?? "<nil>") Rhino=\(c.javaReceived ?? "<nil>")")
            }
        }
        if !failures.isEmpty {
            XCTFail("JSC 与 Rhino 的数字→字符串不一致 \(failures.count) 处：\n" + failures.joined(separator: "\n"))
        }
    }

    /// 2) 本移植实际使用的 JsNumberFormat（ECMAScript Number::toString 复刻）与 Rhino 一致。
    func testJsNumberFormatMatchesRhino() throws {
        let cases = try loadCases()
        var failures: [String] = []
        for c in cases {
            guard let d = Double(c.literal) else {
                // 5e-324 这类次正规数 Double(_) 仍可解析；解析失败视为错误。
                failures.append("[\(c.name)] Swift 无法解析字面量 \(c.literal)")
                continue
            }
            let formatted = JsNumberFormat.toString(d)
            if formatted != c.javaReceived {
                failures.append("[\(c.name)] JsNumberFormat(\(c.literal))=\(formatted) Rhino=\(c.javaReceived ?? "<nil>")")
            }
        }
        if !failures.isEmpty {
            XCTFail("JsNumberFormat 与 Rhino 不一致 \(failures.count) 处：\n" + failures.joined(separator: "\n"))
        }
    }

    /// 3) 端到端：AnalyzeRule 里 `<js>java.<method>(<字面量>)</js>` 的结果 == golden 的 callResult。
    func testAnalyzeRuleCallPathMatchesRhino() throws {
        let cases = try loadCases()
        var failures: [String] = []
        for c in cases where c.error == nil {
            let rule = "<js>java.\(c.method)(\(c.literal))</js>"
            let a = AnalyzeRule()
            do {
                try a.setContent("")
                let got = try a.getString(rule)
                if got != c.callResult {
                    failures.append("[\(c.name)] \(rule) Swift=\(got ?? "<nil>") Rhino=\(c.callResult ?? "<nil>")")
                }
            } catch {
                failures.append("[\(c.name)] \(rule) Swift 抛错 \(error) Rhino=\(c.callResult ?? "<nil>")")
            }
        }
        if !failures.isEmpty {
            XCTFail("analyzeRule 数字入参调用链与 Rhino 不一致 \(failures.count) 处：\n" + failures.joined(separator: "\n"))
        }
    }
}
