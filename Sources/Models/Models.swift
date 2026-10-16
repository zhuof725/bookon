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
    // 以下字段本应用暂未使用，但必须保留，编辑/导出时才不会丢失原书源内容（与原版字段同名）。
    var loginCheckJs: String?
    var coverDecodeJs: String?
    var variableComment: String?
    var concurrentRate: String?
    var exploreScreen: String?
    var enabledExplore: Bool?
    var eventListener: Bool?
    var customButton: Bool?

    var isEnabled: Bool { enabled ?? true }
    var cookieJarEnabled: Bool { enabledCookieJar ?? true }

    enum CodingKeys: String, CodingKey {
        case bookSourceUrl, bookSourceName, bookSourceGroup, bookSourceType, bookSourceComment
        case enabled, header, jsLib, loginUrl, loginUi, searchUrl, exploreUrl, bookUrlPattern, enabledCookieJar
        case ruleSearch, ruleExplore, ruleBookInfo, ruleToc, ruleContent, customOrder, lastUpdateTime
        case respondTime
        case loginCheckJs, coverDecodeJs, variableComment, concurrentRate, exploreScreen
        case enabledExplore, eventListener, customButton
    }

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
        loginCheckJs = try? c.decodeIfPresent(String.self, forKey: .loginCheckJs)
        coverDecodeJs = try? c.decodeIfPresent(String.self, forKey: .coverDecodeJs)
        variableComment = try? c.decodeIfPresent(String.self, forKey: .variableComment)
        concurrentRate = try? c.decodeIfPresent(String.self, forKey: .concurrentRate)
        exploreScreen = try? c.decodeIfPresent(String.self, forKey: .exploreScreen)
        enabledExplore = try? c.decodeIfPresent(Bool.self, forKey: .enabledExplore)
        eventListener = try? c.decodeIfPresent(Bool.self, forKey: .eventListener)
        customButton = try? c.decodeIfPresent(Bool.self, forKey: .customButton)
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
