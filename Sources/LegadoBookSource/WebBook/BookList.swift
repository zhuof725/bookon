//
//  BookList.swift
//  LegadoBookSource
//
//  对应 Kotlin: model/webBook/BookList.kt（第 7 步 A 段）。
//  移植 analyzeBookList / getInfoItem / getSearchItem / checkExploreJson。
//
//  覆盖分支（FUNCTION_MAPPING 全列）：
//    - bookUrlPattern 匹配 → 详情页分支
//    - bookList 规则以 "-" 开头 → 反序；以 "+" 开头 → 仅去 "+"
//    - 列表为空且 bookUrlPattern 为空 → 按详情页解析
//    - 章节相对地址 / 绝对地址；重复项去重（LinkedHashSet）
//    - 各字段获取失败吞异常并写日志（└异常信息）
//

import Foundation

public enum BookList {

    /// 对应 Kotlin: fun analyzeBookList(...)
    public static func analyzeBookList(
        bookSource: inout BookSource,
        ruleData: FlowRuleData,
        analyzeUrl: AnalyzeUrl,
        baseUrl: String,
        body: String?,
        isSearch: Bool,
        isRedirect: Bool = false,
        options: WebBookOptions,
        filter: ((String, String, String?) -> Bool)? = nil,
        shouldBreak: ((Int) -> Bool)? = nil
    ) throws -> [SearchBook] {
        guard let body = body else {
            throw RuleEngineError.unsupported("列表获取失败: \(analyzeUrl.ruleUrl)")
        }
        let src = bookSource.bookSourceUrl
        options.logger.log(src, "≡获取成功:\(analyzeUrl.ruleUrl)")
        options.logger.log(src, body, state: DebugLogState.searchSource)

        let box = BookBox(Book())
        let sourceStore: SourceVariableStore = InMemorySource(key: bookSource.bookSourceUrl)
        let analyzeRule = AnalyzeRule(
            ruleData: box, book: box, source: sourceStore, diagnostics: options.diagnostics
        )
        try analyzeRule.setContent(body).setBaseUrl(baseUrl)
        analyzeRule.setRedirectUrl(baseUrl)

        if !isSearch {
            checkExploreJson(bookSource: bookSource, options: options)
        }

        if isSearch, let pattern = bookSource.bookUrlPattern, !pattern.isEmpty,
           baseUrl.range(of: pattern, options: .regularExpression) != nil {
            options.logger.log(src, "≡链接为详情页")
        if var sb = getInfoItem(
            bookSource: bookSource, analyzeRule: analyzeRule, analyzeUrl: analyzeUrl,
            body: body, baseUrl: baseUrl, variable: ruleData.getVariable(),
            isRedirect: isRedirect, options: options, filter: filter
        ) {
            sb.infoHtml = body
            return [sb]
        }
            return []
        }

        let collections: [RuleValue]
        var reverse = false
        let bookListRule: BookListRule
        if isSearch {
            bookListRule = bookSource.getSearchRule()
        } else if let exploreBookList = bookSource.getExploreRule().bookList, !exploreBookList.isEmpty {
            bookListRule = bookSource.getExploreRule()
        } else {
            bookListRule = bookSource.getSearchRule()
        }
        var ruleList: String = bookListRule.bookList ?? ""
        if ruleList.hasPrefix("-") {
            reverse = true
            ruleList = String(ruleList.dropFirst())
        }
        if ruleList.hasPrefix("+") {
            ruleList = String(ruleList.dropFirst())
        }
        options.logger.log(src, "┌获取书籍列表")
        collections = (try? analyzeRule.getElements(ruleList)) ?? []
        options.logger.log(src, "└列表大小:\(collections.count)")

        var bookList: [SearchBook] = []
        if collections.isEmpty && bookSource.bookUrlPattern?.isEmpty ?? true {
            options.logger.log(src, "└列表为空,按详情页解析")
            if var sb = getInfoItem(
                bookSource: bookSource, analyzeRule: analyzeRule, analyzeUrl: analyzeUrl,
                body: body, baseUrl: baseUrl, variable: ruleData.getVariable(),
                isRedirect: isRedirect, options: options, filter: filter
            ) {
                sb.infoHtml = body
                bookList.append(sb)
            }
        } else {
            let ruleName = (try? analyzeRule.splitSourceRule(bookListRule.name)) ?? []
            let ruleBookUrl = (try? analyzeRule.splitSourceRule(bookListRule.bookUrl)) ?? []
            let ruleAuthor = (try? analyzeRule.splitSourceRule(bookListRule.author)) ?? []
            let ruleCoverUrl = (try? analyzeRule.splitSourceRule(bookListRule.coverUrl)) ?? []
            let ruleIntro = (try? analyzeRule.splitSourceRule(bookListRule.intro)) ?? []
            let ruleKind = (try? analyzeRule.splitSourceRule(bookListRule.kind)) ?? []
            let ruleLastChapter = (try? analyzeRule.splitSourceRule(bookListRule.lastChapter)) ?? []
            let ruleWordCount = (try? analyzeRule.splitSourceRule(bookListRule.wordCount)) ?? []
            options.logger.log(src, "└列表大小:\(collections.count)")
            for (index, item) in collections.enumerated() {
                guard var sb = getSearchItem(
                    bookSource: bookSource, analyzeRule: analyzeRule, item: item, baseUrl: baseUrl,
                    variable: ruleData.getVariable(), log: index == 0, options: options, filter: filter,
                    ruleName: ruleName, ruleBookUrl: ruleBookUrl, ruleAuthor: ruleAuthor,
                    ruleCoverUrl: ruleCoverUrl, ruleIntro: ruleIntro, ruleKind: ruleKind,
                    ruleLastChapter: ruleLastChapter, ruleWordCount: ruleWordCount
                ) else { continue }
                if baseUrl == sb.bookUrl { sb.infoHtml = body }
                bookList.append(sb)
                if shouldBreak?(bookList.count) == true { break }
            }
            // 去重（对应 Kotlin LinkedHashSet）
            var seen = Set<String>()
            bookList = bookList.filter { sb in
                let key = "\(sb.bookUrl)|\(sb.name)|\(sb.author)"
                if seen.contains(key) { return false }
                seen.insert(key); return true
            }
            if reverse {
                bookList.reverse()
            }
        }
        options.logger.log(src, "◇书籍总数:\(bookList.count)")
        return bookList
    }

    /// 对应 Kotlin: private fun getInfoItem(...)
    private static func getInfoItem(
        bookSource: BookSource,
        analyzeRule: AnalyzeRule,
        analyzeUrl: AnalyzeUrl,
        body: String,
        baseUrl: String,
        variable: String?,
        isRedirect: Bool,
        options: WebBookOptions,
        filter: ((String, String, String?) -> Bool)? = nil
    ) -> SearchBook? {
        var searchBook = SearchBook(variable: variable)
        searchBook.type = bookSource.bookSourceType
        searchBook.origin = bookSource.bookSourceUrl
        searchBook.originName = bookSource.bookSourceName
        searchBook.originOrder = bookSource.customOrder
        // 详情解析以 Book 为载体（与 Kotlin AnalyzeRule(book, bookSource) 一致），解析完成再转回 SearchBook。
        var book = searchBook.toBook()
        book.type = bookSource.bookSourceType
        book.origin = bookSource.bookSourceUrl
        book.originName = bookSource.bookSourceName
        book.originOrder = bookSource.customOrder
        let box = BookBox(book)
        analyzeRule.setRuleData(box)
        analyzeRule.setBook(box)
        _ = try? analyzeRule.setContent(body)
        _ = try? BookInfo.analyzeBookInfo(
            box: box, body: body, analyzeRule: analyzeRule, bookSource: bookSource,
            baseUrl: baseUrl, redirectUrl: baseUrl, canReName: false, options: options
        )
        let result = box.book.toSearchBook()
        if result.name.isEmpty { return nil }
        if let filter = filter, !filter(result.name, result.author, result.kind) { return nil }
        return result
    }

    /// 对应 Kotlin: private fun getSearchItem(...)
    private static func getSearchItem(
        bookSource: BookSource,
        analyzeRule: AnalyzeRule,
        item: RuleValue,
        baseUrl: String,
        variable: String?,
        log: Bool,
        options: WebBookOptions,
        filter: ((String, String, String?) -> Bool)? = nil,
        ruleName: [SourceRule],
        ruleBookUrl: [SourceRule],
        ruleAuthor: [SourceRule],
        ruleCoverUrl: [SourceRule],
        ruleIntro: [SourceRule],
        ruleKind: [SourceRule],
        ruleLastChapter: [SourceRule],
        ruleWordCount: [SourceRule]
    ) -> SearchBook? {
        let src = bookSource.bookSourceUrl
        var searchBook = SearchBook(variable: variable)
        searchBook.type = bookSource.bookSourceType
        searchBook.origin = bookSource.bookSourceUrl
        searchBook.originName = bookSource.bookSourceName
        searchBook.originOrder = bookSource.customOrder
        let box = SearchBookBox(searchBook)
        analyzeRule.setRuleData(box)
        analyzeRule.setBook(box)
        _ = try? analyzeRule.setContent(item)

        options.logger.log(src, "┌获取书名", printLog: log)
        searchBook.name = BookHelp.formatBookName(try? analyzeRule.getString(ruleList: ruleName))
        options.logger.log(src, "└\(searchBook.name)", printLog: log)
        guard !searchBook.name.isEmpty else { return nil }

        options.logger.log(src, "┌获取作者", printLog: log)
        searchBook.author = BookHelp.formatBookAuthor(try? analyzeRule.getString(ruleList: ruleAuthor))
        options.logger.log(src, "└\(searchBook.author)", printLog: log)

        options.logger.log(src, "┌获取分类", printLog: log)
        do {
            searchBook.kind = try analyzeRule.getStringList(ruleList: ruleKind)?.joined(separator: ",")
            options.logger.log(src, "└\(searchBook.kind ?? "")", printLog: log)
        } catch {
            options.logger.log(src, "└\(error.localizedDescription)", printLog: log)
        }

        if let filter = filter, !filter(searchBook.name, searchBook.author, searchBook.kind) { return nil }

        options.logger.log(src, "┌获取字数", printLog: log)
        do {
            searchBook.wordCount = LegadoStringUtils2.wordCountFormat(try analyzeRule.getString(ruleList: ruleWordCount))
            options.logger.log(src, "└\(searchBook.wordCount ?? "")", printLog: log)
        } catch {
            options.logger.log(src, "└\(error.localizedDescription)", printLog: log)
        }

        options.logger.log(src, "┌获取最新章节", printLog: log)
        do {
            searchBook.latestChapterTitle = try analyzeRule.getString(ruleList: ruleLastChapter)
            options.logger.log(src, "└\(searchBook.latestChapterTitle ?? "")", printLog: log)
        } catch {
            options.logger.log(src, "└\(error.localizedDescription)", printLog: log)
        }

        options.logger.log(src, "┌获取简介", printLog: log)
        do {
            let intro = try analyzeRule.getString(ruleList: ruleIntro)
            searchBook.intro = HtmlFormatter.format(intro)
            options.logger.log(src, "└\(searchBook.intro ?? "")", printLog: log)
        } catch {
            options.logger.log(src, "└\(error.localizedDescription)", printLog: log)
        }

        options.logger.log(src, "┌获取封面链接", printLog: log)
        do {
            let cover = try analyzeRule.getString(ruleList: ruleCoverUrl)
            if !cover.isEmpty {
                searchBook.coverUrl = NetworkUtils.getAbsoluteURL(baseUrl, cover)
            }
            options.logger.log(src, "└\(searchBook.coverUrl ?? "")", printLog: log)
        } catch {
            options.logger.log(src, "└\(error.localizedDescription)", printLog: log)
        }

        options.logger.log(src, "┌获取详情页链接", printLog: log)
        searchBook.bookUrl = (try? analyzeRule.getString(ruleList: ruleBookUrl, isUrl: true)) ?? ""
        if searchBook.bookUrl.isEmpty { searchBook.bookUrl = baseUrl }
        options.logger.log(src, "└\(searchBook.bookUrl)")
        return searchBook
    }

    /// 对应 Kotlin: private fun checkExploreJson(bookSource)
    /// 仅校验 discover 规则的 JSON 格式是否规范（不规范则告警日志，不抛错、不静默）。
    private static func checkExploreJson(bookSource: BookSource, options: WebBookOptions) {
        let url = bookSource.exploreUrl ?? ""
        // legado 的 exploreUrl 内可嵌入 !!{...} 形式的分类 JSON；提取并尝试解码为 [ExploreKind]。
        guard let range = url.range(of: #"!!\{.*\}"#, options: .regularExpression) else { return }
        let json = String(url[range])
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) else { return }
        let isArray = obj is [Any]
        let isObject = obj is [String: Any]
        guard isArray || isObject else { return }
        if let arrData = try? JSONSerialization.data(withJSONObject: obj),
           (try? JSONDecoder().decode([ExploreKind].self, from: arrData)) == nil,
           isArray {
            options.logger.log(bookSource.bookSourceUrl, "≡发现地址规则 JSON 格式不规范，请改为规范格式")
        }
    }
}
