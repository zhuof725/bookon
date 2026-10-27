import Foundation

/// AI 服务的三种请求方言。
///
/// 国内绝大多数服务（DeepSeek、通义千问、豆包、智谱、Kimi、硅基流动）以及自定义服务
/// 都兼容 OpenAI 的 `/chat/completions`，因此共用一套代码；Claude 与 Gemini 各有一套。
enum AIProtocol: String, Codable, Sendable {
    case openAI
    case anthropic
    case gemini
}

/// 内置提供商目录的一条。模型名会随厂商更新而过期，编辑页允许手填，
/// 这里只提供默认值与候选项。
struct AIProvider: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    /// SF Symbol：没有品牌 logo 时用同色符号保持视觉一致。
    let symbol: String
    /// 品牌色（hex，无 #）。
    let tint: String
    let proto: AIProtocol
    let baseURL: String
    let defaultModel: String
    let modelHints: [String]
    var isCustom: Bool = false

    /// 补全用户漏写的 `/v1` 之类的路径，返回可直接拼接端点的根地址。
    var normalizedBaseURL: String {
        var value = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasSuffix("/") { value.removeLast() }
        return value
    }
}

enum AICatalog {
    /// 顺序与设置页一致：常用在前。
    static let builtins: [AIProvider] = [
        AIProvider(id: "openai", name: "OpenAI", symbol: "brain.head.profile", tint: "10A37F",
                   proto: .openAI, baseURL: "https://api.openai.com/v1",
                   defaultModel: "gpt-4o-mini",
                   modelHints: ["gpt-4o-mini", "gpt-4o", "gpt-4.1-mini", "gpt-4.1", "o4-mini"]),
        AIProvider(id: "claude", name: "Claude", symbol: "sparkles", tint: "D97757",
                   proto: .anthropic, baseURL: "https://api.anthropic.com",
                   defaultModel: "claude-sonnet-4-5",
                   modelHints: ["claude-sonnet-4-5", "claude-opus-4-1", "claude-3-5-haiku-latest"]),
        AIProvider(id: "gemini", name: "Google Gemini", symbol: "diamond.fill", tint: "4285F4",
                   proto: .gemini, baseURL: "https://generativelanguage.googleapis.com",
                   defaultModel: "gemini-2.5-flash",
                   modelHints: ["gemini-2.5-flash", "gemini-2.5-pro", "gemini-2.0-flash"]),
        AIProvider(id: "deepseek", name: "DeepSeek", symbol: "water.waves", tint: "4D6BFE",
                   proto: .openAI, baseURL: "https://api.deepseek.com/v1",
                   defaultModel: "deepseek-chat",
                   modelHints: ["deepseek-chat", "deepseek-reasoner"]),
        AIProvider(id: "qwen", name: "通义千问", symbol: "cloud.fill", tint: "615CED",
                   proto: .openAI, baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1",
                   defaultModel: "qwen-plus",
                   modelHints: ["qwen-plus", "qwen-max", "qwen-turbo", "qwen-long"]),
        AIProvider(id: "doubao", name: "豆包 · 火山方舟", symbol: "flame.fill", tint: "1664FF",
                   proto: .openAI, baseURL: "https://ark.cn-beijing.volces.com/api/v3",
                   defaultModel: "",
                   modelHints: ["填写控制台的推理接入点 ID，如 ep-2024…"]),
        AIProvider(id: "zhipu", name: "智谱 AI", symbol: "z.square.fill", tint: "1A1A1A",
                   proto: .openAI, baseURL: "https://open.bigmodel.cn/api/paas/v4",
                   defaultModel: "glm-4-flash",
                   modelHints: ["glm-4-flash", "glm-4-plus", "glm-4-air"]),
        AIProvider(id: "kimi", name: "Kimi AI", symbol: "moon.stars.fill", tint: "1F1F1F",
                   proto: .openAI, baseURL: "https://api.moonshot.cn/v1",
                   defaultModel: "moonshot-v1-8k",
                   modelHints: ["moonshot-v1-8k", "moonshot-v1-32k", "kimi-k2-0905-preview"]),
        AIProvider(id: "siliconflow", name: "硅基流动", symbol: "hexagon.fill", tint: "7C3AED",
                   proto: .openAI, baseURL: "https://api.siliconflow.cn/v1",
                   defaultModel: "Qwen/Qwen3-8B",
                   modelHints: ["Qwen/Qwen3-8B", "deepseek-ai/DeepSeek-V3", "THUDM/GLM-4-9B-0414"])
    ]

    static let custom = AIProvider(id: "custom", name: "自定义服务", symbol: "plus", tint: "0A84FF",
                                   proto: .openAI, baseURL: "", defaultModel: "",
                                   modelHints: ["任何兼容 OpenAI /chat/completions 的服务"],
                                   isCustom: true)

    static func provider(id: String) -> AIProvider? {
        builtins.first { $0.id == id } ?? (id == custom.id ? custom : nil)
    }
}

/// 一条对话消息。只用到 system / user / assistant 三种角色。
struct AIMessage: Codable, Hashable, Sendable {
    enum Role: String, Codable, Sendable { case system, user, assistant }
    let role: Role
    let content: String

    static func system(_ text: String) -> AIMessage { .init(role: .system, content: text) }
    static func user(_ text: String) -> AIMessage { .init(role: .user, content: text) }
}

/// 已保存的提供商配置。API Key 不进 UserDefaults，单独存 Keychain。
struct AIServiceConfig: Codable, Identifiable, Equatable, Sendable {
    var id: String
    /// 自定义服务的显示名；内置服务为 nil。
    var name: String?
    var baseURL: String
    var model: String
    var temperature: Double
    var enabled: Bool
    var updatedAt: Date

    init(id: String, name: String? = nil, baseURL: String, model: String, temperature: Double = 0.7,
         enabled: Bool = true, updatedAt: Date = Date()) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.model = model
        self.temperature = temperature
        self.enabled = enabled
        self.updatedAt = updatedAt
    }

    var displayName: String {
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return AICatalog.provider(id: id)?.name ?? "AI 服务"
    }

    var trimmedModel: String { model.trimmingCharacters(in: .whitespacesAndNewlines) }
    var canUse: Bool { enabled && !trimmedModel.isEmpty }

    /// 宽度变化不改写存储时用来展示的状态文案。
    func summary(hasKey: Bool) -> String {
        guard hasKey else { return "未配置" }
        guard !trimmedModel.isEmpty else { return "已填写密钥 · 缺模型" }
        return enabled ? trimmedModel : "\(trimmedModel)（已停用）"
    }
}

enum AIError: LocalizedError, Equatable {
    case missingKey
    case missingModel
    case badURL
    case http(Int, String)
    case emptyReply
    case decode(String)

    var errorDescription: String? {
        switch self {
        case .missingKey: return "先填写 API Key。"
        case .missingModel: return "先填写模型名。"
        case .badURL: return "接口地址不正确。"
        case let .http(code, message):
            return message.isEmpty ? "服务返回 HTTP \(code)。" : "HTTP \(code)：\(message)"
        case .emptyReply: return "服务返回了空回复。"
        case let .decode(detail): return "无法解析服务响应：\(detail)"
        }
    }
}

/// 请求构造。纯函数，便于回归测试直接断言 URL 与 JSON 结构。
enum AIRequestBuilder {
    /// 各协议的对话端点。`model` 只对 Gemini 的路径有影响。
    static func endpoint(_ provider: AIProvider, config: AIServiceConfig, apiKey: String) throws -> URL {
        let base = config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !base.isEmpty, var url = URL(string: base) else { throw AIError.badURL }
        let model = config.trimmedModel

        switch provider.proto {
        case .openAI:
            url.appendPathComponent("chat")
            url.appendPathComponent("completions")
        case .anthropic:
            // 允许用户填 https://api.anthropic.com 或 .../v1
            if !url.path.hasSuffix("/v1") { url.appendPathComponent("v1") }
            url.appendPathComponent("messages")
        case .gemini:
            if !url.path.contains("/v1beta") { url.appendPathComponent("v1beta") }
            url.appendPathComponent("models")
            // Gemini 的端点形如 /v1beta/models/gemini-2.5-flash:generateContent
            url.appendPathComponent("\(model):generateContent")
        }
        return url
    }

    static func request(_ provider: AIProvider, config: AIServiceConfig, apiKey: String,
                        messages: [AIMessage], maxTokens: Int = 512,
                        timeout: TimeInterval = 30) throws -> URLRequest {
        let model = config.trimmedModel
        guard !model.isEmpty else { throw AIError.missingModel }
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AIError.missingKey }

        let url = try endpoint(provider, config: config, apiKey: apiKey)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let system = messages.first { $0.role == .system }?.content
        let dialogue = messages.filter { $0.role != .system }
        let temperature = min(max(config.temperature, 0), 2)

        switch provider.proto {
        case .openAI:
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            var payload: [String: Any] = [
                "model": model,
                "messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] },
                "temperature": temperature,
                "max_tokens": maxTokens
            ]
            if provider.id == "zhipu" { payload["stream"] = false }
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        case .anthropic:
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            var payload: [String: Any] = [
                "model": model,
                "max_tokens": maxTokens,
                "temperature": temperature,
                "messages": dialogue.map { ["role": $0.role.rawValue, "content": $0.content] }
            ]
            if let system, !system.isEmpty { payload["system"] = system }
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        case .gemini:
            // Gemini 用查询参数传密钥；不走 Authorization 头。
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.queryItems = [URLQueryItem(name: "key", value: key)]
            guard let final = components?.url else { throw AIError.badURL }
            request.url = final
            var payload: [String: Any] = [
                "contents": dialogue.map { message in
                    ["role": message.role == .assistant ? "model" : "user",
                     "parts": [["text": message.content]]]
                },
                "generationConfig": ["temperature": temperature, "maxOutputTokens": maxTokens]
            ]
            if let system, !system.isEmpty {
                payload["systemInstruction"] = ["parts": [["text": system]]]
            }
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        }
        return request
    }
}

/// 响应解析。服务返回的错误结构各不相同，尽量取出可读的一句话。
enum AIResponseParser {
    private static func object(_ data: Data) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func text(_ proto: AIProtocol, data: Data) throws -> String {
        guard let root = object(data) else {
            let raw = String(data: data, encoding: .utf8) ?? ""
            throw AIError.decode(raw.isEmpty ? "响应不是 JSON" : String(raw.prefix(200)))
        }
        switch proto {
        case .openAI:
            guard let choices = root["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any] else {
                throw AIError.decode(errorMessage(root) ?? "缺少 choices[0].message")
            }
            if let text = message["content"] as? String, !text.isEmpty { return text }
            // 部分推理模型把最终答案放在 reasoning_content 之外的 content 数组里。
            if let parts = message["content"] as? [[String: Any]] {
                let joined = parts.compactMap { $0["text"] as? String }.joined()
                if !joined.isEmpty { return joined }
            }
            throw AIError.emptyReply

        case .anthropic:
            guard let blocks = root["content"] as? [[String: Any]] else {
                throw AIError.decode(errorMessage(root) ?? "缺少 content")
            }
            let text = blocks.compactMap { block -> String? in
                guard (block["type"] as? String) == "text" else { return nil }
                return block["text"] as? String
            }.joined()
            guard !text.isEmpty else { throw AIError.emptyReply }
            return text

        case .gemini:
            guard let candidates = root["candidates"] as? [[String: Any]],
                  let content = candidates.first?["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]] else {
                throw AIError.decode(errorMessage(root) ?? "缺少 candidates[0].content.parts")
            }
            let text = parts.compactMap { $0["text"] as? String }.joined()
            guard !text.isEmpty else { throw AIError.emptyReply }
            return text
        }
    }

    /// 从各家错误响应里抽一句话：`error.message` / `error` 字符串 / `message`。
    static func errorMessage(_ root: [String: Any]) -> String? {
        if let error = root["error"] as? [String: Any], let message = error["message"] as? String {
            return message
        }
        if let error = root["error"] as? String { return error }
        if let message = root["message"] as? String { return message }
        return nil
    }

    static func errorMessage(data: Data) -> String? {
        guard let root = object(data) else {
            let raw = String(data: data, encoding: .utf8) ?? ""
            return raw.isEmpty ? nil : String(raw.prefix(200))
        }
        return errorMessage(root)
    }
}

/// 生成结果的清洗：模型常把整段包在代码块或引号里。
enum AITextCleaner {
    static func clean(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            // 去掉 ```json / ``` 包裹
            if let firstBreak = text.firstIndex(of: "\n") {
                text = String(text[text.index(after: firstBreak)...])
            }
            if let fence = text.range(of: "```", options: .backwards) {
                text = String(text[..<fence.lowerBound])
            }
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let quotes: [(Character, Character)] = [("「", "」"), ("“", "”"), ("\"", "\"")]
        for (open, close) in quotes where text.count >= 2 {
            if text.first == open, text.last == close {
                text.removeFirst()
                text.removeLast()
                break
            }
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
