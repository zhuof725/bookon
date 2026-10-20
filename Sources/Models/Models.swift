import Foundation

// MARK: - Legado-compatible BookSource JSON

struct SearchRule: Codable, Hashable {
    var checkKeyWord: String?
    var bookList: String?
    var name: String?
    var author: String?
    var intro: String?
    var kind: String?
    var lastChapter: String?
    var updateTime: String?
    var bookUrl: String?
    var coverUrl: String?
    var wordCount: String?
}

struct BookInfoRule: Codable, Hashable {
    var `init`: String?
    var name: String?
    var author: String?
    var intro: String?
    var kind: String?
    var lastChapter: String?
    var updateTime: String?
    var coverUrl: String?
    var tocUrl: String?
    var wordCount: String?
    var canReName: String?
    var downloadUrls: String?
}

struct TocRule: Codable, Hashable {
    var preUpdateJs: String?
    var chapterList: String?
    var chapterName: String?
    var chapterUrl: String?
    var formatJs: String?
    var isVolume: String?
    var isVip: String?
    var isPay: String?
    var updateTime: String?
    var nextTocUrl: String?
}

struct ContentRule: Codable, Hashable {
    var content: String?
    var title: String?
    var nextContentUrl: String?
    var webJs: String?
    var sourceRegex: String?
    var replaceRegex: String?
    var imageStyle: String?
    var imageDecode: String?
    /// 部分书源（含聚合源）用于付费/子内容请求的附加规则。
    var subContent: String?
    var payAction: String?
    var callBackJs: String?
}

/// 段评规则（原版 ReviewRule）。字段全部保留；引擎目前只读 reviewUrl 等常用项。
struct ReviewRule: Codable, Hashable {
    var reviewUrl: String?
    var avatarRule: String?
    var contentRule: String?
    var postTimeRule: String?
    var reviewQuoteUrl: String?
    var voteUpUrl: String?
    var voteDownUrl: String?
    var postReviewUrl: String?
    var postQuoteUrl: String?
    var deleteUrl: String?
    var enabled: Bool?
    var reviewSummaryUrl: String?
    var summaryListRule: String?
    var summaryParagraphIndexRule: String?
    var summaryParagraphDataRule: String?
    var summaryCountRule: String?
    var reviewDetailUrl: String?
    var reviewDetailNextPageUrl: String?
    var detailListRule: String?
    var detailIdRule: String?
    var detailAvatarRule: String?
    var detailNameRule: String?
    var detailBadgeRule: String?
    var detailContentRule: String?
    var replyListRule: String?
    var replyIdRule: String?
    var replyAvatarRule: String?
    var replyNameRule: String?
    var replyBadgeRule: String?
    var replyContentRule: String?
}

struct BookSource: Codable, Hashable, Identifiable {
    var id: String { bookSourceUrl }
    var bookSourceUrl: String
    var bookSourceName: String
    var bookSourceGroup: String?
    var bookSourceType: Int?
    var bookSourceComment: String?
    var enabled: Bool?
    var header: String?
    var jsLib: String?
    var loginUrl: String?
    var loginUi: String?
    var searchUrl: String?
    var exploreUrl: String?
    var bookUrlPattern: String?
    /// Legado enabledCookieJar：nil 视为开启（与原版 BookSource 默认值一致）。
    var enabledCookieJar: Bool?
    var ruleSearch: SearchRule?
    var ruleExplore: SearchRule?
    var ruleBookInfo: BookInfoRule?
    var ruleToc: TocRule?
    var ruleContent: ContentRule?
    var customOrder: Int?
    var lastUpdateTime: Int64?
    /// 校验书源（批量测试）测得的耗时毫秒，与原版 BookSource.respondTime 一致。
    var respondTime: Int?
    /// 智能排序权重（原版 BookSource.weight）。
    var weight: Int?
    /// 阅读 Sigma 等分支的存储类型字段（实测是整数，0 表示默认）。
    var storageKind: Int?
    /// 段评规则（原版 BookSource.ruleReview）。
    var ruleReview: ReviewRule?
    /// 纯 JS 单文件书源主脚本（原版 BookSource.mainJs）。
    var mainJs: String?
    // 以下字段本应用暂未使用，但必须保留，编辑/导出时才不会丢失原书源内容（与原版字段同名）。
    var loginCheckJs: String?
    var coverDecodeJs: String?
    var variableComment: String?
    var concurrentRate: String?
    var exploreScreen: String?
    var enabledExplore: Bool?
    var eventListener: Bool?
    var customButton: Bool?
    /// 未在 CodingKeys 中建模的字段，导入时原样保存、导出时原样写回。
    var unknownFields: [String: JSONValue] = [:]

    var isEnabled: Bool { enabled ?? true }
    var cookieJarEnabled: Bool { enabledCookieJar ?? true }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case bookSourceUrl, bookSourceName, bookSourceGroup, bookSourceType, bookSourceComment
        case enabled, header, jsLib, loginUrl, loginUi, searchUrl, exploreUrl, bookUrlPattern, enabledCookieJar
        case ruleSearch, ruleExplore, ruleBookInfo, ruleToc, ruleContent, customOrder, lastUpdateTime
        case respondTime, weight, storageKind, ruleReview, mainJs
        case loginCheckJs, coverDecodeJs, variableComment, concurrentRate, exploreScreen
        case enabledExplore, eventListener, customButton
    }

    static let knownKeys = Set(CodingKeys.allCases.map(\.stringValue))

    /// 新建书源用：其余字段为空，由书源编辑页填写。
    init(bookSourceUrl: String, bookSourceName: String) {
        self.bookSourceUrl = bookSourceUrl
        self.bookSourceName = bookSourceName
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bookSourceUrl = (try? c.decode(String.self, forKey: .bookSourceUrl)) ?? ""
        bookSourceName = (try? c.decode(String.self, forKey: .bookSourceName)) ?? bookSourceUrl
        bookSourceGroup = try? c.decodeIfPresent(String.self, forKey: .bookSourceGroup)
        bookSourceType = try? c.decodeIfPresent(Int.self, forKey: .bookSourceType)
        bookSourceComment = try? c.decodeIfPresent(String.self, forKey: .bookSourceComment)
        enabled = try? c.decodeIfPresent(Bool.self, forKey: .enabled)
        header = try? c.decodeIfPresent(String.self, forKey: .header)
        jsLib = try? c.decodeIfPresent(String.self, forKey: .jsLib)
        loginUrl = try? c.decodeIfPresent(String.self, forKey: .loginUrl)
        loginUi = try? c.decodeIfPresent(String.self, forKey: .loginUi)
        searchUrl = try? c.decodeIfPresent(String.self, forKey: .searchUrl)
        exploreUrl = try? c.decodeIfPresent(String.self, forKey: .exploreUrl)
        bookUrlPattern = try? c.decodeIfPresent(String.self, forKey: .bookUrlPattern)
        enabledCookieJar = try? c.decodeIfPresent(Bool.self, forKey: .enabledCookieJar)
        ruleSearch = BookSource.lenient(c, .ruleSearch)
        ruleExplore = BookSource.lenient(c, .ruleExplore)
        ruleBookInfo = BookSource.lenient(c, .ruleBookInfo)
        ruleToc = BookSource.lenient(c, .ruleToc)
        ruleContent = BookSource.lenient(c, .ruleContent)
        customOrder = try? c.decodeIfPresent(Int.self, forKey: .customOrder)
        lastUpdateTime = try? c.decodeIfPresent(Int64.self, forKey: .lastUpdateTime)
        respondTime = try? c.decodeIfPresent(Int.self, forKey: .respondTime)
        weight = try? c.decodeIfPresent(Int.self, forKey: .weight)
        storageKind = try? c.decodeIfPresent(Int.self, forKey: .storageKind)
        ruleReview = BookSource.lenient(c, .ruleReview)
        mainJs = try? c.decodeIfPresent(String.self, forKey: .mainJs)
        loginCheckJs = try? c.decodeIfPresent(String.self, forKey: .loginCheckJs)
        coverDecodeJs = try? c.decodeIfPresent(String.self, forKey: .coverDecodeJs)
        variableComment = try? c.decodeIfPresent(String.self, forKey: .variableComment)
        concurrentRate = try? c.decodeIfPresent(String.self, forKey: .concurrentRate)
        exploreScreen = try? c.decodeIfPresent(String.self, forKey: .exploreScreen)
        enabledExplore = try? c.decodeIfPresent(Bool.self, forKey: .enabledExplore)
        eventListener = try? c.decodeIfPresent(Bool.self, forKey: .eventListener)
        customButton = try? c.decodeIfPresent(Bool.self, forKey: .customButton)
        // CodingKeys 容器的 allKeys 只会给出已声明的键，必须另开一个动态键容器才能看到未知字段。
        var unknown: [String: JSONValue] = [:]
        if let raw = try? decoder.container(keyedBy: AnyCodingKey.self) {
            for key in raw.allKeys where !BookSource.knownKeys.contains(key.stringValue) {
                if let value = try? raw.decode(JSONValue.self, forKey: key) {
                    unknown[key.stringValue] = value
                }
            }
        }
        unknownFields = unknown
    }

    /// 原样写回已知字段 + 未识别字段；编辑/导出不再丢 weight、storageKind、ruleReview 之外的扩展字段。
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(bookSourceUrl, forKey: .bookSourceUrl)
        try c.encode(bookSourceName, forKey: .bookSourceName)
        try c.encodeIfPresent(bookSourceGroup, forKey: .bookSourceGroup)
        try c.encodeIfPresent(bookSourceType, forKey: .bookSourceType)
        try c.encodeIfPresent(bookSourceComment, forKey: .bookSourceComment)
        try c.encodeIfPresent(enabled, forKey: .enabled)
        try c.encodeIfPresent(header, forKey: .header)
        try c.encodeIfPresent(jsLib, forKey: .jsLib)
        try c.encodeIfPresent(loginUrl, forKey: .loginUrl)
        try c.encodeIfPresent(loginUi, forKey: .loginUi)
        try c.encodeIfPresent(searchUrl, forKey: .searchUrl)
        try c.encodeIfPresent(exploreUrl, forKey: .exploreUrl)
        try c.encodeIfPresent(bookUrlPattern, forKey: .bookUrlPattern)
        try c.encodeIfPresent(enabledCookieJar, forKey: .enabledCookieJar)
        try c.encodeIfPresent(ruleSearch, forKey: .ruleSearch)
        try c.encodeIfPresent(ruleExplore, forKey: .ruleExplore)
        try c.encodeIfPresent(ruleBookInfo, forKey: .ruleBookInfo)
        try c.encodeIfPresent(ruleToc, forKey: .ruleToc)
        try c.encodeIfPresent(ruleContent, forKey: .ruleContent)
        try c.encodeIfPresent(customOrder, forKey: .customOrder)
        try c.encodeIfPresent(lastUpdateTime, forKey: .lastUpdateTime)
        try c.encodeIfPresent(respondTime, forKey: .respondTime)
        try c.encodeIfPresent(weight, forKey: .weight)
        try c.encodeIfPresent(storageKind, forKey: .storageKind)
        try c.encodeIfPresent(ruleReview, forKey: .ruleReview)
        try c.encodeIfPresent(mainJs, forKey: .mainJs)
        try c.encodeIfPresent(loginCheckJs, forKey: .loginCheckJs)
        try c.encodeIfPresent(coverDecodeJs, forKey: .coverDecodeJs)
        try c.encodeIfPresent(variableComment, forKey: .variableComment)
        try c.encodeIfPresent(concurrentRate, forKey: .concurrentRate)
        try c.encodeIfPresent(exploreScreen, forKey: .exploreScreen)
        try c.encodeIfPresent(enabledExplore, forKey: .enabledExplore)
        try c.encodeIfPresent(eventListener, forKey: .eventListener)
        try c.encodeIfPresent(customButton, forKey: .customButton)
        var dynamic = encoder.container(keyedBy: AnyCodingKey.self)
        for (key, value) in unknownFields where !BookSource.knownKeys.contains(key) {
            try dynamic.encode(value, forKey: AnyCodingKey(key))
        }
    }

    /// Some old sources store rule objects as JSON strings.
    private static func lenient<T: Decodable>(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> T? {
        if let v = try? c.decodeIfPresent(T.self, forKey: key) { return v }
        if let s = try? c.decodeIfPresent(String.self, forKey: key), let d = s.data(using: .utf8) {
            return try? JSONDecoder().decode(T.self, from: d)
        }
        return nil
    }
}

// MARK: - Book / Chapter

struct Book: Codable, Hashable, Identifiable {
    var id: String { bookUrl }
    var bookUrl: String
    var name: String
    var author: String = ""
    var intro: String?
    var kind: String?
    var coverUrl: String?
    var lastChapter: String?
    var wordCount: String?
    var tocUrl: String?
    var origin: String          // bookSourceUrl
    var originName: String = ""
    var durChapterIndex: Int = 0
    var durChapterPos: Int = 0
    var durChapterTitle: String?
    var addedAt: Date = Date()
    var lastReadAt: Date = Date()
}

struct BookChapter: Codable, Hashable, Identifiable {
    var id: String { url + "#\(index)" }
    var url: String
    var title: String
    var index: Int
    var isVolume: Bool = false
    /// ruleToc.updateTime 解析结果（可选，旧数据缺省）。
    var updateTime: String? = nil
    /// ruleToc.isVip：付费/会员章节标记，不影响阅读。
    var isVip: Bool = false

    init(url: String, title: String, index: Int, isVolume: Bool = false, updateTime: String? = nil, isVip: Bool = false) {
        self.url = url; self.title = title; self.index = index
        self.isVolume = isVolume; self.updateTime = updateTime; self.isVip = isVip
    }

    enum CodingKeys: String, CodingKey { case url, title, index, isVolume, updateTime, isVip }

    /// 宽松解码：旧版本落盘的目录缓存没有 updateTime/isVip，缺字段时用默认值，不丢缓存。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        url = try c.decode(String.self, forKey: .url)
        title = try c.decode(String.self, forKey: .title)
        index = try c.decode(Int.self, forKey: .index)
        isVolume = (try? c.decodeIfPresent(Bool.self, forKey: .isVolume)) ?? false
        updateTime = try? c.decodeIfPresent(String.self, forKey: .updateTime)
        isVip = (try? c.decodeIfPresent(Bool.self, forKey: .isVip)) ?? false
    }
}
