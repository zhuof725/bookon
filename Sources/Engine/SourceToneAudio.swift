import Foundation
import CryptoKit

/// 用书源自己的音频接口听书（番茄系的 `tone_id` 音色）。
///
/// 番茄源在「听书模式」下请求 `/api/content?item_ids=<章节>&tone_id=N&ts=听书`
/// 得到音频地址。这里**不改书源的全局模式**：按「每本书」记住选中的音色，
/// 取这一章的音频时直接走同一个接口（服务端按 tone_id 合成），
/// 所以切音色只影响这本书，其他书照旧按书源默认模式阅读。
enum SourceToneAudio {
    private static let storagePrefix = "reader.sourceTone.v1."

    struct Config: Codable, Equatable {
        var sourceUrl: String
        /// `tone_id=1` 这种查询片段。
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

    /// 当前章的书源音频地址；这本书没开音色、或接口没返回可播地址时返回 nil。
    static func audioURL(source: BookSource, chapter: BookChapter, bookUrl: String) async -> String? {
        guard let config = config(bookUrl: bookUrl),
              config.sourceUrl == source.bookSourceUrl else { return nil }
        guard let itemID = queryValue(chapter.url, "q"), !itemID.isEmpty else { return nil }
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
        let rawTone = config.tone.trimmingCharacters(in: .whitespacesAndNewlines)
        let tone: String
        if rawTone.isEmpty {
            tone = "tone_id=0"
        } else if rawTone.contains("=") {
            tone = rawTone
        } else {
            // 声明式音色表里存的是裸 id（"1"），番茄接口要 tone_id=1。
            tone = "tone_id=" + rawTone
        }
        for pair in tone.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard let name = parts.first else { continue }
            let value = parts.count > 1 ? String(parts[1]) : ""
            items.append(URLQueryItem(name: String(name), value: value))
        }
        if let key = configValue(source, "api_key"), !key.isEmpty {
            items.append(URLQueryItem(name: "api_key", value: key))
        }
        components.queryItems = items
        guard let url = components.url else { return nil }
        return await fetchAudioURL(url)
    }

    private static func fetchAudioURL(_ url: URL) async -> String? {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            let payload = (root["data"] as? [String: Any]) ?? root
            if let raw = payload["raw_url"] as? String, raw.hasPrefix("http") { return raw }
            if let backups = payload["backup_url"] as? [String],
               let first = backups.first, first.hasPrefix("http") { return first }
            if let content = payload["content"] as? String, content.hasPrefix("http") { return content }
            return nil
        } catch {
            return nil
        }
    }

    // MARK: 书源配置

    /// 源变量里的 server（多线路时是当前线路）；没有就用书源地址本身。
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
        let digest = SHA256.hash(data: Data(bookUrl.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return storagePrefix + digest
    }
}
