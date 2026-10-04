//
//  AnalyzeRuleDependencies.swift
//  LegadoBookSource
//
//  AnalyzeRule 的外部依赖协议 + 内存默认实现。对应 Kotlin 里 AnalyzeRule 直接耦合的
//  RuleDataInterface / BaseBook / BaseSource.put-get / CookieStore / CacheManager /
//  AnalyzeUrl(ajax) / BackstageWebView(webJs)。本步骤用协议注入 + 默认实现解耦；
//  真实网络 / WebView / 磁盘缓存留给第 5、6 步。
//

import Foundation

// MARK: - RuleDataStore（对应 RuleDataInterface）

/// 对应 Kotlin RuleDataInterface：变量存取，含「>=10000 字符走 putBigVariable」分支。
public protocol RuleDataStore: AnyObject {
    func putVariable(_ key: String, _ value: String?)
    func getVariable(_ key: String) -> String
}

/// 内存默认实现（对应 Kotlin RuleData + RuleDataInterface 的 default 方法）：
/// 小变量（<10000）存 variableMap，>=10000 走 bigVariableMap（不做磁盘，只内存区分）。
public final class InMemoryRuleData: RuleDataStore {
    public private(set) var variableMap: [String: String] = [:]
    public private(set) var bigVariableMap: [String: String] = [:]

    public init() {}

    /// 对齐 Kotlin RuleDataInterface.putVariable 的三分支。
    public func putVariable(_ key: String, _ value: String?) {
        guard let value = value else {
            variableMap.removeValue(forKey: key)
            bigVariableMap.removeValue(forKey: key) // putBigVariable(key, null)
            return
        }
        if value.count < 10000 {
            bigVariableMap.removeValue(forKey: key) // putBigVariable(key, null)
            variableMap[key] = value
        } else {
            variableMap.removeValue(forKey: key)
            bigVariableMap[key] = value // putBigVariable(key, value)
        }
    }

    /// 对齐 Kotlin getVariable: variableMap[key] ?: getBigVariable(key) ?: ""
    public func getVariable(_ key: String) -> String {
        return variableMap[key] ?? bigVariableMap[key] ?? ""
    }
}

// MARK: - BookData（对应 BaseBook）

/// 书籍数据存取（对应 Kotlin BaseBook：name + putVariable/getVariable）。
public protocol BookData: AnyObject {
    var name: String { get }
    func putVariable(_ key: String, _ value: String?)
    func getVariable(_ key: String) -> String
}

/// 内存默认实现。
public final class InMemoryBook: BookData {
    public var name: String
    private let store = InMemoryRuleData()
    public init(name: String = "") { self.name = name }
    public func putVariable(_ key: String, _ value: String?) { store.putVariable(key, value) }
    public func getVariable(_ key: String) -> String { store.getVariable(key) }
}

// MARK: - ChapterData（对应 BookChapter）

/// 章节数据存取（对应 Kotlin BookChapter：title + putVariable/getVariable）。
public protocol ChapterData: AnyObject {
    var title: String { get }
    func putVariable(_ key: String, _ value: String?)
    func getVariable(_ key: String) -> String
}

public final class InMemoryChapter: ChapterData {
    public var title: String
    private let store = InMemoryRuleData()
    public init(title: String = "") { self.title = title }
    public func putVariable(_ key: String, _ value: String?) { store.putVariable(key, value) }
    public func getVariable(_ key: String) -> String { store.getVariable(key) }
}

// MARK: - SourceVariableStore（对应 BaseSource.put/get）

/// 书源级变量存取（对应 Kotlin BaseSource.put/get，底层是 CacheManager v_<key>_<name>）。
public protocol SourceVariableStore: AnyObject {
    func put(_ key: String, _ value: String) -> String
    func get(_ key: String) -> String
    func getTag() -> String?
    /// 对应 Kotlin BaseSource.getKey()
    func getKey() -> String
}

/// 内存默认实现。
public final class InMemorySource: SourceVariableStore {
    private var map: [String: String] = [:]
    private let tag: String?
    private let key: String
    public init(tag: String? = nil, key: String = "") { self.tag = tag; self.key = key }
    @discardableResult
    public func put(_ key: String, _ value: String) -> String { map[key] = value; return value }
    public func get(_ key: String) -> String { map[key] ?? "" }
    public func getTag() -> String? { tag }
    public func getKey() -> String { key }
}

// MARK: - AjaxProvider（对应 Kotlin ajax() 走 AnalyzeUrl）

/// 对应 Kotlin AnalyzeRule.ajax()：真实网络。默认实现返回错误字符串（对齐 getOrElse { stackTraceStr }）。
public protocol AjaxProvider: AnyObject {
    func ajax(_ url: String) -> String?
}

/// 默认实现：无网络，返回与 Kotlin 失败分支一致风格的错误串（真实实现第 6 步）。
public final class UnsupportedAjaxProvider: AjaxProvider {
    public init() {}
    public func ajax(_ url: String) -> String? {
        return "ajax(\(url)) error\n未实现网络请求（AnalyzeUrl，第 6 步）"
    }
}

// MARK: - WebJSProvider（对应 Kotlin getWebJsResult 走 BackstageWebView）

public enum WebJSError: Error { case unsupported }

/// 对应 Kotlin AnalyzeRule.getWebJsResult()：真实 WebView。默认抛 unsupported。
public protocol WebJSProvider: AnyObject {
    func eval(js: String, result: String, baseUrl: String?) throws -> String
}

public final class UnsupportedWebJSProvider: WebJSProvider {
    public init() {}
    public func eval(js: String, result: String, baseUrl: String?) throws -> String {
        throw RuleEngineError.unsupported("WebJs（@webjs:/BackstageWebView）未实现，需真实 WebView（第 5/6 步）")
    }
}

// MARK: - Step 5 UI / system JsExtensions dependency

/// toast/browser/verification 等 iOS 系统能力。真实 App 可注入实现；默认明确 unsupported。
public protocol JsUIProvider: AnyObject {
    func invoke(method: String, arguments: [String]) throws -> String?
}

public final class UnsupportedJsUIProvider: JsUIProvider {
    public init() {}
    public func invoke(method: String, arguments: [String]) throws -> String? {
        throw RuleEngineError.unsupported("java.\(method) 需要 UI/系统能力（第 5 步仅协议注入）")
    }
}

// MARK: - Step 5 network/file JsExtensions dependency

/// get/post/head/ajaxAll/connect/cacheFile/downloadFile。真实网络/文件实现留第 6 步。
public protocol JsNetworkExtensionsProvider: AnyObject {
    func invoke(method: String, arguments: [String]) throws -> String?
}

public final class UnsupportedJsNetworkExtensionsProvider: JsNetworkExtensionsProvider {
    public init() {}
    public func invoke(method: String, arguments: [String]) throws -> String? {
        throw RuleEngineError.unsupported("java.\(method) 需要真实网络/文件能力（第 6 步）")
    }
}

// MARK: - CookieStore / CacheManager 最小协议（仅为 JS 绑定对象服务）

/// 对应 Kotlin CookieStore（JS 里 `cookie` 对象）。默认内存实现。
public protocol CookieStoreProtocol: AnyObject {
    func getCookie(_ url: String) -> String
    func setCookie(_ url: String, _ cookie: String?)
    func removeCookie(_ url: String)
}

public final class InMemoryCookieStore: CookieStoreProtocol {
    private var map: [String: String] = [:]
    public init() {}
    public func getCookie(_ url: String) -> String { map[url] ?? "" }
    public func setCookie(_ url: String, _ cookie: String?) { map[url] = cookie }
    public func removeCookie(_ url: String) { map.removeValue(forKey: url) }
}

/// 对应 Kotlin CacheManager（JS 里 `cache` 对象）。默认内存实现。
public protocol CacheManagerProtocol: AnyObject {
    func get(_ key: String) -> String?
    func put(_ key: String, _ value: String)
    func delete(_ key: String)
}

public final class InMemoryCacheManager: CacheManagerProtocol {
    private var map: [String: String] = [:]
    public init() {}
    public func get(_ key: String) -> String? { map[key] }
    public func put(_ key: String, _ value: String) { map[key] = value }
    public func delete(_ key: String) { map.removeValue(forKey: key) }
}
