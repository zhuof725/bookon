//
//  URLSessionHTTPClientTests.swift
//  LegadoNetworkTests
//
//  第 6 步 6B：URLSessionHTTPClient（真实网络）的集成测试。
//
//  用 Network.framework 的 NWListener 在 127.0.0.1 + 随机端口起本地脚本化 HTTP 服务器，
//  可编程返回：状态码/头/body/Set-Cookie/重定向链/gzip 压缩体/指定字节；`hang` 路径
//  故意不响应（测超时）。每个测试独立端口、可并发；tearDown 统一关闭。
//  不依赖任何真实外网。
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