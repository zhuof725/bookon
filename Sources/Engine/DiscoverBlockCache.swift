import Foundation

/// 发现板块书单缓存：缓存期内进出发现页直接用本地数据，下拉刷新强制拉新。
/// 存 Application Support/LegadoReading/discover-blocks/<hash>.json。
enum DiscoverBlockCache {
    private static let directoryName = "discover-blocks"

    /// 缓存有效期（天）：读取设置，钳制到 1...365。
    static var days: Int {
        let stored = UserDefaults.standard.object(forKey: DiscoverSettings.cacheDaysKey) as? Int
        let value = stored ?? DiscoverSettings.defaultCacheDays
        return min(max(value, 1), 365)
    }

    /// 缓存目录（创建失败返回 nil，缓存自动降级）。
    static var directory: URL? {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LegadoReading", isDirectory: true)
            .appendingPathComponent(directoryName, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            return base
        } catch {
            return nil
        }
    }

    static func fileURL(source: String, url: String) -> URL? {
        guard let directory else { return nil }
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in "\(source)|\(url)".utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x100000001b3
        }
        return directory.appendingPathComponent(String(hash, radix: 16) + ".json")
    }

    private struct Entry: Codable {
        var storedAt: Date
        var books: [Book]
    }

    /// 新鲜缓存（未过期）才返回。
    static func cached(source: String, url: String, now: Date = Date()) -> [Book]? {
        guard let file = fileURL(source: source, url: url),
              let data = try? Data(contentsOf: file),
              let entry = try? JSONDecoder().decode(Entry.self, from: data) else { return nil }
        let ttl = TimeInterval(days) * 86400
        guard now.timeIntervalSince(entry.storedAt) < ttl else { return nil }
        return entry.books
    }

    static func store(source: String, url: String, books: [Book], at date: Date = Date()) {
        guard let file = fileURL(source: source, url: url) else { return }
        let entry = Entry(storedAt: date, books: books)
        guard let data = try? JSONEncoder().encode(entry) else { return }
        try? data.write(to: file, options: .atomic)
    }

    /// 清除缓存（当前按目录整体清除；source 参数保留以便后续细分）。
    static func clear(source: String? = nil) {
        _ = source
        guard let directory else { return }
        try? FileManager.default.removeItem(at: directory)
    }
}

/// 发现分类缓存：缓存期内直接使用本地数据，不重新执行发现脚本；下拉刷新强制刷新。
enum DiscoverKindsCache {
    private static let directoryName = "discover-kinds"

    private static var directory: URL? {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LegadoReading", isDirectory: true)
            .appendingPathComponent(directoryName, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            return base
        } catch {
            return nil
        }
    }

    static func fileURL(source: String) -> URL? {
        guard let directory else { return nil }
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in source.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x100000001b3
        }
        return directory.appendingPathComponent(String(hash, radix: 16) + ".json")
    }

    private struct Entry: Codable {
        var storedAt: Date
        var kinds: [SourceDiagnostics.ExploreKind]
    }

    static func cached(source: String, now: Date = Date()) -> [SourceDiagnostics.ExploreKind]? {
        guard let file = fileURL(source: source),
              let data = try? Data(contentsOf: file),
              let entry = try? JSONDecoder().decode(Entry.self, from: data) else { return nil }
        let ttl = TimeInterval(DiscoverBlockCache.days) * 86400
        guard now.timeIntervalSince(entry.storedAt) < ttl else { return nil }
        return entry.kinds
    }

    static func store(source: String, kinds: [SourceDiagnostics.ExploreKind], at date: Date = Date()) {
        guard let file = fileURL(source: source) else { return }
        let entry = Entry(storedAt: date, kinds: kinds)
        guard let data = try? JSONEncoder().encode(entry) else { return }
        try? data.write(to: file, options: .atomic)
    }

    static func clear() {
        guard let directory else { return }
        try? FileManager.default.removeItem(at: directory)
    }
}
