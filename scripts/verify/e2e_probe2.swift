//
//  e2e_probe2.swift — 探针 B：记录真实请求 URL + 用 JS 完成 JS 依赖阶段
//
//  Linux 上 JavaScriptCore 不可用，因此 淘小说/得间/七猫 的 `@js:` 规则无法求值。
//  本探针：
//    1) 用「录制网络」抓出流程层真正请求的 URL（不经 Mock 匹配）；
//    2) 对 JS 依赖的阶段，打印其原始形态，并允许用 precomputed 方式喂入等价结果，
//       以便取得**下游** HTML/JSON 解析的精确值。
//

import Foundation
import LegadoBookSource

let base = "Tests/LegadoWebBookTests/Resources/real/"

func loadAll() throws -> [BookSource] {
    var all: [BookSource] = []
    all += try LegadoJSON.decoder.decode([BookSource].self,
        from: try Data(contentsOf: URL(fileURLWithPath: base + "real_sources_5.json")))
    for f in ["muli_real_source.json", "qimo_real_source.json"] {
        all += try LegadoJSON.decoder.decode([BookSource].self,
            from: try Data(contentsOf: URL(fileURLWithPath: base + f)))
    }
    return all
}

/// 记录所有被请求的 URL，并按 URL 从表里取 body；未命中即抛错（把实际 URL 打出来）。
final class RecordingNetwork: WebBookNetwork {
    private var table: [String: String] = [:]
    private(set) var seen: [String] = []
    private let lock = NSLock()
    init(_ table: [String: String]) { self.table = table }
    func fetch(_ analyzeUrl: AnalyzeUrl, webJs: String?, sourceRegex: String?) async throws -> WebBookResponse {
        let u = analyzeUrl.url.isEmpty ? analyzeUrl.ruleUrl : analyzeUrl.url
        lock.lock(); seen.append(u); lock.unlock()
        guard let body = table[u] else {
            throw RuleEngineError.unsupported("NO BODY for \(u)")
        }
        return WebBookResponse(url: u, status: 200, body: body)
    }
}

func src(_ n: String) -> BookSource { (try! loadAll()).first { $0.bookSourceName == n }! }

// ── 淘小说：搜索规则纯 JSONPath；bookUrl 无 @js；tocUrl 有 @js（Linux 不可用）
// 这里验证：搜索阶段能拿到什么；详情阶段的 tocUrl 因 JS 失败会落到什么值。
func probeTaoyue() {
    print("\n========== 淘小说书城（JS 依赖定位）==========")
    let s = src("⚡📂淘小说书城")
    print("searchUrl = \(s.searchUrl?.prefix(120) ?? "nil")")
    // 用 AnalyzeUrl 直接探测 searchUrl 的解析（无 JS）
    if let su = s.searchUrl {
        let au = AnalyzeUrl(su, key: "斗罗", page: 1, baseUrl: s.bookSourceUrl,
                            source: InMemorySource(key: s.bookSourceUrl), ruleData: FlowRuleData())
        print("searchUrl resolved (no-JS) = \(au.url)")
    }
    print("bookUrl 规则 = \(s.ruleSearch?.bookUrl ?? "nil")")
    print("tocUrl 规则(详情) = \(String((s.ruleBookInfo?.tocUrl ?? "nil").prefix(80)))")
    print("chapterUrl 规则 = \(String((s.ruleToc?.chapterUrl ?? "nil").prefix(80)))")
}

func probeQimo() {
    print("\n========== 七猫（JS 依赖定位）==========")
    let s = src("七猫小说（qimo）")
    print("bookSourceUrl = \(s.bookSourceUrl)")
    print("bookUrl 规则 = \(String((s.ruleSearch?.bookUrl ?? "nil").prefix(60)))... (JS)")
    print("tocUrl 规则 = \(String((s.ruleBookInfo?.tocUrl ?? "nil").prefix(60)))... (JS)")
    print("ruleToc.chapterUrl = \(s.ruleToc?.chapterUrl ?? "nil")")
    print("→ 目录/正文阶段本身是纯 JSONPath，JS 只用于‘拼请求 URL’；")
    print("  在 CI（有 JSC）里 bookUrl/tocUrl 会拼成真实 api URL。")
}

func probeDejian() {
    print("\n========== 得间小说（JS 依赖定位）==========")
    let s = src("⚡📂得间小说")
    print("bookSourceUrl = \(s.bookSourceUrl)")
    print("ruleSearch.bookList = \(s.ruleSearch?.bookList ?? "nil")")
    print("ruleSearch.bookUrl = \(s.ruleSearch?.bookUrl ?? "nil")")
    print("ruleBookInfo.tocUrl = \(String((s.ruleBookInfo?.tocUrl ?? "nil").prefix(90)))")
    print("ruleToc.chapterName = \(s.ruleToc?.chapterName ?? "nil")")
    print("ruleToc.chapterUrl = \(String((s.ruleToc?.chapterUrl ?? "nil").prefix(60)))")
    print("ruleContent.content = \(s.ruleContent?.content ?? "nil")")
}

func probeMuli() {
    print("\n========== 木里番茄（JS 依赖定位）==========")
    let s = src("🍅木里番茄0922[GO聚合版]")
    print("bookSourceUrl = \(s.bookSourceUrl)  (裸 IP:端口)")
    print("ruleSearch.bookList = \(s.ruleSearch?.bookList ?? "nil")")
    print("ruleSearch.name = \(s.ruleSearch?.name ?? "nil")")
    print("ruleBookInfo.name = \(s.ruleBookInfo?.name ?? "nil")")
    print("ruleToc.chapterName = \(s.ruleToc?.chapterName ?? "nil")")
    print("ruleToc.chapterUrl = \(s.ruleToc?.chapterUrl ?? "nil")")
    print("ruleContent.content 前缀 = \(String((s.ruleContent?.content ?? "nil").prefix(60)))... (JS)")
}

try probeTaoyue()
probeQimo()
probeDejian()
probeMuli()
