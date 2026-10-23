import Foundation
import CryptoKit

/// 一本书的阅读模式：文本 / 音频 / 漫画（图片）/ 文件 / 视频。
///
/// 识别顺序参照两位「原版」：
/// 1. **Legado**：书源类型（`bookSourceType` 0 文本 / 1 音频 / 2 图片 / 3 文件 / 4 视频），
///    加书时把它记到书上，阅读器按书上的类型分派。
/// 2. **Yuedu**：聚合源（一个源里同时有小说/听书/漫画）光看源类型不够，
///    还会看这本书自带的标记 —— 书籍地址里的 `tab/type/media` 参数、
///    地址里内嵌的 `data:;base64,…` JSON、书源的运行时变量、以及
///    「当前模式：听书/漫画」这类文字。
/// 我们再多一层兜底：书源名/章节名（第N话、第N集），最后才抓正文看内容。
enum BookKind: String, CaseIterable {
    case text, audio, image, file, video, local

    var label: String {
        switch self {
        case .text: return "文本"
        case .audio: return "音频"
        case .image: return "漫画"
        case .file: return "文件"
        case .video: return "视频"
        case .local: return "本地"
        }
    }

    /// 书源类型 → 模式。0/缺省表示「未声明」，返回 nil 交给后续信号。
    static func from(sourceType: Int?) -> BookKind? {
        switch sourceType ?? 0 {
        case 1: return .audio
        case 2: return .image
        case 3: return .file
        case 4: return .video
        default: return nil
        }
    }

    // MARK: - Yuedu 式多信号推断

    /// 书本身/书源里能直接读出来的模式（不需要联网、也不用抓正文）。
    static func infer(source: BookSource?, book: Book?) -> BookKind? {
        if let declared = from(sourceType: source?.bookSourceType), declared != .text {
            return declared
        }
        for url in [book?.bookUrl, book?.tocUrl].compactMap({ $0 }) {
            if let kind = kind(fromURL: url) { return kind }
        }
        let texts = [book?.kind, book?.originName, source?.bookSourceName,
                     book?.intro, book?.lastChapter].compactMap { $0 }
        for text in texts {
            if let kind = kind(fromMetadataText: text) { return kind }
        }
        return nil
    }

    /// 地址里的模式标记：查询参数 `tab/type/media/mode/category`，
    /// 或聚合源把整段 JSON 塞在地址里的 `data:;base64,…`。
    static func kind(fromURL rawURL: String) -> BookKind? {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        for payload in dataURLPayloads(from: trimmed) {
            if let kind = kind(fromJSONObject: payload) { return kind }
        }
        let requestURL = trimmed.split(separator: ",", maxSplits: 1).first.map(String.init) ?? trimmed
        guard let components = URLComponents(string: requestURL) else { return nil }
        let keys = ["tab", "type", "media", "mode", "category", "booktype", "contenttype"]
        for item in components.queryItems ?? [] where keys.contains(item.name.lowercased()) {
            if let kind = kind(fromStructuredValue: item.value) { return kind }
        }
        return nil
    }

    /// 「当前模式：听书 / 漫画」这类文字标记，以及等值的中英文类型名。
    static func kind(fromMetadataText raw: String) -> BookKind? {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
        guard !normalized.isEmpty else { return nil }
        let audioMarkers = ["当前模式：听书", "当前模式:听书", "模式：听书", "模式:听书", "当前模式：有声"]
        let mangaMarkers = ["当前模式：漫画", "当前模式:漫画", "模式：漫画", "模式:漫画"]
        if audioMarkers.contains(where: { normalized.contains($0) }) { return .audio }
        if mangaMarkers.contains(where: { normalized.contains($0) }) { return .image }
        return kind(fromStructuredValue: normalized)
    }

    /// 结构化取值：数字（Legado 的位标记 8 文本 / 32 音频 / 64 图片）、
    /// 或字符串类型名。
    static func kind(fromStructuredValue value: Any?) -> BookKind? {
        guard let value else { return nil }
        if let intValue = value as? Int { return kind(fromTypeNumber: intValue) }
        if let doubleValue = value as? Double { return kind(fromTypeNumber: Int(doubleValue)) }
        let text = String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if let intValue = Int(text) { return kind(fromTypeNumber: intValue) }
        let normalized = text.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
        switch normalized {
        case "听书", "聽書", "有声", "有聲", "audio", "audiobook": return .audio
        case "漫画", "漫畫", "comic", "manga", "image": return .image
        case "小说", "小說", "novel", "text", "文字": return .text
        case "视频", "視頻", "video": return .video
        case "文件", "file": return .file
        default: return nil
        }
    }

    static func kind(fromTypeNumber value: Int) -> BookKind? {
        switch value {
        case 0, 8: return .text
        case 1, 32: return .audio
        case 2, 64: return .image
        case 3, 128: return .file
        case 4: return .video
        default: return nil
        }
    }

    /// 聚合源常把 JSON（含 tab/type）编进书地址：`data:;base64,<base64>,<…>`。
    static func dataURLPayloads(from text: String) -> [[String: Any]] {
        let marker = "data:;base64,"
        var payloads: [[String: Any]] = []
        var searchStart = text.startIndex
        while let range = text.range(of: marker, options: [.caseInsensitive],
                                     range: searchStart..<text.endIndex) {
            let base64Start = range.upperBound
            let base64End = text[base64Start...].firstIndex(of: ",") ?? text.endIndex
            let raw = String(text[base64Start..<base64End])
            let decoded = raw.removingPercentEncoding ?? raw
            if let data = Data(base64Encoded: decoded),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                payloads.append(json)
            }
            searchStart = base64End
        }
        return payloads
    }

    private static func kind(fromJSONObject object: Any) -> BookKind? {
        if let dictionary = object as? [String: Any] {
            for (key, value) in dictionary {
                if isContentKindKey(key), let kind = kind(fromStructuredValue: value) { return kind }
                if let kind = kind(fromJSONObject: value) { return kind }
            }
        } else if let array = object as? [Any] {
            for value in array {
                if let kind = kind(fromJSONObject: value) { return kind }
            }
        }
        return nil
    }

    private static func isContentKindKey(_ key: String) -> Bool {
        let normalized = key.lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
        return ["tab", "type", "media", "mode", "category", "findtab", "booktype", "contenttype"]
            .contains(normalized)
    }

    // MARK: - 名称/章节名（不联网）

    /// 书源名称/分组、目录章节名。
    /// 番茄漫画、七猫听书这类「一个书源只出一种书」的源，名字和章节名足够分辨。
    static func guess(source: BookSource?, chapters: [BookChapter]) -> BookKind? {
        let name = (source?.bookSourceName ?? "") + " " + (source?.bookSourceGroup ?? "")
        let lower = name.lowercased()
        if lower.contains("漫画") || lower.contains("comic") || lower.contains("manga") {
            return .image
        }
        if lower.contains("听书") || lower.contains("有声") || lower.contains("音频")
            || lower.contains("评书") || lower.contains(" 听 ") {
            return .audio
        }
        let titles = chapters.filter { !$0.isVolume && !$0.title.isEmpty }
            .prefix(30).map(\.title)
        guard titles.count >= 3 else { return nil }
        let comic = titles.filter { $0.contains("话") || $0.contains("話") }.count
        let audio = titles.filter { $0.contains("集") || $0.contains("期") }.count
        let text = titles.filter { $0.contains("章") }.count
        let total = Double(titles.count)
        if Double(comic) / total >= 0.6, comic > text { return .image }
        if Double(audio) / total >= 0.6, audio > text { return .audio }
        return nil
    }

    // MARK: - 正文内容

    /// 从正文规则的结果反推模式。
    /// - 音频：整段结果就是一条播放地址（或多段地址的 JSON 数组）；
    /// - 漫画：正文里是成组的 `<img>`，几乎没有文字；
    /// - 其余按文本处理。
    ///
    /// 阈值故意保守：文字书里偶尔夹一张插图不会被判成漫画。
    static func detect(inContent raw: String) -> BookKind {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .text }
        let plain = strippedText(text)
        // 音频：短、且解析出来的地址都像音频（网页/接口说明页不算）。
        if text.count <= 2000, plain.count <= 600 {
            let urls = AudioChapter.playURLs(fromContent: text)
            if !urls.isEmpty, urls.allSatisfy({ AudioChapter.looksLikeAudioURL($0) }) {
                return .audio
            }
        }
        let images = imageTagCount(text)
        if images >= 3, plain.count <= 200 { return .image }
        return .text
    }

    /// 去掉标签后的可见文字长度（图片的 alt/src 不算正文）。
    static func strippedText(_ raw: String) -> String {
        var text = raw
        if let regex = try? NSRegularExpression(pattern: "<[^>]+>", options: []) {
            let range = NSRange(location: 0, length: (text as NSString).length)
            text = regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
        }
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func imageTagCount(_ raw: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: "<img\\b", options: [.caseInsensitive]) else { return 0 }
        let range = NSRange(location: 0, length: (raw as NSString).length)
        return regex.numberOfMatches(in: raw, options: [], range: range)
    }
}

/// 每本书识别出的阅读模式（UserDefaults，按书地址的 SHA256 存）。
/// 有缓存就不再重复抓正文探测。
enum BookKindStore {
    static let keyPrefix = "book.kind.v1."

    static func key(for bookUrl: String) -> String {
        let digest = SHA256.hash(data: Data(bookUrl.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return keyPrefix + digest
    }

    static func saved(bookUrl: String, defaults: UserDefaults = .standard) -> BookKind? {
        guard let raw = defaults.string(forKey: key(for: bookUrl)) else { return nil }
        return BookKind(rawValue: raw)
    }

    static func save(_ kind: BookKind, bookUrl: String, defaults: UserDefaults = .standard) {
        defaults.set(kind.rawValue, forKey: key(for: bookUrl))
    }

    static func clear(bookUrl: String, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key(for: bookUrl))
    }
}
