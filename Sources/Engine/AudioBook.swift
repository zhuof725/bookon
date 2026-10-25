import Foundation

/// 需要书源/网络的部分：跑正文规则、音色改写后取播放地址。
extension AudioChapter {
    /// 章节的实际播放地址：
    /// - 正文规则为空 → 章节链接（原版 getContentAwait 的短路）；
    /// - 正文规则非空 → 抓章节页跑规则，结果解析成地址；解析不出来时退回章节链接（如果是直链）。
    /// - Parameter content: 已经抓好的正文规则结果（识别阅读模式时顺手拿到的），
    ///   传了就省一次请求。
    static func playURLs(source: BookSource, book: Book, chapter: BookChapter,
                         content: String? = nil) async throws -> [String] {
        let chapterURL = chapter.url.trimmingCharacters(in: .whitespacesAndNewlines)
        // 书源有「音频模式」变体（番茄的 ys_module=2、聚合源的 source=番茄听书）：
        // 把章节地址改写成音频模式，让书源自己的规则算地址（音色取源变量里的 tone）。
        if let toneURL = await SourceToneAudio.audioURL(source: source, book: book, chapter: chapter) {
            return [toneURL]
        }
        // 番茄真人录播书：选了合成音色时改播文字版的 TTS（服务端才会按 tone 换声音）。
        if let ttsURL = await FanqieTTS.audioURL(source: source, book: book, chapter: chapter) {
            return [ttsURL]
        }
        guard hasContentRule(source) else {
            return chapterURL.isEmpty ? [] : [chapterURL]
        }
        if let content {
            let prefetched = playURLs(fromContent: content).compactMap { absolute($0, base: chapterURL) }
            if !prefetched.isEmpty {
                var seen = Set<String>()
                return prefetched.filter { seen.insert($0).inserted }
            }
        }
        // 音频源没有正文可分页，也不该走「自动识别正文容器」兜底。
        do {
            let raw = try await WebBook.rawContentWithBookInfoHealing(
                source: source, book: book, chapter: chapter,
                fallbackToAutoDetect: false, followNextPage: false, normalizeText: false)
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
