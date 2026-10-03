//
//  JsoupBridgeGoldenComparisonTests.swift
//  LegadoHTMLEngineTests
//
//  Step 5 收尾：org.jsoup.Jsoup 替身（JsoupJSBridge，基于 SwiftSoup）与**真实 jsoup 1.16.2**
//  的 golden 逐条对照。
//
//  golden 由 `scripts/golden`（真实 jsoup 1.16.2 + 真实 Rhino 1.8.1）生成：
//  每条用例是一条 JS 表达式 + 一份 HTML；Java 侧用 Rhino 求值（classpath 上是真实 jsoup），
//  Swift 侧用 JavaScriptCore + JsoupJSBridge 求值同一条 JS，两边比较
//  「结果字符串 / null / 抛错」三态。
//
//  用例来源：`scripts/extract_jsoup_chains.py` 从仓库内真实书源配置（配置文件_7个.json +
//  taiwan_real_source.json）提取的 jsoup 链（爱丽丝书屋、台湾小说网），外加替身对外承诺的
//  first/eq/outerHtml 与不规范 HTML（未闭合标签 / 无 tbody 表格 / 大写标签 / 实体字符）。
//
//  CI 下 golden 缺失必须 fail（不许 XCTSkip）。
//

import XCTest
import JavaScriptCore
@testable import LegadoBookSource

final class JsoupBridgeGoldenComparisonTests: XCTestCase {

    private enum Outcome: Equatable {
        case threw
        case null
        case value(String)
    }

    private struct GoldenCase: Decodable {
        let name: String
        let js: String
        let html: String
        let source: String?
        /// 已登记到 README 差异表的不可对齐项（见测试内注释）。普通用例为 nil。
        let knownDivergence: String?
        let result: ValueBox?
        let error: String?
    }

    private enum ValueBox: Decodable {
        case null
        case string(String)
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if c.decodeNil() { self = .null; return }
            self = .string(try c.decode(String.self))
        }
    }

    private struct Envelope: Decodable { let jsoupResults: [GoldenCase]? }

    private func goldenFile() -> URL? {
        guard let resourceURL = Bundle.module.resourceURL else { return nil }
        let direct = resourceURL.appendingPathComponent("golden/jsoup_cases.json")
        if FileManager.default.fileExists(atPath: direct.path) { return direct }
        if let en = FileManager.default.enumerator(at: resourceURL, includingPropertiesForKeys: nil) {
            for case let f as URL in en where f.lastPathComponent == "jsoup_cases.json" { return f }
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

    private func failWhenNoGolden() throws {
        if isRunningInCI() {
            XCTFail("CI 环境下 golden 对照数据缺失或为空（jsoup_cases.json），不允许静默跳过")
            return
        }
        throw XCTSkip("jsoup_cases.json 缺失（本地未跑 golden job）。")
    }

    /// 用 JSC + 替身求值同一条 JS；`java` 只提供真实书源链里用到的 `t2s`
    /// （Java 侧绑定的是真实 quick-chinese-transfer 探针，两边语义一致）。
    private func evaluate(_ js: String, html: String) -> Outcome {
        guard let context = JSContext() else { return .threw }
        var thrown = false
        context.exceptionHandler = { _, _ in thrown = true }
        JsoupJSBridge(diagnostics: nil).install(into: context)

        let t2s: @convention(block) (JSValue) -> String = { value in
            JsExtensionsCore.t2s(value.toString() ?? "")
        }
        let java = JSValue(newObjectIn: context)
        java?.setObject(t2s, forKeyedSubscript: "t2s" as NSString)
        context.setObject(java, forKeyedSubscript: "java" as NSString)

        context.setObject(html, forKeyedSubscript: "result" as NSString)
        let value = context.evaluateScript(js)
        if thrown || context.exception != nil { return .threw }
        guard let value = value, !value.isUndefined, !value.isNull else { return .null }
        return .value(value.toString() ?? "")
    }

    private func javaOutcome(_ c: GoldenCase) -> Outcome {
        if c.error != nil { return .threw }
        switch c.result {
        case .some(.string(let s)): return .value(s)
        default: return .null
        }
    }

    func testGoldenJsoupBridge() throws {
        guard let file = goldenFile() else {
            try failWhenNoGolden()
            return
        }
        let data = try Data(contentsOf: file)
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              let cases = envelope.jsoupResults, !cases.isEmpty else {
            try failWhenNoGolden()
            return
        }
        var failures: [String] = []
        var compared = 0
        var divergencesChecked = 0
        for c in cases {
            if let kind = c.knownDivergence {
                divergencesChecked += 1
                let swift = evaluate(c.js, html: c.html)
                let java = javaOutcome(c)
                // 已登记差异：这里确认差异**仍然存在**。若哪天对齐了，本测试会失败并提醒更新
                // README 差异表与这条登记（不允许"悄悄变绿"）。
                if java == swift {
                    failures.append("[已知差异已消失] \(c.name) (\(kind))：Java 与 Swift 结果相同（\(swift)），"
                                    + "请更新 README 差异表并删除本登记")
                }
                if kind == "javaStringWrapping", swift != .value("number") {
                    failures.append("[已知差异前提变化] \(c.name)：JSC 侧 typeof <js string>.length 期望 \"number\"，实际 \(swift)")
                }
                continue
            }
            compared += 1
            let swift = evaluate(c.js, html: c.html)
            let java = javaOutcome(c)
            if java != swift {
                failures.append("""
                [jsoup/\(c.name)]
                  来源: \(c.source ?? "-")
                  js: \(c.js)
                  html: \(c.html)
                  Java: \(java) error: \(c.error ?? "<none>")
                  Swift: \(swift)
                """)
            }
        }
        XCTAssertGreaterThanOrEqual(compared, 40, "jsoup golden 严格对照用例数不足 40 条")
        XCTAssertEqual(divergencesChecked, 1, "已登记差异用例数变化（README 差异表需要同步）")
        if !failures.isEmpty {
            XCTFail("发现 \(failures.count)/\(compared) 处 jsoup 替身与真实 jsoup 不一致：\n\n"
                    + failures.joined(separator: "\n\n"))
        }
    }
}
