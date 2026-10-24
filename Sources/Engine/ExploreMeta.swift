import Foundation

/// 一本书在探索页里的扩展信息：标签与推荐理由。
///
/// 应用自己不算这些内容——标签（"求生游戏"）和推荐语（"这本「都市」佳作……"）
/// 预留给外部写入（AI / 手动 / 导入 JSON）。没有写入时按空处理，
/// 卡片只显示书源本身已有的书名、简介、分类与字数。
struct ExploreBookMeta: Codable, Hashable {
    var tags: [String]
    var reason: String
    var updatedAt: Date

    init(tags: [String] = [], reason: String = "", updatedAt: Date = Date()) {
        self.tags = tags
        self.reason = reason
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey { case tags, reason, updatedAt }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tags = (try? c.decode([String].self, forKey: .tags)) ?? []
        reason = (try? c.decode(String.self, forKey: .reason)) ?? ""
        updatedAt = (try? c.decode(Date.self, forKey: .updatedAt)) ?? Date()
    }

    var isEmpty: Bool { tags.isEmpty && reason.isEmpty }
}

/// `merge(json:)` 接受的一条结构：标签和推荐语都可省略。
private struct ExploreMetaJSONEntry: Codable {
    var tags: [String]?
    var reason: String?
}

/// 探索扩展信息的本机存储。
///
/// 文件：`Application Support/LegadoReading/explore-meta.json`
/// 结构：`{ "<bookUrl>": { "tags": ["…"], "reason": "…", "updatedAt": "…" } }`
///
/// 外部写入方式（二选一）：
/// 1. 直接调用 `setTags` / `setReason` / `setMeta`；
/// 2. 把一整段 JSON 交给 `merge(json:)`（AI 批处理接口可直接返回这个结构）。
enum ExploreMetaStore {
    static let fileName = "explore-meta.json"

    private static let lock = NSLock()
    private nonisolated(unsafe) static var cache: [String: ExploreBookMeta]?

    static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let directory = base.appendingPathComponent("LegadoReading", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(fileName)
    }

    static func meta(for bookURL: String) -> ExploreBookMeta? {
        let key = bookURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        lock.lock(); defer { lock.unlock() }
        return loadedLocked()[key]
    }

    static func tags(for bookURL: String) -> [String] {
        meta(for: bookURL)?.tags ?? []
    }

    static func reason(for bookURL: String) -> String? {
        let value = meta(for: bookURL)?.reason.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }

    static func all() -> [String: ExploreBookMeta] {
        lock.lock(); defer { lock.unlock() }
        return loadedLocked()
    }

    static func setMeta(_ meta: ExploreBookMeta, for bookURL: String) {
        let key = bookURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        lock.lock()
        var map = loadedLocked()
        map[key] = meta
        persistLocked(map)
        lock.unlock()
    }

    static func setTags(_ tags: [String], for bookURL: String) {
        update(bookURL) { meta in
            meta.tags = tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
    }

    static func setReason(_ reason: String, for bookURL: String) {
        update(bookURL) { meta in
            meta.reason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    static func remove(for bookURL: String) {
        let key = bookURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        lock.lock()
        var map = loadedLocked()
        map.removeValue(forKey: key)
        persistLocked(map)
        lock.unlock()
    }

    /// 批量合并外部 JSON，返回写入的条目数。
    /// 接受 `{ "<bookUrl>": { "tags": [...], "reason": "..." } }`，
    /// 也接受 `{ "<bookUrl>": ["标签1","标签2"] }`（只写标签）。
    @discardableResult
    static func merge(json: String) throws -> Int {
        guard let data = json.data(using: .utf8) else {
            throw ExploreMetaError.invalidJSON
        }
        let decoder = JSONDecoder()
        if let map = try? decoder.decode([String: RawMeta].self, from: data) {
            lock.lock()
            var store = loadedLocked()
            for (bookURL, raw) in map {
                let key = bookURL.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !key.isEmpty else { continue }
                var meta = store[key] ?? ExploreBookMeta()
                if let tags = raw.tags {
                    meta.tags = tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                }
                if let reason = raw.reason {
                    meta.reason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                meta.updatedAt = Date()
                store[key] = meta
            }
            persistLocked(store)
            lock.unlock()
            return map.count
        }
        if let map = try? decoder.decode([String: [String]].self, from: data) {
            lock.lock()
            var store = loadedLocked()
            for (bookURL, tags) in map {
                let key = bookURL.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !key.isEmpty else { continue }
                var meta = store[key] ?? ExploreBookMeta()
                meta.tags = tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                meta.updatedAt = Date()
                store[key] = meta
            }
            persistLocked(store)
            lock.unlock()
            return map.count
        }
        throw ExploreMetaError.invalidJSON
    }

    static func clear() {
        lock.lock()
        cache = [:]
        try? FileManager.default.removeItem(at: fileURL)
        lock.unlock()
    }

    // MARK: - 内部

    private static func update(_ bookURL: String, _ body: (inout ExploreBookMeta) -> Void) {
        let key = bookURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        lock.lock()
        var map = loadedLocked()
        var meta = map[key] ?? ExploreBookMeta()
        body(&meta)
        meta.updatedAt = Date()
        if meta.isEmpty {
            map.removeValue(forKey: key)
        } else {
            map[key] = meta
        }
        persistLocked(map)
        lock.unlock()
    }

    /// 调用方必须已持锁。
    private static func loadedLocked() -> [String: ExploreBookMeta] {
        if let cache { return cache }
        let map: [String: ExploreBookMeta]
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([String: ExploreBookMeta].self, from: data) {
            map = decoded
        } else {
            map = [:]
        }
        cache = map
        return map
    }

    /// 调用方必须已持锁。
    private static func persistLocked(_ map: [String: ExploreBookMeta]) {
        cache = map
        guard let data = try? JSONEncoder().encode(map) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

enum ExploreMetaError: LocalizedError {
    case invalidJSON

    var errorDescription: String? {
        switch self {
        case .invalidJSON: return "JSON 格式不正确"
        }
    }
}

/// 推荐理由里的引号片段高亮用：「…」或 “…” 里的词在卡片上换色显示。
enum ExploreReasonFormat {
    struct Segment: Equatable {
        var text: String
        var highlighted: Bool
    }

    /// 把 "这本“都市”佳作与你的匹配度高达87%！" 拆成普通/高亮片段。
    static func segments(_ reason: String) -> [Segment] {
        let pairs: [(open: Character, close: Character)] = [("“", "”"), ("「", "」"), ("『", "』")]
        var result: [Segment] = []
        var buffer = ""
        var highlight: Character? = nil
        for character in reason {
            if let close = highlight {
                buffer.append(character)
                if character == close {
                    if !buffer.isEmpty { result.append(Segment(text: buffer, highlighted: true)) }
                    buffer = ""
                    highlight = nil
                }
                continue
            }
            if let pair = pairs.first(where: { $0.open == character }) {
                if !buffer.isEmpty { result.append(Segment(text: buffer, highlighted: false)) }
                buffer = String(character)
                highlight = pair.close
                continue
            }
            buffer.append(character)
        }
        if !buffer.isEmpty {
            result.append(Segment(text: buffer, highlighted: highlight != nil))
        }
        return result
    }
}
