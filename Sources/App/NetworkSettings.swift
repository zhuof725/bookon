import Foundation
import CryptoKit

/// 网络设置：搜索/封面/缓存的并发与开关。
enum NetworkSettings {
    private static let concurrencyKey = "network.concurrency.v1"
    private static let coverKey = "network.coverConcurrency.v1"
    private static let cacheDaysKey = "network.searchCacheDays.v1"
    private static let loadTocKey = "network.loadTocOnSwitch.v1"

    static let concurrencyRange = 1...32
    static let coverOptions = [0, 2, 4, 6, 8, 12]
    static let cacheDaysRange = 0...30

    /// 搜索/缓存/下载等请求的并发数（默认 16）。
    static var concurrency: Int {
        get {
            let value = UserDefaults.standard.integer(forKey: concurrencyKey)
            guard value != 0 else { return 16 }
            return min(max(value, concurrencyRange.lowerBound), concurrencyRange.upperBound)
        }
        set {
            let clamped = min(max(newValue, concurrencyRange.lowerBound), concurrencyRange.upperBound)
            UserDefaults.standard.set(clamped, forKey: concurrencyKey)
        }
    }

    /// 封面同时下载数；0 = 不限制（内部按 64 兜底）。
    static var coverConcurrency: Int {
        get {
            let value = UserDefaults.standard.integer(forKey: coverKey)
            return coverOptions.contains(value) ? value : 0
        }
        set {
            UserDefaults.standard.set(coverOptions.contains(newValue) ? newValue : 0, forKey: coverKey)
        }
    }

    /// 搜索结果缓存天数；0 = 不缓存。
    static var searchCacheDays: Int {
        get {
            let value = UserDefaults.standard.integer(forKey: cacheDaysKey)
            guard value != 0 else { return 5 }
            return min(max(value, cacheDaysRange.lowerBound), cacheDaysRange.upperBound)
        }
        set {
            let clamped = min(max(newValue, cacheDaysRange.lowerBound), cacheDaysRange.upperBound)
            UserDefaults.standard.set(clamped, forKey: cacheDaysKey)
        }
    }

    /// 换源时顺便加载各候选源的目录（请求会翻倍）。
    static var loadTocOnSourceSwitch: Bool {
        get { UserDefaults.standard.bool(forKey: loadTocKey) }
        set { UserDefaults.standard.set(newValue, forKey: loadTocKey) }
    }

    /// 交给封面闸门的并发上限。
    static var coverGateLimit: Int {
        coverConcurrency == 0 ? 64 : coverConcurrency
    }

    /// 搜索/换源的实际并发：原版是线程池 min(threadCount, MAX_THREAD=9)，
    /// 再多也会被 9 个线程卡住，这里直接按 9 封顶。
    static var searchFanout: Int {
        min(max(concurrency, 1), 9)
    }

    /// 把封面并发应用到全局闸门（启动与改设置时调用）。
    static func applyCoverLimit() {
        let limit = coverGateLimit
        Task { await CoverLoadGate.shared.updateLimit(limit) }
    }
}

/// 搜索结果缓存：按「书源 + 关键词」存，过期天数取网络设置。
enum SearchResultCache {
    private struct Entry: Codable {
        let savedAt: Date
        let books: [Book]
    }

    static func cached(source: String, key: String) -> [Book]? {
        let days = NetworkSettings.searchCacheDays
        guard days > 0 else { return nil }
        guard let data = try? Data(contentsOf: fileURL(source: source, key: key)),
              let entry = try? JSONDecoder().decode(Entry.self, from: data) else { return nil }
        let age = Date().timeIntervalSince(entry.savedAt)
        guard age >= 0, age <= Double(days) * 86400 else { return nil }
        return entry.books
    }

    static func store(_ books: [Book], source: String, key: String) {
        guard NetworkSettings.searchCacheDays > 0, !books.isEmpty else { return }
        let entry = Entry(savedAt: Date(), books: books)
        guard let data = try? JSONEncoder().encode(entry) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: fileURL(source: source, key: key))
    }

    static func clear() {
        try? FileManager.default.removeItem(at: directory)
    }

    static var diskBytes: Int {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory,
                                                                      includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return files.reduce(0) { total, url in
            total + ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    private static var directory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("SearchResults", isDirectory: true)
    }

    private static func fileURL(source: String, key: String) -> URL {
        let raw = source + "\u{1F}" + key.lowercased()
        let digest = SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(digest + ".json")
    }
}
