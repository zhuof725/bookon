import Foundation
import CryptoKit

/// 用书源自己的「音频模式」取章节音频（番茄系的 tone_id 音色）。
///
/// 思路：不改书源的全局模式，只把这**一个章节地址**里的文字模式标记改写成音频模式，
/// 再交给书源自己的正文规则去算地址：
/// - 番茄源：`ys_module=3`（小说） → `ys_module=2`（听书），规则会请求
///   `/api/content?item_ids=…&tone_id=…&ts=听书`，音色就是源变量里的 `tone`。
/// - 聚合源（书山聚合这类）：章节地址里的 `source=番茄小说` → `source=番茄听书`，
///   规则里对应的音频分支会用它自己的 `getTtsTone('fanqie')`。
///
/// 音色可用性用同一个内容接口探测（只取 JSON，不下载音频），按书缓存。
enum SourceToneAudio {
    private static let storagePrefix = "reader.sourceTone.v1."
    private static let availabilityPrefix = "reader.toneAvailability.v1."

    /// 正文照常显示、音频在后台播（不切到有声书界面）。
    static let backgroundKey = "reader.sourceTone.background.v1"

    static var backgroundPlayback: Bool {
        get { UserDefaults.standard.bool(forKey: backgroundKey) }
        set { UserDefaults.standard.set(newValue, forKey: backgroundKey) }
    }

    struct Config: Codable, Equatable {
        var sourceUrl: String
        /// `tone_id=1` 这种查询片段（也兼容裸 id）。
        var tone: String
        var toneName: String
    }

    // MARK: 每本书的音色

    static func config(bookUrl: String) -> Config? {
        guard let data = UserDefaults.standard.data(forKey: storageKey(bookUrl)),
              let config = try? JSONDecoder().decode(Config.self, from: data) else { return nil }
        return config
    }

    static func isActive(bookUrl: String) -> Bool { config(bookUrl: bookUrl) != nil }

    static func activate(bookUrl: String, sourceUrl: String, tone: String, toneName: String) {
        let config = Config(sourceUrl: sourceUrl, tone: tone, toneName: toneName)
        guard let data = try? JSONEncoder().encode(config) else { return }
        UserDefaults.standard.set(data, forKey: storageKey(bookUrl))
    }

    static func deactivate(bookUrl: String) {
        UserDefaults.standard.removeObject(forKey: storageKey(bookUrl))
    }

    // MARK: 取音频地址

    /// 这一章在「音频模式」下的地址：把章节链接里的文字模式标记换掉。
    /// 没有任何可改写的标记时返回 nil（说明这个源没有音频变体）。
    static func audioVariant(of chapter: BookChapter) -> BookChapter? {
        if let dataVariant = dataChapterAudioVariant(of: chapter) { return dataVariant }
        var url = chapter.url
        var changed = false
        for pair in [("ys_module=3", "ys_module=2"), ("ys_module=13", "ys_module=2")] {
            if url.contains(pair.0) {
                url = url.replacingOccurrences(of: pair.0, with: pair.1)
                changed = true
            }
        }
        for textMode in ["番茄小说", "番茄短剧"] {
            let encoded = textMode.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? textMode
            let audioMode = "番茄听书"
            let encodedAudio = audioMode.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? audioMode
            if url.contains(encoded) {
                url = url.replacingOccurrences(of: encoded, with: encodedAudio)
                changed = true
            } else if url.contains(textMode) {
                url = url.replacingOccurrences(of: textMode, with: audioMode)
                changed = true
            }
        }
        guard changed else { return nil }
        return BookChapter(url: url, title: chapter.title, index: chapter.index,
                           isVolume: chapter.isVolume, updateTime: chapter.updateTime,
                           isVip: chapter.isVip)
    }

    /// 聚合源（书山聚合这类）的章节地址是 `data:chapterUrl;base64,<参数 JSON>,{…}`，
    /// 把里面的 `source: 番茄小说` 改成 `番茄听书` 就会走它的音频分支。
    private static func dataChapterAudioVariant(of chapter: BookChapter) -> BookChapter? {
        let prefix = "data:chapterUrl;base64,"
        let url = chapter.url
        guard url.hasPrefix(prefix) else { return nil }
        let rest = String(url.dropFirst(prefix.count))
        let parts = rest.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
        guard let encoded = parts.first,
              let data = Data(base64Encoded: String(encoded)),
              var dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        let source = (dict["source"] as? String) ?? ""
        guard ["番茄小说", "番茄短剧", "番茄畅听", "番茄听书"].contains(source) else { return nil }
        if source == "番茄小说" || source == "番茄短剧" { dict["source"] = "番茄听书" }
        guard dict["source"] as? String != source,
              JSONSerialization.isValidJSONObject(dict),
              let newData = try? JSONSerialization.data(withJSONObject: dict) else { return nil }
        let rebuilt = prefix + newData.base64EncodedString()
            + (parts.count > 1 ? "," + String(parts[1]) : "")
        return BookChapter(url: rebuilt, title: chapter.title, index: chapter.index,
                           isVolume: chapter.isVolume, updateTime: chapter.updateTime,
                           isVip: chapter.isVip)
    }

    /// 能不能用 `/api/content` 探测音色可用性：只有书源地址本身就是番茄系 API 主机才行，
    /// 聚合源的 bookSourceUrl 不是接口地址，探测会全是失败。
    static func canProbe(source: BookSource) -> Bool {
        guard let url = URL(string: source.bookSourceUrl),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return false
        }
        return (source.jsLib ?? "").contains("_getTones")
    }

    /// 让书源用自己的正文规则算这一章的音频地址（含当前音色）。
    static func audioURL(source: BookSource, book: Book, chapter: BookChapter) async -> String? {
        guard let variant = audioVariant(of: chapter) else { return nil }
        guard let raw = try? await WebBook.rawContentWithBookInfoHealing(
            source: source, book: book, chapter: variant,
            fallbackToAutoDetect: false, followNextPage: false, normalizeText: false),
              !raw.isEmpty else { return nil }
        return AudioChapter.playURLs(fromContent: raw).first
    }

    // MARK: 音色可用性（按书缓存）

    static func cachedAvailability(bookUrl: String, tone: String) -> Bool? {
        let map = availabilityMap(bookUrl: bookUrl)
        guard let value = map[tone] else { return nil }
        return value
    }

    static func clearAvailability(bookUrl: String) {
        UserDefaults.standard.removeObject(forKey: availabilityKey(bookUrl))
    }

    static func storeAvailability(_ available: Bool, bookUrl: String, tone: String) {
        var map = availabilityMap(bookUrl: bookUrl)
        map[tone] = available
        UserDefaults.standard.set(map, forKey: availabilityKey(bookUrl))
    }

    private static func availabilityMap(bookUrl: String) -> [String: Bool] {
        UserDefaults.standard.dictionary(forKey: availabilityKey(bookUrl)) as? [String: Bool] ?? [:]
    }

    /// 探测一个音色：直接问书源的内容接口（只要 JSON，不下载音频）。
    static func probe(tone: String, source: BookSource, chapter: BookChapter) async -> Bool {
        guard let itemID = queryValue(chapter.url, "q") ?? queryValue(chapter.url, "item_id"),
              !itemID.isEmpty else { return false }
        guard let url = contentAPIURL(source: source, itemID: itemID, tone: tone) else { return false }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return false
            }
            let code = (root["code"] as? NSNumber)?.intValue ?? 0
            guard code == 0 else { return false }
            let payload = (root["data"] as? [String: Any]) ?? root
            if let raw = payload["raw_url"] as? String, raw.hasPrefix("http") { return true }
            if let backups = payload["backup_url"] as? [String],
               let first = backups.first, first.hasPrefix("http") { return true }
            if let content = payload["content"] as? String, content.hasPrefix("http") { return true }
            return false
        } catch {
            return false
        }
    }

    /// 用书源自己的规则探测音色（书山这类聚合源没有番茄的 /api/content 接口）：
    /// 临时把音色写进源变量，按音频模式取一次本章地址，再恢复原值。
    static func probeViaRule(tone: SourceTone.Item, group: SourceTone.Group,
                             source: BookSource, book: Book, chapter: BookChapter) async -> Bool {
        let original = SourceTone.currentValue(group: group, source: source)
        SourceTone.setValue(tone.value, group: group, source: source)
        defer { SourceTone.setValue(original, group: group, source: source) }
        return await audioURL(source: source, book: book, chapter: chapter) != nil
    }

    // MARK: 接口地址

    private static func contentAPIURL(source: BookSource, itemID: String, tone: String) -> URL? {
        let host = serverHost(source) ?? source.bookSourceUrl
        guard var components = URLComponents(string: host.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + (basePath.isEmpty ? "" : basePath + "/") + "api/content"
        var items = [
            URLQueryItem(name: "item_ids", value: itemID),
            URLQueryItem(name: "ts", value: "听书"),
        ]
        let rawTone = tone.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = rawTone.isEmpty ? "tone_id=0" : (rawTone.contains("=") ? rawTone : "tone_id=" + rawTone)
        for pair in normalized.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard let name = parts.first else { continue }
            items.append(URLQueryItem(name: String(name), value: parts.count > 1 ? String(parts[1]) : ""))
        }
        if let key = configValue(source, "api_key"), !key.isEmpty {
            items.append(URLQueryItem(name: "api_key", value: key))
        }
        components.queryItems = items
        return components.url
    }

    private static func serverHost(_ source: BookSource) -> String? {
        for key in ["server", "host"] {
            if let value = configValue(source, key)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func configValue(_ source: BookSource, _ key: String) -> String? {
        guard let data = SourceVariable.get(source.bookSourceUrl).data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        let dict: [String: Any]
        if let obj = object as? [String: Any] {
            dict = obj
        } else if let list = object as? [[String: Any]], let first = list.first {
            dict = first
        } else {
            return nil
        }
        switch dict[key] {
        case let value as String: return value
        case let number as NSNumber: return number.stringValue
        default: return nil
        }
    }

    private static func queryValue(_ raw: String, _ name: String) -> String? {
        guard let items = URLComponents(string: raw)?.queryItems else { return nil }
        return items.first { $0.name == name }?.value
    }

    private static func storageKey(_ bookUrl: String) -> String {
        storagePrefix + digest(bookUrl)
    }

    private static func availabilityKey(_ bookUrl: String) -> String {
        availabilityPrefix + digest(bookUrl)
    }

    private static func digest(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
