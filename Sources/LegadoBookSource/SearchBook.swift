//
//  SearchBook.swift
//  LegadoBookSource
//
//  对应 Kotlin: data/entities/SearchBook.kt
//
//  Kotlin 里 SearchBook 是 Room @Entity + Parcelable + BaseBook + Comparable，含
//  与 Book/ReplaceBook 互转、来源集合、显示辅助等方法。
//  本步骤只做数据模型：持久化字段一一对应；@Ignore 运行时字段（infoHtml/tocHtml）不参与 Codable；
//  业务方法留待后续步骤。
//

import Foundation

public struct SearchBook: Codable, BaseBook, Comparable {

    // MARK: 持久化字段

    @LenientString<Defaults.EmptyString> public var bookUrl: String
    /// 书源
    @LenientString<Defaults.EmptyString> public var origin: String
    @LenientString<Defaults.EmptyString> public var originName: String
    /// BookType
    @LenientInt<TextTypeDefault> public var type: Int
    @LenientString<Defaults.EmptyString> public var name: String
    @LenientString<Defaults.EmptyString> public var author: String
    @LenientOptionalString public var kind: String?
    @LenientOptionalString public var coverUrl: String?
    @LenientOptionalString public var intro: String?
    @LenientOptionalString public var wordCount: String?
    @LenientOptionalString public var latestChapterTitle: String?
    /// 目录页Url (toc=table of Contents)
    @LenientString<Defaults.EmptyString> public var tocUrl: String
    /// 构造默认 currentTimeMillis；缺字段用 0（Room 无显式列默认，此处取 0 保证确定性）
    @LenientInt64<Defaults.ZeroInt64> public var time: Int64
    @LenientOptionalString public var variable: String?
    @LenientInt<Defaults.ZeroInt> public var originOrder: Int
    @LenientOptionalString public var chapterWordCountText: String?
    /// 列默认值 "-1"
    @LenientInt<MinusOneInt> public var chapterWordCount: Int
    /// 列默认值 "-1"
    @LenientInt<MinusOneInt> public var respondTime: Int

    // MARK: 运行时字段（对应 Kotlin @Ignore，不参与 Codable）
    public var infoHtml: String? = nil
    public var tocHtml: String? = nil

    // MARK: 默认值定义
    public enum TextTypeDefault: DefaultValueProvider { public static let defaultValue = BookType.text }
    public enum MinusOneInt: DefaultValueProvider { public static let defaultValue = -1 }

    // MARK: 构造器（默认值与 Kotlin 一致）

    public init(
        bookUrl: String = "",
        origin: String = "",
        originName: String = "",
        type: Int = BookType.text,
        name: String = "",
        author: String = "",
        kind: String? = nil,
        coverUrl: String? = nil,
        intro: String? = nil,
        wordCount: String? = nil,
        latestChapterTitle: String? = nil,
        tocUrl: String = "",
        time: Int64 = SearchBook.currentTimeMillis(),
        variable: String? = nil,
        originOrder: Int = 0,
        chapterWordCountText: String? = nil,
        chapterWordCount: Int = -1,
        respondTime: Int = -1
    ) {
        self._bookUrl = LenientString(wrappedValue: bookUrl)
        self._origin = LenientString(wrappedValue: origin)
        self._originName = LenientString(wrappedValue: originName)
        self._type = LenientInt(wrappedValue: type)
        self._name = LenientString(wrappedValue: name)
        self._author = LenientString(wrappedValue: author)
        self._kind = LenientOptionalString(wrappedValue: kind)
        self._coverUrl = LenientOptionalString(wrappedValue: coverUrl)
        self._intro = LenientOptionalString(wrappedValue: intro)
        self._wordCount = LenientOptionalString(wrappedValue: wordCount)
        self._latestChapterTitle = LenientOptionalString(wrappedValue: latestChapterTitle)
        self._tocUrl = LenientString(wrappedValue: tocUrl)
        self._time = LenientInt64(wrappedValue: time)
        self._variable = LenientOptionalString(wrappedValue: variable)
        self._originOrder = LenientInt(wrappedValue: originOrder)
        self._chapterWordCountText = LenientOptionalString(wrappedValue: chapterWordCountText)
        self._chapterWordCount = LenientInt(wrappedValue: chapterWordCount)
        self._respondTime = LenientInt(wrappedValue: respondTime)
    }

    public static func currentTimeMillis() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }

    // MARK: CodingKeys（仅持久化字段）

    public enum CodingKeys: String, CodingKey {
        case bookUrl
        case origin
        case originName
        case type
        case name
        case author
        case kind
        case coverUrl
        case intro
        case wordCount
        case latestChapterTitle
        case tocUrl
        case time
        case variable
        case originOrder
        case chapterWordCountText
        case chapterWordCount
        case respondTime
    }

    /// 对应 Kotlin getDisplayLastChapterTitle()
    public func getDisplayLastChapterTitle() -> String {
        if let it = latestChapterTitle, !it.isEmpty { return it }
        return "无最新章节"
    }

    /// 对应 Kotlin primaryStr()
    public func primaryStr() -> String { origin + bookUrl }

    // 对应 Kotlin Comparable：other.originOrder - this.originOrder。
    // Comparable 语义：compareTo < 0 表示 this 排在前。转成 Swift 的 < 运算符。
    public static func < (lhs: SearchBook, rhs: SearchBook) -> Bool {
        // Kotlin: this.compareTo(other) = other.originOrder - this.originOrder
        // 即当 other.originOrder > this.originOrder 时 this < other。
        return rhs.originOrder - lhs.originOrder < 0
    }

    // TODO(后续步骤): 移植 SearchBook 的业务方法（依赖运行时 / 其他实体 / 资源）：
    //   origins / addOrigin() / trimIntro() / releaseHtmlData()
    //   sameBookTypeLocal() / toBook() / variableMap 等
}

// 对应 Kotlin 自定义 equals / hashCode：仅以 bookUrl 判等。
extension SearchBook: Equatable, Hashable {
    public static func == (lhs: SearchBook, rhs: SearchBook) -> Bool { lhs.bookUrl == rhs.bookUrl }
    public func hash(into hasher: inout Hasher) { hasher.combine(bookUrl) }
}
