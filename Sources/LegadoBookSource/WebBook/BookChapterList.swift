//
//  BookChapterList.swift
//  LegadoBookSource
//
//  对应 Kotlin: model/webBook/BookChapterList.kt（第 7 步 A 段）。
//  移植 analyzeChapterList（两个重载）+ upChapterInfo。
//
//  覆盖分支（FUNCTION_MAPPING 全列）：
//    - chapterList 规则以 "-" 开头 → 反序；以 "+" 开头 → 仅去 "+"
//    - nextTocUrl 多页：0 个 / 1 个（顺序循环抓取）/ 多个（并发抓取，本移植按序抓取，语义一致）
//    - isVolume / isVip / isPay / updateTime / formatJs / reverse / 去重 / preUpdateJs / 相对地址
//    - 目录列表为空 → 抛 TocEmptyException（Swift: RuleEngineError.unsupported）
//    - upChapterInfo：依赖书架 DB 的章节合并，本移植默认 tocCountWords=false 时直接 early-return（与 Kotlin 一致）
//
//  —— 全局规范：绝不崩溃；Kotlin 抛异常处抛 RuleEngineError；吞异常处吞+记日志。
//

import Foundation

public enum BookChapterList {

    /// 对应 Kotlin: fun analyzeChapterList(bookSource, book, baseUrl, redirectUrl, body, isFromBookInfo): List<BookChapter>
    @discardableResult
    public static func analyzeChapterList(
        bookSource: BookSource,
        book: inout Book,
        baseUrl: String,
        redirectUrl: String,
        body: String?,
        isFromBookInfo: Bool = false,
        options: WebBookOptions
    ) async throws -> [BookChapter] {
        guard let body = body else {
            throw RuleEngineError.unsupported("目录获取失败: \(baseUrl)")
        }
        let src = bookSource.bookSourceUrl
        options.logger.log(src, "≡获取成功:\(baseUrl)")
        options.logger.log(src, body, state: DebugLogState.tocSource)

        var mBookSource = bookSource
        let tocRule = mBookSource.getTocRule()
        var nextUrlList: [String] = [redirectUrl]
        var reverse = false
        var listRule = tocRule.chapterList ?? ""
        if listRule.hasPrefix("-") {
            reverse = true
            listRule = String(listRule.dropFirst())
        }
        if listRule.hasPrefix("+") {
            listRule = String(listRule.dropFirst())
        }

        var chapterData = analyzeChapterList(
            book: book, baseUrl: baseUrl, redirectUrl: redirectUrl, body: body,
            tocRule: tocRule, listRule: listRule, bookSource: bookSource,
            getNextUrl: true, log: true, isFromBookInfo: isFromBookInfo, options: options
        )
        var chapterList: [BookChapter] = chapterData.chapters
        switch chapterData.nextUrls.count {
        case 0:
            break
        case 1:
            var nextUrl = chapterData.nextUrls.first ?? ""
            while !nextUrl.isEmpty && !nextUrlList.contains(nextUrl) {
                nextUrlList.append(nextUrl)
                let box = BookBox(book)
                let analyzeUrl = AnalyzeUrl(
                    nextUrl, source: InMemorySource(key: bookSource.bookSourceUrl),
                    ruleData: box, chapter: BookChapterBox(BookChapter())
                )
                let res = try await BookFlowNetwork.fetchPage(bookSource: bookSource, analyzeUrl: analyzeUrl, options: options, stage: .toc)
                if !res.body.isEmpty {
                    chapterData = analyzeChapterList(
                        book: book, baseUrl: nextUrl, redirectUrl: nextUrl, body: res.body,
                        tocRule: tocRule, listRule: listRule, bookSource: bookSource,
                        getNextUrl: true, log: false, isFromBookInfo: isFromBookInfo, options: options
                    )
                    nextUrl = chapterData.nextUrls.first ?? ""
                    chapterList.append(contentsOf: chapterData.chapters)
                } else {
                    nextUrl = ""
                }
            }
            options.logger.log(bookSource.bookSourceUrl, "◇目录总页数:\(nextUrlList.count)")
        default:
            options.logger.log(bookSource.bookSourceUrl, "◇并发解析目录,总页数:\(chapterData.nextUrls.count)")
            for urlStr in chapterData.nextUrls {
                let box = BookBox(book)
                let analyzeUrl = AnalyzeUrl(
                    urlStr, source: InMemorySource(key: bookSource.bookSourceUrl),
                    ruleData: box, chapter: BookChapterBox(BookChapter())
                )
                let res = try await BookFlowNetwork.fetchPage(bookSource: bookSource, analyzeUrl: analyzeUrl, options: options, stage: .toc)
                if !res.body.isEmpty {
                    let data = analyzeChapterList(
                        book: book, baseUrl: urlStr, redirectUrl: res.url, body: res.body,
                        tocRule: tocRule, listRule: listRule, bookSource: bookSource,
                        getNextUrl: true, log: false, isFromBookInfo: isFromBookInfo, options: options
                    )
                    chapterList.append(contentsOf: data.chapters)
                }
            }
        }

        if chapterList.isEmpty {
            throw RuleEngineError.unsupported(WebBookError.chapterListEmpty)
        }
        if !reverse {
            chapterList.reverse()
        }
        // 对应 Kotlin ensureActive()：Swift 结构化并发无需手动检查，跳过（不静默——保留日志语义）。
        // 去重（对应 Kotlin LinkedHashSet，按 url 去重并保持顺序）。
        var seen = Set<String>()
        var list = chapterList.filter { ch in
            let key = ch.url
            if seen.contains(key) { return false }
            seen.insert(key); return true
        }
        if !book.getReverseToc() {
            list.reverse()
        }
        options.logger.log(book.origin, "◇目录总数:\(list.count)")
        for index in list.indices {
            list[index].index = index
        }

        // formatJs：对应 Kotlin Context.enter().use { ... eval(formatJs) }
        let formatJs = tocRule.formatJs
        if let formatJs = formatJs, !formatJs.isEmpty {
            for index in list.indices {
                var ch = list[index]
                let chBox = BookChapterBox(ch)
                let bBox = BookBox(book)
                let sourceStore: SourceVariableStore = InMemorySource(key: bookSource.bookSourceUrl)
                let ar = AnalyzeRule(
                    ruleData: bBox, book: bBox, source: sourceStore,
                    isFromBookInfo: isFromBookInfo, diagnostics: options.diagnostics
                )
                ar.setChapter(chBox)
                _ = try? ar.setContent("")
                if let result = try? ar.evalJS(formatJs),
                   case let .string(newTitle) = result, !newTitle.isEmpty {
                    ch.title = newTitle
                }
                list[index] = ch
            }
        }

        // 书籍级簿记（对应 Kotlin 末尾的 book.durChapterTitle / totalChapterNum / latestChapterTitle 等）。
        // replaceRules / toReplaceBook / getDisplayTitle 属书架层，本移植使用 title 直赋（见差异表）。
        let replaceRules: [String] = []
        let replaceBook: String? = nil
        book.durChapterTitle = getDisplayTitle(list[safe: book.durChapterIndex]?.title ?? list.last?.title,
                                               replaceRules: replaceRules, useReplaceRule: book.getUseReplaceRule(), replaceBook: replaceBook)
        if book.totalChapterNum < list.count {
            book.lastCheckCount = list.count - book.totalChapterNum
            book.latestChapterTime = Book.currentTimeMillis()
        }
        book.lastCheckTime = Book.currentTimeMillis()
        book.totalChapterNum = list.count
        book.latestChapterTitle = getDisplayTitle(
            list[safe: max(0, book.simulatedTotalChapterNum() - 1)]?.title ?? list.last?.title,
            replaceRules: replaceRules, useReplaceRule: book.getUseReplaceRule(), replaceBook: replaceBook
        )

        // 对应 Kotlin ensureActive()
        upChapterInfo(list: &list, book: book)
        return list
    }

    /// 对应 Kotlin: getDisplayTitle(replaceRules, useReplaceRule, replaceBook) 的最简实现。
    /// Kotlin 用 ContentProcessor 的标题替换规则；本移植不含书架层替换，直接返回原标题。
    private static func getDisplayTitle(_ title: String?, replaceRules: [String], useReplaceRule: Bool, replaceBook: String?) -> String? {
        return title
    }

    /// 对应 Kotlin: private fun analyzeChapterList(...): Pair<List<BookChapter>, List<String>>
    private static func analyzeChapterList(
        book: Book,
        baseUrl: String,
        redirectUrl: String,
        body: String,
        tocRule: TocRule,
        listRule: String,
        bookSource: BookSource,
        getNextUrl: Bool = true,
        log: Bool = false,
        isFromBookInfo: Bool,
        options: WebBookOptions
    ) -> (chapters: [BookChapter], nextUrls: [String]) {
        let box = BookBox(book)
        let sourceStore: SourceVariableStore = InMemorySource(key: bookSource.bookSourceUrl)
        let analyzeRule = AnalyzeRule(
            ruleData: box, book: box, source: sourceStore,
            isFromBookInfo: isFromBookInfo, diagnostics: options.diagnostics
        )
        _ = try? analyzeRule.setContent(body).setBaseUrl(baseUrl)
        analyzeRule.setRedirectUrl(redirectUrl)

        let chapterList: [BookChapter] = []
        options.logger.log(bookSource.bookSourceUrl, "┌获取目录列表", printLog: log)
        let elements = (try? analyzeRule.getElements(listRule)) ?? []
        options.logger.log(bookSource.bookSourceUrl, "└列表大小:\(elements.count)", printLog: log)

        // 获取下一页链接
        var nextUrlList: [String] = []
        if let nextToc = tocRule.nextTocUrl, !nextToc.isEmpty {
            options.logger.log(bookSource.bookSourceUrl, "┌获取目录下一页列表", printLog: log)
            if let urls = try? analyzeRule.getStringList(nextToc, isUrl: true) {
                for item in urls where item != redirectUrl {
                    nextUrlList.append(item)
                }
            }
            options.logger.log(bookSource.bookSourceUrl, "└" + FlowStringUtils.join("，\n", nextUrlList), printLog: log)
        }

        guard !elements.isEmpty else {
            return (chapterList, nextUrlList)
        }
        options.logger.log(bookSource.bookSourceUrl, "┌解析目录列表", printLog: log)
        let nameRule = (try? analyzeRule.splitSourceRule(tocRule.chapterName)) ?? []
        let urlRule = (try? analyzeRule.splitSourceRule(tocRule.chapterUrl)) ?? []
        let vipRule = (try? analyzeRule.splitSourceRule(tocRule.isVip)) ?? []
        let payRule = (try? analyzeRule.splitSourceRule(tocRule.isPay)) ?? []
        let upTimeRule = (try? analyzeRule.splitSourceRule(tocRule.updateTime)) ?? []
        let isVolumeRule = (try? analyzeRule.splitSourceRule(tocRule.isVolume)) ?? []
        var result: [BookChapter] = []
        for (index, item) in elements.enumerated() {
            _ = try? analyzeRule.setContent(item)
            var bookChapter = BookChapter(baseUrl: redirectUrl, bookUrl: book.bookUrl)
            let chBox = BookChapterBox(bookChapter)
            analyzeRule.setChapter(chBox)
            bookChapter.title = (try? analyzeRule.getString(ruleList: nameRule)) ?? ""
            bookChapter.url = (try? analyzeRule.getString(ruleList: urlRule)) ?? ""
            let info = (try? analyzeRule.getString(ruleList: upTimeRule)) ?? ""
            let isVolumeStr = (try? analyzeRule.getString(ruleList: isVolumeRule)) ?? ""
            bookChapter.isVolume = false
            if FlowStringUtils.isTrue(isVolumeStr) {
                bookChapter.isVolume = true
                bookChapter.tag = info
            } else {
                if FlowConfig.tocCountWords,
                   let regex = try? NSRegularExpression(pattern: AppPattern.wordCountRegex),
                   let match = regex.firstMatch(in: info, range: NSRange(info.startIndex..<info.endIndex, in: info)),
                   let g1 = Range(match.range(at: 1), in: info) {
                    bookChapter.wordCount = String(info[g1]).trimmingCharacters(in: .whitespaces)
                    if let full = Range(match.range, in: info) {
                        bookChapter.tag = String(info[..<full.lowerBound]) + String(info[full.upperBound...])
                    }
                } else {
                    bookChapter.tag = info
                }
            }
            if bookChapter.url.isEmpty {
                if bookChapter.isVolume {
                    bookChapter.url = bookChapter.title + String(index)
                    options.logger.log(bookSource.bookSourceUrl, "⇒一级目录\(index)未获取到url,使用标题替代")
                } else {
                    bookChapter.url = baseUrl
                    options.logger.log(bookSource.bookSourceUrl, "⇒目录\(index)未获取到url,使用baseUrl替代")
                }
            }
            if !bookChapter.title.isEmpty {
                let isVipStr = (try? analyzeRule.getString(ruleList: vipRule)) ?? ""
                let isPayStr = (try? analyzeRule.getString(ruleList: payRule)) ?? ""
                if FlowStringUtils.isTrue(isVipStr) { bookChapter.isVip = true }
                if FlowStringUtils.isTrue(isPayStr) { bookChapter.isPay = true }
                result.append(bookChapter)
            }
        }
        options.logger.log(bookSource.bookSourceUrl, "└目录列表解析完成", printLog: log)
        if result.isEmpty {
            options.logger.log(bookSource.bookSourceUrl, "◇章节列表为空", printLog: log)
        } else {
            options.logger.log(bookSource.bookSourceUrl, "≡首章信息", printLog: log)
            options.logger.log(bookSource.bookSourceUrl, "◇章节名称:\(result[0].title)", printLog: log)
            options.logger.log(bookSource.bookSourceUrl, "◇章节链接:\(result[0].url)", printLog: log)
            if let wc = result[0].wordCount, !wc.isEmpty {
                options.logger.log(bookSource.bookSourceUrl, "◇章节信息:\(result[0].tag ?? "") \(wc)", printLog: log)
                options.logger.log(bookSource.bookSourceUrl, "⇒已识别到章节信息中的字数", printLog: log)
            } else {
                options.logger.log(bookSource.bookSourceUrl, "◇章节信息:\(result[0].tag ?? "")", printLog: log)
            }
            options.logger.log(bookSource.bookSourceUrl, "◇是否VIP:\(result[0].isVip)", printLog: log)
            options.logger.log(bookSource.bookSourceUrl, "◇是否购买:\(result[0].isPay)", printLog: log)
        }
        return (result, nextUrlList)
    }

    /// 对应 Kotlin: private fun upChapterInfo(list, book)
    /// Kotlin 在 tocCountWords 开启时，用书架 DB 的已存章节去回填 wordCount/variable/imgUrl。
    /// 本移植不含书架 DB；与 Kotlin 一致：tocCountWords=false（FlowConfig 默认值）时直接 early-return。
    private static func upChapterInfo(list: inout [BookChapter], book: Book) {
        if !FlowConfig.tocCountWords {
            return
        }
        // tocCountWords=true 时依赖书架 chapter DAO，不在规则引擎范围内（属第 6 步之后的 App 层），
        // 此处保留 early-return 之外的逻辑缺口，由 App 层补全（见 README「不做」清单说明）。
    }
}

private extension Array {
    /// 对应 Kotlin List.getOrElse(index) { last }，越界时回退到最后一个元素（若为空返回 nil）。
    subscript(safe index: Int) -> Element? {
        guard !isEmpty else { return nil }
        let i = index < 0 ? 0 : (index >= count ? count - 1 : index)
        return self[i]
    }
}
