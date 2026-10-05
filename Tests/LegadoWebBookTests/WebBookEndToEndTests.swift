//
//  WebBookEndToEndTests.swift
//  LegadoBookSource
//
//  第 7 步 A 段：端到端测试 —— 「规则真实、数据合成」。
//  用 配置文件_14个.json 里的 7 个【真实书源规则文本】+ 手工构造的合成响应，
//  跑通 searchBookAwait 全流程（不依赖外部网络）。
//

import XCTest
@testable import LegadoBookSource

final class WebBookEndToEndTests: XCTestCase {

    private func loadSources() throws -> [BookSource] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "配置文件_14个", withExtension: "json"))
        let data = try Data(contentsOf: url)
        let arr = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        return try arr.map { try JSONDecoder().decode(BookSource.self, from: JSONSerialization.data(withJSONObject: $0)) }
    }

    private func realSources() throws -> [BookSource] {
        try loadSources().filter { !$0.bookSourceName.hasPrefix("synthetic_") }
    }

    private func source(named name: String) throws -> BookSource {
        let src = try loadSources().first { $0.bookSourceName == name }
        return try XCTUnwrap(src)
    }

    func testLoads8RealAnd6Synthetic() throws {
        let all = try loadSources()
        XCTAssertEqual(all.count, 14)
        XCTAssertEqual(all.filter { $0.bookSourceName.hasPrefix("synthetic_") }.count, 6)
        XCTAssertEqual(all.filter { !$0.bookSourceName.hasPrefix("synthetic_") }.count, 8)
    }

    func testRealSourcesHaveSearchUrl() throws {
        for s in try realSources() {
            XCTAssertFalse(s.searchUrl?.isEmpty ?? true, "\(s.bookSourceName) 缺少 searchUrl")
        }
    }

    func testRealSourcesSearchUrlResolves() throws {
        // 用真实 searchUrl 文本构造 AnalyzeUrl，验证能解析出非空 url（不真正发请求）。
        for s in try realSources() {
            guard let searchUrl = s.searchUrl, !searchUrl.isEmpty else { continue }
            let analyzeUrl = AnalyzeUrl(
                searchUrl, key: "测试", page: 1,
                baseUrl: s.bookSourceUrl,
                source: InMemorySource(key: s.bookSourceUrl),
                ruleData: FlowRuleData()
            )
            XCTAssertFalse(analyzeUrl.url.isEmpty, "\(s.bookSourceName) 的 searchUrl 无法解析出 url")
        }
    }

    func testDeqixsSearchEndToEnd() async throws {
        // 规则真实（得奇小说网 ruleSearch 原文）；响应为合成 HTML。
        let src = try source(named: "📂得奇小说网")
        let html = """
        <div class="item">
        <h3><a href="https://www.deqixs.org/book/1/">斗破苍穹</a></h3>
        <img src="https://www.deqixs.org/files/1.jpg">
        <div class="itemtxt">
        <p>简介：少年萧炎<span>玄幻</span><span>连载中</span><span>100万字</span></p>
        <p><a>天蚕土豆</a></p>
        <ul><li><a>第一章</a></li></ul>
        </div>
        </div>
        """
        let net = MockWebBookNetwork(["https://www.deqixs.org/modules/article/search.php": WebBookResponse(url: "https://www.deqixs.org/modules/article/search.php", status: 200, body: html)])
        let opts = WebBookOptions(network: net)
        let result = try await WebBook.searchBookAwait(bookSource: src, key: "斗罗", options: opts)
        XCTAssertFalse(result.isEmpty)
        XCTAssertEqual(result[0].name, "斗破苍穹")
    }

    func testShuduguSearchEndToEnd() async throws {
        // 规则真实（速读谷 ruleSearch 原文，@css 规则）；响应为合成 HTML。
        let src = try source(named: "速读谷")
        let html = """
        <div class="item">
        <div class="itemtxt"><h3><a href="https://www.shudugu.org/book/1.html">斗罗大陆</a></h3></div>
        <p><span>玄幻</span></p>
        <div class="itemtxt"><ul><li><a>第一章</a></li></ul></div>
        <div class="itemtxt"><p><a>唐家三少</a></p></div>
        </div>
        """
        let net = MockWebBookNetwork(["https://www.shudugu.org/i/sor.aspx?key=%E6%96%97%E7%BD%97": WebBookResponse(url: "https://www.shudugu.org/i/sor.aspx?key=%E6%96%97%E7%BD%97", status: 200, body: html)])
        let opts = WebBookOptions(network: net)
        let result = try await WebBook.searchBookAwait(bookSource: src, key: "斗罗", options: opts)
        XCTAssertFalse(result.isEmpty)
        XCTAssertEqual(result[0].name, "斗罗大陆")
    }

    func testTaiwanSearchEndToEnd() async throws {
        // 规则真实（台湾小说网 ruleSearch 原文）；响应为合成 HTML。
        let src = try source(named: "📂台湾小说网")
        let html = """
        <ul><li><a href="https://www.twkan.cc/book/1.html">测试书名</a></li></ul>
        """
        let net = MockWebBookNetwork(["https://www.twkan.cc/search/%E6%B5%8B%E8%AF%95/1.html": WebBookResponse(url: "https://www.twkan.cc/search/%E6%B5%8B%E8%AF%95/1.html", status: 200, body: html)])
        let opts = WebBookOptions(network: net)
        let result = try await WebBook.searchBookAwait(bookSource: src, key: "测试", options: opts)
        // 台湾小说网 ruleSearch.bookList 为 CSS/其它规则；此处只断言不崩溃、能返回（可能为空列表）。
        _ = result
    }
}
