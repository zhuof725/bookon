//
//  RealJsNetworkExtensionsProvider.swift
//  LegadoBookSource
//
//  第 6 步 6B：JsNetworkExtensionsProvider 的真实网络/文件实现。
//
//  Kotlin 对应位置：app/src/main/java/io/legado/app/help/JsExtensions.kt 的
//   get / post / head / ajaxAll / connect / cacheFile / downloadFile（第 100–560 行区间），
//  以及它们依赖的：
//   - AnalyzeUrl.getStrResponse / getStrResponseAwait（model/analyzeRule/AnalyzeUrl.kt:417/540）
//   - ConcurrentRateLimiter.withLimit（help/ConcurrentRateLimiter.kt）
//   - FileUtils.getCachePath / MD5Utils.md5Encode16 / UrlUtil.getSuffix（utils/）
//   - CacheManager.get/put（help/CacheManager.kt）
//
//  —— JS 可见对象对照表（本移植用「信封字符串」穿过 invoke 的 String 返回通道，
//     由 JSJavaBridge 注入的 __javaUnwrap 还原为带方法的 JS 对象）——
//
//  1) get/post/head 返回「jsoup Connection.Response 替身」：
//     | JS 方法                | Kotlin/jsoup 对应              | 语义 |
//     |------------------------|-------------------------------|------|
//     | body()                 | Connection.Response.body()     | 按 Content-Type/BOM/UTF-8 解码的响应体 |
//     | statusCode()           | statusCode()                   | 状态码（不跟随重定向，3xx 原样返回） |
//     | statusMessage()        | statusMessage()                | 状态短语（URLSession 无原话，用标准短语表） |
//     | headers()              | headers()                      | {name: [values]}；带非枚举 get(name)（大小写不敏感，jsoup Headers 语义） |
//     | cookies()              | cookies()                      | {name: value}；带非枚举 get(name) |
//     | header(name)           | header(name)                   | 首个同名值；无则 null（jsoup 语义） |
//     | cookieKey(name)        | ——（便捷补充，Kotlin 无此方法）  | cookies()[name]；无则 null |
//     | url()                  | url()                          | 请求 URL（规范化后） |
//     | contentType()          | contentType()                  | Content-Type 头（无则空串） |
//
//  2) connect 返回「StrResponse 替身」（Kotlin StrResponse.kt + jsHelp.md 文档的方法面）：
//     body() / code() / message() / headers() / raw() / toString() / callTime() / url()
//     ⚠️ 差异：Kotlin 的 StrResponse 是「JavaBean 属性 + 同名方法」双通道（.body 与 body()），
//     Rhino 可两者并存；JS 对象上无法让同名的数据属性与方法并存，本移植只提供**同名方法**，
//     `.body` 属性访问请改用 `.body()`。
//
//  3) ajaxAll 返回 StrResponse 替身数组（顺序与输入一致）。
//  4) cacheFile 返回文件文本内容；downloadFile 返回相对缓存根的路径（带前导 "/"）。
//
//  —— 语义对齐（逐条）——
//  - get/post/head：**不走 AnalyzeUrl**，对应 Kotlin 直接 Jsoup.connect(urlStr)：
//      .sslSocketFactory(SSLHelper.unsafeSSLSocketFactory)（URLSessionHTTPClient 已对齐信任所有证书）
//      .timeout(timeout ?: 30000)
//      .ignoreContentType(true)
//      .followRedirects(false)   ← 本移植给 HTTPRequest.followRedirects=false
//      .headers(requestHeaders)  ← 来自 JS 对象参数
//      .method(GET/HEAD/POST[.requestBody(body)])
//      包在 ConcurrentRateLimiter(getSource()).withLimitBlocking 里（本移植 provider 不携带书源，
//      见「差异 5」）。
//  - connect：AnalyzeUrl(urlStr, headerMapF: JSON 头, callTimeout) → getStrResponse()；
//      失败时对齐 Kotlin `StrResponse(analyzeUrl.url, it.stackTraceStr)`（code 200 / message OK /
//      callTime 0 —— Kotlin 构造器会造一个 200 OK 的 raw）。
//  - ajaxAll：并发（对齐 mapAsync(AppConfig.threadCount)，本移植默认 4、可注入），保持输入顺序；
//      任一 URL 失败即整体抛错（对齐 Kotlin isTest=false 时 getStrResponseAwait 会抛异常）。
//  - cacheFile：key=md5Encode16(url) 查 CacheManager；命中且文件存在 → 读文本；否则 downloadFile
//      落盘 → CacheManager.put(key, path, saveTime) → 读文本（对齐 Kotlin 的分支与顺序）。
//  - downloadFile：文件名 md5Encode16(url).type（type = analyzeUrl.type ?: UrlUtil.getSuffix(url)），
//      写 `<缓存根>/<文件名>`，返回 path.substring(getCachePath().length) 即「/文件名」。
//
//  —— 与 Kotlin 的差异（README 6B 小节登记）——
//   1. 缓存根目录：Kotlin 用 Context.externalCacheDir（/android/data/{pkg}/cache）；
//      本移植默认用 FileManager Caches 目录下 "legado-js-cache"（可注入，测试传临时目录）；
//   2. 文本解码：Kotlin 走 ResponseBody.text()（explicit charset → Content-Type → ICU4J
//      EncodingDetect.getHtmlEncode）；本移植为最小解码链（BOM 剥离 → explicit → Content-Type →
//      UTF-8 替换语义），ICU4J 检测链在 step6-6b-wip 分支 WIP(4)/(5)，尚未并入 main；
//      读取本地缓存文件同理（Kotlin 用 EncodingDetect.getEncode(file) 检测）；
//   3. headers 参数顺序：JS 对象经桥接 → JSON（Swift 侧按字典序），Kotlin 保持 JS 对象插入
//      顺序（LinkedHashMap）；键唯一时不影响 HTTP 语义；
//   4. get/post/head 的 Cookie：Kotlin 的 Jsoup.connect 用自建客户端（不带 legado CookieStore）；
//      本移植经 URLSessionHTTPClient 会注入 CookieStore 的 Cookie（客户端既有差异 #5 不变）；
//   5. get/post/head 的书源并发率：Kotlin 用 ConcurrentRateLimiter(getSource())；本移植 provider
//      不携带书源，未接线（App 集成方可自行包装限速）；
//   6. 请求重试：Kotlin get/post/head 无重试（单次 execute）；ajax/connect 走 AnalyzeUrl retry；
//      本移植一致；网络错误的分类/超时语义由 URLSessionHTTPClient 负责（既有差异见 6B 客户端文档）；
//   7. cacheFile 的 saveTime：Kotlin CacheManager.put(key, path, saveTime) 带 TTL；本移植注入的
//      cacheManager 若是带 saveTime 的 CacheManager（Network/CacheManager.swift）则透传，
//      否则退化为不带 TTL 的 CacheManagerProtocol.put（记本条差异）。
//

import Foundation
import CoreFoundation

// MARK: - JS 信封（invoke 的 String 返回通道 → JS 对象）

/// 「信封字符串」：`<前缀><JSON>`。前缀用控制字符 \u{1} 包裹，避免与任何真实响应文本冲突。
/// JS 侧由 JSJavaBridge 注入的 __javaUnwrap 按前缀还原为带方法的对象（见文件头对照表）。
enum JsNetEnvelope {

    /// Connection.Response 替身信封前缀（get/post/head）。
    static let connectionPrefix = "\u{1}JSCONN\u{1}"
    /// StrResponse 替身信封前缀（connect）。
    static let strResponsePrefix = "\u{1}JSSTR\u{1}"
    /// StrResponse 数组信封前缀（ajaxAll）。
    static let strResponseArrayPrefix = "\u{1}JSSTRS\u{1}"

    /// 尽量安全地序列化 JSON（失败返回 nil，调用方退化为原始文本，绝不崩溃）。
    static func jsonString(_ object: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(object) else { return nil }
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: []) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// get/post/head 的信封构造（对应 Kotlin 的 Connection.Response）。
    static func connection(url: String,
                           status: Int,
                           message: String,
                           headerPairs: [(String, String)],
                           cookiePairs: [(String, String)],
                           body: String,
                           contentType: String) -> String {
        let object: [String: Any] = [
            "url": url,
            "status": status,
            "message": message,
            "headers": headerPairs.map { [$0.0, $0.1] },
            "cookies": cookiePairs.map { [$0.0, $0.1] },
            "body": body,
            "contentType": contentType
        ]
        guard let json = jsonString(object) else { return body }
        return connectionPrefix + json
    }

    /// connect / ajaxAll 元素的信封构造（对应 Kotlin StrResponse）。
    static func strResponse(url: String,
                            body: String,
                            callTime: Int,
                            code: Int,
                            message: String,
                            headerPairs: [(String, String)]) -> String {
        let raw = "Response{code=\(code), message=\(message), url=\(url)}"
        let object: [String: Any] = [
            "url": url,
            "body": body,
            "callTime": callTime,
            "code": code,
            "message": message,
            "headers": headerPairs.map { [$0.0, $0.1] },
            "raw": raw
        ]
        guard let json = jsonString(object) else { return body }
        return strResponsePrefix + json
    }

    /// ajaxAll 的数组信封。
    static func strResponseArray(_ items: [StrPayload]) -> String {
        let array: [[String: Any]] = items.map { item in
            let raw = "Response{code=\(item.code), message=\(item.message), url=\(item.url)}"
            return [
                "url": item.url,
                "body": item.body,
                "callTime": item.callTime,
                "code": item.code,
                "message": item.message,
                "headers": item.headers.map { [$0.0, $0.1] },
                "raw": raw
            ]
        }
        guard JSONSerialization.isValidJSONObject(array),
              let data = try? JSONSerialization.data(withJSONObject: array, options: []),
              let json = String(data: data, encoding: .utf8) else {
            return strResponseArrayPrefix + "[]"
        }
        return strResponseArrayPrefix + json
    }

    /// StrResponse 的数据形态（对应 Kotlin StrResponse 的 body/url/callTime/code/message/headers）。
    struct StrPayload {
        var url: String
        var body: String
        var callTime: Int
        var code: Int
        var message: String
        var headers: [(String, String)]
    }
}

// MARK: - 最小响应文本解码（差异见文件头 #2）

/// 响应字节 → 字符串的最小解码链，对应 Kotlin `ResponseBody.text(encode)` 的前三级
/// （BOM 剥离 → 显式 charset → Content-Type charset），最后以 UTF-8 替换语义兜底
/// （ICU4J 检测链未并入 main，见文件头差异 #2）。
enum JsNetTextDecoder {

    /// 剥离 UTF-8 BOM（对应 legado Utf8BomUtils.removeUTF8BOM 的等价物）。
    static func removeUTF8BOM(_ bytes: [UInt8]) -> [UInt8] {
        if bytes.count >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF {
            return Array(bytes.dropFirst(3))
        }
        return bytes
    }

    /// 从 Content-Type 头取 charset 参数（大小写不敏感；语义对齐 OkHttp MediaType.charset()）。
    static func charsetFromContentTypeHeader(_ header: String?) -> String? {
        guard let header = header, !header.isEmpty else { return nil }
        for segment in header.components(separatedBy: ";") {
            let trimmed = segment.trimmingCharacters(in: .whitespacesAndNewlines)
            let lower = trimmed.lowercased()
            guard lower.hasPrefix("charset=") else { continue }
            var value = String(trimmed.dropFirst("charset=".count))
            value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"' \t"))
            if !value.isEmpty { return value }
        }
        return nil
    }

    /// bytes → String。explicitCharset（书源 charset）→ Content-Type charset → UTF-8。
    /// 不可解码字节按 Java `new String(bytes, charset)` 的 U+FFFD 替换语义处理。
    static func decode(bytes: [UInt8], explicitCharset: String?, contentTypeHeader: String?) -> String {
        let stripped = removeUTF8BOM(bytes)
        let data = Data(stripped)

        if let explicit = explicitCharset, !explicit.isEmpty {
            if let text = decode(data, charsetName: explicit) { return text }
            // 差异：Kotlin 对不可识别 charset 名抛异常；这里回退到下一级（不崩溃）。
        }
        if let headerCharset = charsetFromContentTypeHeader(contentTypeHeader) {
            if let text = decode(data, charsetName: headerCharset) { return text }
        }
        return String(decoding: stripped, as: UTF8.self)
    }

    /// 按字符集名解码（支持 UTF-8/UTF-16/GBK/GB2312/GB18030/Big5/ISO-8859-1/ASCII；
    /// 其它名字返回 nil 走兜底）。GB 系/Big5 用 CFStringEncoding 映射（与 AnalyzeUrl.GBKBytes 同源）。
    static func decode(_ data: Data, charsetName: String) -> String? {
        let name = charsetName.uppercased().replacingOccurrences(of: "_", with: "-")
        switch name {
        case "UTF-8", "UTF8":
            return String(decoding: Array(data), as: UTF8.self)
        case "UTF-16", "UTF16":
            return String(data: data, encoding: .utf16)
        case "UTF-16LE", "UTF16LE":
            return String(data: data, encoding: .utf16LittleEndian)
        case "UTF-16BE", "UTF16BE":
            return String(data: data, encoding: .utf16BigEndian)
        case "ISO-8859-1", "LATIN1", "ISO8859-1":
            return String(data: data, encoding: .isoLatin1)
        case "US-ASCII", "ASCII":
            return String(data: data, encoding: .ascii) ?? String(decoding: Array(data), as: UTF8.self)
        default:
            break
        }
        // GBK/GB2312/GB18030（CFStringEncodings.GB_18030_2000 与 Java 的 GBK 系兼容）
        if name == "GBK" || name == "GB2312" || name == "GB-2312" || name == "GB18030" || name == "CP936" {
            let enc = CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
            if enc != 0 && enc != UInt(kCFStringEncodingInvalidId) {
                return String(data: data, encoding: String.Encoding(rawValue: enc))
            }
            return nil
        }
        // Big5
        if name == "BIG5" || name == "BIG-5" || name == "BIG5-HKSCS" {
            let enc = CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.big5.rawValue))
            if enc != 0 && enc != UInt(kCFStringEncodingInvalidId) {
                return String(data: data, encoding: String.Encoding(rawValue: enc))
            }
            return nil
        }
        return nil
    }
}

// MARK: - 文件名后缀（对应 Kotlin UrlUtil.getSuffix）

/// 对应 Kotlin `UrlUtil.getSuffix(str, default)`：
/// `substringAfterLast("/").substringBefore("?").substringBefore("#").substringAfterLast(".", "")`，
/// 合法条件：长度 ≤ 5 且全为 [a-zA-Z0-9]；否则用 default（null → "ext"）。
enum JsUrlSuffix {

    static func suffix(_ url: String, default defaultValue: String? = nil) -> String {
        var s = url
        if let idx = s.lastIndex(of: "/") { s = String(s[s.index(after: idx)...]) }
        if let idx = s.firstIndex(of: "?") { s = String(s[s.startIndex..<idx]) }
        if let idx = s.firstIndex(of: "#") { s = String(s[s.startIndex..<idx]) }
        var cand = ""
        if let idx = s.lastIndex(of: ".") { cand = String(s[s.index(after: idx)...]) }
        if cand.count > 5 || !isLegalSuffix(cand) {
            return defaultValue ?? "ext"
        }
        return cand
    }

    /// [a-zA-Z0-9]+（对应 Kotlin `fileSuffixRegex` 的 `suffix.matches(...)`，空串不合法）。
    private static func isLegalSuffix(_ s: String) -> Bool {
        guard !s.isEmpty else { return false }
        for scalar in s.unicodeScalars {
            let v = scalar.value
            let ok = (v >= 0x30 && v <= 0x39) || (v >= 0x41 && v <= 0x5A) || (v >= 0x61 && v <= 0x7A)
            if !ok { return false }
        }
        return true
    }
}

// MARK: - 文件写入错误（Kotlin 是 IOException，这里收敛为可抛错误，绝不崩溃）

/// downloadFile / cacheFile 的 IO 错误（对应 Kotlin 会向上抛的 IOException，
/// JS 侧表现为 java.downloadFile(...) 抛错）。
public enum JsNetFileError: Error, LocalizedError {
    case writeFailed(path: String, message: String)
    case readFailed(path: String, message: String)

    public var errorDescription: String? {
        switch self {
        case .writeFailed(let path, let message): return "写入失败: \(path) (\(message))"
        case .readFailed(let path, let message): return "读取失败: \(path) (\(message))"
        }
    }
}

// MARK: - RealJsNetworkExtensionsProvider

/// `JsNetworkExtensionsProvider` 的真实实现（第 6 步 6B）。
/// 覆盖 get/post/head/connect/ajaxAll/cacheFile/downloadFile；其余方法抛 unsupported。
public final class RealJsNetworkExtensionsProvider: JsNetworkExtensionsProvider {

    /// Jsoup.connect 的默认超时（毫秒）：Kotlin `timeout(timeout ?: 30000)`。
    public static let jsoupDefaultTimeoutMillis = 30000
    /// ajaxAll 默认并发数（对齐 Kotlin `mapAsync(AppConfig.threadCount)` 的默认 4）。
    public static let defaultMaxConcurrent = 4

    private let client: HTTPClient
    private let environment: AnalyzeUrlEnvironment
    private let cacheManager: CacheManagerProtocol
    private let cacheDirectory: URL
    private let diagnostics: RuleEngineDiagnostics?
    private let maxConcurrent: Int

    /// 对应 Kotlin `getSource()?.enabledCookieJar`：为 true 时 get/post/head 追加 `CookieJar: 1` 头。
    /// ⚠️ 差异：Kotlin 从书源实时读取；本移植 provider 不携带书源，需显式设置（默认 false）。
    public var enabledCookieJar: Bool = false

    public init(client: HTTPClient? = nil,
                environment: AnalyzeUrlEnvironment = AnalyzeUrlEnvironment(),
                cacheManager: CacheManagerProtocol = InMemoryCacheManager(),
                cacheDirectory: URL? = nil,
                diagnostics: RuleEngineDiagnostics? = nil,
                maxConcurrent: Int = RealJsNetworkExtensionsProvider.defaultMaxConcurrent) {
        self.client = client ?? RealJsNetworkExtensionsProvider.makeDefaultClient()
        self.environment = environment
        self.cacheManager = cacheManager
        self.cacheDirectory = cacheDirectory ?? RealJsNetworkExtensionsProvider.defaultCacheDirectory()
        self.diagnostics = diagnostics
        self.maxConcurrent = max(1, maxConcurrent)
    }

    /// 默认客户端：URLSessionHTTPClient + 内存 CookieStore（对应 Kotlin HttpHelper.okHttpClient）。
    private static func makeDefaultClient() -> HTTPClient {
        JsNetSupport.makeDefaultClient()
    }

    /// 默认缓存根：FileManager Caches + "legado-js-cache"（差异：Kotlin 是 externalCacheDir，见文件头 #1）。
    public static func defaultCacheDirectory() -> URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("legado-js-cache", isDirectory: true)
    }

    // MARK: - invoke 分发（对应 JsExtensionsRuntime 的路由）

    /// 对应 Kotlin JsExtensions 的同名方法；method 清单见 JsExtensionsCatalog.providerImplemented。
    public func invoke(method: String, arguments: [String]) throws -> String? {
        switch method {
        case "get":
            return try jsoupGetOrHead(method: .get, arguments: arguments)
        case "head":
            return try jsoupGetOrHead(method: .head, arguments: arguments)
        case "post":
            return try jsoupPost(arguments: arguments)
        case "connect":
            return try connect(arguments: arguments)
        case "ajaxAll":
            return try ajaxAll(urls: arguments)
        case "cacheFile":
            return try cacheFile(arguments: arguments)
        case "downloadFile":
            return try downloadFile(url: arguments.first ?? "")
        default:
            throw RuleEngineError.unsupported(
                "java.\(method) 不在 JsNetworkExtensionsProvider 覆盖范围（6B 已覆盖 get/post/head/connect/ajaxAll/cacheFile/downloadFile）")
        }
    }

    // MARK: - get / post / head（对应 JsExtensions.kt:483-563，Jsoup.connect 语义）

    /// 对应 Kotlin `get(urlStr, headers, timeout?)` / `head(urlStr, headers, timeout?)`：
    /// Jsoup.connect(urlStr).sslSocketFactory(unsafe).timeout(timeout ?: 30000).ignoreContentType(true)
    /// .followRedirects(false).headers(requestHeaders).method(GET/HEAD).execute()
    private func jsoupGetOrHead(method: RequestMethod, arguments: [String]) throws -> String {
        let urlStr = arguments.first ?? ""
        var headers = Self.parseHeadersJSON(arguments.count > 1 ? arguments[1] : nil)
        let timeoutMs = Self.parseTimeoutMillis(arguments.count > 2 ? arguments[2] : nil)
            ?? RealJsNetworkExtensionsProvider.jsoupDefaultTimeoutMillis
        if enabledCookieJar {
            // 对应 Kotlin：enabledCookieJar 时 `headers + cookieJarHeader`
            headers.append((CookieMerge.cookieJarHeader, "1"))
        }
        var request = HTTPRequest(url: Self.normalizedURL(urlStr),
                                  method: method,
                                  headers: headers)
        request.readTimeout = Int64(timeoutMs)
        request.callTimeout = Int64(timeoutMs)
        // Jsoup followRedirects(false)：不跟随重定向，3xx 原样返回（本移植经
        // HTTPRequest.followRedirects = false，见 URLSessionHTTPClient 对应分支）。
        request.followRedirects = false

        let response = try runBlockingNetwork { [client] in
            try await client.execute(request)
        }
        let bodyText = Self.decodeBody(response, explicitCharset: nil)
        let cookies = Self.cookiesFromSetCookieHeaders(response.headers)
        return JsNetEnvelope.connection(url: response.url,
                                        status: response.status,
                                        message: response.message ?? "",
                                        headerPairs: response.headers,
                                        cookiePairs: cookies,
                                        body: bodyText,
                                        contentType: response.header("Content-Type") ?? "")
    }

    /// 对应 Kotlin `post(urlStr, body, headers, timeout?)`：
    /// Jsoup.connect(urlStr)...followRedirects(false).requestBody(body).headers(...).method(POST).execute()
    /// 说明：jsoup 的 requestBody(String) 不自动加 Content-Type（只有 form 的 data() 才会加
    /// application/x-www-form-urlencoded）；用户 header 里给了 Content-Type 才发送（对照 Kotlin）。
    private func jsoupPost(arguments: [String]) throws -> String {
        guard arguments.count >= 2 else {
            throw RuleEngineError.unsupported("java.post 需要参数 (url, body[, headers[, timeout]])")
        }
        let urlStr = arguments[0]
        let bodyText = arguments[1]
        var headers = Self.parseHeadersJSON(arguments.count > 2 ? arguments[2] : nil)
        let timeoutMs = Self.parseTimeoutMillis(arguments.count > 3 ? arguments[3] : nil)
            ?? RealJsNetworkExtensionsProvider.jsoupDefaultTimeoutMillis
        if enabledCookieJar {
            headers.append((CookieMerge.cookieJarHeader, "1"))
        }
        var request = HTTPRequest(url: Self.normalizedURL(urlStr),
                                  method: .post,
                                  headers: headers,
                                  body: Data(bodyText.utf8),
                                  contentType: Self.headerValue(headers, "Content-Type"))
        request.readTimeout = Int64(timeoutMs)
        request.callTimeout = Int64(timeoutMs)
        request.followRedirects = false

        let response = try runBlockingNetwork { [client] in
            try await client.execute(request)
        }
        let decoded = Self.decodeBody(response, explicitCharset: nil)
        let cookies = Self.cookiesFromSetCookieHeaders(response.headers)
        return JsNetEnvelope.connection(url: response.url,
                                        status: response.status,
                                        message: response.message ?? "",
                                        headerPairs: response.headers,
                                        cookiePairs: cookies,
                                        body: decoded,
                                        contentType: response.header("Content-Type") ?? "")
    }

    // MARK: - connect（对应 JsExtensions.kt:164-193）

    /// 对应 Kotlin `connect(urlStr, header = null, callTimeout = null)`：
    /// header 是 JSON 字符串（GSON.fromJsonObject<Map<String, String>>(...).getOrNull()），
    /// 解析失败/为空 → 无附加头。返回 StrResponse；失败时返回错误体（url + 错误描述）。
    private func connect(arguments: [String]) throws -> String {
        let urlStr = arguments.first ?? ""
        let headerPairs = Self.parseHeaderJSONString(arguments.count > 1 ? arguments[1] : nil)
        let callTimeout = Self.parseTimeoutMillis(arguments.count > 2 ? arguments[2] : nil)

        let analyzeUrl = AnalyzeUrl(urlStr,
                                    source: nil,
                                    callTimeout: callTimeout.map(Int64.init),
                                    headerMapF: headerPairs,
                                    environment: environment)
        do {
            let payload = try runBlockingNetwork { [self] in
                try await strPayload(for: analyzeUrl, skipRateLimit: false)
            }
            return JsNetEnvelope.strResponse(url: payload.url,
                                             body: payload.body,
                                             callTime: payload.callTime,
                                             code: payload.code,
                                             message: payload.message,
                                             headerPairs: payload.headers)
        } catch {
            if !(error is CancellationError) {
                diagnostics?.record(source: "RealJsNetworkExtensionsProvider.connect",
                                    rule: urlStr, message: "connect 失败：\(error)")
            }
            // 对应 Kotlin `StrResponse(analyzeUrl.url, it.stackTraceStr)`：
            // Kotlin 用 URL+body 的构造器（raw 固定为 200 OK、callTime 0）。
            // 差异：stackTraceStr 是 Java 堆栈文本，这里用 Swift 错误描述。
            return JsNetEnvelope.strResponse(url: analyzeUrl.url,
                                             body: "\(error)",
                                             callTime: 0,
                                             code: 200,
                                             message: "OK",
                                             headerPairs: [])
        }
    }

    // MARK: - ajaxAll（对应 JsExtensions.kt:124-139）

    /// 对应 Kotlin `ajaxAll(urlList, skipRateLimit = false)`：
    /// 并发 getStrResponseAwait 后按输入顺序合并为数组；任一失败整体抛错。
    /// 并发数对齐 mapAsync(AppConfig.threadCount)（默认 4，可注入），按批分组执行以限并发。
    private func ajaxAll(urls: [String]) throws -> String {
        guard !urls.isEmpty else { return JsNetEnvelope.strResponseArray([]) }
        let payloads = try runBlockingNetwork { [self] () -> [JsNetEnvelope.StrPayload] in
            var collected: [JsNetEnvelope.StrPayload] = []
            var index = 0
            while index < urls.count {
                let slice = Array(urls[index..<min(index + maxConcurrent, urls.count)])
                let base = index
                let batch = try await withThrowingTaskGroup(of: (Int, JsNetEnvelope.StrPayload).self) { group in
                    for (offset, url) in slice.enumerated() {
                        group.addTask { [self] in
                            let analyzeUrl = AnalyzeUrl(url, source: nil, environment: environment)
                            let payload = try await strPayload(for: analyzeUrl, skipRateLimit: false)
                            return (base + offset, payload)
                        }
                    }
                    var out: [JsNetEnvelope.StrPayload?] = Array(repeating: nil, count: slice.count)
                    for try await (idx, payload) in group {
                        if idx >= base && idx - base < out.count { out[idx - base] = payload }
                    }
                    return out.compactMap { $0 }
                }
                collected.append(contentsOf: batch)
                index += slice.count
            }
            return collected
        }
        return JsNetEnvelope.strResponseArray(payloads)
    }

    // MARK: - cacheFile（对应 JsExtensions.kt:378-401）

    /// 对应 Kotlin `cacheFile(urlStr, saveTime = 0)`：
    /// key=md5Encode16(url) → CacheManager.get(key)；命中且文件存在 → 读文本；
    /// 否则 downloadFile 落盘 → CacheManager.put(key, path, saveTime) → 读文本。
    private func cacheFile(arguments: [String]) throws -> String {
        let urlStr = arguments.first ?? ""
        let saveTime = arguments.count > 1 ? (Self.parseTimeoutMillis(arguments[1]) ?? 0) : 0
        let key = JsExtensionsCore.md5Encode16(urlStr)

        if let path = cacheManager.get(key), !path.isEmpty,
           FileManager.default.fileExists(atPath: resolveCachePath(path).path) {
            return readTxtFile(resolveCachePath(path))
        }
        let path = try downloadFile(url: urlStr)
        if let concrete = cacheManager as? CacheManager {
            // CacheManager（Network/CacheManager.swift）带 saveTime 的 put（对齐 Kotlin）。
            concrete.put(key, path, saveTime: saveTime)
        } else {
            // CacheManagerProtocol 无 saveTime（差异 #7）。
            cacheManager.put(key, path)
        }
        diagnostics?.record(source: "RealJsNetworkExtensionsProvider.cacheFile",
                            rule: urlStr, message: "首次下载 \(urlStr) >> \(path)")
        return readTxtFile(resolveCachePath(path))
    }

    /// 对应 Kotlin `readTxtFile(path)`：文件不存在返回 ""；解码差异见文件头 #2。
    private func readTxtFile(_ fileURL: URL) -> String {
        guard let data = try? Data(contentsOf: fileURL) else { return "" }
        return JsNetTextDecoder.decode(bytes: Array(data), explicitCharset: nil, contentTypeHeader: nil)
    }

    /// Kotlin 的路径都是「缓存根 + 相对路径」；downloadFile 返回的 "/name.ext" 在这里还原。
    private func resolveCachePath(_ path: String) -> URL {
        if path.hasPrefix("/") {
            return cacheDirectory.appendingPathComponent(String(path.dropFirst()))
        }
        return cacheDirectory.appendingPathComponent(path)
    }

    // MARK: - 内部转发（共享给 RealAjaxProvider；实现在文件尾部 JsNetSupport）

    private static func parseHeadersJSON(_ json: String?) -> [(String, String)] {
        JsNetSupport.parseHeadersJSON(json)
    }
    private static func parseHeaderJSONString(_ json: String?) -> [(String, String)]? {
        JsNetSupport.parseHeaderJSONString(json)
    }
    private static func parseTimeoutMillis(_ s: String?) -> Int? {
        JsNetSupport.parseTimeoutMillis(s)
    }
    private static func decodeBody(_ response: HTTPResponse, explicitCharset: String?) -> String {
        JsNetSupport.decodeBody(response, explicitCharset: explicitCharset)
    }
    private static func cookiesFromSetCookieHeaders(_ headers: [(String, String)]) -> [(String, String)] {
        JsNetSupport.cookiesFromSetCookieHeaders(headers)
    }
    private static func headerValue(_ headers: [(String, String)], _ name: String) -> String? {
        JsNetSupport.headerValue(headers, name)
    }
    private static func normalizedURL(_ url: String) -> String {
        JsNetSupport.normalizedURL(url)
    }

    /// 把异步网络工作桥接回同步调用点（对应 Kotlin 的 runBlocking(coroutineContext)）。
    /// ⚠️ 与 Kotlin 相同的取舍：会阻塞调用线程（JS 回调线程），iOS 上不要在需要主线程的路径里调用。
    private func runBlockingNetwork<T>(_ operation: @escaping () async throws -> T) throws -> T {
        try JsNetSupport.runBlocking(operation)
    }

    /// 单 URL 的 StrResponse 数据（connect 与 ajaxAll 共用）。
    private func strPayload(for analyzeUrl: AnalyzeUrl,
                            skipRateLimit: Bool) async throws -> JsNetEnvelope.StrPayload {
        try await JsNetSupport.strPayload(for: analyzeUrl, client: client,
                                          environment: environment, skipRateLimit: skipRateLimit)
    }

    /// 对应 Kotlin `downloadFile(url)`（JsExtensions.kt:426-450）：
    /// type = analyzeUrl.type ?: UrlUtil.getSuffix(url)；文件名 = md5Encode16(url).type；
    /// 先 file.delete() 再写；返回 path.substring(getCachePath().length)（带前导 "/"）。
    private func downloadFile(url: String) throws -> String {
        let analyzeUrl = AnalyzeUrl(url, source: nil, environment: environment)
        let optionType: String? = {
            if let t = analyzeUrl.type, !t.isEmpty { return t }
            return nil
        }()
        let type = optionType ?? JsUrlSuffix.suffix(url)
        let fileName = JsExtensionsCore.md5Encode16(url) + "." + type
        let fileURL = cacheDirectory.appendingPathComponent(fileName)
        let fm = FileManager.default
        try? fm.removeItem(at: fileURL) // Kotlin: file.delete()

        let data = try runBlockingNetwork { [self] in
            try await JsNetSupport.bytesForDownload(analyzeUrl, client: client, skipRateLimit: false)
        }
        // Kotlin: FileUtils.createFolderIfNotExist(FileUtils.getCachePath())
        if !fm.fileExists(atPath: cacheDirectory.path) {
            do {
                try fm.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
            } catch {
                throw JsNetFileError.writeFailed(path: cacheDirectory.path, message: "\(error)")
            }
        }
        do {
            try data.write(to: fileURL, options: .atomic)
        } catch {
            try? fm.removeItem(at: fileURL) // Kotlin: catch 时 file.delete() 后重抛
            throw JsNetFileError.writeFailed(path: fileURL.path, message: "\(error)")
        }
        // Kotlin: path.substring(FileUtils.getCachePath().length)
        return "/" + fileName
    }
}

// MARK: - 共享网络小工具（RealJsNetworkExtensionsProvider / RealAjaxProvider）

/// 两个 provider 共用的：阻塞桥、Build+Execute+Decode（对齐 Kotlin executeStrRequest 的
/// 非 WebView 路径）、请求参数解析、响应解码、错误处理小工具。
enum JsNetSupport {

    // MARK: 阻塞桥

    /// 结果盒（线程安全）。
    private final class ResultBox<T> {
        private let lock = NSLock()
        private var stored: Result<T, Error>?
        var value: Result<T, Error>? {
            get { lock.lock(); defer { lock.unlock() }; return stored }
            set { lock.lock(); defer { lock.unlock() }; stored = newValue }
        }
    }

    /// 同步等待异步任务（对应 Kotlin `runBlocking(coroutineContext)`）。
    static func runBlocking<T>(_ operation: @escaping () async throws -> T) throws -> T {
        let semaphore = DispatchSemaphore(value: 0)
        let box = ResultBox<T>()
        Task {
            do {
                box.value = .success(try await operation())
            } catch {
                box.value = .failure(error)
            }
            semaphore.signal()
        }
        semaphore.wait()
        guard let result = box.value else {
            // 防御分支（signal 之后必然已赋值），不强制解包。
            throw RuleEngineError.unsupported("网络工作未返回结果（内部错误）")
        }
        return try result.get()
    }

    // MARK: 请求执行（对应 Kotlin AnalyzeUrl.getStrResponseAwait / executeStrRequest）

    /// 构造并执行请求（限速 + retry 由 AnalyzeUrl/HTTPClient 负责），返回响应。
    static func buildAndExecute(_ analyzeUrl: AnalyzeUrl,
                                client: HTTPClient,
                                skipRateLimit: Bool) async throws -> (request: HTTPRequest, response: HTTPResponse) {
        let request = analyzeUrl.buildRequest()
        let response: HTTPResponse
        if skipRateLimit {
            response = try await client.execute(request)
        } else {
            response = try await analyzeUrl.withRateLimit { [client] in
                try await client.execute(request)
            }
        }
        return (request, response)
    }

    /// 对应 Kotlin `getStrResponseAwait`：type != null 时 body 是「字节的十六进制串」；
    /// 否则网络请求 + 解码 + isXml/bodyJs 后处理（差异：WebView 分支不在此实现）。
    static func strPayload(for analyzeUrl: AnalyzeUrl,
                           client: HTTPClient,
                           environment: AnalyzeUrlEnvironment,
                           skipRateLimit: Bool) async throws -> JsNetEnvelope.StrPayload {
        if analyzeUrl.type != nil {
            // Kotlin: `if (type != null) return StrResponse(url, HexUtil.encodeHexStr(getByteArrayAwait()))`
            let bytes: Data
            if let dataUriBytes = analyzeUrl.getByteArrayIfDataUri() {
                bytes = dataUriBytes
            } else {
                let executed = try await buildAndExecute(analyzeUrl, client: client, skipRateLimit: skipRateLimit)
                bytes = executed.response.body
            }
            return JsNetEnvelope.StrPayload(url: analyzeUrl.url,
                                            body: hexString(bytes),
                                            callTime: 0,
                                            code: 200,
                                            message: "OK",
                                            headers: [])
        }

        let executed = try await buildAndExecute(analyzeUrl, client: client, skipRateLimit: skipRateLimit)
        let response = executed.response
        var body = decodeBody(response, explicitCharset: analyzeUrl.charset)

        // 对应 executeStrRequest 的 isXml / bodyJs 后处理（顺序与 Kotlin 一致：先 XML 前缀，
        // 否则 bodyJs；bodyJs 用 AnalyzeUrl.evalJS 求值）。
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        if isXmlContentType(response.header("Content-Type")),
           !trimmed.lowercased().hasPrefix("<?xml") {
            body = "<?xml version=\"1.0\"?>" + body
        } else if let bodyJs = executed.request.bodyJs, !bodyJs.isEmpty {
            body = AnalyzeUrl.jsToString(analyzeUrl.evalJS(bodyJs, result: .string(body)))
        }

        return JsNetEnvelope.StrPayload(url: response.url,
                                        body: body,
                                        callTime: response.callTime,
                                        code: response.status,
                                        message: response.message ?? "",
                                        headers: response.headers)
    }

    // MARK: 解码与解析

    /// 响应体解码（最小链，见文件头差异 #2）。
    static func decodeBody(_ response: HTTPResponse, explicitCharset: String?) -> String {
        JsNetTextDecoder.decode(bytes: Array(response.body),
                                explicitCharset: explicitCharset,
                                contentTypeHeader: response.header("Content-Type"))
    }

    /// 十六进制串（小写，对齐 hutool HexUtil.encodeHexStr 的默认输出）。
    static func hexString(_ data: Data) -> String {
        var out = ""
        out.reserveCapacity(data.count * 2)
        for byte in data {
            out += String(format: "%02x", byte)
        }
        return out
    }

    /// Set-Cookie 头 → [(name, value)]（对齐 jsoup 1.16.2 Response.processResponseHeaders：
    /// 逐条 Set-Cookie 取第一个 name=value 段，重名只保留第一个；Foundation 可能按逗号/换行
    /// 合并多条，这里先按逗号/换行拆开再解析）。
    static func cookiesFromSetCookieHeaders(_ headers: [(String, String)]) -> [(String, String)] {
        var result: [(String, String)] = []
        var seen = Set<String>()
        for (name, value) in headers where name.caseInsensitiveCompare("Set-Cookie") == .orderedSame {
            for part in value.components(separatedBy: CharacterSet(charactersIn: ",\n")) {
                let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
                let firstSegment = trimmed.components(separatedBy: ";").first ?? ""
                guard !firstSegment.isEmpty, let eq = firstSegment.firstIndex(of: "=") else { continue }
                let key = String(firstSegment[firstSegment.startIndex..<eq]).trimmingCharacters(in: .whitespaces)
                let val = String(firstSegment[firstSegment.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
                guard !key.isEmpty, seen.insert(key).inserted else { continue }
                result.append((key, val))
            }
        }
        return result
    }

    /// 头查找（大小写不敏感，取首个，对齐 OkHttp/jsoup 语义）。
    static func headerValue(_ headers: [(String, String)], _ name: String) -> String? {
        for (k, v) in headers where k.caseInsensitiveCompare(name) == .orderedSame {
            return v
        }
        return nil
    }

    /// URL 规范化：OkHttp HttpUrl（jsoup 的 OkHttp 层同样会规范化）；解析失败保留原样，
    /// 由 HTTPClient 抛错（对齐 Kotlin 在 OkHttp 构造 Request 处抛异常 → JS 异常）。
    static func normalizedURL(_ url: String) -> String {
        if let normalized = HttpUrl.parse(url) {
            return normalized.urlString
        }
        return url
    }

    /// JS headers 对象 → JSON（JSJavaBridge/JsExtensionsRuntime 的字符串化规则）→ 有序数组。
    /// 差异 #3：顺序按字典序（JS 对象插入顺序在 Swift 侧不可恢复）；键唯一时不影响语义。
    static func parseHeadersJSON(_ json: String?) -> [(String, String)] {
        guard let json = json, !json.isEmpty else { return [] }
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: Any] else {
            return []
        }
        var pairs: [(String, String)] = []
        for key in dict.keys.sorted() {
            guard let value = dict[key] else { continue }
            if let s = value as? String {
                pairs.append((key, s))
            } else if let n = value as? NSNumber {
                // JS number → 字符串（与桥接层的 JsNumberFormat 语义一致）
                pairs.append((key, JsNumberFormat.toString(n.doubleValue)))
            } else if let b = value as? Bool {
                pairs.append((key, b ? "true" : "false"))
            }
            // 其它类型（对象/数组/null）跳过：Kotlin Map<String,String> 同语义
        }
        return pairs
    }

    /// connect 的 header 参数：JSON 字符串 → [(String, String)]?（解析失败/空 → nil，对齐
    /// Kotlin `GSON.fromJsonObject<Map<String, String>>(header).getOrNull()` 的容错）。
    static func parseHeaderJSONString(_ json: String?) -> [(String, String)]? {
        guard let json = json, !json.isEmpty else { return nil }
        let pairs = parseHeadersJSON(json)
        return pairs.isEmpty ? nil : pairs
    }

    /// JS 数字（毫秒/秒）字符串 → Int（截断；非法/空 → nil → 调用方用默认值）。
    static func parseTimeoutMillis(_ s: String?) -> Int? {
        guard let s = s, !s.isEmpty else { return nil }
        guard let d = Double(s), d.isFinite else { return nil }
        if d <= 0 { return nil }
        if d > Double(Int.max / 2) { return Int.max / 2 }
        return Int(d)
    }

    /// `text|application/...xml...` 全串匹配（对应 Kotlin `contentType.matches(xmlContentTypeRegex)`）。
    private static let xmlContentTypeRegex = NSRegularExpressionCache(
        pattern: "(application|text)/\\w*\\+?xml.*")

    static func isXmlContentType(_ contentType: String?) -> Bool {
        guard let ct = contentType else { return false }
        guard let m = xmlContentTypeRegex.firstMatch(in: ct) else { return false }
        return m.range.location == 0 && m.range.length == (ct as NSString).length
    }

    /// 下载字节（下载/缓存用）：data URI 直接解码，否则网络请求（含重定向跟随，OkHttp 默认）。
    static func bytesForDownload(_ analyzeUrl: AnalyzeUrl,
                                 client: HTTPClient,
                                 skipRateLimit: Bool) async throws -> Data {
        if let dataUriBytes = analyzeUrl.getByteArrayIfDataUri() {
            return dataUriBytes
        }
        let executed = try await buildAndExecute(analyzeUrl, client: client, skipRateLimit: skipRateLimit)
        return executed.response.body
    }

    /// 默认客户端：URLSessionHTTPClient + 内存 CookieStore（对应 Kotlin HttpHelper.okHttpClient）。
    static func makeDefaultClient() -> HTTPClient {
        let cache = CacheManager(storage: MemoryCacheStorage())
        let store = CookieStore(persistence: MemoryCookiePersistence(), cache: cache)
        return URLSessionHTTPClient(cookieStore: store, cookieManagerCache: cache)
    }
}
