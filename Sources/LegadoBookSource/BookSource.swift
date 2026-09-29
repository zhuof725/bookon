//
//  BookSource.swift
//  LegadoBookSource
//
//  对应 Kotlin: data/entities/BookSource.kt
//
//  Kotlin 里 BookSource 同时是 Room @Entity + Parcelable + BaseSource，
//  并带有一批业务方法（getSearchRule()、addGroup()、equal() 等）以及
//  一个 Room TypeConverter 内部类 Converters（把各 Rule 与其 JSON 字符串互转）。
//
//  本步骤只做数据模型：
//    - 全部持久化字段一一对应，字段名 / JSON key 与 Kotlin 完全一致；
//    - 可空字段 -> Optional；有默认值字段 -> decodeIfPresent + 同样默认值；
//    - 六个规则字段（ruleSearch/ruleExplore/ruleBookInfo/ruleToc/ruleContent/ruleReview）
//      支持「对象」与「JSON 字符串」两种输入，编码统一输出为对象
//      （对应 Converters 的 stringToXxxRule / xxxRuleToString 思路）。
//    - 不移植持久化（Room）与运行时业务逻辑（后续步骤）。
//

import Foundation

public struct BookSource: Codable, BaseSource {

    // MARK: 持久化字段（顺序、名称与 Kotlin 保持一致）

    /// 地址，包括 http/https
    @LenientString<Defaults.EmptyString> public var bookSourceUrl: String
    /// 名称
    @LenientString<Defaults.EmptyString> public var bookSourceName: String
    /// 分组
    @LenientOptionalString public var bookSourceGroup: String?
    /// 类型，0 文本，1 音频, 2 图片, 3 文件（指的是类似知轩藏书只提供下载的网站）, 4 视频
    @LenientInt<Defaults.ZeroInt> public var bookSourceType: Int
    /// 详情页url正则
    @LenientOptionalString public var bookUrlPattern: String?
    /// 手动排序编号
    @LenientInt<Defaults.ZeroInt> public var customOrder: Int
    /// 是否启用
    @LenientBool<Defaults.TrueBool> public var enabled: Bool
    /// 启用发现
    @LenientBool<Defaults.TrueBool> public var enabledExplore: Bool
    /// js库
    @LenientOptionalString public var jsLib: String?
    /// 启用okhttp CookieJAr 自动保存每次请求的cookie
    /// 注意：Kotlin 声明为 Boolean? 且默认 true（列默认值为 "0"，构造默认值为 true）。
    @LenientOptionalBool public var enabledCookieJar: Bool?
    /// 并发率
    @LenientOptionalString public var concurrentRate: String?
    /// 请求头
    @LenientOptionalString public var header: String?
    /// 登录地址
    @LenientOptionalString public var loginUrl: String?
    /// 登录UI
    @LenientOptionalString public var loginUi: String?
    /// 登录检测js
    @LenientOptionalString public var loginCheckJs: String?
    /// 封面解密js
    @LenientOptionalString public var coverDecodeJs: String?
    /// 注释
    @LenientOptionalString public var bookSourceComment: String?
    /// 自定义变量说明
    @LenientOptionalString public var variableComment: String?
    /// 最后更新时间，用于排序
    @LenientInt64<Defaults.ZeroInt64> public var lastUpdateTime: Int64
    /// 响应时间，用于排序
    @LenientInt64<RespondTimeDefault> public var respondTime: Int64
    /// 智能排序的权重
    @LenientInt<Defaults.ZeroInt> public var weight: Int
    /// 发现url
    @LenientOptionalString public var exploreUrl: String?
    /// 发现筛选规则
    @LenientOptionalString public var exploreScreen: String?
    /// 发现规则
    @StringOrObject<ExploreRule> public var ruleExplore: ExploreRule?
    /// 搜索url
    @LenientOptionalString public var searchUrl: String?
    /// 搜索规则
    @StringOrObject<SearchRule> public var ruleSearch: SearchRule?
    /// 书籍信息页规则
    @StringOrObject<BookInfoRule> public var ruleBookInfo: BookInfoRule?
    /// 目录页规则
    @StringOrObject<TocRule> public var ruleToc: TocRule?
    /// 正文页规则
    @StringOrObject<ContentRule> public var ruleContent: ContentRule?
    /// 段评规则
    @StringOrObject<ReviewRule> public var ruleReview: ReviewRule?
    /// 是否监听事件来执行回调规则
    @LenientBool<Defaults.FalseBool> public var eventListener: Bool
    /// 由书源控制的自定义按钮
    @LenientBool<Defaults.FalseBool> public var customButton: Bool

    /// respondTime 的默认值：180000L
    public enum RespondTimeDefault: DefaultValueProvider { public static let defaultValue = Int64(180000) }

    // MARK: 构造器（默认值与 Kotlin 完全一致）

    public init(
        bookSourceUrl: String = "",
        bookSourceName: String = "",
        bookSourceGroup: String? = nil,
        bookSourceType: Int = 0,
        bookUrlPattern: String? = nil,
        customOrder: Int = 0,
        enabled: Bool = true,
        enabledExplore: Bool = true,
        jsLib: String? = nil,
        enabledCookieJar: Bool? = true,
        concurrentRate: String? = nil,
        header: String? = nil,
        loginUrl: String? = nil,
        loginUi: String? = nil,
        loginCheckJs: String? = nil,
        coverDecodeJs: String? = nil,
        bookSourceComment: String? = nil,
        variableComment: String? = nil,
        lastUpdateTime: Int64 = 0,
        respondTime: Int64 = 180000,
        weight: Int = 0,
        exploreUrl: String? = nil,
        exploreScreen: String? = nil,
        ruleExplore: ExploreRule? = nil,
        searchUrl: String? = nil,
        ruleSearch: SearchRule? = nil,
        ruleBookInfo: BookInfoRule? = nil,
        ruleToc: TocRule? = nil,
        ruleContent: ContentRule? = nil,
        ruleReview: ReviewRule? = nil,
        eventListener: Bool = false,
        customButton: Bool = false
    ) {
        self._bookSourceUrl = LenientString(wrappedValue: bookSourceUrl)
        self._bookSourceName = LenientString(wrappedValue: bookSourceName)
        self._bookSourceGroup = LenientOptionalString(wrappedValue: bookSourceGroup)
        self._bookSourceType = LenientInt(wrappedValue: bookSourceType)
        self._bookUrlPattern = LenientOptionalString(wrappedValue: bookUrlPattern)
        self._customOrder = LenientInt(wrappedValue: customOrder)
        self._enabled = LenientBool(wrappedValue: enabled)
        self._enabledExplore = LenientBool(wrappedValue: enabledExplore)
        self._jsLib = LenientOptionalString(wrappedValue: jsLib)
        self._enabledCookieJar = LenientOptionalBool(wrappedValue: enabledCookieJar)
        self._concurrentRate = LenientOptionalString(wrappedValue: concurrentRate)
        self._header = LenientOptionalString(wrappedValue: header)
        self._loginUrl = LenientOptionalString(wrappedValue: loginUrl)
        self._loginUi = LenientOptionalString(wrappedValue: loginUi)
        self._loginCheckJs = LenientOptionalString(wrappedValue: loginCheckJs)
        self._coverDecodeJs = LenientOptionalString(wrappedValue: coverDecodeJs)
        self._bookSourceComment = LenientOptionalString(wrappedValue: bookSourceComment)
        self._variableComment = LenientOptionalString(wrappedValue: variableComment)
        self._lastUpdateTime = LenientInt64(wrappedValue: lastUpdateTime)
        self._respondTime = LenientInt64(wrappedValue: respondTime)
        self._weight = LenientInt(wrappedValue: weight)
        self._exploreUrl = LenientOptionalString(wrappedValue: exploreUrl)
        self._exploreScreen = LenientOptionalString(wrappedValue: exploreScreen)
        self._ruleExplore = StringOrObject(wrappedValue: ruleExplore)
        self._searchUrl = LenientOptionalString(wrappedValue: searchUrl)
        self._ruleSearch = StringOrObject(wrappedValue: ruleSearch)
        self._ruleBookInfo = StringOrObject(wrappedValue: ruleBookInfo)
        self._ruleToc = StringOrObject(wrappedValue: ruleToc)
        self._ruleContent = StringOrObject(wrappedValue: ruleContent)
        self._ruleReview = StringOrObject(wrappedValue: ruleReview)
        self._eventListener = LenientBool(wrappedValue: eventListener)
        self._customButton = LenientBool(wrappedValue: customButton)
    }

    // MARK: CodingKeys（字段名与 JSON key 完全一致，不转 snake_case）

    public enum CodingKeys: String, CodingKey {
        case bookSourceUrl
        case bookSourceName
        case bookSourceGroup
        case bookSourceType
        case bookUrlPattern
        case customOrder
        case enabled
        case enabledExplore
        case jsLib
        case enabledCookieJar
        case concurrentRate
        case header
        case loginUrl
        case loginUi
        case loginCheckJs
        case coverDecodeJs
        case bookSourceComment
        case variableComment
        case lastUpdateTime
        case respondTime
        case weight
        case exploreUrl
        case exploreScreen
        case ruleExplore
        case searchUrl
        case ruleSearch
        case ruleBookInfo
        case ruleToc
        case ruleContent
        case ruleReview
        case eventListener
        case customButton
    }

    // MARK: 业务方法（数据模型层可自足实现的部分）

    /// 对应 Kotlin getTag()
    public func getTag() -> String { bookSourceName }

    /// 对应 Kotlin getKey()
    public func getKey() -> String { bookSourceUrl }

    /// 对应 Kotlin getSearchRule(): 空时创建并返回一个新的 SearchRule。
    /// Swift struct 是值类型，这里返回现有值或一个新建实例。
    public mutating func getSearchRule() -> SearchRule {
        if let r = ruleSearch { return r }
        let rule = SearchRule()
        ruleSearch = rule
        return rule
    }

    /// 对应 Kotlin getExploreRule()
    public mutating func getExploreRule() -> ExploreRule {
        if let r = ruleExplore { return r }
        let rule = ExploreRule()
        ruleExplore = rule
        return rule
    }

    /// 对应 Kotlin getBookInfoRule()
    public mutating func getBookInfoRule() -> BookInfoRule {
        if let r = ruleBookInfo { return r }
        let rule = BookInfoRule()
        ruleBookInfo = rule
        return rule
    }

    /// 对应 Kotlin getTocRule()
    public mutating func getTocRule() -> TocRule {
        if let r = ruleToc { return r }
        let rule = TocRule()
        ruleToc = rule
        return rule
    }

    /// 对应 Kotlin getContentRule()
    public mutating func getContentRule() -> ContentRule {
        if let r = ruleContent { return r }
        let rule = ContentRule()
        ruleContent = rule
        return rule
    }

    // 注意：Kotlin 中 getReviewRule() 被注释掉了，这里也不实现。

    /// 对应 Kotlin getDisPlayNameGroup()
    public func getDisPlayNameGroup() -> String {
        if bookSourceGroup?.isEmpty ?? true || (bookSourceGroup?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
            return bookSourceName
        } else {
            return String(format: "%@ (%@)", bookSourceName, bookSourceGroup ?? "")
        }
    }

    /// 对应 Kotlin getCheckKeyword(default:)
    public func getCheckKeyword(_ defaultValue: String) -> String {
        if let it = ruleSearch?.checkKeyWord,
           !it.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !it.contains("http"),
           !it.contains("::"),
           !it.contains("++"),
           !it.contains("--") {
            return it
        }
        return defaultValue
    }

    /// 对应 Kotlin getDisplayVariableComment(otherComment:)
    public func getDisplayVariableComment(_ otherComment: String) -> String {
        if variableComment?.isEmpty ?? true || (variableComment?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
            return otherComment
        } else {
            return "\(variableComment ?? "")\n\(otherComment)"
        }
    }

    // TODO(后续步骤): 以下 Kotlin 业务方法涉及分组正则拆分 / 数据库 / 错误注释等，
    //   与「数据模型」关系不大或依赖运行时，暂不移植，待后续需要时补齐：
    //     addGroup(groups:) / removeGroup(groups:) / hasGroup(group:)
    //     removeInvalidGroups() / getInvalidGroupNames()
    //     removeErrorComment() / addErrorComment(e:)
    //     equal(source:)  — 逐字段比较
}

// 对应 Kotlin 自定义 equals / hashCode：仅以 bookSourceUrl 判等。
extension BookSource: Equatable, Hashable {
    public static func == (lhs: BookSource, rhs: BookSource) -> Bool {
        lhs.bookSourceUrl == rhs.bookSourceUrl
    }
    public func hash(into hasher: inout Hasher) {
        hasher.combine(bookSourceUrl)
    }
}
