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
    var unknownFields: [String: AnyJSONValue] = [:]
    /// 已知键但类型对不上时保留的原值（例如 `"weight": {"a":1}`）。
    /// 这些键不会进 unknownFields（它们是已知键），若直接丢掉，导出时字段就彻底没了。
    var mismatchedFields: [String: AnyJSONValue] = [:]

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
        // 类型不匹配（或缺失）的已知键记下来：它们不会进 unknownFields，
        // 若直接丢掉，导出时这个字段就彻底没了（例如 weight 写成 "5" 或对象）。
        var unresolved: Set<CodingKeys> = []
        func track<T>(_ value: T?, _ key: CodingKeys) -> T? {
            if value == nil { unresolved.insert(key) }
            return value
        }
        bookSourceUrl = (try? c.decode(String.self, forKey: .bookSourceUrl)) ?? ""
        bookSourceName = (try? c.decode(String.self, forKey: .bookSourceName)) ?? bookSourceUrl
        bookSourceGroup = track(try? c.decodeIfPresent(String.self, forKey: .bookSourceGroup), .bookSourceGroup)
        bookSourceType = track(BookSource.lenientInt(c, .bookSourceType), .bookSourceType)
        bookSourceComment = track(try? c.decodeIfPresent(String.self, forKey: .bookSourceComment), .bookSourceComment)
        enabled = track(BookSource.lenientBool(c, .enabled), .enabled)
        header = track(try? c.decodeIfPresent(String.self, forKey: .header), .header)
        jsLib = track(try? c.decodeIfPresent(String.self, forKey: .jsLib), .jsLib)
        loginUrl = track(try? c.decodeIfPresent(String.self, forKey: .loginUrl), .loginUrl)
        loginUi = track(try? c.decodeIfPresent(String.self, forKey: .loginUi), .loginUi)
        searchUrl = track(try? c.decodeIfPresent(String.self, forKey: .searchUrl), .searchUrl)
        exploreUrl = track(try? c.decodeIfPresent(String.self, forKey: .exploreUrl), .exploreUrl)
        bookUrlPattern = track(try? c.decodeIfPresent(String.self, forKey: .bookUrlPattern), .bookUrlPattern)
        enabledCookieJar = track(BookSource.lenientBool(c, .enabledCookieJar), .enabledCookieJar)
        let searchRule: SearchRule? = BookSource.lenient(c, .ruleSearch)
        let exploreRule: SearchRule? = BookSource.lenient(c, .ruleExplore)
        let bookInfoRule: BookInfoRule? = BookSource.lenient(c, .ruleBookInfo)
        let tocRule: TocRule? = BookSource.lenient(c, .ruleToc)
        let contentRule: ContentRule? = BookSource.lenient(c, .ruleContent)
        let reviewRule: ReviewRule? = BookSource.lenient(c, .ruleReview)
        ruleSearch = track(searchRule, .ruleSearch)
        ruleExplore = track(exploreRule, .ruleExplore)
        ruleBookInfo = track(bookInfoRule, .ruleBookInfo)
        ruleToc = track(tocRule, .ruleToc)
        ruleContent = track(contentRule, .ruleContent)
        customOrder = track(BookSource.lenientInt(c, .customOrder), .customOrder)
        lastUpdateTime = track(BookSource.lenientInt64(c, .lastUpdateTime), .lastUpdateTime)
        respondTime = track(BookSource.lenientInt(c, .respondTime), .respondTime)
        weight = track(BookSource.lenientInt(c, .weight), .weight)
        storageKind = track(BookSource.lenientInt(c, .storageKind), .storageKind)
        ruleReview = track(reviewRule, .ruleReview)
        mainJs = track(try? c.decodeIfPresent(String.self, forKey: .mainJs), .mainJs)
        loginCheckJs = track(try? c.decodeIfPresent(String.self, forKey: .loginCheckJs), .loginCheckJs)
        coverDecodeJs = track(try? c.decodeIfPresent(String.self, forKey: .coverDecodeJs), .coverDecodeJs)
        variableComment = track(try? c.decodeIfPresent(String.self, forKey: .variableComment), .variableComment)
        concurrentRate = track(try? c.decodeIfPresent(String.self, forKey: .concurrentRate), .concurrentRate)
        exploreScreen = track(try? c.decodeIfPresent(String.self, forKey: .exploreScreen), .exploreScreen)
        enabledExplore = track(BookSource.lenientBool(c, .enabledExplore), .enabledExplore)
        eventListener = track(BookSource.lenientBool(c, .eventListener), .eventListener)
        customButton = track(BookSource.lenientBool(c, .customButton), .customButton)
        // CodingKeys 容器的 allKeys 只会给出已声明的键，必须另开一个动态键容器才能看到未知字段。
        var unknown: [String: AnyJSONValue] = [:]
        var mismatched: [String: AnyJSONValue] = [:]
        if let raw = try? decoder.container(keyedBy: AnyCodingKey.self) {
            for key in raw.allKeys {
                let name = key.stringValue
                guard let value = try? raw.decode(AnyJSONValue.self, forKey: key) else { continue }
                if let codingKey = CodingKeys(rawValue: name) {
                    // 已知键：类型化解码成功时用上面的类型化输出，这里不再重复写；
                    // 解码失败（类型不匹配）时把原值单独存下来，导出时原样写回。
                    guard unresolved.contains(codingKey) else { continue }
                    mismatched[name] = value
                } else {
                    unknown[name] = value
                }
            }
        }
        unknownFields = unknown
        mismatchedFields = mismatched
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
        // 类型不匹配的已知键：类型化输出这里是 nil（没写），用原值补上，不会重复同一个 JSON 键。
        // 若用户后来在编辑页把这个字段改成了合法值（typed 不再是 nil），就不再写原值，避免覆盖用户的修改。
        for (key, value) in mismatchedFields {
            guard let codingKey = CodingKeys(rawValue: key), BookSource.isNil(codingKey, in: self) else { continue }
            try dynamic.encode(value, forKey: AnyCodingKey(key))
        }
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

    /// 宽松的整数解码：书源里 `"weight": "5"` 这种写法很常见，
    /// 直接按 Int 解会得到 nil，字段在导出时就被静默丢掉（它是已知键，不会进 unknownFields）。
    static func lenientInt(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Int? {
        if let v = try? c.decodeIfPresent(Int.self, forKey: key) { return v }
        if let s = try? c.decodeIfPresent(String.self, forKey: key) {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if let v = Int(t) { return v }
            if let d = Double(t) { return Int(d) }
        }
        if let d = try? c.decodeIfPresent(Double.self, forKey: key) { return Int(d) }
        return nil
    }

    static func lenientInt64(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Int64? {
        if let v = try? c.decodeIfPresent(Int64.self, forKey: key) { return v }
        if let v = try? c.decodeIfPresent(Int.self, forKey: key) { return Int64(v) }
        if let s = try? c.decodeIfPresent(String.self, forKey: key) {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if let v = Int64(t) { return v }
            if let d = Double(t) { return Int64(d) }
        }
        return nil
    }

    /// 宽松的布尔解码：兼容 "true"/"1"/1 等写法。
    static func lenientBool(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Bool? {
        if let v = try? c.decodeIfPresent(Bool.self, forKey: key) { return v }
        if let s = try? c.decodeIfPresent(String.self, forKey: key) {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if t == "true" || t == "1" || t == "yes" { return true }
            if t == "false" || t == "0" || t == "no" { return false }
        }
        if let i = try? c.decodeIfPresent(Int.self, forKey: key) { return i != 0 }
        return nil
    }

    /// 某个已知键在当前书源里是否没有值（nil）。
    /// 导入时用它判断「已知键但类型不匹配」，好把原值存进 mismatchedFields 原样导出。
    /// 非可选的 bookSourceUrl / bookSourceName 永远返回 false：它们的解码有兜底值，
    /// 若也当「类型不匹配」处理，导出时会出现同名重复键。
    static func isNil(_ key: CodingKeys, in source: BookSource) -> Bool {
        switch key {
        case .bookSourceUrl, .bookSourceName: return false
        case .bookSourceGroup: return source.bookSourceGroup == nil
        case .bookSourceType: return source.bookSourceType == nil
        case .bookSourceComment: return source.bookSourceComment == nil
        case .enabled: return source.enabled == nil
        case .header: return source.header == nil
        case .jsLib: return source.jsLib == nil
        case .loginUrl: return source.loginUrl == nil
        case .loginUi: return source.loginUi == nil
        case .searchUrl: return source.searchUrl == nil
        case .exploreUrl: return source.exploreUrl == nil
        case .bookUrlPattern: return source.bookUrlPattern == nil
        case .enabledCookieJar: return source.enabledCookieJar == nil
        case .ruleSearch: return source.ruleSearch == nil
        case .ruleExplore: return source.ruleExplore == nil
        case .ruleBookInfo: return source.ruleBookInfo == nil
        case .ruleToc: return source.ruleToc == nil
        case .ruleContent: return source.ruleContent == nil
        case .customOrder: return source.customOrder == nil
        case .lastUpdateTime: return source.lastUpdateTime == nil
        case .respondTime: return source.respondTime == nil
        case .weight: return source.weight == nil
        case .storageKind: return source.storageKind == nil
        case .ruleReview: return source.ruleReview == nil
        case .mainJs: return source.mainJs == nil
        case .loginCheckJs: return source.loginCheckJs == nil
        case .coverDecodeJs: return source.coverDecodeJs == nil
        case .variableComment: return source.variableComment == nil
        case .concurrentRate: return source.concurrentRate == nil
        case .exploreScreen: return source.exploreScreen == nil
        case .enabledExplore: return source.enabledExplore == nil
        case .eventListener: return source.eventListener == nil
        case .customButton: return source.customButton == nil
        }
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
