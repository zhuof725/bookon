//
//  BookContent.swift
//  LegadoBookSource
//
//  对应 Kotlin: model/webBook/BookContent.kt（第 7 步 A 段）。
//  移植 analyzeContent（两个重载）—— 正文解析 + 多页正文 + 副文 + 全文替换 + 标题规则。
//
//  覆盖分支（FUNCTION_MAPPING 全列）：
//    - content 规则为空 / 一级目录正文不解析
//    - nextContentUrl 多页：0 / 1（顺序循环，含到下一章链接的终止判定）/ 多个（并发，本移植按序抓取）
//    - webJs / sourceRegex（仅真实网络路径生效，Mock 直接供给已变换 body）
//    - replaceRegex / subContent（onLineTxt / audio 歌词 / video 弹幕）/ title（含 imgRegex 提取封面）
//    - ContentRule 全字段（content/nextContentUrl/webJs/sourceRegex/replaceRegex/imageStyle/payAction/callBackJs/subContent/title）
//    - 正文为空且非分卷 → 抛 ContentEmptyException（Swift: RuleEngineError.unsupported）
//
//  —— 全局规范：绝不崩溃；Kotlin 抛异常处抛 RuleEngineError；吞异常处吞+记日志。
//

import Foundation

public enum BookContent {

    /// 对应 Kotlin: fun analyzeContent(...): String
    @discardableResult
    public static func analyzeContent(
        bookSource: BookSource,
        book: Book,
        bookChapter: BookChapter,
        baseUrl: String,
        redirectUrl: String,
        body: String?,
        nextChapterUrl: String?,
        needSave: Bool = true,
        options: WebBookOptions
    ) async throws -> String {
        guard let body = body else {
            throw RuleEngineError.unsupported("正文获取失败: \(baseUrl)")
        }
        let src = bookSource.bookSourceUrl
        options.logger.log(src, "≡获取成功:\(baseUrl)")
        options.logger.log(src, body, state: DebugLogState.contentSource)

        // 对应 Kotlin appDb.bookChapterDao.getChapter(...)：本移植无 DB，直接用传入的 nextChapterUrl。
        let mNextChapterUrl = nextChapterUrl

        // 本地可变副本：Kotlin 的 BookChapter 是 class（引用语义），这里用 var 副本等价承载所有字段变更。
        var bookChapter = bookChapter

        var mBookSource = bookSource
        let contentRule = mBookSource.getContentRule()

        let box = BookBox(book)
        let sourceStore: SourceVariableStore = InMemorySource(key: bookSource.bookSourceUrl)
        let analyzeRule = AnalyzeRule(
            ruleData: box, book: box, source: sourceStore, diagnostics: options.diagnostics
        )
        _ = try? analyzeRule.setContent(body, baseUrl: baseUrl)
        analyzeRule.setRedirectUrl(redirectUrl)
        analyzeRule.setChapter(BookChapterBox(bookChapter))
        analyzeRule.setNextChapterUrl(mNextChapterUrl)

        var contentData = analyzeContent(
            book: book, baseUrl: baseUrl, redirectUrl: redirectUrl, body: body,
            contentRule: contentRule, chapter: bookChapter, bookSource: bookSource,
            nextChapterUrl: mNextChapterUrl, options: options
        )
        var contentList: [String] = [contentData.first]

        if contentData.second.count == 1 {
            let webJs = contentRule.webJs
            var nextUrlList: [String] = [redirectUrl]
            var nextUrl = contentData.second.first ?? ""
            while !nextUrl.isEmpty && !nextUrlList.contains(nextUrl) {
                if let m = mNextChapterUrl, !m.isEmpty,
                   NetworkUtils.getAbsoluteURL(redirectUrl, nextUrl)
                    == NetworkUtils.getAbsoluteURL(redirectUrl, m) {
                    break
                }
                nextUrlList.append(nextUrl)
                let box2 = BookBox(book)
                let analyzeUrl = AnalyzeUrl(
                    nextUrl, source: InMemorySource(key: bookSource.bookSourceUrl),
                    ruleData: box2, chapter: BookChapterBox(bookChapter)
                )
                let res = try await BookFlowNetwork.fetchPage(bookSource: bookSource, analyzeUrl: analyzeUrl, options: options, stage: .content, webJs: webJs)
                if !res.body.isEmpty {
                    contentData = analyzeContent(
                        book: book, baseUrl: nextUrl, redirectUrl: res.url, body: res.body,
                        contentRule: contentRule, chapter: bookChapter, bookSource: bookSource,
                        nextChapterUrl: mNextChapterUrl, getNextPageUrl: false, printLog: false, options: options
                    )
                    nextUrl = contentData.second.first ?? ""
                    contentList.append(contentData.first)
                    options.logger.log(bookSource.bookSourceUrl, "第\(contentList.count)页完成")
                } else {
                    nextUrl = ""
                }
            }
            options.logger.log(bookSource.bookSourceUrl, "◇本章总页数:\(nextUrlList.count)")
        } else if contentData.second.count > 1 {
            options.logger.log(bookSource.bookSourceUrl, "◇并发解析正文,总页数:\(contentData.second.count)")
            for urlStr in contentData.second {
                let box2 = BookBox(book)
                let analyzeUrl = AnalyzeUrl(
                    urlStr, source: InMemorySource(key: bookSource.bookSourceUrl),
                    ruleData: box2, chapter: BookChapterBox(bookChapter)
                )
                let res = try await BookFlowNetwork.fetchPage(bookSource: bookSource, analyzeUrl: analyzeUrl, options: options, stage: .content)
                if !res.body.isEmpty {
                    let data = analyzeContent(
                        book: book, baseUrl: urlStr, redirectUrl: res.url, body: res.body,
                        contentRule: contentRule, chapter: bookChapter, bookSource: bookSource,
                        nextChapterUrl: mNextChapterUrl, getNextPageUrl: false, printLog: false, options: options
                    )
                    contentList.append(data.first)
                }
            }
        }

        // 副内容（歌词 / 弹幕 / onLineTxt 章节正文）
        let subContentRule = contentRule.subContent
        if let sub = subContentRule, !sub.isEmpty {
            if let rawContent = try? analyzeRule.getString(sub) {
                if book.isOnLineTxt {
                    contentList.append(rawContent)
                } else {
                    var subContent = rawContent.trimmingCharacters(in: .whitespacesAndNewlines)
                    if subContent.lowercased().hasPrefix("http") {
                        if let fetched = await fetchSubContent(url: subContent, bookSource: bookSource, book: book, options: options) {
                            subContent = fetched
                        }
                    }
                    if book.isAudio {
                        // 对应 Kotlin bookChapter.putLyric(subContent)：本移植用 resourceUrl 承载音频歌词/真实URL
                        // （BookChapter 无独立 lyric 字段，见差异表）。
                        bookChapter.resourceUrl = subContent
                        options.logger.log(src, "┌获取副文歌词")
                        options.logger.log(src, "└\n\(subContent)")
                    } else if book.isVideo {
                        // 对应 Kotlin bookChapter.putDanmaku(subContent)：同上，用 resourceUrl 承载弹幕文本。
                        bookChapter.resourceUrl = subContent
                        options.logger.log(src, "┌获取副文弹幕")
                        options.logger.log(src, "└\n\(subContent)")
                    }
                }
            }
        }

        var contentStr = contentList.joined(separator: "\n")

        // 全文替换
        let replaceRegex = contentRule.replaceRegex
        if let replaceRegex = replaceRegex, !replaceRegex.isEmpty {
            contentStr = contentStr.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
            if let replaced = try? analyzeRule.getString(replaceRegex, mContent: .string(contentStr)) {
                contentStr = replaced
            }
            if book.isOnLineTxt {
                contentStr = contentStr.components(separatedBy: "\n").map { "　　\($0)" }.joined(separator: "\n")
            }
        }

        // 标题规则（先正文再章节名称）
        let titleRule = contentRule.title
        if let titleRule = titleRule, !titleRule.isEmpty {
            if let title = try? analyzeRule.getString(titleRule), !title.isEmpty {
                var newTitle = title
                if let regex = try? NSRegularExpression(pattern: AppPattern.imgRegex),
                   let m = regex.firstMatch(in: title, range: NSRange(title.startIndex..<title.endIndex, in: title)) {
                    let g1Range = m.range(at: 1)
                    let g2Range = m.range(at: 2)
                    let g1 = g1Range.location != NSNotFound ? (title as NSString).substring(with: g1Range) : ""
                    let g2 = g2Range.location != NSNotFound ? (title as NSString).substring(with: g2Range) : ""
                    newTitle = g1.isEmpty ? bookChapter.title : g1
                    bookChapter.imgUrl = g2
                }
                bookChapter.title = newTitle
                // 对应 Kotlin bookChapter.titleMD5 = null; bookChapter.update()（update 属 DB，本移植跳过）
                bookChapter.titleMD5 = nil
            }
        }

        options.logger.log(src, "┌获取章节名称")
        options.logger.log(src, "└\(bookChapter.title)")
        options.logger.log(src, "┌获取正文内容")
        options.logger.log(src, "└\n\(contentStr)")

        if !bookChapter.isVolume && contentStr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw RuleEngineError.unsupported(WebBookError.contentEmpty)
        }
        if needSave {
            // 对应 Kotlin BookHelp.saveContent（书架/DB 持久化，第 6 步之后由 App 层 BookonDebugKit 负责，不静默，仅记录）。
            options.logger.log(src, "≡需保存正文（由 App 层 BookonDebugKit 处理持久化）")
        }
        return contentStr
    }

    /// 对应 Kotlin: private fun analyzeContent(...): Pair<String, List<String>>
    private static func analyzeContent(
        book: Book,
        baseUrl: String,
        redirectUrl: String,
        body: String,
        contentRule: ContentRule,
        chapter: BookChapter,
        bookSource: BookSource,
        nextChapterUrl: String?,
        getNextPageUrl: Bool = true,
        printLog: Bool = true,
        options: WebBookOptions
    ) -> (first: String, second: [String]) {
        let box = BookBox(book)
        let sourceStore: SourceVariableStore = InMemorySource(key: bookSource.bookSourceUrl)
        let analyzeRule = AnalyzeRule(
            ruleData: box, book: box, source: sourceStore, diagnostics: options.diagnostics
        )
        _ = try? analyzeRule.setContent(body, baseUrl: baseUrl)
        analyzeRule.setRedirectUrl(redirectUrl)
        analyzeRule.setChapter(BookChapterBox(chapter))
        analyzeRule.setNextChapterUrl(nextChapterUrl)

        // 获取正文
        var content = (try? analyzeRule.getString(contentRule.content, unescape: false)) ?? ""
        if !book.isAudio && !book.isVideo {
            // adaptSpecialStyle 默认关闭（FlowConfig.adaptSpecialStyle=false），跳过 <usehtml> 保留逻辑。
            content = HtmlFormatter.formatKeepImg(content, redirectUrl: redirectUrl)
            if content.contains("&") {
                content = StringEscapeUtils.unescapeHtml4(content)
            }
        }

        // 获取下一页链接
        var nextUrlList: [String] = []
        if getNextPageUrl, let nextRule = contentRule.nextContentUrl, !nextRule.isEmpty {
            options.logger.log(bookSource.bookSourceUrl, "┌获取正文下一页链接", printLog: printLog)
            if let urls = try? analyzeRule.getStringList(nextRule, isUrl: true) {
                nextUrlList.append(contentsOf: urls)
            }
            options.logger.log(bookSource.bookSourceUrl, "└" + nextUrlList.joined(separator: "，"), printLog: printLog)
        }
        return (content, nextUrlList)
    }

    /// 对应 Kotlin: subContent 以 http(s) 开头时，用 AnalyzeUrl 抓取副文（歌词/弹幕）。
    private static func fetchSubContent(url: String, bookSource: BookSource, book: Book, options: WebBookOptions) async -> String? {
        let box = BookBox(book)
        let analyzeUrl = AnalyzeUrl(
            url, source: InMemorySource(key: bookSource.bookSourceUrl), ruleData: box
        )
        do {
            let res = try await BookFlowNetwork.fetchPage(bookSource: bookSource, analyzeUrl: analyzeUrl, options: options, stage: .content)
            return res.body.isEmpty ? nil : res.body
        } catch {
            options.logger.log(bookSource.bookSourceUrl, "获取副文出错, \(error.localizedDescription)")
            return nil
        }
    }
}
