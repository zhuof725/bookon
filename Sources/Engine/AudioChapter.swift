import Foundation

/// 音频章节的纯逻辑部分（不依赖网络/书源）：直链判断、地址解析、目录重定位。
/// 网络相关的取地址实现留在 AudioBook.swift 的 extension 里，
/// 这样只需要 BookKind 的测试工程不必引入整个 WebBook 依赖链。
enum AudioChapter {
    /// 常见音频文件扩展名（小写、不含点）。
    static let audioExtensions: Set<String> = ["mp3", "m4a", "aac", "wav", "flac", "ogg", "m4b", "opus", "wma", "amr"]

    /// 章节是否为音频：书源类型是音频（1），或章节地址本身就是音频直链。
    static func isAudio(source: BookSource?, chapter: BookChapter) -> Bool {
        if let type = source?.bookSourceType, type == 1 {
            return !chapter.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return isDirectAudioURL(chapter.url)
    }

    /// 是否音频文件直链：忽略查询参数与锚点，只看扩展名。
    static func isDirectAudioURL(_ raw: String) -> Bool {
        let url = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard url.hasPrefix("http://") || url.hasPrefix("https://") else { return false }
        let path = url.split(separator: "?", maxSplits: 1)[0]
            .split(separator: "#", maxSplits: 1)[0]
        guard let ext = path.split(separator: ".").last, path.contains(".") else { return false }
        return audioExtensions.contains(String(ext))
    }

    /// 从多行文本里取第一个音频直链（正文规则可能返回一组候选地址）。
    static func firstAudioURL(in raw: String) -> String? {
        for line in raw.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let candidate = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            if isDirectAudioURL(candidate) { return candidate }
        }
        let single = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return isDirectAudioURL(single) ? single : nil
    }

    /// 刷新目录后重新定位当前音频章：音频直链每次抓取都会重新签名，URL 必然变化，
    /// 不能按 URL 匹配；按标题定位，找不到时退回原序号（按新目录长度钳制）。
    static func relocatedIndex(in chapters: [BookChapter], title: String?, fallback: Int) -> Int? {
        guard !chapters.isEmpty else { return nil }
        if let title, !title.isEmpty,
           let found = chapters.firstIndex(where: { $0.title == title }) {
            return found
        }
        return min(max(fallback, 0), chapters.count - 1)
    }

    // MARK: 播放地址

    /// 音频书源是否配了正文规则（决定播放地址要不要跑规则）。
    static func hasContentRule(_ source: BookSource?) -> Bool {
        let rule = source?.ruleContent?.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !rule.isEmpty
    }

    /// 解析正文规则的结果 → 播放地址列表。
    ///
    /// 依次尝试：JSON 数组（原版按多段播放）、带 `url/audioUrl/playUrl/src` 的 JSON、
    /// 单行地址、多行里第一个音频直链。解析不出返回空数组。
    static func playURLs(fromContent raw: String) -> [String] {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }
        if text.hasPrefix("[") || text.hasPrefix("{") { 
            let urls = jsonURLs(text)
            if !urls.isEmpty { return urls }
        }
        if isPlayableURL(text) { return [text] }
        if let first = firstAudioURL(in: text) { return [first] }
        // 多行（或带引号/空白）里挑第一个像地址的行。
        for line in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let candidate = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if isPlayableURL(candidate) { return [candidate] }
        }
        return []
    }

    /// 从内容反推「这像不像音频地址」：有音频扩展名，或无扩展名的 http 接口
    /// （音频源常用 `getAudio?id=` 这类地址）。网页/JSON/文本文件不算。
    static func looksLikeAudioURL(_ raw: String) -> Bool {
        if isDirectAudioURL(raw) { return true }
        let lower = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard lower.hasPrefix("http://") || lower.hasPrefix("https://") else { return false }
        let pageMarks = [".html", ".htm", ".php", ".asp", ".aspx", ".jsp", ".shtml",
                         ".json", ".xml", ".txt", ".css", ".js"]
        return !pageMarks.contains(where: { lower.contains($0) })
    }

    /// 音频播放地址：http(s) 即可（很多接口地址没有 .mp3 后缀）。
    static func isPlayableURL(_ raw: String) -> Bool {
        let url = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard url.hasPrefix("http://") || url.hasPrefix("https://") else { return false }
        return !url.contains(" ")
    }

    /// 解析 JSON 结果里的地址：数组取所有字符串元素；
    /// 对象则找常见字段（url/audioUrl/playUrl/src），以及 data/list/urls 里的同类结构。
    static func jsonURLs(_ raw: String) -> [String] {
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else { return [] }
        return jsonURLs(from: object)
    }

    private static func jsonURLs(from object: Any, depth: Int = 0) -> [String] {
        guard depth < 4 else { return [] }
        if let text = object as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return isPlayableURL(trimmed) ? [trimmed] : []
        }
        if let list = object as? [Any] {
            return list.flatMap { jsonURLs(from: $0, depth: depth + 1) }
        }
        guard let map = object as? [String: Any] else { return [] }
        let directKeys = ["url", "audioUrl", "playUrl", "src", "audio", "play_url", "audio_url", "fileUrl"]
        var urls: [String] = []
        for key in directKeys {
            if let value = map[key] {
                urls.append(contentsOf: jsonURLs(from: value, depth: depth + 1))
            }
        }
        if urls.isEmpty {
            for key in ["data", "list", "urls", "audioList", "result", "items"] {
                if let value = map[key] {
                    urls.append(contentsOf: jsonURLs(from: value, depth: depth + 1))
                }
            }
        }
        return urls
    }

    /// 规则里的地址可能是相对的（`//cdn.x/a.mp3`、`/audio/a.mp3`），按章节链接补全。
    static func absolute(_ raw: String, base: String) -> String? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let lower = text.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") { return text }
        if text.hasPrefix("//") { return "https:" + text }
        guard let baseURL = URL(string: base) else { return nil }
        return URL(string: text, relativeTo: baseURL)?.absoluteString
    }
}


/// 判一下下载回来的字节像什么：MP3/M4A/HTML/JSON/加密。
/// 番茄不同音色的音频可能带加密标记（URL 里的 cr=4），先看头几个字节再决定怎么处理。
enum AudioSniff {
    static func describe(_ data: Data) -> String {
        let head = [UInt8](data.prefix(16))
        let hex = head.map { String(format: "%02X", $0) }.joined(separator: " ")
        if data.starts(with: Array("ID3".utf8)) { return "MP3(ID3) · \(hex)" }
        if head.count >= 2, head[0] == 0xFF, (head[1] & 0xE0) == 0xE0 { return "MP3/AAC · \(hex)" }
        if data.count > 8, String(data: data[4..<8], encoding: .ascii) == "ftyp" { return "MP4/M4A · \(hex)" }
        if data.starts(with: Array("OggS".utf8)) { return "OGG · \(hex)" }
        let text = String(data: data.prefix(80), encoding: .utf8)?.lowercased() ?? ""
        if text.contains("<html") || text.contains("<!doctype") { return "HTML · \(hex)" }
        if text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") { return "JSON · \(hex)" }
        return "未知/可能是加密 · \(hex)"
    }

    /// 有的 CDN 会在音频前加一段封装头：扫描前 8KB，找到 MP3/M4A 的起始标记就丢掉前面。
    static func trimmedToAudio(_ data: Data) -> Data? {
        let bytes = [UInt8](data.prefix(8192))
        guard bytes.count > 8 else { return nil }
        func isStart(_ i: Int) -> Bool {
            if i + 3 <= bytes.count,
               bytes[i] == 0x49, bytes[i + 1] == 0x44, bytes[i + 2] == 0x33 { return true } // ID3
            if i + 1 < bytes.count, bytes[i] == 0xFF, (bytes[i + 1] & 0xE0) == 0xE0 { return true }
            if i + 4 <= bytes.count,
               String(bytes: bytes[i..<(i + 4)], encoding: .ascii) == "ftyp" { return true }
            return false
        }
        for i in 4..<bytes.count where isStart(i) {
            return data.subdata(in: i..<data.count)
        }
        return nil
    }
}


/// 有声书「哪些章的音频已经落到本地」的索引（目录里显示实心云）。
/// 只记 bookUrl + 章节标题，不存音频本身。
enum AudioCacheIndex {
    private static let key = "reader.audioCachedChapters.v1"
    private static let lock = NSLock()
    private nonisolated(unsafe) static var cache: Set<String>?

    private static func id(_ bookURL: String, _ chapter: String) -> String {
        bookURL + "\u{1F}" + chapter
    }

    static func mark(bookUrl: String, chapter: String) {
        guard !bookUrl.isEmpty, !chapter.isEmpty else { return }
        lock.lock()
        var set = loadedLocked()
        set.insert(id(bookUrl, chapter))
        persistLocked(set)
        lock.unlock()
    }

    static func contains(bookUrl: String, chapter: String) -> Bool {
        guard !bookUrl.isEmpty, !chapter.isEmpty else { return false }
        lock.lock(); defer { lock.unlock() }
        return loadedLocked().contains(id(bookUrl, chapter))
    }

    private static func loadedLocked() -> Set<String> {
        if let cache { return cache }
        let list = UserDefaults.standard.stringArray(forKey: key) ?? []
        let set = Set(list)
        cache = set
        return set
    }

    private static func persistLocked(_ set: Set<String>) {
        cache = set
        UserDefaults.standard.set(Array(set), forKey: key)
    }
}


/// 有声书诊断日志（音频地址 / 失败原因 / 音色探测）。
/// 单独一份，不混进「书源调试」页面；只在播放器的「音频信息」里显示。
enum AudioLog {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var entries: [String] = []
    private static let limit = 60

    static func add(_ message: String) {
        lock.lock(); defer { lock.unlock() }
        let stamp = DateFormatter()
        stamp.dateFormat = "HH:mm:ss"
        entries.append("\(stamp.string(from: Date())) \(message)")
        if entries.count > limit { entries.removeFirst(entries.count - limit) }
    }

    static func snapshot() -> String {
        lock.lock(); defer { lock.unlock() }
        return entries.joined(separator: "\n")
    }

    static func clear() {
        lock.lock(); entries.removeAll(); lock.unlock()
    }
}
