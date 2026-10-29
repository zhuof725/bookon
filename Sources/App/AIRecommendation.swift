import Foundation

/// 按阅读记录推荐相似小说。
///
/// 流程与书城的推荐系统同一套思路：
/// 1. 从书架（最近在读优先）提取口味关键词 —— 分类、AI 写过的标签；
/// 2. 拿这些词去各书源真实搜索，聚合去重，得到候选池；
/// 3. 把候选交给 AI 精选，并写出推荐理由（写进 ExploreMetaStore）；
/// 4. 结果直接挂在「为你推荐」板块上，下拉刷新就换一批。
enum AIRecommendation {
    static let boardID = "ai-for-you"
    static let boardTitle = "为你推荐"
    /// 一次展示多少本。
    static let targetCount = 8
    /// 交给 AI 的候选上限（控制 token，也免得模型被长列表带偏）。
    static let candidateLimit = 20

    struct Outcome {
        let books: [Book]
        let subtitle: String
    }

    enum RecommendationError: LocalizedError {
        case emptyShelf
        case noKeywords
        case noCandidates
        case badReply(String)

        var errorDescription: String? {
            switch self {
            case .emptyShelf: return "书架还是空的，先读几本再让 AI 推荐。"
            case .noKeywords: return "这些书还没有分类或标签，暂时算不出你的口味。"
            case .noCandidates: return "书源里没搜到相似的书，换个时间或换几个书源再试。"
            case let .badReply(detail): return "AI 返回的格式不对：\(detail)"
            }
        }
    }

    // MARK: - 口味

    /// 把书上的分类与标签拆成词，按出现次数排序。
    /// 分类字段常见写法：`都市`、`都市,玄幻`、`都市 | 玄幻`、`都市 玄幻`。
    static func tasteKeywords(from shelf: [Book], limit: Int = 3) -> [String] {
        var weights: [String: Int] = [:]
        let recent = shelf.sorted { $0.lastReadAt > $1.lastReadAt }.prefix(12)
        for book in recent {
            var tokens: [String] = []
            if let kind = book.kind {
                tokens += kind.split(whereSeparator: { ",，|/、 　".contains($0) }).map(String.init)
            }
            tokens += ExploreMetaStore.tags(for: book.bookUrl)
            for token in tokens {
                let value = token.trimmingCharacters(in: .whitespacesAndNewlines)
                guard value.count >= 2, value.count <= 8 else { continue }
                weights[value, default: 0] += 1
            }
        }
        return weights.sorted {
            $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value
        }.prefix(limit).map(\.key)
    }

    // MARK: - 候选池

    /// 用关键词去书源真实搜索，聚合并去重。
    static func search(keywords: [String], sources: [BookSource],
                       perKeywordSources: Int = 4, excluding: Set<String>) async -> [Book] {
        let usable = sources.filter { $0.isEnabled != false && !($0.searchUrl ?? "").isEmpty }
        guard !usable.isEmpty, !keywords.isEmpty else { return [] }

        var seen = Set<String>()
        var results: [Book] = []

        for keyword in keywords {
            let picked = Array(usable.prefix(perKeywordSources))
            await withTaskGroup(of: [Book].self) { group in
                var iterator = picked.makeIterator()
                let fanout = min(4, picked.count)
                func addNext() {
                    guard let source = iterator.next() else { return }
                    group.addTask {
                        await WebBook.searchWithTimeout(source: source, key: keyword) ?? []
                    }
                }
                for _ in 0..<fanout { addNext() }
                for await list in group {
                    for book in list {
                        guard !book.bookUrl.isEmpty, !excluding.contains(book.bookUrl) else { continue }
                        guard seen.insert(book.bookUrl).inserted else { continue }
                        results.append(book)
                    }
                    addNext()
                }
            }
        }
        return results
    }

    /// 相关度打分：书名/分类/简介里命中口味词越多越靠前；简介太短的降权。
    static func rank(_ books: [Book], keywords: [String]) -> [Book] {
        func score(_ book: Book) -> Int {
            let haystack = [book.name, book.kind ?? "", book.intro ?? "", book.author]
                .joined(separator: " ").lowercased()
            var value = 0
            for keyword in keywords where haystack.contains(keyword.lowercased()) {
                value += book.name.contains(keyword) ? 6 : 2
            }
            if (book.intro ?? "").count > 20 { value += 1 }
            if book.author.isEmpty { value -= 1 }
            return value
        }
        return books.sorted { a, b in
            let sa = score(a), sb = score(b)
            if sa != sb { return sa > sb }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    // MARK: - 提示词

    static func systemPrompt() -> String {
        """
        你是中文网络小说平台的推荐算法。根据读者的阅读记录，从候选书里挑出他/她最可能喜欢的。

        要求：
        - 优先相似题材、相近的爽点与节奏；不要选和已读完全重复的书；
        - 每本写一句推荐语：18~40 个汉字，口语化，像朋友安利；
        - 可以用「」强调关键词，不要复述简介，不要以书名开头；
        - 按推荐把握从高到低排序。

        只输出 JSON，不要代码块，不要解释：
        {"subtitle": "一句话说明这批推荐的角度", "picks": [{"index": 1, "reason": "…"}]}

        index 是候选列表里的编号，必须原样使用。
        """
    }

    static func userPrompt(shelf: [Book], keywords: [String], candidates: [Book]) -> String {
        let recent = shelf.sorted { $0.lastReadAt > $1.lastReadAt }.prefix(6).map { book -> String in
            let kind = (book.kind ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = [book.name, book.author.isEmpty ? nil : book.author,
                         kind.isEmpty ? nil : kind].compactMap { $0 }
            return parts.joined(separator: " · ")
        }
        let list = candidates.enumerated().map { index, book -> String in
            let kind = (book.kind ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let intro = (book.intro ?? "").replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespaces)
            let clipped = intro.count > 70 ? String(intro.prefix(70)) + "…" : intro
            return "\(index + 1). 书名：\(book.name) ｜作者：\(book.author.isEmpty ? "未知" : book.author)"
                + " ｜分类：\(kind.isEmpty ? "未知" : kind) ｜简介：\(clipped.isEmpty ? "无" : clipped)"
        }
        return """
        读者最近在读：
        \(recent.isEmpty ? "（空）" : recent.joined(separator: "\n"))

        口味关键词：\(keywords.joined(separator: "、"))

        候选书：
        \(list.joined(separator: "\n"))
        """
    }

    // MARK: - 生成

    static func recommend(shelf: [Book], sources: [BookSource], excluding: Set<String>,
                          provider: AIProvider, config: AIServiceConfig, apiKey: String,
                          client: AIClient = AIClient()) async throws -> Outcome {
        guard !shelf.isEmpty else { throw RecommendationError.emptyShelf }
        let keywords = tasteKeywords(from: shelf)
        guard !keywords.isEmpty else { throw RecommendationError.noKeywords }

        var pool = await search(keywords: keywords, sources: sources, excluding: excluding)
        if pool.isEmpty {
            // 「换一批」把仅有的候选都排掉了：退一步只排除书架，宁可重复也要有内容。
            let shelfOnly = Set(shelf.map(\.bookUrl))
            if excluding != shelfOnly {
                pool = await search(keywords: keywords, sources: sources, excluding: shelfOnly)
            }
        }
        // 书源里搜到的书可能还没简介：先按关键词粗排，取前 20 交给模型精挑。
        pool = Array(rank(pool, keywords: keywords).prefix(candidateLimit))
        guard !pool.isEmpty else { throw RecommendationError.noCandidates }

        let messages: [AIMessage] = [
            .system(systemPrompt()),
            .user(userPrompt(shelf: shelf, keywords: keywords, candidates: pool))
        ]
        var reply = try await client.complete(
            provider: provider, config: config, apiKey: apiKey,
            messages: messages, maxTokens: 2000, timeout: 120)

        // 模型偶尔不按 JSON 答（温度高时尤其常见）：正文里能认出书名也算数。
        var parsed = parseFlexible(reply, candidates: pool)

        if parsed == nil {
            // 再给一次机会：温度压到 0.2，明确要求只输出 JSON。
            var strictConfig = config
            strictConfig.temperature = 0.2
            let strictSystem = systemPrompt()
                + "\n\n注意：上一次的回复不是约定的 JSON。这次只输出一个 JSON 对象，任何解释都不要写。"
            reply = try await client.complete(
                provider: provider, config: strictConfig, apiKey: apiKey,
                messages: [.system(strictSystem),
                           .user(userPrompt(shelf: shelf, keywords: keywords, candidates: pool))],
                maxTokens: 2400, timeout: 120)
            parsed = parseFlexible(reply, candidates: pool)
        }

        guard let parsed else {
            let snippet = reply.replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw RecommendationError.badReply(
                "回复里既没有 JSON 也没有书名（开头：\(String(snippet.prefix(50)))）")
        }
        var books: [Book] = []
        var subtitle = parsed.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        for pick in parsed.picks {
            let position = pick.index - 1
            guard position >= 0, position < pool.count else { continue }
            let book = pool[position]
            books.append(book)
            let reason = pick.reason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !reason.isEmpty {
                ExploreMetaStore.setReason(reason, for: book.bookUrl)
            }
            if books.count >= targetCount { break }
        }
        guard !books.isEmpty else { throw RecommendationError.badReply("没有可用的 index") }
        if subtitle.isEmpty { subtitle = "根据你在读的 \(keywords.joined(separator: "、")) 挑的" }
        return Outcome(books: books, subtitle: subtitle)
    }

    // MARK: - 解析

    private struct Pick {
        let index: Int
        let reason: String?
    }

    private struct Parsed {
        let subtitle: String?
        let picks: [Pick]
    }

    private static func parse(_ text: String) throws -> Parsed {
        guard let json = firstJSONObject(in: text) ?? (text.hasPrefix("{") ? text : nil),
              let data = json.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw RecommendationError.badReply("没有找到 JSON")
        }
        var picks: [Pick] = []
        if let raw = root["picks"] as? [[String: Any]] {
            for item in raw {
                let index: Int?
                if let value = item["index"] as? Int { index = value }
                else if let value = item["index"] as? String { index = Int(value) }
                else { index = nil }
                guard let index else { continue }
                picks.append(Pick(index: index, reason: item["reason"] as? String))
            }
        } else if let raw = root["picks"] as? [Int] {
            picks = raw.map { Pick(index: $0, reason: nil) }
        }
        guard !picks.isEmpty else { throw RecommendationError.badReply("缺少 picks") }
        return Parsed(subtitle: root["subtitle"] as? String, picks: picks)
    }

    /// 先按 JSON 解析；不行再从正文里认候选书名。
    private static func parseFlexible(_ text: String, candidates: [Book]) -> Parsed? {
        if let parsed = try? parse(text), !parsed.picks.isEmpty { return parsed }
        let loose = AILooseSuggestions.parse(text: text, names: candidates.map(\.name),
                                             limit: targetCount)
        guard !loose.isEmpty else { return nil }
        return Parsed(subtitle: nil,
                      picks: loose.map { Pick(index: $0.index + 1, reason: $0.reason) })
    }

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
