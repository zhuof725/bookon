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
        check(geminiURL.contains("gemini-2.5-flash:generateContent"), "Gemini 模型名与动作之间的冒号不被编码")
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

        // 空密钥是本地端点（Ollama / LM Studio）的合法配置：请求照发，但不带空的 Bearer 头。
        let keylessRequest = try? AIRequestBuilder.request(openai, config: openAIConfig, apiKey: " ",
                                                          messages: [.user("hi")])
        check(keylessRequest != nil, "空密钥不阻止请求")
        check(keylessRequest?.value(forHTTPHeaderField: "Authorization") == nil, "空密钥不发 Authorization 头")

        // 只填到域名：自动补 /v1
        let hostOnly = AIServiceConfig(id: "openai", baseURL: "https://api.openai.com", model: "gpt-4o-mini")
        let hostRequest = try? AIRequestBuilder.request(openai, config: hostOnly, apiKey: "k", messages: [.user("hi")])
        check(hostRequest?.url?.absoluteString == "https://api.openai.com/v1/chat/completions",
              "只填域名时自动补 /v1")

        // 关掉自动补：按原样拼，用于自建网关
        let verbatim = AIServiceConfig(id: "openai", baseURL: "https://relay.example.com/api", model: "m",
                                       appendV1: false)
        let verbatimRequest = try? AIRequestBuilder.request(openai, config: verbatim, apiKey: "k",
                                                            messages: [.user("hi")])
        check(verbatimRequest?.url?.absoluteString == "https://relay.example.com/api/chat/completions",
              "关闭自动补 /v1 时按原样拼接")

        // 用户直接贴完整端点：不重复
        let fullEndpoint = AIServiceConfig(id: "openai", baseURL: "https://relay.example.com/v1/chat/completions",
                                           model: "m")
        let fullRequest = try? AIRequestBuilder.request(openai, config: fullEndpoint, apiKey: "k",
                                                        messages: [.user("hi")])
        check(fullRequest?.url?.absoluteString == "https://relay.example.com/v1/chat/completions",
              "贴完整端点时不重复拼接")

        // 国内服务的版本段不能被再补一个 /v1
        for (name, base) in [("智谱", "https://open.bigmodel.cn/api/paas/v4"),
                             ("通义", "https://dashscope.aliyuncs.com/compatible-mode/v1"),
                             ("豆包", "https://ark.cn-beijing.volces.com/api/v3")] {
            let config = AIServiceConfig(id: "x", baseURL: base, model: "m", appendV1: false)
            let request = try? AIRequestBuilder.request(openai, config: config, apiKey: "k", messages: [.user("hi")])
            check(request?.url?.absoluteString == base + "/chat/completions", "\(name) 的版本路径保持原样")
        }

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

        // MARK: 模型列表

        func parsed(_ json: String) -> [AIModelSummary] {
            AIModelListParser.parse(Data(json.utf8)) ?? []
        }
        check(parsed(#"{"data":[{"id":"gpt-4o"},{"id":"gpt-4o-mini"}]}"#).count == 2, "解析 OpenAI 模型列表")
        check(parsed(#"["alpha","beta"]"#).map(\.id) == ["alpha", "beta"], "解析裸数组模型列表")
        check(parsed(#"{"data":{"models":[{"id":"nested"}]}}"#).first?.id == "nested", "解析嵌套一层的模型列表")
        let geminiModels = parsed(#"{"models":[{"name":"models/gemini-2.5-flash","displayName":"Gemini 2.5 Flash"}]}"#)
        check(geminiModels.first?.id == "gemini-2.5-flash", "Gemini 的 models/ 前缀被去掉")
        check(geminiModels.first?.displayName == "Gemini 2.5 Flash", "Gemini 的 displayName 保留")
        check(parsed(#"{"data":[{"id":"claude-sonnet-4-5","display_name":"Claude Sonnet 4.5"}]}"#).first?.displayName
                == "Claude Sonnet 4.5", "解析 Anthropic 的 display_name")
        check(parsed(#"{"data":[{"id":"a"},{"id":"a"}]}"#).count == 1, "重复模型去重")
        check(parsed(#"{"error":{"message":"bad key"}}"#).isEmpty, "错误响应不当作模型列表")

        // 模型列表的端点规则要与对话端点一致
        let listOpenAI = AIServiceConfig(id: "openai", baseURL: "https://api.openai.com", model: "m")
        let listRequest = try? AIModelFetcher().makeRequest(provider: openai, config: listOpenAI, apiKey: "k")
        check(listRequest?.url?.absoluteString == "https://api.openai.com/v1/models", "OpenAI 官方补 /v1/models")
        var listRequest2: URLRequest?
        do { listRequest2 = try AIModelFetcher().makeRequest(provider: openai, config: openAIConfig, apiKey: "k") } catch {}
        check(listRequest2?.url?.absoluteString == "https://api.openai.com/v1/models", "已含 /v1 时不重复成 /v1/v1/models")
        check(listRequest2?.value(forHTTPHeaderField: "Authorization") == "Bearer k", "模型列表带 Bearer")

        let listClaude = AIServiceConfig(id: "claude", baseURL: "https://api.anthropic.com", model: "m")
        let claudeListRequest = try? AIModelFetcher().makeRequest(provider: provider("claude"), config: listClaude, apiKey: "sk-ant")
        check(claudeListRequest?.url?.absoluteString.hasPrefix("https://api.anthropic.com/v1/models") == true,
              "Claude 的模型端点")
        check(claudeListRequest?.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01",
              "Claude 模型列表带版本头")

        let listGemini = AIServiceConfig(id: "gemini", baseURL: "https://generativelanguage.googleapis.com", model: "m")
        let geminiListRequest = try? AIModelFetcher().makeRequest(provider: provider("gemini"), config: listGemini, apiKey: "AIza")
        let geminiListURL = geminiListRequest?.url?.absoluteString ?? ""
        check(geminiListURL.contains("/v1beta/models"), "Gemini 的模型端点")
        check(geminiListURL.contains("key=AIza"), "Gemini 模型列表的密钥参数")

        // MARK: 模型不按 JSON 答时的兜底（从散文里认书名）

        let prose = """
        结合你的阅读记录，我推荐这几本：
        1. 《让仙门再次伟大》—— 宗门争锋的爽点很足，节奏也快
        2. 万生痴魔：脑洞大，种田变强一路升级
        你列的《让仙门再次伟大》《万生痴魔》里，这两本最合适。
        """
        let loose = AILooseSuggestions.parse(text: prose,
                                             names: ["让仙门再次伟大", "万生痴魔", "捞尸人"],
                                             limit: 8)
        check(loose.count == 2, "散文回复里认出两本书")
        check(loose.first?.index == 0, "第一本命中候选 1")
        check(loose.first?.reason?.contains("宗门") == true, "推荐语取书名后半句")
        check(loose.last?.index == 1, "第二本命中候选 2")
        check(AILooseSuggestions.parse(text: "你列的《让仙门再次伟大》《万生痴魔》都很适合你。",
                                       names: ["让仙门再次伟大", "万生痴魔"]).isEmpty,
              "一行提到多本时不误判为推荐")
        check(AILooseSuggestions.parse(text: "推荐《仙门传》这本。", names: ["仙门", "仙门传"]).first?.index == 1,
              "书名有包含关系时取更长的那本")

        // MARK: 配置 → provider 解析（自定义服务的 id 是 custom-<uuid>）

        let customConfig = AIServiceConfig(id: "custom-1111", name: "1111",
                                           baseURL: "https://api.river.ai", model: "m")
        let customResolved = AICatalog.provider(for: customConfig)
        check(customResolved?.isCustom == true, "自定义服务 custom-<uuid> 能解析出 provider")
        check(customResolved?.proto == .openAI, "自定义服务默认按 OpenAI 兼容")
        check(customResolved?.name == "自定义服务", "自定义服务沿用模板名称")
        check(customConfig.displayName == "1111", "自定义服务显示保存的名字")

        var claudeCustom = customConfig
        claudeCustom.proto = .anthropic
        check(AICatalog.provider(for: claudeCustom)?.proto == .anthropic, "自定义服务保存的协议生效")
        check(AICatalog.provider(for: AIServiceConfig(id: "nope", baseURL: "https://x", model: "m")) == nil,
              "未知 id 不会被误当成自定义服务")

        let builtinResolved = AICatalog.provider(for: AIServiceConfig(id: "claude", baseURL: "https://x", model: "m"))
        check(builtinResolved?.id == "claude" && builtinResolved?.proto == .anthropic, "内置服务仍按目录解析")

        // 协议要随配置一起落库（旧数据没有这个键，解码为 nil）
        if let data = try? JSONEncoder().encode(claudeCustom),
           let decoded = try? JSONDecoder().decode(AIServiceConfig.self, from: data) {
            check(decoded.proto == .anthropic, "配置编码后保留协议")
        } else {
            check(false, "配置编码/解码失败")
        }
        if let legacy = try? JSONDecoder().decode(AIServiceConfig.self, from: Data(#"{"id":"custom-x","baseURL":"https://x","model":"m","temperature":0.7,"enabled":true,"updatedAt":0}"#.utf8)) {
            check(legacy.proto == nil && AICatalog.provider(for: legacy)?.proto == .openAI,
                  "旧配置缺少协议字段时按 OpenAI 兼容")
        } else {
            check(false, "旧配置解码失败")
        }

        // MARK: 目录完整性

        check(AICatalog.builtins.count >= 9, "内置提供商至少 9 个")
        check(AICatalog.builtins.allSatisfy { !$0.baseURL.isEmpty }, "内置提供商都有默认地址")
        check(AICatalog.builtins.allSatisfy { !$0.defaultModel.isEmpty || $0.id == "doubao" },
              "除豆包（需接入点 ID）外都有默认模型")
        check(AICatalog.provider(id: "custom")?.isCustom == true, "自定义服务模板存在")
    }
}
