import Foundation

/// 让 AI 根据书架口味，从已导入书源的发现分类里挑几个，组成「AI 推荐」板块。
enum AIExplorePicks {
    /// 固定 id：整个探索页只保留一个 AI 推荐板块，重新生成时原地替换。
    static let boardID = "ai-explore-picks"
    static let defaultTitle = "AI 推荐"

    struct Candidate {
        let category: ExploreCategory
        let sourceName: String
    }

    enum PicksError: LocalizedError {
        case noSources
        case noCategories
        case badReply(String)

        var errorDescription: String? {
            switch self {
            case .noSources: return "还没有可探索的书源。先导入带发现页的书源。"
            case .noCategories: return "没能从书源里读到分类。去「探索 → 添加板块」看看哪个源能拉到分类。"
            case let .badReply(detail): return "AI 返回的格式不对：\(detail)"
            }
        }
    }

    // MARK: 候选池

    /// 书源的发现分类。优先用缓存，缺的现场拉几个（源多时不能让用户等太久）。
    static func candidates(sources: [BookSource], liveLimit: Int = 3, perSourceLimit: Int = 8,
                           totalLimit: Int = 60) async -> [Candidate] {
        let explorable = DiscoverCatalog.explorableSources(sources)
        guard !explorable.isEmpty else { return [] }

        var pool: [Candidate] = []
        var missing: [BookSource] = []

        func append(_ kinds: [SourceDiagnostics.ExploreKind], from source: BookSource) {
            var added = 0
            for kind in kinds {
                guard added < perSourceLimit else { break }
                // 控件（text/button/select）是筛选条，没有地址的是分节标题，都不是分类。
                guard (kind.type ?? "").isEmpty else { continue }
                guard let url = kind.url?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty else { continue }
                let title = kind.title.trimmingCharacters(in: .whitespacesAndNewlines)
                pool.append(Candidate(
                    category: ExploreCategory(sourceURL: source.bookSourceUrl,
                                              url: url,
                                              title: title.isEmpty ? "分类" : title),
                    sourceName: source.bookSourceName))
                added += 1
            }
        }

        for source in explorable {
            if let cached = DiscoverKindsCache.cached(source: source.bookSourceUrl), !cached.isEmpty {
                append(cached, from: source)
            } else {
                missing.append(source)
            }
        }

        for source in missing.prefix(liveLimit) where pool.count < totalLimit {
            let kinds = await Task.detached(priority: .utility) {
                SourceDiagnostics.exploreKinds(source: source)
            }.value
            if !kinds.isEmpty {
                DiscoverKindsCache.store(source: source.bookSourceUrl, kinds: kinds)
                append(kinds, from: source)
            }
        }

        return Array(pool.prefix(totalLimit))
    }

    // MARK: 提示词

    static func systemPrompt() -> String {
        """
        你是中文网络小说平台的老编辑，熟悉各类题材和读者口味。

        任务：根据这位读者的书架，从给定的「书源 · 分类」列表里挑 3 个最值得他现在去看的分类，
        并为整个推荐板块起一个标题和一句介绍。

        要求：
        - 优先贴近他最近读的类型，也可以有一个"换个口味但不相远"的选择；
        - 标题 4~6 个汉字，不要用"AI""智能"这类词；
        - 介绍一句话，20~40 字，说明为什么这批值得看；
        - 只输出 JSON，不要代码块，不要解释。

        格式：
        {"title": "…", "subtitle": "…", "picks": [{"index": 1, "reason": "…"}]}

        index 是下面列表里的序号，必须原样使用。
        """
    }

    static func userPrompt(shelf: [Book], candidates: [Candidate]) -> String {
        let recent = shelf
            .sorted { $0.lastReadAt > $1.lastReadAt }
            .prefix(8)
            .map { book -> String in
                let tags = ExploreMetaStore.tags(for: book.bookUrl).joined(separator: "/")
                let kind = (book.kind ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let pieces = [book.name, book.author.isEmpty ? "未知作者" : book.author,
                              kind.isEmpty ? nil : kind, tags.isEmpty ? nil : tags]
                return pieces.compactMap { $0 }.joined(separator: " · ")
            }
        let shelfText = recent.isEmpty ? "（书架还是空的，按大众口味挑热门分类）" : recent.joined(separator: "\n")

        let list = candidates.enumerated().map { index, candidate in
            "\(index + 1). \(candidate.sourceName) · \(candidate.category.title)"
        }.joined(separator: "\n")

        return """
        读者最近在读：
        \(shelfText)

        可选分类：
        \(list)
        """
    }

    // MARK: 生成

    @discardableResult
    static func generate(sources: [BookSource], shelf: [Book], provider: AIProvider,
                         config: AIServiceConfig, apiKey: String,
                         client: AIClient = AIClient()) async throws -> ExploreBoard {
        guard !DiscoverCatalog.explorableSources(sources).isEmpty else { throw PicksError.noSources }
        let pool = await candidates(sources: sources)
        guard !pool.isEmpty else { throw PicksError.noCategories }

        let reply = try await client.complete(
            provider: provider, config: config, apiKey: apiKey,
            messages: [.system(systemPrompt()), .user(userPrompt(shelf: shelf, candidates: pool))],
            maxTokens: 800, timeout: 90)

        let output = try decode(reply)
        let picked = output.indices.compactMap { index -> ExploreCategory? in
            let position = index - 1
            guard position >= 0, position < pool.count else { return nil }
            return pool[position].category
        }
        guard !picked.isEmpty else { throw PicksError.badReply("没有可用的 index") }

        let title = output.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        return ExploreBoard(
            id: boardID,
            title: (title?.isEmpty == false ? title! : defaultTitle),
            subtitle: output.subtitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            layout: .categoryFeed,
            categories: picked,
            count: 6)
    }

    // MARK: 解析

    private struct Output {
        var title: String?
        var subtitle: String?
        var indices: [Int]
    }

    private static func decode(_ text: String) throws -> Output {
        guard let json = firstJSONObject(in: text) ?? (text.hasPrefix("{") ? text : nil),
              let data = json.data(using: .utf8) else {
            throw PicksError.badReply("没有找到 JSON")
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw PicksError.badReply("JSON 无法解析")
        }
        let title = root["title"] as? String
        let subtitle = root["subtitle"] as? String
        var indices: [Int] = []

        if let picks = root["picks"] as? [[String: Any]] {
            for pick in picks {
                if let value = pick["index"] as? Int { indices.append(value) }
                else if let value = pick["index"] as? String, let parsed = Int(value) { indices.append(parsed) }
            }
        } else if let picks = root["picks"] as? [Int] {
            indices = picks
        } else if let picks = root["categories"] as? [Int] {
            indices = picks
        }

        guard !indices.isEmpty else { throw PicksError.badReply("缺少 picks") }
        return Output(title: title, subtitle: subtitle, indices: indices)
    }

    /// 从一段文本里截出第一个完整的 JSON 对象（模型常常前后多说一句）。
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
