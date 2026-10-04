//
//  Book.swift
//  LegadoBookSource
//
//  对应 Kotlin: data/entities/Book.kt
//
//  Kotlin 里 Book 是 Room @Entity + Parcelable + BaseBook，含大量业务方法
//  （阅读配置读写、迁移、书签、目录字数计算、与 SearchBook/ReplaceBook 互转等）
//  以及内嵌的 ReadConfig 数据类和 Room Converters。
//
//  本步骤只做数据模型：
//    - 持久化字段一一对应，字段名 / JSON key 与 Kotlin 完全一致；
//    - 有默认值字段用 decodeIfPresent + 同样默认值；可空字段 -> Optional；
//    - @Ignore 运行时字段（infoHtml/tocHtml/downloadUrls/folderName）不参与 Codable；
//    - readConfig 内嵌对象照常 Codable。
//    - 不移植业务方法与持久化（Room），保持纯数据结构。
//
//  关于时间默认值：Kotlin 构造器默认用 System.currentTimeMillis()，
//  但 Room 列默认值（@ColumnInfo defaultValue = "0"）为 "0"。
//  为保证 decode 的确定性与「JSON 缺字段不报错」，本移植在「JSON 缺字段」时
//  采用列默认值 0（与数据库落库语义一致）。若需要构造新书时用当前时间，
//  可显式传入 Date().millisecondsSince1970。
//

import Foundation

public struct Book: Codable, BaseBook {

    // MARK: 持久化字段

    /// 详情页Url(本地书源存储完整文件路径)
    @LenientString<Defaults.EmptyString> public var bookUrl: String
    /// 目录页Url (toc=table of Contents)
    @LenientString<Defaults.EmptyString> public var tocUrl: String
    /// 书源URL(默认BookType.localTag)
    @LenientString<LocalTagDefault> public var origin: String
    /// 书源名称 or 本地书籍文件名
    @LenientString<Defaults.EmptyString> public var originName: String
    /// 书籍名称(书源获取)
    @LenientString<Defaults.EmptyString> public var name: String
    /// 作者名称(书源获取)
    @LenientString<Defaults.EmptyString> public var author: String
    /// 分类信息(书源获取)
    @LenientOptionalString public var kind: String?
    /// 分类信息(用户修改)
    @LenientOptionalString public var customTag: String?
    /// 封面Url(书源获取)
    @LenientOptionalString public var coverUrl: String?
    /// 封面Url(用户修改)
    @LenientOptionalString public var customCoverUrl: String?
    /// 简介内容(书源获取)
    @LenientOptionalString public var intro: String?
    /// 简介内容(用户修改)
    @LenientOptionalString public var customIntro: String?
    /// 自定义字符集名称(仅适用于本地书籍)
    @LenientOptionalString public var charset: String?
    /// 类型,详见BookType
    @LenientInt<TextTypeDefault> public var type: Int
    /// 自定义分组索引号
    @LenientInt64<Defaults.ZeroInt64> public var group: Int64
    /// 最新章节标题
    @LenientOptionalString public var latestChapterTitle: String?
    /// 最新章节标题更新时间（构造默认 currentTimeMillis；列默认 "0"，缺字段用 0）
    @LenientInt64<Defaults.ZeroInt64> public var latestChapterTime: Int64
    /// 最近一次更新书籍信息的时间（同上）
    @LenientInt64<Defaults.ZeroInt64> public var lastCheckTime: Int64
    /// 最近一次发现新章节的数量
    @LenientInt<Defaults.ZeroInt> public var lastCheckCount: Int
    /// 书籍目录总数
    @LenientInt<Defaults.ZeroInt> public var totalChapterNum: Int
    /// 当前章节名称
    @LenientOptionalString public var durChapterTitle: String?
    /// 当前章节索引
    @LenientInt<Defaults.ZeroInt> public var durChapterIndex: Int
    /// 当前卷索引
    @LenientInt<Defaults.ZeroInt> public var durVolumeIndex: Int
    /// 相对于卷的索引
    @LenientInt<Defaults.ZeroInt> public var chapterInVolumeIndex: Int
    /// 当前阅读的进度(首行字符的索引位置)
    @LenientInt<Defaults.ZeroInt> public var durChapterPos: Int
    /// 最近一次阅读书籍的时间(打开正文的时间)（构造默认 currentTimeMillis；列默认 "0"）
    @LenientInt64<Defaults.ZeroInt64> public var durChapterTime: Int64
    /// 字数
    @LenientOptionalString public var wordCount: String?
    /// 刷新书架时更新书籍信息
    @LenientBool<Defaults.TrueBool> public var canUpdate: Bool
    /// 手动排序
    @LenientInt<Defaults.ZeroInt> public var order: Int
    /// 书源排序
    @LenientInt<Defaults.ZeroInt> public var originOrder: Int
    /// 自定义书籍变量信息(用于书源规则检索书籍信息)
    @LenientOptionalString public var variable: String?
    /// 阅读设置
    public var readConfig: ReadConfig?
    /// 同步时间
    @LenientInt64<Defaults.ZeroInt64> public var syncTime: Int64

    // MARK: 运行时字段（对应 Kotlin @Ignore / @IgnoredOnParcel，不参与 Codable）

    /// 对应 Kotlin @Ignore infoHtml
    public var infoHtml: String? = nil
    /// 对应 Kotlin @Ignore tocHtml
    public var tocHtml: String? = nil
    /// 对应 Kotlin @Ignore downloadUrls
    public var downloadUrls: [String]? = nil

    // MARK: 默认值定义

    /// origin 默认值 BookType.localTag = "loc_book"
    public enum LocalTagDefault: DefaultValueProvider { public static let defaultValue = BookType.localTag }
    /// type 默认值 BookType.text
    public enum TextTypeDefault: DefaultValueProvider { public static let defaultValue = BookType.text }

    // MARK: 构造器（默认值与 Kotlin 一致；时间字段默认用当前毫秒时间戳）

    public init(
        bookUrl: String = "",
        tocUrl: String = "",
        origin: String = BookType.localTag,
        originName: String = "",
        name: String = "",
        author: String = "",
        kind: String? = nil,
        customTag: String? = nil,
        coverUrl: String? = nil,
        customCoverUrl: String? = nil,
        intro: String? = nil,
        customIntro: String? = nil,
        charset: String? = nil,
        type: Int = BookType.text,
        group: Int64 = 0,
        latestChapterTitle: String? = nil,
        latestChapterTime: Int64 = Book.currentTimeMillis(),
        lastCheckTime: Int64 = Book.currentTimeMillis(),
        lastCheckCount: Int = 0,
        totalChapterNum: Int = 0,
        durChapterTitle: String? = nil,
        durChapterIndex: Int = 0,
        durVolumeIndex: Int = 0,
        chapterInVolumeIndex: Int = 0,
        durChapterPos: Int = 0,
        durChapterTime: Int64 = Book.currentTimeMillis(),
        wordCount: String? = nil,
        canUpdate: Bool = true,
        order: Int = 0,
        originOrder: Int = 0,
        variable: String? = nil,
        readConfig: ReadConfig? = nil,
        syncTime: Int64 = 0
    ) {
        self._bookUrl = LenientString(wrappedValue: bookUrl)
        self._tocUrl = LenientString(wrappedValue: tocUrl)
        self._origin = LenientString(wrappedValue: origin)
        self._originName = LenientString(wrappedValue: originName)
        self._name = LenientString(wrappedValue: name)
        self._author = LenientString(wrappedValue: author)
        self._kind = LenientOptionalString(wrappedValue: kind)
        self._customTag = LenientOptionalString(wrappedValue: customTag)
        self._coverUrl = LenientOptionalString(wrappedValue: coverUrl)
        self._customCoverUrl = LenientOptionalString(wrappedValue: customCoverUrl)
        self._intro = LenientOptionalString(wrappedValue: intro)
        self._customIntro = LenientOptionalString(wrappedValue: customIntro)
        self._charset = LenientOptionalString(wrappedValue: charset)
        self._type = LenientInt(wrappedValue: type)
        self._group = LenientInt64(wrappedValue: group)
        self._latestChapterTitle = LenientOptionalString(wrappedValue: latestChapterTitle)
        self._latestChapterTime = LenientInt64(wrappedValue: latestChapterTime)
        self._lastCheckTime = LenientInt64(wrappedValue: lastCheckTime)
        self._lastCheckCount = LenientInt(wrappedValue: lastCheckCount)
        self._totalChapterNum = LenientInt(wrappedValue: totalChapterNum)
        self._durChapterTitle = LenientOptionalString(wrappedValue: durChapterTitle)
        self._durChapterIndex = LenientInt(wrappedValue: durChapterIndex)
        self._durVolumeIndex = LenientInt(wrappedValue: durVolumeIndex)
        self._chapterInVolumeIndex = LenientInt(wrappedValue: chapterInVolumeIndex)
        self._durChapterPos = LenientInt(wrappedValue: durChapterPos)
        self._durChapterTime = LenientInt64(wrappedValue: durChapterTime)
        self._wordCount = LenientOptionalString(wrappedValue: wordCount)
        self._canUpdate = LenientBool(wrappedValue: canUpdate)
        self._order = LenientInt(wrappedValue: order)
        self._originOrder = LenientInt(wrappedValue: originOrder)
        self._variable = LenientOptionalString(wrappedValue: variable)
        self.readConfig = readConfig
        self._syncTime = LenientInt64(wrappedValue: syncTime)
    }

    public static func currentTimeMillis() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }

    // MARK: CodingKeys（仅持久化字段；运行时字段不编码）

    public enum CodingKeys: String, CodingKey {
        case bookUrl
        case tocUrl
        case origin
        case originName
        case name
        case author
        case kind
        case customTag
        case coverUrl
        case customCoverUrl
        case intro
        case customIntro
        case charset
        case type
        case group
        case latestChapterTitle
        case latestChapterTime
        case lastCheckTime
        case lastCheckCount
        case totalChapterNum
        case durChapterTitle
        case durChapterIndex
        case durVolumeIndex
        case chapterInVolumeIndex
        case durChapterPos
        case durChapterTime
        case wordCount
        case canUpdate
        case order
        case originOrder
        case variable
        case readConfig
        case syncTime
    }

    // MARK: 内嵌 ReadConfig（对应 Kotlin Book.ReadConfig）

    /// 阅读设置。对应 Kotlin data class Book.ReadConfig。
    public struct ReadConfig: Codable, Equatable {
        public var reverseToc: Bool                // 默认 false
        public var pageAnim: Int?                  // 默认 null
        public var reSegment: Bool                 // 默认 false
        public var imageStyle: String?             // 默认 null
        /// 正文使用净化替换规则
        public var useReplaceRule: Bool?           // 默认 null
        /// 去除标签
        public var delTag: Int64                   // 默认 0L
        public var ttsEngine: String?              // 默认 null
        public var splitLongChapter: Bool          // 默认 true
        public var readSimulating: Bool            // 默认 false
        /// TODO: Kotlin 为 java.time.LocalDate?，JSON 序列化格式依赖 Gson 的 LocalDate 适配器；
        ///   本移植暂以 String? 承载其原始 JSON 表示，避免猜测日期格式。待确认存储格式后再改为强类型。
        public var startDate: String?              // 默认 null
        /// 用户设置的起始章节
        public var startChapter: Int?              // 默认 null
        /// 用户设置的每日更新章节数
        public var dailyChapters: Int              // 默认 3
        /// 音频片头
        public var openCredits: Int                // 默认 0
        /// 音频片尾
        public var closeCredits: Int               // 默认 0
        /// 音频播放模式
        public var playMode: Int                   // 默认 0
        /// 音频播放速度
        public var playSpeed: Float                // 默认 1.0f

        public init(
            reverseToc: Bool = false,
            pageAnim: Int? = nil,
            reSegment: Bool = false,
            imageStyle: String? = nil,
            useReplaceRule: Bool? = nil,
            delTag: Int64 = 0,
            ttsEngine: String? = nil,
            splitLongChapter: Bool = true,
            readSimulating: Bool = false,
            startDate: String? = nil,
            startChapter: Int? = nil,
            dailyChapters: Int = 3,
            openCredits: Int = 0,
            closeCredits: Int = 0,
            playMode: Int = 0,
            playSpeed: Float = 1.0
        ) {
            self.reverseToc = reverseToc
            self.pageAnim = pageAnim
            self.reSegment = reSegment
            self.imageStyle = imageStyle
            self.useReplaceRule = useReplaceRule
            self.delTag = delTag
            self.ttsEngine = ttsEngine
            self.splitLongChapter = splitLongChapter
            self.readSimulating = readSimulating
            self.startDate = startDate
            self.startChapter = startChapter
            self.dailyChapters = dailyChapters
            self.openCredits = openCredits
            self.closeCredits = closeCredits
            self.playMode = playMode
            self.playSpeed = playSpeed
        }

        enum CodingKeys: String, CodingKey {
            case reverseToc
            case pageAnim
            case reSegment
            case imageStyle
            case useReplaceRule
            case delTag
            case ttsEngine
            case splitLongChapter
            case readSimulating
            case startDate
            case startChapter
            case dailyChapters
            case openCredits
            case closeCredits
            case playMode
            case playSpeed
        }

        // 缺字段用同样默认值。
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.reverseToc = try c.decodeIfPresent(Bool.self, forKey: .reverseToc) ?? false
            self.pageAnim = try c.decodeIfPresent(Int.self, forKey: .pageAnim)
            self.reSegment = try c.decodeIfPresent(Bool.self, forKey: .reSegment) ?? false
            self.imageStyle = try c.decodeIfPresent(String.self, forKey: .imageStyle)
            self.useReplaceRule = try c.decodeIfPresent(Bool.self, forKey: .useReplaceRule)
            self.delTag = try c.decodeIfPresent(Int64.self, forKey: .delTag) ?? 0
            self.ttsEngine = try c.decodeIfPresent(String.self, forKey: .ttsEngine)
            self.splitLongChapter = try c.decodeIfPresent(Bool.self, forKey: .splitLongChapter) ?? true
            self.readSimulating = try c.decodeIfPresent(Bool.self, forKey: .readSimulating) ?? false
            self.startDate = try c.decodeIfPresent(String.self, forKey: .startDate)
            self.startChapter = try c.decodeIfPresent(Int.self, forKey: .startChapter)
            self.dailyChapters = try c.decodeIfPresent(Int.self, forKey: .dailyChapters) ?? 3
            self.openCredits = try c.decodeIfPresent(Int.self, forKey: .openCredits) ?? 0
            self.closeCredits = try c.decodeIfPresent(Int.self, forKey: .closeCredits) ?? 0
            self.playMode = try c.decodeIfPresent(Int.self, forKey: .playMode) ?? 0
            self.playSpeed = try c.decodeIfPresent(Float.self, forKey: .playSpeed) ?? 1.0
        }
    }

    // MARK: companion object 常量（对应 Kotlin Book.companion）
    public enum Const {
        public static let hTag: Int64 = 2
        public static let rubyTag: Int64 = 4
        public static let imgStyleDefault = "DEFAULT"
        public static let imgStyleFull = "FULL"
        public static let imgStyleText = "TEXT"
        public static let imgStyleSingle = "SINGLE"
    }

    // TODO(后续步骤): 移植 Book 的业务方法（依赖运行时 / 其他实体 / DB）：
    //   getRealAuthor() / getUnreadChapterNum() / getDisplayCover() / getDisplayIntro()
    //   fileCharset() / config 及一系列 get/set(ReadConfig 各项)
    //   toSearchBook() / toReplaceBook() / migrateTo() / createBookMark()
    //   save() / delete() / getFolderName() / variableMap 等
}

// 对应 Kotlin 自定义 equals / hashCode：仅以 bookUrl 判等。
extension Book: Equatable, Hashable {
    public static func == (lhs: Book, rhs: Book) -> Bool { lhs.bookUrl == rhs.bookUrl }
    public func hash(into hasher: inout Hasher) { hasher.combine(bookUrl) }
}
