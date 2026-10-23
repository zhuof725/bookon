import Foundation
import CryptoKit

/// 有声书播放进度记忆（原版 `AudioPlay.saveRead` 的 `durChapterIndex` + `durChapterPos`）。
///
/// 按书保存「听到第几章 + 这一章第几秒」：重新打开这本书时接着上次的位置播，
/// 换了章节则从新章开头开始（和原版一致）。
enum AudioProgress {
    struct Position: Equatable {
        var chapter: Int
        var seconds: Double
    }

    static let keyPrefix = "audio.progress.v1."

    /// 地址可能很长，统一用 SHA256 当键。
    static func key(for bookUrl: String) -> String {
        let digest = SHA256.hash(data: Data(bookUrl.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return keyPrefix + digest
    }

    static func load(bookUrl: String, defaults: UserDefaults = .standard) -> Position? {
        guard let raw = defaults.dictionary(forKey: key(for: bookUrl)),
              let chapter = raw["chapter"] as? Int,
              let seconds = raw["seconds"] as? Double,
              seconds.isFinite, seconds >= 0 else { return nil }
        return Position(chapter: chapter, seconds: seconds)
    }

    static func save(bookUrl: String, chapter: Int, seconds: Double,
                     defaults: UserDefaults = .standard) {
        guard chapter >= 0, seconds.isFinite, seconds >= 0 else { return }
        defaults.set(["chapter": chapter, "seconds": seconds], forKey: key(for: bookUrl))
    }

    /// 重新打开这本书时该从第几秒开始：只有同一章才续播。
    static func resumeSeconds(bookUrl: String, chapter: Int,
                              defaults: UserDefaults = .standard) -> Double {
        guard let saved = load(bookUrl: bookUrl, defaults: defaults),
              saved.chapter == chapter else { return 0 }
        return saved.seconds
    }

    static func clear(bookUrl: String, defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: key(for: bookUrl))
    }
}
