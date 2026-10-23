import Foundation

/// 音频书源支持（如「喜马拉雅（优+）」这类 bookSourceType == 1 的源）。
///
/// 播放地址的取法与原版 `AudioPlay.loadPlayUrl` 一致：
/// - **正文规则为空** → 章节链接本身就是播放地址（`WebBook.getContentAwait` 里
///   `contentRule.content.isNullOrEmpty()` 直接返回 `bookChapter.url`）；
/// - **正文规则非空** → 抓章节页、跑正文规则，规则结果就是播放地址
///   （原版 `contentLoadFinish` 把 `content.trim()` 直接赋给 `durPlayUrl`）。
/// 换句话说，音频源的章节链接经常是「接口/页面」，真正的 m4a 是规则里算出来的。
/// 规则结果也可以是 JSON 数组（原版 `ExoPlayerHelper.getMediaSource` 按数组
/// 拼成多段播放），这里同样返回多个地址。
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

    /// 章节的实际播放地址：
    /// - 正文规则为空 → 章节链接（原版 getContentAwait 的短路）；
    /// - 正文规则非空 → 抓章节页跑规则，结果解析成地址；解析不出来时退回章节链接（如果是直链）。
    static func playURLs(source: BookSource, book: Book, chapter: BookChapter) async throws -> [String] {
        let chapterURL = chapter.url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard hasContentRule(source) else {
            return chapterURL.isEmpty ? [] : [chapterURL]
        }
        // 音频源没有正文可分页，也不该走「自动识别正文容器」兜底。
        do {
            let raw = try await WebBook.rawContent(source: source, chapter: chapter,
                                                   nextChapterUrl: nil, book: book,
                                                   fallbackToAutoDetect: false,
                                                   followNextPage: false,
                                                   normalizeText: false)
            let urls = playURLs(fromContent: raw).compactMap { absolute($0, base: chapterURL) }
            if !urls.isEmpty {
                var seen = Set<String>()
                return urls.filter { seen.insert($0).inserted }
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // 规则请求失败但章节链接本身就是音频直链：照旧播它（不少源两套都给了）。
            if isDirectAudioURL(chapterURL) { return [chapterURL] }
            throw error
        }
        return isDirectAudioURL(chapterURL) ? [chapterURL] : []
    }
}
