import Foundation

/// 用已配置的 AI 服务为探索板块的书生成标签与推荐语。
///
/// 只取板块前若干本，控制单次请求的 token；结果直接写进 `ExploreMetaStore`，
/// 与手动导入的 JSON 走同一条落库路径。
enum AIRecommender {
    /// 一次最多处理的书本数。
    static let maxBooks = 8

    static func systemPrompt() -> String {
        """
        你是中文网络小说的资深编辑。为给定的书各写 2~3 个短标签和一句推荐语。

        要求：
        - 推荐语 18~40 个汉字，像朋友之间推荐那样口语化；
        - 可以用「」强调一个关键词，不要通篇复述简介；
        - 不要以书名开头，不要写"这本书"；
        - 标签是 2~5 个字的类型词，如「都市」「悬疑流」「爽文」。

        只输出一个 JSON 对象，不要 Markdown 代码块，不要任何解释。格式：
        {"书籍地址": {"tags": ["标签1", "标签2"], "reason": "推荐语"}}

        书籍地址必须从书单原样照抄，不能改写、不能省略。
        """
    }

    static func userPrompt(for books: [Book]) -> String {
        let lines = books.enumerated().map { index, book -> String in
            let intro = (book.intro ?? "")
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let clipped = intro.count > 80 ? String(intro.prefix(80)) + "…" : intro
            let kind = (book.kind ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let author = book.author.isEmpty ? "未知" : book.author
            return "\(index + 1). 书名：\(book.name) ｜作者：\(author) ｜分类：\(kind.isEmpty ? "未知" : kind)"
                + " ｜地址：\(book.bookUrl) ｜简介：\(clipped.isEmpty ? "无" : clipped)"
        }
        return "书单：\n" + lines.joined(separator: "\n")
    }

    /// 生成并写入，返回写入的条目数。
    @discardableResult
    static func generate(books: [Book], provider: AIProvider, config: AIServiceConfig,
                         apiKey: String, client: AIClient = AIClient()) async throws -> Int {
        let selected = Array(books.filter { !$0.bookUrl.isEmpty }.prefix(maxBooks))
        guard !selected.isEmpty else { throw AIError.emptyReply }

        /// 模型偶尔会包一层 {"result": {...}} 或返回数组；先按原样，失败再尝试取内层对象。
        func merged(_ text: String) -> Int? {
            if let count = try? ExploreMetaStore.merge(json: text), count > 0 { return count }
            if let inner = firstJSONObject(in: text),
               let count = try? ExploreMetaStore.merge(json: inner), count > 0 { return count }
            return nil
        }

        var reply = try await client.complete(
            provider: provider, config: config, apiKey: apiKey,
            messages: [.system(systemPrompt()), .user(userPrompt(for: selected))],
            maxTokens: 1800, timeout: 90)
        if let count = merged(reply) { return count }

        // 温度偏高时模型容易写成散文：压到 0.2 再要一次 JSON。
        var strictConfig = config
        strictConfig.temperature = 0.2
        let strictSystem = systemPrompt()
            + "\n\n注意：上一次的回复不是约定的 JSON。这次只输出一个 JSON 对象，任何解释都不要写。"
        reply = try await client.complete(
            provider: provider, config: strictConfig, apiKey: apiKey,
            messages: [.system(strictSystem), .user(userPrompt(for: selected))],
            maxTokens: 2200, timeout: 90)
        if let count = merged(reply) { return count }

        let snippet = reply.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        throw AIError.decode("返回的内容不是约定的 JSON（开头：\(String(snippet.prefix(40)))）")
    }

    /// 从一段文本里截出第一个完整的 JSON 对象（处理前后多嘴的解释）。
    static func firstJSONObject(in text: String) -> String? {
        guard let start = text.firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        var index = start
        while index < text.endIndex {
            let character = text[index]
            if inString {
                if escaped { escaped = false }
                else if character == "\\" { escaped = true }
                else if character == "\"" { inString = false }
            } else {
                if character == "\"" { inString = true }
                else if character == "{" || character == "[" { depth += 1 }
                else if character == "}" || character == "]" {
                    depth -= 1
                    if depth == 0 { return String(text[start...index]) }
                }
            }
            index = text.index(after: index)
        }
        return nil
    }
}
