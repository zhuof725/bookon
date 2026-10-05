//
//  Debug.swift
//  LegadoBookSource
//
//  对应 Kotlin: model/Debug.kt 的**书源调试部分**（RSS 部分不移植，见 README「不做」清单）。
//
//  startDebug(bookSource, key) 五路分发（符号 ⇒/︾/︽/≡ 与 Kotlin 完全一致）：
//    - key 为绝对地址           → 详情页（infoDebug）
//    - key 含 "::"             → 发现页（exploreDebug）→ 成功后链式 infoDebug
//    - key 以 "++" 开头        → 目录页（tocDebug）
//    - key 以 "--" 开头        → 正文页（contentDebug，固定调试章节）
//    - 其它                    → 搜索（searchDebug）→ 成功后链式 infoDebug
//
//  链式调试：搜索/发现 → 详情 → 目录 → 正文；每个阶段自动通过 WebBook 流程函数
//  留存「该阶段最后响应」（URL/状态/头/体），由注入的 DebugLogger 输出。
//
//  —— 全局规范：绝不崩溃；任何异常都转为日志（state = -1），不向上抛、不静默。
//

import Foundation

public enum Debug {

    /// 对应 Kotlin: fun startDebug(scope, bookSource, key)
    public static func startDebug(
        bookSource: BookSource,
        key: String,
        options: WebBookOptions
    ) async {
        options.logger.beginDebug(sourceUrl: bookSource.bookSourceUrl)
        let trimmed = key.trimmingCharacters(in: .whitespaces)
        if FlowStringUtils.isAbsUrl(trimmed) {
            var book = Book()
            book.origin = bookSource.bookSourceUrl
            book.bookUrl = trimmed
            options.logger.log(bookSource.bookSourceUrl, "⇒开始访问详情页:\(trimmed)")
            await infoDebug(bookSource: bookSource, book: &book, options: options)
        } else if trimmed.contains("::") {
            let url = FlowStringUtils.substringAfter(trimmed, "::")
            options.logger.log(bookSource.bookSourceUrl, "⇒开始访问发现页:\(url)")
            await exploreDebug(bookSource: bookSource, url: url, options: options)
        } else if trimmed.hasPrefix("++") {
            let url = String(trimmed.dropFirst(2))
            var book = Book()
            book.origin = bookSource.bookSourceUrl
            book.tocUrl = url
            options.logger.log(bookSource.bookSourceUrl, "⇒开始访目录页:\(url)")
            await tocDebug(bookSource: bookSource, book: &book, options: options)
        } else if trimmed.hasPrefix("--") {
            let url = String(trimmed.dropFirst(2))
            var book = Book()
            book.origin = bookSource.bookSourceUrl
            options.logger.log(bookSource.bookSourceUrl, "⇒开始访正文页:\(url)")
            var chapter = BookChapter()
            chapter.title = "调试"
            chapter.url = url
            await contentDebug(bookSource: bookSource, book: &book, bookChapter: chapter, nextChapterUrl: nil, options: options)
        } else {
            options.logger.log(bookSource.bookSourceUrl, "⇒开始搜索关键字:\(trimmed)")
            await searchDebug(bookSource: bookSource, key: trimmed, options: options)
        }
    }

    // MARK: - 发现

    private static func exploreDebug(bookSource: BookSource, url: String, options: WebBookOptions) async {
        let src = bookSource.bookSourceUrl
        options.logger.log(src, "︾开始解析发现页")
        do {
            let exploreBooks = try await WebBook.exploreBookAwait(bookSource: bookSource, url: url, options: options)
            if !exploreBooks.isEmpty {
                options.logger.log(src, "︽发现页解析完成")
                options.logger.log(src, "", showTime: false)
                var book = exploreBooks[0].toBook()
                await infoDebug(bookSource: bookSource, book: &book, options: options)
            } else {
                options.logger.log(src, "︽未获取到书籍", state: DebugLogState.error)
            }
        } catch {
            options.logger.log(src, error.localizedDescription, state: DebugLogState.error)
        }
    }

    // MARK: - 搜索

    private static func searchDebug(bookSource: BookSource, key: String, options: WebBookOptions) async {
        let src = bookSource.bookSourceUrl
        options.logger.log(src, "︾开始解析搜索页")
        do {
            let searchBooks = try await WebBook.searchBookAwait(bookSource: bookSource, key: key, options: options)
            if !searchBooks.isEmpty {
                options.logger.log(src, "︽搜索页解析完成")
                options.logger.log(src, "", showTime: false)
                var book = searchBooks[0].toBook()
                await infoDebug(bookSource: bookSource, book: &book, options: options)
            } else {
                options.logger.log(src, "︽未获取到书籍", state: DebugLogState.error)
            }
        } catch {
            options.logger.log(src, error.localizedDescription, state: DebugLogState.error)
        }
    }

    // MARK: - 详情

    private static func infoDebug(bookSource: BookSource, book: inout Book, options: WebBookOptions) async {
        let src = bookSource.bookSourceUrl
        if !book.tocUrl.isEmpty {
            options.logger.log(src, "≡已获取目录链接,跳过详情页")
            options.logger.log(src, "", showTime: false)
            await tocDebug(bookSource: bookSource, book: &book, options: options)
            return
        }
        options.logger.log(src, "︾开始解析详情页")
        do {
            _ = try await WebBook.getBookInfoAwait(bookSource: bookSource, book: &book, canReName: true, options: options)
            options.logger.log(src, "︽详情页解析完成")
            options.logger.log(src, "", showTime: false)
            if !book.isWebFile {
                await tocDebug(bookSource: bookSource, book: &book, options: options)
            } else {
                options.logger.log(src, "≡文件类书源跳过解析目录", state: DebugLogState.finished)
            }
        } catch {
            options.logger.log(src, error.localizedDescription, state: DebugLogState.error)
        }
    }

    // MARK: - 目录

    private static func tocDebug(bookSource: BookSource, book: inout Book, options: WebBookOptions) async {
        let src = bookSource.bookSourceUrl
        options.logger.log(src, "︾开始解析目录页")
        do {
            let chapters = try await WebBook.getChapterListAwait(bookSource: bookSource, book: &book, options: options)
            options.logger.log(src, "︽目录页解析完成")
            options.logger.log(src, "", showTime: false)
            let toc = chapters.filter { !(($0.isVolume) && ($0.url.hasPrefix($0.title))) }
            guard !toc.isEmpty else {
                options.logger.log(src, "≡没有正文章节")
                return
            }
            let nextChapterUrl = (toc.count > 1 ? toc[1].url : toc[0].url)
            let first = toc[0]
            await contentDebug(bookSource: bookSource, book: &book, bookChapter: first, nextChapterUrl: nextChapterUrl, options: options)
        } catch {
            options.logger.log(src, error.localizedDescription, state: DebugLogState.error)
        }
    }

    // MARK: - 正文

    private static func contentDebug(
        bookSource: BookSource,
        book: inout Book,
        bookChapter: BookChapter,
        nextChapterUrl: String?,
        options: WebBookOptions
    ) async {
        let src = bookSource.bookSourceUrl
        options.logger.log(src, "︾开始解析正文页")
        do {
            _ = try await WebBook.getContentAwait(
                bookSource: bookSource, book: book, bookChapter: bookChapter,
                nextChapterUrl: nextChapterUrl, needSave: false, options: options
            )
            options.logger.log(src, "︽正文页解析完成", state: DebugLogState.finished)
        } catch {
            options.logger.log(src, error.localizedDescription, state: DebugLogState.error)
        }
    }
}
