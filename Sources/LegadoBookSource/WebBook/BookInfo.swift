//
//  BookInfo.swift
//  LegadoBookSource
//
//  对应 Kotlin: model/webBook/BookInfo.kt（第 7 步 A 段）。
//  移植 getBookInfo 的两个重载：
//    1) analyzeBookInfo(bookSource, book, baseUrl, redirectUrl, body, canReName)
//       —— 内部先构造 AnalyzeRule(book, bookSource)，再调 2)。
//    2) analyzeBookInfo(book, body, analyzeRule, bookSource, baseUrl, redirectUrl, canReName)
//       —— 真正的字段解析（书名/作者/分类/字数/最新章节/简介/封面/目录链接或下载链接）。
//
//  全局规范：body 为 nil 抛 NoStackTraceException（Swift 用 RuleEngineError.unsupported）；
//  每个字段解析用 Debug.log 的 ┌/└ 输出；失败字段吞异常并写日志（不崩溃、不静默）。
//

import Foundation

public enum BookInfo {

    /// 对应 Kotlin: fun analyzeBookInfo(bookSource, book, baseUrl, redirectUrl, body, canReName)
    @discardableResult
    public static func analyzeBookInfo(
        bookSource: BookSource,
        book: inout Book,
        baseUrl: String,
        redirectUrl: String,
        body: String?,
        canReName: Bool,
        options: WebBookOptions
    ) throws -> Book {
        guard let body = body else {
            throw RuleEngineError.unsupported("详情页获取失败: \(baseUrl)")
        }
        options.logger.log(bookSource.bookSourceUrl, "≡获取成功:\(baseUrl)")
        options.logger.log(bookSource.bookSourceUrl, body, state: DebugLogState.infoSource)

        let box = BookBox(book)
        let sourceStore: SourceVariableStore = InMemorySource(key: bookSource.bookSourceUrl)
        let analyzeRule = AnalyzeRule(
            ruleData: box,
            book: box,
            source: sourceStore,
            diagnostics: options.diagnostics
        )
        try analyzeRule.setContent(body).setBaseUrl(baseUrl)
        analyzeRule.setRedirectUrl(redirectUrl)

        // ⚠️ 这里**不能**写 `book: &box.book`（CI run 37444288772 的真实崩溃）：
        //   * `BookBox.book` 是可变的 class stored property，`&box.book` 会在整个调用期间
        //     对它持有长期写访问；
        //   * 而函数体内每个字段解析都调 `analyzeRule.getString(...)`，本 Box 同时又是该
        //     AnalyzeRule 的 ruleData / bookStore —— `@js:` 规则里的 `java.put` 会经
        //     `AnalyzeRule.put` → `BookBox.putVariable` **写** `box.book.variable`，
        //     `BookBox.name` getter 也会**读** `box.book`；
        //   * 于是长期写访问与上述读写重叠 → Swift 独占性检查报
        //     `Simultaneous accesses … Fatal access conflict detected` 并 SIGABRT。
        // 改为传 `box` 本体，由被调方逐字段赋值：每次赋值都是独立、短促的访问，
        // 不跨越 `analyzeRule.getString(...)` 调用，因而不会产生重叠区间。
        try analyzeBookInfo(
            box: box,
            body: body,
            analyzeRule: analyzeRule,
            bookSource: bookSource,
            baseUrl: baseUrl,
            redirectUrl: redirectUrl,
            canReName: canReName,
            options: options
        )
        book = box.book
        return box.book
    }

    /// 对应 Kotlin: 第二个 analyzeBookInfo(book, body, analyzeRule, bookSource, baseUrl, redirectUrl, canReName)
    ///
    /// 参数为 `BookBox` 而非 `inout Book`，原因见上面调用点的注释（避免 inout 独占区间
    /// 与 analyzeRule 内部的读取重叠）。
    public static func analyzeBookInfo(
        box: BookBox,
        body: String,
        analyzeRule: AnalyzeRule,
        bookSource: BookSource,
        baseUrl: String,
        redirectUrl: String,
        canReName: Bool,
        options: WebBookOptions
    ) throws {
        let src = bookSource.bookSourceUrl
        var mBookSource = bookSource
        let infoRule = mBookSource.getBookInfoRule()

        // init 规则
        if let initRule = infoRule.`init`, !initRule.isEmpty {
            options.logger.log(src, "≡执行详情页初始化规则")
            let el = try analyzeRule.getElement(initRule)
            try analyzeRule.setContent(el)
        }

        let mCanReName = canReName && !(infoRule.canReName?.isEmpty ?? true)

        // ┌获取书名
        options.logger.log(src, "┌获取书名")
        let name = BookHelp.formatBookName(try? analyzeRule.getString(infoRule.name))
        if !name.isEmpty, (mCanReName || box.book.name.isEmpty) {
            box.book.name = name
        }
        options.logger.log(src, "└\(box.book.name)")

        // ┌获取作者
        options.logger.log(src, "┌获取作者")
        let author = BookHelp.formatBookAuthor(try? analyzeRule.getString(infoRule.author))
        if !author.isEmpty, (mCanReName || box.book.author.isEmpty) {
            box.book.author = author
        }
        options.logger.log(src, "└\(box.book.author)")

        // ┌获取分类
        options.logger.log(src, "┌获取分类")
        do {
            let kind = try analyzeRule.getStringList(infoRule.kind)?.joined(separator: ",") ?? ""
            if !kind.isEmpty { box.book.kind = kind }
            options.logger.log(src, "└\(kind)")
        } catch {
            options.logger.log(src, "└\(error.localizedDescription)")
        }

        // ┌获取字数
        options.logger.log(src, "┌获取字数")
        do {
            let wc = LegadoStringUtils2.wordCountFormat(try analyzeRule.getString(infoRule.wordCount))
            if !wc.isEmpty { box.book.wordCount = wc }
            options.logger.log(src, "└\(wc)")
        } catch {
            options.logger.log(src, "└\(error.localizedDescription)")
        }

        // ┌获取最新章节
        options.logger.log(src, "┌获取最新章节")
        do {
            let lc = try analyzeRule.getString(infoRule.lastChapter)
            if !lc.isEmpty { box.book.latestChapterTitle = lc }
            options.logger.log(src, "└\(lc)")
        } catch {
            options.logger.log(src, "└\(error.localizedDescription)")
        }

        // ┌获取简介
        options.logger.log(src, "┌获取简介")
        do {
            let intro = try analyzeRule.getString(infoRule.intro)
            let introTrim = intro.trimmingCharacters(in: .whitespaces)
            if introTrim.hasPrefix("<usehtml>") || introTrim.hasPrefix("<md>") || introTrim.hasPrefix("<useweb>") {
                box.book.intro = introTrim
                options.logger.log(src, "└\(introTrim)")
            } else {
                let formatted = HtmlFormatter.format(intro)
                if !formatted.isEmpty { box.book.intro = formatted }
                options.logger.log(src, "└\(formatted)")
            }
        } catch {
            options.logger.log(src, "└\(error.localizedDescription)")
        }

        // ┌获取封面链接
        options.logger.log(src, "┌获取封面链接")
        do {
            let cover = try analyzeRule.getString(infoRule.coverUrl)
            if !cover.isEmpty {
                box.book.coverUrl = NetworkUtils.getAbsoluteURL(redirectUrl, cover)
            }
            options.logger.log(src, "└\(cover)")
        } catch {
            options.logger.log(src, "└\(error.localizedDescription)")
        }

        // 目录链接 OR 文件下载链接
        if !box.book.isWebFile {
            options.logger.log(src, "┌获取目录链接")
            box.book.tocUrl = try analyzeRule.getString(infoRule.tocUrl, isUrl: true)
            if box.book.tocUrl.isEmpty { box.book.tocUrl = baseUrl }
            if box.book.tocUrl == baseUrl {
                box.book.tocHtml = body
            }
            options.logger.log(src, "└\(box.book.tocUrl)")
        } else {
            options.logger.log(src, "┌获取文件下载链接")
            let urls = try analyzeRule.getStringList(infoRule.downloadUrls, isUrl: true)
            if urls?.isEmpty ?? true {
                options.logger.log(src, "└")
                throw RuleEngineError.unsupported("下载链接为空")
            } else {
                box.book.downloadUrls = urls ?? []
                options.logger.log(src, "└" + (urls?.joined(separator: "，\n") ?? ""))
            }
        }
    }
}
