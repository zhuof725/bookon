import Foundation
import CryptoKit

/// 阅读与预取只能通过同一入口获取在线正文，防止重复抓取、重复解析和覆盖缓存。
enum ChapterContentLoader {
    static func content(source: BookSource, book: Book, chapter: BookChapter,
                        nextChapterURL: String?, priority: TaskPriority = .userInitiated) async throws -> String {
        // 卷名在本地展示，不对空 URL 或卷链接运行正文规则。
        guard !chapter.isVolume else { return chapter.title }
        // 音频书源：章节链接就是音频直链，正文即该地址本身；
        // 不下载音频当正文、不写正文缓存。阅读器据此走音频播放。
        if AudioChapter.isAudio(source: source, chapter: chapter) { return chapter.url }
        let key = ChapterContentKey(sourceURL: source.bookSourceUrl, bookURL: book.bookUrl, chapterURL: chapter.url)
        let raw = try await ChapterContentCache.shared.content(for: key, priority: priority) {
            if let legacy = legacyContent(chapterURL: chapter.url) { return legacy }
            // 缓存原始正文，段评标签留给阅读器排版；不在预读时执行 UIKit 分页。
            return try await WebBook.rawContentWithBookInfoHealing(source: source, book: book,
                                                                  chapter: chapter,
                                                                  nextChapterURL: nextChapterURL)
        }
        // 漫画（图片源）的正文是 <img> 图片列表，不做文字段落归一化；
        // 图片地址由阅读器用 MangaBook.imageURLs 提取。
        if MangaBook.isManga(source: source) { return raw }
        // Also normalize cache hits, so users do not have to clear old chapter caches
        // after this paragraph-layout fix (it applies to every book source).
        return WebBook.normalizeParagraphBoundaries(raw)
    }

    /// 旧版 c_MD5(url).txt 继续可读；命中后由共享缓存迁移到 source/book/chapter 隔离的新键。
    private static func legacyContent(chapterURL: String) -> String? {
        guard !chapterURL.isEmpty else { return nil }
        let digest = Insecure.MD5.hash(data: Data(chapterURL.utf8))
            .map { String(format: "%02x", $0) }.joined()
        let file = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("chapters/c_" + digest + ".txt")
        guard let raw = try? String(contentsOf: file, encoding: .utf8),
              !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return raw
    }
}
