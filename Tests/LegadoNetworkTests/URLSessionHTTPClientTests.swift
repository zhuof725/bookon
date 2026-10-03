//
//  URLSessionHTTPClientTests.swift
//  LegadoNetworkTests
//
//  第 6 步 6B：URLSessionHTTPClient（真实网络）的集成测试（27 个用例）。
//
//  用 Network.framework 的 NWListener 在 127.0.0.1 + 随机端口起本地脚本化 HTTP 服务器，
//  可编程返回：状态码/头/body/Set-Cookie/重定向链/gzip 压缩体（stored-block 容器）；
//  `hang` 路径故意不响应（测超时）。每个测试独立端口、独立 CookieStore/CacheManager；
//  tearDown 统一 stop 服务器；不依赖任何真实外网。
//
//  覆盖：GET 往返（最终 url / callTime）、POST form/json、HEAD、持久化/会话 Cookie 保存与
//  回放、请求头 Cookie 合并、301/302/303/307/308 重定向语义与 20 跳上限、readTimeout/
//  callTimeout 覆盖、retry（1+retry 次、2xx 提前返回）、错误分类（实测 connectRefused +
//  mapError 纯函数含 unknownHost）、dnsIp/非法代理降级 diagnostics、gzip 解压、
//  同名响应头多值、非 2xx 正常返回。
//

import XCTest
import Network
import CFNetwork
@testable import LegadoBookSource

/// 本地脚本化 HTTP 服务器：NWListener 绑定 127.0.0.1 + 随机端口。
/// 按 path 精确路由到 handler；未命中时走 defaultHandler（可为 nil，返回 404）。
final class LocalScriptedServer {

    /// 服务器收到的请求（供测试断言）。
    struct ReceivedRequest {
        let method: String
        /// path + query（如 /search?q=1）
        let target: String
        /// 仅路径（不含 query）
        let path: String
        let headers: [(String, String)]
        let body: Data

        func header(_ name: String) -> String? {
            for (k, v) in headers where k.caseInsensitiveCompare(name) == .orderedSame {
                return v
            }
            return nil
        }

        /// 取同名头的全部值（保序），用于多值/重复头断言。
        func headerValues(_ name: String) -> [String] {
            var out: [String] = []
            for (k, v) in headers where k.caseInsensitiveCompare(name) == .orderedSame {
                out.append(v)
            }
            return out
        }
    }

    /// 一次响应的脚本描述。
    struct Response {
        var status: Int
        var reason: String
        var headers: [(String, String)]
        var body: Data
        /// true 时不发送任何数据（连接保持打开，用于超时测试）
        var hang: Bool

        init(status: Int, reason: String, headers: [(String, String)] = [],
             body: Data = Data(), hang: Bool = false) {
            self.status = status
            self.reason = reason
            self.headers = headers
            self.body = body
            self.hang = hang
        }
    }

    typealias Handler = (ReceivedRequest) -> Response

    enum ServerError: Error {
        case startTimedOut
        case noPort
    }

    private let listener: NWListener
    private let queue = DispatchQueue(label: "LocalScriptedServer.queue")
    private let lock = NSLock()
    private var handlers: [String: Handler]
    private let defaultHandler: Handler?
    private var recorded: [ReceivedRequest] = []
    private var connections: [NWConnection] = []
    private(set) var port: UInt16 = 0

    init(handlers: [String: Handler], defaultHandler: Handler? = nil) throws {
        self.handlers = handlers
        self.defaultHandler = defaultHandler
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: NWEndpoint.Host("127.0.0.1"),
                                                               port: .any)
        self.listener = try NWListener(using: parameters, on: .any)
    }

    /// 启动并等待 ready（拿到随机端口）。
    func start() throws {
        let ready = DispatchSemaphore(value: 0)
        var failure: Error?
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                ready.signal()
            case .failed(let error):
                failure = error
                ready.signal()
            case .cancelled:
                ready.signal()
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.start(queue: queue)
        if ready.wait(timeout: .now() + 5) == .timedOut {
            throw ServerError.startTimedOut
        }
        if let failure = failure { throw failure }
        guard let port = listener.port else { throw ServerError.noPort }
        self.port = port.rawValue
    }

    /// 关闭监听与所有连接（幂等）。
    func stop() {
        lock.lock()
        let conns = connections
        connections = []
        let handlersCopy = handlers
        handlers = handlersCopy
        lock.unlock()
        for connection in conns { connection.cancel() }
        listener.cancel()
    }

    /// 已收到的请求（线程安全）。
    var requests: [ReceivedRequest] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }

    // MARK: - gzip（压缩响应体测试用）

    /// 生成一个最小 gzip 容器（deflate 全部用 "stored" 块，不依赖外部工具与 zlib）。
    /// 客户端（URLSession）会对 `Content-Encoding: gzip` 的响应体自动解压。
    static func gzip(_ data: Data) -> Data {
        var out = Data([0x1F, 0x8B, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xFF])
        var offset = 0
        if data.isEmpty {
            out.append(contentsOf: [0x01, 0x00, 0x00, 0xFF, 0xFF])
        }
        while offset < data.count {
            let chunkLength = min(65535, data.count - offset)
            let isLast = offset + chunkLength >= data.count
            out.append(isLast ? 0x01 : 0x00) // BFINAL=isLast, BTYPE=00（stored）
            let len = UInt16(chunkLength)
            let nlen = ~len
            out.append(contentsOf: [UInt8(len & 0xFF), UInt8(len >> 8),
                                    UInt8(nlen & 0xFF), UInt8(nlen >> 8)])
            out.append(data.subdata(in: offset..<(offset + chunkLength)))
            offset += chunkLength
        }
        let crc = crc32(data)
        out.append(contentsOf: [UInt8(crc & 0xFF), UInt8((crc >> 8) & 0xFF),
                                UInt8((crc >> 16) & 0xFF), UInt8((crc >> 24) & 0xFF)])
        let size = UInt32(truncatingIfNeeded: data.count)
        out.append(contentsOf: [UInt8(size & 0xFF), UInt8((size >> 8) & 0xFF),
                                UInt8((size >> 16) & 0xFF), UInt8((size >> 24) & 0xFF)])
        return out
    }

    /// 标准 CRC-32（IEEE，反射多项式 0xEDB88320）——gzip 尾部的校验字段。
    static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                if (crc & 1) == 1 {
                    crc = (crc >> 1) ^ 0xEDB8_8320
                } else {
                    crc >>= 1
                }
            }
        }
        return crc ^ 0xFFFF_FFFF
    }

    // MARK: - 连接处理

    private func accept(_ connection: NWConnection) {
        lock.lock()
        connections.append(connection)
        lock.unlock()
        connection.start(queue: queue)
        readLoop(connection, buffer: Data())
    }

    private func readLoop(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            var buf = buffer
            if let data = data, !data.isEmpty { buf.append(data) }
            if let parsed = self.parseRequest(buf) {
                self.recordAndRespond(parsed.request, on: connection)
                return
            }
            if error != nil || isComplete {
                connection.cancel()
                return
            }
            self.readLoop(connection, buffer: buf)
        }
    }

    /// 解析一个完整请求（头 + Content-Length 指定的 body）；不足时返回 nil。
    private func parseRequest(_ buffer: Data) -> (request: ReceivedRequest, remainder: Data)? {
        guard let separator = buffer.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let headerData = buffer.subdata(in: buffer.startIndex..<separator.lowerBound)
        guard let headerText = String(data: headerData, encoding: .utf8) else { return nil }
        var lines = headerText.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { return nil }
        let requestLine = lines.removeFirst()
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        let method = String(parts[0])
        let target = String(parts[1])
        let path = target.components(separatedBy: "?").first ?? target
        var headers: [(String, String)] = []
        var contentLength = 0
        for line in lines where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = String(line[line.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            if name.lowercased() == "content-length" { contentLength = Int(value) ?? 0 }
            headers.append((name, value))
        }
        let bodyStart = separator.upperBound
        let total = bodyStart + contentLength
        guard buffer.count >= total else { return nil }
        let body = buffer.subdata(in: bodyStart..<total)
        let request = ReceivedRequest(method: method, target: target, path: path,
                                      headers: headers, body: body)
        return (request, buffer.subdata(in: total..<buffer.count))
    }

    private func recordAndRespond(_ request: ReceivedRequest, on connection: NWConnection) {
        lock.lock()
        recorded.append(request)
        let handler = handlers[request.path] ?? defaultHandler
        lock.unlock()
        let response: Response
        if let handler = handler {
            response = handler(request)
        } else {
            response = Response(status: 404, reason: "Not Found",
                                headers: [("Content-Type", "text/plain")],
                                body: Data("NF".utf8))
        }
        if response.hang { return } // 故意不响应；连接由 stop() 统一关闭
        var text = "HTTP/1.1 \(response.status) \(response.reason)\r\n"
        var hasLength = false
        var hasConnection = false
        for (name, value) in response.headers {
            text += "\(name): \(value)\r\n"
            if name.lowercased() == "content-length" { hasLength = true }
            if name.lowercased() == "connection" { hasConnection = true }
        }
        if !hasLength { text += "Content-Length: \(response.body.count)\r\n" }
        if !hasConnection { text += "Connection: close\r\n" }
        text += "\r\n"
        var payload = Data(text.utf8)
        payload.append(response.body)
        connection.send(content: payload, completion: .contentProcessed { _ in
            connection.send(content: nil, completion: .contentProcessed { _ in
                connection.cancel()
            })
        })
    }
}

/// 按调用次数依次返回脚本响应的线程安全包装（用于重试/「前 N 次返回 X」的场景）。
/// 越界后重复最后一个响应；空脚本兜底 500（不崩溃）。
final class SequencedResponder: @unchecked Sendable {
    private let lock = NSLock()
    private let responses: [LocalScriptedServer.Response]
    private var index = 0

    init(_ responses: [LocalScriptedServer.Response]) {
        self.responses = responses
    }

    /// 已返回的响应个数（= 服务器实际处理的请求次数）。
    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return index
    }

    func next() -> LocalScriptedServer.Response {
        lock.lock(); defer { lock.unlock() }
        let response: LocalScriptedServer.Response
        if index < responses.count {
            response = responses[index]
        } else if let last = responses.last {
            response = last
        } else {
            response = LocalScriptedServer.Response(status: 500, reason: "No Script")
        }
        index += 1
        return response
    }
}

/// 200 + 纯文本 body 的常规响应（文件内工具，供 handler 闭包直接调用）。
private func makeOKResponse(_ text: String) -> LocalScriptedServer.Response {
    return LocalScriptedServer.Response(status: 200, reason: "OK",
                                        headers: [("Content-Type", "text/plain")],
                                        body: Data(text.utf8))
}

/// URLSessionHTTPClient 的集成测试（27 个用例）。
final class URLSessionHTTPClientTests: XCTestCase {

    /// 每个用例自己起服务器（helper 自动挑随机端口），tearDown 统一关闭。
    private var servers: [LocalScriptedServer] = []

    override func tearDown() {
        for server in servers { server.stop() }
        servers.removeAll()
        // 说明：URLSessionHTTPClient 每次 attempt 内部新建 URLSession 并在 defer 里
        // invalidateAndCancel()，用例无需额外关 session；这里只保证本地服务器全部关闭。
        super.tearDown()
    }

    // MARK: - 工具

    /// 起一个本地脚本化服务器并登记到 tearDown。
    private func startServer(handlers: [String: LocalScriptedServer.Handler],
                             defaultHandler: LocalScriptedServer.Handler? = nil) throws -> LocalScriptedServer {
        let server = try LocalScriptedServer(handlers: handlers, defaultHandler: defaultHandler)
        try server.start()
        servers.append(server)
        return server
    }

    /// 每个用例独立的 client + CookieStore + CacheManager（全部内存实现，互不串扰）。
    private func makeClient(diagnostics: RuleEngineDiagnostics? = nil)
        -> (client: URLSessionHTTPClient, store: CookieStore, cache: CacheManager) {
        let cache = CacheManager(storage: MemoryCacheStorage())
        let store = CookieStore(persistence: MemoryCookiePersistence(), cache: cache)
        let client = URLSessionHTTPClient(cookieStore: store,
                                          cookieManagerCache: cache,
                                          diagnostics: diagnostics)
        return (client, store, cache)
    }

    /// 本地服务器上的绝对 URL。
    private func url(_ path: String, _ server: LocalScriptedServer) -> String {
        return "http://127.0.0.1:\(server.port)\(path)"
    }

    // MARK: - 1. GET 往返（status/message/headers/body/最终 url/callTime）

    func testGetRoundTrip() async throws {
        let handlers: [String: LocalScriptedServer.Handler] = [
            "/hello": { _ in
                LocalScriptedServer.Response(status: 200, reason: "OK",
                                             headers: [("Content-Type", "text/plain; charset=utf-8"),
                                                       ("X-Test", "hello")],
                                             body: Data("hello-body".utf8))
            }
        ]
        let server = try startServer(handlers: handlers)
        let (client, _, _) = makeClient()

        let response = try await client.execute(HTTPRequest(url: url("/hello", server)))

        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(response.message, "OK")
        XCTAssertEqual(response.body, Data("hello-body".utf8))
        XCTAssertEqual(response.header("Content-Type"), "text/plain; charset=utf-8")
        XCTAssertEqual(response.header("X-Test"), "hello")
        XCTAssertEqual(response.url, url("/hello", server), "HTTPResponse.url 应为最终请求 URL")
        XCTAssertGreaterThanOrEqual(response.callTime, 0, "callTime（毫秒）不应为负")
        XCTAssertEqual(server.requests.count, 1)
        XCTAssertEqual(server.requests.first?.path, "/hello")
    }

    // MARK: - 2. 相对 Location 解析（/next）与最终 url

    func testRelativeLocationRedirectResolvesAndFinalURLIsTarget() async throws {
        let handlers: [String: LocalScriptedServer.Handler] = [
            "/start": { _ in
                LocalScriptedServer.Response(status: 302, reason: "Found",
                                             headers: [("Location", "/next")],
                                             body: Data())
            },
            "/next": { _ in makeOKResponse("next-page") }
        ]
        let server = try startServer(handlers: handlers)
        let (client, _, _) = makeClient()

        let response = try await client.execute(HTTPRequest(url: url("/start", server)))

        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(response.body, Data("next-page".utf8))
        XCTAssertEqual(response.url, url("/next", server),
                       "相对 Location(/next) 应基于当前 URL 解析成绝对地址，并作为最终 url 返回")
        XCTAssertEqual(server.requests.count, 2)
        XCTAssertEqual(server.requests.first?.path, "/start")
        XCTAssertEqual(server.requests.last?.path, "/next")
    }

    // MARK: - 3. POST form（application/x-www-form-urlencoded）

    func testPostFormBodyAndContentType() async throws {
        let handlers: [String: LocalScriptedServer.Handler] = [
            "/form": { _ in makeOKResponse("form-ok") }
        ]
        let server = try startServer(handlers: handlers)
        let (client, _, _) = makeClient()

        var request = HTTPRequest(url: url("/form", server), method: .post)
        request.body = Data("q=hello&n=2".utf8)
        request.contentType = "application/x-www-form-urlencoded"

        let response = try await client.execute(request)

        XCTAssertEqual(response.status, 200)
        let received = try XCTUnwrap(server.requests.first)
        XCTAssertEqual(received.method, "POST")
        XCTAssertEqual(received.header("Content-Type"), "application/x-www-form-urlencoded",
                       "contentType 未在 headers 里给定时应自动补 Content-Type（对应 OkHttp RequestBody）")
        XCTAssertEqual(received.body, Data("q=hello&n=2".utf8), "服务器看到的 form 原始字节应一致")
    }

    // MARK: - 4. POST json（application/json; charset=UTF-8）

    func testPostJSONBodyAndContentType() async throws {
        let handlers: [String: LocalScriptedServer.Handler] = [
            "/json": { _ in makeOKResponse("json-ok") }
        ]
        let server = try startServer(handlers: handlers)
        let (client, _, _) = makeClient()

        let payload = Data("{\"name\":\"书源\",\"n\":1}".utf8)
        var request = HTTPRequest(url: url("/json", server), method: .post)
        request.body = payload
        request.contentType = "application/json; charset=UTF-8"

        let response = try await client.execute(request)

        XCTAssertEqual(response.status, 200)
        let received = try XCTUnwrap(server.requests.first)
        XCTAssertEqual(received.method, "POST")
        XCTAssertEqual(received.header("Content-Type"), "application/json; charset=UTF-8")
        XCTAssertEqual(received.body, payload, "服务器看到的 json 字节（含非 ASCII）应一致")
    }

    // MARK: - 5. HEAD：服务器收到 HEAD，客户端拿到空 body

    func testHeadRequestSendsHeadAndEmptyBody() async throws {
        let handlers: [String: LocalScriptedServer.Handler] = [
            "/head": { _ in
                LocalScriptedServer.Response(status: 200, reason: "OK",
                                             headers: [("X-Method", "HEAD")],
                                             body: Data())
            }
        ]
        let server = try startServer(handlers: handlers)
        let (client, _, _) = makeClient()

        let response = try await client.execute(HTTPRequest(url: url("/head", server), method: .head))

        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(response.header("X-Method"), "HEAD")
        XCTAssertTrue(response.body.isEmpty, "HEAD 响应不应有 body（对应 RequestMethod.HEAD）")
        XCTAssertEqual(server.requests.first?.method, "HEAD", "服务器应收到 HEAD 方法")
    }

    // MARK: - 6. 持久化 Set-Cookie（带 Max-Age）→ CookieStore，下一次请求自动带上

    func testPersistentSetCookieSavedAndReplayed() async throws {
        let handlers: [String: LocalScriptedServer.Handler] = [
            "/set-persistent": { _ in
                LocalScriptedServer.Response(status: 200, reason: "OK",
                                             headers: [("Set-Cookie", "sid=persist-1; Max-Age=3600; Path=/")],
                                             body: Data("set".utf8))
            },
            "/check": { _ in makeOKResponse("checked") }
        ]
        let server = try startServer(handlers: handlers)
        let (client, store, cache) = makeClient()

        _ = try await client.execute(HTTPRequest(url: url("/set-persistent", server)))

        XCTAssertEqual(store.getCookieNoSession(url("/check", server)), "sid=persist-1",
                       "带 Max-Age 的 Set-Cookie 应持久化（CookieStore.replaceCookie）")
        XCTAssertNil(cache.getFromMemory("127.0.0.1_session_cookie"),
                     "持久化 Cookie 不应写进 <domain>_session_cookie 键")

        _ = try await client.execute(HTTPRequest(url: url("/check", server)))

        let second = try XCTUnwrap(server.requests.last)
        XCTAssertEqual(second.path, "/check")
        XCTAssertEqual(second.header("Cookie"), "sid=persist-1",
                       "同一 client 下一次请求应自动注入持久化 Cookie（CookieManager.loadRequest）")
    }

    // MARK: - 7. 会话 Set-Cookie（无 Max-Age/Expires）→ <domain>_session_cookie

    func testSessionSetCookieSavedToCacheAndReplayed() async throws {
        let handlers: [String: LocalScriptedServer.Handler] = [
            "/set-session": { _ in
                LocalScriptedServer.Response(status: 200, reason: "OK",
                                             headers: [("Set-Cookie", "sess=tok-9; Path=/")],
                                             body: Data("set".utf8))
            },
            "/check": { _ in makeOKResponse("checked") }
        ]
        let server = try startServer(handlers: handlers)
        let (client, store, cache) = makeClient()

        _ = try await client.execute(HTTPRequest(url: url("/set-session", server)))

        XCTAssertEqual(cache.getFromMemory("127.0.0.1_session_cookie") as? String, "sess=tok-9",
                       "无 Max-Age/Expires 的 Set-Cookie 应存 <domain>_session_cookie（updateSessionCookie）")
        XCTAssertEqual(store.getCookieNoSession(url("/check", server)), "",
                       "会话 Cookie 不应持久化进 CookieStore")

        _ = try await client.execute(HTTPRequest(url: url("/check", server)))

        let second = try XCTUnwrap(server.requests.last)
        XCTAssertEqual(second.path, "/check")
        XCTAssertEqual(second.header("Cookie"), "sess=tok-9",
                       "下一次请求应带上会话 Cookie")
    }

    // MARK: - 8. 请求已有 Cookie 头与存储 Cookie 合并（同键以存储为准）

    func testStoredCookieOverridesSameKeyInRequestCookieHeader() async throws {
        let handlers: [String: LocalScriptedServer.Handler] = [
            "/merge": { _ in makeOKResponse("merged") }
        ]
        let server = try startServer(handlers: handlers)
        let (client, store, _) = makeClient()

        // 存储里已有 b=99; c=3（模拟此前保存过的 Cookie）
        store.replaceCookie(url("/merge", server), "b=99; c=3")

        var request = HTTPRequest(url: url("/merge", server))
        request.headers = [("Cookie", "a=1; b=2")]
        _ = try await client.execute(request)

        let received = try XCTUnwrap(server.requests.first)
        XCTAssertEqual(received.header("Cookie"), "a=1; b=99; c=3",
                       "合并顺序=已有头在前，存储 Cookie 覆盖同键（CookieManager.cookieHeaderFor）")
    }

    // MARK: - 9~11. 301/302/303：POST → GET 且丢弃 body（OkHttp RedirectInterceptor）

    /// 断言 POST 收到 301/302/303 后转 GET：丢 body、丢 Content-Type，两跳都在服务器留痕。
    private func assertRedirectPostToGet(status: Int, reason: String, path: String) async throws {
        let handlers: [String: LocalScriptedServer.Handler] = [
            path: { _ in
                LocalScriptedServer.Response(status: status, reason: reason,
                                             headers: [("Location", "/target")],
                                             body: Data("redirected".utf8))
            },
            "/target": { _ in
                LocalScriptedServer.Response(status: 200, reason: "OK",
                                             headers: [("X-Target", "1")],
                                             body: Data("target-body".utf8))
            }
        ]
        let server = try startServer(handlers: handlers)
        let (client, _, _) = makeClient()

        var request = HTTPRequest(url: url(path, server), method: .post)
        request.body = Data("payload=1".utf8)
        request.contentType = "application/x-www-form-urlencoded"

        let response = try await client.execute(request)

        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(response.body, Data("target-body".utf8))
        XCTAssertEqual(response.url, url("/target", server))

        XCTAssertEqual(server.requests.count, 2, "应发生两跳：原始请求 + follow 请求")
        let first = try XCTUnwrap(server.requests.first)
        let second = try XCTUnwrap(server.requests.dropFirst().first)
        XCTAssertEqual(first.path, path)
        XCTAssertEqual(first.method, "POST")
        XCTAssertEqual(first.body, Data("payload=1".utf8))
        XCTAssertEqual(second.path, "/target")
        XCTAssertEqual(second.method, "GET", "\(status) 应转 GET（OkHttp RedirectInterceptor 语义）")
        XCTAssertTrue(second.body.isEmpty, "\(status) 转 GET 后应丢弃请求体")
        XCTAssertNil(second.header("Content-Type"), "body 丢弃后不应再带 Content-Type")
    }

    func testRedirect301PostBecomesGetAndDropsBody() async throws {
        try await assertRedirectPostToGet(status: 301, reason: "Moved Permanently", path: "/r301")
    }

    func testRedirect302PostBecomesGetAndDropsBody() async throws {
        try await assertRedirectPostToGet(status: 302, reason: "Found", path: "/r302")
    }

    func testRedirect303PostBecomesGet() async throws {
        try await assertRedirectPostToGet(status: 303, reason: "See Other", path: "/r303")
    }

    // MARK: - 12~13. 307/308：保持方法与 body

    /// 断言 POST 收到 307/308 后保持 POST 并重放 body（两跳都在服务器留痕）。
    private func assertRedirectKeepsMethodAndBody(status: Int, reason: String, path: String) async throws {
        let handlers: [String: LocalScriptedServer.Handler] = [
            path: { _ in
                LocalScriptedServer.Response(status: status, reason: reason,
                                             headers: [("Location", "/target")],
                                             body: Data())
            },
            "/target": { _ in
                LocalScriptedServer.Response(status: 200, reason: "OK",
                                             headers: [("X-Target", "1")],
                                             body: Data("target-body".utf8))
            }
        ]
        let server = try startServer(handlers: handlers)
        let (client, _, _) = makeClient()

        var request = HTTPRequest(url: url(path, server), method: .post)
        request.body = Data("payload=1".utf8)
        request.contentType = "application/x-www-form-urlencoded"

        let response = try await client.execute(request)

        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(response.body, Data("target-body".utf8))
        XCTAssertEqual(server.requests.count, 2)
        let second = try XCTUnwrap(server.requests.dropFirst().first)
        XCTAssertEqual(second.path, "/target")
        XCTAssertEqual(second.method, "POST", "\(status) 应保持 POST 方法（OkHttp RedirectInterceptor 语义）")
        XCTAssertEqual(second.body, Data("payload=1".utf8), "\(status) 应重放请求体")
        XCTAssertEqual(second.header("Content-Type"), "application/x-www-form-urlencoded",
                       "\(status) 保持 body 时 Content-Type 也要保留")
    }

    func testRedirect307KeepsMethodAndBody() async throws {
        try await assertRedirectKeepsMethodAndBody(status: 307, reason: "Temporary Redirect", path: "/r307")
    }

    func testRedirect308KeepsMethodAndBody() async throws {
        try await assertRedirectKeepsMethodAndBody(status: 308, reason: "Permanent Redirect", path: "/r308")
    }

    // MARK: - 14. 重定向链第一跳的 Set-Cookie 被保存（第二跳请求带上）

    func testRedirectFirstHopSetCookieSavedForSecondHop() async throws {
        let handlers: [String: LocalScriptedServer.Handler] = [
            "/hop1": { _ in
                LocalScriptedServer.Response(status: 302, reason: "Found",
                                             headers: [("Location", "/hop2"),
                                                       ("Set-Cookie", "hop=1; Max-Age=600; Path=/")],
                                             body: Data())
            },
            "/hop2": { _ in makeOKResponse("hop2") }
        ]
        let server = try startServer(handlers: handlers)
        let (client, _, _) = makeClient()

        let response = try await client.execute(HTTPRequest(url: url("/hop1", server)))

        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(server.requests.count, 2)
        let second = try XCTUnwrap(server.requests.last)
        XCTAssertEqual(second.path, "/hop2")
        XCTAssertEqual(second.header("Cookie"), "hop=1",
                       "中间跳响应的 Set-Cookie 应在 follow 请求上被带上（逐跳 saveResponse + loadRequest）")
    }

    // MARK: - 15. 超过 20 跳上限：返回最后一跳响应（不崩溃）+ diagnostics

    func testRedirectOverLimitThrowsTooManyRedirectsAndRecordsDiagnostics() async throws {
        // 路径每跳自增（/loop/0 → /loop/1 → ...），避开同一 URL 的循环检测干扰。
        // 对齐 OkHttp：超过 20 次 follow-up 时抛 ProtocolException("Too many follow-up requests")，
        // 而不是把最后一跳响应返回（Kotlin 侧同样会抛，由上层 isTest/错误分支处理）。
        let server = try startServer(handlers: [:], defaultHandler: { request in
            let step = Int(request.path.dropFirst("/loop/".count)) ?? 0
            return LocalScriptedServer.Response(status: 301, reason: "Moved Permanently",
                                                headers: [("Location", "/loop/\(step + 1)")],
                                                body: Data())
        })
        let diag = RuleEngineDiagnostics()
        let (client, _, _) = makeClient(diagnostics: diag)

        var thrown: HTTPError?
        do {
            _ = try await client.execute(HTTPRequest(url: url("/loop/0", server)))
            XCTFail("超过 20 跳应当抛 HTTPError（对齐 OkHttp 的 Too many follow-up requests）")
        } catch let e as HTTPError {
            thrown = e
        } catch {
            XCTFail("应当是 HTTPError，实际：\(error)")
        }
        XCTAssertNotNil(thrown)
        XCTAssertTrue((thrown?.message.lowercased().contains("redirect") ?? false)
                      || (thrown?.message.contains("重定向") ?? false),
                      "错误信息应说明重定向过多；实际：\(thrown?.message ?? "<nil>")")
        XCTAssertEqual(server.requests.count, 22, "初始请求 + 21 次 follow = 服务器共收到 22 次（第 21 跳前判定超限）")
        XCTAssertTrue(diag.diagnostics.contains { $0.message.contains("重定向") || $0.message.lowercased().contains("redirect") },
                      "应记录 diagnostics；实际：\(diag.diagnostics.map { $0.message })")
    }

    // MARK: - 16. readTimeout 覆盖：服务器 hang → SocketTimeoutException(-2)

    func testReadTimeoutOverrideThrowsSocketTimeout() async throws {
        let handlers: [String: LocalScriptedServer.Handler] = [
            "/slow": { _ in LocalScriptedServer.Response(status: 200, reason: "OK", hang: true) }
        ]
        let server = try startServer(handlers: handlers)
        let (client, _, _) = makeClient()

        var request = HTTPRequest(url: url("/slow", server))
        request.readTimeout = 500 // 毫秒；覆盖默认 60s（写进 timeoutIntervalForRequest）

        do {
            _ = try await client.execute(request)
            XCTFail("服务器故意不响应且 readTimeout=500ms，应抛超时错误")
        } catch let error as HTTPError {
            XCTAssertEqual(error.kind, .socketTimeout,
                           "readTimeout 超时应映射为 SocketTimeoutException(-2)，实际：\(error.kind)")
        } catch {
            XCTFail("错误类型应为 HTTPError，实际：\(error)")
        }
    }

    // MARK: - 17. callTimeout 覆盖：hang + 小 callTimeout → 超过设定时间(-1)

    func testCallTimeoutOverrideThrowsTimeoutOverCallLimit() async throws {
        let handlers: [String: LocalScriptedServer.Handler] = [
            "/slow": { _ in LocalScriptedServer.Response(status: 200, reason: "OK", hang: true) }
        ]
        let server = try startServer(handlers: handlers)
        let (client, _, _) = makeClient()

        var request = HTTPRequest(url: url("/slow", server))
        request.callTimeout = 500 // 毫秒；readTimeout 保持默认 60s，只可能是 callTimeout 生效

        do {
            _ = try await client.execute(request)
            XCTFail("callTimeout=500ms 且服务器不响应，应抛超时错误")
        } catch let error as HTTPError {
            XCTAssertEqual(error.kind, .timeoutOverCallLimit,
                           "callTimeout 超时应映射为 -1（超过设定时间），实际：\(error.kind)")
        } catch {
            XCTFail("错误类型应为 HTTPError，实际：\(error)")
        }
    }

    // MARK: - 18. retry 语义：前两次 500 再 200，retry=2 → 共 3 次请求

    func testRetryRepeatsOnServerErrorUntilSuccess() async throws {
        let responder = SequencedResponder([
            LocalScriptedServer.Response(status: 500, reason: "Internal Server Error", body: Data("fail-1".utf8)),
            LocalScriptedServer.Response(status: 500, reason: "Internal Server Error", body: Data("fail-2".utf8)),
            makeOKResponse("ok-3")
        ])
        let handlers: [String: LocalScriptedServer.Handler] = ["/retry": { _ in responder.next() }]
        let server = try startServer(handlers: handlers)
        let (client, _, _) = makeClient()

        var request = HTTPRequest(url: url("/retry", server))
        request.retry = 2 // 最多 1+retry 次（OkHttpUtils.newCallResponse）

        let response = try await client.execute(request)

        XCTAssertEqual(response.status, 200, "前两次 500、第三次 200，retry=2 应最终拿到 200")
        XCTAssertEqual(response.body, Data("ok-3".utf8))
        XCTAssertEqual(responder.count, 3, "应恰好尝试 1+retry 次")
        XCTAssertEqual(server.requests.count, 3)
    }

    // MARK: - 19. retry 只对非 2xx 生效：第一次 200 就不重试

    func testRetryDoesNotRepeatOnSuccess() async throws {
        let responder = SequencedResponder([makeOKResponse("first-ok"), makeOKResponse("second")])
        let handlers: [String: LocalScriptedServer.Handler] = ["/ok": { _ in responder.next() }]
        let server = try startServer(handlers: handlers)
        let (client, _, _) = makeClient()

        var request = HTTPRequest(url: url("/ok", server))
        request.retry = 5

        let response = try await client.execute(request)

        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(response.body, Data("first-ok".utf8), "2xx 应提前返回第一次的响应")
        XCTAssertEqual(responder.count, 1, "2xx 时不应继续重试")
        XCTAssertEqual(server.requests.count, 1)
    }

    // MARK: - 20. 错误分类：连不上的端口 → connectRefused(-4) 或 other(-7)

    func testConnectRefusedOnDeadPortMapsToConnectError() async throws {
        let (client, _, _) = makeClient()
        // 127.0.0.1:1 必然没有监听：ECONNREFUSED -> ConnectException。不用「不存在的域名」
        // 场景（unknownHost 的 DNS 行为依赖 CI 网络环境），按任务约定用必败地址替代。
        do {
            _ = try await client.execute(HTTPRequest(url: "http://127.0.0.1:1/dead"))
            XCTFail("端口必然连不上，应抛 HTTPError")
        } catch let error as HTTPError {
            switch error.kind {
            case .connectRefused, .other:
                break
            default:
                XCTFail("应映射为 connectRefused(-4) 或 other(-7)，实际：\(error.kind)（\(error.message)）")
            }
        } catch {
            XCTFail("错误类型应为 HTTPError，实际：\(error)")
        }
    }

    // MARK: - 21. dnsIp 被忽略但请求成功 + diagnostics 说明

    func testDnsIpIgnoredButRequestSucceedsWithDiagnostic() async throws {
        let handlers: [String: LocalScriptedServer.Handler] = ["/dns": { _ in makeOKResponse("dns-ok") }]
        let server = try startServer(handlers: handlers)
        let diag = RuleEngineDiagnostics()
        let (client, _, _) = makeClient(diagnostics: diag)

        var request = HTTPRequest(url: url("/dns", server))
        request.dnsIp = "10.9.9.9" // URLSession 不支持自定义解析：应忽略并记 diagnostics

        let response = try await client.execute(request)

        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(response.body, Data("dns-ok".utf8))
        XCTAssertTrue(diag.diagnostics.contains { $0.message.contains("dnsIp") },
                      "应记录 dnsIp 被忽略的 diagnostics；实际：\(diag.diagnostics.map { $0.message })")
    }

    // MARK: - 22. 非法代理字段：记 diagnostics 且请求照常成功

    func testInvalidProxyRecordedAndRequestSucceeds() async throws {
        let handlers: [String: LocalScriptedServer.Handler] = ["/proxy": { _ in makeOKResponse("proxy-ok") }]
        let server = try startServer(handlers: handlers)
        let diag = RuleEngineDiagnostics()
        let (client, _, _) = makeClient(diagnostics: diag)

        var request = HTTPRequest(url: url("/proxy", server))
        request.proxy = "not a proxy" // 无法解析：忽略 + diagnostics（对应 getProxyClient 的容错）

        let response = try await client.execute(request)

        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(response.body, Data("proxy-ok".utf8))
        XCTAssertTrue(diag.diagnostics.contains { $0.message.contains("代理") },
                      "应记录代理解析失败的 diagnostics；实际：\(diag.diagnostics.map { $0.message })")
    }

    // MARK: - 23. gzip 响应体被正确解压

    func testGzipResponseBodyDecompressed() async throws {
        let original = Data("gzip 原文：中文与字节混排 ✔".utf8)
        let compressed = LocalScriptedServer.gzip(original)
        XCTAssertNotEqual(compressed, original, "gzip 容器应不同于原文，确保真的在测解压")

        let handlers: [String: LocalScriptedServer.Handler] = [
            "/gz": { _ in
                LocalScriptedServer.Response(status: 200, reason: "OK",
                                             headers: [("Content-Encoding", "gzip"),
                                                       ("Content-Type", "text/plain; charset=utf-8")],
                                             body: compressed)
            }
        ]
        let server = try startServer(handlers: handlers)
        let (client, _, _) = makeClient()

        let response = try await client.execute(HTTPRequest(url: url("/gz", server)))

        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(response.body, original,
                       "Content-Encoding: gzip 的响应体应被 URLSession 透明解压（替代 DecompressInterceptor）")
    }

    // MARK: - 24. 同名响应头多值：headerValues 能取到全部

    func testDuplicateResponseHeadersVisibleViaHeaderValues() async throws {
        let handlers: [String: LocalScriptedServer.Handler] = [
            "/multi": { _ in
                LocalScriptedServer.Response(status: 200, reason: "OK",
                                             headers: [("Set-Cookie", "m1=alpha; Max-Age=3600; Path=/"),
                                                       ("Set-Cookie", "m2=beta; Path=/"),
                                                       ("X-Dup", "one"),
                                                       ("X-Dup", "two")],
                                             body: Data("multi".utf8))
            }
        ]
        let server = try startServer(handlers: handlers)
        let (client, store, _) = makeClient()

        let response = try await client.execute(HTTPRequest(url: url("/multi", server)))

        // 平台差异：URLSession/CFNetwork 可能把重复头按逗号或换行合并成一条，也可能保留多条；
        // 两种形态下都要求两个同名值能在 headerValues 结果里被取到。
        let setCookieTokens = response.headerValues("Set-Cookie")
            .flatMap { $0.components(separatedBy: CharacterSet(charactersIn: ",\n")) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .joined(separator: "|")
        XCTAssertTrue(setCookieTokens.contains("m1=alpha"),
                      "应能取到第一个 Set-Cookie：\(response.headerValues("Set-Cookie"))")
        XCTAssertTrue(setCookieTokens.contains("m2=beta"),
                      "应能取到第二个 Set-Cookie：\(response.headerValues("Set-Cookie"))")

        let dupTokens = response.headerValues("X-Dup")
            .flatMap { $0.components(separatedBy: CharacterSet(charactersIn: ",\n")) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .joined(separator: "|")
        XCTAssertTrue(dupTokens.contains("one"), "应能取到同名头第一个值：\(response.headerValues("X-Dup"))")
        XCTAssertTrue(dupTokens.contains("two"), "应能取到同名头第二个值：\(response.headerValues("X-Dup"))")

        // 持久化侧：m1 带 Max-Age，两种合并形态下都可解析并落 CookieStore
        XCTAssertTrue(store.getCookieNoSession(url("/multi", server)).contains("m1=alpha"))
    }

    // MARK: - 25. 非 2xx 也照常返回 HTTPResponse（404/500 不抛错）

    func testNon2xxReturnedWithoutThrow() async throws {
        let handlers: [String: LocalScriptedServer.Handler] = [
            "/missing": { _ in
                LocalScriptedServer.Response(status: 404, reason: "Not Found",
                                             headers: [("Content-Type", "text/plain")],
                                             body: Data("not-found-body".utf8))
            },
            "/error": { _ in
                LocalScriptedServer.Response(status: 500, reason: "Boom", body: Data("server-error".utf8))
            }
        ]
        let server = try startServer(handlers: handlers)
        let (client, _, _) = makeClient()

        let notFound = try await client.execute(HTTPRequest(url: url("/missing", server)))
        XCTAssertEqual(notFound.status, 404, "404 应作为普通响应返回，不抛错")
        XCTAssertEqual(notFound.body, Data("not-found-body".utf8))

        let serverError = try await client.execute(HTTPRequest(url: url("/error", server)))
        XCTAssertEqual(serverError.status, 500)
        XCTAssertEqual(serverError.message, "Internal Server Error",
                       "message 用标准短语表近似（URLSession 不暴露服务器原话）")
        XCTAssertEqual(serverError.body, Data("server-error".utf8))
    }

    // MARK: - 26. mapError 纯函数：URLError 码 → HTTPError.Kind（含 unknownHost(-3)）

    func testErrorMappingFromURLErrorCodes() {
        func mappedKind(_ code: Int) -> HTTPError.Kind {
            let error = NSError(domain: NSURLErrorDomain, code: code, userInfo: nil)
            return URLSessionHTTPClient.mapError(error, requestURL: "http://example.invalid/").kind
        }

        XCTAssertEqual(mappedKind(NSURLErrorTimedOut), .socketTimeout)
        XCTAssertEqual(mappedKind(NSURLErrorCannotFindHost), .unknownHost,
                       "域名解析失败应映射 -3（用合成错误测，避免依赖 CI 的 DNS 环境）")
        XCTAssertEqual(mappedKind(NSURLErrorDNSLookupFailed), .unknownHost)
        XCTAssertEqual(mappedKind(NSURLErrorCannotConnectToHost), .connectRefused)
        XCTAssertEqual(mappedKind(NSURLErrorNetworkConnectionLost), .socket)
        XCTAssertEqual(mappedKind(NSURLErrorSecureConnectionFailed), .ssl)
        XCTAssertEqual(mappedKind(NSURLErrorBadURL), .other)
    }

    // MARK: - 27. 超时派生（readTimeout → callTimeout 的换算，来自 AnalyzeUrl.getClient）

    func testTimeoutFallbackSemantics() {
        XCTAssertEqual(URLSessionHTTPClient.readTimeoutMillis(for: HTTPRequest(url: "http://127.0.0.1/")),
                       60_000, "默认 readTimeout 60s（HttpHelper.okHttpClient）")
        XCTAssertEqual(URLSessionHTTPClient.callTimeoutMillis(for: HTTPRequest(url: "http://127.0.0.1/")),
                       60_000, "默认 callTimeout 60s")

        var request = HTTPRequest(url: "http://127.0.0.1/")
        request.readTimeout = 1_000
        XCTAssertEqual(URLSessionHTTPClient.readTimeoutMillis(for: request), 1_000, "readTimeout 覆盖按毫秒")
        XCTAssertEqual(URLSessionHTTPClient.callTimeoutMillis(for: request), 60_000,
                       "readTimeout*2=2s 小于 60s 时取 60s")

        request.readTimeout = 40_000
        XCTAssertEqual(URLSessionHTTPClient.callTimeoutMillis(for: request), 80_000,
                       "readTimeout*2=80s 大于 60s 时取 80s")

        request.callTimeout = 1_234
        XCTAssertEqual(URLSessionHTTPClient.callTimeoutMillis(for: request), 1_234,
                       "显式 callTimeout 优先")
    }
}
