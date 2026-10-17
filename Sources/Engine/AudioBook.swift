import Foundation

/// 音频书源支持（如「喜马拉雅（优+）」这类 bookSourceType == 1 的源）：
/// 章节链接本身就是音频直链，正文规则返回的也是该地址；
/// 阅读器据此改用音频播放，而不是当文字排版。
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
}
