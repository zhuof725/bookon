import Foundation

/// 一次连通性测试的完整结果。失败时把 URL、HTTP 状态和响应片段一起带回来，
/// 用户不用猜"连不上"是地址写错、密钥错误还是被网关拒绝。
struct AIProbeResult: Sendable {
    let ok: Bool
    /// 一句话结论：`连接成功` / `HTTP 401` / `无法连接服务器`。
    let title: String
    /// 服务端返回的错误文案或模型回复。
    let detail: String
    let url: String
    let status: Int
    let seconds: Double
    /// 响应体前 400 字，便于复制排查。
    let raw: String

    var summary: String {
        var lines = ["\(title) · \(String(format: "%.1f", seconds))s"]
        if !detail.isEmpty { lines.append(detail) }
        lines.append("请求：\(url)")
        return lines.joined(separator: "\n")
    }
}

/// 对话请求的执行层。只做一件事：把 `AIRequestBuilder` 造好的请求发出去，
/// 把 `AIResponseParser` 能读懂的响应交回来。测试可注入自定义 session。
struct AIClient: Sendable {
    var session: URLSession = .shared

    /// 发一次对话，返回纯文本。失败抛 `AIError`。
    func complete(provider: AIProvider, config: AIServiceConfig, apiKey: String,
                  messages: [AIMessage], maxTokens: Int = 512,
                  timeout: TimeInterval = 30) async throws -> String {
        let request = try AIRequestBuilder.request(provider, config: config, apiKey: apiKey,
                                                   messages: messages, maxTokens: maxTokens,
                                                   timeout: timeout)
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw AIError.http(status, AIResponseParser.errorMessage(data: data) ?? "")
        }
        let text = AITextCleaner.clean(try AIResponseParser.text(provider.proto, data: data))
        guard !text.isEmpty else { throw AIError.emptyReply }
        return text
    }

    /// 连通性测试：发一句最短的 ping，把成功/失败都收敛成一个可展示的结果。
    func probe(provider: AIProvider, config: AIServiceConfig, apiKey: String) async -> AIProbeResult {
        let started = Date()
        var urlString = ""

        func elapsed() -> Double { Date().timeIntervalSince(started) }

        func failure(_ title: String, _ detail: String, raw: String = "", status: Int = 0) -> AIProbeResult {
            AIProbeResult(ok: false, title: title, detail: detail, url: urlString,
                          status: status, seconds: elapsed(), raw: raw)
        }

        let request: URLRequest
        do {
            request = try AIRequestBuilder.request(
                provider, config: config, apiKey: apiKey,
                messages: [.user("只回复：ok")], maxTokens: 32, timeout: 30)
            urlString = request.url?.absoluteString ?? ""
        } catch {
            return failure("地址配置有误", error.localizedDescription)
        }

        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: data, encoding: .utf8) ?? ""
            let snippet = String(body.prefix(400))

            guard (200..<300).contains(status) else {
                let message = AIResponseParser.errorMessage(data: data)
                    ?? (body.isEmpty ? "服务返回了空响应" : snippet)
                return failure("HTTP \(status)", message, raw: snippet, status: status)
            }

            do {
                let text = AITextCleaner.clean(try AIResponseParser.text(provider.proto, data: data))
                guard !text.isEmpty else {
                    return failure("响应为空", "HTTP 200 但没有正文。推理类模型可能需要更大的 max_tokens。",
                                   raw: snippet, status: status)
                }
                return AIProbeResult(ok: true, title: "连接成功", detail: text,
                                     url: urlString, status: status, seconds: elapsed(), raw: snippet)
            } catch {
                return failure("响应无法解析", error.localizedDescription, raw: snippet, status: status)
            }
        } catch {
            let ns = error as NSError
            let hint: String
            switch ns.code {
            case NSURLErrorTimedOut: hint = "请求超时。检查网络，或确认这个地址在当前网络下可访问。"
            case NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost:
                hint = "找不到服务器。检查地址拼写，或该域名是否需要代理。"
            case NSURLErrorNotConnectedToInternet: hint = "设备当前没有网络。"
            case NSURLErrorAppTransportSecurityRequiresSecureConnection:
                hint = "系统拦截了明文 HTTP 请求。"
            case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted:
                hint = "TLS 握手失败：证书不受信任，或中间人代理改写了连接。"
            default: hint = error.localizedDescription
            }
            return failure("连接失败", hint + "（\(ns.domain) \(ns.code)）")
        }
    }
}
