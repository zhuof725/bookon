//
//  AnalyzeUrlGoldenComparisonTests.swift
//  LegadoNetworkTests
//
//  第 6 步 6A：AnalyzeUrl 的规则解析 / 编码 / UrlOption 与**真实 Java 库**的 golden 逐条对照。
//
//  golden 由 `scripts/golden`（hutool 5.8.22 + gson 2.13.2 + 真实 Rhino 1.8.1）生成：
//   - `url_codec_cases.json`     -> codecResults     （encodeParams / encodedQuery / encodedForm / escape）
//   - `url_option_cases.json`    -> urlOptionResults （UrlOption 的 Gson 宽松解析）
//   - `analyze_url_cases.json`   -> analyzeUrlResults（paramPattern / 页码规则 / {{}} / @js 调度）
//
//  CI 下 golden 缺失必须 fail（不许 XCTSkip）。
//

import XCTest
@testable import LegadoBookSource

final class AnalyzeUrlGoldenComparisonTests: XCTestCase {

    // MARK: - golden 读取

    private func goldenFile(_ name: String) -> URL? {
        guard let resourceURL = Bundle.module.resourceURL else { return nil }
        let direct = resourceURL.appendingPathComponent("golden/\(name)")
        if FileManager.default.fileExists(atPath: direct.path) { return direct }
        if let en = FileManager.default.enumerator(at: resourceURL, includingPropertiesForKeys: nil) {
            for case let f as URL in en where f.lastPathComponent == name { return f }
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

    /// 失败信息里把 '%' 转成 '%%'：XCTest 会把消息当 printf 格式串处理，不转义时
    /// "%39" 这类片段会被吞掉，日志里看到的就是失真的值。
    private func esc(_ s: String) -> String {
        return s.replacingOccurrences(of: "%", with: "%%")
    }

    private func load<T: Decodable>(_ file: String, as type: T.Type, key: String) throws -> [T]? {
        guard let url = goldenFile(file), let data = try? Data(contentsOf: url) else {
            if isRunningInCI() {
                XCTFail("CI 环境下 golden 缺失（\(file)），不允许静默跳过")
            }
            throw XCTSkip("\(file) 缺失（本地未跑 golden job）。")
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = obj[key] as? [Any] else {
            if isRunningInCI() { XCTFail("CI 环境下 golden 结构异常（\(file)/\(key)）") }
            throw XCTSkip("\(file) 结构异常。")
        }
        var out: [T] = []
        for item in arr {
            let d = try JSONSerialization.data(withJSONObject: item)
            out.append(try JSONDecoder().decode(T.self, from: d))
        }
        return out
    }

    // MARK: - 1) 编码：encodeParams / encodedQuery / encodedForm / escape

    private struct CodecCase: Decodable {
        let name: String
        let kind: String?
        let params: String?
        let charset: String?
        let isQuery: Bool?
        let result: String?
        let error: String?
    }

    func testGoldenUrlCodec() throws {
        let cases = try load("url_codec_cases.json", as: CodecCase.self, key: "codecResults") ?? []
        guard !cases.isEmpty else { XCTFail("url_codec_cases.json 为空"); return }
        var failures: [String] = []
        for c in cases {
            let kind = c.kind ?? "encodeParams"
            let swift: String
            if c.error != nil {
                // Java 侧抛错（例如字符集不存在）：本移植的对应行为是「保持原样返回」，
                // 差异登记在 README；这里只断言 Swift 不崩溃。
                failures.append("[\(c.name)] Java 抛错（\(c.error ?? "")），Swift 侧行为见 README 差异表")
                continue
            }
            switch kind {
            case "encodedQuery":
                swift = NetworkUtils.encodedQuery(c.params ?? "") ? "true" : "false"
            case "encodedForm":
                swift = NetworkUtils.encodedForm(c.params ?? "") ? "true" : "false"
            case "escape":
                swift = AnalyzeUrl.escape(c.params ?? "")
            default:
                swift = AnalyzeUrl.encodeParams(c.params ?? "", charset: c.charset, isQuery: c.isQuery ?? false)
            }
            if swift != (c.result ?? "") {
                failures.append(esc("[\(c.name)] kind=\(kind) charset=\(c.charset ?? "-") isQuery=\(c.isQuery.map(String.init) ?? "-")\n  Java: \(c.result ?? "<nil>")\n  Swift: \(swift)"))
            }
        }
        if !failures.isEmpty {
            XCTFail("url_codec golden 不一致 \(failures.count)/\(cases.count)：\n" + failures.prefix(20).joined(separator: "\n"))
        }
    }

    // MARK: - 2) UrlOption（Gson 宽松解析）

    private struct UrlOptionCase: Decodable {
        let name: String
        let json: String?
        let ok: Bool?
        let usedLenient: Bool?
        let dump: String?
    }

    /// 把 UrlOption 的各 getter 结果拼成与 Java 侧一致的文本（顺序固定）。
    private func dump(_ option: UrlOption) -> String {
        func s(_ v: String?) -> String { v ?? "<null>" }
        var lines: [String] = []
        lines.append("method=\(s(option.getMethod()))")
        lines.append("charset=\(s(option.getCharset()))")
        lines.append("origin=\(s(option.getOrigin()))")
        lines.append("retry=\(option.getRetry())")
        lines.append("type=\(s(option.getType()))")
        lines.append("webJs=\(s(option.getWebJs()))")
        lines.append("dnsIp=\(s(option.getDnsIp()))")
        lines.append("js=\(s(option.getJs()))")
        lines.append("bodyJs=\(s(option.getBodyJs()))")
        lines.append("serverID=\(option.getServerID().map(String.init) ?? "<null>")")
        lines.append("webViewDelayTime=\(option.getWebViewDelayTime().map(String.init) ?? "<null>")")
        lines.append("useWebView=\(option.useWebView())")
        if let hm = option.getHeaderMap() {
            lines.append("headerMap=" + hm.map { "\($0.0)=\($0.1)" }.joined(separator: ";"))
        } else {
            lines.append("headerMap=<null>")
        }
        lines.append("body=\(s(option.getBody()))")
        return lines.joined(separator: "\n")
    }

    /// 容错比较：两侧都把 "<null>" 与 "null" 视为等价（不同实现写法差异不影响语义）。
    private func normalizeDump(_ s: String) -> String {
        return s.replacingOccurrences(of: "<null>", with: "null")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func testGoldenUrlOption() throws {
        let cases = try load("url_option_cases.json", as: UrlOptionCase.self, key: "urlOptionResults") ?? []
        guard !cases.isEmpty else { XCTFail("url_option_cases.json 为空"); return }
        var failures: [String] = []
        for c in cases {
            let json = c.json ?? ""
            let ok = (c.ok ?? false)
            if !ok {
                // Java 侧两次解析都失败 -> Swift 也必须失败
                if UrlOption.parse(json) != nil {
                    failures.append("[\(c.name)] Java 解析失败，Swift 却成功：\(json)")
                }
                continue
            }
            guard let option = UrlOption.parse(json) else {
                failures.append("[\(c.name)] Java 解析成功，Swift 失败：\(json)")
                continue
            }
            if option.usedLenientFallback != (c.usedLenient ?? false) {
                failures.append("[\(c.name)] usedLenient 不一致 Java=\(c.usedLenient ?? false) Swift=\(option.usedLenientFallback)")
            }
            let lhs = normalizeDump(c.dump ?? "")
            let rhs = normalizeDump(dump(option))
            if lhs != rhs {
                failures.append("[\(c.name)] dump 不一致\n  json: \(json)\n  Java:\n\(lhs)\n  Swift:\n\(rhs)")
            }
        }
        if !failures.isEmpty {
            XCTFail("url_option golden 不一致 \(failures.count)/\(cases.count)：\n" + failures.prefix(10).joined(separator: "\n"))
        }
    }

    // MARK: - 3) URL 规则解析（paramPattern / 页码 / {{}} / @js）

    private struct AnalyzeUrlCase: Decodable {
        let name: String
        let ruleUrl: String?
        let baseUrl: String?
        let page: Int?
        let key: String?
        let resultUrl: String?
        let urlNoQuery: String?
        let method: String?
        let encodedQuery: String?
        let encodedForm: String?
        let error: String?
    }

    func testGoldenAnalyzeUrl() throws {
        let cases = try load("analyze_url_cases.json", as: AnalyzeUrlCase.self, key: "analyzeUrlResults") ?? []
        guard !cases.isEmpty else { XCTFail("analyze_url_cases.json 为空"); return }
        var failures: [String] = []
        for c in cases {
            if c.error != nil {
                failures.append("[\(c.name)] Java 抛错（\(c.error ?? "")），见 README 差异表")
                continue
            }
            let a = AnalyzeUrl(c.ruleUrl ?? "", key: c.key, page: c.page, baseUrl: c.baseUrl ?? "")
            if a.url != (c.resultUrl ?? "") {
                failures.append(esc("[\(c.name)] url 不一致\n  rule: \(c.ruleUrl ?? "") base: \(c.baseUrl ?? "")\n  Java: \(c.resultUrl ?? "<nil>")\n  Swift: \(a.url)"))
                continue
            }
            if a.urlNoQuery != (c.urlNoQuery ?? "") {
                failures.append(esc("[\(c.name)] urlNoQuery 不一致 Java=\(c.urlNoQuery ?? "<nil>") Swift=\(a.urlNoQuery)"))
            }
            if a.method.rawValue != (c.method ?? "GET") {
                failures.append("[\(c.name)] method 不一致 Java=\(c.method ?? "GET") Swift=\(a.method.rawValue)")
            }
            if (a.encodedQuery ?? "") != (c.encodedQuery ?? "") {
                failures.append(esc("[\(c.name)] encodedQuery 不一致 Java=\(c.encodedQuery ?? "<nil>") Swift=\(a.encodedQuery ?? "<nil>")"))
            }
            if (a.encodedForm ?? "") != (c.encodedForm ?? "") {
                failures.append("[\(c.name)] encodedForm 不一致 Java=\(c.encodedForm ?? "<nil>") Swift=\(a.encodedForm ?? "<nil>")")
            }
        }
        if !failures.isEmpty {
            XCTFail("analyze_url golden 不一致 \(failures.count)/\(cases.count)：\n" + failures.prefix(15).joined(separator: "\n"))
        }
    }
}
