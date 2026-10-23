import Foundation
import CryptoKit

/// 一本书的阅读模式：文本 / 音频 / 漫画（图片）/ 文件 / 视频。
///
/// 原版靠书源的 `bookSourceType` 决定进哪种阅读器；但实际书源里经常出现
/// 「类型写成文本、正文其实是 `<img>` 图片列表」「类型没填、章节链接却是音频接口」
/// 这类情况，光看类型会进错阅读器（漫画当文字排版、音频当正文抓）。
/// 这里除了书源类型，还支持**从正文内容反推**模式，并按书缓存结果。
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

    /// 书源类型 → 模式。0/缺省表示「未声明」，返回 nil 交给正文识别。
    static func from(sourceType: Int?) -> BookKind? {
        switch sourceType ?? 0 {
        case 1: return .audio
        case 2: return .image
        case 3: return .file
        case 4: return .video
        default: return nil
        }
    }

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
        // 音频：短、且能解析成播放地址。
        if text.count <= 2000, plain.count <= 600,
           !AudioChapter.playURLs(fromContent: text).isEmpty {
            return .audio
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
