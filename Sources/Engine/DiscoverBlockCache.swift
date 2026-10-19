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

    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LegadoReading", isDirectory: true)
            .appendingPathComponent(directoryName, isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private static func fileURL(source: String, url: String) -> URL {
        let key = "\(source)|\(url)"
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in key.utf8 {
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
        let file = fileURL(source: source, url: url)
        guard let data = try? Data(contentsOf: file),
              let entry = try? JSONDecoder().decode(Entry.self, from: data) else { return nil }
        let ttl = TimeInterval(days) * 86400
        guard now.timeIntervalSince(entry.storedAt) < ttl else { return nil }
        return entry.books
    }

    static func store(source: String, url: String, books: [Book], at date: Date = Date()) {
        let entry = Entry(storedAt: date, books: books)
        guard let data = try? JSONEncoder().encode(entry) else { return }
        try? data.write(to: fileURL(source: source, url: url), options: .atomic)
    }

    /// 清除缓存（clear(source:) 只清该书源；nil 清全部）。
    static func clear(source: String? = nil) {
        guard let source else {
            try? FileManager.default.removeItem(at: directory)
            return
        }
        // 无法从哈希反推来源，只能按文件名清空全部：源切换不频繁，代价可接受。
        // 这里保留 source 参数以便未来改为目录分区；当前实现直接清全部。
        _ = source
        try? FileManager.default.removeItem(at: directory)
    }
}
