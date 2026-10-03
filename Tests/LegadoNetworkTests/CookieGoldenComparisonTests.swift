//
//  CookieGoldenComparisonTests.swift
//  LegadoNetworkTests
//
//  第 6 步 6A：Cookie 纯函数（cookieToMap / mapToCookie / mergeCookies）与
//  Kotlin CookieStore/CookieManager 手工移植版（Java golden）的逐条对照。
//
//  CI 下 golden 缺失必须 fail（不许 XCTSkip）。
//

import XCTest
@testable import LegadoBookSource

final class CookieGoldenComparisonTests: XCTestCase {

    private struct CookieCase: Decodable {
        let name: String
        let op: String
        let cookie: String?
        let pairs: [[String: String]]?
        let cookies: [String?]?
        let result: String?
        let error: String?
    }

    private func goldenFile() -> URL? {
        guard let resourceURL = Bundle.module.resourceURL else { return nil }
        let direct = resourceURL.appendingPathComponent("golden/cookie_cases.json")
        if FileManager.default.fileExists(atPath: direct.path) { return direct }
        if let en = FileManager.default.enumerator(at: resourceURL, includingPropertiesForKeys: nil) {
            for case let f as URL in en where f.lastPathComponent == "cookie_cases.json" { return f }
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

    func testGoldenCookiePureFunctions() throws {
        guard let url = goldenFile(), let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = obj["cookieResults"] as? [Any], !arr.isEmpty else {
            if isRunningInCI() {
                XCTFail("CI 环境下 golden 缺失或为空（cookie_cases.json），不允许静默跳过")
                return
            }
            throw XCTSkip("cookie_cases.json 缺失（本地未跑 golden job）。")
        }
        var failures: [String] = []
        for item in arr {
            guard let d = try? JSONSerialization.data(withJSONObject: item),
                  let c = try? JSONDecoder().decode(CookieCase.self, from: d) else { continue }
            let swift: String?
            switch c.op {
            case "cookieToMap":
                swift = CookieStore.mapToCookie(CookieStore.cookieToMap(c.cookie ?? ""))
            case "mapToCookie":
                let map = (c.pairs ?? []).map { ($0["k"] ?? "", $0["v"] ?? "") }
                swift = CookieStore.mapToCookie(map)
            case "mergeCookies":
                let list = (c.cookies ?? []).map { $0 as String? }
                swift = CookieMerge.mergeCookies(list)
            default:
                continue
            }
            if (c.error == nil) && swift != c.result {
                failures.append("[\(c.name)] op=\(c.op) cookie=\(c.cookie ?? "-")\n  Java: \(c.result ?? "<nil>")\n  Swift: \(swift ?? "<nil>")")
            }
        }
        if !failures.isEmpty {
            XCTFail("cookie golden 不一致 \(failures.count)/\(arr.count)：\n" + failures.prefix(15).joined(separator: "\n"))
        }
    }
}
