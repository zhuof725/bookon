//
//  HTTPTypes.swift
//  LegadoBookSource
//
//  第 6 步 6A：网络请求/响应的中立模型与 HTTPClient 协议。
//  Kotlin 里 AnalyzeUrl 直接构造 OkHttp 的 Request/Response；本移植把它们抽象成
//  HTTPRequest / HTTPResponse，真实实现（URLSession）在 6B，6A 只提供协议 + 测试用假实现。
//
//  对应 Kotlin：
//   - RequestMethod（help/http/RequestMethod.kt：GET/POST/HEAD）
//   - okhttp3.Request（url/method/headers/body）+ AnalyzeUrl 里额外携带的
//     retry/readTimeout/callTimeout/useWebView/webJs/bodyJs/dnsIp/proxy/type/serverID
//   - okhttp3.Response 的常用面（最终 url、status、headers、body bytes）
//

import Foundation

/// 对应 Kotlin `enum class RequestMethod { GET, POST, HEAD }`。
public enum RequestMethod: String, Sendable, Equatable {
    case get = "GET"
    case post = "POST"
    case head = "HEAD"

    /// 对应 Kotlin `it.uppercase()` 的三分支映射（未知/null 一律 GET）。
    /// 注意 Kotlin 用的是 `Locale` 无关的 uppercase()，这里用 `uppercased()` 对齐。
    public static func from(_ method: String?) -> RequestMethod {
        switch (method ?? "").uppercased() {
        case "POST": return .post
        case "HEAD": return .head
        default: return .get
        }
    }
}

/// 一次请求的完整描述（AnalyzeUrl.buildRequest() 的输出）。
///
/// headers 用有序数组表示：Kotlin 的 headerMap 是 LinkedHashMap，OkHttp 的 Headers 也保持
/// 插入顺序，golden 对照要逐条比较顺序，所以这里不能退化成 Dictionary。
public struct HTTPRequest: Sendable {
    /// 最终请求 URL（已含 encodedQuery；POST 时为 urlNoQuery）
    public var url: String
    public var method: RequestMethod
    /// 有序 headers（Kotlin: headerMap + OkHttp 手工添加的 Content-Type 等）
    public var headers: [(String, String)]
    /// 请求体（form / json / multipart 已编码后的字节）
    public var body: Data?
    /// 请求体媒体类型（Content-Type 的值；multipart 时含 boundary）
    public var contentType: String?
    /// UrlOption.charset（仅用于 body 编码，不直接作为 header）
    public var charset: String?
    /// 对应 OkHttpClient 的 retry 语义（newCallResponse(retry) 的重试次数）
    public var retry: Int
    /// UrlOption.readTimeout（毫秒）
    public var readTimeout: Int64?
    /// UrlOption.callTimeout（毫秒）
    public var callTimeout: Int64?
    /// UrlOption.useWebView
    public var useWebView: Bool
    /// UrlOption.webJs
    public var webJs: String?
    /// UrlOption.bodyJs
    public var bodyJs: String?
    /// UrlOption.dnsIp（自定义域名 IP；URLSession 不支持，6B 里记 diagnostics）
    public var dnsIp: String?
    /// UrlOption.proxy（"host:port"/"http://host:port"/"socks5://host:port"）
    public var proxy: String?
    /// UrlOption.type（如 data:text/plain;base64,xxx 的类型名）
    public var type: String?
    /// UrlOption.serverID
    public var serverID: Int64?
    /// 书源启用了 cookieJar 时，Kotlin 会在请求头里加 CookieManager.cookieJarHeader = "1"
    public var enabledCookieJar: Bool
    /// webViewDelayTime（毫秒）
    public var webViewDelayTime: Int64

    public init(url: String,
                method: RequestMethod = .get,
                headers: [(String, String)] = [],
                body: Data? = nil,
                contentType: String? = nil,
                charset: String? = nil,
                retry: Int = 0,
                readTimeout: Int64? = nil,
                callTimeout: Int64? = nil,
                useWebView: Bool = false,
                webJs: String? = nil,
                bodyJs: String? = nil,
                dnsIp: String? = nil,
                proxy: String? = nil,
                type: String? = nil,
                serverID: Int64? = nil,
                enabledCookieJar: Bool = false,
                webViewDelayTime: Int64 = 0) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
        self.contentType = contentType
        self.charset = charset
        self.retry = retry
        self.readTimeout = readTimeout
        self.callTimeout = callTimeout
        self.useWebView = useWebView
        self.webJs = webJs
        self.bodyJs = bodyJs
        self.dnsIp = dnsIp
        self.proxy = proxy
        self.type = type
        self.serverID = serverID
        self.enabledCookieJar = enabledCookieJar
        self.webViewDelayTime = webViewDelayTime
    }

    /// 手写 Equatable（headers 是有序元组数组，Swift 不会自动合成）。
    public static func == (lhs: HTTPRequest, rhs: HTTPRequest) -> Bool {
        if lhs.url != rhs.url || lhs.method != rhs.method { return false }
        if lhs.headers.count != rhs.headers.count { return false }
        for (a, b) in zip(lhs.headers, rhs.headers) where a.0 != b.0 || a.1 != b.1 { return false }
        if lhs.body != rhs.body { return false }
        if lhs.contentType != rhs.contentType || lhs.charset != rhs.charset { return false }
        if lhs.retry != rhs.retry || lhs.readTimeout != rhs.readTimeout || lhs.callTimeout != rhs.callTimeout { return false }
        if lhs.useWebView != rhs.useWebView || lhs.webJs != rhs.webJs || lhs.bodyJs != rhs.bodyJs { return false }
        if lhs.dnsIp != rhs.dnsIp || lhs.proxy != rhs.proxy || lhs.type != rhs.type { return false }
        if lhs.serverID != rhs.serverID || lhs.enabledCookieJar != rhs.enabledCookieJar { return false }
        return lhs.webViewDelayTime == rhs.webViewDelayTime
    }

    /// 取第一个（Kotlin 里 headers 是 map，key 唯一；这里按不区分大小写查找以对齐 OkHttp 的 header 语义）。
    public func header(_ name: String) -> String? {
        for (k, v) in headers where k.caseInsensitiveCompare(name) == .orderedSame {
            return v
        }
        return nil
    }
}

/// 一次响应的常用面。对应 OkHttp Response + StrResponse 里被用到的字段。
public struct HTTPResponse: Sendable {
    /// 最终 URL（跟随重定向之后；对应 Kotlin `response.request.url`）
    public var url: String
    public var status: Int
    public var message: String?
    /// 有序响应头（Set-Cookie 可能出现多次，顺序保留）
    public var headers: [(String, String)]
    public var body: Data
    /// 对应 StrResponse.callTime（毫秒；错误时 Kotlin 用负数错误码）
    public var callTime: Int

    public init(url: String, status: Int, message: String? = nil,
                headers: [(String, String)] = [], body: Data = Data(), callTime: Int = 0) {
        self.url = url
        self.status = status
        self.message = message
        self.headers = headers
        self.body = body
        self.callTime = callTime
    }

    /// 取所有同名头（Set-Cookie 语义）。
    public func headerValues(_ name: String) -> [String] {
        var out: [String] = []
        for (k, v) in headers where k.caseInsensitiveCompare(name) == .orderedSame {
            out.append(v)
        }
        return out
    }

    public func header(_ name: String) -> String? { headerValues(name).first }
}

/// 网络错误分类。对应 Kotlin executeStrRequest 里 `isTest` 模式对异常类型的分支
/// （SocketTimeoutException -> -2、UnknownHost -> -3、Connect -> -4、Socket -> -5、
/// SSL -> -6、InterruptedIOException(timeout) -> -1、其它 -> -7）。
public struct HTTPError: Error, Equatable {
    public enum Kind: Int, Sendable {
        case timeoutOverCallLimit = -1   // 超过设定时间
        case socketTimeout = -2
        case unknownHost = -3
        case connectRefused = -4
        case socket = -5
        case ssl = -6
        case other = -7
    }

    public let kind: Kind
    public let message: String

    public init(kind: Kind, message: String) {
        self.kind = kind
        self.message = message
    }

    public var errorCode: Int { kind.rawValue }
}

/// 网络入口协议：6A 只定义协议 + 假实现（6B 提供 URLSession 实现）。
public protocol HTTPClient: AnyObject {
    func execute(_ request: HTTPRequest) async throws -> HTTPResponse
}

/// 6A 用的假实现：把请求原样记录，按脚本返回预设响应。测试与 golden 对照都用它。
public final class ScriptedHTTPClient: HTTPClient, @unchecked Sendable {
    public struct Entry {
        public var matchURLContains: String?
        public var response: HTTPResponse
        public init(matchURLContains: String? = nil, response: HTTPResponse) {
            self.matchURLContains = matchURLContains
            self.response = response
        }
    }

    private let lock = NSLock()
    private var entries: [Entry]
    private var defaultResponse: HTTPResponse
    /// 按顺序记录收到的请求（供测试断言）
    public private(set) var received: [HTTPRequest] = []

    public init(entries: [Entry] = [], defaultResponse: HTTPResponse = HTTPResponse(url: "", status: 404)) {
        self.entries = entries
        self.defaultResponse = defaultResponse
    }

    public func execute(_ request: HTTPRequest) async throws -> HTTPResponse {
        lock.lock()
        received.append(request)
        let hit = entries.first { $0.matchURLContains.map { needle in request.url.contains(needle) } ?? true }
        lock.unlock()
        return hit?.response ?? defaultResponse
    }
}
