//
//  mock_network_probe.swift — 验证 MockWebBookNetwork 的匹配语义（新增能力）。
//
//  覆盖：
//    1) 精确匹配优先；
//    2) 前缀回退（书源 URL 含运行时算出的 sign 时，测试只能注册稳定前缀）；
//    3) 多前缀命中取**最长前缀**（特例注册盖住通用注册）；
//    4) requestedURLs 如实记录每一次请求（含顺序与重复）；
//    5) 全不命中时抛 RuleEngineError（不崩溃、不静默返回空响应）。
//
//  真实验收仍以 macOS / iOS CI 为准；本探针在 Linux 上验证纯匹配逻辑。
//

import Foundation
import LegadoBookSource

var PASS = 0, FAIL = 0
func check(_ cond: Bool, _ msg: String, line: Int = #line) {
    if cond { PASS += 1 } else { FAIL += 1; print("  [X] FAIL: \(msg)  [line \(line)]") }
}

func makeAnalyzeUrl(_ url: String) -> AnalyzeUrl {
    AnalyzeUrl(url)
}

@main struct MockNetworkProbe {
    static func main() async {
        print("== MockWebBookNetwork 匹配语义 ==")

        // ── 1) 精确匹配优先 ──
        do {
            let net = MockWebBookNetwork()
            net.set("https://a.test/p", WebBookResponse(url: "https://a.test/p", status: 200, body: "exact"))
            net.setPrefix("https://a.test/", WebBookResponse(url: "https://a.test/", status: 200, body: "prefix"))
            let r = try? await net.fetch(makeAnalyzeUrl("https://a.test/p"), webJs: nil, sourceRegex: nil)
            check(r?.body == "exact", "精确匹配应优先于前缀（实际 \(r?.body ?? "nil")）")
        } catch { check(false, "精确匹配用例抛错: \(error)") }

        // ── 2) 前缀回退（七猫场景：query 由 JS 在运行时算 sign）──
        do {
            let net = MockWebBookNetwork()
            net.setPrefix("https://api-bc.wtzw.com/api/v5/search/words",
                          WebBookResponse(url: "x", status: 200, body: "qimo"))
            let real = "https://api-bc.wtzw.com/api/v5/search/words?&gender=3&imei_ip=2937357107&page=1&wd=%E6%96%97%E7%BD%97&sign=71e8301a85c231615c6fb6cf2003583b"
            let r = try? await net.fetch(makeAnalyzeUrl(real), webJs: nil, sourceRegex: nil)
            check(r?.body == "qimo", "前缀应命中带运行时 sign 的 URL（实际 \(r?.body ?? "nil")）")
        } catch { check(false, "前缀回退用例抛错: \(error)") }

        // ── 3) 最长前缀优先 ──
        do {
            let net = MockWebBookNetwork()
            net.setPrefix("https://b.test/", WebBookResponse(url: "1", status: 200, body: "short"))
            net.setPrefix("https://b.test/api/", WebBookResponse(url: "2", status: 200, body: "long"))
            let r = try? await net.fetch(makeAnalyzeUrl("https://b.test/api/x"), webJs: nil, sourceRegex: nil)
            check(r?.body == "long", "多前缀命中应取最长（实际 \(r?.body ?? "nil")）")
        } catch { check(false, "最长前缀用例抛错: \(error)") }

        // ── 4) requestedURLs 如实记录（顺序 + 重复）──
        do {
            let net = MockWebBookNetwork()
            net.setPrefix("https://c.test/", WebBookResponse(url: "c", status: 200, body: "ok"))
            _ = try? await net.fetch(makeAnalyzeUrl("https://c.test/1"), webJs: nil, sourceRegex: nil)
            _ = try? await net.fetch(makeAnalyzeUrl("https://c.test/2"), webJs: nil, sourceRegex: nil)
            _ = try? await net.fetch(makeAnalyzeUrl("https://c.test/1"), webJs: nil, sourceRegex: nil)
            check(net.requestedURLs == ["https://c.test/1", "https://c.test/2", "https://c.test/1"],
                  "requestedURLs 应按发生顺序如实记录（实际 \(net.requestedURLs)）")
        } catch { check(false, "requestedURLs 用例抛错: \(error)") }

        // ── 5) 全不命中必须抛错（不静默）──
        do {
            let net = MockWebBookNetwork()
            net.setPrefix("https://d.test/", WebBookResponse(url: "d", status: 200, body: "ok"))
            var threw = false
            do { _ = try await net.fetch(makeAnalyzeUrl("https://other.test/x"), webJs: nil, sourceRegex: nil) }
            catch { threw = true }
            check(threw, "无匹配时必须抛错，不能静默返回")
            // 但该次尝试仍应记录（便于失败诊断）。
            check(net.requestedURLs == ["https://other.test/x"], "未命中的请求也应被记录")
        } catch { check(false, "不命中用例抛错: \(error)") }

        print("PASS=\(PASS) FAIL=\(FAIL)")
        if FAIL > 0 { exit(1) }
    }
}
