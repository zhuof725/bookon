//
//  AnalyzeUrl.swift
//  LegadoBookSource
//
//  第 6 步 6A：model/analyzeRule/AnalyzeUrl.kt（978 行）的完整移植——**只做规则解析与请求构造，
//  不发网络请求**。真实网络在 6B（URLSessionHTTPClient）。
//
//  逐段对应关系（Kotlin -> Swift）：
//   - init / initUrl / analyzeJs / replaceKeyPageJs / analyzeUrl / analyzeFields / analyzeQuery
//     / encodeParams / StringBuilder.appendEncoded / evalJS / put / get / getUserAgent / isPost
//     / getSource / getTag / getByteArrayIfDataUri / UrlOption / ConcurrentRecord —— 全部在本文
//     件或 UrlOption.swift / ConcurrentRateLimiter.swift；
//   - 请求构造：Kotlin 的 executeStrRequest / getResponseAwait / upload 里「构造 Request」的部分
//     抽取成 public `buildRequest()`（url/method/有序 headers/body/contentType/charset/retry/
//     readTimeout/callTimeout/useWebView/webJs/bodyJs/dnsIp/proxy/type/serverID）；
//   - WebView 分支（useWebView=true）只记录，不执行（6B/后续）。
//
//  ⚠️ 已知差异（README 差异表逐条登记）：
//   1. dnsIp / proxy 只落到 HTTPRequest 上，URLSession 侧的支持情况见 6B；
//   2. Kotlin 的 getClient() 里 Cronet + customIp 仅 Android 有效，本移植不涉及；
//   3. WebView 分支（BackstageWebView）不实现；
//   4. `ConcurrentRateLimiter` 的全局记录表是 actor + 可注入存储（语义等价，见该文件注释）。
//

import Foundation
import CoreFoundation

// MARK: - 依赖注入

/// 书源提供请求头（对应 Kotlin `BaseSource.getHeaderMap(hasLoginHeader)`）。
/// 用有序数组表示：Kotlin 侧是 LinkedHashMap，header 顺序会进 golden 对照。
public protocol SourceHeaderProvider: AnyObject {
    func getHeaderMap(hasLoginHeader: Bool) -> [(String, String)]
}

/// AnalyzeUrl 需要的外部环境（JS 里的 cookie/cache 对象 + diagnostics）。
public struct AnalyzeUrlEnvironment {
    public var cookie: CookieStoreProtocol
    public var cache: CacheManagerProtocol
    public var diagnostics: RuleEngineDiagnostics?

    public init(cookie: CookieStoreProtocol = InMemoryCookieStore(),
                cache: CacheManagerProtocol = InMemoryCacheManager(),
                diagnostics: RuleEngineDiagnostics? = nil) {
        self.cookie = cookie
        self.cache = cache
        self.diagnostics = diagnostics
    }
}

/// evalJS 的绑定集合（对应 Kotlin buildScriptBindings 里 AnalyzeUrl 绑的那一批）。
public struct AnalyzeUrlJSBindings {
    public var java: AnyObject?
    public var baseUrl: String = ""
    public var cookie: CookieStoreProtocol = InMemoryCookieStore()
    public var cache: CacheManagerProtocol = InMemoryCacheManager()
    public var page: Int?
    public var key: String?
    public var speakText: String?
    public var speakSpeed: Int?
    public var book: BookData?
    public var source: SourceVariableStore?
    public var result: RuleValue = .null
    public var infoMap: [String: String]?
    public init() {}
}

/// JS 求值入口协议（默认实现用 JSEngine；测试可注入桩）。
public protocol AnalyzeUrlJSEvaluator: AnyObject {
    func evaluate(_ js: String, bindings: AnalyzeUrlJSBindings) throws -> RuleValue
}

/// 默认实现：复用第 4 步的 JSEngine（JSC），把 AnalyzeUrl 及其绑定喂进去。
public final class DefaultAnalyzeUrlJSEvaluator: AnalyzeUrlJSEvaluator {
    private let engine: JSEngine
    private let diagnostics: RuleEngineDiagnostics?
    /// `java` 桥（对应 Kotlin `bindings["java"] = this`，即 AnalyzeUrl 自己实现 JsExtensions）
    private var bridge: JSJavaBridge?

    public init(diagnostics: RuleEngineDiagnostics? = nil) {
        self.engine = JSEngine(diagnostics: diagnostics)
        self.diagnostics = diagnostics
    }

    public func evaluate(_ js: String, bindings: AnalyzeUrlJSBindings) throws -> RuleValue {
        let javaBridge: JSJavaBridge
        if let existing = bridge {
            javaBridge = existing
        } else {
            let created = JSJavaBridge(diagnostics: diagnostics)
            bridge = created
            javaBridge = created
        }
        // AnalyzeUrl 自身方法（put/get/getSource/getTag/getUserAgent/isPost）挂到 java 上
        if let analyzeUrl = bindings.java as? AnalyzeUrl {
            let runtime = javaBridge.runtime
            runtime.putFn = { k, v in analyzeUrl.put(key: k, value: v) }
            runtime.getFn = { k in analyzeUrl.get(key: k) }
            runtime.getSourceKeyFn = { analyzeUrl.getSource()?.getKey() }
            runtime.getTagFn = { analyzeUrl.getTag() }
        }
        var engineBindings = JSEngine.Bindings(
            java: javaBridge,
            cookie: bindings.cookie,
            cache: bindings.cache,
            sourceKey: bindings.source?.getKey(),
            bookName: bindings.book?.name,
            result: bindings.result,
            baseUrl: bindings.baseUrl,
            chapterTitle: nil,
            src: nil,
            nextChapterUrl: nil,
            fromBookInfo: false)
        var extra: [String: Any] = [:]
        extra["page"] = bindings.page.map { $0 as Any } ?? NSNull()
        extra["key"] = bindings.key ?? NSNull()
        extra["speakText"] = bindings.speakText ?? NSNull()
        extra["speakSpeed"] = bindings.speakSpeed.map { $0 as Any } ?? NSNull()
        extra["book"] = bindings.book?.name ?? NSNull()
        extra["infoMap"] = bindings.infoMap ?? NSNull()
        engineBindings.extraBindings = extra
        return try engine.eval(js, bindings: engineBindings)
    }
}

// MARK: - AnalyzeUrl

/// 对应 Kotlin `class AnalyzeUrl`。
public final class AnalyzeUrl {

    // 对应 Kotlin 的私有构造参数
    private let mUrl: String
    private let key: String?
    private let page: Int?
    private let speakText: String?
    private let speakSpeed: Int?
    private var baseUrl: String
    private let source: (any SourceVariableStore)?
    private let ruleData: RuleDataStore?
    private let chapter: ChapterData?
    private let readTimeout: Int64?
    private let callTimeout: Int64?
    private let infoMap: [String: String]?
    private let getHeaderMapFn: ((Bool) -> [(String, String)])?

    // 对外只读状态
    public private(set) var ruleUrl = ""
    public private(set) var url = ""
    public private(set) var type: String?
    /// Kotlin: `val headerMap = LinkedHashMap<String, String>()`（有序）
    public private(set) var headerMap: [(String, String)] = []
    private var body: String?
    public private(set) var urlNoQuery = ""
    public private(set) var encodedForm: String?
    public private(set) var encodedQuery: String?
    public private(set) var charset: String?
    public private(set) var method = RequestMethod.get
    private var proxy: String?
    private var retry = 0
    private var useWebView = false
    private var webJs: String?
    private var bodyJs: String?
    private var dnsIp: String?
    private var webViewDelayTime: Int64 = 0
    /// Kotlin: `source?.enabledCookieJar == true`（本移植用 source 的实现方提供）
    private var enabledCookieJar: Bool { (source as? SourceCookieJarProvider)?.enabledCookieJar ?? false }
    public private(set) var domain = ""

    /// 服务器 ID（对应 Kotlin `var serverID: Long?`）
    public private(set) var serverID: Int64?

    private let environment: AnalyzeUrlEnvironment
    private let jsEvaluator: AnalyzeUrlJSEvaluator
    private let rateLimiter: ConcurrentRateLimiter

    public init(_ mUrl: String,
                key: String? = nil,
                page: Int? = nil,
                speakText: String? = nil,
                speakSpeed: Int? = nil,
                baseUrl: String = "",
                source: (any SourceVariableStore)? = nil,
                ruleData: RuleDataStore? = nil,
                chapter: ChapterData? = nil,
                readTimeout: Int64? = nil,
                callTimeout: Int64? = nil,
                headerMapF: [(String, String)]? = nil,
                hasLoginHeader: Bool = true,
                infoMap: [String: String]? = nil,
                getHeaderMap: ((Bool) -> [(String, String)])? = nil,
                environment: AnalyzeUrlEnvironment = AnalyzeUrlEnvironment(),
                jsEvaluator: AnalyzeUrlJSEvaluator? = nil,
                rateLimitStore: ConcurrentRecordStore = .shared,
                rateLimitClock: RateLimitClock = SystemRateLimitClock()) {
        self.mUrl = mUrl
        self.key = key
        self.page = page
        self.speakText = speakText
        self.speakSpeed = speakSpeed
        self.baseUrl = baseUrl
        self.source = source
        self.ruleData = ruleData
        self.chapter = chapter
        self.readTimeout = readTimeout
        self.callTimeout = callTimeout
        self.infoMap = infoMap
        self.getHeaderMapFn = getHeaderMap
        self.environment = environment
        self.jsEvaluator = jsEvaluator ?? DefaultAnalyzeUrlJSEvaluator(diagnostics: environment.diagnostics)
        if let provider = source as? ConcurrentRateSource {
            self.rateLimiter = ConcurrentRateLimiter(source: provider, store: rateLimitStore, clock: rateLimitClock)
        } else {
            self.rateLimiter = ConcurrentRateLimiter(concurrentRate: nil, key: source?.getKey(),
                                                     store: rateLimitStore, clock: rateLimitClock)
        }

        // init 块
        var base = baseUrl
        if let m = AnalyzeUrl.paramPattern.firstMatch(in: base), m.range.location != NSNotFound {
            base = AnalyzeUrl.substring(base, 0, m.range.location)
        }
        self.baseUrl = base

        var headers: [(String, String)] = []
        if let headerMapF = headerMapF {
            headers = headerMapF
        } else if let fn = getHeaderMapFn {
            headers = fn(hasLoginHeader)
        } else if let provider = source as? SourceHeaderProvider {
            headers = provider.getHeaderMap(hasLoginHeader: hasLoginHeader)
        }
        for (k, v) in headers {
            setHeader(k, v)
        }
        if let p = headers.first(where: { $0.0 == "proxy" })?.1 {
            proxy = p
            removeHeader("proxy")
        }

        initUrl()
        domain = NetworkUtils.getSubDomain((source?.getKey()) ?? url)
    }

    public convenience init(_ mUrl: String) {
        self.init(mUrl, key: nil)
    }

    // MARK: - 头部小工具（保持 LinkedHashMap 的有序语义）

    private func setHeader(_ k: String, _ v: String) {
        if let idx = headerMap.firstIndex(where: { $0.0 == k }) {
            headerMap[idx].1 = v
        } else {
            headerMap.append((k, v))
        }
    }

    private func removeHeader(_ k: String) {
        headerMap.removeAll { $0.0 == k }
    }

    private func headerValue(_ k: String) -> String? {
        headerMap.first { $0.0 == k }?.1
    }

    // MARK: - initUrl 三步

    /// 对应 Kotlin `initUrl()`。
    public func initUrl() {
        ruleUrl = mUrl
        analyzeJs()
        replaceKeyPageJs()
        analyzeUrl()
    }

    /// 对应 Kotlin `analyzeJs()`：执行 `@js:` / `<js></js>`，其余片段做 `@result` 替换。
    private func analyzeJs() {
        var start = 0
        var result = ruleUrl
        let matches = AnalyzeUrl.jsPattern.matches(in: ruleUrl)
        for m in matches {
            let matchStart = m.range.location
            if matchStart > start {
                let segment = AnalyzeUrl.substring(ruleUrl, start, matchStart)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !segment.isEmpty {
                    result = segment.replacingOccurrences(of: "@result", with: result)
                }
            }
            // group(2) 是 @js: 的内容，group(1) 是 <js> 的内容
            let g1 = AnalyzeUrl.group(ruleUrl, m, 1)
            let g2 = AnalyzeUrl.group(ruleUrl, m, 2)
            let jsStr = (g2 != nil ? g2 : g1) ?? ""
            let evaluated = evalJSString(jsStr, result: .string(result))
            result = evaluated
            start = m.range.location + m.range.length
        }
        if ruleUrl.utf16.count > start {
            let segment = AnalyzeUrl.substring(ruleUrl, start, ruleUrl.utf16.count)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !segment.isEmpty {
                result = segment.replacingOccurrences(of: "@result", with: result)
            }
        }
        ruleUrl = result
    }

    /// 对应 Kotlin `replaceKeyPageJs()`。
    private func replaceKeyPageJs() {
        if ruleUrl.contains("{{") && ruleUrl.contains("}}") {
            let analyze = RuleAnalyzer(ruleUrl)
            let url = (try? analyze.innerRule("{{", "}}") { [weak self] inner -> String? in
                guard let self = self else { return "" }
                let jsEval = self.evalJS(inner, result: nil)
                // Kotlin: `val jsEval = evalJS(it) ?: ""`，再对 Double%1==0 用 "%.0f"，其余 toString
                return AnalyzeUrl.innerRuleString(jsEval)
            }) ?? nil
            if let url = url, !url.isEmpty {
                ruleUrl = url
            }
        }
        if let page = page {
            // 注意（对齐 Kotlin）：matcher 建立在当时的 ruleUrl 上，替换作用于**新的** ruleUrl
            let snapshot = ruleUrl
            let matcher = AnalyzeUrl.pagePattern
            let ns = snapshot as NSString
            let matches = matcher.matches(in: snapshot)
            for m in matches {
                let inner = m.numberOfRanges > 1 ? ns.substring(with: m.range(at: 1)) : ""
                let pages = inner.components(separatedBy: ",")
                let replacement: String
                if page < pages.count {
                    // Kotlin 在 page == 0 时会抛 IndexOutOfBounds；本移植取 max(0, page-1) 不崩溃
                    // （README 差异表登记，真实调用 page >= 1）
                    replacement = AnalyzeUrl.trimSpaces(pages[max(0, page - 1)])
                } else {
                    replacement = AnalyzeUrl.trimSpaces(pages.last ?? "")
                }
                let matchedText = ns.substring(with: m.range)
                ruleUrl = ruleUrl.replacingOccurrences(of: matchedText, with: replacement)
            }
        }
    }

    /// 对应 Kotlin `analyzeUrl()`。
    private func analyzeUrl() {
        let ns = ruleUrl as NSString
        let urlMatches = AnalyzeUrl.paramPattern.matches(in: ruleUrl)
        let first = urlMatches.first
        let urlNoOption: String
        if let m = first {
            urlNoOption = AnalyzeUrl.substring(ruleUrl, 0, m.range.location)
        } else {
            urlNoOption = ruleUrl
        }
        url = NetworkUtils.getAbsoluteURL(baseUrl, urlNoOption)
        if let b = NetworkUtils.getBaseUrl(url) {
            baseUrl = b
        }
        if urlNoOption.utf16.count != ns.length, let m = first {
            let urlOptionStr = AnalyzeUrl.substring(ruleUrl, m.range.location + m.range.length, ns.length)
            if let option = UrlOption.parse(urlOptionStr) {
                if option.usedLenientFallback {
                    log("链接参数 JSON 格式不规范，请改为规范格式")
                }
                if let optMethod = option.getMethod() {
                    method = RequestMethod.from(optMethod)
                }
                if let hm = option.getHeaderMap() {
                    for (k, v) in hm { setHeader("\(k)", "\(v)") }
                }
                if let b = option.getBody() { body = b }
                type = option.getType()
                charset = option.getCharset()
                retry = option.getRetry()
                useWebView = option.useWebView()
                webJs = option.getWebJs()
                bodyJs = option.getBodyJs()
                dnsIp = option.getDnsIp()
                if let jsStr = option.getJs() {
                    let evaluated = evalJSString(jsStr, result: .string(url))
                    if let newUrl = evaluated as String? { url = newUrl }
                }
                serverID = option.getServerID()
                webViewDelayTime = max(0, option.getWebViewDelayTime() ?? 0)
            }
        }
        urlNoQuery = url
        switch method {
        case .post:
            if let b = body,
               !AnalyzeUrl.isJson(b), !AnalyzeUrl.isXml(b),
               (headerValue("Content-Type") ?? "").isEmpty {
                analyzeFields(b)
            }
        default:
            if let pos = url.firstIndex(of: "?") {
                let offset = url.distance(from: url.startIndex, to: pos)
                analyzeQuery(AnalyzeUrl.substring(url, offset + 1, url.utf16.count))
                urlNoQuery = AnalyzeUrl.substring(url, 0, offset)
            }
        }
    }

    /// 对应 Kotlin `analyzeFields`。
    private func analyzeFields(_ fieldsTxt: String) {
        encodedForm = encodeParams(fieldsTxt, charset: charset, isQuery: false)
    }

    /// 对应 Kotlin `analyzeQuery`。
    private func analyzeQuery(_ query: String) {
        encodedQuery = encodeParams(query, charset: charset, isQuery: true)
    }

    // MARK: - 编码（对应 Kotlin encodeParams / StringBuilder.appendEncoded）

    /// 对应 Kotlin `encodeParams(params, charset, isQuery)`。
    /// - charset 为 nil/空 -> UTF-8；"escape" -> nil（走 EncoderUtils.escape）；
    ///   其它按 `Charset.forName` 查找（找不到时 Kotlin 抛异常，这里返回 nil 并在调用处保持原样）。
    public func encodeParams(_ params: String, charset charsetName: String?, isQuery: Bool) -> String {
        return AnalyzeUrl.encodeParams(params, charset: charsetName, isQuery: isQuery)
    }

    /// 与实例方法同名的静态版本（golden 对照直接调用，不依赖实例状态）。
    public static func encodeParams(_ params: String, charset charsetName: String?, isQuery: Bool) -> String {
        let checkEncoded = (charsetName ?? "").isEmpty
        let resolved: AnalyzeUrlCharsetResult = {
            if (charsetName ?? "").isEmpty { return .charset(.utf8) }
            if charsetName == "escape" { return .escape }
            if let enc = AnalyzeUrlCharset.lookup(charsetName ?? "") { return .charset(enc) }
            return .invalid
        }()
        if case .invalid = resolved {
            // Kotlin: Charset.forName 抛异常 -> 由调用方 catch（analyzeUrl 不在 try 里，会冒泡）
            return params
        }
        if isQuery, case .charset(let enc) = resolved {
            if NetworkUtils.encodedQuery(params) { return params }
            return AnalyzeUrlQueryEncoder.encode(params, charset: enc)
        }
        let len = params.utf16.count
        var sb = ""
        var pos = 0
        while pos <= len {
            if !sb.isEmpty { sb += "&" }
            var ampOffset = AnalyzeUrl.indexOf(params, "&", pos)
            if ampOffset == -1 { ampOffset = len }
            let eqOffset = AnalyzeUrl.indexOf(params, "=", pos)
            let key: String
            let value: String?
            if eqOffset == -1 || eqOffset > ampOffset {
                key = AnalyzeUrl.substring(params, pos, ampOffset)
                value = nil
            } else {
                key = AnalyzeUrl.substring(params, pos, eqOffset)
                value = AnalyzeUrl.substring(params, eqOffset + 1, ampOffset)
            }
            sb += AnalyzeUrl.appendEncoded(key, checkEncoded: checkEncoded, charset: resolved)
            if let value = value {
                sb += "="
                sb += AnalyzeUrl.appendEncoded(value, checkEncoded: checkEncoded, charset: resolved)
            }
            pos = ampOffset + 1
        }
        return sb
    }

    /// 对应 Kotlin `StringBuilder.appendEncoded(value, checkEncoded, charset)`。
    private static func appendEncoded(_ value: String, checkEncoded: Bool,
                                      charset: AnalyzeUrlCharsetResult) -> String {
        if checkEncoded && NetworkUtils.encodedForm(value) {
            return value
        }
        switch charset {
        case .escape:
            return AnalyzeUrl.escape(value)
        case .charset(let enc):
            return AnalyzeUrlURLEncoder.encode(value, charset: enc)
        case .invalid:
            return value
        }
    }

    // MARK: - JS

    /// 对应 Kotlin `evalJS(jsStr, result)`：返回 RuleValue（Kotlin 是 Any?）。
    @discardableResult
    public func evalJS(_ jsStr: String, result: RuleValue?) -> RuleValue {
        var bindings = AnalyzeUrlJSBindings()
        bindings.java = self
        bindings.baseUrl = baseUrl
        bindings.cookie = environment.cookie
        bindings.cache = environment.cache
        bindings.page = page
        bindings.key = key
        bindings.speakText = speakText
        bindings.speakSpeed = speakSpeed
        bindings.book = ruleData as? BookData
        bindings.source = source
        bindings.result = result ?? .null
        bindings.infoMap = infoMap
        do {
            return try jsEvaluator.evaluate(jsStr, bindings: bindings)
        } catch {
            environment.diagnostics?.record(source: "AnalyzeUrl.evalJS", rule: jsStr,
                                            message: "JS 求值失败：\(error)")
            return .null
        }
    }

    /// Kotlin `evalJS(...).toString()`：null/undefined -> 字面量 "null"。
    private func evalJSString(_ jsStr: String, result: RuleValue?) -> String {
        return AnalyzeUrl.jsToString(evalJS(jsStr, result: result))
    }

    /// Kotlin `replaceKeyPageJs` 里 `{{}}` 的取值规则：null -> ""；整数 Double -> "%.0f"；其余 toString。
    static func innerRuleString(_ v: RuleValue) -> String {
        switch v {
        case .null: return ""
        case .number(let d):
            if d.truncatingRemainder(dividingBy: 1) == 0 { return String(format: "%.0f", d) }
            return v.stringValue
        default: return v.stringValue
        }
    }

    static func jsToString(_ v: RuleValue) -> String {
        if case .null = v { return "null" }
        return v.stringValue
    }

    // MARK: - put / get

    /// 对应 Kotlin `put(key, value)`。
    @discardableResult
    public func put(key: String, value: String) -> String {
        chapter?.putVariable(key, value) ?? ruleData?.putVariable(key, value)
        return value
    }

    /// 对应 Kotlin `get(key)`。
    public func get(key: String) -> String {
        if key == "bookName", let book = ruleData as? BookData {
            return book.name
        }
        if key == "title", let chapter = chapter {
            return chapter.title
        }
        if let v = chapter?.getVariable(key), !v.isEmpty { return v }
        if let v = ruleData?.getVariable(key), !v.isEmpty { return v }
        return ""
    }

    // MARK: - 请求构造（6A 的核心输出）

    /// 对应 Kotlin `setCookie()`：urlOption 临时 cookie > 数据库 cookie（合并顺序）。
    /// 另按 enabledCookieJar 加/删 `CookieJar` 头。
    /// 对应 Kotlin `setCookie()`（cookie 优先级：urlOption 临时 cookie > 数据库 cookie）。
    public func setCookie() {
        let cookie = environment.cookie.getCookie(domain)
        if !cookie.isEmpty {
            if let merged = CookieMerge.mergeCookies([cookie, headerValue("Cookie")]) {
                setHeader("Cookie", merged)
            }
        }
        if enabledCookieJar {
            setHeader(CookieMerge.cookieJarHeader, "1")
        } else {
            removeHeader(CookieMerge.cookieJarHeader)
        }
    }

    /// 把 Kotlin `executeStrRequest`/`getResponseAwait` 里「构造请求」的部分抽出来。
    /// 不发网络请求，只产出 HTTPRequest（6B 的客户端负责真正发送）。
    public func buildRequest() -> HTTPRequest {
        setCookie()
        var headers = headerMap
        var contentType: String? = nil
        var bodyData: Data? = nil
        var finalUrl = urlNoQuery

        switch method {
        case .post:
            let ct = headerValue("Content-Type")
            let bodyText = body
            if !(encodedForm ?? "").isEmpty || (bodyText ?? "").isEmpty {
                // postForm(encodedForm ?: "")
                contentType = "application/x-www-form-urlencoded"
                bodyData = Data((encodedForm ?? "").utf8)
            } else if !(ct ?? "").isEmpty {
                // body.toRequestBody(contentType.toMediaType())
                contentType = ct
                bodyData = Data((bodyText ?? "").utf8)
            } else {
                // postJson(body)
                contentType = "application/json; charset=UTF-8"
                bodyData = Data((bodyText ?? "").utf8)
            }
        case .head, .get:
            if let q = encodedQuery {
                finalUrl = urlNoQuery + "?" + q
            }
        }

        // 与 Kotlin 一致：最终 URL 经过 OkHttp HttpUrl 的规范化（scheme/host 小写、默认端口剥离、
        // 路径 %xx 与 . / .. 段解析、查询/片段编码）。解析失败时保留拼接结果（Kotlin 会在
        // toHttpUrl() 处抛异常 -> AnalyzeUrl 的 try/catch 路径，6B 的客户端负责记录 diagnostics）。
        if let normalized = HttpUrl.parse(finalUrl) {
            finalUrl = normalized.urlString
        }

        return HTTPRequest(url: finalUrl,
                           method: method,
                           headers: headers,
                           body: bodyData,
                           contentType: contentType,
                           charset: charset,
                           retry: retry,
                           readTimeout: readTimeout,
                           callTimeout: callTimeout,
                           useWebView: useWebView,
                           webJs: webJs,
                           bodyJs: bodyJs,
                           dnsIp: dnsIp,
                           proxy: proxy,
                           type: type,
                           serverID: serverID,
                           enabledCookieJar: enabledCookieJar,
                           webViewDelayTime: webViewDelayTime)
    }

    /// 对应 Kotlin `getUserAgent()`：headerMap 里不区分大小写找 UA_NAME，否则默认 UA。
    public func getUserAgent(defaultUserAgent: String = AnalyzeUrl.defaultUserAgent) -> String {
        for (k, v) in headerMap where k.caseInsensitiveCompare("User-Agent") == .orderedSame {
            return v
        }
        return defaultUserAgent
    }

    /// 对应 Kotlin `isPost()`。
    public func isPost() -> Bool { method == .post }

    /// 对应 Kotlin `getSource()`。
    public func getSource() -> (any SourceVariableStore)? { source }

    /// 对应 Kotlin `getTag()`。
    public func getTag() -> String? { source?.getTag() }

    /// 对应 Kotlin `getByteArrayIfDataUri()`：data: URI 的 base64 内容。
    public func getByteArrayIfDataUri() -> Data? {
        guard urlNoQuery.lowercased().hasPrefix("data:") else { return nil }
        guard let m = AnalyzeUrl.dataUriRegex.firstMatch(in: urlNoQuery) else { return nil }
        let ns = urlNoQuery as NSString
        guard m.numberOfRanges > 1 else { return nil }
        let base64 = ns.substring(with: m.range(at: 1))
        return Data(base64Encoded: base64, options: [.ignoreUnknownCharacters])
    }

    /// 对应 Kotlin `log(...)`（AnalyzeUrl 里只有一条“链接参数 JSON 格式不规范”）。
    private func log(_ message: String) {
        environment.diagnostics?.record(source: "AnalyzeUrl", rule: "", message: message)
    }

    /// 限速入口（对应 Kotlin `concurrentRateLimiter.withLimit {}`）。
    public func withRateLimit<T>(_ block: () async throws -> T) async rethrows -> T {
        return try await rateLimiter.withLimit(block)
    }

    /// 按书源构造并发率限制器（对应 Kotlin `ConcurrentRateLimiter(getSource())`，
    /// 用于 get/post/head 这三条「不走 AnalyzeUrl」的 Jsoup.connect 分支）。
    /// 传 nil / 空串时等价于不限速。
    public static func makeRateLimiter(concurrentRate: String?, key: String? = nil,
                                       store: ConcurrentRecordStore = .shared,
                                       clock: RateLimitClock = SystemRateLimitClock()) -> ConcurrentRateLimiter {
        return ConcurrentRateLimiter(concurrentRate: concurrentRate, key: key, store: store, clock: clock)
    }
}

/// 书源是否启用 cookieJar（对应 Kotlin `BaseSource.enabledCookieJar`）。
public protocol SourceCookieJarProvider: AnyObject {
    var enabledCookieJar: Bool { get }
}

// MARK: - 常量与工具（对应 Kotlin companion object + 各处小工具）

public extension AnalyzeUrl {

    /// Kotlin: `Pattern.compile("\\s*,\\s*(?=\\{)")`
    static let paramPattern = NSRegularExpressionCache(pattern: "\\s*,\\s*(?=\\{)")
    /// Kotlin: `Pattern.compile("<(.*?)>")`
    static let pagePattern = NSRegularExpressionCache(pattern: "<(.*?)>", options: [.dotMatchesLineSeparators])
    /// Kotlin AppPattern.JS_PATTERN: `Pattern.compile("<js>([\\w\\W]*?)</js>|@js:([\\w\\W]*)", CASE_INSENSITIVE)`
    static let jsPattern = NSRegularExpressionCache(
        pattern: "<js>(.*?)</js>|@js:(.*)",
        options: [.caseInsensitive, .dotMatchesLineSeparators])
    /// Kotlin AppPattern.dataUriRegex: `^data:.*?;base64,(.*)`
    static let dataUriRegex = NSRegularExpressionCache(pattern: "^data:.*?;base64,(.*)")

    /// 默认 User-Agent（Kotlin AppConfig.userAgent 的默认值，见 AppConst.USER_AGENT）。
    static let defaultUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36"

    // MARK: UTF-16 小工具（Kotlin String 的索引语义）

    static func substring(_ s: String, _ start: Int, _ end: Int) -> String {
        let units = Array(s.utf16)
        let a = max(0, min(start, units.count))
        let b = max(a, min(end, units.count))
        return String(decoding: units[a..<b], as: UTF16.self)
    }

    static func indexOf(_ s: String, _ needle: String, _ from: Int) -> Int {
        let units = Array(s.utf16)
        let n = Array(needle.utf16)
        guard !n.isEmpty, from <= units.count else { return -1 }
        var i = max(0, from)
        while i + n.count <= units.count {
            var ok = true
            for j in 0..<n.count where units[i + j] != n[j] { ok = false; break }
            if ok { return i }
            i += 1
        }
        return -1
    }

    static func group(_ s: String, _ match: NSTextCheckingResult, _ index: Int) -> String? {
        guard index < match.numberOfRanges else { return nil }
        let r = match.range(at: index)
        if r.location == NSNotFound { return nil }
        return (s as NSString).substring(with: r)
    }

    /// Kotlin `it.trim { it <= ' ' }`：只裁剪 <= 空格（0x20）的字符（含 \n \t \r）。
    static func trimSpaces(_ s: String) -> String {
        let units = Array(s.utf16)
        var a = 0, b = units.count
        while a < b && units[a] <= 0x20 { a += 1 }
        while b > a && units[b - 1] <= 0x20 { b -= 1 }
        return String(decoding: units[a..<b], as: UTF16.self)
    }

    /// Kotlin `String.isJson()/isJsonObject()/isJsonArray()/isXml()`
    static func isJsonObject(_ s: String?) -> Bool {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        return t.hasPrefix("{") && t.hasSuffix("}")
    }
    static func isJsonArray(_ s: String?) -> Bool {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        return t.hasPrefix("[") && t.hasSuffix("]")
    }
    static func isJson(_ s: String?) -> Bool { isJsonObject(s) || isJsonArray(s) }
    static func isXml(_ s: String?) -> Bool {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        return t.hasPrefix("<") && t.hasSuffix(">")
    }

    /// 对应 Kotlin `EncoderUtils.escape`：遍历的是 Kotlin 的 `Char`（UTF-16 单元），
    /// 所以 emoji 会拆成两个 %uXXXX（与 Java 一致）。
    static func escape(_ src: String) -> String {
        var out = ""
        for unit in src.utf16 {
            let code = Int(unit)
            if (code >= 48 && code <= 57) || (code >= 65 && code <= 90) || (code >= 97 && code <= 122) {
                out.append(Character(UnicodeScalar(unit) ?? " "))
                continue
            }
            let prefix: String
            if code < 16 { prefix = "%0" }
            else if code < 256 { prefix = "%" }
            else { prefix = "%u" }
            out += prefix + String(code, radix: 16)
        }
        return out
    }
}

/// 编码目标（对应 Kotlin 的 Charset 解析三分支）。
public enum AnalyzeUrlCharsetResult {
    case charset(AnalyzeUrlCharset)
    case escape
    case invalid
}

/// 需要用到的字符集（Kotlin `Charset.forName` 的子集；其它返回 nil -> 视为 invalid）。
public enum AnalyzeUrlCharset: String {
    case utf8 = "UTF-8"
    case gbk = "GBK"
    case gb2312 = "GB2312"
    case gb18030 = "GB18030"
    case iso88591 = "ISO-8859-1"
    case usAscii = "US-ASCII"

    public static func lookup(_ name: String) -> AnalyzeUrlCharset? {
        switch name.uppercased().replacingOccurrences(of: "_", with: "-") {
        case "UTF-8", "UTF8": return .utf8
        case "GBK", "CP936": return .gbk
        case "GB2312", "GB-2312": return .gb2312
        case "GB18030": return .gb18030
        case "ISO-8859-1", "LATIN1", "ISO8859-1": return .iso88591
        case "US-ASCII", "ASCII": return .usAscii
        default: return nil
        }
    }
}

/// 复刻 hutool `RFC3986.UNRESERVED.orNew(PercentCodec.of("!$%&()*+,/:;=?@[\\]^`{|}"))`：
/// 不编码 A-Za-z0-9-._~ 与 "!$%&()*+,/:;=?@[]^`{|}"（其余按 UTF-8 百分号编码，大写 hex）。
public enum AnalyzeUrlQueryEncoder {
    private static let safe: Set<UInt8> = {
        var s = Set<UInt8>()
        for b in Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~".utf8) { s.insert(b) }
        for b in Array("!$%&()*+,/:;=?@[]^`{|}".utf8) { s.insert(b) }
        return s
    }()

    public static func encode(_ input: String, charset: AnalyzeUrlCharset) -> String {
        var out = ""
        for scalar in input.unicodeScalars {
            // 只有「标量本身」在安全集里才原样输出；否则该标量的**全部字节**都转义
            // （对齐 hutool PercentCodec / Java URLEncoder：多字节编码里的 ASCII 字节同样转义）。
            if scalar.value < 128 && safe.contains(UInt8(scalar.value)) {
                out.unicodeScalars.append(scalar)
                continue
            }
            for b in CharsetBytes.encodeScalar(scalar, charset: charset) {
                out += String(format: "%%%02X", b)
            }
        }
        return out
    }
}

/// 复刻 java.net.URLEncoder.encode(value, charset)：a-zA-Z0-9 与 ".-*_" 保留，空格 -> '+'，其余 %XX。
public enum AnalyzeUrlURLEncoder {
    public static func encode(_ input: String, charset: AnalyzeUrlCharset) -> String {
        var out = ""
        for scalar in input.unicodeScalars {
            let v = scalar.value
            if (v >= 0x41 && v <= 0x5A) || (v >= 0x61 && v <= 0x7A) || (v >= 0x30 && v <= 0x39)
                || v == 0x2E || v == 0x2D || v == 0x2A || v == 0x5F {
                out.unicodeScalars.append(scalar)
                continue
            }
            if v == 0x20 { out.append("+"); continue }
            for b in CharsetBytes.encodeScalar(scalar, charset: charset) {
                out += String(format: "%%%02X", b)
            }
        }
        return out
    }
}

/// Cookie 合并（对应 Kotlin CookieManager.mergeCookies / CookieStore.mapToCookie 的纯函数部分）。
/// 6B 的真实 CookieStore 会提供更完整的实现；6A 的 buildRequest 只用这里的最小合并。
public enum CookieMerge {
    public static let cookieJarHeader = "CookieJar"

    /// 对应 Kotlin `CookieStore.cookieToMap`（保序）。
    public static func cookieToMap(_ cookie: String) -> [(String, String)] {
        var result: [(String, String)] = []
        if cookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return result }
        var pairs = cookie.components(separatedBy: ";")
        while let last = pairs.last, last.isEmpty { pairs.removeLast() }
        for pair in pairs {
            let kv = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            var parts = kv.map(String.init)
            while let last = parts.last, last.isEmpty { parts.removeLast() }
            if parts.count <= 1 { continue }
            let key = AnalyzeUrl.trimSpaces(parts[0])
            let value = parts[1]
            if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || AnalyzeUrl.trimSpaces(value) == "null" {
                setMap(&result, key, AnalyzeUrl.trimSpaces(value))
            }
        }
        return result
    }

    private static func setMap(_ map: inout [(String, String)], _ key: String, _ value: String) {
        if let idx = map.firstIndex(where: { $0.0 == key }) {
            map[idx].1 = value
        } else {
            map.append((key, value))
        }
    }

    /// 对应 Kotlin `CookieStore.mapToCookie`：空 -> nil。
    public static func mapToCookie(_ map: [(String, String)]) -> String? {
        if map.isEmpty { return nil }
        return map.map { "\($0.0)=\($0.1)" }.joined(separator: "; ")
    }

    /// 对应 Kotlin `CookieManager.mergeCookies(vararg)`：后面的覆盖前面的（键相同）。
    public static func mergeCookies(_ cookies: [String?]) -> String? {
        var merged: [(String, String)] = []
        for c in cookies {
            guard let c = c else { continue }
            for (k, v) in cookieToMap(c) { setMap(&merged, k, v) }
        }
        return mapToCookie(merged)
    }
}

// MARK: - 正则缓存（避免每次 new）

/// 轻量 NSRegularExpression 包装（编译失败时返回空结果，不崩溃）。
public final class NSRegularExpressionCache: @unchecked Sendable {
    private let regex: NSRegularExpression?
    public let pattern: String

    public init(pattern: String, options: NSRegularExpression.Options = []) {
        self.pattern = pattern
        self.regex = try? NSRegularExpression(pattern: pattern, options: options)
    }

    public func matches(in string: String) -> [NSTextCheckingResult] {
        guard let regex = regex else { return [] }
        return regex.matches(in: string, options: [], range: NSRange(location: 0, length: (string as NSString).length))
    }

    public func firstMatch(in string: String) -> NSTextCheckingResult? {
        guard let regex = regex else { return nil }
        return regex.firstMatch(in: string, options: [],
                                range: NSRange(location: 0, length: (string as NSString).length))
    }
}

/// 逐标量编码（对齐 Java `String.getBytes(charset)` / URLEncoder 的 REPLACE 语义：
/// 目标字符集里**不可表示**的字符 -> 单个 '?'(0x3F)）。GBK/GB2312 只认 GB18030 的 1-2 字节形式
/// （4 字节形式属 GB18030 扩展，Java 的 GBK 编码器对它同样给出 '?'）。
public enum CharsetBytes {
    public static func encodePerScalar(_ input: String, charset: AnalyzeUrlCharset) -> [UInt8] {
        var out: [UInt8] = []
        for scalar in input.unicodeScalars {
            out.append(contentsOf: encodeScalar(scalar, charset: charset))
        }
        return out
    }

    static func encodeScalar(_ scalar: Unicode.Scalar, charset: AnalyzeUrlCharset) -> [UInt8] {
        switch charset {
        case .utf8:
            return Array(String(scalar).utf8)
        case .usAscii:
            return scalar.value <= 0x7F ? [UInt8(scalar.value)] : [0x3F]
        case .iso88591:
            return scalar.value <= 0xFF ? [UInt8(scalar.value)] : [0x3F]
        case .gbk, .gb2312, .gb18030:
            let bytes = GBKBytes.encode(String(scalar))
            if bytes.isEmpty { return [0x3F] }
            if charset != .gb18030 && bytes.count > 2 { return [0x3F] }
            return bytes
        }
    }
}

/// GBK/GB2312/GB18030 的编码（Foundation 的 GB_18030-2000 → 字节）。
/// 用于 encodeParams 的非 UTF-8 分支；无法编码的字符按 Java URLEncoder 的替换语义记 `?`。
public enum GBKBytes {
    public static func encode(_ input: String) -> [UInt8] {
        let cf = CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        let nsEnc = CFStringConvertEncodingToNSStringEncoding(cf)
        if nsEnc != 0 && nsEnc != UInt(kCFStringEncodingInvalidId),
           let data = input.data(using: String.Encoding(rawValue: nsEnc)) {
            return Array(data)
        }
        // 回退：逐字符编码，失败用 '?'
        var out: [UInt8] = []
        for ch in input {
            if let d = String(ch).data(using: String.Encoding(rawValue: nsEnc)) {
                out.append(contentsOf: d)
            } else {
                out.append(0x3F)
            }
        }
        return out
    }
}
