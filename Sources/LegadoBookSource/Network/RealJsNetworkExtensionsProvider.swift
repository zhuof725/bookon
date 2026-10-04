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
//     | body / body()          | Connection.Response.body()     | 完整解码链（BOM→charset→Content-Type→HTML meta→ICU4J 检测器）解出的响应体 |
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
//     body / body() / code() / message() / headers() / raw() / toString() / callTime() / url()
//     ✅ `.body`（属性）与 `.body()`（方法）**双通道均已支持**（与 Kotlin StrResponse 的
//     `var body` + `fun body()` 一致）：JSJavaBridge 注入的 __installDualChannel 让属性返回
//     一个「可调用 + 转发 String 原型」的 Proxy，`x.body`、`x.body()`、拼接/比较/`String(x)`/
//     `JSON.stringify` / `x.body.length` / `x.body.indexOf(...)` 都与字符串语义一致。
//     唯一残留差异：`typeof x.body` 为 "function"、严格 `===` 字符串比较为 false（已记入差异表 6B-6）。
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
//   2. 文本解码：与 Kotlin `ResponseBody.text(encode)`（OkHttpUtils.kt）逐级一致 ——
//      BOM 剥离 → explicit charset（UrlOption.charset）→ Content-Type charset →
//      EncodingDetect.getHtmlEncode（HTML meta → ICU4J 检测器 → "UTF-8" 兜底）。
//      唯一差异：Kotlin 对「不可识别的 charset 名」抛 UnsupportedCharsetException，
//      本移植回退到下一级（不崩溃）；读取本地缓存文件同理（Kotlin 用
//      EncodingDetect.getEncode(file)，本移植在 EncodingDetect.getEncode(file:) 里实现同样的
//      「只取负字节、上限 8000」语义）；
//   3. headers 参数顺序：JS 对象经桥接 → JSON（Swift 侧按字典序），Kotlin 保持 JS 对象插入
//      顺序（LinkedHashMap）；键唯一时不影响 HTTP 语义；
//   4. get/post/head 的 Cookie：Kotlin 的 Jsoup.connect 用自建客户端（不带 legado CookieStore）；
//      本移植经 URLSessionHTTPClient 会注入 CookieStore 的 Cookie（客户端既有差异 #5 不变）；
//   5. get/post/head 的书源并发率：与 Kotlin 一致，经 `AnalyzeUrl.withRateLimit` 接到
//      `ConcurrentRateLimiter`（书源注入，见 RealJsNetworkExtensionsProvider.rateLimiter /
//      RealAjaxProvider）；`skipRateLimit` 为 true 时跳过；
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

// MARK: - 响应文本解码（与 Kotlin ResponseBody.text(encode) 逐级一致）

/// 响应字节 → 字符串的完整解码链，与 Kotlin `ResponseBody.text(encode)`（OkHttpUtils.kt）完全一致：
///
///   1. `Utf8BomUtils.removeUTF8BOM(bytes)` 剥离 UTF-8 BOM；
///   2. 显式 charset（书源 `UrlOption.charset`，由调用方传入 `explicitCharset`）；
///   3. OkHttp `MediaType.charset()`（即 `Content-Type` 头里的 charset 参数）；
///   4. `EncodingDetect.getHtmlEncode(bytes)`：
///        a. HTML `<meta charset>` / `<meta http-equiv=content-type content=...>`；
///        b. 否则 `EncodingDetect.getEncode(bytes)` → ICU4J 检测器，无匹配时 Kotlin 兜底 "UTF-8"。
///
/// 各级都按 Java `new String(bytes, charset)` 的 U+FFFD 替换语义解码。
enum JsNetTextDecoder {

    /// 剥离 UTF-8 BOM（对应 legado `Utf8BomUtils.removeUTF8BOM(bytes)`）。
    ///
    /// ⚠️ 判定条件是 **`bytes.size > 3`（严格大于）**，不是 `>= 3`：
    /// legado 的三处实现（`removeUTF8BOM(String)` / `removeUTF8BOM(ByteArray)` / `hasBom`）
    /// 用的都是 `bytes.size > 3`，因此**恰好只有 BOM、没有正文字节的 3 字节输入不会被剥离**，
    /// BOM 会原样留在解码结果里。本移植早期写成 `>= 3`，导致 `empty-only-bom` 这类样本
    /// 与 Kotlin 不一致（golden 期望 `"\u{FEFF}"`，Swift 却给出 `""`）。已按 Kotlin 修正。
    static func removeUTF8BOM(_ bytes: [UInt8]) -> [UInt8] {
        if bytes.count > 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF {
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

    /// bytes → String。完整链：BOM → explicitCharset（书源 charset）→ Content-Type charset
    /// → EncodingDetect.getHtmlEncode（HTML meta → ICU4J 检测器 → "UTF-8" 兜底）。
    /// 不可解码字节按 Java `new String(bytes, charset)` 的 U+FFFD 替换语义处理。
    ///
    /// 与 Kotlin `ResponseBody.text(encode)` 逐级对应；Kotlin 对不可识别 charset 名会抛
    /// `UnsupportedCharsetException`，这里回退到下一级（不崩溃，差异见 6B 差异表）。
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
        // 第 4/5 级：EncodingDetect.getHtmlEncode（HTML meta → ICU4J 检测器 → "UTF-8"）。
        let detected = EncodingDetect.getHtmlEncode(stripped)
        if let text = decode(data, charsetName: detected) { return text }
        // 检测出的名字在本移植的解码表里不可用（极少见）：退回 UTF-8 替换语义。
        return String(decoding: stripped, as: UTF8.self)
    }

    /// 按字符集名解码（支持 UTF-8/UTF-16/GBK/GB2312/GB18030/Big5/ISO-8859-1/ASCII；
    /// 其它名字返回 nil 走兜底）。
    ///
    /// **全部走容错解码**（`lossyString`），语义等同 Java `new String(bytes, charset)`：
    /// 遇到目标编码里非法的字节序列插入 U+FFFD，而不是整体失败。
    ///
    /// ⚠️ 不要对这些分支改用 `String(data:encoding:)`：它在 Apple 平台与 Linux 上都是
    /// **严格**的（非法字节 → nil）。一旦返回 nil，上层 `decode(bytes:...)` 会把它当作
    /// 「该 charset 不可用」而**回落到下一级**，从而静默忽略 explicit charset / Content-Type
    /// charset。实测的典型翻车：GBK 字节配 explicit=UTF-8，Kotlin 输出 UTF-8 乱码，
    /// 而严格路径返回 nil → 回落检测器 → 反而输出「正确中文」，与 Kotlin 全面不符
    /// （本地全量对照曾一次性暴露 820 处不一致）。
    static func decode(_ data: Data, charsetName: String) -> String? {
        let name = charsetName.uppercased().replacingOccurrences(of: "_", with: "-")
        switch name {
        case "UTF-8", "UTF8":
            // 直接用 Swift 标准库的容错 UTF-8 解码（Unicode 最大子部分算法），
            // **不要**走 `lossyString`：
            //   - `NSString`/`CFString` 的 UTF-8 解码在 Linux 上会把「孤立的 BOM」吃掉
            //     （`[EF BB BF]` → 空串），而 Java `new String(bytes,"UTF-8")` 与 Swift
            //     `String(decoding:)` 都保留 `U+FEFF`。走 NSString 会让 `empty-only-bom`
            //     这类样本与 Kotlin 不一致（golden 期望 "\u{FEFF}"）。
            //   - `String(decoding:as:UTF8.self)` 在 Apple 与 Linux 上语义完全一致，
            //     且替换字符个数与 Unicode 标准一致。
            return String(decoding: Array(data), as: UTF8.self)
        case "UTF-16", "UTF16":
            return Self.lossyString(data, nsEncoding: NSUTF16StringEncoding)
        case "UTF-16LE", "UTF16LE":
            return Self.lossyString(data, nsEncoding: NSUTF16LittleEndianStringEncoding)
        case "UTF-16BE", "UTF16BE":
            return Self.lossyString(data, nsEncoding: NSUTF16BigEndianStringEncoding)
        case "ISO-8859-1", "LATIN1", "ISO8859-1":
            return Self.lossyString(data, nsEncoding: NSISOLatin1StringEncoding)
        case "US-ASCII", "ASCII":
            // Java 的 US-ASCII 对 >0x7F 也是替换字符语义；这里同样用容错路径。
            return Self.lossyString(data, nsEncoding: NSASCIIStringEncoding)
        default:
            break
        }
        // GBK/GB2312/GB18030（CFStringEncodings.GB_18030_2000 与 Java 的 GBK 系兼容）
        if name == "GBK" || name == "GB2312" || name == "GB-2312" || name == "GB18030" || name == "CP936" {
            let nsEnc = CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
            if let s = Self.lossyString(data, nsEncoding: nsEnc) { return s }
            return nil
        }
        // Big5
        if name == "BIG5" || name == "BIG-5" || name == "BIG5-HKSCS" {
            let nsEnc = CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.big5.rawValue))
            if let s = Self.lossyString(data, nsEncoding: nsEnc) { return s }
            return nil
        }
        return nil
    }

    /// 用容错解码把字节转成字符串，**永不因字节非法而返回 nil**。
    ///
    /// 这是 Java `new String(bytes, charset)` / Kotlin `String(bytes, Charset)` 的语义：
    /// 遇到目标编码里非法的字节序列时插入 U+FFFD（替换字符），而不是整体解码失败。
    ///
    /// Foundation 的 `String(data:encoding:)` / `NSString(data:encoding:)` 在 Apple 平台是
    /// **严格**的：遇到非法的字节序列会返回 nil。这会让上层把「解码失败」误当作
    /// 「该 charset 不可用」而回落到下一级（Content-Type / 检测器），从而**静默忽略 explicit
    /// charset**——例如 golden 用例里 GBK 字节配 explicit=Big5，Kotlin 输出 Big5 乱码，
    /// 而严格解码返回 nil → 回落检测器 → 反而输出「正确的」GBK 中文，与 Kotlin 不符。
    ///
    /// 因此 Darwin 上走 `CFStringCreateWithBytes` 的**容错模式**
    /// （`isExternalRepresentation = false`，即上述 Java 语义）。
    ///
    /// 入参用 `UInt`（`CFStringConvertEncodingToNSStringEncoding` 的返回类型；
    /// Swift 里 `NSStringEncoding` 已 unavailable）。
    private static func lossyString(_ data: Data, nsEncoding: UInt) -> String? {
        guard nsEncoding != 0 else { return nil }
        let bytes = [UInt8](data)
        if bytes.isEmpty { return "" }
        #if canImport(Darwin)
        let cfEncoding = CFStringConvertNSStringEncodingToEncoding(nsEncoding)
        if cfEncoding != kCFStringEncodingInvalidId {
            let created: CFString? = bytes.withUnsafeBufferPointer { buf in
                guard let base = buf.baseAddress else { return nil }
                return CFStringCreateWithBytes(kCFAllocatorDefault,
                                               base,
                                               buf.count,
                                               cfEncoding,
                                               false)
            }
            // CFString 与 NSString 在 Darwin 上是 toll-free bridged，`as String` 由桥接支撑。
            if let created = created {
                return created as String
            }
        }
        // 编码在系统里不可用（cfEncoding == invalidId）或 CF 创建失败 → 落到下面的
        // 通用容错路径，仍然返回字符串而不是 nil。
        #endif
        // 非 Darwin 平台（供本地 Linux 语法/行为验证）或上述 CF 路径不可用时的退路。
        // `NSString(data:encoding:)` 在 Linux/Apple 上都是严格的（非法字节 → nil），
        // 所以这里必须自己按名分派到等价的容错路径，绝不能直接返回它的 nil。
        if let s = NSString(data: data, encoding: nsEncoding) as String? {
            return s
        }
        return lossyFallback(bytes, nsEncoding: nsEncoding)
    }

    /// 通用容错解码退路：对 Foundation 严格解码失败的字节，按「UTF-8 用 `String(decoding:)`
    /// 的替换字符语义；其余单/双字节编码逐字节映射」产出字符串。
    ///
    /// 这条路径只会在 `CFStringCreateWithBytes` 与 `NSString(data:encoding:)` 都失败时进入
    /// （Linux 本地验证、或系统缺该编码），目的只有一个：**永不返回 nil**，从而保持
    /// Java `new String(bytes, charset)` 的语义，不触发上游静默回落。
    private static func lossyFallback(_ bytes: [UInt8], nsEncoding: UInt) -> String? {
        switch nsEncoding {
        case NSUTF8StringEncoding:
            // 与 Java 的 UTF-8 解码一致：非法序列插入 U+FFFD。
            return String(decoding: bytes, as: UTF8.self)
        case NSISOLatin1StringEncoding:
            // ISO-8859-1 是全单字节映射：1 字节 = 1 个码位，永不失败。
            return String(bytes.map { Character(UnicodeScalar(UInt32($0))!) })
        default:
            return nil
        }
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

    /// 书源的并发率限制器（对应 Kotlin `ConcurrentRateLimiter(getSource())`）。
    /// get/post/head 在发起请求前经它 `withLimit`（Kotlin `withLimitBlocking`）；
    /// 为 nil 时不限速。可由初始化参数注入（测试可传自定义时钟/存储），
    /// 也可在拿到书源后通过 `setRateLimiterFromSource(_:)` 由书源构造。
    private var rateLimiter: ConcurrentRateLimiter?

    /// 对应 Kotlin `getSource()?.enabledCookieJar`：为 true 时 get/post/head 追加 `CookieJar: 1` 头。
    /// ⚠️ 差异：Kotlin 从书源实时读取；本移植 provider 不携带书源，需显式设置（默认 false）。
    public var enabledCookieJar: Bool = false

    public init(client: HTTPClient? = nil,
                environment: AnalyzeUrlEnvironment = AnalyzeUrlEnvironment(),
                cacheManager: CacheManagerProtocol = InMemoryCacheManager(),
                cacheDirectory: URL? = nil,
                diagnostics: RuleEngineDiagnostics? = nil,
                maxConcurrent: Int = RealJsNetworkExtensionsProvider.defaultMaxConcurrent,
                rateLimiter: ConcurrentRateLimiter? = nil) {
        self.client = client ?? RealJsNetworkExtensionsProvider.makeDefaultClient()
        self.environment = environment
        self.cacheManager = cacheManager
        self.cacheDirectory = cacheDirectory ?? RealJsNetworkExtensionsProvider.defaultCacheDirectory()
        self.diagnostics = diagnostics
        self.maxConcurrent = max(1, maxConcurrent)
        self.rateLimiter = rateLimiter
    }

    /// 用书源构造并发率限制器（对应 Kotlin `ConcurrentRateLimiter(getSource())`）。
    /// 书源 `concurrentRate` 为空时内部等价于不限速。
    /// 注意：`BookSource` 在 Swift 侧是 struct（`ConcurrentRateSource` 是 AnyObject 协议），
    /// 因此这里直接取 `concurrentRate` 字符串与 `bookSourceKey`。
    public func setRateLimiterFromSource(concurrentRate: String?, key: String?) {
        rateLimiter = AnalyzeUrl.makeRateLimiter(concurrentRate: concurrentRate, key: key)
    }

    /// 直接注入限制器（测试用）。
    public func setRateLimiter(_ limiter: ConcurrentRateLimiter?) {
        rateLimiter = limiter
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

        let response = try runBlockingNetwork { [self] in
            try await executeWithRateLimit { [client] in
                try await client.execute(request)
            }
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

        let response = try runBlockingNetwork { [self] in
            try await executeWithRateLimit { [client] in
                try await client.execute(request)
            }
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

    /// 对应 Kotlin `readTxtFile(path)`：文件不存在返回 ""；解码链见文件头 #2。
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

    /// get/post/head 的限速执行（对应 Kotlin `ConcurrentRateLimiter(getSource()).withLimitBlocking {}`）：
    /// 注入了 rateLimiter 时先取限速令牌再发请求，否则直连。
    private func executeWithRateLimit<T>(_ operation: @escaping () async throws -> T) async throws -> T {
        guard let limiter = rateLimiter else { return try await operation() }
        return try await limiter.withLimit(operation)
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

    /// 响应体解码（完整链：BOM → explicit → Content-Type → getHtmlEncode；见文件头 #2）。
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
