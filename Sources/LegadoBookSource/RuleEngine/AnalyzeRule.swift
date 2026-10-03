//
//  AnalyzeRule.swift
//  LegadoBookSource
//
//  对应 Kotlin: model/analyzeRule/AnalyzeRule.kt（规则总调度）。
//
//  移植范围（本步骤 Step4-B）：
//   - getString（三重载）、getStringList（两重载）、getElement、getElements
//   - splitSourceRule / SourceRule（Mode 判定、前缀、{{ }}/@get/@put、$1~$99、## ### 切分）
//   - putRule / splitPutRule / replaceRegex / compileRegexCache / 各缓存（容量 16）
//   - setContent（含 isJSON 判定）/ setBaseUrl / setRedirectUrl
//   - getAnalyzeByXPath/JSoup/JSonPath（o != content 新建，否则缓存复用）
//   - put/get 四层回退链（chapter→book→ruleData→source）
//   - evalJS（JavaScriptCore）、ajax（AjaxProvider）、WebJs（WebJSProvider，默认 unsupported）
//   - setChapter / setNextChapterUrl / setRuleData 等 setter
//
//  排除（见 README「后续 TODO」）：reGetBook/refreshTocUrl 真实实现（留桩抛 unsupported）、
//  JsExtensions 100 方法体、真实网络/WebView/WebBook 流程。
//
//  —— 全局规范：绝不崩溃；Kotlin 抛异常处 -> throws + RuleEngineError；Kotlin 吞异常处 -> 吞 + 记诊断。
//

import Foundation
import SwiftSoup

/// Kotlin: enum class Mode { XPath, Json, Default, Js, Regex, WebJs }
public enum Mode {
    case xPath, json, `default`, js, regex, webJs
}

public final class AnalyzeRule {

    // MARK: - 注入依赖

    private var ruleData: RuleDataStore?
    private var book: BookData?
    private var chapter: ChapterData?
    private let source: SourceVariableStore?
    private let isFromBookInfo: Bool
    private let preUpdateJs: Bool

    private let cookieStore: CookieStoreProtocol
    private let cacheManager: CacheManagerProtocol
    private let ajaxProvider: AjaxProvider
    private let webJSProvider: WebJSProvider
    private let jsUIProvider: JsUIProvider
    private let jsNetworkProvider: JsNetworkExtensionsProvider
    public let diagnostics: RuleEngineDiagnostics?

    // MARK: - 运行时状态

    private var content: RuleValue?
    private var baseUrl: String?
    private var redirectUrl: JavaURL?

    // 供扩展文件访问的 internal 访问器
    var contentValue: RuleValue? { content }
    var baseUrlValue: String? { baseUrl }
    var redirectUrlValue: JavaURL? { redirectUrl }
    var isJSONFlag: Bool { get { isJSON } set { isJSON = newValue } }
    var isRegexFlag: Bool { get { isRegex } set { isRegex = newValue } }
    var chapterStore: ChapterData? { chapter }
    var bookStore: BookData? { book }
    var ruleDataStore: RuleDataStore? { ruleData }
    var sourceStore: SourceVariableStore? { source }
    var nextChapterUrlValue: String? { nextChapterUrl }
    var isFromBookInfoValue: Bool { isFromBookInfo }
    var cookieStoreValue: CookieStoreProtocol { cookieStore }
    var cacheManagerValue: CacheManagerProtocol { cacheManager }
    var ajaxProviderValue: AjaxProvider { ajaxProvider }
    var webJSProviderValue: WebJSProvider { webJSProvider }
    var jsUIProviderValue: JsUIProvider { jsUIProvider }
    var jsNetworkProviderValue: JsNetworkExtensionsProvider { jsNetworkProvider }
    var ruleNameValue: String? { ruleName }
    private var isJSON: Bool = false
    private var isRegex: Bool = false
    private var nextChapterUrl: String?
    private var ruleName: String?

    private var analyzeByXPath: AnalyzeByXPath?
    private var analyzeByJSoup: AnalyzeByJSoup?
    private var analyzeByJSonPath: AnalyzeByJSonPath?

    // 缓存（对齐 Kotlin 容量）
    var stringRuleCache: [String: [SourceRule]] = [:]
    var regexCache: [String: NSRegularExpression?] = [:]
    let regexCacheLimit = 16
    var loggedNonStandardJSON = false

    // MARK: - init

    public init(
        ruleData: RuleDataStore? = nil,
        book: BookData? = nil,
        chapter: ChapterData? = nil,
        source: SourceVariableStore? = nil,
        isFromBookInfo: Bool = false,
        preUpdateJs: Bool = false,
        cookieStore: CookieStoreProtocol = InMemoryCookieStore(),
        cacheManager: CacheManagerProtocol = InMemoryCacheManager(),
        ajaxProvider: AjaxProvider = UnsupportedAjaxProvider(),
        webJSProvider: WebJSProvider = UnsupportedWebJSProvider(),
        jsUIProvider: JsUIProvider = UnsupportedJsUIProvider(),
        jsNetworkProvider: JsNetworkExtensionsProvider = UnsupportedJsNetworkExtensionsProvider(),
        diagnostics: RuleEngineDiagnostics? = nil
    ) {
        self.ruleData = ruleData
        self.book = book
        self.chapter = chapter
        self.source = source
        self.isFromBookInfo = isFromBookInfo
        self.preUpdateJs = preUpdateJs
        self.cookieStore = cookieStore
        self.cacheManager = cacheManager
        self.ajaxProvider = ajaxProvider
        self.webJSProvider = webJSProvider
        self.jsUIProvider = jsUIProvider
        self.jsNetworkProvider = jsNetworkProvider
        self.diagnostics = diagnostics
    }

    // MARK: - setter（对应 Kotlin companion 扩展 setter）

    @discardableResult
    public func setRuleData(_ ruleData: RuleDataStore?) -> AnalyzeRule { self.ruleData = ruleData; return self }
    @discardableResult
    public func setBook(_ book: BookData?) -> AnalyzeRule { self.book = book; return self }
    @discardableResult
    public func setChapter(_ chapter: ChapterData?) -> AnalyzeRule { self.chapter = chapter; return self }
    @discardableResult
    public func setNextChapterUrl(_ url: String?) -> AnalyzeRule { self.nextChapterUrl = url; return self }
    public func setRuleName(_ name: String) { if !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { ruleName = name } }

    /// 对应 Kotlin setContent(content, baseUrl)。content 为 nil 时 Kotlin 抛 AssertionError -> 这里 throws。
    @discardableResult
    public func setContent(_ content: RuleValue?, baseUrl: String? = nil) throws -> AnalyzeRule {
        guard let content = content, !content.isNull else {
            throw RuleEngineError.unsupported("内容不可空（Content cannot be null）")
        }
        self.content = content
        // isJSON: Node -> false；否则 content.toString().isJson()
        switch content {
        case .element, .elements, .xpathNodes:
            isJSON = false
        default:
            isJSON = LegadoStringUtils.isJson(content.stringValue)
        }
        setBaseUrl(baseUrl)
        analyzeByXPath = nil
        analyzeByJSoup = nil
        analyzeByJSonPath = nil
        return self
    }

    /// 便利：直接用字符串内容（最常见入口）。
    @discardableResult
    public func setContent(_ string: String, baseUrl: String? = nil) throws -> AnalyzeRule {
        return try setContent(.string(string), baseUrl: baseUrl)
    }

    @discardableResult
    public func setBaseUrl(_ baseUrl: String?) -> AnalyzeRule {
        if let b = baseUrl { self.baseUrl = b }
        return self
    }

    /// 对应 Kotlin setRedirectUrl：isDataUrl 直接返回；解析失败记日志不崩。
    @discardableResult
    public func setRedirectUrl(_ url: String) -> JavaURL? {
        if LegadoStringUtils.isDataUrl(url) { return redirectUrl }
        if let parsed = JavaURL.parse(url) {
            redirectUrl = parsed
        } else {
            diagnostics?.record(source: "AnalyzeRule.setRedirectUrl", rule: url, message: "URL 解析失败")
        }
        return redirectUrl
    }

    // MARK: - 解析器复用（对应 getAnalyzeByXxx 的 o != content 逻辑）

    private func contentEquals(_ v: RuleValue) -> Bool {
        guard let c = content else { return false }
        // 以字符串化判等（RuleValue 不是 Equatable；Kotlin 用引用判等 o != content，
        // 本移植用「是否就是当前 content」近似：相同引用的元素或相同字符串）。
        return c.stringValue == v.stringValue
    }

    func getAnalyzeByXPath(_ o: RuleValue) throws -> AnalyzeByXPath {
        if !contentEquals(o) {
            return try AnalyzeByXPath(ruleValueToDoc(o))
        }
        if analyzeByXPath == nil {
            analyzeByXPath = try AnalyzeByXPath(ruleValueToDoc(content!))
        }
        return analyzeByXPath!
    }

    func getAnalyzeByJSoup(_ o: RuleValue) throws -> AnalyzeByJSoup {
        if !contentEquals(o) {
            return try AnalyzeByJSoup(ruleValueToDoc(o))
        }
        if analyzeByJSoup == nil {
            analyzeByJSoup = try AnalyzeByJSoup(ruleValueToDoc(content!))
        }
        return analyzeByJSoup!
    }

    func getAnalyzeByJSonPath(_ o: RuleValue) throws -> AnalyzeByJSonPath {
        if !contentEquals(o) {
            return AnalyzeByJSonPath(ruleValueToJSON(o), diagnostics: diagnostics)
        }
        if analyzeByJSonPath == nil {
            analyzeByJSonPath = AnalyzeByJSonPath(ruleValueToJSON(content!), diagnostics: diagnostics)
        }
        return analyzeByJSonPath!
    }

    /// RuleValue -> 适合喂给 JSoup/XPath 的 doc（Element 或 HTML 字符串）。
    private func ruleValueToDoc(_ v: RuleValue) -> Any {
        switch v {
        case .element(let e): return e
        case .elements(let es): return Elements(es)
        case .xpathNodes(let ns): return ns.first ?? v.stringValue
        case .string(let s): return s
        default: return v.stringValue
        }
    }

    /// RuleValue -> JSONValue（喂给 JSonPath）。
    private func ruleValueToJSON(_ v: RuleValue) -> JSONValue {
        switch v {
        case .json(let j): return j
        case .string(let s): return JSONValue.parse(s) ?? .null
        default: return JSONValue.parse(v.stringValue) ?? .null
        }
    }
}
