import Foundation

/// 一个可选模型。`id` 是调用时写进请求的那个名字，`displayName` 只用于展示。
struct AIModelSummary: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let displayName: String

    init(id: String, displayName: String? = nil) {
        self.id = id
        let trimmed = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.displayName = trimmed.isEmpty ? id : trimmed
    }
}

enum AIModelsError: LocalizedError, Equatable {
    case http(Int, String)
    case notAList(String)
    case empty

    var errorDescription: String? {
        switch self {
        case let .http(code, message):
            return message.isEmpty ? "获取模型列表失败：HTTP \(code)" : "HTTP \(code)：\(message)"
        case let .notAList(snippet):
            return "返回的不是模型列表：\(snippet)"
        case .empty:
            return "这家服务没有返回任何模型。"
        }
    }
}

/// 模型列表的解析。各家的 JSON 形状差异很大，沿用 OpenMinis 的宽容策略：
/// 列表可能叫 `data` / `models` / `items` / `results` / `result`，也可能直接是数组，
/// 还可能嵌一层；条目里的名字可能在 `id` / `model` / `model_id` / `name`。
enum AIModelListParser {
    private static let listKeys = ["data", "models", "items", "results", "result"]
    private static let idKeys = ["id", "model", "model_id", "name"]
    private static let nameKeys = ["display_name", "displayName", "name", "label", "title"]

    static func list(_ data: Data) -> [Any]? {
        guard let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return nil
        }
        if let array = json as? [Any] { return array }
        guard let object = json as? [String: Any] else { return nil }
        for key in listKeys {
            if let array = object[key] as? [Any] { return array }
        }
        for key in listKeys {
            guard let inner = object[key] as? [String: Any] else { continue }
            for innerKey in listKeys {
                if let array = inner[innerKey] as? [Any] { return array }
            }
        }
        return nil
    }

    static func parse(_ data: Data) -> [AIModelSummary]? {
        guard let raw = list(data) else { return nil }
        var seen = Set<String>()
        var models: [AIModelSummary] = []
        for item in raw {
            guard let entry = entry(item) else { continue }
            // Gemini 的 name 是 "models/gemini-2.5-flash"，调用时只写冒号前的模型名。
            var identifier = entry.id
            if identifier.hasPrefix("models/") { identifier = String(identifier.dropFirst("models/".count)) }
            guard !identifier.isEmpty, seen.insert(identifier).inserted else { continue }
            models.append(AIModelSummary(id: identifier,
                                         displayName: displayName(entry.object) ?? identifier))
        }
        return models
    }

    private static func entry(_ raw: Any) -> (id: String, object: [String: Any])? {
        if let id = raw as? String {
            let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : (trimmed, [:])
        }
        guard let object = raw as? [String: Any] else { return nil }
        for key in idKeys {
            if let value = object[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return (trimmed, object) }
            }
        }
        return nil
    }

    private static func displayName(_ object: [String: Any]) -> String? {
        for key in nameKeys {
            if let value = object[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                // 名字和 id 一样时没有额外信息，交给调用方回退。
                if !trimmed.isEmpty, !trimmed.hasPrefix("models/") { return trimmed }
            }
        }
        return nil
    }

    /// 错误响应里的一句话，便于直接展示。
    static func errorMessage(_ data: Data) -> String {
        AIResponseParser.errorMessage(data: data) ?? String((String(data: data, encoding: .utf8) ?? "").prefix(200))
    }
}

/// 拉取模型列表。端点与对话请求用同一套地址规则，避免"对话能通、列表拉不到"。
struct AIModelFetcher: Sendable {
    var session: URLSession = .shared

    func fetch(provider: AIProvider, config: AIServiceConfig, apiKey: String) async throws -> [AIModelSummary] {
        let request = try makeRequest(provider: provider, config: config, apiKey: apiKey)
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw AIModelsError.http(status, AIModelListParser.errorMessage(data))
        }
        guard let models = AIModelListParser.parse(data) else {
            throw AIModelsError.notAList(String((String(data: data, encoding: .utf8) ?? "").prefix(200)))
        }
        guard !models.isEmpty else { throw AIModelsError.empty }
        return filter(models, provider: provider)
    }

    func makeRequest(provider: AIProvider, config: AIServiceConfig, apiKey: String) throws -> URLRequest {
        let base = AIRequestBuilder.normalizedBase(config.baseURL)
        guard !base.isEmpty else { throw AIError.badURL }
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        var urlString: String
        switch provider.proto {
        case .openAI:
            if base.hasSuffix("/chat/completions") {
                urlString = String(base.dropLast("/chat/completions".count)) + "/models"
            } else if config.appendV1 ?? provider.appendV1 {
                var host = base
                if host.hasSuffix("/v1") { host = String(host.dropLast(3)) }
                urlString = host + "/v1/models"
            } else {
                urlString = base + "/models"
            }
        case .anthropic:
            urlString = (base.hasSuffix("/v1") ? base : base + "/v1") + "/models?limit=1000"
        case .gemini:
            let prefix = base.contains("/v1beta") ? base : base + "/v1beta"
            urlString = prefix + "/models?pageSize=200"
        }

        guard var components = URLComponents(string: urlString) else { throw AIError.badURL }
        if provider.proto == .gemini, !key.isEmpty {
            var items = components.queryItems ?? []
            items.append(URLQueryItem(name: "key", value: key))
            components.queryItems = items
        }
        guard let url = components.url else { throw AIError.badURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        switch provider.proto {
        case .openAI:
            if !key.isEmpty { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        case .anthropic:
            if !key.isEmpty { request.setValue(key, forHTTPHeaderField: "x-api-key") }
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        case .gemini:
            break
        }
        return request
    }

    /// 官方 OpenAI 的列表混着 embedding、语音、画图模型，过滤掉明显不能对话的。
    /// 第三方中转站的名字不在这个命名体系里，原样保留。
    private func filter(_ models: [AIModelSummary], provider: AIProvider) -> [AIModelSummary] {
        let excluded = ["embedding", "whisper", "tts", "dall-e", "moderation",
                        "transcribe", "realtime", "-audio", "image-1", "omni-moderation"]
        let filtered: [AIModelSummary]
        if provider.id == "openai" {
            filtered = models.filter { model in
                let id = model.id.lowercased()
                return !excluded.contains { id.contains($0) }
            }
        } else {
            filtered = models
        }
        let result = filtered.isEmpty ? models : filtered
        return result.sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }
}
