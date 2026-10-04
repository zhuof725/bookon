//
//  BookChapter.swift
//  LegadoBookSource
//
//  对应 Kotlin: data/entities/BookChapter.kt
//
//  Kotlin 里 BookChapter 是 Room @Entity + Parcelable + RuleDataInterface，含
//  变量存取、标题替换、绝对 URL 拼接、文件名生成等业务方法。
//  本步骤只做数据模型：持久化字段一一对应；@Ignore 运行时字段（titleMD5）不参与 Codable；
//  业务方法留待后续步骤。
//

import Foundation

public struct BookChapter: Codable {

    // MARK: 持久化字段

    /// 章节地址
    @LenientString<Defaults.EmptyString> public var url: String
    /// 章节标题
    @LenientString<Defaults.EmptyString> public var title: String
    /// 是否是卷名
    @LenientBool<Defaults.FalseBool> public var isVolume: Bool
    /// 用来拼接相对url
    @LenientString<Defaults.EmptyString> public var baseUrl: String
    /// 书籍地址
    @LenientString<Defaults.EmptyString> public var bookUrl: String
    /// 章节序号
    @LenientInt<Defaults.ZeroInt> public var index: Int
    /// 是否VIP
    @LenientBool<Defaults.FalseBool> public var isVip: Bool
    /// 是否已购买
    @LenientBool<Defaults.FalseBool> public var isPay: Bool
    /// 音频真实URL
    @LenientOptionalString public var resourceUrl: String?
    /// 更新时间或其他章节附加信息
    @LenientOptionalString public var tag: String?
    /// 本章节字数
    @LenientOptionalString public var wordCount: String?
    /// 章节起始位置
    @LenientOptionalInt64 public var start: Int64?
    /// 章节终止位置
    @LenientOptionalInt64 public var end: Int64?
    /// EPUB书籍当前章节的fragmentId
    @LenientOptionalString public var startFragmentId: String?
    /// EPUB书籍下一章节的fragmentId
    @LenientOptionalString public var endFragmentId: String?
    /// 变量
    @LenientOptionalString public var variable: String?
    /// 标题段评图或者视频封面
    @LenientOptionalString public var imgUrl: String?

    // MARK: 运行时字段（对应 Kotlin @Ignore titleMD5，不参与 Codable）
    public var titleMD5: String? = nil

    // MARK: 构造器（默认值与 Kotlin 一致）

    public init(
        url: String = "",
        title: String = "",
        isVolume: Bool = false,
        baseUrl: String = "",
        bookUrl: String = "",
        index: Int = 0,
        isVip: Bool = false,
        isPay: Bool = false,
        resourceUrl: String? = nil,
        tag: String? = nil,
        wordCount: String? = nil,
        start: Int64? = nil,
        end: Int64? = nil,
        startFragmentId: String? = nil,
        endFragmentId: String? = nil,
        variable: String? = nil,
        imgUrl: String? = nil
    ) {
        self._url = LenientString(wrappedValue: url)
        self._title = LenientString(wrappedValue: title)
        self._isVolume = LenientBool(wrappedValue: isVolume)
        self._baseUrl = LenientString(wrappedValue: baseUrl)
        self._bookUrl = LenientString(wrappedValue: bookUrl)
        self._index = LenientInt(wrappedValue: index)
        self._isVip = LenientBool(wrappedValue: isVip)
        self._isPay = LenientBool(wrappedValue: isPay)
        self._resourceUrl = LenientOptionalString(wrappedValue: resourceUrl)
        self._tag = LenientOptionalString(wrappedValue: tag)
        self._wordCount = LenientOptionalString(wrappedValue: wordCount)
        self._start = LenientOptionalInt64(wrappedValue: start)
        self._end = LenientOptionalInt64(wrappedValue: end)
        self._startFragmentId = LenientOptionalString(wrappedValue: startFragmentId)
        self._endFragmentId = LenientOptionalString(wrappedValue: endFragmentId)
        self._variable = LenientOptionalString(wrappedValue: variable)
        self._imgUrl = LenientOptionalString(wrappedValue: imgUrl)
    }

    // MARK: CodingKeys（仅持久化字段）

    public enum CodingKeys: String, CodingKey {
        case url
        case title
        case isVolume
        case baseUrl
        case bookUrl
        case index
        case isVip
        case isPay
        case resourceUrl
        case tag
        case wordCount
        case start
        case end
        case startFragmentId
        case endFragmentId
        case variable
        case imgUrl
    }

    /// 对应 Kotlin primaryStr()
    public func primaryStr() -> String { bookUrl + url }

    // TODO(后续步骤): 移植 BookChapter 的业务方法（依赖运行时 / DB / 正则）：
    //   putImgUrl() / putLyric() / putDanmaku() / update()
    //   putVariable() / putBigVariable() / getBigVariable() / variableMap
    //   getDisplayTitle() / getAbsoluteURL() / getFileName() / getFontName()
}

// 对应 Kotlin 自定义 equals / hashCode：仅以 url 判等。
extension BookChapter: Equatable, Hashable {
    public static func == (lhs: BookChapter, rhs: BookChapter) -> Bool { lhs.url == rhs.url }
    public func hash(into hasher: inout Hasher) { hasher.combine(url) }
}
