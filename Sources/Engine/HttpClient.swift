import Foundation
import Security

/// A transport result, not a fabricated HTTP success. Code 0 means no HTTP
/// status was available (for example, HTML returned by WebView or a data URL).
struct HTTPResponseData: Sendable {
    let body: String
    let url: String
    let code: Int
    let headers: [String: String]
    /// 响应原始字节：文本解码失败的二进制为 nil，由 bodyBytes 兜底合成。
    let rawData: Data?

    init(body: String, url: String, code: Int = 0, headers: [String: String] = [:], rawData: Data? = nil) {
        self.body = body
        self.url = url
        self.code = code
        self.headers = headers
        self.rawData = rawData
    }

    init(body: String, response: URLResponse, fallbackURL: String, rawData: Data? = nil) {
        let http = response as? HTTPURLResponse
        var fields: [String: String] = [:]
        if let http = http {
            for (key, value) in http.allHeaderFields {
                fields[String(describing: key)] = String(describing: value)
            }
        }
        self.init(body: body, url: response.url?.absoluteString ?? fallbackURL,
                  code: http?.statusCode ?? 0, headers: fields, rawData: rawData)
    }

    /// response.body().bytes() 对应的总能拿到的字节（响应本质上就是字节流）。
    var bodyBytes: Data { rawData ?? Data(body.utf8) }
}

/// Parses Legado-style URLs: `https://x.com/search?q={{key}}&p={{page}},{"method":"POST","body":"k={{key}}","charset":"gbk","headers":{...}}`
struct AnalyzeUrl {
    var url: String
    var method: String = "GET"
    var body: String?
    var charset: String?
    var headers: [String: String] = [:]
    /// 教程 UrlOption.webView：非空即用 WebView 加载
    var webView: Bool = false
    /// ruleContent.webJs：WebView 加载后执行的 JS
    var webJs: String?
    let context: RuleContext?
    let jsLib: String?
    /// 书源 enabledCookieJar：关闭时本次请求不带、也不保存 Cookie。
    var cookieJarEnabled: Bool = true

    init(rawUrl: String, key: String? = nil, page: Int = 1, baseUrl: String? = nil,
         sourceHeader: String? = nil, context: RuleContext? = nil, jsLib: String? = nil,
         extraVars: [String: Any] = [:]) {
        self.context = context
        self.jsLib = jsLib
        self.cookieJarEnabled = context?.source?.cookieJarEnabled ?? true
        var s = rawUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        // @js: / <js></js> 先执行，再做模板替换（与 Legado 一致）
        s = AnalyzeUrl.evalUrlJS(s, key: key, page: page, baseUrl: baseUrl, context: context, jsLib: jsLib, extraVars: extraVars)
        s = AnalyzeUrl.substitute(s, key: key, page: page, context: context, jsLib: jsLib, extraVars: extraVars)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // <1,2,3> page selection
        if let r = s.range(of: "<[^>]+>", options: .regularExpression) {
            let items = s[r].dropFirst().dropLast().split(separator: ",").map(String.init)
            let idx = min(max(page - 1, 0), max(items.count - 1, 0))
            s.replaceSubrange(r, with: items.isEmpty ? "" : items[idx])
        }
        // Split options JSON
        var options: [String: Any]? = nil
        if let r = s.range(of: ",\\s*\\{", options: .regularExpression) {
            let jsonPart = String(s[s.index(after: r.lowerBound)...]).trimmingCharacters(in: .whitespaces)
            if let o = AnalyzeUrl.looseJSON(jsonPart) {
                options = o
                s = String(s[..<r.lowerBound])
            }
        }
        // `地址,` + 空的 java.get("headers")（变量丢失时）会留下结尾逗号，它会进入签名参数导致验签失败。
        if options == nil, s.hasSuffix(",") {
            s = String(s.dropLast()).trimmingCharacters(in: .whitespaces)
        }
        for (k, v) in AnalyzeUrl.headerFields(sourceHeader, key: key, page: page,
                                              baseUrl: baseUrl, context: context, jsLib: jsLib,
                                              extraVars: extraVars) {
            headers[k] = v
        }
        if let o = options {
            if let m = o["method"] as? String { method = m.uppercased() }
            if let b = o["body"] { body = (b as? String) ?? AnalyzeUrl.jsonString(b) }
            if let c = o["charset"] as? String { charset = c }
            if let h = o["headers"] as? [String: Any] { for (k, v) in h { headers[k] = "\(v)" } }
            if let w = o["webView"] {
                if let b = w as? Bool { webView = b }
                else if let n = w as? NSNumber { webView = n.boolValue }
                else if let t = w as? String { webView = !t.isEmpty && t.lowercased() != "false" }
                else { webView = !(w is NSNull) }
            }
        }
        // GBK/Big5 站点（第一版主 wd=…）：查询参数必须按对应字符集百分号编码后再提交。
        // Foundation 的 URL(string:).absoluteString 只会按 UTF-8 编码非 ASCII 字符，
        // 迟一步会把 GBK 关键词encode成 UTF-8 字节（如 wd=%E6%88%91%E7%9A%84），站点搜不到。
        // POST 表单体走 percentEncodedBody（已按 charset 编码），GET 参数在这里统一处理。
        if let c = charset, !c.lowercased().contains("utf-8"), !c.lowercased().contains("utf8") {
            // init 内不能调实例方法（此时 url 尚未赋值），用静态版本。
            s = AnalyzeUrl.percentEncoded(s, charset: charset)
        }
        url = AnalyzeUrl.absolute(s, base: baseUrl)
    }

    /// Legado 的书源 header 同样是规则：支持 `@js:`、`<js></js>` 与 `{{key}}/{{page}}`。
    /// 返回 JSON 对象时逐项作为请求头；直接返回 UA 字符串时作为 User-Agent。
    static func headerFields(_ raw: String?, key: String?, page: Int, baseUrl: String?,
                             context: RuleContext?, jsLib: String?, extraVars: [String: Any] = [:]) -> [String: String] {
        guard let raw else { return [:] }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [:] }
        let lowered = trimmed.lowercased()
        let evaluated: String
        if lowered.hasPrefix("@js:") || lowered.contains("<js>") {
            evaluated = evalUrlJS(trimmed, key: key, page: page, baseUrl: baseUrl,
                                  context: context, jsLib: jsLib, extraVars: extraVars)
        } else {
            evaluated = substitute(trimmed, key: key, page: page, context: context, jsLib: jsLib, extraVars: extraVars)
        }
        let text = evaluated.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [:] }
        if let o = looseJSON(text) {
            var fields: [String: String] = [:]
            for (k, v) in o { fields[k] = AnalyzeRule.asString(v) }
            return fields
        }
        // 部分导入书源把 UA 直接放在 header，而不是 JSON 对象。
        if text.hasPrefix("Mozilla/"), !text.contains("\n"), !text.contains("\r") {
            return ["User-Agent": text]
        }
        return [:]
    }

    /// 解析 Legado 常见的单引号 JSON，如 {'method':'POST','body':'k=v'}
    static func looseJSON(_ s: String) -> [String: Any]? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix("{") else { return nil }
        if let d = t.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] { return o }
        guard let r = JSEngine.shared.eval("JSON.stringify(eval('(' + __src + ')'))", vars: ["__src": t]) as? String,
              let d = r.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: d) as? [String: Any]
    }

    /// 执行 URL 规则里的 @js: 和 <js></js>，返回最终的 URL 字符串
    static func evalUrlJS(_ raw: String, key: String?, page: Int, baseUrl: String?, context: RuleContext? = nil, jsLib: String? = nil, extraVars: [String: Any] = [:]) -> String {
        // 与 Kotlin AppPattern.JS_PATTERN 一致：按出现顺序处理，大小写不敏感。
        guard let re = try? NSRegularExpression(
            pattern: "<js>([\\s\\S]*?)</js>|@js:([\\s\\S]*)",
            options: [.caseInsensitive]
        ) else { return raw }
        let text = raw as NSString
        let matches = re.matches(in: raw, range: NSRange(location: 0, length: text.length))
        guard !matches.isEmpty else { return raw }
        var result = raw
        var start = 0
        var vars: [String: Any] = ["key": key ?? "", "page": page, "searchKey": key ?? "", "searchPage": page]
        for (k, v) in extraVars { vars[k] = v }
        func applyLiteral(_ literal: String) {
            let value = literal.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                result = value.replacingOccurrences(of: "@result", with: result)
            }
        }
        for match in matches {
            if match.range.location > start {
                applyLiteral(text.substring(with: NSRange(location: start, length: match.range.location - start)))
            }
            let scriptRange = match.range(at: 2).location != NSNotFound ? match.range(at: 2) : match.range(at: 1)
            let value = JSEngine.shared.eval(text.substring(with: scriptRange), result: result,
                baseUrl: baseUrl ?? "", vars: vars, jsLib: jsLib, context: context)
            result = value.map { AnalyzeRule.asString($0) } ?? ""
            start = NSMaxRange(match.range)
        }
        if start < text.length { applyLiteral(text.substring(from: start)) }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func substitute(_ s: String, key: String?, page: Int, context: RuleContext? = nil, jsLib: String? = nil, extraVars: [String: Any] = [:]) -> String {
        let k = key ?? ""
        guard let re = try? NSRegularExpression(pattern: "\\{\\{([\\s\\S]*?)\\}\\}") else { return s }
        var result = s
        let original = s as NSString
        var jsVars: [String: Any] = ["key": k, "page": page, "searchKey": k, "searchPage": page]
        for (name, value) in extraVars { jsVars[name] = value }
        // Legado 先计算每个 {{js}}，再处理 page 标记，避免先替换 key 破坏 JS。
        for match in re.matches(in: s, range: NSRange(location: 0, length: original.length)).reversed() {
            let expr = original.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            let js = expr
            let value: String
            if js == "key" { value = k }
            else if js == "page" { value = "\(page)" }
            else if js == "baseUrl" { value = AnalyzeUrl.cleanSourceUrl(context?.source?.bookSourceUrl ?? "") }
            else if js == "host" && (jsLib ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                value = AnalyzeUrl.cleanSourceUrl(context?.source?.bookSourceUrl ?? "")
            }
            else if js.hasPrefix("@get:") { value = context?.get(String(js.dropFirst(5))) ?? "" }
            else {
                // 朗读 URL 的 {{speakText}}/{{speakSpeed}} 与 JS 表达式同通过这里求值。
                if let direct = extraVars[js] {
                    value = direct is String ? direct as! String : "\(direct)"
                } else {
                    value = JSEngine.shared.evalString(js, vars: jsVars, jsLib: jsLib, context: context) ?? ""
                }
            }
            result = (result as NSString).replacingCharacters(in: match.range, with: value)
        }
        return result.replacingOccurrences(of: "{key}", with: k)
            .replacingOccurrences(of: "{page}", with: "\(page)")
    }

    /// 书源地址里 # 之后是备注（如 https://x.com#🎃、https://x.com##），请求时去掉
    static func cleanSourceUrl(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if let i = t.firstIndex(of: "#") { return String(t[..<i]) }
        return t
    }

    static func absolute(_ s: String, base: String?) -> String {
        if s.hasPrefix("http://") || s.hasPrefix("https://") || s.hasPrefix("data:") { return s }
        // Legado 请求选项 `,{...}` 不属于网址：只解析前半段再原样拼回。
        // 否则 iOS 17+ 的 URL(string:) 会把 {"headers":…} 百分号编码进查询参数，请求头随之丢失。
        if let r = s.range(of: ",\\s*\\{", options: .regularExpression) {
            return absolute(String(s[..<r.lowerBound]), base: base) + String(s[r.lowerBound...])
        }
        guard let b = base.map({ AnalyzeUrl.cleanSourceUrl($0) }), let bu = URL(string: b) else { return s }
        return URL(string: s, relativeTo: bu)?.absoluteString ?? s
    }

    static func jsonString(_ o: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(o), let d = try? JSONSerialization.data(withJSONObject: o) else { return nil }
        return String(data: d, encoding: .utf8)
    }

    static func encoding(_ name: String?) -> String.Encoding {
        guard let n = name?.lowercased() else { return .utf8 }
        if n.contains("gb") {
            let cf = CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
            return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))
        }
        if n.contains("big5") {
            let cf = CFStringEncoding(CFStringEncodings.big5.rawValue)
            return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))
        }
        return .utf8
    }

    func percentEncoded(_ s: String) -> String {
        AnalyzeUrl.percentEncoded(s, charset: charset)
    }

    /// 按书源 charset 百分号编码（GET 查询串）。init 阶段求值时用它，
    /// 那时实例尚未初始化完成，不能调实例方法。
    static func percentEncoded(_ s: String, charset: String?) -> String {
        let enc = AnalyzeUrl.encoding(charset)
        if enc == .utf8 {
            return s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "+"))) ?? s
        }
        guard let d = s.data(using: enc) else { return s }
        return d.map { b -> String in
            let c = Character(UnicodeScalar(b))
            // '%' 保留：书源可能已带百分号转义（%XX），不能二次编码
            if b < 0x80 && (c.isLetter || c.isNumber || "-_.~=&/:?%".contains(c)) { return String(c) }
            return String(format: "%%%02X", b)
        }.joined()
    }

    /// Compatibility entry point for existing body/URL callers.
    func fetch() async throws -> (String, String) {
        let response = try await fetchResponse()
        return (response.body, response.url)
    }

    /// 朗读音频用的二进制请求：不做字符集转换，也不走 WebView 兜底。
    /// TTS 服务可能几十秒才返回（会话级合成），超时放宽；返回原始字节、响应与最终网址。
    func fetchData(session baseSession: URLSession = .shared,
                   readTimeout: TimeInterval = 120) async throws -> (data: Data, response: URLResponse, finalURL: String) {
        try Task.checkCancellation()
        let session: URLSession
        if cookieJarEnabled { session = baseSession } else {
            // ephemeral：自带的瞬态 Cookie 存储不跨会话持久化；显式禁用 Set-Cookie 与携带 Cookie。
            // （不把 httpCookieStorage 置 nil：macOS CLI 上真 HTTP 请求会直接崩溃。）
            let cfg = URLSessionConfiguration.ephemeral
            cfg.httpShouldSetCookies = false
            cfg.httpCookieAcceptPolicy = .never
            session = URLSession(configuration: cfg)
        }
        await rateLimitIfNeeded()
        let (_, u) = try applyRequestURL()
        let finalUrl = u.absoluteString
        var req = URLRequest(url: u, timeoutInterval: readTimeout)
        req.httpMethod = method
        if !cookieJarEnabled { req.httpShouldHandleCookies = false }
        if req.value(forHTTPHeaderField: "User-Agent") == nil {
            req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        }
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        if req.value(forHTTPHeaderField: "Referer") == nil, let host = u.host {
            req.setValue("\(u.scheme ?? "https")://\(host)/", forHTTPHeaderField: "Referer")
        }
        if let requestBody = resolvedRequestBody(), !(method == "GET" && requestBody.count <= 2) {
            req.httpBody = requestBody
            if req.value(forHTTPHeaderField: "Content-Type") == nil {
                let isJson = (body ?? "").trimmingCharacters(in: .whitespaces).hasPrefix("{")
                req.setValue(isJson ? "application/json" : "application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            }
        }
        let (data, resp) = try await send(req, session: session)
        try Task.checkCancellation()
        return (data, resp, finalUrl)
    }

    /// 表单正文按 charset 编码（百分号编码后为 ASCII，与原 UTF-8 写法等价）。
    private func resolvedRequestBody() -> Data? {
        guard let raw = body, !raw.isEmpty else { return nil }
        return percentEncodedBody(raw).data(using: AnalyzeUrl.encoding(charset))
    }

    /// 按 Legado 的「直接解析」生成最终 URL；已带百分号的串原样交 URL。
    /// 返回登录可能写补充头的最终 URL 与 Foundation URL。
    private func applyRequestURL() throws -> (String, URL) {
        let s = url.contains("%") ? url : percentEncoded(url)
        guard let u = URL(string: s) else { throw URLError(.badURL) }
        return (s, u)
    }

    /// HTTP 4xx/5xx remain responses; transport errors and cancellation throw.
    /// Session injection is local and does not register a global URLProtocol.
    func fetchResponse(session baseSession: URLSession = .shared, allowChallengeFallback: Bool = true,
                       deferAuthorizationChallenge: Bool = false) async throws -> HTTPResponseData {
        try Task.checkCancellation()
        // enabledCookieJar=false：用不存 Cookie 的临时会话，既不发送也不保存 Set-Cookie。
        let session: URLSession
        if cookieJarEnabled { session = baseSession } else {
            let cfg = baseSession.configuration.copy() as! URLSessionConfiguration
            cfg.httpCookieStorage = nil
            cfg.httpShouldSetCookies = false
            cfg.httpCookieAcceptPolicy = .never
            session = URLSession(configuration: cfg)
        }
        if url.hasPrefix("data:") {
            var payload = ""
            if let r = url.range(of: "base64,") { payload = String(url[r.upperBound...]) }
            payload = payload.trimmingCharacters(in: .whitespacesAndNewlines)
            while payload.count % 4 != 0 { payload += "=" }
            let bytes = Data(base64Encoded: payload) ?? Data()
            DebugLog.add("≡获取成功:\(DebugLog.url(url))")
            return HTTPResponseData(body: bytes.map { String(format: "%02x", $0) }.joined(), url: url)
        }
        #if canImport(UIKit) && canImport(WebKit)
        if webView || (webJs?.isEmpty == false) {
            let result = try await WebViewLoader.load(url: url, method: method, body: body.map { percentEncodedBody($0) },
                                                      headers: headers, js: webJs, cookieJar: cookieJarEnabled)
            try Task.checkCancellation()
            DebugLog.add("≡获取成功:\(DebugLog.url(result.1))")
            return HTTPResponseData(body: result.0, url: result.1)
        }
        #endif
        await rateLimitIfNeeded()
        let finalUrl = url.contains("%") ? url : percentEncoded(url)
        guard let u = URL(string: finalUrl) else { throw URLError(.badURL) }
        var req = URLRequest(url: u, timeoutInterval: 20)
        req.httpMethod = method
        // enabledCookieJar=false：不携带也不接收 Cookie（Legado 原版同样绕过 CookieJar）。
        if !cookieJarEnabled { req.httpShouldHandleCookies = false }
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        if req.value(forHTTPHeaderField: "Referer") == nil, let host = URL(string: finalUrl)?.host {
            req.setValue("\(u.scheme ?? "https")://\(host)/", forHTTPHeaderField: "Referer")
        }
        if let requestBody = resolvedRequestBody() {
            // URLSession 对 GET+body 的支持在 Apple 平台上不可靠（部分系统版本直接抛
            // NSURLErrorUnknown："Request has a body but no content length" 之类）。
            // 书源脚本普遍把空 body 序列化成 "{}" 挂在 GET 上（服务器不读它），这里剥掉。
            if method == "GET", requestBody.count <= 2 {
                DebugLog.add("≡GET 请求的空 body 已忽略")
            } else {
                req.httpBody = requestBody
                if req.value(forHTTPHeaderField: "Content-Type") == nil {
                    let isJson = (body ?? "").trimmingCharacters(in: .whitespaces).hasPrefix("{")
                    req.setValue(isJson ? "application/json" : "application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                }
            }
        }
        let cookiesBefore = (HTTPCookieStorage.shared.cookies(for: u) ?? []).count
        let (data, resp) = try await send(req, session: session)
        try Task.checkCancellation()
        var enc = AnalyzeUrl.encoding(charset)
        if charset == nil, let n = (resp as? HTTPURLResponse)?.textEncodingName { enc = AnalyzeUrl.encoding(n) }
        var text = String(data: data, encoding: enc)
        if text == nil { text = String(data: data, encoding: AnalyzeUrl.encoding("gbk")) }
        if charset == nil, enc == .utf8, let t = text, t.range(of: "charset=[\"']?gb", options: [.regularExpression, .caseInsensitive]) != nil {
            text = String(data: data, encoding: AnalyzeUrl.encoding("gbk")) ?? t
        }
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let rawData: Data? = data
        DebugLog.add("≡获取成功:\(DebugLog.url(finalUrl))")
        if !(200..<300).contains(status) { DebugLog.add("◇HTTP 状态:\(status)") }
        // 首次访问只下发 WAF/会话 Cookie 的站点（三八小说）：第一份响应是「错误提示」页，
        // 带着刚拿到的 Cookie 重发一次才会跳到真实结果。
        if cookieJarEnabled, cookiesBefore == 0, let t = text,
           WebViewSupport.isSessionCookieErrorPage(t, status: status),
           !(HTTPCookieStorage.shared.cookies(for: u) ?? []).isEmpty,
           let retry = try? await session.data(for: req, delegate: ExpiredCertificateAllowance.delegate) {
            try Task.checkCancellation()
            let retryStatus = (retry.1 as? HTTPURLResponse)?.statusCode ?? 0
            var retryEnc = AnalyzeUrl.encoding(charset)
            if charset == nil, let n = (retry.1 as? HTTPURLResponse)?.textEncodingName { retryEnc = AnalyzeUrl.encoding(n) }
            let retryText = String(data: retry.0, encoding: retryEnc)
                ?? String(data: retry.0, encoding: AnalyzeUrl.encoding("gbk")) ?? ""
            if (200..<300).contains(retryStatus), !retryText.isEmpty,
               !WebViewSupport.isSessionCookieErrorPage(retryText, status: retryStatus) {
                DebugLog.add("≡首次请求只拿到会话 Cookie，已带 Cookie 重试：\(retryText.count) 字符")
                return HTTPResponseData(body: retryText, response: retry.1, fallbackURL: finalUrl, rawData: retry.0)
            }
        }
        #if canImport(UIKit) && canImport(WebKit)
        let blocked = [403, 429, 503].contains(status) && (text ?? "").count < 200
        let deferredAuthorization = deferAuthorizationChallenge && [401, 403].contains(status)
        if allowChallengeFallback && !deferredAuthorization && (blocked || WebViewSupport.isChallenge(text ?? "")) {
            DebugLog.add("被拦截/需要验证：改用 WebView；验证后会重新请求原接口")
            if let r = try? await WebViewLoader.load(url: finalUrl, method: method, body: body.map { percentEncodedBody($0) },
                                                     headers: headers, js: webJs, cookieJar: cookieJarEnabled) {
                // JSON API 在 WebView 中会渲染为 <pre>，不能把外层HTML交给 JSONPath。
                // 同步验证 Cookie 后重新发原始请求，保留 POST 请求体。
                try Task.checkCancellation()
                await WebViewLoader.syncCookiesFromWebView(host: URL(string: finalUrl)?.host, enabled: cookieJarEnabled)
                try Task.checkCancellation()
                if let retry = try? await session.data(for: req, delegate: ExpiredCertificateAllowance.delegate) {
                    try Task.checkCancellation()
                    let retryStatus = (retry.1 as? HTTPURLResponse)?.statusCode ?? 0
                    let retryText = String(data: retry.0, encoding: enc) ?? String(data: retry.0, encoding: .utf8) ?? ""
                    DebugLog.add("验证后重试：HTTP \(retryStatus)，\(retry.0.count) 字节；\(DebugLog.summary(retryText))")
                    if (200...299).contains(retryStatus), !retryText.isEmpty, !WebViewSupport.isChallenge(retryText) {
                        return HTTPResponseData(body: retryText, response: retry.1, fallbackURL: finalUrl)
                    }
                }
                try Task.checkCancellation()
                if !r.0.isEmpty, !WebViewSupport.isChallenge(r.0) {
                    // WebView only supplies HTML and URL: do not reuse the original
                    // failure status/headers or invent a successful HTTP status.
                    return HTTPResponseData(body: r.0, url: r.1)
                }
            }
            try Task.checkCancellation()
            DebugLog.add("浏览器重试未获得可用数据；保留原始失败响应")
        }
        #endif
        try Task.checkCancellation()
        return HTTPResponseData(body: text ?? "", response: resp, fallbackURL: url, rawData: rawData)
    }

    // MARK: - 限流 / 重试

    /// 书源 concurrentRate：请求前按「次数/毫秒」等待，避免被站点限流。
    private func rateLimitIfNeeded() async {
        guard let source = context?.source else { return }
        await SourceRateLimiter.shared.acquire(key: source.bookSourceUrl, rate: source.concurrentRate)
    }

    /// 通用退避重试：只重试「请求根本没拿到响应」的传输错误（超时、连接被重置、DNS 失败）。
    /// 不按 HTTP 状态码重试：状态码属于书源自己的业务语义（401 触发登录、429/5xx 由书源脚本
    /// 换线路），引擎自行重发会让同一次详情请求变成多次，既破坏既有的请求计数契约，
    /// 也可能把站点的限流拖得更久。
    /// 只重试 GET/HEAD：POST 等可能是提交动作，重发会造成重复下单/重复登录。
    private func send(_ req: URLRequest, session: URLSession,
                      maxAttempts: Int = 3) async throws -> (Data, URLResponse) {
        let method = (req.httpMethod ?? "GET").uppercased()
        let attempts = Self.idempotentMethods.contains(method) ? maxAttempts : 1
        var attempt = 1
        while true {
            do {
                return try await session.data(for: req, delegate: ExpiredCertificateAllowance.delegate)
            } catch {
                guard attempt < attempts, Self.retryableError(error), !Task.isCancelled else { throw error }
                let delay = Self.backoff(attempt)
                DebugLog.add("≡请求失败（\(error.localizedDescription)），\(Int(delay * 1000))ms 后重试（第 \(attempt) 次）")
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                attempt += 1
            }
        }
    }

    /// 可安全重发的 HTTP 方法（RFC 9110 幂等方法的常用子集）。
    static let idempotentMethods: Set<String> = ["GET", "HEAD"]

    static func retryableError(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .timedOut, .networkConnectionLost, .cannotConnectToHost,
             .cannotFindHost, .dnsLookupFailed, .resourceUnavailable:
            return true
        default:
            return false
        }
    }

    private static func backoff(_ attempt: Int) -> TimeInterval {
        // 0.4s / 1.2s，加少量抖动避免多本书同时重试。
        let base = attempt == 1 ? 0.4 : 1.2
        return base + Double.random(in: 0...0.2)
    }


    /// 表单 body 按 key=value 逐项做 URL 编码（与 Legado 一致），charset 为 gbk 时按 GBK 字节编码
    private func percentEncodedBody(_ b: String) -> String {
        let t = b.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("{") || t.hasPrefix("[") { return b }
        if t.range(of: "%[0-9A-Fa-f]{2}", options: .regularExpression) != nil { return b }
        return t.components(separatedBy: "&").map { pair -> String in
            guard let eq = pair.firstIndex(of: "=") else { return encodeComponent(pair) }
            let k = String(pair[..<eq])
            let v = String(pair[pair.index(after: eq)...])
            return encodeComponent(k) + "=" + encodeComponent(v)
        }.joined(separator: "&")
    }

    func encodeComponent(_ s: String) -> String {
        let enc = AnalyzeUrl.encoding(charset)
        guard let d = s.data(using: enc) else { return s }
        return d.map { b -> String in
            if (b >= 0x30 && b <= 0x39) || (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A)
                || b == 0x2D || b == 0x5F || b == 0x2E || b == 0x7E || b == 0x2A {
                return String(UnicodeScalar(b))
            }
            return String(format: "%%%02X", b)
        }.joined()
    }
}
