import Foundation

/// AI 服务：请求构造与响应解析的固定断言。不联网，不依赖任何真实密钥。
enum AIRegression {
    static func run(check: (Bool, String) -> Void) {
        func provider(_ id: String) -> AIProvider {
            guard let p = AICatalog.provider(id: id) else {
                print("FAIL: 目录缺少 \(id)"); exit(1)
            }
            return p
        }

        // MARK: OpenAI 兼容

        let openai = provider("openai")
        let openAIConfig = AIServiceConfig(id: "openai", baseURL: "https://api.openai.com/v1",
                                           model: "gpt-4o-mini", temperature: 0.7)
        guard let openAIRequest = try? AIRequestBuilder.request(
            openai, config: openAIConfig, apiKey: "sk-test",
            messages: [.system("你是助手"), .user("你好")]) else {
            print("FAIL: OpenAI 请求构造失败"); exit(1)
        }
        check(openAIRequest.url?.absoluteString == "https://api.openai.com/v1/chat/completions",
              "OpenAI 端点：/v1/chat/completions")
        check(openAIRequest.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test",
              "OpenAI 鉴权头：Bearer")
        let openAIBody = (try? JSONSerialization.jsonObject(with: openAIRequest.httpBody ?? Data())) as? [String: Any]
        check(openAIBody?["model"] as? String == "gpt-4o-mini", "OpenAI body 带 model")
        check((openAIBody?["messages"] as? [[String: Any]])?.count == 2, "OpenAI body 带 system+user 两条消息")
        check((openAIBody?["temperature"] as? Double) == 0.7, "OpenAI body 带 temperature")

        // 末尾斜杠与多余空格不应产生双斜杠
        let slashConfig = AIServiceConfig(id: "openai", baseURL: " https://api.openai.com/v1/ ",
                                          model: "gpt-4o-mini")
        let slashRequest = try? AIRequestBuilder.request(openai, config: slashConfig, apiKey: "k",
                                                         messages: [.user("hi")])
        check(slashRequest?.url?.absoluteString == "https://api.openai.com/v1/chat/completions",
              "地址末尾斜杠/空格会被规整")

        // MARK: Anthropic

        let claude = provider("claude")
        let claudeConfig = AIServiceConfig(id: "claude", baseURL: "https://api.anthropic.com",
                                           model: "claude-sonnet-4-5")
        guard let claudeRequest = try? AIRequestBuilder.request(
            claude, config: claudeConfig, apiKey: "sk-ant",
            messages: [.system("你是助手"), .user("你好")]) else {
            print("FAIL: Claude 请求构造失败"); exit(1)
        }
        check(claudeRequest.url?.absoluteString == "https://api.anthropic.com/v1/messages",
              "Claude 端点：/v1/messages")
        check(claudeRequest.value(forHTTPHeaderField: "x-api-key") == "sk-ant", "Claude 鉴权头：x-api-key")
        check(claudeRequest.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01",
              "Claude 版本头")
        let claudeBody = (try? JSONSerialization.jsonObject(with: claudeRequest.httpBody ?? Data())) as? [String: Any]
        check(claudeBody?["system"] as? String == "你是助手", "Claude body 的 system 独立字段")
        check((claudeBody?["messages"] as? [[String: Any]])?.count == 1, "Claude messages 不含 system")

        // 用户直接填 .../v1 时不重复拼接
        let claudeV1 = AIServiceConfig(id: "claude", baseURL: "https://api.anthropic.com/v1",
                                       model: "claude-sonnet-4-5")
        let claudeV1Request = try? AIRequestBuilder.request(claude, config: claudeV1, apiKey: "k",
                                                            messages: [.user("hi")])
        check(claudeV1Request?.url?.absoluteString == "https://api.anthropic.com/v1/messages",
              "Claude 地址已含 /v1 时不重复")

        // MARK: Gemini

        let gemini = provider("gemini")
        let geminiConfig = AIServiceConfig(id: "gemini",
                                           baseURL: "https://generativelanguage.googleapis.com",
                                           model: "gemini-2.5-flash")
        guard let geminiRequest = try? AIRequestBuilder.request(
            gemini, config: geminiConfig, apiKey: "AIza-test",
            messages: [.system("你是助手"), .user("你好")]) else {
            print("FAIL: Gemini 请求构造失败"); exit(1)
        }
        let geminiURL = geminiRequest.url?.absoluteString ?? ""
        check(geminiURL.contains("/v1beta/models/"), "Gemini 端点：/v1beta/models/")
        check(geminiURL.contains("generateContent"), "Gemini 端点：generateContent")
        check(geminiURL.contains("key=AIza-test"), "Gemini 密钥走查询参数")
        check(geminiRequest.value(forHTTPHeaderField: "Authorization") == nil, "Gemini 不带 Bearer 头")
        let geminiBody = (try? JSONSerialization.jsonObject(with: geminiRequest.httpBody ?? Data())) as? [String: Any]
        let contents = geminiBody?["contents"] as? [[String: Any]]
        check(contents?.count == 1, "Gemini contents 只含对话消息")
        let parts = contents?.first?["parts"] as? [[String: Any]]
        check(parts?.first?["text"] as? String == "你好", "Gemini parts 文本")
        check((geminiBody?["systemInstruction"] as? [String: Any]) != nil, "Gemini systemInstruction 独立字段")

        // MARK: 错误路径

        let missingModel = AIServiceConfig(id: "openai", baseURL: "https://api.openai.com/v1", model: "  ")
        var threwMissingModel = false
        do {
            _ = try AIRequestBuilder.request(openai, config: missingModel, apiKey: "k", messages: [.user("hi")])
        } catch { threwMissingModel = true }
        check(threwMissingModel, "缺模型时直接报错，不发请求")

        var threwMissingKey = false
        do {
            _ = try AIRequestBuilder.request(openai, config: openAIConfig, apiKey: " ", messages: [.user("hi")])
        } catch { threwMissingKey = true }
        check(threwMissingKey, "缺密钥时直接报错")

        // MARK: 响应解析

        func text(_ proto: AIProtocol, _ json: String) -> String? {
            guard let data = json.data(using: .utf8) else { return nil }
            return try? AIResponseParser.text(proto, data: data)
        }
        check(text(.openAI, #"{"choices":[{"message":{"content":"好的"}}]}"#) == "好的", "解析 OpenAI 回复")
        check(text(.anthropic, #"{"content":[{"type":"text","text":"好的"}]}"#) == "好的", "解析 Claude 回复")
        check(text(.anthropic, #"{"content":[{"type":"thinking","thinking":"…"},{"type":"text","text":"好的"}]}"#) == "好的",
              "Claude 跳过 thinking 块")
        check(text(.gemini, #"{"candidates":[{"content":{"parts":[{"text":"好的"}]}}]}"#) == "好的", "解析 Gemini 回复")
        check(text(.openAI, #"{"error":{"message":"无效的令牌"}}"#) == nil, "错误响应不当作正文")

        let errorData = #"{"error":{"message":"无效的令牌","type":"invalid"}}"#.data(using: .utf8) ?? Data()
        check(AIResponseParser.errorMessage(data: errorData) == "无效的令牌", "取出错误文案")
        let plainError = "502 Bad Gateway".data(using: .utf8) ?? Data()
        check(AIResponseParser.errorMessage(data: plainError) == "502 Bad Gateway", "非 JSON 错误保留原文")

        // MARK: 结果清洗

        check(AITextCleaner.clean("```json\n\"一本好书\"\n```") == "一本好书", "去掉代码块与引号")
        check(AITextCleaner.clean("「推荐」") == "推荐", "去掉中文引号")
        check(AITextCleaner.clean("  正文  ") == "正文", "去首尾空白")

        // MARK: 目录完整性

        check(AICatalog.builtins.count >= 9, "内置提供商至少 9 个")
        check(AICatalog.builtins.allSatisfy { !$0.baseURL.isEmpty }, "内置提供商都有默认地址")
        check(AICatalog.builtins.allSatisfy { !$0.defaultModel.isEmpty || $0.id == "doubao" },
              "除豆包（需接入点 ID）外都有默认模型")
        check(AICatalog.provider(id: "custom")?.isCustom == true, "自定义服务模板存在")
    }
}
