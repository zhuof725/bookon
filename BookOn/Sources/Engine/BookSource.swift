import Foundation

/// Legado 书源模型。用 [String: Any] 宽松解析，兼容各种不规范书源 JSON。
struct BookSource: Identifiable, Hashable {
    var id: String { bookSourceUrl }

    var bookSourceUrl: String
    var bookSourceName: String
    var bookSourceGroup: String
    var bookSourceType: Int          // 0 文本 1 音频 2 图片 3 文件
    var bookUrlPattern: String
    var customOrder: Int
    var enabled: Bool
    var enabledExplore: Bool
    var enabledCookieJar: Bool
    var header: String               // JSON 字符串或 js
    var loginUrl: String
    var jsLib: String
    var concurrentRate: String
    var bookSourceComment: String
    var variableComment: String
    var lastUpdateTime: Int64
    var respondTime: Int64
    var weight: Int
    var exploreUrl: String
    var searchUrl: String
    var ruleSearch: [String: String]
    var ruleExplore: [String: String]
    var ruleBookInfo: [String: String]
    var ruleToc: [String: String]
    var ruleContent: [String: String]
    var raw: [String: Any]

    static func == (a: BookSource, b: BookSource) -> Bool { a.bookSourceUrl == b.bookSourceUrl }
    func hash(into h: inout Hasher) { h.combine(bookSourceUrl) }

    // MARK: rule accessors
    var search: SearchRule { SearchRule(ruleSearch) }
    var explore: SearchRule { SearchRule(ruleExplore) }
    var bookInfo: BookInfoRule { BookInfoRule(ruleBookInfo) }
    var toc: TocRule { TocRule(ruleToc) }
    var content: ContentRule { ContentRule(ruleContent) }

    // MARK: parse

    init?(json: [String: Any]) {
        guard let url = J.str(json["bookSourceUrl"]), !url.isEmpty else { return nil }
        bookSourceUrl = url
        bookSourceName = J.str(json["bookSourceName"]) ?? url
        bookSourceGroup = J.str(json["bookSourceGroup"]) ?? ""
        bookSourceType = J.int(json["bookSourceType"]) ?? 0
        bookUrlPattern = J.str(json["bookUrlPattern"]) ?? ""
        customOrder = J.int(json["customOrder"]) ?? 0
        enabled = J.bool(json["enabled"]) ?? true
        enabledExplore = J.bool(json["enabledExplore"]) ?? true
        enabledCookieJar = J.bool(json["enabledCookieJar"]) ?? true
        header = J.str(json["header"]) ?? ""
        loginUrl = J.str(json["loginUrl"]) ?? ""
        jsLib = J.str(json["jsLib"]) ?? ""
        concurrentRate = J.str(json["concurrentRate"]) ?? ""
        bookSourceComment = J.str(json["bookSourceComment"]) ?? ""
        variableComment = J.str(json["variableComment"]) ?? ""
        lastUpdateTime = J.int64(json["lastUpdateTime"]) ?? 0
        respondTime = J.int64(json["respondTime"]) ?? 180000
        weight = J.int(json["weight"]) ?? 0
        exploreUrl = J.str(json["exploreUrl"]) ?? ""
        searchUrl = J.str(json["searchUrl"]) ?? ""
        ruleSearch = J.ruleMap(json["ruleSearch"])
        ruleExplore = J.ruleMap(json["ruleExplore"])
        ruleBookInfo = J.ruleMap(json["ruleBookInfo"])
        ruleToc = J.ruleMap(json["ruleToc"])
        ruleContent = J.ruleMap(json["ruleContent"])
        raw = json
    }

    /// 从 JSON 文本解析（单个对象或数组）
    static func parseList(_ text: String) -> [BookSource] {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return [] }
        if let arr = obj as? [[String: Any]] {
            return arr.compactMap(BookSource.init(json:))
        }
        if let one = obj as? [String: Any], let s = BookSource(json: one) { return [s] }
        return []
    }

    var jsonData: Data {
        (try? JSONSerialization.data(withJSONObject: raw, options: [.prettyPrinted, .sortedKeys])) ?? Data()
    }

    /// 解析 header 字段为请求头
    func headerMap(js: JSEngine? = nil) -> [String: String] {
        var h = header.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !h.isEmpty else { return [:] }
        if h.lowercased().hasPrefix("@js:") {
            h = js?.eval(String(h.dropFirst(4)))?.toString() ?? ""
        } else if h.hasPrefix("<js>") {
            let body = h.replacingOccurrences(of: "<js>", with: "").replacingOccurrences(of: "</js>", with: "")
            h = js?.eval(body)?.toString() ?? ""
        }
        guard let d = h.data(using: .utf8),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return [:] }
        var out: [String: String] = [:]
        for (k, v) in o { out[k] = J.str(v) ?? "\(v)" }
        return out
    }
}

// MARK: - Rule structs (thin wrappers)

struct SearchRule {
    let m: [String: String]
    init(_ m: [String: String]) { self.m = m }
    var bookList: String { m["bookList"] ?? "" }
    var name: String { m["name"] ?? "" }
    var author: String { m["author"] ?? "" }
    var intro: String { m["intro"] ?? "" }
    var kind: String { m["kind"] ?? "" }
    var lastChapter: String { m["lastChapter"] ?? "" }
    var updateTime: String { m["updateTime"] ?? "" }
    var bookUrl: String { m["bookUrl"] ?? "" }
    var coverUrl: String { m["coverUrl"] ?? "" }
    var wordCount: String { m["wordCount"] ?? "" }
    var checkKeyWord: String { m["checkKeyWord"] ?? "" }
}

struct BookInfoRule {
    let m: [String: String]
    init(_ m: [String: String]) { self.m = m }
    var initRule: String { m["init"] ?? "" }
    var name: String { m["name"] ?? "" }
    var author: String { m["author"] ?? "" }
    var intro: String { m["intro"] ?? "" }
    var kind: String { m["kind"] ?? "" }
    var lastChapter: String { m["lastChapter"] ?? "" }
    var updateTime: String { m["updateTime"] ?? "" }
    var coverUrl: String { m["coverUrl"] ?? "" }
    var tocUrl: String { m["tocUrl"] ?? "" }
    var wordCount: String { m["wordCount"] ?? "" }
    var canReName: String { m["canReName"] ?? "" }
}

struct TocRule {
    let m: [String: String]
    init(_ m: [String: String]) { self.m = m }
    var preUpdateJs: String { m["preUpdateJs"] ?? "" }
    var chapterList: String { m["chapterList"] ?? "" }
    var chapterName: String { m["chapterName"] ?? "" }
    var chapterUrl: String { m["chapterUrl"] ?? "" }
    var formatJs: String { m["formatJs"] ?? "" }
    var isVolume: String { m["isVolume"] ?? "" }
    var isVip: String { m["isVip"] ?? "" }
    var isPay: String { m["isPay"] ?? "" }
    var updateTime: String { m["updateTime"] ?? "" }
    var nextTocUrl: String { m["nextTocUrl"] ?? "" }
}

struct ContentRule {
    let m: [String: String]
    init(_ m: [String: String]) { self.m = m }
    var content: String { m["content"] ?? "" }
    var title: String { m["title"] ?? "" }
    var nextContentUrl: String { m["nextContentUrl"] ?? "" }
    var webJs: String { m["webJs"] ?? "" }
    var sourceRegex: String { m["sourceRegex"] ?? "" }
    var replaceRegex: String { m["replaceRegex"] ?? "" }
    var imageStyle: String { m["imageStyle"] ?? "" }
}

// MARK: - Lenient JSON helpers

enum J {
    static func str(_ v: Any?) -> String? {
        switch v {
        case nil: return nil
        case let s as String: return s
        case is NSNull: return nil
        case let b as Bool: return b ? "true" : "false"
        case let n as NSNumber: return n.stringValue
        case let d as [String: Any]:
            return (try? JSONSerialization.data(withJSONObject: d)).flatMap { String(data: $0, encoding: .utf8) }
        case let a as [Any]:
            return (try? JSONSerialization.data(withJSONObject: a)).flatMap { String(data: $0, encoding: .utf8) }
        default: return "\(v!)"
        }
    }
    static func int(_ v: Any?) -> Int? {
        switch v {
        case let n as NSNumber: return n.intValue
        case let s as String: return Int(s.trimmingCharacters(in: .whitespaces)) ?? Double(s).map { Int($0) }
        default: return nil
        }
    }
    static func int64(_ v: Any?) -> Int64? {
        switch v {
        case let n as NSNumber: return n.int64Value
        case let s as String: return Int64(s) ?? Double(s).map { Int64($0) }
        default: return nil
        }
    }
    static func bool(_ v: Any?) -> Bool? {
        switch v {
        case let b as Bool: return b
        case let n as NSNumber: return n.intValue != 0
        case let s as String: return ["true", "1", "yes"].contains(s.lowercased())
        default: return nil
        }
    }
    /// 规则对象：可能是字典，也可能是 JSON 字符串（旧格式）
    static func ruleMap(_ v: Any?) -> [String: String] {
        var dict: [String: Any]?
        if let d = v as? [String: Any] { dict = d }
        else if let s = v as? String, let data = s.data(using: .utf8) {
            dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        }
        guard let d = dict else { return [:] }
        var out: [String: String] = [:]
        for (k, val) in d { if let s = str(val), !s.isEmpty { out[k] = s } }
        return out
    }
}
