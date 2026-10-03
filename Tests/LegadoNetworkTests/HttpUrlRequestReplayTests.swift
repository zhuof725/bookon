//
//  HttpUrlRequestReplayTests.swift
//  LegadoNetworkTests
//
//  第 6 步 6B 追加项②：把 URL 规范化 golden 的每条用例**真实走一遍请求**——
//  用 OkHttp 规范化结果里的 path+query 拼出指向本地服务器的 URL，真实发送后断言
//  **服务器收到的原始 request-target 与之逐字符相等**（即：我们发出的请求没有被
//  URLSession/URL 再改写过）。这样「规范化 = OkHttp」与「实际发出的请求 = 规范化结果」
//  两段链条都被验证。
//
//  无法构造/发出的用例（URLSession 对非法字符比 OkHttp 严格）不硬失败，收集成清单并
//  检查上限；该清单是 README 差异表要登记的内容。
//
//  CI 下 golden 缺失必须 fail（不许 XCTSkip）。
//

import XCTest
@testable import LegadoBookSource

final class HttpUrlRequestReplayTests: XCTestCase {

    private var servers: [LocalScriptedServer] = []

    override func tearDown() {
        for s in servers { s.stop() }
        servers = []
        super.tearDown()
    }

    private struct HttpUrlCase: Decodable {
        let name: String
        let kind: String?
        let input: String?
        let result: String?
        let ok: Bool?
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

    private func loadCases() throws -> [HttpUrlCase] {
        guard let url = goldenFile(), let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = obj["httpUrlResults"] as? [Any], !arr.isEmpty else {
            if isRunningInCI() {
                XCTFail("CI 环境下 golden 缺失或为空（http_url_cases.json），不允许静默跳过")
            }
            throw XCTSkip("http_url_cases.json 缺失（本地未跑 golden job）。")
        }
        var out: [HttpUrlCase] = []
        for item in arr {
            guard let d = try? JSONSerialization.data(withJSONObject: item),
                  let c = try? JSONDecoder().decode(HttpUrlCase.self, from: d) else { continue }
            out.append(c)
        }
        return out
    }

    private func startEchoServer() throws -> LocalScriptedServer {
        let server = try LocalScriptedServer(handlers: [:], defaultHandler: { _ in
            LocalScriptedServer.Response(status: 200, reason: "OK", headers: [], body: Data("ok".utf8))
        })
        try server.start()
        servers.append(server)
        return server
    }

    private func makeReplayClient() -> URLSessionHTTPClient {
        let cache = CacheManager(storage: MemoryCacheStorage())
        let store = CookieStore(persistence: MemoryCookiePersistence(), cache: cache)
        return URLSessionHTTPClient(cookieStore: store, cookieManagerCache: cache)
    }

    /// 已知差异（README 差异表登记）：URLSession/CFNetwork 在写请求行时会把下面这些字符
    /// **额外百分号编码**，而 OkHttp 原样保留：`| { } ^ ` [ ]`（OkHttp 的 QUERY/PATH 允许集包含它们）
    /// 以及非法的 `%` 转义（OkHttp 保留 `%zz`，CFNetwork 写成 `%25zz`）。
    /// 这些用例不参与严格相等比较，而是**钉住实际行为**（数量变化或行为变化都会让测试失败提醒更新文档）。
    static let knownWireEncodingDivergences: Set<String> = [
        "path_33", "path_34", "path_35", "query_12", "query_13",
        "query_14", "query_15", "query_26", "more_03", "more_20",
    ]

    /// URLSession 因非法字符等拒绝的用例上限（超出则说明差异面扩大，需要复核 README 差异表）。
    private static let maxSkipped = 12

    func testGoldenUrlCasesReachServerUnchanged() async throws {
        let cases = try loadCases()
        let server = try startEchoServer()
        let client = makeReplayClient()
        var failures: [String] = []
        var skipped: [String] = []
        var replayed = 0
        var diverged: [String] = []

        for c in cases where c.kind ?? "httpUrl" == "httpUrl" {
            guard c.ok == true, let result = c.result else { continue }
            guard let parsed = HttpUrl.parse(result) else {
                failures.append(esc("[\(c.name)] 我们的 HttpUrl 解析不了 OkHttp 的规范化结果: \(result)"))
                continue
            }
            let expected = parsed.encodedPath + (parsed.query.map { "?" + $0 } ?? "")
            let target = "http://127.0.0.1:\(server.port)" + expected
            guard HttpUrl.parse(target) != nil else {
                skipped.append("\(c.name) (无法构造: \(result))")
                continue
            }
            do {
                _ = try await client.execute(HTTPRequest(url: target))
            } catch {
                skipped.append("\(c.name) (发送失败: \(error))")
                continue
            }
            replayed += 1
            let seen = server.requests.last?.target ?? "<无请求>"
            if seen != expected {
                if HttpUrlRequestReplayTests.knownWireEncodingDivergences.contains(c.name) {
                    diverged.append("\(c.name): OkHttp=\(expected) 线上=\(seen)")
                } else {
                    failures.append(esc("[\(c.name)] 服务器收到的 request-target 与 OkHttp 规范化结果不一致\n"
                                        + "  OkHttp: \(result)\n  期望 target: \(expected)\n  实际 target: \(seen)"))
                }
            }
        }

        if !skipped.isEmpty {
            // 这些是 URLSession 比 OkHttp 严格的字符面；数量与清单都要如实暴露
            print("[HttpUrlReplay] URLSession 拒绝/无法构造的用例 \(skipped.count) 条：\n" + skipped.joined(separator: "\n"))
        }
        if skipped.count > HttpUrlRequestReplayTests.maxSkipped {
            failures.append("URLSession 拒绝的用例数 \(skipped.count) 超过上限 \(HttpUrlRequestReplayTests.maxSkipped)：\n"
                            + skipped.joined(separator: "\n"))
        }
        // 已登记差异必须恰好是这些（数量或行为变化都要更新 README 差异表）
        XCTAssertEqual(diverged.count, HttpUrlRequestReplayTests.knownWireEncodingDivergences.count,
                       "已登记差异的命中数变了（实际：\(diverged.count)）：\n" + diverged.joined(separator: "\n"))
        XCTAssertGreaterThanOrEqual(replayed, 120, "至少应有 120 条用例真实走通（其余为 URLSession 拒绝面）")
        if !failures.isEmpty {
            XCTFail("URL 回放不一致 \(failures.count)/\(replayed)：\n" + failures.prefix(20).joined(separator: "\n"))
        }
    }

    func testAbsoluteThenHttpUrlCasesReachServerUnchanged() async throws {
        let cases = try loadCases()
        let server = try startEchoServer()
        let client = makeReplayClient()
        var failures: [String] = []
        var replayed = 0

        for c in cases where c.kind == "absoluteThenHttpUrl" {
            guard c.ok == true, let result = c.result, let parsed = HttpUrl.parse(result) else { continue }
            let expected = parsed.encodedPath + (parsed.query.map { "?" + $0 } ?? "")
            let target = "http://127.0.0.1:\(server.port)" + expected
            guard HttpUrl.parse(target) != nil else { continue }
            do {
                _ = try await client.execute(HTTPRequest(url: target))
            } catch {
                continue
            }
            replayed += 1
            let seen = server.requests.last?.target ?? "<无请求>"
            if seen != expected {
                failures.append(esc("[\(c.name)] 不一致\n  OkHttp: \(result)\n  期望: \(expected)\n  实际: \(seen)"))
            }
        }
        XCTAssertGreaterThanOrEqual(replayed, 10, "absoluteThenHttpUrl 类用例应有 10 条以上走通")
        if !failures.isEmpty {
            XCTFail("absoluteThenHttpUrl 回放不一致 \(failures.count)/\(replayed)：\n" + failures.prefix(10).joined(separator: "\n"))
        }
    }

    /// AnalyzeUrl.buildRequest() 产出的 URL 发到服务器后 path+query 不变。
    func testBuildRequestUrlReachesServerUnchanged() async throws {
        let server = try startEchoServer()
        let client = makeReplayClient()
        let rawCases = [
            "https://x.com/a%20b?c=d%20e",
            "https://x.com/%E4%B8%AD%E6%96%87/",
            "https://x.com/a/b/./c",
            "https://x.com/?a=1&b=2",
        ]
        for raw in rawCases {
            let a = AnalyzeUrl(raw)
            let built = a.buildRequest().url
            guard let parsed = HttpUrl.parse(built) else {
                XCTFail("buildRequest 的 URL 无法解析: \(built)")
                continue
            }
            let expected = parsed.encodedPath + (parsed.query.map { "?" + $0 } ?? "")
            let target = "http://127.0.0.1:\(server.port)" + expected
            guard HttpUrl.parse(target) != nil else { continue }
            _ = try await client.execute(HTTPRequest(url: target))
            XCTAssertEqual(server.requests.last?.target, expected, esc("buildRequest 后的 URL 在服务器侧被改写: \(built)"))
        }
    }
}
