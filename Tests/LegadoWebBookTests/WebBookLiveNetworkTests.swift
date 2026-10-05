//
//  WebBookLiveNetworkTests.swift
//  LegadoBookSource
//
//  第 7 步 A 段：LiveWebBookNetwork（真实网络路径的 buildRequest → HTTPClient.execute →
//  charset 解码 → WebBookResponse）用 ScriptedHTTPClient 驱动测试。
//  全部为合成书源规则 + 合成响应（非真实站点）。
//

import XCTest
@testable import LegadoBookSource

final class WebBookLiveNetworkTests: XCTestCase {

    private func liveNet(_ html: String, url: String = "http://synthetic.test/search") -> LiveWebBookNetwork {
        let entry = ScriptedHTTPClient.Entry(matchURLContains: "synthetic.test", response: HTTPResponse(url: url, status: 200, body: Data(html.utf8)))
        let client = ScriptedHTTPClient(entries: [entry])
        return LiveWebBookNetwork(client: client)
    }

    func testLiveNetworkFetchDecodesUtf8() async throws {
        let net = liveNet(Fixtures.searchBasic)
        let src = SynthSources.basic()
        let opts = WebBookOptions(network: net)
        let result = try await WebBook.searchBookAwait(bookSource: src, key: "x", options: opts)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].name, "书名一")
    }

    func testLiveNetworkRedirectDetected() async throws {
        // 301 状态 → isRedirect = true
        let entry = ScriptedHTTPClient.Entry(matchURLContains: "synthetic.test", response: HTTPResponse(url: "http://synthetic.test/search", status: 301, body: Data(Fixtures.searchBasic.utf8)))
        let client = ScriptedHTTPClient(entries: [entry])
        let net = LiveWebBookNetwork(client: client)
        let logger = DebugLogger()
        let sink = RecordingSink()
        logger.callback = sink
        logger.beginDebug(sourceUrl: "http://synthetic.test")
        let src = SynthSources.basic()
        let opts = WebBookOptions(logger: logger, network: net)
        _ = try await WebBook.searchBookAwait(bookSource: src, key: "x", options: opts)
        XCTAssertTrue(sink.contains("≡检测到重定向"))
    }

    func testLiveNetworkNotFoundReturnsEmpty() async throws {
        // 404 由 LiveWebBookNetwork 转成一个 status=404、body 为空的 WebBookResponse
        // （fetch 只在**网络层异常**时抛错，见 WebBookNetwork.swift:106-110）。
        // 空 body 后续在 BookList 里解析出空列表并原样返回 —— 与 Kotlin 一致：
        // searchBookAwait 对「空结果」不抛异常（抛错只发生在按书名找书的另一条链路）。
        let client = ScriptedHTTPClient(entries: [], defaultResponse: HTTPResponse(url: "http://synthetic.test/search", status: 404))
        let net = LiveWebBookNetwork(client: client)
        let src = SynthSources.basic()
        let opts = WebBookOptions(network: net)
        let result = try await WebBook.searchBookAwait(bookSource: src, key: "x", options: opts)
        XCTAssertTrue(result.isEmpty, "404 空响应应得到空列表，实际：\(result.count)")
    }

    func testLiveNetworkCapturesResponseHeaders() async throws {
        let entry = ScriptedHTTPClient.Entry(matchURLContains: "synthetic.test", response: HTTPResponse(url: "http://synthetic.test/search", status: 200, headers: [("Content-Type", "text/html; charset=utf-8")], body: Data(Fixtures.searchBasic.utf8)))
        let client = ScriptedHTTPClient(entries: [entry])
        let net = LiveWebBookNetwork(client: client)
        let logger = DebugLogger()
        let src = SynthSources.basic()
        let opts = WebBookOptions(logger: logger, network: net)
        _ = try await WebBook.searchBookAwait(bookSource: src, key: "x", options: opts)
        let cap = logger.capturedResponse(stage: .search)
        XCTAssertEqual(cap?.headers["Content-Type"], "text/html; charset=utf-8")
    }
}
