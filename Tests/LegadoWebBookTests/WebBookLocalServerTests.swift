//
//  WebBookLocalServerTests.swift
//  LegadoBookSource
//
//  第 7 步 A 段：本地合成服务器（NWListener）端到端测试 —— 真实 TCP/HTTP 链路 + URLSession。
//  仅在 Apple 平台（macOS/iOS）编译运行（Network framework）。Linux 上本文件为空。
//  全部为合成书源规则 + 合成 HTML（非真实站点）。
//

#if canImport(Network)
import XCTest
import Network
@testable import LegadoBookSource

/// 极简一次性 HTTP 服务器：accept 一条连接，回写固定 200 响应后关闭。
final class TinyHTTPServer {
    private let listener: NWListener
    private(set) var port: UInt16 = 0
    private let responseBody: String
    private let responseStatus: Int
    private let queue = DispatchQueue(label: "tiny-http-server")

    init(responseBody: String, responseStatus: Int = 200) throws {
        self.responseBody = responseBody
        self.responseStatus = responseStatus
        listener = try NWListener(using: .tcp)
        listener.newConnectionHandler = { [weak self] conn in
            self?.handle(conn)
        }
    }

    func start() throws {
        let sem = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in
            if case .ready = state { sem.signal() }
        }
        listener.start(queue: queue)
        _ = sem.wait(timeout: .now() + 5)
        guard let p = listener.port?.rawValue else { throw RuleEngineError.unsupported("无法获取本地端口") }
        port = p
    }

    func stop() {
        listener.cancel()
    }

    private func handle(_ conn: NWConnection) {
        conn.start(queue: queue)
        let body = responseBody
        let status = responseStatus
        let reason = status == 200 ? "OK" : "Not Found"
        let http = "HTTP/1.1 \(status) \(reason)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        conn.send(content: Data(http.utf8), completion: .contentProcessed { _ in
            conn.cancel()
        })
        conn.stateUpdateHandler = { state in
            if case .failed = state { conn.cancel() }
        }
    }
}

final class WebBookLocalServerTests: XCTestCase {

    func testSearchOverLocalHTTPServer() async throws {
        let server = try TinyHTTPServer(responseBody: Fixtures.searchBasic)
        try server.start()
        defer { server.stop() }

        let searchUrl = "http://127.0.0.1:\(server.port)/search"
        let src = SynthSources.basic(searchUrl: searchUrl)
        let client = URLSessionHTTPClient(cookieStore: CookieStore(), cookieManagerCache: CacheManager())
        let net = LiveWebBookNetwork(client: client)
        let opts = WebBookOptions(network: net)

        let result = try await WebBook.searchBookAwait(bookSource: src, key: "斗罗", options: opts)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].name, "书名一")
    }
}
#endif
