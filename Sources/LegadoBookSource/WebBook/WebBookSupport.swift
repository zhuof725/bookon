//
//  WebBookSupport.swift
//  LegadoBookSource
//
//  对应 Kotlin 流程层所依赖的**支撑类型**（第 7 步 A 段）：
//   - RuleData：对应 Kotlin model/analyzeRule/RuleData.kt 的最小可用子集
//     （variable 读写：getVariable()/putVariable()，供 BookList.getInfoItem 取变量）
//   - BookData / ChapterData / SourceVariableStore / RuleDataStore 的组合实现：
//     直接用现有的 Book / BookChapter / BookSource 作为 storage（它们已实现这些协议）。
//   - 流程层用到的字符串/URL 小工具（isAbsUrl、isTrue、stackTraceStr、getAbsoluteURL 封装）
//   - AppFreezeException / TocEmptyException / ContentEmptyException 等对应异常
//   - AppPattern 里流程层用到的正则（imgRegex / wordCountRegex / LFRegex / useHtmlRegex）
//   - BookHelp.formatBookName / formatBookAuthor / isWebFile / isOnLineTxt / isAudio / isVideo
//   - StringEscapeUtils.unescapeHtml4（对应 org.apache.commons.text）
//
//  —— 全局规范：绝不崩溃；Kotlin 抛异常处 -> throws + RuleEngineError；吞异常处 -> 吞 + 记诊断。
//

import Foundation

// MARK: - RuleData（对应 Kotlin model/analyzeRule/RuleData.kt 的子集）

/// 对应 Kotlin: open class RuleData(variable: String? = null)。
/// Kotlin 的 RuleData 既提供 `getVariable(): String?`（返回 variableMap 的 JSON 序列化），
/// 又实现 RuleDataInterface（putVariable(key,value)/getVariable(key)）。
/// 流程层在 analyzeBookList 等入口构造它并把整串 variable 透传给 Book(variable:)。
public final class FlowRuleData: RuleDataStore, SourceVariableStore, ConcurrentRateSource {
    private var variableMap: [String: String] = [:]
    private var sourceMap: [String: String] = [:]

    public init(variable: String? = nil) {
        if let variable = variable, !variable.isEmpty,
           let data = variable.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
            variableMap = obj
        }
    }

    // MARK: RuleDataStore（对应 RuleDataInterface）
    public func putVariable(_ key: String, _ value: String?) {
        if let value = value { variableMap[key] = value } else { variableMap.removeValue(forKey: key) }
    }

    public func getVariable(_ key: String) -> String { variableMap[key] ?? "" }

    /// 对应 Kotlin: RuleData.getVariable(): String? —— 整串（variableMap 的 JSON）。
    public func getVariable() -> String? {
        guard !variableMap.isEmpty else { return nil }
        guard let data = try? JSONSerialization.data(withJSONObject: variableMap, options: [.sortedKeys]),
              let s = String(data: data, encoding: .utf8) else { return nil }
        return s
    }

    // MARK: SourceVariableStore（对应 BaseSource.put/get 的底层）
    public func put(_ key: String, _ value: String) -> String { sourceMap[key] = value; return value }
    public func get(_ key: String) -> String { sourceMap[key] ?? "" }
    public func getTag() -> String? { nil }
    public func getKey() -> String { "" }

    // MARK: ConcurrentRateSource
    public var concurrentRate: String? { nil }
}

// MARK: - Book / SearchBook 遵循 BookData + RuleDataStore（对应 Kotlin Book : RuleData()）

private func _wb_variableMap(from variable: String?) -> [String: String] {
    guard let variable = variable, !variable.isEmpty,
          let data = variable.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
        return [:]
    }
    return obj
}

private func _wb_jsonString(from map: [String: String]) -> String? {
    guard !map.isEmpty,
          let data = try? JSONSerialization.data(withJSONObject: map, options: [.sortedKeys]),
          let s = String(data: data, encoding: .utf8) else { return nil }
    return s
}

/// 对应 Kotlin: `Book : RuleData()` —— Kotlin 的 Book 是 class（引用语义），Swift 的 Book 是 struct。
/// 流程层在 Kotlin 把同一个 Book 同时当 ruleData 和 BookData 使用（引用共享）。
/// Swift 用 `BookBox` 包装一个可变的 Book，遵循 BookData + RuleDataStore，二者指向同一实例。
///
/// ⚠️ **不要把 `book` 以 `inout` 传出去**（如 `f(&box.book)`）。
/// `book` 是可变的 class stored property，Swift 会对它做运行时独占性检查；
/// 一旦 `f` 内部又经由 `AnalyzeRule`（本 Box 同时是它的 ruleData / bookStore）
/// 读写同一个 `book`（例如 `@js:` 规则里的 `java.put` → `putVariable` → 写 `book.variable`，
/// 或 `BookBox.name` getter → 读 `book`），就会触发
/// `Simultaneous accesses … Fatal access conflict detected` 并 SIGABRT。
/// 需要「传入后可写回」的语义时，请直接传 `BookBox` 本体，由被调方逐字段赋值。
/// 见 `BookInfo.analyzeBookInfo(box:...)`（曾用 `book: &box.book`，已在 CI 实测崩溃后改掉）。
public final class BookBox: BookData, RuleDataStore {
    public var book: Book

    public init(_ book: Book = Book()) { self.book = book }

    // MARK: BookData
    public var name: String { book.name }

    // MARK: RuleDataStore（variable 以 JSON 存于 book.variable，与 Kotlin 一致）
    public func putVariable(_ key: String, _ value: String?) {
        var map = _wb_variableMap(from: book.variable)
        if let value = value { map[key] = value } else { map.removeValue(forKey: key) }
        book.variable = _wb_jsonString(from: map)
    }
    public func getVariable(_ key: String) -> String { _wb_variableMap(from: book.variable)[key] ?? "" }
}

/// 对应 Kotlin: `SearchBook : RuleData()`。
public final class SearchBookBox: BookData, RuleDataStore {
    public var searchBook: SearchBook

    public init(_ searchBook: SearchBook = SearchBook()) { self.searchBook = searchBook }

    public var name: String { searchBook.name }

    public func putVariable(_ key: String, _ value: String?) {
        var map = _wb_variableMap(from: searchBook.variable)
        if let value = value { map[key] = value } else { map.removeValue(forKey: key) }
        searchBook.variable = _wb_jsonString(from: map)
    }
    public func getVariable(_ key: String) -> String { _wb_variableMap(from: searchBook.variable)[key] ?? "" }
}

/// 对应 Kotlin: `BookChapter : RuleDataInterface`（ChapterData）。
/// Kotlin 的 BookChapter 是 class（引用语义），Swift 用 `BookChapterBox` 包装可变 BookChapter，
/// 遵循 ChapterData，供 AnalyzeRule.setChapter 使用（二者指向同一实例）。
public final class BookChapterBox: ChapterData {
    public var chapter: BookChapter

    public init(_ chapter: BookChapter = BookChapter()) { self.chapter = chapter }

    public var title: String { chapter.title }

    public func putVariable(_ key: String, _ value: String?) {
        var map = _wb_variableMap(from: chapter.variable)
        if let value = value { map[key] = value } else { map.removeValue(forKey: key) }
        chapter.variable = _wb_jsonString(from: map)
    }
    public func getVariable(_ key: String) -> String { _wb_variableMap(from: chapter.variable)[key] ?? "" }
}

// MARK: - 异常（对应 Kotlin 各 NoStackTraceException 子类）

/// 流程层错误（对应 Kotlin NoStackTraceException / TocEmptyException / ContentEmptyException 等）。
/// 统一走 RuleEngineError，遵守「Kotlin 抛异常处抛 RuleEngineError」的全局规则。
public enum WebBookError {
    /// 对应 Kotlin: NoStackTraceException(message)
    public static func noStackTrace(_ message: String) -> RuleEngineError {
        .unsupported(message)
    }
    /// 对应 Kotlin: TocEmptyException(appCtx.getString(R.string.chapter_list_empty))
    public static let chapterListEmpty = "目录列表为空"
    /// 对应 Kotlin: ContentEmptyException("内容为空")
    public static let contentEmpty = "内容为空"
}

// MARK: - AppPattern 子集（对应 Kotlin constant/AppPattern.kt 流程层用到的正则）

public enum AppPattern {
    /// 对应 Kotlin: Regex("<usehtml>.*?</usehtml>", DOT_MATCHES_ALL)
    public static let useHtmlRegex = "<usehtml>.*?</usehtml>"
    /// 对应 Kotlin: Regex("(.*)((?:data|https?):[\\s\\S]+)$")
    public static let imgRegex = "(.*)((?:data|https?):[\\s\\S]+)$"
    /// 对应 Kotlin: Regex("(?:^|字数[：:、]?|\\s+)([0-9万千百\\.]{1,6}字)")
    public static let wordCountRegex = "(?:^|字数[：:、]?|\\s+)([0-9万千百\\.]{1,6}字)"
    /// 对应 Kotlin: "[⇒◇┌└≡]".toRegex()（用于校验模式剔除符号）
    public static let debugMessageSymbolRegex = "[⇒◇┌└≡]"
    /// 对应 Kotlin: "\\n".toRegex()
    public static let LFRegex = "\\n"
    /// 对应 Kotlin: AppPattern.gIntRegex 等流程层的 "字数：" 前缀清理（见 BookChapterList）
    public static let chapterWordCountPrefix = "字数[：:]"
}

// MARK: - FlowConfig（对应 Kotlin AppConfig 流程层开关）

/// 对应 Kotlin: AppConfig.tocCountWords / adaptSpecialStyle 等流程层开关。
/// 本移植不依赖全局可变单例，改为可注入常量（默认与 Kotlin 出厂默认值一致）。
public enum FlowConfig {
    /// 对应 AppConfig.tocCountWords：目录/正文是否解析字数（影响 tag 里的字数提取）。
    public static var tocCountWords: Bool = false
    /// 对应 AppConfig.adaptSpecialStyle：是否保留 <usehtml> 原始片段（默认关闭）。
    public static var adaptSpecialStyle: Bool = false
}

// MARK: - BookFlowNetwork（多页抓取共用）

/// 多页抓取（目录下一页 / 正文下一页）共用的原始 fetch。
/// 与 Kotlin AnalyzeUrl.getStrResponseAwait 一致：只走注入的 WebBookNetwork，
/// 不附加 loginCheckJs / checkRedirect；但会留存该阶段的响应源码（对应 A 段第 4 点）。
public enum BookFlowNetwork {
    public static func fetchPage(
        bookSource: BookSource,
        analyzeUrl: AnalyzeUrl,
        options: WebBookOptions,
        stage: DebugStage,
        webJs: String? = nil,
        sourceRegex: String? = nil
    ) async throws -> WebBookResponse {
        let res = try await options.network.fetch(analyzeUrl, webJs: webJs, sourceRegex: sourceRegex)
        options.logger.captureResponse(CapturedResponse(
            stage: stage, url: res.url, statusCode: res.status,
            headers: Dictionary(uniqueKeysWithValues: res.headers), body: res.body
        ))
        return res
    }
}

// MARK: - 小工具

/// 对应 Kotlin: io.legado.app.utils.isAbsUrl / isTrue 等 String 扩展。
public enum FlowStringUtils {
    /// 对应 Kotlin: fun String.isTrue(): Boolean = this == "true" || this == "1"
    public static func isTrue(_ s: String?) -> Bool {
        guard let s = s else { return false }
        return s == "true" || s == "1"
    }

    /// 对应 Kotlin: fun String.isAbsUrl(): Boolean
    public static func isAbsUrl(_ s: String) -> Bool {
        return LegadoStringUtils.isAbsUrl(s)
    }

    /// 对应 Kotlin: Throwable.stackTraceStr（用于错误日志）。
    public static func stackTraceStr(_ error: Error) -> String {
        return String(describing: error)
    }

    /// 对应 Kotlin: TextUtils.join(separator, list)
    public static func join(_ separator: String, _ list: [String]) -> String {
        return list.joined(separator: separator)
    }

    /// 对应 Kotlin: String.substringAfter("::")
    public static func substringAfter(_ s: String, _ delimiter: String) -> String {
        if let r = s.range(of: delimiter) {
            return String(s[r.upperBound...])
        }
        return s
    }

    /// 对应 Kotlin: String.substringBefore("::")
    public static func substringBefore(_ s: String, _ delimiter: String) -> String {
        if let r = s.range(of: delimiter) {
            return String(s[s.startIndex..<r.lowerBound])
        }
        return s
    }
}

/// 对应 Kotlin: org.apache.commons.text.StringEscapeUtils.unescapeHtml4
/// 复用既有 HtmlUnescape（第 3 步已移植 HTML4 实体表）。
public enum StringEscapeUtils {
    /// 对应 Kotlin: StringEscapeUtils.unescapeHtml4(s)
    public static func unescapeHtml4(_ s: String) -> String {
        return HtmlUnescape.unescapeHtml4(s)
    }
}

// MARK: - BookHelp 子集（对应 Kotlin help/book/BookHelp.kt 流程层用到的部分）

public enum BookHelp {
    /// 对应 Kotlin: fun formatBookName(name: String?): String
    /// 去掉书名里常见的广告/前缀后缀（与 Kotlin 完全一致的正则与替换顺序）。
    public static func formatBookName(_ name: String?) -> String {
        guard let name = name else { return "" }
        return name
            .replacingOccurrences(of: "\\s", with: "", options: .regularExpression)
            .replacingOccurrences(of: "（.*?）", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\(.*?\\)", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\[.*?\\]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "【.*?】", with: "", options: .regularExpression)
            .replacingOccurrences(of: "《|》", with: "", options: .regularExpression)
    }

    /// 对应 Kotlin: fun formatBookAuthor(author: String?): String
    public static func formatBookAuthor(_ author: String?) -> String {
        guard let author = author else { return "" }
        return author
            .replacingOccurrences(of: "\\s", with: "", options: .regularExpression)
            .replacingOccurrences(of: "（.*?）", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\(.*?\\)", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\[.*?\\]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "【.*?】", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\[|\\]", with: "", options: .regularExpression)
    }
}

/// 对应 Kotlin: help/book/BookExt.kt 的 addType / removeAllBookType（按位类型标记）。
extension Book {
    /// 对应 Kotlin: fun Book.removeAllBookType() { type = 0 }
    public mutating func removeAllBookType() { type = 0 }
    /// 对应 Kotlin: fun Book.addType(type: Int) { this.type = this.type or type }
    public mutating func addType(_ t: Int) { type = type | t }
}

/// 对应 Kotlin: help/book/BookType.kt 的 Book 扩展（isWebFile / isOnLineTxt / isAudio / isVideo）。
extension Book {
    /// 对应 Kotlin: `fun Book.isType(bookType: Int): Boolean = type and bookType > 0`
    ///
    /// `type` 是**按位**类型标记（一本书可同时是文本 + 音频 + …），因此这里必须做
    /// **位测试**而不是相等比较。
    ///
    /// ⚠️ 不要把这些属性退回 `type == BookType.xxx`：相等的判定会让「文本+音频」这类
    /// 组合书全部落空。真实缺陷来源（CI run `37283495871`，`testSubContentAudioStoredInResourceUrl`
    /// 等 3 个用例）：测试调 `book.addType(BookType.audio)` 得到 `type = 32`，恰好等于
    /// `BookType.audio` 所以相等判定侥幸成立；但只要再叠加任何一位（如 `addType(BookType.text)`
    /// 得到 40），Kotlin 仍判 `isAudio == true`，而相等判定会给出 `false`，副文歌词/弹幕
    /// 分支被整段跳过。
    public func isType(_ bookType: Int) -> Bool { type & bookType > 0 }

    /// 对应 Kotlin: val Book.isWebFile: Boolean —— 文件类书源（BookType.webFile）。
    public var isWebFile: Bool { isType(BookType.webFile) }

    /// 对应 Kotlin: val Book.isOnLineTxt: Boolean = !isLocal && isType(BookType.text)
    public var isOnLineTxt: Bool { isType(BookType.text) }

    /// 对应 Kotlin: val Book.isAudio: Boolean = isType(BookType.audio)
    public var isAudio: Bool { isType(BookType.audio) }

    /// 对应 Kotlin: val Book.isVideo: Boolean = isType(BookType.video)
    public var isVideo: Bool { isType(BookType.video) }

    /// 对应 Kotlin: fun Book.getReverseToc(): Boolean = readConfig?.reverseToc ?: false
    public func getReverseToc() -> Bool { readConfig?.reverseToc ?? false }

    /// 对应 Kotlin: fun Book.getUseReplaceRule(): Boolean = readConfig?.useReplaceRule ?: true
    public func getUseReplaceRule() -> Bool { readConfig?.useReplaceRule ?? true }

    /// 对应 Kotlin: fun Book.simulatedTotalChapterNum(): Int
    /// Kotlin: if (totalChapterNum == 0) Int.MAX_VALUE else totalChapterNum
    public func simulatedTotalChapterNum() -> Int {
        if totalChapterNum == 0 { return Int.max }
        return totalChapterNum
    }
}

// MARK: - 书源对象互转（对应 Kotlin SearchBook.toBook() / Book.toSearchBook()）

extension SearchBook {
    /// 对应 Kotlin: fun SearchBook.toBook(): Book
    public func toBook() -> Book {
        var book = Book()
        book.bookUrl = bookUrl
        book.origin = origin
        book.originName = originName
        book.type = type
        book.name = name
        book.author = author
        book.kind = kind
        book.coverUrl = coverUrl
        book.intro = intro
        book.wordCount = wordCount
        book.latestChapterTitle = latestChapterTitle
        book.tocUrl = tocUrl
        book.variable = variable
        book.originOrder = originOrder
        book.infoHtml = infoHtml
        book.tocHtml = tocHtml
        return book
    }
}

extension Book {
    /// 对应 Kotlin: fun Book.toSearchBook(): SearchBook
    public func toSearchBook() -> SearchBook {
        var sb = SearchBook(
            bookUrl: bookUrl,
            origin: origin,
            originName: originName,
            type: type,
            name: name,
            author: author,
            kind: kind,
            coverUrl: coverUrl,
            intro: intro,
            wordCount: wordCount,
            latestChapterTitle: latestChapterTitle,
            tocUrl: tocUrl,
            variable: variable,
            originOrder: originOrder
        )
        // SearchBook 的 infoHtml/tocUrl 为运行时字段，构造后赋值（对应 Kotlin 同名拷贝）。
        sb.infoHtml = infoHtml
        sb.tocHtml = tocHtml
        return sb
    }
}
