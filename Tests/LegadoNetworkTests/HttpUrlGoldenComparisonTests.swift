//
//  HttpUrlGoldenComparisonTests.swift
//  LegadoNetworkTests
//
//  第 6 步 6B：URL 规范化与**真实 OkHttp 5.3.2 的 HttpUrl**逐条对照。
//
//  golden 由 `scripts/golden/HttpUrlGen.java` 生成（170 条）：
//   - kind=httpUrl：直接用 HttpUrl 解析输入；
//   - kind=absoluteThenHttpUrl：先用 NetworkUtils.getAbsoluteURL(base, input)（java.net.URL 语义，
//     第 4 步 C 已对照）拼接，再交给 HttpUrl；
//   - 解析失败（OkHttp 返回 null）时 ok=false、result=null，Swift 侧也必须解析失败。
//
//  另外验证 `AnalyzeUrl.buildRequest()` 产出的 URL 已经过 HttpUrl 规范化。
//
//  CI 下 golden 缺失必须 fail（不许 XCTSkip）。
//

import XCTest
@testable import LegadoBookSource

final class HttpUrlGoldenComparisonTests: XCTestCase {

    private struct HttpUrlCase: Decodable {
        let name: String
        let kind: String?
        let input: String?
        let base: String?
        let intermediate: String?
        let ok: Bool?
        let result: String?
        let error: String?
    }

    private func goldenFile() -> URL? {
        guard let resourceURL = Bundle.module.resourceURL else { return nil }
        let direct = resourceURL.appendingPathComponent("golden/http_url_cases.json")
        if FileManager.default.fileExists(atPath: direct.path) { return direct }
        if let en = FileManager.default.enumerator(at: resourceURL, includingPropertiesForKeys: nil) {
            for case let f as URL in en where f.lastPathComponent == "http_url_cases.json" { return f }
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

    private func esc(_ s: String) -> String { s.replacingOccurrences(of: "%", with: "%%") }

    func testGoldenHttpUrlNormalization() throws {
        guard let url = goldenFile(), let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = obj["httpUrlResults"] as? [Any], !arr.isEmpty else {
            if isRunningInCI() {
                XCTFail("CI 环境下 golden 缺失或为空（http_url_cases.json），不允许静默跳过")
                return
            }
            throw XCTSkip("http_url_cases.json 缺失（本地未跑 golden job）。")
        }
        var failures: [String] = []
        var compared = 0
        for item in arr {
            guard let d = try? JSONSerialization.data(withJSONObject: item),
                  let c = try? JSONDecoder().decode(HttpUrlCase.self, from: d) else { continue }
            compared += 1
            let input = c.input ?? ""
            let candidate: String
            if c.kind == "absoluteThenHttpUrl" {
                let joined = NetworkUtils.getAbsoluteURL(c.base, input)
                // 中间串（getAbsoluteURL 的结果）也要一致，便于区分「拼接」与「规范化」
                if joined != (c.intermediate ?? "") {
                    failures.append(esc("[\(c.name)] getAbsoluteURL 中间串不一致\n  base: \(c.base ?? "<nil>") input: \(input)\n  Java: \(c.intermediate ?? "<nil>")\n  Swift: \(joined)"))
                    continue
                }
                candidate = joined
            } else {
                candidate = input
            }
            let parsed = HttpUrl.parse(candidate)
            if c.ok == true {
                guard let parsed = parsed else {
                    failures.append(esc("[\(c.name)] Java 解析成功、Swift 失败\n  input: \(candidate)\n  Java: \(c.result ?? "<nil>")"))
                    continue
                }
                if parsed.urlString != (c.result ?? "") {
                    failures.append(esc("[\(c.name)] 规范化结果不一致\n  input: \(candidate)\n  Java: \(c.result ?? "<nil>")\n  Swift: \(parsed.urlString)"))
                }
            } else if c.error == nil {
                // OkHttp 判定非法 -> Swift 也必须 nil
                if let parsed = parsed {
                    failures.append(esc("[\(c.name)] Java 解析失败、Swift 却成功\n  input: \(candidate)\n  Swift: \(parsed.urlString)"))
                }
            }
        }
        XCTAssertGreaterThanOrEqual(compared, 150, "URL 规范化 golden 用例数不足 150 条")
        if !failures.isEmpty {
            XCTFail("http_url golden 不一致 \(failures.count)/\(compared)：\n" + failures.prefix(25).joined(separator: "\n"))
        }
    }

    /// buildRequest() 产出的 URL 必须经过 HttpUrl 规范化。
    func testBuildRequestUrlIsNormalized() {
        let cases = [
            ("https://X.com:443/a b", "https://x.com/a%20b"),
            ("https://x.com/a/../b", "https://x.com/b"),
            ("https://x.com/?", "https://x.com/?"),
            ("https://x.com/中文", "https://x.com/%E4%B8%AD%E6%96%87"),
        ]
        for (raw, expected) in cases {
            let a = AnalyzeUrl(raw)
            XCTAssertEqual(a.buildRequest().url, expected, "buildRequest 未规范化: \(raw)")
        }
    }
}
