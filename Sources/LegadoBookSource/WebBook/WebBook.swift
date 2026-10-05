//
//  WebBook.swift
//  LegadoBookSource
//
//  对应 Kotlin: model/webBook/WebBook.kt（第 7 步 A 段）。
//  移植 searchBook / exploreBook / getBookInfo / getChapterList / runPreUpdateJs /
//  getContent / preciseSearch 及其 async 版本（Swift 用 async/await，不单独写 Await 后缀），
//  以及 checkRedirect。
//
//  每个流程函数：
//    1) 构造 AnalyzeUrl（mUrl/key/page/baseUrl/source/ruleData）；
//    2) fetch（可注入 WebBookNetwork，含 loginCheckJs、checkRedirect、响应源码留存）；
//    3) 交给对应的 BookList / BookInfo / BookChapterList / BookContent 解析；
//    4) 全程 try，错误不静默、不崩溃，统一抛 RuleEngineError 并由 DebugLogger 记录。
//

import Foundation

public enum WebBook {

    // MARK: - 搜索

    public static func searchBookAwait(
        bookSource: BookSource,
        key: String,
        page: Int? = 1,
        options: WebBookOptions,
        filter: ((String, String, String?) -> Bool)? = nil,
        shouldBreak: ((Int) -> Bool)? = nil
    ) async throws -> [SearchBook] {
        guard let searchUrl = bookSource.searchUrl, !searchUrl.isEmpty else {
            throw RuleEngineError.unsupported("搜索url不能为空")
        }
        let ruleData = FlowRuleData()
        let analyzeUrl = AnalyzeUrl(
            searchUrl, key: key, page: page,
            baseUrl: bookSource.bookSourceUrl,
            source: InMemorySource(key: bookSource.bookSourceUrl),
            ruleData: ruleData
        )
        let res = try await fetch(bookSource: bookSource, analyzeUrl: analyzeUrl, options: options, stage: .search)
        var bk = bookSource
        return try BookList.analyzeBookList(
            bookSource: &bk, ruleData: ruleData, analyzeUrl: analyzeUrl,
            baseUrl: res.url, body: res.body, isSearch: true, isRedirect: res.isRedirect,
            options: options, filter: filter, shouldBreak: shouldBreak
        )
    }

    // MARK: - 发现

    public static func exploreBookAwait(
        bookSource: BookSource,
        url: String,
        page: Int? = 1,
        options: WebBookOptions
    ) async throws -> [SearchBook] {
        let ruleData = FlowRuleData()
        let sourceUrl = bookSource.bookSourceUrl
        let analyzeUrl = AnalyzeUrl(
            url, page: page, baseUrl: sourceUrl,
            source: InMemorySource(key: sourceUrl),
            ruleData: ruleData
        )
        let res = try await fetch(bookSource: bookSource, analyzeUrl: analyzeUrl, options: options, stage: .explore)
        var bk = bookSource
        return try BookList.analyzeBookList(
            bookSource: &bk, ruleData: ruleData, analyzeUrl: analyzeUrl,
            baseUrl: res.url, body: res.body, isSearch: false, isRedirect: res.isRedirect,
            options: options
        )
    }

    // MARK: - 书籍信息

    public static func getBookInfoAwait(
        bookSource: BookSource,
        book: inout Book,
        canReName: Bool = true,
        options: WebBookOptions
    ) async throws -> Book {
        book.removeAllBookType()
        book.addType(bookSource.bookSourceType)
        if let infoHtml = book.infoHtml, !infoHtml.isEmpty {
            _ = try BookInfo.analyzeBookInfo(
                bookSource: bookSource, book: &book,
                baseUrl: book.bookUrl, redirectUrl: book.bookUrl, body: infoHtml,
                canReName: canReName, options: options
            )
        } else {
            let ruleData = BookBox(book)
            let analyzeUrl = AnalyzeUrl(
                book.bookUrl, baseUrl: bookSource.bookSourceUrl,
                source: InMemorySource(key: bookSource.bookSourceUrl),
                ruleData: ruleData
            )
            let res = try await fetch(bookSource: bookSource, analyzeUrl: analyzeUrl, options: options, stage: .info)
            _ = try BookInfo.analyzeBookInfo(
                bookSource: bookSource, book: &book,
                baseUrl: book.bookUrl, redirectUrl: res.url, body: res.body,
                canReName: canReName, options: options
            )
        }
        return book
    }

    // MARK: - 目录

    public static func runPreUpdateJs(
        bookSource: BookSource,
        book: inout Book,
        isFromBookInfo: Bool = false,
        options: WebBookOptions
    ) {
        let preUpdateJs = bookSource.ruleToc?.preUpdateJs
        guard let preUpdateJs = preUpdateJs, !preUpdateJs.isEmpty else { return }
        let box = BookBox(book)
        let sourceStore: SourceVariableStore = InMemorySource(key: bookSource.bookSourceUrl)
        let analyzeRule = AnalyzeRule(
            ruleData: box, book: box, source: sourceStore,
            isFromBookInfo: isFromBookInfo, preUpdateJs: true,
            diagnostics: options.diagnostics
        )
        do {
            try analyzeRule.evalJS(preUpdateJs)
            book = box.book
        } catch {
            options.logger.log(bookSource.bookSourceUrl, "执行preUpdateJs规则失败: \(error.localizedDescription)", state: DebugLogState.error)
        }
    }

    public static func getChapterListAwait(
        bookSource: BookSource,
        book: inout Book,
        runPerJs: Bool = false,
        isFromBookInfo: Bool = false,
        options: WebBookOptions
    ) async throws -> [BookChapter] {
        book.removeAllBookType()
        book.addType(bookSource.bookSourceType)
        if runPerJs {
            runPreUpdateJs(bookSource: bookSource, book: &book, isFromBookInfo: isFromBookInfo, options: options)
        }
        if book.bookUrl == book.tocUrl, let tocHtml = book.tocHtml, !tocHtml.isEmpty {
            return try await BookChapterList.analyzeChapterList(
                bookSource: bookSource, book: &book, baseUrl: book.tocUrl,
                redirectUrl: book.tocUrl, body: tocHtml, isFromBookInfo: isFromBookInfo, options: options
            )
        }
        let box = BookBox(book)
        let analyzeUrl = AnalyzeUrl(
            book.tocUrl, baseUrl: book.bookUrl,
            source: InMemorySource(key: bookSource.bookSourceUrl),
            ruleData: box
        )
        let res = try await fetch(bookSource: bookSource, analyzeUrl: analyzeUrl, options: options, stage: .toc)
        let list = try await BookChapterList.analyzeChapterList(
            bookSource: bookSource, book: &book, baseUrl: book.tocUrl,
            redirectUrl: res.url, body: res.body, isFromBookInfo: isFromBookInfo, options: options
        )
        return list
    }

    // MARK: - 章节内容

    public static func getContentAwait(
        bookSource: BookSource,
        book: Book,
        bookChapter: BookChapter,
        nextChapterUrl: String? = nil,
        needSave: Bool = true,
        options: WebBookOptions
    ) async throws -> String {
        var bkSrc = bookSource
        let contentRule = bkSrc.getContentRule()
        if contentRule.content?.isEmpty ?? true {
            options.logger.log(bookSource.bookSourceUrl, "⇒正文规则为空,使用章节链接:\(bookChapter.url)")
            return bookChapter.url
        }
        if bookChapter.isVolume && bookChapter.url.hasPrefix(bookChapter.title) {
            options.logger.log(bookSource.bookSourceUrl, "⇒一级目录正文不解析规则")
            return bookChapter.tag ?? ""
        }
        let base = NetworkUtils.getAbsoluteURL(book.tocUrl, bookChapter.url)
        if bookChapter.url == book.bookUrl, let tocHtml = book.tocHtml, !tocHtml.isEmpty {
            return try await BookContent.analyzeContent(
                bookSource: bookSource, book: book, bookChapter: bookChapter,
                baseUrl: base, redirectUrl: base, body: tocHtml,
                nextChapterUrl: nextChapterUrl, needSave: needSave, options: options
            )
        }
        let box = BookBox(book)
        let analyzeUrl = AnalyzeUrl(
            base, baseUrl: book.tocUrl,
            source: InMemorySource(key: bookSource.bookSourceUrl),
            ruleData: box, chapter: nil
        )
        let res = try await fetch(
            bookSource: bookSource, analyzeUrl: analyzeUrl, options: options, stage: .content,
            webJs: contentRule.webJs, sourceRegex: contentRule.sourceRegex
        )
        return try await BookContent.analyzeContent(
            bookSource: bookSource, book: book, bookChapter: bookChapter,
            baseUrl: base, redirectUrl: res.url, body: res.body,
            nextChapterUrl: nextChapterUrl, needSave: needSave, options: options
        )
    }

    // MARK: - 精准搜索

    public static func preciseSearchAwait(
        bookSource: BookSource,
        name: String,
        author: String,
        options: WebBookOptions
    ) async throws -> Book {
        let searchBooks = try await searchBookAwait(
            bookSource: bookSource, key: name, options: options,
            filter: { fName, fAuthor, _ in fName == name && fAuthor == author },
            shouldBreak: { $0 > 0 }
        )
        guard let first = searchBooks.first else {
            throw RuleEngineError.unsupported("未搜索到 \(name)(\(author)) 书籍")
        }
        let book = first.toBook()
        return book
    }

    // MARK: - 检测重定向

    /// 对应 Kotlin: private fun checkRedirect(bookSource, response)
    private static func checkRedirect(bookSource: BookSource, response: WebBookResponse, options: WebBookOptions) {
        guard response.isRedirect else { return }
        let src = bookSource.bookSourceUrl
        options.logger.log(src, "≡检测到重定向(\(response.status))")
        options.logger.log(src, "┌重定向后地址")
        options.logger.log(src, "└\(response.url)")
    }

    // MARK: - 共享 fetch（对应 Kotlin AnalyzeUrl.getStrResponseAwait + loginCheckJs + checkRedirect）

    /// 对应 Kotlin 各流程函数里反复出现的「getStrResponseAwait + loginCheckJs + checkRedirect」。
    /// - Parameters:
    ///   - webJs: 正文页的 webJs 变换（仅 LiveWebBookNetwork 应用，Mock 直接供给已变换 body）。
    ///   - sourceRegex: 正文页的 sourceRegex 过滤（仅 LiveWebBookNetwork 应用）。
    static func fetch(
        bookSource: BookSource,
        analyzeUrl: AnalyzeUrl,
        options: WebBookOptions,
        stage: DebugStage,
        webJs: String? = nil,
        sourceRegex: String? = nil
    ) async throws -> WebBookResponse {
        let checkJs = bookSource.loginCheckJs
        let res: WebBookResponse
        do {
            let r = try await options.network.fetch(analyzeUrl, webJs: webJs, sourceRegex: sourceRegex)
            if let checkJs = checkJs, !checkJs.isEmpty {
                // 检测书源是否已登录
                analyzeUrl.evalJS(checkJs, result: .string(r.body))
            }
            res = r
        } catch {
            if let checkJs = checkJs, !checkJs.isEmpty {
                // 已登录检测失败时，用错误响应再试一次；若仍失败则上抛
                let errResp = WebBookResponse(url: analyzeUrl.url, status: 500, body: error.localizedDescription)
                analyzeUrl.evalJS(checkJs, result: .string(errResp.body))
            }
            throw RuleEngineError.unsupported("网络请求失败: \(analyzeUrl.url) —— \(error.localizedDescription)")
        }
        options.logger.captureResponse(CapturedResponse(
            stage: stage, url: res.url, statusCode: res.status,
            headers: Dictionary(uniqueKeysWithValues: res.headers), body: res.body
        ))
        checkRedirect(bookSource: bookSource, response: res, options: options)
        return res
    }
}
