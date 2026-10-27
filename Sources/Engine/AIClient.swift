import Foundation

/// 对话请求的执行层。只做一件事：把 `AIRequestBuilder` 造好的请求发出去，
/// 把 `AIResponseParser` 能读懂的响应交回来。测试可注入自定义 session。
struct AIClient: Sendable {
    var session: URLSession = .shared

    /// 发一次对话，返回纯文本。
    func complete(provider: AIProvider, config: AIServiceConfig, apiKey: String,
                  messages: [AIMessage], maxTokens: Int = 512,
                  timeout: TimeInterval = 30) async throws -> String {
        let request = try AIRequestBuilder.request(provider, config: config, apiKey: apiKey,
                                                   messages: messages, maxTokens: maxTokens,
                                                   timeout: timeout)
        let (data, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else {
            throw AIError.http(code, AIResponseParser.errorMessage(data: data) ?? "")
        }
        let text = try AIResponseParser.text(provider.proto, data: data)
        let cleaned = AITextCleaner.clean(text)
        guard !cleaned.isEmpty else { throw AIError.emptyReply }
        return cleaned
    }

    /// 连通性测试：发一句最短的 ping，返回回复与耗时。
    func ping(provider: AIProvider, config: AIServiceConfig, apiKey: String) async throws -> (text: String, seconds: Double) {
        let started = Date()
        let reply = try await complete(
            provider: provider, config: config, apiKey: apiKey,
            messages: [.user("只回复：ok")], maxTokens: 16, timeout: 20)
        return (reply, Date().timeIntervalSince(started))
    }
}
