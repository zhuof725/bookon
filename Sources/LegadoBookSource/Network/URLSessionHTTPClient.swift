//
//  URLSessionHTTPClient.swift
//  LegadoBookSource
//
//  第 6 步 6B：HTTPClient 协议的真实网络实现（URLSession）。
//
//  对应 Kotlin：
//   - HttpHelper.kt：okHttpClient 的默认超时（connectTimeout 15s / writeTimeout 15s /
//     readTimeout 60s / callTimeout 60s）与 getProxyClient(proxy) 的代理解析；
//   - AnalyzeUrl.kt getClient()：readTimeout / callTimeout 的按请求覆盖
//     （readTimeout 非空时 callTimeout = max(60s, readTimeout*2)；callTimeout 非空时直接使用）；
//   - OkHttpUtils.kt newCallResponse(retry)：最多 1+retry 次，2xx 提前返回；
//   - RedirectInterceptor（OkHttp 4.10）：301/302 对 POST 转 GET、303 转 GET、
//     307/308 保持方法与 body、最多 20 跳、跨连接去掉 Authorization、不自动加 Referer；
//   - DecompressInterceptor.kt：gzip/deflate 解压（本移植依赖 URLSession 自动解压，见下方差异）；
//   - SSLHelper.kt：unsafeTrustManager / unsafeHostnameVerifier —— 信任所有服务器证书
//     （安全取舍，见类注释）；
//   - CookieManager.kt：loadRequest / saveResponse（本移植在每次请求前注入、每跳响应后保存）；
//   - StrResponse.kt：url / status / message / headers / body / callTime 的组装；
//   - executeStrRequest 的异常分类：SocketTimeoutException -> -2、UnknownHostException -> -3、
//     ConnectException -> -4、SocketException -> -5、SSLException -> -6、
//     InterruptedIOException(timeout) -> -1、其它 -> -7。
//
//  ⚠️ 与 Kotlin 的差异（逐条在正文「差异：」注释中标注；汇总清单由上级整理进 README 差异表）：
//   1. reason phrase：URLSession 不暴露 HTTP 状态短语，用标准短语表近似（Kotlin 用服务器原话）；
//   2. 响应头：allHeaderFields 不保留原始顺序、非 Set-Cookie 的重复头会被折叠
//      （OkHttp Headers 保序且允许重复），本移植按 key 排序输出、Set-Cookie 重复项保留；
//   3. 压缩：URLSession 自动加 Accept-Encoding 并透明解压（OkHttp 自己加头、DecompressInterceptor
//      手动解压）；本移植**不再手工解压**（避免双重解压）。raw-deflate（无 zlib 头）变体在部分
//      系统版本上 URLSession 可能不解压，属平台差异；
//   4. 自动 UA / Keep-Alive / Connection / Cache-Control：legado 的拦截器会补这些头，
//      本移植不自动补（上层在 headers 里给）；URLSession 自带 UA 与 keep-alive 管理；
//   5. Cookie 门控：Kotlin 的 loadRequest/saveResponse 仅在请求带 CookieJar: 1 头时生效，
//      本移植按任务约定无条件注入/保存（CookieJar 头本身由 AnalyzeUrl.buildRequest 负责）；
//   6. Referer：OkHttp 同源重定向会加 Referer（BridgeInterceptor），URLSession 不会自动设置，
//      本移植按任务约定不设置（行为更接近"不带 Referer"）；
//   7. 超时：URLSession 没有独立的 connectTimeout / writeTimeout（timeoutIntervalForRequest
//      兼作读写空闲超时）；callTimeout 用 Task 超时实现；
//   8. 303 + HEAD：OkHttp 对 HEAD 的 303 保持 HEAD，本移植按任务约定「303 一律转 GET」；
//   9. dnsIp：URLSession 无法自定义解析，记 diagnostics 后忽略（Kotlin OkHttp Dns 可直连指定 IP）；
//   10. 代理认证：Kotlin getProxyClient 支持 user:pass@ 的 Proxy-Authorization basic，
//      本移植忽略凭据（记 diagnostics），只使用 host:port；
//   11. WebView：Kotlin 先发真实请求再把结果灌进 BackstageWebView 渲染；本移植按任务约定
//      直接调用注入的 WebJSProvider.eval，不发网络请求；
//   12. 会话复用：OkHttp 有连接池；本移植每次 execute 新建一个 URLSession（可后续做会话池）。
//

import Foundation
import CFNetwork

/// `HTTPClient` 的真实实现：基于 URLSession（ephemeral 配置 + 手工管理 Cookie + 手工重定向）。
///
/// 对 Kotlin 的对应关系一览：
/// - 超时默认值来自 HttpHelper.kt 的 okHttpClient（read 60s / call 60s），
///   按请求覆盖来自 AnalyzeUrl.kt `getClient()`（readTimeout 毫秒 + callTimeout 毫秒）；
/// - retry 语义来自 OkHttpUtils.kt `newCallResponse(retry)`：for (i in 0..retry) 最多 1+retry 次，
///   只有 2xx 提前返回；**网络异常不重试**（Kotlin 的 await() 异常直接向上抛）；
/// - 证书策略对齐 SSLHelper.kt：信任所有服务器证书。
///
/// ⚠️ 安全取舍（对应 legado SSLHelper 的 unsafeTrustManager / unsafeHostnameVerifier）：
/// **legado 信任所有证书**，本实现同样接受任意服务器证书（`URLCredential(trust:)`），
/// 以保持书源行为一致。App 集成方需要 NSAllowsArbitraryLoads（明文 HTTP 允许，
/// 第 7 步处理）并在安全敏感场景自行收紧证书策略（iOS 的 ATS 默认策略在本类中被绕过）。
public final class URLSessionHTTPClient: NSObject, HTTPClient, @unchecked Sendable {

    /// 重定向上限（对应 OkHttp RedirectInterceptor.MAX_FOLLOW_UPS = 20）。
    private static let maxRedirects = 20
    /// HttpHelper.kt：`.readTimeout(60, SECONDS)`。
    private static let defaultReadTimeoutMillis: Int64 = 60_000
    /// HttpHelper.kt：`.callTimeout(60, SECONDS)`。
    private static let defaultCallTimeoutMillis: Int64 = 60_000

    private let cookieStore: CookieStore
    private let cookieManagerCache: CacheManager
    private let diagnostics: RuleEngineDiagnostics?
    private let webJSProvider: WebJSProvider

    /// - Parameters:
    ///   - cookieStore: 持久化 Cookie 的存储（对应 Kotlin `CookieStore`）。
    ///   - cookieManagerCache: CookieManager 的 session cookie / 内存缓存（对应 Kotlin `CacheManager`）。
    ///   - diagnostics: 非致命诊断收集器（默认为 nil，不收集）。
    ///   - webJSProvider: useWebView 分支的执行器（默认 Unsupported 抛 unsupported）。
    public init(cookieStore: CookieStore,
                cookieManagerCache: CacheManager,
                diagnostics: RuleEngineDiagnostics? = nil,
                webJSProvider: WebJSProvider = UnsupportedWebJSProvider()) {
        self.cookieStore = cookieStore
        self.cookieManagerCache = cookieManagerCache
        self.diagnostics = diagnostics
        self.webJSProvider = webJSProvider
    }

    /// 执行一次请求，返回响应（非 2xx 也照常返回，由上层判断）。
    ///
    /// 对应 Kotlin `AnalyzeUrl.executeStrRequest` / `getResponseAwait` 的网络部分 +
    /// `OkHttpUtils.newCallResponse(retry)` 的重试语义：
    /// 最多尝试 1+retry 次，遇到 2xx 提前返回；**网络异常立即抛出**（Kotlin 不重试异常）。
    ///
    /// - Throws:
    ///   - `HTTPError`：网络/超时/代理等错误，kind 对齐 executeStrRequest 的异常分类
    ///     （.socketTimeout / .unknownHost / .connectRefused / .socket / .ssl /
    ///     .timeoutOverCallLimit / .other）。
    ///   - `RuleEngineError.unsupported`：useWebView 分支且 WebJSProvider 不可用。
    public func execute(_ request: HTTPRequest) async throws -> HTTPResponse {
        // 对应 Kotlin executeStrRequest 的 `if (this.useWebView && useWebView)` 分支。
        // 差异：Kotlin 先发真实请求再把响应灌进 BackstageWebView 渲染；本移植按任务约定
        // 不发网络请求，直接调用注入的 WebJSProvider.eval，失败抛 RuleEngineError.unsupported。
        if request.useWebView {
            let start = Date()
            do {
                let result = try await webJSProvider.eval(js: request.webJs ?? "",
                                                          result: "",
                                                          baseUrl: request.url)
                let callTime = Int(Date().timeIntervalSince(start) * 1000)
                return HTTPResponse(url: request.url,
                                    status: 200,
                                    message: "OK",
                                    headers: [],
                                    body: Data(result.utf8),
                                    callTime: callTime)
            } catch let error as RuleEngineError {
                throw error
            } catch {
                diagnostics?.record(source: "URLSessionHTTPClient.execute",
                                    rule: request.url,
                                    message: "useWebView 执行失败：\(error)")
                throw RuleEngineError.unsupported("WebJs 执行失败：\(error)")
            }
        }

        // 差异：dnsIp 自定义解析（Kotlin getClient() 的 `dns { ... }`）URLSession 不支持，
        // 记一条 diagnostics 后照常请求（绝不崩溃）。
        if let dnsIp = request.dnsIp, !dnsIp.isEmpty {
            diagnostics?.record(source: "URLSessionHTTPClient.execute",
                                rule: request.url,
                                message: "dnsIp 自定义解析 URLSession 不支持，已忽略（dnsIp=\(dnsIp)）")
        }

        // 对应 OkHttpUtils.newCallResponse(retry)：for (i in 0..retry)。
        let attempts = max(0, request.retry) + 1
        var lastResponse: HTTPResponse?
        for _ in 0..<attempts {
            let response = try await performAttempt(request) // 网络错误立即抛出（不重试异常）
            lastResponse = response
            if (200...299).contains(response.status) {
                return response
            }
        }
        guard let last = lastResponse else {
            // 防御分支：attempts >= 1 时不会走到这里（满足"不强制解包"规则）。
            throw HTTPError(kind: .other, message: "请求未产生响应：\(request.url)")
        }
        return last
    }

    // MARK: - 单次尝试

    /// 执行一次网络尝试（重定向、超时、Cookie 注入都在这一层）。
    /// 每次尝试使用独立的 URLSession + delegate（delegate 持有重定向跳数等一次性状态，
    /// 保证并发 execute 互不干扰）。
    private func performAttempt(_ request: HTTPRequest) async throws -> HTTPResponse {
        guard let url = URL(string: request.url) else {
            diagnostics?.record(source: "URLSessionHTTPClient.performAttempt",
                                rule: request.url,
                                message: "无法解析请求 URL")
            throw HTTPError(kind: .other, message: "无法解析请求 URL：\(request.url)")
        }
        let attemptStart = Date()
        let configuration = makeConfiguration(for: request)
        let delegate = AttemptDelegate(client: self, originalBody: request.body)
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        let urlRequest = makeURLRequest(url: url, request: request)
        let callTimeoutMs = Self.callTimeoutMillis(for: request)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await withCallTimeout(millis: callTimeoutMs) {
                try await session.data(for: urlRequest)
            }
        } catch {
            throw Self.mapError(error, requestURL: request.url)
        }
        guard let http = response as? HTTPURLResponse else {
            throw HTTPError(kind: .other, message: "非 HTTP 响应：\(request.url)")
        }
        // 最终响应的 Set-Cookie 也要保存（中间跳的 Set-Cookie 在 delegate 里保存）。
        saveCookies(from: http)
        let headers = Self.orderedHeaders(from: http)
        let callTime = Int(Date().timeIntervalSince(attemptStart) * 1000)
        // 对应 StrResponse：url 取最终请求 URL（Kotlin `response.request.url`）。
        return HTTPResponse(url: http.url?.absoluteString ?? request.url,
                            status: http.statusCode,
                            message: Self.reasonPhrase(for: http.statusCode),
                            headers: headers,
                            body: data,
                            callTime: callTime)
    }

    /// 组装 URLSession 配置。
    ///
    /// 对应 HTTPRequest -> OkHttp 客户端的映射（HttpHelper.kt + AnalyzeUrl.kt getClient()）：
    /// - ephemeral + httpShouldHandleCookies = false：Cookie 自己管（任务 6B-a），
    ///   对应 Kotlin 把 okHttpClient 的 cookieJar 注释掉、由 CookieManager 手工管理；
    /// - 超时：默认 readTimeout 60s；request.readTimeout（毫秒）覆盖；
    ///   callTimeout 在 withCallTimeout 里实现（本配置不体现）；
    /// - 代理：request.proxy 解析进 connectionProxyDictionary（对应 getProxyClient）；
    /// - 缓存：OkHttp 默认无缓存（无 .cache()），用 reloadIgnoringLocalCacheData + urlCache=nil 对齐。
    private func makeConfiguration(for request: HTTPRequest) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldHandleCookies = false
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.waitsForConnectivity = false
        // 差异：URLSession 无独立 connectTimeout/writeTimeout；timeoutIntervalForRequest
        // 兼作连接与读写空闲超时（Kotlin connectTimeout 15s / writeTimeout 15s / readTimeout 60s）。
        configuration.timeoutIntervalForRequest =
            TimeInterval(Self.readTimeoutMillis(for: request)) / 1000.0

        if let proxy = request.proxy, !proxy.isEmpty {
            if let dict = Self.parseProxy(proxy) {
                configuration.connectionProxyDictionary = dict as [AnyHashable: Any]
            } else {
                diagnostics?.record(source: "URLSessionHTTPClient.makeConfiguration",
                                    rule: request.url,
                                    message: "代理地址解析失败，已忽略：\(proxy)")
            }
        }
        return configuration
    }

    /// 按 HTTPRequest 组装 URLRequest（含 Cookie 注入）。
    private func makeURLRequest(url: URL, request: HTTPRequest) -> URLRequest {
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method.rawValue
        for (name, value) in request.headers {
            urlRequest.addValue(value, forHTTPHeaderField: name)
        }
        if request.method == .post, let body = request.body {
            urlRequest.httpBody = body
            // OkHttp 的 RequestBody 会带 Content-Type；buildRequest 已给出 contentType，
            // 若 headers 里没有 Content-Type 则补上（防止重复则不动）。
            if let contentType = request.contentType,
               urlRequest.value(forHTTPHeaderField: "Content-Type") == nil {
                urlRequest.setValue(contentType, forHTTPHeaderField: "Content-Type")
            }
        }
        // Cookie 注入（对应 Kotlin CookieManager.loadRequest）：已有 Cookie 头则合并。
        // 差异：Kotlin 以 CookieJar: 1 头为开关，本移植按任务约定无条件注入。
        if let merged = CookieManager.cookieHeaderFor(url: request.url,
                                                      existingHeader: request.header("Cookie"),
                                                      store: cookieStore,
                                                      cache: cookieManagerCache) {
            urlRequest.setValue(merged, forHTTPHeaderField: "Cookie")
        }
        return urlRequest
    }

    /// callTimeout 毫秒（实现 withCallTimeout）。对应 HttpHelper.kt 的 callTimeout(60s)
    /// 与 AnalyzeUrl.kt getClient() 的 `callTimeout(max(60s, readTimeout*2))`。
    static func callTimeoutMillis(for request: HTTPRequest) -> Int64 {
        if let ct = request.callTimeout { return max(0, ct) }
        if let rt = request.readTimeout { return max(defaultCallTimeoutMillis, rt * 2) }
        return defaultCallTimeoutMillis
    }

    /// readTimeout 毫秒（写进 timeoutIntervalForRequest）。对应 HttpHelper.kt 的 readTimeout(60s)
    /// 与 AnalyzeUrl.kt getClient() 的 readTimeout 覆盖。
    static func readTimeoutMillis(for request: HTTPRequest) -> Int64 {
        if let rt = request.readTimeout { return max(0, rt) }
        return defaultReadTimeoutMillis
    }

    // MARK: - CallTimeout（对应 OkHttp callTimeout；超时 -> .timeoutOverCallLimit）

    /// 用 Task 实现 callTimeout：超时取消网络任务并抛 `HTTPError(kind: .timeoutOverCallLimit)`，
    /// 对应 Kotlin InterruptedIOException(timeout) -> -1。
    /// 上层任务被取消时原样传播 `CancellationError`（对应 Kotlin await() 的
    /// invokeOnCancellation { cancel() } + CancellationException）。
    private func withCallTimeout<T>(millis: Int64,
                                    _ operation: @escaping () async throws -> T) async throws -> T {
        let attempt = Task { try await operation() }
        let timeoutTask: Task<Void, Never>?
        if millis > 0 {
            timeoutTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(millis) * 1_000_000)
                attempt.cancel()
            }
        } else {
            timeoutTask = nil
        }
        return try await withTaskCancellationHandler {
            do {
                let value = try await attempt.value
                timeoutTask?.cancel()
                return value
            } catch is CancellationError {
                timeoutTask?.cancel()
                if Task.isCancelled { throw CancellationError() }
                throw HTTPError(kind: .timeoutOverCallLimit,
                                message: "超过设定时间（callTimeout \(millis) ms）")
            } catch let error as URLError where error.code == .cancelled {
                timeoutTask?.cancel()
                if Task.isCancelled { throw CancellationError() }
                throw HTTPError(kind: .timeoutOverCallLimit,
                                message: "超过设定时间（callTimeout \(millis) ms）")
            } catch {
                timeoutTask?.cancel()
                throw error
            }
        } onCancel: {
            attempt.cancel()
        }
    }

    // MARK: - 错误映射（对应 executeStrRequest 的异常分类）

    /// 把 URLSession 错误映射成 `HTTPError`，kind 对齐 Kotlin executeStrRequest 的 errorCode：
    /// 超时 -> .socketTimeout(-2)、域名解析失败 -> .unknownHost(-3)、连接被拒 -> .connectRefused(-4)、
    /// 连接重置/Socket -> .socket(-5)、SSL -> .ssl(-6)、其它 -> .other(-7)。
    static func mapError(_ error: Error, requestURL: String) -> HTTPError {
        if let httpError = error as? HTTPError { return httpError }
        let nsError = error as NSError
        let message = "\(requestURL)：\(nsError.localizedDescription)"
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorTimedOut:
                return HTTPError(kind: .socketTimeout, message: message)
            case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed:
                return HTTPError(kind: .unknownHost, message: message)
            case NSURLErrorCannotConnectToHost:
                return HTTPError(kind: .connectRefused, message: message)
            case NSURLErrorNetworkConnectionLost, NSURLErrorDataLengthExceeded:
                return HTTPError(kind: .socket, message: message)
            case NSURLErrorSecureConnectionFailed,
                 NSURLErrorServerCertificateUntrusted,
                 NSURLErrorServerCertificateHasBadDate,
                 NSURLErrorServerCertificateHasUnknownRoot,
                 NSURLErrorServerCertificateNotYetValid,
                 NSURLErrorClientCertificateRejected,
                 NSURLErrorClientCertificateRequired,
                 NSURLErrorAppTransportSecurityRequiresSecureConnection:
                return HTTPError(kind: .ssl, message: message)
            default:
                return HTTPError(kind: .other, message: message)
            }
        }
        return HTTPError(kind: .other, message: message)
    }

    // MARK: - 响应头与状态短语

    /// 把 `HTTPURLResponse.allHeaderFields` 转成有序 `[(String, String)]`。
    ///
    /// 差异：allHeaderFields 不保留原始顺序且非 Set-Cookie 的重复头会被折叠
    /// （OkHttp Headers 保序且允许重复），这里按 key 排序保证确定性；Set-Cookie 的重复项
    /// Foundation 会保留为同 key 多条（个别系统版本可能用换行拼接，这里按换行拆开兜底）。
    static func orderedHeaders(from http: HTTPURLResponse) -> [(String, String)] {
        var out: [(String, String)] = []
        let fields = http.allHeaderFields
        let keys = fields.keys.compactMap { $0 as? String }
            .sorted { $0.lowercased() < $1.lowercased() }
        for key in keys {
            guard let value = fields[key] as? String else { continue }
            if key.caseInsensitiveCompare("Set-Cookie") == .orderedSame {
                for line in value.components(separatedBy: "\n") {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { out.append(("Set-Cookie", trimmed)) }
                }
            } else {
                out.append((key, value))
            }
        }
        return out
    }

    /// HTTP 状态短语。差异：URLSession 不暴露 reason phrase（Kotlin `raw.message` 是服务器原话），
    /// 这里用标准短语表近似。
    static func reasonPhrase(for status: Int) -> String? {
        switch status {
        case 100: return "Continue"
        case 101: return "Switching Protocols"
        case 200: return "OK"
        case 201: return "Created"
        case 202: return "Accepted"
        case 203: return "Non-Authoritative Information"
        case 204: return "No Content"
        case 205: return "Reset Content"
        case 206: return "Partial Content"
        case 300: return "Multiple Choices"
        case 301: return "Moved Permanently"
        case 302: return "Found"
        case 303: return "See Other"
        case 304: return "Not Modified"
        case 305: return "Use Proxy"
        case 307: return "Temporary Redirect"
        case 308: return "Permanent Redirect"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 402: return "Payment Required"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 406: return "Not Acceptable"
        case 407: return "Proxy Authentication Required"
        case 408: return "Request Timeout"
        case 409: return "Conflict"
        case 410: return "Gone"
        case 411: return "Length Required"
        case 412: return "Precondition Failed"
        case 413: return "Payload Too Large"
        case 414: return "URI Too Long"
        case 415: return "Unsupported Media Type"
        case 416: return "Range Not Satisfiable"
        case 417: return "Expectation Failed"
        case 426: return "Upgrade Required"
        case 428: return "Precondition Required"
        case 429: return "Too Many Requests"
        case 431: return "Request Header Fields Too Large"
        case 500: return "Internal Server Error"
        case 501: return "Not Implemented"
        case 502: return "Bad Gateway"
        case 503: return "Service Unavailable"
        case 504: return "Gateway Timeout"
        case 505: return "HTTP Version Not Supported"
        case 511: return "Network Authentication Required"
        default: return nil
        }
    }

    // MARK: - Cookie 保存

    /// 保存一次 HTTPURLResponse 的所有 Set-Cookie（对应 Kotlin CookieManager.saveResponse /
    /// saveCookiesFromHeaders；持久化 vs 会话分流在 CookieManager 内完成）。
    private func saveCookies(from http: HTTPURLResponse) {
        guard let url = http.url?.absoluteString else { return }
        let setCookies = Self.orderedHeaders(from: http)
            .filter { $0.0.caseInsensitiveCompare("Set-Cookie") == .orderedSame }
            .map { $0.1 }
        guard !setCookies.isEmpty else { return }
        CookieManager.saveCookiesFromHeaders(url: url,
                                             setCookieHeaders: setCookies,
                                             store: cookieStore,
                                             cache: cookieManagerCache)
    }

    // MARK: - 代理解析（对应 Kotlin getProxyClient）

    /// 把 `"host:port"` / `"http://host:port"` / `"socks5://host:port"` 解析成
    /// `connectionProxyDictionary` 内容；解析失败返回 nil（调用方记 diagnostics 并忽略）。
    ///
    /// 对应 Kotlin getProxyClient 的 Regex `(http|socks4|socks5)://(.*):(\d{2,5})(@.*@.*)?`：
    /// - http(s) 代理：同时启用 HTTP 与 HTTPS 代理（OkHttp 的 Proxy.Type.HTTP 两者都走）；
    /// - socks：走 SOCKS 代理（对应 Proxy.Type.SOCKS）；
    /// - 差异：Kotlin 支持 `user:pass@` 的 Proxy-Authorization basic 认证，
    ///   本移植忽略凭据（见 parseProxy 调用处记录 diagnostics）。
    static func parseProxy(_ proxy: String) -> [String: Any]? {
        var scheme = "http"
        var rest = proxy
        let lower = proxy.lowercased()
        if lower.hasPrefix("socks5://") {
            scheme = "socks"
            rest = String(proxy.dropFirst("socks5://".count))
        } else if lower.hasPrefix("http://") {
            rest = String(proxy.dropFirst("http://".count))
        }
        // Kotlin regex 的 `(@.*@.*)?` 携带 user/password，这里剥掉 userinfo 只留 host:port。
        if let at = rest.lastIndex(of: "@") {
            rest = String(rest[rest.index(after: at)...])
        }
        guard let colon = rest.lastIndex(of: ":") else { return nil }
        let host = String(rest[rest.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
        let portString = String(rest[rest.index(after: colon)...])
        guard !host.isEmpty, let port = Int(portString), (1...65535).contains(port) else { return nil }
        if scheme == "socks" {
            return [
                kCFNetworkProxiesSOCKSEnable as String: true,
                kCFNetworkProxiesSOCKSProxy as String: host,
                kCFNetworkProxiesSOCKSPort as String: port
            ]
        }
        return [
            kCFNetworkProxiesHTTPEnable as String: true,
            kCFNetworkProxiesHTTPProxy as String: host,
            kCFNetworkProxiesHTTPPort as String: port,
            kCFNetworkProxiesHTTPSEnable as String: true,
            kCFNetworkProxiesHTTPSProxy as String: host,
            kCFNetworkProxiesHTTPSPort as String: port
        ]
    }

    /// OkHttp RedirectInterceptor 的 sameConnection：host/port/scheme 全部相同才算同一连接
    /// （跨连接重定向会去掉 Authorization）。
    static func sameConnection(_ a: URL?, _ b: URL?) -> Bool {
        guard let a = a, let b = b else { return false }
        return a.scheme?.lowercased() == b.scheme?.lowercased()
            && a.host?.lowercased() == b.host?.lowercased()
            && (a.port ?? Self.defaultPort(for: a.scheme)) == (b.port ?? Self.defaultPort(for: b.scheme))
    }

    private static func defaultPort(for scheme: String?) -> Int? {
        switch scheme?.lowercased() {
        case "http": return 80
        case "https": return 443
        default: return nil
        }
    }

    // MARK: - 单次尝试的 delegate（重定向 / 证书）

    /// 每次尝试的 URLSession delegate：持有跳数计数与原始 body。
    /// delegate 回调在 URLSession 的串行 delegateQueue 上执行，跳数无并发问题。
    private final class AttemptDelegate: NSObject, URLSessionTaskDelegate, URLSessionDataDelegate {
        private let client: URLSessionHTTPClient
        /// 307/308 重定向需要重放请求体（URLSession 发出后会消费 httpBodyStream，
        /// 这里保留原始 Data 的拷贝）。
        private let originalBody: Data?
        private var redirectHopCount = 0

        init(client: URLSessionHTTPClient, originalBody: Data?) {
            self.client = client
            self.originalBody = originalBody
        }

        // MARK: 重定向（手工处理，对应 OkHttp RedirectInterceptor）

        /// 手工重定向：最多 `maxRedirects` 跳；每一跳先保存 Set-Cookie；
        /// 301/302 对 POST 转 GET 且丢 body、303 转 GET（任务约定「一律转 GET」）、
        /// 307/308 保持方法与 body；超限返回最后一跳的响应并记 diagnostics「重定向过多」。
        /// 差异：OkHttp 同源重定向由 BridgeInterceptor 加 Referer，这里按任务约定不设置。
        func urlSession(_ session: URLSession,
                        task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) {
            // 每一跳的中间响应都要保存 Set-Cookie（对应 Kotlin CookieManager.saveResponse，
            // legado 的 network interceptor 对每一跳响应都生效）。
            client.saveCookies(from: response)

            redirectHopCount += 1
            if redirectHopCount > URLSessionHTTPClient.maxRedirects {
                client.diagnostics?.record(
                    source: "URLSessionHTTPClient.willPerformHTTPRedirection",
                    rule: task.currentRequest?.url?.absoluteString ?? "",
                    message: "重定向过多（超过 \(URLSessionHTTPClient.maxRedirects) 跳），返回最后一跳的响应")
                // 停止跟随：URLSession 会把当前 3xx 响应作为最终响应返回。
                completionHandler(nil)
                return
            }
            guard let targetURL = request.url else {
                completionHandler(nil)
                return
            }
            let statusCode = response.statusCode
            let current = task.currentRequest
            let currentMethod = current?.httpMethod ?? "GET"
            let currentURL = current?.url
            let currentHeaders = current?.allHTTPHeaderFields ?? [:]

            var followMethod = currentMethod
            var followBody: Data?
            switch statusCode {
            case 301, 302:
                // OkHttp：301/302 对 POST 转 GET 并丢弃 body
                if currentMethod == "POST" {
                    followMethod = "GET"
                }
            case 303:
                // 任务约定（OkHttp 语义：303 一律转 GET，丢 body）。
                // 差异：OkHttp 对 HEAD 的 303 保持 HEAD，本移植按约定转 GET。
                followMethod = "GET"
            case 307, 308:
                // OkHttp：307/308 保持方法与 body
                followBody = originalBody
            default:
                completionHandler(nil)
                return
            }
            if followMethod == "GET" || followMethod == "HEAD" {
                followBody = nil
            }

            var follow = URLRequest(url: targetURL)
            follow.httpMethod = followMethod
            let sameConnection = URLSessionHTTPClient.sameConnection(currentURL, targetURL)
            for (name, value) in currentHeaders {
                let lower = name.lowercased()
                // Cookie 在下面按新 URL 重新注入（对应每个请求 URL 的 loadRequest）
                if lower == "cookie" { continue }
                // Host 由 URLSession 根据 URL 自动设置，不能照抄旧值
                if lower == "host" { continue }
                // Content-Length / Transfer-Encoding 交给 URLSession 按新 body 重新计算
                if lower == "content-length" || lower == "transfer-encoding" { continue }
                // OkHttp RedirectInterceptor：跨 host/port/scheme 重定向去掉 Authorization
                if lower == "authorization" && !sameConnection { continue }
                // 转 GET 后旧的 body 相关头不再有意义（OkHttp 丢弃 body 时同样不保留）
                if followBody == nil && (lower == "content-type") { continue }
                follow.setValue(value, forHTTPHeaderField: name)
            }
            if let body = followBody {
                follow.httpBody = body
            }
            let existingCookie = currentHeaders.first { $0.key.lowercased() == "cookie" }?.value
            if let merged = CookieManager.cookieHeaderFor(url: targetURL.absoluteString,
                                                          existingHeader: existingCookie,
                                                          store: client.cookieStore,
                                                          cache: client.cookieManagerCache) {
                follow.setValue(merged, forHTTPHeaderField: "Cookie")
            }
            completionHandler(follow)
        }

        // MARK: 证书（对应 SSLHelper.unsafeTrustManager / unsafeHostnameVerifier）

        /// 对服务器证书信任一律放行（`URLCredential(trust:)`），对应 legado 信任所有证书。
        /// 其它认证方式（如 HTTP Basic / 代理认证）走系统默认处理。
        func urlSession(_ session: URLSession,
                        task: URLSessionTask,
                        didReceive challenge: URLAuthenticationChallenge,
                        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
                if let trust = challenge.protectionSpace.serverTrust {
                    completionHandler(.useCredential, URLCredential(trust: trust))
                } else {
                    completionHandler(.performDefaultHandling, nil)
                }
                return
            }
            completionHandler(.performDefaultHandling, nil)
        }

        // URLSessionDataDelegate 的实现说明：本类按约定实现 URLSessionTaskDelegate 与
        // URLSessionDataDelegate 两个协议（方法全部可选，无需实现数据接收方法）——
        // 数据由 `session.data(for:delegate:)` 的返回值收集，不实现
        // `urlSession(_:dataTask:didReceive:)` 以避免与 async 桥接的数据收集冲突。
    }
}