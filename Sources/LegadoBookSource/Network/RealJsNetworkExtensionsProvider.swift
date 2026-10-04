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
            return Self.lossyString(data, nsEncoding: NSUTF16StringEncoding,
                                    profile: Self.utf16Profile)
        case "UTF-16LE", "UTF16LE":
            return Self.lossyString(data, nsEncoding: NSUTF16LittleEndianStringEncoding,
                                    profile: Self.utf16Profile)
        case "UTF-16BE", "UTF16BE":
            return Self.lossyString(data, nsEncoding: NSUTF16BigEndianStringEncoding,
                                    profile: Self.utf16Profile)
        case "UTF-32", "UTF32":
            return Self.lossyString(data, nsEncoding: NSUTF32StringEncoding)
        case "UTF-32LE", "UTF32LE":
            return Self.lossyString(data, nsEncoding: NSUTF32LittleEndianStringEncoding)
        case "UTF-32BE", "UTF32BE":
            return Self.lossyString(data, nsEncoding: NSUTF32BigEndianStringEncoding)
        case "ISO-8859-1", "LATIN1", "ISO8859-1":
            return Self.lossyString(data, nsEncoding: NSISOLatin1StringEncoding)
        case "US-ASCII", "ASCII":
            // Java 的 US-ASCII 对 >0x7F 也是替换字符语义；这里同样用容错路径。
            return Self.lossyString(data, nsEncoding: NSASCIIStringEncoding)
        case "ISO-2022-JP", "ISO2022JP", "ISO-2022-JP-2", "JIS":
            // ISO-2022-JP 是**带状态的变长转义编码**，不是「一张码表 + 定长序列」，
            // 因此既不能用 `CFStringCreateWithBytes`（它没有跨调用状态，且
            // `kCFStringEncodingISO_2022_JP` 在 Linux 上不可用），也不能套 `MBCSProfile`。
            // 这里按 JIS X 0202 的状态机自行解码，语义对齐 JDK `new String(b,"ISO-2022-JP")`。
            //
            // 真实缺陷来源（CI run 37212186047，样本 `iso-2022-jp-japanese`）：
            //   Java  : decodedDefault = "第一章 旅立ち…"（83 字符）
            //   Swift : "\u{1B}$BBh0l>O\u{1B}(B …"（191 字符，ESC 序列原样输出）
            // 根因即此分支缺失 → `decode` 返回 nil → 上层回落检测器/UTF-8 → 直出原始字节。
            return Self.decodeISO2022JP(Array(data))
        default:
            break
        }
        // GBK/GB2312/GB18030（CFStringEncodings.GB_18030_2000 与 Java 的 GBK 系兼容）。
        // 字节结构（含 GB18030 的 4 字节形式）由 `mbcsProfile` 给出。
        if name == "GBK" || name == "GB2312" || name == "GB-2312" || name == "GB18030" || name == "CP936" {
            let nsEnc = CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
            if let s = Self.lossyString(data, nsEncoding: nsEnc,
                                        profile: Self.mbcsProfile(for: name)) { return s }
            return nil
        }
        // Big5。⚠️ 必须开 `puaIsFailure`：Apple 走 CP950 表（把 JDK 严格 Big5 表判为
        // 不可映射的位点落到 PUA），而 JDK 给 U+FFFD。开这个开关后，含 PUA 的整块会被判失败、
        // 转入增量解码，逐字符把 PUA 位点替换成 U+FFFD，从而与 JDK 输出对齐。
        if name == "BIG5" || name == "BIG-5" || name == "BIG5-HKSCS" {
            let nsEnc = CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.big5.rawValue))
            if let s = Self.lossyString(data, nsEncoding: nsEnc,
                                        profile: Self.mbcsProfile(for: name),
                                        puaIsFailure: true) { return s }
            return nil
        }

        // ── 日韩编码 ─────────────────────────────────────────────────────────
        // 这三族此前**完全缺失**，落到函数末尾的 `return nil` → 上层误判「charset 不可用」
        // → 回落到检测器/UTF-8 兜底。CI run 37209884314 实测：
        //   Java  : decodedDefault(Shift_JIS) = "第一章 旅立ち"
        //   Swift : "���� ������"（把 Shift_JIS 字节当 UTF-8 解）
        // 属真实移植缺陷，已补。
        if name == "SHIFT-JIS" || name == "SHIFTJIS" || name == "SJIS" || name == "MS-KANJI"
            || name == "WINDOWS-31J" || name == "CP932" {
            let nsEnc = CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.shiftJIS.rawValue))
            if let s = Self.lossyString(data, nsEncoding: nsEnc,
                                        profile: Self.mbcsProfile(for: name)) { return s }
            return nil
        }
        if name == "EUC-JP" || name == "EUCJP" {
            let nsEnc = CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.EUC_JP.rawValue))
            if let s = Self.lossyString(data, nsEncoding: nsEnc,
                                        profile: Self.mbcsProfile(for: name)) { return s }
            return nil
        }
        if name == "EUC-KR" || name == "EUCKR" || name == "CP949" || name == "KSC5601" {
            let nsEnc = CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.EUC_KR.rawValue))
            if let s = Self.lossyString(data, nsEncoding: nsEnc,
                                        profile: Self.mbcsProfile(for: name)) { return s }
            return nil
        }

        // ── 通用单字节编码兜底（windows-* / ISO-8859-* / KOI8-R / …）───────────
        //
        // 检测器（`EncodingDetect.getHtmlEncode`）会输出一批**单字节**编码名：
        // `windows-1250/1251/1252/1256`、`ISO-8859-5/7/8-I/9`、`KOI8-R` 等。
        // 这些编码没有多字节结构（每字节恒映射 1 个字符，未定义位点给 `U+FFFD`），
        // 因此不需要 `MBCSProfile`，但**必须有显式分支**——否则会落到函数末尾的
        // `return nil`，上层误判「charset 不可用」而回落到 UTF-8 兜底。
        //
        // 真实缺陷来源（CI run `37217650394`，样本 `windows-1251-russian`）：
        //   Java : decodedDefault = "Глава первая: Дорога…"（俄文）
        //   Swift: "����� ������: ������…"（把 windows-1251 字节当 UTF-8 解）
        // 这是修好 EUC-JP 之后**被暴露出来的下一条**（此前被 EUC-JP 的失败掩盖）。
        //
        // 用 `CFStringConvertIANACharSetNameToEncoding` 让 CF 自己解析 IANA 名，
        // 从而**一次覆盖全部单字节编码**，不必逐个手写 case。Apple 对
        // `windows-1251`/`ISO-8859-5`/`KOI8-R` 等的 IANA 名支持完整。
        //
        // ⚠️ 只对「CF 认得的、且不是已知多字节族」的名字生效：多字节族已在上面处理完，
        // 走到这里的一定是单字节族或未知名；未知名（如 `x-unknown-encoding`）解析结果
        // 为 `kCFStringEncodingInvalidId`，仍返回 nil，由上层回落。
        if let cfEnc = Self.ianaSingleByteEncodingName(name),
           cfEnc != kCFStringEncodingInvalidId {
            let nsEnc = CFStringConvertEncodingToNSStringEncoding(cfEnc)
            if nsEnc != 0, let s = Self.lossyString(data, nsEncoding: nsEnc) { return s }
            return nil
        }
        return nil
    }

    /// 把一个 IANA 字符集名解析为 CF 的**单字节**编码；不适用时返回 nil。
    ///
    /// 这是 `decode(_:charsetName:)` 的通用兜底：只放行单字节族，避免把
    /// 多字节编码（已在上面显式处理）误交到逐字节路径上。
    ///
    /// 放行名单来自 golden 侧检测器实际会输出的名字全集（见 `charset_cases.json`
    /// 的 `detectName` / `htmlEncode` 取值集），并做前缀匹配以覆盖别名。
    ///
    /// ⚠️ 只在 Apple 平台启用：`CFStringConvertIANACharSetNameToEncoding` 虽然在
    /// Linux 的 corelibs-foundation 里有符号，但其 IANA 名表是**空**的（恒返回
    /// `kCFStringEncodingInvalidId`），依赖它会让 Linux 侧行为与 Apple 不一致。
    /// 本移植只为 Apple 平台交付运行时行为，Linux 仅用于 `swiftc -parse`。
    private static func ianaSingleByteEncodingName(_ name: String) -> CFStringEncoding? {
        #if canImport(Darwin)
        // 只放行已知单字节族的前缀。
        let singleBytePrefixes = [
            "WINDOWS-12",   // windows-1250/1251/1252/1256
            "CP12",         // cp1250/1251/1252
            "ISO-8859-",    // ISO-8859-2..16（-1 已在上面处理）
            "ISO8859-",
            "KOI8-",
            "IBM8",         // IBM866 等
        ]
        guard singleBytePrefixes.contains(where: { name.hasPrefix($0) }) else { return nil }
        return CFStringEncoding(CFStringConvertIANACharSetNameToEncoding(name as CFString))
        #else
        _ = name
        return nil
        #endif
    }
    /// 用容错解码把字节转成字符串，**永不因字节非法而返回 nil**。
    ///
    /// 这是 Java `new String(bytes, charset)` / Kotlin `String(bytes, Charset)` 的语义：
    /// 遇到目标编码里非法的字节序列时插入 U+FFFD（替换字符），而不是整体解码失败。
    ///
    /// Foundation 的 `String(data:encoding:)` / `NSString(data:encoding:)` 是**严格**的：
    /// 遇到非法的字节序列会返回 nil。这会让上层把「解码失败」误当作「该 charset 不可用」
    /// 而回落到下一级（Content-Type / 检测器），从而**静默忽略 explicit charset**——
    /// 例如 GBK 字节配 explicit=Big5，Kotlin 输出 Big5 乱码，而严格解码返回 nil →
    /// 回落检测器 → 反而输出「正确的」GBK 中文，与 Kotlin 不符。
    ///
    /// ⚠️ `CFStringCreateWithBytes` 也**不是**容错的：只要缓冲里有**任何一个**非法字节序列，
    /// 它就整块返回 `NULL`（Apple 官方文档：`NULL if there was a problem creating the object`；
    /// 社区亦有多例 Big5 返回空串/`NULL` 的报告）。因此不能"整块试一次、失败就放弃"——
    /// 那会在 macOS 上把 Big5/EUC 系全部退化为 `nil`（本地 CI 实测：`testDecodePriorityMatchesKotlin`
    /// 中 `decode(Data(gbkBytes), charsetName: "Big5")` 返回 nil）。
    ///
    /// 本实现改为**增量容错**：从左到右每次吃掉最长的可解码前缀，无法解码的单个字节
    /// 输出一个 U+FFFD。这样合法部分正常还原、非法部分留下替换字符，与 Java 的替换语义
    /// 逐码位一致（已用真实 JVM 核对：12 字节 GBK 配 Big5 → `笢恅聆彸囀` + 2×U+FFFD）。
    ///
    /// ### `puaIsFailure`：为什么只有 Big5 需要把 PUA 视作解码失败
    ///
    /// 由 CI 真实日志（run `37207219284`）统计得出，**两类 CJK 编码的行为截然不同**：
    ///
    /// | 编码 | Apple 与 Java 的码表是否一致 | Java 侧含 PUA 的用例数 |
    /// |---|---|---|
    /// | GB18030 / GBK / GB2312 | **一致**（两侧都输出同一批 `U+E0xx` PUA 位点） | 80 / 240 |
    /// | Big5 | **不一致**：Apple 走 CP950（含 PUA 扩展），JDK 走严格 Big5（差异位点给 `U+FFFD`） | 0 / 240 |
    ///
    /// 所以 **PUA 拒绝只能对 Big5 开**：对 GB 系开会把 80 条本来正确的用例打成 `U+FFFD`；
    /// 对 Big5 不开，则 Apple 的 PUA 会与 JDK 的 `U+FFFD` 不一致（CI 实测 3 处）。
    ///
    /// 入参用 `UInt`（`CFStringConvertEncodingToNSStringEncoding` 的返回类型；
    /// Swift 里 `NSStringEncoding` 已 unavailable）。
    ///
    /// `mbcsProfile` 是该编码的**字节结构画像**（由调用点按编码族给出）。
    /// 传 `nil` 表示非 MBCS（UTF 系 / 单字节系），此时不做结构化解码。
    ///
    /// 刻意**不在函数内反查 CF 常量**：避免依赖具体 SDK 里
    /// `kCFStringEncoding*` / `CFStringEncodings.*` 成员的拼写与可用性
    /// （CI 实测：`kCFStringEncodingUTF8` 等在 Swift 里并非全局可见，会编译不过）。
    private static func lossyString(_ data: Data, nsEncoding: UInt,
                                    profile: MBCSProfile? = nil,
                                    puaIsFailure: Bool = false) -> String? {
        guard nsEncoding != 0 else { return nil }
        let bytes = [UInt8](data)
        if bytes.isEmpty { return "" }
        #if canImport(Darwin)
        let cfEncoding = CFStringConvertNSStringEncodingToEncoding(nsEncoding)
        if cfEncoding == kCFStringEncodingInvalidId {
            // 该编码在系统里不可用 → 交下面的通用退路。
            return lossyFallback(bytes, nsEncoding: nsEncoding)
        }
        // 先整体试一次（合法输入的最快路径，也是绝大多数情况）。
        // ⚠️ 变长 MBCS（profile != nil 且 unitWidth == 0）**不能**走这条捷径：
        // Apple 的 CF 会把非法字节悄悄跳过/替换，且消耗字节数与 JDK 不同
        //（见 `incrementalLossyDecode` 的文档）。
        //
        // 定宽码元（UTF-16，unitWidth == 2）**可以**走捷径：对完全合法的 UTF-16 输入，
        // CF 的整体解码与 JDK 逐码元解码结果一致，代理对也能正确合并；只有含孤立代理等
        // 非法输入时才会落到下面的增量路径（此时按码元推进，见 `utf16Profile`）。
        let isVariableWidthMBCS = (profile != nil && profile!.unitWidth == 0)
        if !isVariableWidthMBCS,
           let whole = decodeCFString(bytes, cfEncoding: cfEncoding),
           !(puaIsFailure && containsPrivateUse(whole)) {
            return whole
        }
        // 整块失败（或含 PUA，或变长 MBCS）：走增量容错，**永不返回 nil**。
        // 非 MBCS（profile == nil，即 ISO-8859-1/ASCII）用「逐字节」画像：
        // 每个字节单独试解，失败记 1 个 U+FFFD —— 这正是 ISO-8859-1 / ASCII 的
        // JDK 语义（单字节编码永不 MALFORMED）。UTF-16 用 `utf16Profile`（按 2 字节码元）。
        return incrementalLossyDecode(bytes, cfEncoding: cfEncoding,
                                      profile: profile ?? Self.byteWiseProfile,
                                      puaIsFailure: puaIsFailure)
        #else
        // 非 Darwin（本地 Linux 验证）：同样先整体试，失败再增量容错。
        _ = profile   // 仅 Darwin 的增量路径使用；此处显式忽略以免 unused 警告
        if let whole = NSString(data: data, encoding: nsEncoding) as String?,
           !(puaIsFailure && containsPrivateUse(whole)) {
            return whole
        }
        return lossyFallback(bytes, nsEncoding: nsEncoding)
        #endif
    }

    #if canImport(Darwin)
    /// 用 CoreFoundation 把一个字节缓冲整体转成 `String`；失败返回 `nil`。
    private static func decodeCFString(_ bytes: [UInt8], cfEncoding: CFStringEncoding) -> String? {
        guard !bytes.isEmpty else { return "" }
        let created: CFString? = bytes.withUnsafeBufferPointer { buf in
            guard let base = buf.baseAddress else { return nil }
            return CFStringCreateWithBytes(kCFAllocatorDefault,
                                           base,
                                           buf.count,
                                           cfEncoding,
                                           false)
        }
        // CFString 与 NSString 在 Darwin 上是 toll-free bridged，`as String` 由桥接支撑。
        guard let s = created else { return nil }
        return s as String
    }
    #endif

    // ── ISO-2022-JP ────────────────────────────────────────────────────────
    //
    // 这是唯一一个**带状态**的字符集：字节序列里夹着 `ESC`（0x1B）引导的字符集切换指令，
    // 后续字节的解释方式取决于当前所处的「设计集」。因此它既不能走 `CFStringCreateWithBytes`
    // （整块 API、无跨调用状态，且 `kCFStringEncodingISO_2022_JP` 在 Linux 上不可用），
    // 也不能套 `MBCSProfile`（那套模型假设每个字节/字节对独立可解）。
    //
    // 实现完全按 JDK `sun.nio.cs.ISO_2022_JP` 的状态机行为，由真实 JVM 探针逐条核对：
    //
    // | ESC 序列 | 目标字符集 | JDK 行为 |
    // |---|---|---|
    // | `ESC ( B` | ASCII | 单字节直通 |
    // | `ESC ( J` | JIS X 0201 Roman | 等价 ASCII（`0x5C`→`U+00A5`、`0x7E`→`U+203E` 的差异JDK 未采纳，实测直通） |
    // | `ESC ( I` | JIS X 0201 Katakana | 单字节 `21-5F` → 全角片假名 `U+FF61…U+FF9F` |
    // | `ESC $ @` / `ESC $ B` | JIS X 0208 | 双字节 `hi,lo ∈ 21-7E`，查表；未定义位点 → `U+FFFD` |
    // | 其它 | — | `MALFORMED[3]`：吃掉 3 字节，产 1 个 `U+FFFD` |
    //
    // 半角片假名（`ESC ( I`）与 JIS X 0208 的差异是实测得出的，不是猜测。

    /// 解码 ISO-2022-JP。语义对齐 JDK `new String(bytes, "ISO-2022-JP")`。
    ///
    /// 真实缺陷来源（CI run `37212186047`，样本 `iso-2022-jp-japanese`）：
    /// Java 83 字符 vs Swift 191 字符（ESC 序列原样输出）。
    static func decodeISO2022JP(_ bytes: [UInt8]) -> String {
        // 设计集：0 = ASCII/Roman，1 = JIS X 0201 Katakana，2 = JIS X 0208。
        var design: UInt8 = 0
        var out = String()
        out.reserveCapacity(bytes.count)
        var i = 0
        let n = bytes.count

        /// 把 `bytes[k..<k+len]` 按 JIS X 0208 查表；返回 `nil` 表示该位点无映射。
        func jis0208(_ hi: UInt8, _ lo: UInt8) -> UInt32? {
            // 同 `lookupJdkBig5`：一个 lead 可能有多段，需 `continue` 而非 `return nil`。
            for seg in Self.jis0208Segments where seg.hi == hi {
                guard lo >= seg.loStart else { continue }
                let off = Int(lo - seg.loStart)
                guard off < seg.count else { continue }
                return Self.jis0208Map[seg.offset + off]
            }
            return nil
        }

        while i < n {
            let b = bytes[i]

            if b == 0x1B {
                // ── ESC 序列 ──
                guard i + 1 < n else {
                    // 悬空 ESC：JDK 在 endOfInput 时报 MALFORMED，替换语义下产 1 个 U+FFFD。
                    out.unicodeScalars.append("\u{FFFD}")
                    i += 1
                    continue
                }
                let b1 = bytes[i + 1]
                if b1 == 0x24 {   // ESC $  → 双字节设计集
                    guard i + 2 < n else {
                        out.unicodeScalars.append("\u{FFFD}"); i += 1; continue
                    }
                    let b2 = bytes[i + 2]
                    if b2 == 0x40 || b2 == 0x42 {          // ESC $ @ / ESC $ B
                        design = 2
                        i += 3
                    } else {
                        out.unicodeScalars.append("\u{FFFD}")   // MALFORMED[3]
                        i += 3
                    }
                    continue
                }
                if b1 == 0x28 {   // ESC (  → 单字节设计集
                    guard i + 2 < n else {
                        out.unicodeScalars.append("\u{FFFD}"); i += 1; continue
                    }
                    let b2 = bytes[i + 2]
                    if b2 == 0x42 || b2 == 0x4A {          // ESC ( B / ESC ( J
                        design = 0
                        i += 3
                    } else if b2 == 0x49 {                 // ESC ( I
                        design = 1
                        i += 3
                    } else {
                        out.unicodeScalars.append("\u{FFFD}")   // MALFORMED[3]
                        i += 3
                    }
                    continue
                }
                // 其它 ESC 引导（含 ESC $ ( D / ESC $ ( O 这类 JDK 不支持的扩展）：
                // JDK 在 ISO-2022-JP 下报 MALFORMED[3]，吃 3 字节产 1 个 U+FFFD。
                out.unicodeScalars.append("\u{FFFD}")
                i += min(3, n - i)
                continue
            }

            // ── 非 ESC 字节：按当前设计集解释 ──
            switch design {
            case 2:
                // JIS X 0208 双字节。
                if b < 0x21 || b > 0x7E {
                    // 控制字符（如 0x0A）在双字节设计集下仍是单字节直通（JDK 实测：
                    // 样本里的换行在 ESC $ B 段内照常输出 U+000A）。
                    if b < 0x21 {
                        out.unicodeScalars.append(Unicode.Scalar(UInt32(b))!)
                        i += 1
                    } else {
                        out.unicodeScalars.append("\u{FFFD}")
                        i += 1
                    }
                    continue
                }
                guard i + 1 < n else {
                    out.unicodeScalars.append("\u{FFFD}")
                    i += 1
                    continue
                }
                let lo = bytes[i + 1]
                if lo < 0x21 || lo > 0x7E {
                    out.unicodeScalars.append("\u{FFFD}")
                    i += 1
                    continue
                }
                if let scalar = jis0208(b, lo), let us = Unicode.Scalar(scalar) {
                    out.unicodeScalars.append(us)
                } else {
                    out.unicodeScalars.append("\u{FFFD}")
                }
                i += 2
            case 1:
                // JIS X 0201 Katakana：0x21-0x5F → U+FF61…；其余按 JDK 处理。
                if b >= 0x21 && b <= 0x5F {
                    let idx = Int(b - 0x21)
                    if let us = Unicode.Scalar(Self.jis0201Katakana[idx]) {
                        out.unicodeScalars.append(us)
                    } else {
                        out.unicodeScalars.append("\u{FFFD}")
                    }
                } else if b < 0x21 {
                    out.unicodeScalars.append(Unicode.Scalar(UInt32(b))!)
                } else {
                    out.unicodeScalars.append("\u{FFFD}")
                }
                i += 1
            default:
                // ASCII / JIS X 0201 Roman：单字节直通。
                if b < 0x80 {
                    out.unicodeScalars.append(Unicode.Scalar(UInt32(b))!)
                } else {
                    out.unicodeScalars.append("\u{FFFD}")
                }
                i += 1
            }
        }
        return out
    }

    /// 私有使用区（PUA）判定：Apple 的若干 CJK 编码（Big5/EUC 等）把「无法映射到标准
    /// Unicode 的位点」落到 PUA（U+E000–U+F8FF），而 Java 判为不可映射并输出 `U+FFFD`。
    /// 为了让两侧逐码位一致，把这些 PUA 码位视同「解码失败」，交给替换字符逻辑。
    ///
    /// **不放在 `#if canImport(Darwin)` 里**：`lossyString` 的两个分支（Darwin 走 CF、
    /// 其它平台走 `NSString`）都需要它。
    private static func containsPrivateUse(_ s: String) -> Bool {
        s.unicodeScalars.contains { (0xE000...0xF8FF).contains($0.value) }
    }

    /// 多字节编码（MBCS）的**字节结构画像**：决定「从位置 `i` 起该吃几个字节」。
    ///
    /// ### 为什么需要它
    ///
    /// JDK 的 `CharsetDecoder` 在遇到非法输入时会报两种错误，**消耗的字节数不同**：
    ///
    /// | 错误 | 含义 | `CoderResult.length()` | 单向替换时的消耗 |
    /// |---|---|---|---|
    /// | `MALFORMED` | 该位置**根本不构成合法的字节序列** | 1（或 2/3，见下） | 吃掉 `length` 个字节，产 1 个 `U+FFFD` |
    /// | `UNMAPPABLE` | 字节序列**合法但码表里没有对应字符** | 全部序列长度 | 同上 |
    ///
    /// 这个差别**直接决定输出字符数**。真实 CI 实测（run `37211011044`，样本 `utf8-chinese`
    /// 的 `decodedExplicitBig5`）：Java 给 234 字符，旧 Swift 给 283 字符 —— 就是因为在
    /// `MALFORMED[1]`（吃 1）与 `UNMAPPABLE[2]`（吃 2）两类位置上判错，逐位累积成 49 个字符的偏差。
    ///
    /// ### 为什么不能用「试探窗口能解出几个字符」来推断
    ///
    /// `CFStringCreateWithBytes` 是**整块** API，没有「消耗了几个字节」的概念；对非法字节它要么
    /// 整块返回 `NULL`，要么（更麻烦）**悄悄跳过或替换**。而 Apple 的码表与 JDK 又有系统性差异
    /// （见 `README` 差异 6B-13/6B-14）。唯一可靠的做法是：**按字节结构先算出该吃几个字节，
    /// 再把这一段交给 CF 解出字符**——结构规则来自真实 JVM 探针，不依赖任何 Apple 行为。
    ///
    /// ### 规则来源
    ///
    /// 下表由真实 JDK 逐位探针得出（`MALFORMED`/`UNMAPPABLE` 的 `length()` 全枚举）：
    ///
    /// | 编码 | 单字节有效范围 | 双字节 lead | 双字节 trail | 额外多字节 |
    /// |---|---|---|---|---|
    /// | GBK / GB2312 / CP936 | `00–7F` | `81–FE` | `40–7E`,`80–FE` | — |
    /// | GB18030 | `00–7F` | `81–FE` | `40–7E`,`80–FE` | `81–FE`+`30–39`+`81–FE`+`30–39` |
    /// | Big5 | `00–7F` | `A1–F9` | `40–7E`,`A1–FE` | — |
    /// | Shift_JIS / CP932 | `00–7F`,`A1–DF` | `81–9F`,`E0–FC` | `40–7E`,`80–FC` | — |
    /// | EUC-KR | `00–7F` | `A1–FE` | `A1–FE` | — |
    /// | EUC-JP | `00–7F` | `A1–FE` | `A1–FE` | `8E`+`A1–DF`；`8F`+`A1–FE`+`A1–FE` |
    ///
    /// 任一条件不满足即为非法：若「首字节本身就不可能是 lead」→ `MALFORMED[1]`；
    /// 若「首字节是 lead 但 trail 不合法」→ `MALFORMED[1]`（trail 属于 `00–3F`/`7F` 的空白带）
    /// 或 `UNMAPPABLE[2]`（trail 属于 `80–A0`/`FF` 的高位带）。两类都产 1 个 `U+FFFD`，
    /// 但**消耗字节数不同**，所以必须区分。
    ///
    /// ### trail 的三分类（本结构的关键）
    ///
    /// 设首字节 `hi` 是合法 lead、次字节 `lo` 是「形状上像 trail」的字节，则 JDK 会把它归入三类之一：
    ///
    /// | 类别 | 判定 | 单向替换时 |
    /// |---|---|---|
    /// | **映射区** | `lo` 落在映射用 trail 范围且码表有值 | 吃 2 字节，出 1 个字符 |
    /// | `UNMAPPABLE[2]` | `lo` 落在「高位带」 | 吃 2 字节，出 1 个 `U+FFFD` |
    /// | `MALFORMED[1]` | `lo` 落在「低位带」 | 吃 1 字节，出 1 个 `U+FFFD`（`lo` 留到下一轮） |
    ///
    /// 真实 JDK 全枚举探针（`lead = 0xB8`）得到的分带：
    ///
    /// | 编码 | 映射区 trail | `MALFORMED[1]` | `UNMAPPABLE[2]` |
    /// |---|---|---|---|
    /// | GBK / GB18030 | `40–7E`, `80–FE` | `00–3F`, `7F` | `FF` |
    /// | Big5 | `40–7E`, `A1–FE` | `00–3F`, `7F` | `80–A0`, `FF` |
    /// | Shift_JIS | `40–7E`, `80–FC` | `00–3F`, `7F` | `FD–FF` |
    /// | EUC-KR | `A1–FE` | `00–7F` | `80–A0`, `FF` |
    ///
    /// ### `malformedExceptions`：少数 lead 的映射区「有洞」
    ///
    /// 大多数 lead 的分带是规整区间，但有极少数 lead 在**映射区内部**开了洞 —— 这些 `(hi, lo)`
    /// 组合形状合法、却仍判 `MALFORMED[1]`。它们来自码表本身的结构（如 Big5 的 `A3` 区、
    /// JIS X 0208 的 `81`/`82`/`EA` 区），必须逐条列出。探针实测的规模：
    ///
    /// | 编码 | 有洞的 lead 数 | 备注 |
    /// |---|---|---|
    /// | GBK / GB18030 / EUC-JP | **0** | 纯区间规则即可 100% 吻合 |
    /// | Big5 | 4（`A1`/`A3`/`C8`/`F9`） | 压缩成 7 个区间 |
    /// | EUC-KR | 13 | 压缩成 21 个区间 |
    ///
    /// 这张例外表是 `README` 差异 6B-17 的修复依据。
    struct MBCSProfile {
        /// 单字节直接映射（ASCII）的上界，含。
        let singleByteMax: UInt8
        /// 单字节直接映射的**额外**离散取值（Shift_JIS 的 `A1–DF` 半角片假名）。
        let singleByteExtra: ClosedRange<UInt8>?
        /// 双字节序列的 lead 范围列表。
        let leadRanges: [ClosedRange<UInt8>]
        /// 双字节序列中**可映射**的 trail 范围列表。
        let trailRanges: [ClosedRange<UInt8>]
        /// trail 落在这些范围内时判 `UNMAPPABLE[2]`（吃 2 字节）。
        let u2TrailRanges: [ClosedRange<UInt8>]
        /// trail 落在这些范围内时判 `MALFORMED[2]`（吃 **2** 字节，产 1 个 `U+FFFD`）。
        /// 目前只有 GB18030 需要：`hi(81-FE) + lo(30-39)` 是 4 字节序列的第 1、2 字节，
        /// 若后续两字节不构成合法 4 字节序列，JDK 报 `MALFORMED[2]`（而不是 `[1]`）。
        let m2TrailRanges: [ClosedRange<UInt8>]
        /// `(lead, trail)` 落在这些区间内时判 `MALFORMED[1]`（吃 1 字节），
        /// **即便该 trail 落在 `trailRanges` 内**。键为 lead 字节。
        let malformedExceptions: [UInt8: [ClosedRange<UInt8>]]
        /// `(lead, trail)` 落在这些区间内时判 `UNMAPPABLE[2]`（吃 **2** 字节），
        /// **即便该 trail 落在 `trailRanges` 内**。键为 lead 字节。
        ///
        /// 与 `malformedExceptions` 的区别只在**消耗字节数**：两者都产 1 个 `U+FFFD`，
        /// 但前者吃 1 字节（trail 留给下一轮），后者吃 2 字节。
        ///
        /// 目前只有 EUC-JP 用它：JVM 探针（`JdkProf EUC-JP A4`）显示 `A1–FE` lead 的
        /// trail 分带是 `MAP A1–F3` / `U 20–A0 ∪ F4–FF` / **`M` 为空** ——
        /// 即「lead 合法 + 后面有字节」恒为 `UNMAPPABLE[2]`，**从不** `MALFORMED[1]`。
        let unmappableExceptions: [UInt8: [ClosedRange<UInt8>]]
        /// 三字节序列的 lead（EUC-JP 的 `8E`/`8F`）。
        let threeByteLead: [UInt8]
        /// 四字节序列（GB18030）的第二、四字节范围。
        let fourByteDigitRange: ClosedRange<UInt8>?
        /// 该编码的双字节区是否**改用内嵌的 JDK 严格表**（而不是 Apple CF 表）。
        ///
        /// 仅 Big5 为 `true`。原因见 `big5JdkTableBase64` 的文档：Apple 的
        /// `CFStringEncodings.big5` 是 **CP950**，与 JDK 严格 `Big5` 表存在三类差异，
        /// 其中「CP950 独有且非 PUA」的 44 个位点**无法靠 `puaIsFailure` 补救**，
        /// 只能以 JDK 表为准。
        ///
        /// 其它编码族为 `false`（GB 系 Apple 与 JDK 码表一致，见 README 差异 6B-13/6B-14）。
        let useJdkBig5Table: Bool

        /// **固定码元宽度**（字节）。`0` 表示「变长，按 lead/trail 结构推进」（所有 MBCS）。
        ///
        /// 目前只有 UTF-16 用它（值 `2`）。原因（CI run `37219082032` 的
        /// `ext-cn-3-utf-16be`）：UTF-16 的最小单元是 **2 字节码元**，一对合法的
        /// 高/低代理（`D800-DBFF` + `DC00-DFFF`）必须**整体**解成 1 个补充平面标量。
        /// 早期把它当成 `byteWiseProfile`（逐**字节**）推进，代理对被拆成两个孤立的
        /// 半码元各解一次，于是 Java 41 个标量的样本在 Swift 侧变成 42 个
        /// （Java `…U+A060 U+A060…` vs Swift 多出 1 个），被 golden 对照判为不一致。
        let unitWidth: Int

        func isLead(_ b: UInt8) -> Bool { leadRanges.contains { $0.contains(b) } }
        func isTrail(_ b: UInt8) -> Bool { trailRanges.contains { $0.contains(b) } }
        func isU2Trail(_ b: UInt8) -> Bool { u2TrailRanges.contains { $0.contains(b) } }
        func isM2Trail(_ b: UInt8) -> Bool { m2TrailRanges.contains { $0.contains(b) } }
        func isSingle(_ b: UInt8) -> Bool {
            if b <= singleByteMax { return true }
            if let e = singleByteExtra, e.contains(b) { return true }
            return false
        }
        /// 该 `(hi, lo)` 是否命中「映射区内的洞」→ 应按 `MALFORMED[1]` 处理。
        func isMalformedException(_ hi: UInt8, _ lo: UInt8) -> Bool {
            guard let rs = malformedExceptions[hi] else { return false }
            return rs.contains { $0.contains(lo) }
        }
        /// 该 `(hi, lo)` 是否命中「形状合法但无映射」→ 应按 `UNMAPPABLE[2]` 处理（吃 2 字节）。
        func isUnmappableException(_ hi: UInt8, _ lo: UInt8) -> Bool {
            guard let rs = unmappableExceptions[hi] else { return false }
            return rs.contains { $0.contains(lo) }
        }
    }

    /// 构造区间列表的简写。
    private static func ranges(_ pairs: (UInt8, UInt8)...) -> [ClosedRange<UInt8>] {
        pairs.map { $0.0...$0.1 }
    }

    /// 按编码族返回字节结构画像；返回 `nil` 表示该编码不走结构化解码（UTF 系 / 单字节系）。
    static func mbcsProfile(for name: String) -> MBCSProfile? {
        switch name {
        case "GB2312", "GB-2312":
            // GB2312 与 GBK **不是同一张表**：lead 上界是 `F7`（非 `FE`），
            // 且 trail 只有 `A1–FE`（无 `40–7E` 区）。JVM 探针实测另有 7 个 lead 在
            // 映射区内部开洞（`A2`/`A4`/`A5`/`A6`/`A7`/`A8`/`A9`）。
            // 早期实现误让它复用 GBK 画像，导致 112/240 与 Java 不符（本地镜像实测）。
            //
            // ⚠️ `u2TrailRanges` **不能为空**（CI run `37219082032` 的
            // `html-meta-content-only`）：`G2312Prof` 对真实 JDK 全枚举 87 个 lead × 256 个
            // trail，得到统一分带 `MAL1[00-7F] U2[80-A0] <映射区含洞> U2[FF-FF]` ——
            // 即 **lead 后面只要不是低位字节（`00-7F`），JDK 一律按整段消耗**：
            //   - `lo ∈ 80-A0 ∪ FF`（非 trail 但非低位）→ `UNMAPPABLE[2]` 吃 **2**；
            //   - `lo ∈ A1-FE` 且在映射区 → MAP 吃 2；在洞内 → `MALFORMED[1]` 吃 1；
            //   - `lo ∈ 00-7F`（含空格 `20`）→ `MALFORMED[1]` 吃 1。
            //
            // 早期 `u2TrailRanges: []` 让 `BA 8E` / `E9 90` 这类组合各吃 1 字节，
            // 于是 259 字节的样本解出 226 个标量，而 JDK 是 213（每个这样的位置多 1 个
            // `U+FFFD`，共 13 处）。
            return MBCSProfile(
                singleByteMax: 0x7F,
                singleByteExtra: nil,
                leadRanges: ranges((0xA1, 0xA9), (0xB0, 0xF7)),
                trailRanges: ranges((0xA1, 0xFE)),
                u2TrailRanges: ranges((0x80, 0xA0), (0xFF, 0xFF)),
                m2TrailRanges: [],
                malformedExceptions: [
                    0xA2: ranges((0xA1, 0xA9), (0xB0, 0xB0), (0xE3, 0xE4), (0xEF, 0xF0)),
                    0xA4: ranges((0xF4, 0xF7)),
                    0xA5: ranges((0xF7, 0xF7)),
                    0xA6: ranges((0xB9, 0xC0), (0xD9, 0xF7)),
                    0xA7: ranges((0xC2, 0xD0), (0xF2, 0xF7)),
                    0xA8: ranges((0xBB, 0xC4), (0xEA, 0xF7)),
                    0xA9: ranges((0xA1, 0xA3), (0xF0, 0xF7)),
                ],
                unmappableExceptions: [:],
                threeByteLead: [],
                fourByteDigitRange: nil,
                useJdkBig5Table: false,
                unitWidth: 0)
        case "GBK", "CP936", "GB18030":
            // GB18030 的 4 字节形式：b1(81-FE) b2(30-39) b3(81-FE) b4(30-39)。
            // 探针实测：GBK / GB18030 的 lead **零例外**，纯区间规则即 100% 吻合。
            let four: ClosedRange<UInt8>? = (name == "GB18030") ? 0x30...0x39 : nil
            return MBCSProfile(
                singleByteMax: 0x7F,
                singleByteExtra: nil,
                leadRanges: ranges((0x81, 0xFE)),
                trailRanges: ranges((0x40, 0x7E), (0x80, 0xFE)),
                u2TrailRanges: ranges((0xFF, 0xFF)),
                m2TrailRanges: (four == nil) ? [] : ranges((0x30, 0x39)),
                malformedExceptions: [:],
                unmappableExceptions: [:],
                threeByteLead: [],
                fourByteDigitRange: four,
                useJdkBig5Table: false,
                unitWidth: 0)
        case "BIG5", "BIG-5", "BIG5-HKSCS":
            // lead 为 A1-F9，但 **`C8` 是彻底无效的 lead**：JVM 探针实测 `C8` + 任意 trail
            // 全部报 `MALFORMED[1]`（吃 1 字节），且 JDK 严格 Big5 表里 `C8` 区**零映射**。
            // 因此把 lead 拆成 `A1-C7` 与 `C9-F9` 两段，`C8` 落到「非 lead」路径自动得到
            // 与 Java 相同的 `FFFD(1)`（CI run `37212186047` 样本 `shift-jis-japanese`
            // 的 `decodedExplicitBig5` 实测差异即由 `C8 82` 引起）。
            //
            // u2 带为 80-A0 与 FF；另有 3 个 lead（`A1`/`A3`/`F9`）在映射区内部开洞。
            return MBCSProfile(
                singleByteMax: 0x7F,
                singleByteExtra: nil,
                leadRanges: ranges((0xA1, 0xC7), (0xC9, 0xF9)),
                trailRanges: ranges((0x40, 0x7E), (0xA1, 0xFE)),
                u2TrailRanges: ranges((0x80, 0xA0), (0xFF, 0xFF)),
                m2TrailRanges: [],
                malformedExceptions: [
                    0xA1: ranges((0xC3, 0xC3), (0xC5, 0xC5)),
                    0xA3: ranges((0xC0, 0xC7), (0xC9, 0xF9)),
                    0xF9: ranges((0xD6, 0xF9)),
                ],
                unmappableExceptions: [:],
                threeByteLead: [],
                fourByteDigitRange: nil,
                useJdkBig5Table: true,
                unitWidth: 0)
        case "SHIFT-JIS", "SHIFTJIS", "SJIS", "MS-KANJI", "WINDOWS-31J", "CP932":
            // 0xA1-0xDF 是半角片假名（单字节）；lead 为 81-9F / E0-FC。
            // u2 带为 FD-FF；JIS X 0208 的 81/82/83/84/88/98/EA 区在映射区开洞。
            return MBCSProfile(
                singleByteMax: 0x7F,
                singleByteExtra: 0xA1...0xDF,
                leadRanges: ranges((0x81, 0x84), (0x88, 0x9F), (0xE0, 0xEA)),
                trailRanges: ranges((0x40, 0x7E), (0x80, 0xFC)),
                u2TrailRanges: ranges((0xFD, 0xFF)),
                m2TrailRanges: [],
                malformedExceptions: [
                   0x81: ranges((0xAD, 0xB7), (0xC0, 0xC7), (0xCF, 0xD9), (0xE9, 0xEA)),
                   0x82: ranges((0x40, 0x4E), (0x59, 0x5F), (0x7A, 0x7E), (0x9B, 0x9E)),
                   0x83: ranges((0x97, 0x9E), (0xB7, 0xBE), (0xD7, 0xEA)),
                   0x84: ranges((0x61, 0x6F), (0x92, 0x9E), (0xBF, 0xEA)),
                   0x88: ranges((0x40, 0x7E), (0x81, 0x84), (0x88, 0x9E)),
                   0x98: ranges((0x73, 0x7E), (0x81, 0x84), (0x88, 0x9E)),
                   0xEA: ranges((0xA5, 0xEA)),
                ],
                unmappableExceptions: [
                   0x81: ranges((0xEB, 0xEF), (0xF8, 0xFB)),
                   0x82: ranges((0x80, 0x80), (0xF2, 0xFC)),
                   0x83: ranges((0xEB, 0xFC)),
                   0x84: ranges((0xEB, 0xFC)),
                   0x88: ranges((0x80, 0x80), (0x85, 0x87)),
                   0x98: ranges((0x80, 0x80), (0x85, 0x87)),
                   0xEA: ranges((0xEB, 0xFC)),
                ],
                threeByteLead: [],
                fourByteDigitRange: nil,
                useJdkBig5Table: false,
                unitWidth: 0)
        case "EUC-KR", "EUCKR", "CP949", "KSC5601":
            // u2 带为 80-A0 与 FF；13 个 lead 在映射区开洞。
            return MBCSProfile(
                singleByteMax: 0x7F,
                singleByteExtra: nil,
                leadRanges: ranges((0xA1, 0xAC), (0xB0, 0xC8), (0xCA, 0xFD)),
                trailRanges: ranges((0xA1, 0xFE)),
                u2TrailRanges: ranges((0x80, 0xA0), (0xFF, 0xFF)),
                m2TrailRanges: [],
                malformedExceptions: [
                    0xA2: ranges((0xE9, 0xFD)),
                    0xA5: ranges((0xAB, 0xAC), (0xBA, 0xC0), (0xD9, 0xE0), (0xF9, 0xFD)),
                    0xA6: ranges((0xE5, 0xFD)),
                    0xA7: ranges((0xF0, 0xFD)),
                    0xA8: ranges((0xA5, 0xA5), (0xA7, 0xA7), (0xB0, 0xB0)),
                    0xAA: ranges((0xF4, 0xFD)),
                    0xAB: ranges((0xF7, 0xFD)),
                    0xAC: ranges((0xC2, 0xC8), (0xCA, 0xD0), (0xF2, 0xFD)),
                ],
                unmappableExceptions: [
                   0xA2: ranges((0xFE, 0xFE)),
                   0xA5: ranges((0xAD, 0xAF), (0xFE, 0xFE)),
                   0xA6: ranges((0xFE, 0xFE)),
                   0xA7: ranges((0xFE, 0xFE)),
                   0xAA: ranges((0xFE, 0xFE)),
                   0xAB: ranges((0xFE, 0xFE)),
                   0xAC: ranges((0xC9, 0xC9), (0xFE, 0xFE)),
                ],
                threeByteLead: [],
                fourByteDigitRange: nil,
                useJdkBig5Table: false,
                unitWidth: 0)
        case "EUC-JP", "EUCJP":
            // 结构：`A1-FE` 双字节（JIS X 0208）；`8E`+1 字节（JIS X 0201 片假名）；
            // `8F`+2 字节（JIS X 0212）。后两者在 `incrementalLossyDecode` 里单独处理。
            //
            // ⚠️ **EUC-JP 没有 `MALFORMED[1]` 的双字节情形** —— 这是它和 GBK/Big5/EUC-KR 的
            // 根本区别。真实 JVM 逐 lead 探针（`EucJpProf`，全 94 个 lead × 256 个 trail）实测：
            //
            // | 项 | 结果 |
            // |---|---|
            // | 有 `MALFORMED` 的 `(lead, trail)` | **0 个** |
            // | lead 合法、trail 无映射 | 一律 `UNMAPPABLE[2]`（**吃 2 字节**） |
            //
            // 即：只要首字节是 `A1-FE`，JDK 就把它与**紧随的那个字节**一起消费
            // （无论那个字节是 `20`、`40` 还是 `FF`），产 1 个 `U+FFFD`。
            // 旧实现按「trail 落低位带 → `MALFORMED[1]`」处理，每个这样的位置都**少吞 1 字节**，
            // 导致此后全部错位（CI run `37212186047` 的 `euc-jp-japanese-2` 位置 22；
            // 本地镜像对拍 `big5-traditional` 样本：JDK `A4 40` → 1 个 `U+FFFD`，
            // 旧实现 → `U+3042 U+0040`）。
            //
            // 因此画像写成：`trailRanges` = `A1-FE`（可映射候选），
            // `u2TrailRanges` = `00-A0 ∪ FF`（映射区外，吃 2 字节），
            // 再用 `unmappableExceptions` 列出每个 lead 在 `A1-FE` **内部的洞**（同样吃 2 字节）。
            // 27 条例外由 `EucJpProf` 全枚举直接导出，**不含人工推断**：
            // 26 条是 `A1-FE` lead 在映射区内的洞，另有 `FF`（非 lead 但同样吃 2 字节）。
            return MBCSProfile(
                singleByteMax: 0x7F,
                singleByteExtra: nil,
                leadRanges: ranges((0x80, 0xFF)),
                trailRanges: ranges((0xA1, 0xFE)),
                u2TrailRanges: ranges((0x00, 0xA0), (0xFF, 0xFF)),
                m2TrailRanges: [],
                malformedExceptions: [:],
                unmappableExceptions: [
                    0xFF: ranges((0xA1, 0xFE)),
                   0xA2: ranges((0xAF, 0xB9), (0xC2, 0xC9), (0xD1, 0xDB), (0xEB, 0xF1), (0xFA, 0xFD)),
                   0xA3: ranges((0xA1, 0xAF), (0xBA, 0xC0), (0xDB, 0xE0), (0xFB, 0xFE)),
                   0xA4: ranges((0xF4, 0xFE)),
                   0xA5: ranges((0xF7, 0xFE)),
                   0xA6: ranges((0xB9, 0xC0), (0xD9, 0xFE)),
                   0xA7: ranges((0xC2, 0xD0), (0xF2, 0xFE)),
                   0xA8: ranges((0xC1, 0xFE)),
                   0xA9: ranges((0xA1, 0xFE)),
                   0xAA: ranges((0xA1, 0xFE)),
                   0xAB: ranges((0xA1, 0xFE)),
                   0xAC: ranges((0xA1, 0xFE)),
                   0xAD: ranges((0xA1, 0xFE)),
                   0xAE: ranges((0xA1, 0xFE)),
                   0xAF: ranges((0xA1, 0xFE)),
                   0xCF: ranges((0xD4, 0xFE)),
                   0xF4: ranges((0xA7, 0xFE)),
                   0xF5: ranges((0xA1, 0xFE)),
                   0xF6: ranges((0xA1, 0xFE)),
                   0xF7: ranges((0xA1, 0xFE)),
                   0xF8: ranges((0xA1, 0xFE)),
                   0xF9: ranges((0xA1, 0xFE)),
                   0xFA: ranges((0xA1, 0xFE)),
                   0xFB: ranges((0xA1, 0xFE)),
                   0xFC: ranges((0xA1, 0xFE)),
                   0xFD: ranges((0xA1, 0xFE)),
                   0xFE: ranges((0xA1, 0xFE)),
                ],
                threeByteLead: [0x8E, 0x8F],
                fourByteDigitRange: nil,
                useJdkBig5Table: false,
                unitWidth: 0)
        default:
            return nil
        }
    }

    /// Big5 的 **JDK 严格表全量**（13708 个 `A1-F9` lead 区内的可映射位点）。
    ///
    /// ### 为什么不用 Apple 的 `CFStringEncodings.big5`
    ///
    /// Apple 的 `big5` 实际是 **CP950**，与 JDK 的严格 `Big5` 表有系统性差异：
    ///
    /// | 项 | 数量 | 后果 |
    /// |---|---|---|
    /// | 两侧都有、**值不同** | 263 | Apple 给 PUA 或异体字，与 JDK 逐码位不符 |
    /// | CP950 独有、JDK 无映射 | 6012 | JDK 判 `U+FFFD`；Apple 给 PUA，可靠 `puaIsFailure` 补齐 |
    /// | CP950 独有、非 PUA | 44 | JDK 判 `U+FFFD`，但 Apple 会输出真字符（**无法靠 PUA 判据补救**） |
    ///
    /// 第 3 类是关键：`A3E1` 在 Apple 上是 `U+20AC`（欧元符号），JDK Big5 判不可映射。
    /// 这类差异**无法用任何「PUA 是否算失败」的开关表达**，只能以 JDK 表为准。
    ///
    /// 真实缺陷来源（CI run `37212186047`，`euc-jp-japanese-2` 的 `decodedExplicitBig5`）：
    /// 字节 `C6 DD` → JDK Big5 给 `U+3079`（べ），Apple CP950 给 `U+F6ED`（PUA）→
    /// 旧实现按 `puaIsFailure` 替换成 `U+FFFD`，在字符位置 22 处与 Java 不符。
    ///
    /// ### 编码方式
    ///
    /// 值序列（每项 2 字节，big-endian）Base64 编码成单个字符串字面量
    /// （27416 字节 → 36556 字符），配合段索引 `(hi, loStart, offset, count)` 定位。
    /// 相比 13708 条字典字面量，源码体积与编译时间都低一个数量级。
    ///
    /// 表内未命中的 `(hi, lo)`：JDK 判不可映射 → 调用方输出 `U+FFFD`。
    private static let big5JdkTableBase64 =
        "MAD/DDABMAL/DiAi/xv/Gv8f/wH+MCAmICX+UP9k/lIAt/5U/lX+Vv5X/1wgE/4xIBT+M/8//jT+T/8I/wn+Nf42/1v/Xf43/jgwFDAV/jn+OjAQMBH+O/48MAowC/49/j4wCDAJ/j/+QDAMMA3+Qf5CMA4wD/5D/kT+Wf5a/lv+XP5d/l4gGCAZIBwgHTAdMB4gNSAy/wP/Bv8KIDsApzADJcslzyWzJbIlziYGJgUlxyXGJaEloCW9JbwyoyEFID7/P/5J/kr+Tf5O/kv+TP5f/mD+Yf8L/w0A1wD3ALEiGv8c/x7/HSJmImciYCIeIlIiYf5i/mP+ZP5l/mYiPCIpIioipSIgIh8ivzPSM9EiKyIuIjUiNCZAJkImQSYJIZEhkyGQIZIhliGXIZkhmCIlIiMlcSVy/w//PP8EAKUwEgCiAKP/Bf8gIQMhCf5p/mr+azPVM5wznTOeM84zoTOOM48zxACwUVlRW1FeUV1RYVFjVed06XzOJYElgiWDJYQlhSWGJYcliCWPJY4ljSWMJYsliiWJJTwlNCUsJSQlHCWUJQAlAiWVJQwlECUUJRglbSVuJXAlbyVQJV4laiVhJeIl4yXlJeQlcSVyJXP/EP8R/xL/E/8U/xX/Fv8X/xj/GSFgIWEhYiFjIWQhZSFmIWchaCFpMCEwIjAjMCQwJTAmMCcwKDApU0FTRFNF/yH/Iv8j/yT/Jf8m/yf/KP8p/yr/K/8s/y3/Lv8v/zD/Mf8y/zP/NP81/zb/N/84/zn/Ov9B/0L/Q/9E/0X/Rv9H/0j/Sf9K/0v/TP9N/07/T/9Q/1H/Uv9T/1T/Vf9W/1f/WP9Z/1oDkQOSA5MDlAOVA5YDlwOYA5kDmgObA5wDnQOeA58DoAOhA6MDpAOlA6YDpwOoA6kDsQOyA7MDtAO1A7YDtwO4A7kDugO7A7wDvQO+A78DwAPBA8MDxAPFA8YDxwPIA8kxBTEGMQcxCDEJMQoxCzEMMQ0xDjEPMRAxETESMRMxFDEVMRYxFzEYMRkxGjEbMRwxHTEeMR8xIDEhMSIxIzEkMSUxJjEnMSgxKQLZAskCygLHAstOAE5ZTgFOA05DTl1Ohk6MTrpRP1FlUWtR4FIAUgFSm1MVU0FTXFPITglOC04ITgpOK044UeFORU5ITl9OXk6OTqFRQFIDUvpTQ1PJU+NXH1jrWRVZJ1lzW1BbUVtTW/hcD1wiXDhccV3dXeVd8V3yXfNd/l5yXv5fC18TYk1OEU4QTg1OLU4wTjlOS1w5TohOkU6VTpJOlE6iTsFOwE7DTsZOx07NTspOy07EUUNRQVFnUW1RblFsUZdR9lIGUgdSCFL7Uv5S/1MWUzlTSFNHU0VTXlOEU8tTylPNWOxZKVkrWSpZLVtUXBFcJFw6XG9d9F57Xv9fFF8VX8NiCGI2YktiTmUvZYdll2WkZbll5WbwZwhnKGsga2JreWvLa9Rr22wPbDRwa3IqcjZyO3JHcllyW3Ksc4tOGU4WThVOFE4YTjtOTU5PTk5O5U7YTtRO1U7WTtdO407kTtlO3lFFUURRiVGKUaxR+VH6UfhSClKgUp9TBVMGUxdTHU7fU0pTSVNhU2BTb1NuU7tT71PkU/NT7FPuU+lT6FP8U/hT9VPrU+ZT6lPyU/FT8FPlU+1T+1bbVtpZFlkuWTFZdFl2W1Vbg1w8Xehd513mXgJeA15zXnxfAV8YXxdfxWIKYlNiVGJSYlFlpWXmZy5nLGcqZytnLWtja81sEWwQbDhsQWxAbD5yr3OEc4l03HTmdRh1H3UodSl1MHUxdTJ1M3WLdn12rna/du5323fid/N5Onm+enR6y04eTh9OUk5TTmlOmU6kTqZOpU7/TwlPGU8KTxVPDU8QTxFPD07yTvZO+07wTvNO/U8BTwtRSVFHUUZRSFFoUXFRjVGwUhdSEVISUg5SFlKjUwhTIVMgU3BTcVQJVA9UDFQKVBBUAVQLVARUEVQNVAhUA1QOVAZUElbgVt5W3VczVzBXKFctVyxXL1cpWRlZGlk3WThZhFl4WYNZfVl5WYJZgVtXW1hbh1uIW4VbiVv6XBZceV3eXgZedl50Xw9fG1/ZX9ZiDmIMYg1iEGJjYltiWGU2Zell6GXsZe1m8mbzZwlnPWc0ZzFnNWsha2Rre2wWbF1sV2xZbF9sYGxQbFVsYWxbbE1sTnBwcl9yXXZ+evl8c3z4fzZ/in+9gAGAA4AMgBKAM4B/gImAi4CMgeOB6oHzgfyCDIIbgh+CboJygn6Ga4hAiEyIY4l/liFOMk6oT01PT09HT1dPXk80T1tPVU8wT1BPUU89TzpPOE9DT1RPPE9GT2NPXE9gTy9PTk82T1lPXU9IT1pRTFFLUU1RdVG2UbdSJVIkUilSKlIoUqtSqVKqUqxTI1NzU3VUHVQtVB5UPlQmVE5UJ1RGVENUM1RIVEJUG1QpVEpUOVQ7VDhULlQ1VDZUIFQ8VEBUMVQrVB9ULFbqVvBW5FbrV0pXUVdAV01XR1dOVz5XUFdPVztY71k+WZ1ZklmoWZ5Zo1mZWZZZjVmkWZNZilmlW11bXFtaW1tbjFuLW49cLFxAXEFcP1w+XJBckVyUXIxd614MXo9eh16KXvdfBF8fX2RfYl93X3lf2F/MX9dfzV/xX+tf+F/qYhJiEWKEYpdilmKAYnZiiWJtYopifGJ+Ynlic2KSYm9imGJuYpVik2KRYoZlOWU7ZThl8Wb0Z19nTmdPZ1BnUWdcZ1ZnXmdJZ0ZnYGdTZ1drZWvPbEJsXmyZbIFsiGyJbIVsm2xqbHpskGxwbIxsaGyWbJJsfWyDbHJsfmx0bIZsdmyNbJRsmGyCcHZwfHB9cHhyYnJhcmByxHLCc5Z1LHUrdTd1OHaCdu9343nBecB5v3p2fPt/VYCWgJOAnYCYgJuAmoCygm+CkoKLgo2Ji4nSigCMN4xGjFWMnY1kjXCNs46rjsqPm4+wj8KPxo/Fj8Rd4ZCRkKKQqpCmkKORSZHGkcyWMpYuljGWKpYsTiZOVk5zTotOm06eTqtOrE9vT51PjU9zT39PbE+bT4tPhk+DT3BPdU+IT2lPe0+WT35Pj0+RT3pRVFFSUVVRaVF3UXZReFG9Uf1SO1I4UjdSOlIwUi5SNlJBUr5Su1NSU1RTU1NRU2ZTd1N4U3lT1lPUU9dUc1R1VJZUeFSVVIBUe1R3VIRUklSGVHxUkFRxVHZUjFSaVGJUaFSLVH1Ujlb6V4NXd1dqV2lXYVdmV2RXfFkcWUlZR1lIWURZVFm+WbtZ1Fm5Wa5Z0VnGWdBZzVnLWdNZylmvWbNZ0lnFW19bZFtjW5dbmluYW5xbmVubXBpcSFxFXEZct1yhXLhcqVyrXLFcs14YXhpeFl4VXhteEV54Xppel16cXpVell72XyZfJ18pX4BfgV9/X3xf3V/gX/1f9V//YA9gFGAvYDVgFmAqYBVgIWAnYClgK2AbYhZiFWI/Yj5iQGJ/YslizGLEYr9iwmK5YtJi22KrYtNi1GLLYshiqGK9Yrxi0GLZYsdizWK1YtpisWLYYtZi12LGYqxizmU+ZadlvGX6ZhRmE2YMZgZmAmYOZgBmD2YVZgpmB2cNZwtnbWeLZ5VncWecZ3Nnd2eHZ51nl2dvZ3Bnf2eJZ35nkGd1Z5pnk2d8Z2pncmsja2ZrZ2t/bBNsG2zjbOhs82yxbMxs5WyzbL1svmy8bOJsq2zVbNNsuGzEbLlswWyubNdsxWzxbL9su2zhbNtsymysbO9s3GzWbOBwlXCOcJJwinCZcixyLXI4ckhyZ3JpcsByznLZctdy0HOpc6hzn3Orc6V1PXWddZl1mnaEdsJ28nb0d+V3/Xk+eUB5QXnJech6enp5evp8/n9Uf4x/i4AFgLqApYCigLGAoYCrgKmAtICqgK+B5YH+gg2Cs4KdgpmCrYK9gp+CuYKxgqyCpYKvgriCo4Kwgr6Ct4ZOhnFSHYhojsuPzo/Uj9GQtZC4kLGQtpHHkdGVd5WAlhyWQJY/ljuWRJZClrmW6JdSl15On06tTq5P4U+1T69Pv0/gT9FPz0/dT8NPtk/YT99Pyk/XT65P0E/ET8JP2k/OT95Pt1FXUZJRkVGgUk5SQ1JKUk1STFJLUkdSx1LJUsNSwVMNU1dTe1OaU9tUrFTAVKhUzlTJVLhUplSzVMdUwlS9VKpUwVTEVMhUr1SrVLFUu1SpVKdUv1b/V4JXi1egV6NXolfOV65Xk1lVWVFZT1lOWVBZ3FnYWf9Z41noWgNZ5VnqWdpZ5loBWftbaVujW6ZbpFuiW6VcAVxOXE9cTVxLXNlc0l33Xh1eJV4fXn1eoF6mXvpfCF8tX2VfiF+FX4pfi1+HX4xfiWASYB1gIGAlYA5gKGBNYHBgaGBiYEZgQ2BsYGtgamBkYkFi3GMWYwli/GLtYwFi7mL9Ywdi8WL3Yu9i7GL+YvRjEWMCZT9lRWWrZb1l4mYlZi1mIGYnZi9mH2YoZjFmJGb3Z/9n02fxZ9Rn0GfsZ7Znr2f1Z+ln72fEZ9FntGfaZ+VnuGfPZ95n82ewZ9ln4mfdZ9JramuDa4ZrtWvSa9dsH2zJbQttMm0qbUFtJW0MbTFtHm0XbTttPW0+bTZtG2z1bTltJ204bSltLm01bQ5tK3CrcLpws3CscK9wrXC4cK5wpHIwcnJyb3J0culy4HLhc7dzynO7c7JzzXPAc7N1GnUtdU91THVOdUt1q3WkdaV1onWjdnh2hnaHdoh2yHbGdsN2xXcBdvl2+HcJdwt2/nb8dwd33HgCeBR4DHgNeUZ5SXlIeUd5uXm6edF50nnLen96gXr/ev18fX0CfQV9AH0JfQd9BH0Gfzh/jn+/gASAEIANgBGANoDWgOWA2oDDgMSAzIDhgNuAzoDegOSA3YH0giKC54MDgwWC44LbguaDBILlgwKDCYLSgteC8YMBgtyC1ILRgt6C04Lfgu+DBoZQhnmGe4Z6iE2Ia4mBidSKCIoCigOMnoygjXSNc420js2OzI/wj+aP4o/qj+WP7Y/rj+SP6JDKkM6QwZDDkUuRSpHNlYKWUJZLlkyWTZdil2mXy5ftl/OYAZiomNuY35mWmZlOWE6zUAxQDVAjT+9QJlAlT/hQKVAWUAZQPFAfUBpQElART/pQAFAUUChP8VAhUAtQGVAYT/NP7lAtUCpP/lArUAlRfFGkUaVRolHNUcxRxlHLUlZSXFJUUltSXVMqU39Tn1OdU99U6FUQVQFVN1T8VOVU8lUGVPpVFFTpVO1U4VUJVO5U6lTmVSdVB1T9VQ9XA1cEV8JX1FfLV8NYCVkPWVdZWFlaWhFaGFocWh9aG1oTWexaIFojWilaJVoMWglba1xYW7Bbs1u2W7Rbrlu1W7lbuFwEXFFcVVxQXO1c/Vz7XOpc6FzwXPZdAVz0Xe5eLV4rXqterV6nXzFfkl+RX5BgWWBjYGVgUGBVYG1gaWBvYIRgn2CaYI1glGCMYIVglmJHYvNjCGL/Y05jPmMvY1VjQmNGY09jSWM6Y1BjPWMqYytjKGNNY0xlSGVJZZllwWXFZkJmSWZPZkNmUmZMZkVmQWb4ZxRnFWcXaCFoOGhIaEZoU2g5aEJoVGgpaLNoF2hMaFFoPWf0aFBoQGg8aENoKmhFaBNoGGhBa4priWu3bCNsJ2wobCZsJGzwbWptlW2IbYdtZm14bXdtWW2TbWxtiW1ubVptdG1pbYxtim15bYVtZW2UcMpw2HDkcNlwyHDPcjlyeXL8cvly/XL4cvdzhnPtdAlz7nPgc+pz3nVUdV11XHVadVl1vnXFdcd1snWzdb11vHW5dcJ1uHaLdrB2ynbNds53KXcfdyB3KHfpeDB4J3g4eB14NHg3eCV4LXggeB94MnlVeVB5YHlfeVZ5XnldeVd5WnnkeeN553nfeeZ56XnYeoR6iHrZewZ7EXyJfSF9F30LfQp9IH0ifRR9EH0VfRp9HH0NfRl9G386f19/lH/Ff8GABoAYgBWAGYAXgD2AP4DxgQKA8IEFgO2A9IEGgPiA84EIgP2BCoD8gO+B7YHsggCCEIIqgiuCKIIsgruDK4NSg1SDSoM4g1CDSYM1gzSDT4MygzmDNoMXg0CDMYMog0OGVIaKhqqGk4akhqmGjIajhpyIcIh3iIGIgoh9iHmKGIoQig6KDIoVigqKF4oTihaKD4oRjEiMeox5jKGMoo13jqyO0o7Ujs+PsZABkAaP95AAj/qP9JADj/2QBY/4kJWQ4ZDdkOKRUpFNkUyR2JHdkdeR3JHZlYOWYpZjlmGWW5ZdlmSWWJZelruY4pmsmqia2JslmzKbPE5+UHpQfVBcUEdQQ1BMUFpQSVBlUHZQTlBVUHVQdFB3UE9QD1BvUG1RXFGVUfBSalJvUtJS2VLYUtVTEFMPUxlTP1NAUz5Tw2b8VUZValVmVURVXlVhVUNVSlUxVVZVT1VVVS9VZFU4VS5VXFUsVWNVM1VBVVdXCFcLVwlX31gFWApYBlfgV+RX+lgCWDVX91f5WSBZYlo2WkFaSVpmWmpaQFo8WmJaWlpGWkpbcFvHW8VbxFvCW79bxlwJXAhcB1xgXFxcXV0HXQZdDl0bXRZdIl0RXSldFF0ZXSRdJ10XXeJeOF42XjNeN163Xrhetl61Xr5fNV83X1dfbF9pX2tfl1+ZX55fmF+hX6BfnGB/YKNgiWCgYKhgy2C0YOZgvWDFYLtgtWDcYLxg2GDVYMZg32C4YNpgx2IaYhtiSGOgY6djcmOWY6JjpWN3Y2djmGOqY3FjqWOJY4Njm2NrY6hjhGOIY5ljoWOsY5Jjj2OAY3tjaWNoY3plXWVWZVFlWWVXVV9lT2VYZVVlVGWcZZtlrGXPZctlzGXOZl1mWmZkZmhmZmZeZvlS12cbaIFor2iiaJNotWh/aHZosWinaJdosGiDaMRorWiGaIVolGidaKhon2ihaIJrMmu6a+tr7GwrbY5tvG3zbdltsm3hbcxt5G37bfpuBW3Hbcttr23Rba5t3m35bbht9231bcVt0m4abbVt2m3rbdht6m3xbe5t6G3GbcRtqm3sbb9t5nD5cQlxCnD9cO9yPXJ9coFzHHMbcxZzE3MZc4d0BXQKdAN0BnP+dA104HT2dPd1HHUidWV1ZnVidXB1j3XUddV1tXXKdc12jnbUdtJ223c3dz53PHc2dzh3OnhreEN4TnlleWh5bXn7epJ6lXsgeyh7G3sseyZ7GXseey58knyXfJV9Rn1DfXF9Ln05fTx9QH0wfTN9RH0vfUJ9Mn0xfz1/nn+af8x/zn/SgByASoBGgS+BFoEjgSuBKYEwgSSCAoI1gjeCNoI5g46DnoOYg3iDooOWg72Dq4OSg4qDk4OJg6CDd4N7g3yDhoOnhlVfaobHhsCGtobEhrWGxobLhrGGr4bJiFOInoiIiKuIkoiWiI2Ii4mTiY+KKoodiiOKJYoxii2KH4obiiKMSYxajKmMrIyrjKiMqoynjWeNZo2+jbqO247fkBmQDZAakBeQI5AfkB2QEJAVkB6QIJAPkCKQFpAbkBSQ6JDtkP2RV5HOkfWR5pHjkeeR7ZHplYmWapZ1lnOWeJZwlnSWdpZ3lmyWwJbqlul64HrfmAKYA5tanOWedZ5/nqWeu1CiUI1QhVCZUJFQgFCWUJhQmmcAUfFSclJ0UnVSaVLeUt1S21NaU6VVe1WAVadVfFWKVZ1VmFWCVZxVqlWUVYdVi1WDVbNVrlWfVT5VslWaVbtVrFWxVX5ViVWrVZlXDVgvWCpYNFgkWDBYMVghWB1YIFj5WPpZYFp3Wppaf1qSWptap1tzW3Fb0lvMW9Nb0FwKXAtcMV1MXVBdNF1HXf1eRV49XkBeQ15+XspewV7CXsRfPF9tX6lfql+oYNFg4WCyYLZg4GEcYSNg+mEVYPBg+2D0YWhg8WEOYPZhCWEAYRJiH2JJY6NjjGPPY8Bj6WPJY8ZjzWPSY+Nj0GPhY9Zj7WPuY3Zj9GPqY9tkUmPaY/llXmVmZWJlY2WRZZBlr2ZuZnBmdGZ2Zm9mkWZ6Zn5md2b+Zv9nH2cdaPpo1WjgaNho12kFaN9o9WjuaOdo+WjSaPJo42jLaM1pDWkSaQ5oyWjaaW5o+2s+azprPWuYa5ZrvGvvbC5sL2wsbi9uOG5UbiFuMm5nbkpuIG4lbiNuG25bblhuJG5Wbm5uLW4mbm9uNG5NbjpuLG5Dbh1uPm7LboluGW5ObmNuRG5ybmluX3EZcRpxJnEwcSFxNnFucRxyTHKEcoBzNnMlczRzKXQ6dCp0M3QidCV0NXQ2dDR0L3QbdCZ0KHUldSZ1a3VqdeJ123Xjddl12HXedeB2e3Z8dpZ2k3a0dtx3T3fteF14bHhveg16CHoLegV6AHqYepd6lnrleuN7SXtWe0Z7UHtSe1R7TXtLe097UXyffKV9Xn1QfWh9VX0rfW59cn1hfWZ9Yn1wfXNVhH/Uf9WAC4BSgIWBVYFUgUuBUYFOgTmBRoE+gUyBU4F0ghKCHIPphAOD+IQNg+CDxYQLg8GD74Pxg/SEV4QKg/CEDIPMg/2D8oPKhDiEDoQEg9yEB4PUg9+GW4bfhtmG7YbUhtuG5IbQht6IV4jBiMKIsYmDiZaKO4pgilWKXoo8ikGKVIpbilCKRoo0ijqKNopWjGGMgoyvjLyMs4y9jMGMu4zAjLSMt4y2jL+MuI2KjYWNgY3Ojd2Ny43ajdGNzI3bjcaO+474jvyPnJAukDWQMZA4kDKQNpECkPWRCZD+kWORZZHPkhSSFZIjkgmSHpINkhCSB5IRlZSVj5WLlZGVk5WSlY6WipaOlouWfZaFloaWjZZyloSWwZbFlsSWxpbHlu+W8pfMmAWYBpgImOeY6pjvmOmY8pjtma6ZrZ7Dns2e0U6CUK1QtVCyULNQxVC+UKxQt1C7UK9Qx1J/UndSfVLfUuZS5FLiUuNTL1XfVehV01XmVc5V3FXHVdFV41XkVe9V2lXhVcVVxlXlVclXElcTWF5YUVhYWFdYWlhUWGtYTFhtWEpYYlhSWEtZZ1rBWslazFq+Wr1avFqzWsJasl1pXW9eTF55XsleyF8SX1lfrF+uYRphD2FIYR9g82EbYPlhAWEIYU5hTGFEYU1hPmE0YSdhDWEGYTdiIWIiZBNkPmQeZCpkLWQ9ZCxkD2QcZBRkDWQ2ZBZkF2QGZWxln2WwZpdmiWaHZohmlmaEZphmjWcDaZRpbWlaaXdpYGlUaXVpMGmCaUppaGlraV5pU2l5aYZpXWljaVtrR2tya8Brv2vTa/1uom6vbtNutm7CbpBunW7HbsVupW6Ybrxuum6rbtFulm6cbsRu1G6qbqdutHFOcVlxaXFkcUlxZ3FccWxxZnFMcWVxXnFGcWhxVnI6clJzN3NFcz9zPnRvdFp0VXRfdF50QXQ/dFl0W3RcdXZ1eHYAdfB2AXXydfF1+nX/dfR183bedt93W3drd2Z3Xndjd3l3andsd1x3ZXdod2J37niOeLB4l3iYeIx4iXh8eJF4k3h/eXp5f3mBhCx5vXocehp6IHoUeh96HnqfeqB7d3vAe2B7bntnfLF8s3y1fZN9eX2RfYF9j31bf25/aX9qf3J/qX+of6SAVoBYgIaAhIFxgXCBeIFlgW6Bc4FrgXmBeoFmggWCR4SChHeEPYQxhHWEZoRrhEmEbIRbhDyENYRhhGOEaYRthEaGXoZchl+G+YcThwiHB4cAhv6G+4cChwOHBocKiFmI34jUiNmI3IjYiN2I4YjKiNWI0omcieOKa4pyinOKZoppinCKh4p8imOKoIpxioWKbYpiim6KbIp5inuKPopojGKMioyJjMqMx4zIjMSMsozDjMKMxY3hjd+N6I3vjfON+o3qjeSN5o6yjwOPCY7+jwqPn4+ykEuQSpBTkEKQVJA8kFWQUJBHkE+QTpBNkFGQPpBBkRKRF5FskWqRaZHJkjeSV5I4kj2SQJI+kluSS5JkklGSNJJJkk2SRZI5kj+SWpWYlpiWlJaVls2Wy5bJlsqW95b7lvmW9pdWl3SXdpgQmBGYE5gKmBKYDJj8mPSY/Zj+mbOZsZm0muGc6Z6Cnw6fE58gUOdQ7lDlUNZQ7VDaUNVQz1DRUPFQzlDpUWJR81KDUoJTMVOtVf5WAFYbVhdV/VYUVgZWCVYNVg5V91YWVh9WCFYQVfZXGFcWWHVYfliDWJNYilh5WIVYfVj9WSVZIlkkWWpZaVrhWuZa6VrXWtZa2FrjW3Vb3lvnW+Fb5VvmW+hb4lvkW99cDVxiXYRdh15bXmNeVV5XXlRe017WXwpfRl9wX7lhR2E/YUthd2FiYWNhX2FaYVhhdWIqZIdkWGRUZKRkeGRfZHpkUWRnZDRkbWR7ZXJloWXXZdZmomaoZp1pnGmoaZVpwWmuadNpy2mbabdpu2mrabRp0GnNaa1pzGmmacNpo2tJa0xsM28zbxRu/m8TbvRvKW8+byBvLG8PbwJvIm7/bu9vBm8xbzhvMm8jbxVvK28vb4hvKm7sbwFu8m7MbvdxlHGZcX1xinGEcZJyPnKScpZzRHNQdGR0Y3RqdHB0bXUEdZF2J3YNdgt2CXYTduF243eEd313f3dheMF4n3ineLN4qXijeY55j3mNei56MXqqeql67Xrve6F7lXuLe3V7l3ude5R7j3u4e4d7hHy5fL18vn27fbB9nH29fb59oH3KfbR9sn2xfbp9on2/fbV9uH2tfdJ9x32sf3B/4H/hf9+AXoBagIeBUIGAgY+BiIGKgX+BgoHngfqCB4IUgh6CS4TJhL+ExoTEhJmEnoSyhJyEy4S4hMCE04SQhLyE0YTKhz+HHIc7hyKHJYc0hxiHVYc3hymI84kCiPSI+Yj4iP2I6IkaiO+KpoqMip6Ko4qNiqGKk4qkiqqKpYqoipiKkYqaiqeMaoyNjIyM04zRjNKNa42ZjZWN/I8UjxKPFY8Tj6OQYJBYkFyQY5BZkF6QYpBdkFuRGZEYkR6RdZF4kXeRdJJ4koCShZKYkpaSe5KTkpySqJJ8kpGVoZWolamVo5WllaSWmZaclpuWzJbSlwCXfJeFl/aYF5gYmK+YsZkDmQWZDJkJmcGar5qwmuabQZtCnPSc9pzznryfO59KUQRRAFD7UPVQ+VECUQhRCVEFUdxSh1KIUolSjVKKUvBTslYuVjtWOVYyVj9WNFYpVlNWTlZXVnRWNlYvVjBYgFifWJ5Ys1icWK5YqVimWW1bCVr7Wwta9VsMWwhb7lvsW+lb61xkXGVdnV2UXmJeX15hXuJe2l7fXt1e417gX0hfcV+3X7VhdmFnYW5hXWFVYYJhfGFwYWthfmGnYZBhq2GOYaxhmmGkYZRhrmIuZGlkb2R5ZJ5ksmSIZJBksGSlZJNklWSpZJJkrmStZKtkmmSsZJlkomSzZXVld2V4Zq5mq2a0ZrFqI2ofaehqAWoeahlp/WohahNqCmnzagJqBWntahFrUGtOa6RrxWvGbz9vfG+Eb1FvZm9Ub4ZvbW9bb3hvbm+Ob3pvcG9kb5dvWG7Vb29vYG9fcZ9xrHGxcahyVnKbc05zV3RpdIt0g3R+dIB1f3Ygdil2H3YkdiZ2IXYidpp2unbkd453h3eMd5F3i3jLeMV4unjKeL541Xi8eNB6P3o8ekB6PXo3ejt6r3que617sXvEe7R7xnvHe8F7oHvMfMp94H30fe99+33Yfex93X3ofeN92n3efel9nn3ZffJ9+X91f3d/r3/pgCaBm4GcgZ2BoIGagZiFF4U9hRqE7oUshS2FE4URhSOFIYUUhOyFJYT/hQaHgod0h3aHYIdmh3iHaIdZh1eHTIdTiFuIXYkQiQeJEokTiRWJCoq8itKKx4rEipWKy4r4irKKyYrCir+KsIrWis2Ktoq5ituMTIxOjGyM4IzejOaM5IzsjO2M4ozjjNyM6ozhjW2Nn42jjiuOEI4djiKOD44pjh+OIY4ejrqPHY8bjx+PKY8mjyqPHI8ejyWQaZBukGiQbZB3kTCRLZEnkTGRh5GJkYuRg5LFkruSt5LqkqyS5JLBkrOSvJLSkseS8JKyla2VsZcElwaXB5cJl2CXjZeLl4+YIZgrmByYs5kKmROZEpkYmd2Z0JnfmduZ0ZnVmdKZ2Zq3mu6a75snm0WbRJt3m2+dBp0JnQOeqZ6+ns5YqJ9SURJRGFEUURBRFVGAUapR3VKRUpNS81ZZVmtWeVZpVmRWeFZqVmhWZVZxVm9WbFZiVnZYwVi+WMdYxVluWx1bNFt4W/BcDl9KYbJhkWGpYYphzWG2Yb5hymHIYjBkxWTBZMtku2S8ZNpkxGTHZMJkzWS/ZNJk1GS+ZXRmxmbJZrlmxGbHZrhqPWo4ajpqWWpralhqOWpEamJqYWpLakdqNWpfakhrWWt3bAVvwm+xb6Fvw2+kb8Fvp2+zb8BvuW+2b6ZvoG+0cb5xyXHQcdJxyHHVcblxznHZcdxxw3HEc2h0nHSjdJh0n3SedOJ1DHUNdjR2OHY6dud25Xegd553n3eleOh42njseOd5pnpNek56RnpMekt6unvZfBF7yXvke9t74Xvpe+Z81XzWfgp+EX4Ifht+I34efh1+CX4Qf3l/sn/wf/F/7oAogbOBqYGogfuCCIJYglmFSoVZhUiFaIVphUOFSYVthWqFXoeDh5+Hnoeih42IYYkqiTKJJYkriSGJqommiuaK+orrivGLAIrciueK7or+iwGLAor3iu2K84r2ivyMa4xtjJOM9I5EjjGONI5CjjmONY87jy+POI8zj6iPppB1kHSQeJBykHyQepE0kZKTIJM2kviTM5MvkyKS/JMrkwSTGpMQkyaTIZMVky6TGZW7lqeWqJaqltWXDpcRlxaXDZcTlw+XW5dcl2aXmJgwmDiYO5g3mC2YOZgkmRCZKJkemRuZIZkame2Z4pnxmriavJr7mu2bKJuRnRWdI50mnSidEp0bntie1J+Nn5xRKlEfUSFRMlL1Vo5WgFaQVoVWh1aPWNVY01jRWM5bMFsqWyRbelw3XGhdvF26Xb1duF5rX0xfvWHJYcJhx2HmYctiMmI0ZM5kymTYZOBk8GTmZOxk8WTiZO1lgmWDZtlm1mqAapRqhGqiapxq22qjan5ql2qQaqBrXGuua9psCG/Yb/Fv32/gb9tv5G/rb+9vgG/sb+Fv6W/Vb+5v8HHncd9x7nHmceVx7XHscfRx4HI1ckZzcHNydKl0sHSmdKh2RnZCdkx26nezd6p3sHesd6d3rXfvePd4+nj0eO95AXmneap6V3q/fAd8DXv+e/d8DHvgfOB83HzefOJ833zZfN1+Ln4+fkZ+N34yfkN+K349fjF+RX5BfjR+OX5IfjV+P34vf0R/83/8gHGAcoBwgG+Ac4HGgcOBuoHCgcCBv4G9gcmBvoHoggmCcYWqhYSFfoWchZGFlIWvhZuFh4WohYqGZ4fAh9GHs4fSh8aHq4e7h7qHyIfLiTuJNolEiTiJPYmsiw6LF4sZixuLCosgix2LBIsQjEGMP4xzjPqM/Yz8jPiM+42ojkmOS45IjkqPRI8+j0KPRY8/kH+QfZCEkIGQgpCAkTmRo5GekZyTTZOCkyiTdZNKk2WTS5MYk36TbJNbk3CTWpNUlcqVy5XMlciVxpaxlriW1pcclx6XoJfTmEaYtpk1mgGZ/5uum6ubqputnTudP56Lns+e3p7cnt2e258+n0tT4laVVq5Y2VjYWzhfXWHjYjNk9GTyZP5lBmT6ZPtk92W3ZtxnJmqzaqxqw2q7arhqwmquaq9rX2t4a69wCXALb/5wBm/6cBFwD3H7cfxx/nH4c3dzdXSndL91FXZWdlh2Une9d793u3e8eQ55rnphemJ6YHrEesV8K3wnfCp8HnwjfCF8535UflV+Xn5afmF+Un5Zf0h/+X/7gHeAdoHNgc+CCoXPhamFzYXQhcmFsIW6hbmFpofvh+yH8ofgiYaJson0iyiLOYssiyuMUI0FjlmOY45mjmSOX45VjsCPSY9NkIeQg5CIkauRrJHQk5STipOWk6KTs5Ouk6yTsJOYk5qTl5XUldaV0JXVluKW3JbZltuW3pckl6OXppetl/mYTZhPmEyYTphTmLqZPpk/mT2ZLpmlmg6awZsDmwabT5tOm02bypvJm/2byJvAnVGdXZ1gnuCfFZ8sUTNWpVjeWN9Y4lv1n5Be7GHyYfdh9mH1ZQBlD2bgZt1q5Wrdatpq03AbcB9wKHAacB1wFXAYcgZyDXJYcqJzeHN6dL10ynTjdYd1hnZfdmF3x3kZebF6a3ppfD58P3w4fD18N3xAfmt+bX55fml+an+FfnN/tn+5f7iB2IXphd2F6oXVheSF5YX3h/uIBYgNh/mH/olgiV+JVolei0GLXItYi0mLWotOi0+LRotZjQiNCo58jnKOh452jmyOeo50j1SPTo+tkIqQi5Gxka6T4ZPRk9+Tw5PIk9yT3ZPWk+KTzZPYk+ST15PoldyWtJbjlyqXJ5dhl9yX+5hemFiYW5i8mUWZSZoWmhmbDZvom+eb1pvbnYmdYZ1ynWqdbJ6Snpeek560UvhWqFa3VrZWtFa8WORbQFtDW31b9l3JYfhh+mUYZRRlGWbmZydq7HA+cDBwMnIQc3t0z3ZidmV5JnkqeSx5K3rHevZ8THxDfE1873zwj65+fX58foJ/TIAAgdqCZoX7hfmGEYX6hgaGC4YHhgqIFIgViWSJuon4i3CLbItmi2+LX4trjQ+NDY6JjoGOhY6CkbSRy5QYlAOT/ZXhlzCYxJlSmVGZqJormjCaN5o1nBOcDZ55nrWe6J8vn1+fY59hUTdROFbBVsBWwlkUXGxdzWH8Yf5lHWUcZZVm6Wr7awRq+muycExyG3KndNZ01HZpd9N8UH6Pfox/vIYXhi2GGogjiCKIIYgfiWqJbIm9i3SLd4t9jROOio6NjouPX4+vkbqULpQzlDWUOpQ4lDKUK5XilziXOZcyl/+YZ5hlmVeaRZpDmkCaPprPm1SbUZwtnCWdr520ncKduJ6dnu+fGZ9cn2afZ1E8UTtWyFbKVslbf13UXdJfTmH/ZSRrCmthcFFwWHOAdOR1inZudmx5s3xgfF+AfoB9gd+JcolvifyLgI0WjReOkY6Tj2GRSJRElFGUUpc9lz6Xw5fBmGuZVZpVmk2a0psanEmcMZw+nDud053XnzSfbJ9qn5RWzF3WYgBlI2UrZSpm7GsQdNp6ynxkfGN8ZX6TfpZ+lIHihjiGP4gxi4qQkJCPlGOUYJRkl2iYb5lcmlqaW5pXmtOa1JrRnFScV5xWneWen570VtFY6WUscF52cXZyd9d/UH+IiDaIOYhii5OLkouWgneNG5HAlGqXQpdIl0SXxphwml+bIptYnF+d+Z36nnyefZ8Hn3efcl7zaxZwY3xsfG6IO4nAjqGRwZRylHCYcZlemtabI57McGR32oualHeXyZpimmV+nIucjqqRxZR9lH6UfJx3nHie94xUlH+eGnIommqbMZ4bnh58cjD+MJ0wnjAFMEEwQjBDMEQwRTBGMEcwSDBJMEowSzBMME0wTjBPMFAwUTBSMFMwVDBVMFYwVzBYMFkwWjBbMFwwXTBeMF8wYDBhMGIwYzBkMGUwZjBnMGgwaTBqMGswbDBtMG4wbzBwMHEwcjBzMHQwdTB2MHcweDB5MHowezB8MH0wfjB/MIAwgTCCMIMwhDCFMIYwhzCIMIkwijCLMIwwjTCOMI8wkDCRMJIwkzChMKIwozCkMKUwpjCnMKgwqTCqMKswrDCtMK4wrzCwMLEwsjCzMLQwtTC2MLcwuDC5MLowuzC8ML0wvjC/MMAwwTDCMMMwxDDFMMYwxzDIMMkwyjDLMMwwzTDOMM8w0DDRMNIw0zDUMNUw1jDXMNgw2TDaMNsw3DDdMN4w3zDgMOEw4jDjMOQw5TDmMOcw6DDpMOow6zDsMO0w7jDvMPAw8TDyMPMw9DD1MPYEFAQVBAEEFgQXBBgEGQQaBBsEHAQjBCQEJQQmBCcEKAQpBCoEKwQsBC0ELgQvBDAEMQQyBDMENAQ1BFEENgQ3BDgEOQQ6BDsEPAQ9BD4EPwRABEEEQgRDBEQERQRGBEcESARJBEoESwRMBE0ETgRPJGAkYSRiJGMkZCRlJGYkZyRoJGkkdCR1JHYkdyR4JHkkeiR7JHwkfU5CTlxR9VMaU4JOB04MTkdOjVbX+gxcbl9zTg9Rh04OTi5Ok07CTslOyFGYUvxTbFO5VyBZA1ksXBBd/2Xha7NrzGwUcj9OMU48TuhO3E7pTuFO3U7aUgxTHFNMVyJXI1kXWS9bgVuEXBJcO1x0XHNeBF6AXoJfyWIJYlBsFWw2bENsP2w7cq5ysHOKebiAipYeTw5PGE8sTvVPFE7xTwBO908ITx1PAk8FTyJPE08ETvRPElGxUhNSCVIQUqZTIlMfU01TilQHVuFW31cuVypXNFk8WYBZfFmFWXtZfll3WX9bVlwVXCVcfFx6XHtcfl3fXnVehF8CXxpfdF/VX9Rfz2JcYl5iZGJhYmZiYmJZYmBiWmJlZe9l7mc+ZzlnOGc7ZzpnP2c8ZzNsGGxGbFJsXGxPbEpsVGxLbExwcXJecrRytXOOdSp2f3p1f1GCeIJ8goCCfYJ/hk2JfpCZkJeQmJCbkJSWIpYkliCWI09WTztPYk9JT1NPZE8+T2dPUk9fT0FPWE8tTzNPP09hUY9RuVIcUh5SIVKtUq5TCVNjU3JTjlOPVDBUN1QqVFRURVQZVBxUJVQYVD1UT1RBVChUJFRHVu5W51blV0FXRVdMV0lXS1dSWQZZQFmmWZhZoFmXWY5ZolmQWY9Zp1mhW45bklwoXCpcjVyPXIhci1yJXJJcilyGXJNclV3gXgpeDl6LXolejF6IXo1fBV8dX3hfdl/SX9Ff0F/tX+hf7l/zX+Ff5F/jX/pf71/3X/tgAF/0Yjpig2KMYo5ij2KUYodicWJ7YnpicGKBYohid2J9YnJidGU3ZfBl9GXzZfJl9WdFZ0dnWWdVZ0xnSGddZ01nWmdLa9BsGWwabHhsZ2xrbIRsi2yPbHFsb2xpbJpsbWyHbJVsnGxmbHNsZWx7bI5wdHB6cmNyv3K9csNyxnLBcrpyxXOVc5dzk3OUc5J1OnU5dZR1lXaBeT2ANICVgJmAkICSgJyCkIKPgoWCjoKRgpOCioKDgoSMeI/Jj7+Qn5ChkKWQnpCnkKCWMJYoli+WLU4zT5hPfE+FT31PgE+HT3ZPdE+JT4RPd09MT5dPak+aT3lPgU94T5BPnE+UT55Pkk+CT5VPa09uUZ5RvFG+UjVSMlIzUkZSMVK8UwpTC1M8U5JTlFSHVH9UgVSRVIJUiFRrVHpUflRlVGxUdFRmVI1Ub1RhVGBUmFRjVGdUZFb3VvlXb1dyV21Xa1dxV3BXdleAV3VXe1dzV3RXYldoV31ZDFlFWbVZulnPWc5ZslnMWcFZtlm8WcNZ1lmxWb1ZwFnIWbRZx1tiW2Vbk1uVXERcR1yuXKRcoFy1XK9cqFysXJ9co1ytXKJcqlynXJ1cpVy2XLBcpl4XXhReGV8oXyJfI18kX1Rfgl9+X31f3l/lYC1gJmAZYDJgC2A0YApgF2AzYBpgHmAsYCJgDWAQYC5gE2ARYAxgCWAcYhRiPWKtYrRi0WK+YqpitmLKYq5is2KvYrtiqWKwYrhlPWWoZbtmCWX8ZgRmEmYIZftmA2YLZg1mBWX9ZhFmEGb2ZwpnhWdsZ45nkmd2Z3tnmGeGZ4RndGeNZ4xnemefZ5FnmWeDZ31ngWd4Z3lnlGsla4BrfmvebB1sk2zsbOts7mzZbLZs1GytbOdst2zQbMJsumzDbMZs7WzybNJs3Wy0bIpsnWyAbN5swG0wbM1sx2ywbPlsz2zpbNFwlHCYcIVwk3CGcIRwkXCWcIJwmnCDcmpy1nLLcthyyXLcctJy1HLacsxy0XOkc6FzrXOmc6JzoHOsc5103XTodT91QHU+dYx1mHavdvN28XbwdvV3+Hf8d/l3+3f6d/d5Qnk/ecV6eHp7evt8dXz9gDWAj4CugKOAuIC1gK2CIIKggsCCq4KagpiCm4K1gqeCroK8gp6CuoK0gqiCoYKpgsKCpILDgraCooZwhm+GbYZujFaP0o/Lj9OPzY/Wj9WP15CykLSQr5CzkLCWOZY9ljyWOpZDT81PxU/TT7JPyU/LT8FP1E/cT9lPu0+zT9tPx0/WT7pPwE+5T+xSRFJJUsBSwlM9U3xTl1OWU5lTmFS6VKFUrVSlVM9Uw4MNVLdUrlTWVLZUxVTGVKBUcFS8VKJUvlRyVN5UsFe1V55Xn1ekV4xXl1edV5tXlFeYV49XmVelV5pXlVj0WQ1ZU1nhWd5Z7loAWfFZ3Vn6Wf1Z/Fn2WeRZ8ln3WdtZ6VnzWfVZ4Fn+WfRZ7VuoXExc0FzYXMxc11zLXNtc3lzaXMlcx1zKXNZc01zUXM9cyFzGXM5c31z4XfleIV4iXiNeIF4kXrBepF6iXpteo16lXwdfLl9WX4ZgN2A5YFRgcmBeYEVgU2BHYElgW2BMYEBgQmBfYCRgRGBYYGZgbmJCYkNiz2MNYwti9WMOYwNi62L5Yw9jDGL4YvZjAGMTYxRi+mMVYvti8GVBZUNlqmW/ZjZmIWYyZjVmHGYmZiJmM2YrZjpmHWY0ZjlmLmcPZxBnwWfyZ8hnumfcZ7tn+GfYZ8Bnt2fFZ+tn5GffZ7VnzWezZ/dn9mfuZ+Nnwme5Z85n52fwZ7Jn/GfGZ+1nzGeuZ+Zn22f6Z8lnymfDZ+pny2soa4JrhGu2a9Zr2GvgbCBsIW0obTRtLW0fbTxtP20SbQps2m0zbQRtGW06bRptEW0AbR1tQm0BbRhtN20DbQ9tQG0HbSBtLG0IbSJtCW0QcLdwn3C+cLFwsHChcLRwtXCpckFySXJKcmxycHJzcm5yynLkcuhy63Lfcupy5nLjc4VzzHPCc8hzxXO5c7ZztXO0c+tzv3PHc75zw3PGc7hzy3TsdO51LnVHdUh1p3Wqdnl2xHcIdwN3BHcFdwp293b7dvp353foeAZ4EXgSeAV4EHgPeA54CXgDeBN5SnlMeUt5RXlEedV5zXnPedZ5znqAen560XsAewF8enx4fHl8f3yAfIF9A30IfQF/WH+Rf41/voAHgA6AD4AUgDeA2IDHgOCA0YDIgMKA0IDFgOOA2YDcgMqA1YDJgM+A14DmgM2B/4IhgpSC2YL+gvmDB4LogwCC1YM6guuC1oL0guyC4YLygvWDDIL7gvaC8ILqguSC4IL6gvOC7YZ3hnSGfIZziEGITohniGqIaYnTigSKB41yj+OP4Y/uj+CQ8ZC9kL+Q1ZDFkL6Qx5DLkMiR1JHTllSWT5ZRllOWSpZOUB5QBVAHUBNQIlAwUBtP9U/0UDNQN1AsT/ZP91AXUBxQIFAnUDVQL1AxUA5RWlGUUZNRylHEUcVRyFHOUmFSWlJSUl5SX1JVUmJSzVMOU55VJlTiVRdVElTnVPNU5FUaVP9VBFUIVOtVEVUFVPFVClT7VPdU+FTgVQ5VA1ULVwFXAlfMWDJX1VfSV7pXxle9V7xXuFe2V79Xx1fQV7lXwVkOWUpaGVoWWi1aLloVWg9aF1oKWh5aM1tsW6dbrVusXANcVlxUXOxc/1zuXPFc910AXPleKV4oXqherl6qXqxfM18wX2dgXWBaYGdgQWCiYIhggGCSYIFgnWCDYJVgm2CXYIdgnGCOYhliRmLyYxBjVmMsY0RjRWM2Y0Nj5GM5Y0tjSmM8YyljQWM0Y1hjVGNZYy1jR2MzY1pjUWM4Y1djQGNIZUplRmXGZcNlxGXCZkpmX2ZHZlFnEmcTaB9oGmhJaDJoM2g7aEtoT2gWaDFoHGg1aCtoLWgvaE5oRGg0aB1oEmgUaCZoKGguaE1oOmglaCBrLGsvay1rMWs0a22AgmuIa+Zr5Gvoa+Nr4mvnbCVtem1jbWRtdm0NbWFtkm1YbWJtbW1vbZFtjW3vbX9thm1ebWdtYG2XbXBtfG1fbYJtmG0vbWhti21+bYBthG0WbYNte219bXVtkHDccNNw0XDdcMt/OXDicNdw0nDecOBw1HDNcMVwxnDHcNpwznDhckJyeHJ3cnZzAHL6cvRy/nL2cvNy+3MBc9Nz2XPlc9ZzvHPnc+Nz6XPcc9Jz23PUc91z2nPXc9hz6HTedN909HT1dSF1W3VfdbB1wXW7dcR1wHW/dbZ1unaKdsl3HXcbdxB3E3cSdyN3EXcVdxl3Gncidyd4I3gseCJ4NXgveCh4LngreCF4KXgzeCp4MXlUeVt5T3lceVN5UnlReet57Hngee557Xnqedx53nndeoZ6iXqFeot6jHqKeod62HsQewR7E3sFew97CHsKew57CXsSfIR8kXyKfIx8iHyNfIV9Hn0dfRF9Dn0YfRZ9E30ffRJ9D30Mf1x/YX9ef2B/XX9bf5Z/kn/Df8J/wIAWgD6AOYD6gPKA+YD1gQGA+4EAggGCL4IlgzODLYNEgxmDUYMlg1aDP4NBgyaDHIMig0KDToMbgyqDCIM8g02DFoMkgyCDN4MvgymDR4NFg0yDU4MegyyDS4Mng0iGU4ZShqKGqIaWho2GkYaehoeGl4aGhouGmoaFhqWGmYahhqeGlYaYho6GnYaQhpSIQ4hEiG2IdYh2iHKIgIhxiH+Ib4iDiH6IdIh8ihKMR4xXjHuMpIyjjXaNeI21jbeNto7RjtOP/o/1kAKP/4/7kASP/I/2kNaQ4JDZkNqQ45DfkOWQ2JDbkNeQ3JDkkVCRTpFPkdWR4pHallyWX5a8mOOa35svTn9QcFBqUGFQXlBgUFNQS1BdUHJQSFBNUEFQW1BKUGJQFVBFUF9QaVBrUGNQZFBGUEBQblBzUFdQUVHQUmtSbVJsUm5S1lLTUy1TnFV1VXZVPFVNVVBVNFUqVVFVYlU2VTVVMFVSVUVVDFUyVWVVTlU5VUhVLVU7VUBVS1cKVwdX+1gUV+JX9lfcV/RYAFftV/1YCFf4WAtX81fPWAdX7lfjV/JX5VfsV+FYDlf8WBBX51gBWAxX8VfpV/BYDVgEWVxaYFpYWlVaZ1peWjhaNVptWlBaX1plWmxaU1pkWldaQ1pdWlJaRFpbWkhajlo+Wk1aOVpMWnBaaVpHWlFaVlpCWlxbcltuW8FbwFxZXR5dC10dXRpdIF0MXShdDV0mXSVdD10wXRJdI10fXS5ePl40XrFetF65XrJes182Xzhfm1+WX59gimCQYIZgvmCwYLpg02DUYM9g5GDZYN1gyGCxYNtgt2DKYL9gw2DNYMBjMmNlY4pjgmN9Y71jnmOtY51jl2OrY45jb2OHY5BjbmOvY3VjnGNtY65jfGOkYztjn2N4Y4VjgWORY41jcGVTZc1mZWZhZltmWWZcZmJnGGh5aIdokGicaG1obmiuaKtpVmhvaKNorGipaHVodGiyaI9od2iSaHxoa2hyaKpogGhxaH5om2iWaItooGiJaKRoeGh7aJFojGiKaH1rNmszazdrOGuRa49rjWuOa4xsKm3AbatttG2zbnRtrG3pbeJtt232bdRuAG3IbeBt323Wbb5t5W3cbd1t2230bcptvW3tbfBtum3VbcJtz23JbdBt8m3Tbf1t123NbeNtu3D6cQ1w93EXcPRxDHDwcQRw83EQcPxw/3EGcRNxAHD4cPZxC3ECcQ5yfnJ7cnxyf3MdcxdzB3MRcxhzCnMIcv9zD3Mec4hz9nP4c/V0BHQBc/10B3QAc/pz/HP/dAx0C3P0dAh1ZHVjdc510nXPdct1zHXRddB2j3aJdtN3OXcvdy13MXcydzR3M3c9dyV3O3c1eEh4UnhJeE14SnhMeCZ4RXhQeWR5Z3lpeWp5Y3lreWF5u3n6efh59nn3eo96lHqQezV7R3s0eyV7MHsieyR7M3sYeyp7HXsxeyt7LXsvezJ7OHsaeyN8lHyYfJZ8o301fT19OH02fTp9RX0sfSl9QX1HfT59P31KfTt9KH9jf5V/nH+df5t/yn/Lf81/0H/Rf8d/z3/JgB+AHoAbgEeAQ4BIgRiBJYEZgRuBLYEfgSyBHoEhgRWBJ4EdgSKCEYI4gjOCOoI0gjKCdIOQg6ODqIONg3qDc4Okg3SDj4OBg5WDmYN1g5SDqYN9g4ODjIOdg5uDqoOLg36DpYOvg4iDl4Owg3+DpoOHg66DdoOahlmGVoa/hreGwobBhsWGuoawhsiGuYazhriGzIa0hruGvIbDhr2GvohSiImIlYioiKKIqoiaiJGIoYifiJiIp4iZiJuIl4ikiKyIjIiTiI6JgonWidmJ1YowiieKLIoejDmMO4xcjF2MfYyljX2Ne415jbyNwo25jb+NwY7Yjt6O3Y7cjteO4I7hkCSQC5ARkByQDJAhkO+Q6pDwkPSQ8pDzkNSQ65DskOmRVpFYkVqRU5FVkeyR9JHxkfOR+JHkkfmR6pHrkfeR6JHulXqVhpWIlnyWbZZrlnGWb5a/l2qYBJjlmZdQm1CVUJRQnlCLUKNQg1CMUI5QnVBoUJxQklCCUIdRX1HUUxJTEVOkU6dVkVWoVaVVrVV3VkVVolWTVYhVj1W1VYFVo1WSVaRVfVWMVaZVf1WVVaFVjlcMWClYN1gZWB5YJ1gjWChX9VhIWCVYHFgbWDNYP1g2WC5YOVg4WC1YLFg7WWFar1qUWp9aelqiWp5aeFqmWnxapVqsWpVarlo3WoRailqXWoNai1qpWntafVqMWpxaj1qTWp1b6lvNW8tb1FvRW8pbzlwMXDBdN11DXWtdQV1LXT9dNV1RXU5dVV0zXTpdUl09XTFdWV1CXTldSV04XTxdMl02XUBdRV5EXkFfWF+mX6Vfq2DJYLlgzGDiYM5gxGEUYPJhCmEWYQVg9WETYPhg/GD+YMFhA2EYYR1hEGD/YQRhC2JKY5RjsWOwY85j5WPoY+9jw2SdY/NjymPgY/Zj1WPyY/VkYWPfY75j3WPcY8Rj2GPTY8Jjx2PMY8tjyGPwY9dj2WUyZWdlamVkZVxlaGVlZYxlnWWeZa5l0GXSZnxmbGZ7ZoBmcWZ5ZmpmcmcBaQxo02kEaNxpKmjsaOpo8WkPaNZo92jraORo9mkTaRBo82jhaQdozGkIaXBotGkRaO9oxmkUaPho0Gj9aPxo6GkLaQppF2jOaMho3WjeaOZo9GjRaQZo1GjpaRVpJWjHazlrO2s/azxrlGuXa5lrlWu9a/Br8mvzbDBt/G5GbkduH25JbohuPG49bkVuYm4rbj9uQW5dbnNuHG4zbktuQG5RbjtuA24ubl5uaG5cbmFuMW4obmBucW5rbjluIm4wblNuZW4nbnhuZG53blVueW5SbmZuNW42blpxIHEecS9w+3EucTFxI3ElcSJxMnEfcShxOnEbcktyWnKIcolyhnKFcotzEnMLczBzInMxczNzJ3Mycy1zJnMjczVzDHQudCx0MHQrdBZ0GnQhdC10MXQkdCN0HXQpdCB0MnT7dS91b3Vsded12nXhdeZ13XXfdeR113aVdpJ22ndGd0d3RHdNd0V3SndOd0t3THfed+x4YHhkeGV4XHhteHF4anhueHB4aXhoeF54Ynl0eXN5cnlwegJ6CnoDegx6BHqZeuZ65HtKezt7RHtIe0x7TntAe1h7RXyifJ58qHyhfVh9b31jfVN9Vn1nfWp9T31tfVx9a31SfVR9aX1RfV99Tn8+fz9/ZX9mf6J/oH+hf9eAUYBPgFCA/oDUgUOBSoFSgU+BR4E9gU2BOoHmge6B94H4gfmCBII8gj2CP4J1gzuDz4P5hCODwIPohBKD54Pkg/yD9oQQg8aDyIPrg+ODv4QBg92D5YPYg/+D4YPLg86D1oP1g8mECYQPg96EEYQGg8KD84PVg/qDx4PRg+qEE4PDg+yD7oPEg/uD14PihBuD24P+htiG4obmhtOG44bahuqG3YbrhtyG7IbphteG6IbRiEiIVohViLqI14i5iLiIwIi+iLaIvIi3iL2IsokBiMmJlYmYiZeJ3YnaiduKTopNijmKWYpAileKWIpEikWKUopIilGKSopMik+MX4yBjICMuoy+jLCMuYy1jYSNgI2JjdiN043NjceN1o3cjc+N1Y3ZjciN143Fju+O9476jvmO5o7ujuWO9Y7njuiO9o7rjvGO7I70jumQLZA0kC+RBpEskQSQ/5D8kQiQ+ZD7kQGRAJEHkQWRA5FhkWSRX5FikWCSAZIKkiWSA5IakiaSD5IMkgCSEpH/kf2SBpIEkieSApIckiSSGZIXkgWSFpV7lY2VjJWQloeWfpaIlomWg5aAlsKWyJbDlvGW8Jdsl3CXbpgHmKmY65zmnvlOg06ETrZQvVC/UMZQrlDEUMpQtFDIUMJQsFDBULpQsVDLUMlQtlC4UddSelJ4UntSfFXDVdtVzFXQVctVylXdVcBV1FXEVelVv1XSVY1Vz1XVVeJV1lXIVfJVzVXZVcJXFFhTWGhYZFhPWE1YSVhvWFVYTlhdWFlYZVhbWD1YY1hxWPxax1rEWstaulq4WrFatVqwWr9ayFq7WsZat1rAWspatFq2Ws1auVqQW9Zb2FvZXB9cM11xXWNdSl1lXXJdbF1eXWhdZ11iXfBeT15OXkpeTV5LXsVezF7GXstex19AX69frWD3YUlhSmErYUVhNmEyYS5hRmEvYU9hKWFAYiCRaGIjYiViJGPFY/Fj62QQZBJkCWQgZCRkM2RDZB9kFWQYZDlkN2QiZCNkDGQmZDBkKGRBZDVkL2QKZBpkQGQlZCdkC2PnZBtkLmQhZA5lb2WSZdNmhmaMZpVmkGaLZopmmWaUZnhnIGlmaV9pOGlOaWJpcWk/aUVpamk5aUJpV2lZaXppSGlJaTVpbGkzaT1pZWjwaXhpNGlpaUBpb2lEaXZpWGlBaXRpTGk7aUtpN2lcaU9pUWkyaVJpL2l7aTxrRmtFa0NrQmtIa0Frm/oNa/tr/Gv5a/dr+G6bbtZuyG6PbsBun26TbpRuoG6xbrluxm7Sbr1uwW6ebslut26wbs1upm7PbrJuvm7Dbtxu2G6ZbpJujm6NbqRuoW6/brNu0G7Kbpdurm6jcUdxVHFScWNxYHFBcV1xYnFycXhxanFhcUJxWHFDcUtxcHFfcVBxU3FEcU1xWnJPco1yjHKRcpByjnM8c0JzO3M6c0BzSnNJdER0SnRLdFJ0UXRXdEB0T3RQdE50QnRGdE10VHThdP90/nT9dR11eXV3aYN173YPdgN193X+dfx1+XX4dhB1+3X2de119XX9dpl2tXbdd1V3X3dgd1J3Vndad2l3Z3dUd1l3bXfgeId4mniUeI94hHiVeIV4hniheIN4eXiZeIB4lnh7eXx5gnl9eXl6EXoYehl6EnoXehV6InoTeht6EHqjeqJ6nnrre2Z7ZHtte3R7aXtye2V7c3txe3B7YXt4e3Z7Y3yyfLR8r32IfYZ9gH2NfX99hX16fY59e32DfXx9jH2UfYR9fX2Sf21/a39nf2h/bH+mf6V/p3/bf9yAIYFkgWCBd4FcgWmBW4FigXJnIYFegXaBZ4FvgUSBYYIdgkmCRIJAgkKCRYTxhD+EVoR2hHmEj4SNhGWEUYRAhIaEZ4QwhE2EfYRahFmEdIRzhF2FB4RehDeEOoQ0hHqEQ4R4hDKERYQpg9mES4QvhEKELYRfhHCEOYROhEyEUoRvhMWEjoQ7hEeENoQzhGiEfoREhCuEYIRUhG6EUIcLhwSG94cMhvqG1ob1h02G+IcOhwmHAYb2hw2HBYjWiMuIzYjOiN6I24jaiMyI0ImFiZuJ34nlieSJ4YngieKJ3InminaKhop/imGKP4p3ioKKhIp1ioOKgYp0inqMPIxLjEqMZYxkjGaMhoyEjIWMzI1ojWmNkY2MjY6Nj42NjZONlI2QjZKN8I3gjeyN8Y3ujdCN6Y3jjeKN543yjeuN9I8Gjv+PAY8AjwWPB48IjwKPC5BSkD+QRJBJkD2REJENkQ+REZEWkRSRC5EOkW6Rb5JIklKSMJI6kmaSM5Jlkl6Sg5IukkqSRpJtkmyST5JgkmeSb5I2kmGScJIxklSSY5JQknKSTpJTkkySVpIylZ+VnJWelZuWkpaTlpGWl5bOlvqW/Zb4lvWXc5d3l3iXcpgPmA2YDpismPaY+ZmvmbKZsJm1mq2aq5tbnOqc7ZznnoCe/VDmUNRQ11DoUPNQ21DqUN1Q5FDTUOxQ8FDvUONQ4FHYUoBSgVLpUutTMFOsVidWFVYMVhJV/FYPVhxWAVYTVgJV+lYdVgRV/1X5WIlYfFiQWJhYhliBWH9YdFiLWHpYh1iRWI5YdliCWIhYe1iUWI9Y/llrWtxa7lrlWtVa6lraWu1a61rzWuJa4FrbWuxa3lrdWtla6FrfW3db4FvjXGNdgl2AXX1dhl16XYFdd12KXYldiF1+XXxdjV15XX9eWF5ZXlNe2F7RXtdezl7cXtVe2V7SXtRfRF9DX29ftmEsYShhQWFeYXFhc2FSYVNhcmFsYYBhdGFUYXphW2FlYTthamFhYVZiKWInYitkK2RNZFtkXWR0ZHZkcmRzZH1kdWRmZKZkTmSCZF5kXGRLZFNkYGRQZH9kP2RsZGtkWWRlZHdlc2WgZqFmoGafZwVnBGciabFptmnJaaBpzmmWabBprGm8aZFpmWmOaadpjWmpab5pr2m/acRpvWmkadRpuWnKaZppz2mzaZNpqmmhaZ5p2WmXaZBpwmm1aaVpxmtKa01rS2uea59roGvDa8Rr/m7ObvVu8W8DbyVu+G83bvtvLm8Jb05vGW8abydvGG87bxJu7W8KbzZvc275bu5vLW9AbzBvPG81butvB28Ob0NvBW79bvZvOW8cbvxvOm8fbw1vHm8IbyFxh3GQcYlxgHGFcYJxj3F7cYZxgXGXckRyU3KXcpVyk3NDc01zUXNMdGJ0c3RxdHV0cnRndG51AHUCdQN1fXWQdhZ2CHYMdhV2EXYKdhR2uHeBd3x3hXeCd253gHdvd353g3iyeKp4tHiteKh4fnireJ54pXigeKx4onikeZh5inmLeZZ5lXmUeZN5l3mIeZJ5kHorekp6MHoveih6Jnqoeqt6rHrue4h7nHuKe5F7kHuWe417jHube457hXuYUoR7mXuke4J8u3y/fLx8un2nfbd9wn2jfap9wX3AfcV9nX3OfcR9xn3Lfcx9r325fZZ9vH2ffaZ9rn2pfaF9yX9zf+J/43/lf96AJIBdgFyBiYGGgYOBh4GNgYyBi4IVhJeEpIShhJ+EuoTOhMKErISuhKuEuYS0hMGEzYSqhJqEsYTQhJ2Ep4S7hKKElITHhMyEm4SphK+EqITWhJiEtoTPhKCE14TUhNKE24SwhJGGYYczhyOHKIdrh0CHLocehyGHGYcbh0OHLIdBhz6HRocghzKHKocthzyHEoc6hzGHNYdChyaHJ4c4hySHGocwhxGI94jniPGI8oj6iP6I7oj8iPaI+4jwiOyI64mdiaGJn4meiemJ64noiquKmYqLipKKj4qWjD2MaIxpjNWMz4zXjZaOCY4Cjf+ODY39jgqOA44HjgaOBY3+jgCOBI8QjxGPDo8NkSORHJEgkSKRH5EdkRqRJJEhkRuRepFykXmRc5KlkqSSdpKbknqSoJKUkqqSjZKmkpqSq5J5kpeSf5Kjku6SjpKCkpWSopJ9koiSoZKKkoaSjJKZkqeSfpKHkqmSnZKLki2Wnpahlv+XWJd9l3qXfpeDl4CXgpd7l4SXgZd/l86XzZgWmK2YrpkCmQCZB5mdmZyZw5m5mbuZupnCmb2Zx5qxmuOa55s+mz+bYJthm1+c8ZzynPWep1D/UQNRMFD4UQZRB1D2UP5RC1EMUP1RClKLUoxS8VLvVkhWQlZMVjVWQVZKVklWRlZYVlpWQFYzVj1WLFY+VjhWKlY6VxpYq1idWLFYoFijWK9YrFilWKFY/1r/WvRa/Vr3WvZbA1r4WwJa+VsBWwdbBVsPXGddmV2XXZ9dkl2iXZNdlV2gXZxdoV2aXZ5eaV5dXmBeXH3zXtte3l7hX0lfsmGLYYNheWGxYbBhomGJYZthk2GvYa1hn2GSYaphoWGNYWZhs2ItZG5kcGSWZKBkhWSXZJxkj2SLZIpkjGSjZJ9kaGSxZJhldmV6ZXlle2WyZbNmtWawZqlmsma3Zqpmr2oAagZqF2nlafhqFWnxaeRqIGn/aexp4mobah1p/monafJp7moUafdp52pAaghp5mn7ag1p/GnraglqBGoYaiVqD2n2aiZqB2n0ahZrUWula6NromumbAFsAGv/bAJvQW8mb35vh2/Gb5JvjW+Jb4xvYm9Pb4VvWm+Wb3ZvbG+Cb1Vvcm9Sb1BvV2+Ub5NvXW8Ab2Fva299b2dvkG9Tb4tvaW9/b5VvY293b2pve3Gyca9xm3GwcaBxmnGpcbVxnXGlcZ5xpHGhcapxnHGncbNymHKac1hzUnNec19zYHNdc1tzYXNac1lzYnSHdIl0inSGdIF0fXSFdIh0fHR5dQh1B3V+diV2HnYZdh12HHYjdhp2KHYbdpx2nXaedpt3jXePd4l3iHjNeLt4z3jMeNF4znjUeMh4w3jEeMl5mnmheaB5nHmieZtrdno5erJ6tHqze7d7y3u+e6x7znuve7l7ynu1fMV8yHzMfMt9933bfep9533XfeF+A336feZ99n3xffB97n3ff3Z/rH+wf61/7X/rf+p/7H/mf+iAZIBngaOBn4GegZWBooGZgZeCFoJPglOCUoJQgk6CUYUkhTuFD4UAhSmFDoUJhQ2FH4UKhSeFHIT7hSuE+oUIhQyE9IUqhPKFFYT3hOuE84T8hRKE6oTphRaE/oUohR2FLoUChP2FHoT2hTGFJoTnhOiE8ITvhPmFGIUghTCFC4UZhS+GYodWh2OHZId3h+GHc4dYh1SHW4dSh2GHWodRh16HbYdqh1CHTodfh12Hb4dsh3qHbodch2WHT4d7h3WHYodnh2mIWokFiQyJFIkLiReJGIkZiQaJFokRiQ6JCYmiiaSJo4ntifCJ7IrPisaKuIrTitGK1IrViruK14q+isCKxYrYisOKuoq9itmMPoxNjI+M5YzfjNmM6IzajN2M542gjZyNoY2bjiCOI44ljiSOLo4VjhuOFo4RjhmOJo4njhSOEo4YjhOOHI4XjhqPLI8kjxiPGo8gjyOPFo8XkHOQcJBvkGeQa5EvkSuRKZEqkTKRJpEukYWRhpGKkYGRgpGEkYCS0JLDksSSwJLZkraSz5Lxkt+S2JLpkteS3ZLMku+SwpLoksqSyJLOkuaSzZLVksmS4JLekueS0ZLTkrWS4ZLGkrSVfJWslauVrpWwlqSWopbTlwWXCJcCl1qXipeOl4iX0JfPmB6YHZgmmCmYKJggmBuYJ5iymQiY+pkRmRSZFpkXmRWZ3JnNmc+Z05nUmc6ZyZnWmdiZy5nXmcyas5rsmuua85rymvGbRptDm2ebdJtxm2abdpt1m3CbaJtkm2yc/Jz6nP2c/5z3nQedAJz5nPudCJ0FnQSeg57Tnw+fEFEcURNRF1EaURFR3lM0U+FWcFZgVm5Wc1ZmVmNWbVZyVl5Wd1ccVxtYyFi9WMlYv1i6WMJYvFjGWxdbGVsbWyFbFFsTWxBbFlsoWxpbIFseW+9drF2xXaldp121XbBdrl2qXahdsl2tXa9dtF5nXmheZl5vXule517mXuhe5V9LX7xhnWGoYZZhxWG0YcZhwWHMYbphv2G4YYxk12TWZNBkz2TJZL1kiWTDZNtk82TZZTNlf2V8ZaJmyGa+ZsBmymbLZs9mvWa7ZrpmzGcjajRqZmpJamdqMmpoaj5qXWptanZqW2pRaihqWmo7aj9qQWpqamRqUGpPalRqb2ppamBqPGpealZqVWpNak5qRmtVa1RrVmuna6prq2vIa8dsBGwDbAZvrW/Lb6Nvx2+8b85vyG9eb8RvvW+eb8pvqHAEb6Vvrm+6b6xvqm/Pb79vuG+ib8lvq2/Nb69vsm+wccVxwnG/cbhx1nHAccFxy3HUccpxx3HPcb1x2HG8ccZx2nHbcp1ynnNpc2ZzZ3Nsc2Vza3NqdH90mnSgdJR0knSVdKF1C3WAdi92LXYxdj12M3Y8djV2MnYwdrt25nead513oXecd5t3onejd5V3mXeXeN146XjleOp43njjeNt44XjieO1433jgeaR6RHpIekd6tnq4erV6sXq3e95743vne9171Xvle9p76Hv5e9R76nvie9x763vYe9980nzUfNd80HzRfhJ+IX4Xfgx+H34gfhN+Dn4cfhV+Gn4ifgt+D34Wfg1+FH4lfiR/Q397f3x/en+xf++AKoApgGyBsYGmga6BuYG1gauBsIGsgbSBsoG3gaeB8oJVglaCV4VWhUWFa4VNhVOFYYVYhUCFRoVkhUGFYoVEhVGFR4VjhT6FW4VxhU6FboV1hVWFZ4VghYyFZoVdhVSFZYVshmOGZYZkh5uHj4eXh5OHkoeIh4GHloeYh3mHh4ejh4WHkIeRh52HhIeUh5yHmoeJiR6JJokwiS2JLokniTGJIokpiSOJL4ksiR+J8YrgiuKK8or0ivWK3YsUiuSK34rwisiK3orhiuiK/4rvivuMkYySjJCM9YzujPGM8IzzjWyNbo2ljaeOM44+jjiOQI5FjjaOPI49jkGOMI4/jr2PNo8ujzWPMo85jzePNJB2kHmQe5CGkPqRM5E1kTaRk5GQkZGRjZGPkyeTHpMIkx+TBpMPk3qTOJM8kxuTI5MSkwGTRpMtkw6TDZLLkx2S+pMlkxOS+ZL3kzSTApMkkv+TKZM5kzWTKpMUkwyTC5L+kwmTAJL7kxaVvJXNlb6VuZW6lbaVv5W1lb2WqZbUlwuXEpcQl5mXl5eUl/CX+Jg1mC+YMpkkmR+ZJ5kpmZ6Z7pnsmeWZ5JnwmeOZ6pnpmeeauZq/mrSau5r2mvqa+Zr3mzObgJuFm4ebfJt+m3ubgpuTm5KbkJt6m5WbfZuInSWdF50gnR6dFJ0pnR2dGJ0inRCdGZ0fnoiehp6Hnq6erZ7Vntae+p8Snz1RJlElUSJRJFEgUSlS9FaTVoxWjVaGVoRWg1Z+VoJWf1aBWNZY1FjPWNJbLVslWzJbI1ssWydbJlsvWy5be1vxW/Jdt15sXmpfvl+7YcNhtWG8Yedh4GHlYeRh6GHeZO9k6WTjZOtk5GToZYFlgGW2Zdpm0mqNapZqgWqlaolqn2qbaqFqnmqHapNqjmqVaoNqqGqkapFqf2qmappqhWqMapJrW2utbAlvzG+pb/Rv1G/jb9xv7W/nb+Zv3m/yb91v4m/oceFx8XHocfJx5HHwceJzc3Nuc290l3SydKt0kHSqdK10sXSldK91EHURdRJ1D3WEdkN2SHZJdkd2pHbpd7V3q3eyd7d3tne0d7F3qHfwePN4/XkCePt4/HjyeQV4+Xj+eQR5q3moelx6W3pWelh6VHpaer56wHrBfAV8D3vyfAB7/3v7fA579HwLe/N8AnwJfAN8AXv4e/18Bnvwe/F8EHwKfOh+LX48fkJ+M5hIfjh+Kn5JfkB+R34pfkx+MH47fjZ+RH46f0V/f39+f31/9H/ygCyBu4HEgcyByoHFgceBvIHpgluCWoJchYOFgIWPhaeFlYWghYuFo4V7haSFmoWehXeFfIWJhaGFeoV4hVeFjoWWhYaFjYWZhZ2FgYWihYKFiIWFhXmFdoWYhZCFn4Zoh76Hqoeth8WHsIesh7mHtYe8h66HyYfDh8KHzIe3h6+HxIfKh7SHtoe/h7iHvYfeh7KJNYkziTyJPolBiVKJN4lCia2Jr4muifKJ84seixiLFosRiwWLC4siiw+LEosViweLDYsIiwaLHIsTixqMT4xwjHKMcYxvjJWMlIz5jW+OTo5NjlOOUI5MjkePQ49AkIWQfpE4kZqRopGbkZmRn5GhkZ2RoJOhk4OTr5Nkk1aTR5N8k1iTXJN2k0mTUJNRk2CTbZOPk0yTapN5k1eTVZNSk0+TcZN3k3uTYZNek2OTZ5OAk06TWZXHlcCVyZXDlcWVt5aulrCWrJcglx+XGJcdlxmXmpehl5yXnpedl9WX1JfxmEGYRJhKmEmYRZhDmSWZK5ksmSqZM5kymS+ZLZkxmTCZmJmjmaGaApn6mfSZ95n5mfiZ9pn7mf2Z/pn8mgOavpr+mv2bAZr8m0ibmpuom56bm5umm6GbpZukm4abopugm6+dM51BnWedNp0unS+dMZ04nTCdRZ1CnUOdPp03nUCdPX/1nS2eip6Jno2esJ7Intqe+57/nySfI58in1SfoFExUS1RLlaYVpxWl1aaVp1WmVlwWzxcaVxqXcBebV5uYdhh32HtYe5h8WHqYfBh62HWYelk/2UEZP1k+GUBZQNk/GWUZdtm2mbbZthqxWq5ar1q4WrGarpqtmq3asdqtGqta15ryWwLcAdwDHANcAFwBXAUcA5v/3AAb/twJm/8b/dwCnIBcf9x+XIDcf1zdnS4dMB0tXTBdL50tnS7dMJ1FHUTdlx2ZHZZdlB2U3ZXdlp2pna9dux3wne6eP95DHkTeRR5CXkQeRJ5EXmteax6X3wcfCl8GXwgfB98LXwdfCZ8KHwifCV8MH5cflB+Vn5jflh+Yn5fflF+YH5XflN/tX+zf/d/+IB1gdGB0oHQgl+CXoW0hcaFwIXDhcKFs4W1hb2Fx4XEhb+Fy4XOhciFxYWxhbaF0oYkhbiFt4W+hmmH54fmh+KH24frh+qH5Yffh/OH5IfUh9yH04fth9iH44ekh9eH2YgBh/SH6IfdiVOJS4lPiUyJRolQiVGJSYsqiyeLI4szizCLNYtHiy+LPIs+izGLJYs3iyaLNosuiySLO4s9izqMQox1jJmMmIyXjP6NBI0CjQCOXI5ijmCOV45Wjl6OZY5njluOWo5hjl2OaY5Uj0aPR49Ij0uRKJE6kTuRPpGokaWRp5GvkaqTtZOMk5KTt5Obk52TiZOnk46TqpOek6aTlZOIk5mTn5ONk7GTkZOyk6STqJO0k6OTpZXSldOV0ZazlteW2l3Clt+W2JbdlyOXIpcll6yXrpeol6uXpJeql6KXpZfXl9mX1pfYl/qYUJhRmFKYuJlBmTyZOpoPmguaCZoNmgSaEZoKmgWaB5oGmsCa3JsImwSbBZspmzWbSptMm0ubx5vGm8Obv5vBm7WbuJvTm7abxJu5m72dXJ1TnU+dSp1bnUudWZ1WnUydV51SnVSdX51YnVqejp6Mnt+fAZ8AnxafJZ8rnyqfKZ8on0yfVVE0UTVSllL3U7RWq1atVqZWp1aqVqxY2ljdWNtZEls9Wz5bP13DXnBfv2H7ZQdlEGUNZQllDGUOZYRl3mXdZt5q52rgasxq0WrZastq32rcatBq62rPas1q3mtga7BsDHAZcCdwIHAWcCtwIXAicCNwKXAXcCRwHHAqcgxyCnIHcgJyBXKlcqZypHKjcqF0y3TFdLd0w3UWdmB3yXfKd8R38XkdeRt5IXkceRd5Hnmwemd6aHwzfDx8OXwsfDt87HzqfnZ+dX54fnB+d35vfnp+cn50fmh/S39Kf4N/hn+3f/1//oB4gdeB1YJkgmGCY4XrhfGF7YXZheGF6IXahdeF7IXyhfiF2IXfheOF3IXRhfCF5oXvhd6F4ogAh/qIA4f2h/eICYgMiAuIBof8iAiH/4gKiAKJYolaiVuJV4lhiVyJWIldiVmJiIm3ibaJ9otQi0iLSotAi1OLVotUi0uLVYtRi0KLUotXjEOMd4x2jJqNBo0HjQmNrI2qja2Nq45tjniOc45qjm+Oe47Cj1KPUY9Pj1CPU4+0kUCRP5Gwka2T3pPHk8+TwpPak9CT+ZPsk8yT2ZOpk+aTypPUk+6T45PVk8STzpPAk9KT55V9ldqV25bhlymXK5cslyiXJpezl7eXtpfdl96X35hcmFmYXZhXmL+YvZi7mL6ZSJlHmUOZppmnmhqaFZolmh2aJJobmiKaIJonmiOaHpocmhSawpsLmwqbDpsMmzeb6pvrm+Cb3pvkm+ab4pvwm9Sb15vsm9yb2Zvlm9Wb4ZvanXedgZ2KnYSdiJ1xnYCdeJ2GnYudjJ19nWuddJ11nXCdaZ2FnXOde52CnW+deZ1/nYedaJ6UnpGewJ78ny2fQJ9Bn02fVp9Xn1hTN1ayVrVWs1jjW0Vdxl3HXu5e71/AX8Fh+WUXZRZlFWUTZd9m6GbjZuRq82rwaupq6Gr5avFq7mrvcDxwNXAvcDdwNHAxcEJwOHA/cDpwOXBAcDtwM3BBchNyFHKoc31zfHS6dqt2qna+du13zHfOd893zXfyeSV5I3kneSh5JHkpebJ6bnpsem1693xJfEh8SnxHfEV87n57fn5+gX6Af7p//4B5gduB2YILgmiCaYYihf+GAYX+hhuGAIX2hgSGCYYFhgyF/YgZiBCIEYgXiBOIFoljiWaJuYn3i2CLaotdi2iLY4tli2eLbY2ujoaOiI6Ej1mPVo9Xj1WPWI9akI2RQ5FBkbeRtZGykbOUC5QTk/uUIJQPlBST/pQVlBCUKJQZlA2T9ZQAk/eUB5QOlBaUEpP6lAmT+JQKk/+T/JQMk/aUEZQGld6V4JXfly6XL5e5l7uX/Zf+mGCYYphjmF+YwZjCmVCZTplZmUyZS5lTmjKaNJoxmiyaKpo2mimaLpo4mi2ax5rKmsabEJsSmxGcC5wIm/ecBZwSm/icQJwHnA6cBpwXnBScCZ2fnZmdpJ2dnZKdmJ2QnZudoJ2UnZydqp2XnaGdmp2inaidnp2jnb+dqZ2Wnaadp56Znpuemp7lnuSe557mnzCfLp9bn2CfXp9dn1mfkVE6UTlSmFKXVsNWvVa+W0hbR13LXc9e8WH9ZRtrAmr8awNq+GsAcENwRHBKcEhwSXBFcEZyHXIachlzfnUXdmp30HkteTF5L3xUfFN88n6Kfod+iH6LfoZ+jX9Nf7uAMIHdhhiGKoYmhh+GI4YchhmGJ4YuhiGGIIYphh6GJYgpiB2IG4ggiCSIHIgriEqJbYlpiW6Ja4n6i3mLeItFi3qLe40QjRSNr46OjoyPXo9bj12RRpFEkUWRuZQ/lDuUNpQplD2UPJQwlDmUKpQ3lCyUQJQxleWV5JXjlzWXOpe/l+GYZJjJmMaYwJlYmVaaOZo9mkaaRJpCmkGaOpo/ms2bFZsXmxibFps6m1KcK5wdnBycLJwjnCicKZwknCGdt522nbydwZ3Hncqdz52+ncWdw527nbWdzp25nbqdrJ3InbGdrZ3MnbOdzZ2ynnqenJ7rnu6e7Z8bnxifGp8xn06fZZ9kn5JOuVbGVsVWy1lxW0tbTF3VXdFe8mUhZSBlJmUiawtrCGsJbA1wVXBWcFdwUnIech9yqXN/dNh01XTZdNd2bXateTV5tHpwenF8V3xcfFl8W3xafPR88X6Rf09/h4HegmuGNIY1hjOGLIYyhjaILIgoiCaIKogliXGJv4m+ifuLfouEi4KLhouFi3+NFY6VjpSOmo6SjpCOlo6Xj2CPYpFHlEyUUJRKlEuUT5RHlEWUSJRJlEaXP5fjmGqYaZjLmVSZW5pOmlOaVJpMmk+aSJpKmkmaUppQmtCbGZsrmzubVptVnEacSJw/nEScOZwznEGcPJw3nDScMpw9nDad253Snd6d2p3LndCd3J3Rnd+d6Z3Zndid1p31ndWd3Z62nvCfNZ8znzKfQp9rn5WfolE9UplY6FjnWXJbTV3YiC9fT2IBYgNiBGUpZSVllmbraxFrEmsPa8pwW3BaciJzgnOBc4N2cHfUfGd8Zn6VgmyGOoZAhjmGPIYxhjuGPogwiDKILogziXaJdIlzif6LjIuOi4uLiIxFjRmOmI9kj2ORvJRilFWUXZRXlF6XxJfFmACaVppZmx6bH5sgnFKcWJxQnEqcTZxLnFWcWZxMnE6d+533ne+d453rnfid5J32neGd7p3mnfKd8J3ineyd9J3zneid7Z7CntCe8p7znwafHJ84nzefNp9Dn0+fcZ9wn26fb1bTVs1bTlxtZS1m7WbuaxNwX3BhcF1wYHIjdNt05XfVeTh5t3m2fGp+l3+Jgm2GQ4g4iDeINYhLi5SLlY6ejp+OoI6dkb6RvZHClGuUaJRpluWXRpdDl0eXx5flml6a1ZtZnGOcZ5xmnGKcXpxgngKd/p4HngOeBp4FngCeAZ4Jnf+d/Z4EnqCfHp9Gn3SfdZ92VtRlLmW4axhrGWsXaxpwYnImcqp32HfZeTl8aXxrfPZ+mn6Yfpt+mYHggeGGRoZHhkiJeYl6iXyJe4n/i5iLmY6ljqSOo5RulG2Ub5RxlHOXSZhymV+caJxunG2eC54NnhCeD54SnhGeoZ71nwmfR594n3ufep95Vx5wZnxviDyNso6mkcOUdJR4lHaUdZpgnHScc5xxnHWeFJ4TnvafCp+kcGhwZXz3hmqIPog9iD+LnoycjqmOyZdLmHOYdJjMmWGZq5pkmmaaZ5sknhWeF59IYgdrHnInhkyOqJSClICUgZppmmibLp4ZcimGS4uflIOceZ63dnWaa5x6nh1waXBqnqSffp9Jn5g="

    /// 见 `big5JdkTableBase64`。段索引 `(hi, loStart, offset, count)`：
    /// 命中时取 `big5JdkTable[offset + (lo - loStart)]`。
    private static let big5JdkTableSegments: [(hi: UInt8, loStart: UInt8, offset: Int, count: Int)] = [
        (0xA1, 0x40, 0, 63),
        (0xA1, 0xA1, 63, 34),
        (0xA1, 0xC4, 97, 1),
        (0xA1, 0xC6, 98, 57),
        (0xA2, 0x40, 155, 63),
        (0xA2, 0xA1, 218, 94),
        (0xA3, 0x40, 312, 63),
        (0xA3, 0xA1, 375, 31),
        (0xA4, 0x40, 406, 63),
        (0xA4, 0xA1, 469, 94),
        (0xA5, 0x40, 563, 63),
        (0xA5, 0xA1, 626, 94),
        (0xA6, 0x40, 720, 63),
        (0xA6, 0xA1, 783, 94),
        (0xA7, 0x40, 877, 63),
        (0xA7, 0xA1, 940, 94),
        (0xA8, 0x40, 1034, 63),
        (0xA8, 0xA1, 1097, 94),
        (0xA9, 0x40, 1191, 63),
        (0xA9, 0xA1, 1254, 94),
        (0xAA, 0x40, 1348, 63),
        (0xAA, 0xA1, 1411, 94),
        (0xAB, 0x40, 1505, 63),
        (0xAB, 0xA1, 1568, 94),
        (0xAC, 0x40, 1662, 63),
        (0xAC, 0xA1, 1725, 94),
        (0xAD, 0x40, 1819, 63),
        (0xAD, 0xA1, 1882, 94),
        (0xAE, 0x40, 1976, 63),
        (0xAE, 0xA1, 2039, 94),
        (0xAF, 0x40, 2133, 63),
        (0xAF, 0xA1, 2196, 94),
        (0xB0, 0x40, 2290, 63),
        (0xB0, 0xA1, 2353, 94),
        (0xB1, 0x40, 2447, 63),
        (0xB1, 0xA1, 2510, 94),
        (0xB2, 0x40, 2604, 63),
        (0xB2, 0xA1, 2667, 94),
        (0xB3, 0x40, 2761, 63),
        (0xB3, 0xA1, 2824, 94),
        (0xB4, 0x40, 2918, 63),
        (0xB4, 0xA1, 2981, 94),
        (0xB5, 0x40, 3075, 63),
        (0xB5, 0xA1, 3138, 94),
        (0xB6, 0x40, 3232, 63),
        (0xB6, 0xA1, 3295, 94),
        (0xB7, 0x40, 3389, 63),
        (0xB7, 0xA1, 3452, 94),
        (0xB8, 0x40, 3546, 63),
        (0xB8, 0xA1, 3609, 94),
        (0xB9, 0x40, 3703, 63),
        (0xB9, 0xA1, 3766, 94),
        (0xBA, 0x40, 3860, 63),
        (0xBA, 0xA1, 3923, 94),
        (0xBB, 0x40, 4017, 63),
        (0xBB, 0xA1, 4080, 94),
        (0xBC, 0x40, 4174, 63),
        (0xBC, 0xA1, 4237, 94),
        (0xBD, 0x40, 4331, 63),
        (0xBD, 0xA1, 4394, 94),
        (0xBE, 0x40, 4488, 63),
        (0xBE, 0xA1, 4551, 94),
        (0xBF, 0x40, 4645, 63),
        (0xBF, 0xA1, 4708, 94),
        (0xC0, 0x40, 4802, 63),
        (0xC0, 0xA1, 4865, 94),
        (0xC1, 0x40, 4959, 63),
        (0xC1, 0xA1, 5022, 94),
        (0xC2, 0x40, 5116, 63),
        (0xC2, 0xA1, 5179, 94),
        (0xC3, 0x40, 5273, 63),
        (0xC3, 0xA1, 5336, 94),
        (0xC4, 0x40, 5430, 63),
        (0xC4, 0xA1, 5493, 94),
        (0xC5, 0x40, 5587, 63),
        (0xC5, 0xA1, 5650, 94),
        (0xC6, 0x40, 5744, 63),
        (0xC6, 0xA1, 5807, 94),
        (0xC7, 0x40, 5901, 63),
        (0xC7, 0xA1, 5964, 92),
        (0xC9, 0x40, 6056, 63),
        (0xC9, 0xA1, 6119, 94),
        (0xCA, 0x40, 6213, 63),
        (0xCA, 0xA1, 6276, 94),
        (0xCB, 0x40, 6370, 63),
        (0xCB, 0xA1, 6433, 94),
        (0xCC, 0x40, 6527, 63),
        (0xCC, 0xA1, 6590, 94),
        (0xCD, 0x40, 6684, 63),
        (0xCD, 0xA1, 6747, 94),
        (0xCE, 0x40, 6841, 63),
        (0xCE, 0xA1, 6904, 94),
        (0xCF, 0x40, 6998, 63),
        (0xCF, 0xA1, 7061, 94),
        (0xD0, 0x40, 7155, 63),
        (0xD0, 0xA1, 7218, 94),
        (0xD1, 0x40, 7312, 63),
        (0xD1, 0xA1, 7375, 94),
        (0xD2, 0x40, 7469, 63),
        (0xD2, 0xA1, 7532, 94),
        (0xD3, 0x40, 7626, 63),
        (0xD3, 0xA1, 7689, 94),
        (0xD4, 0x40, 7783, 63),
        (0xD4, 0xA1, 7846, 94),
        (0xD5, 0x40, 7940, 63),
        (0xD5, 0xA1, 8003, 94),
        (0xD6, 0x40, 8097, 63),
        (0xD6, 0xA1, 8160, 94),
        (0xD7, 0x40, 8254, 63),
        (0xD7, 0xA1, 8317, 94),
        (0xD8, 0x40, 8411, 63),
        (0xD8, 0xA1, 8474, 94),
        (0xD9, 0x40, 8568, 63),
        (0xD9, 0xA1, 8631, 94),
        (0xDA, 0x40, 8725, 63),
        (0xDA, 0xA1, 8788, 94),
        (0xDB, 0x40, 8882, 63),
        (0xDB, 0xA1, 8945, 94),
        (0xDC, 0x40, 9039, 63),
        (0xDC, 0xA1, 9102, 94),
        (0xDD, 0x40, 9196, 63),
        (0xDD, 0xA1, 9259, 94),
        (0xDE, 0x40, 9353, 63),
        (0xDE, 0xA1, 9416, 94),
        (0xDF, 0x40, 9510, 63),
        (0xDF, 0xA1, 9573, 94),
        (0xE0, 0x40, 9667, 63),
        (0xE0, 0xA1, 9730, 94),
        (0xE1, 0x40, 9824, 63),
        (0xE1, 0xA1, 9887, 94),
        (0xE2, 0x40, 9981, 63),
        (0xE2, 0xA1, 10044, 94),
        (0xE3, 0x40, 10138, 63),
        (0xE3, 0xA1, 10201, 94),
        (0xE4, 0x40, 10295, 63),
        (0xE4, 0xA1, 10358, 94),
        (0xE5, 0x40, 10452, 63),
        (0xE5, 0xA1, 10515, 94),
        (0xE6, 0x40, 10609, 63),
        (0xE6, 0xA1, 10672, 94),
        (0xE7, 0x40, 10766, 63),
        (0xE7, 0xA1, 10829, 94),
        (0xE8, 0x40, 10923, 63),
        (0xE8, 0xA1, 10986, 94),
        (0xE9, 0x40, 11080, 63),
        (0xE9, 0xA1, 11143, 94),
        (0xEA, 0x40, 11237, 63),
        (0xEA, 0xA1, 11300, 94),
        (0xEB, 0x40, 11394, 63),
        (0xEB, 0xA1, 11457, 94),
        (0xEC, 0x40, 11551, 63),
        (0xEC, 0xA1, 11614, 94),
        (0xED, 0x40, 11708, 63),
        (0xED, 0xA1, 11771, 94),
        (0xEE, 0x40, 11865, 63),
        (0xEE, 0xA1, 11928, 94),
        (0xEF, 0x40, 12022, 63),
        (0xEF, 0xA1, 12085, 94),
        (0xF0, 0x40, 12179, 63),
        (0xF0, 0xA1, 12242, 94),
        (0xF1, 0x40, 12336, 63),
        (0xF1, 0xA1, 12399, 94),
        (0xF2, 0x40, 12493, 63),
        (0xF2, 0xA1, 12556, 94),
        (0xF3, 0x40, 12650, 63),
        (0xF3, 0xA1, 12713, 94),
        (0xF4, 0x40, 12807, 63),
        (0xF4, 0xA1, 12870, 94),
        (0xF5, 0x40, 12964, 63),
        (0xF5, 0xA1, 13027, 94),
        (0xF6, 0x40, 13121, 63),
        (0xF6, 0xA1, 13184, 94),
        (0xF7, 0x40, 13278, 63),
        (0xF7, 0xA1, 13341, 94),
        (0xF8, 0x40, 13435, 63),
        (0xF8, 0xA1, 13498, 94),
        (0xF9, 0x40, 13592, 63),
        (0xF9, 0xA1, 13655, 53),
    ]

    /// 惰性解码 `big5JdkTableBase64` 得到的码表（约 13708 项）。
    private static let big5JdkTable: [UInt32] = {
        guard let data = Data(base64Encoded: big5JdkTableBase64) else { return [] }
        let bytes = [UInt8](data)
        var out = [UInt32]()
        out.reserveCapacity(bytes.count / 2)
        var i = 0
        while i + 1 < bytes.count {
            out.append(UInt32(bytes[i]) << 8 | UInt32(bytes[i + 1]))
            i += 2
        }
        return out
    }()

    /// 查 JDK 严格 Big5 表。返回 `nil` 表示该位点不可映射。
    private static func lookupJdkBig5(_ hi: UInt8, _ lo: UInt8) -> UInt32? {
        // ⚠️ 同一个 lead 可能**有多段**（如 `E7` 分 `40–7E` 与 `A1–FE` 两段），
        // 因此段不匹配时必须 `continue` 试下一段，不能直接 `return nil`。
        for seg in big5JdkTableSegments where seg.hi == hi {
            guard lo >= seg.loStart else { continue }
            let off = Int(lo - seg.loStart)
            guard off < seg.count else { continue }
            return big5JdkTable[seg.offset + off]
        }
        return nil
    }

    /// 「逐字节」画像：单字节上界覆盖全部取值，因而 `isSingle` 恒为 `true`，
    /// `incrementalLossyDecode` 会逐字节推进。用于单字节系（ISO-8859-x / ASCII / KOI8-R）
    /// 与 UTF-8 —— 它们的 JDK 语义就是「每字节独立」。
    ///
    /// ⚠️ **UTF-16 / UTF-32 不能用它**（见 `utf16Profile`）：它们的码元是 2 / 4 字节宽，
    /// 逐字节推进会拆散代理对，导致标量个数与 Java 不符。
    static let byteWiseProfile = MBCSProfile(
        singleByteMax: 0xFF, singleByteExtra: nil,
        leadRanges: [], trailRanges: [], u2TrailRanges: [], m2TrailRanges: [],
        malformedExceptions: [:],
        unmappableExceptions: [:],
        threeByteLead: [], fourByteDigitRange: nil, useJdkBig5Table: false,
        unitWidth: 0)

    /// UTF-16 画像：**按 2 字节码元**推进。
    ///
    /// 语义对齐 JDK `new String(bytes, "UTF-16LE"/"UTF-16BE"/"UTF-16")`：
    ///   - 每 2 字节构成 1 个码元；
    ///   - 高代理（`D800-DBFF`）+ 紧随的低代理（`DC00-DFFF`）→ 合并成 1 个补充平面标量；
    ///   - 孤立代理 → 1 个 `U+FFFD`（**该侧仍是 1 个码元、2 字节**）；
    ///   - 末尾不足 2 字节 → 1 个 `U+FFFD`。
    ///
    /// 与 `byteWiseProfile` 的唯一差别是 `unitWidth: 2`，但影响实质：CI run `37219082032`
    /// 的 `ext-cn-3-utf-16be`（`decodedDefault` / `decodedContentTypeNoCharset`）
    /// 因逐字节推进把代理对拆开，Java 41 个标量在 Swift 侧变成 42 个。
    static let utf16Profile = MBCSProfile(
        singleByteMax: 0xFF, singleByteExtra: nil,
        leadRanges: [], trailRanges: [], u2TrailRanges: [], m2TrailRanges: [],
        malformedExceptions: [:],
        unmappableExceptions: [:],
        threeByteLead: [], fourByteDigitRange: nil, useJdkBig5Table: false,
        unitWidth: 2)

    /// JIS X 0208 码表（ISO-2022-JP 的 `ESC $ B` / `ESC $ @` 双字节区）。
    ///
    /// 由真实 JVM 枚举 `ChaserDecoder` 得到：对 `ESC $ B` + `hi(21-7E)` + `lo(21-7E)`
    /// 共 8836 个位点逐个解码，取成功映射的 6879 条，压缩成 86 个连续段。
    /// 段索引 `(hi, loStart, offset, count)`：命中时取 `jis0208Map[offset + (lo - loStart)]`。
    /// 未命中（含 JIS 未定义位点）按 JDK 语义输出 `U+FFFD`。
    private static let jis0208Segments: [(hi: UInt8, loStart: UInt8, offset: Int, count: Int)] = [
        (0x21, 0x21, 0, 94),
        (0x22, 0x21, 94, 14),
        (0x22, 0x3A, 108, 8),
        (0x22, 0x4A, 116, 7),
        (0x22, 0x5C, 123, 15),
        (0x22, 0x72, 138, 8),
        (0x22, 0x7E, 146, 1),
        (0x23, 0x30, 147, 10),
        (0x23, 0x41, 157, 26),
        (0x23, 0x61, 183, 26),
        (0x24, 0x21, 209, 83),
        (0x25, 0x21, 292, 86),
        (0x26, 0x21, 378, 24),
        (0x26, 0x41, 402, 24),
        (0x27, 0x21, 426, 33),
        (0x27, 0x51, 459, 33),
        (0x28, 0x21, 492, 32),
        (0x30, 0x21, 524, 94),
        (0x31, 0x21, 618, 94),
        (0x32, 0x21, 712, 94),
        (0x33, 0x21, 806, 94),
        (0x34, 0x21, 900, 94),
        (0x35, 0x21, 994, 94),
        (0x36, 0x21, 1088, 94),
        (0x37, 0x21, 1182, 94),
        (0x38, 0x21, 1276, 94),
        (0x39, 0x21, 1370, 94),
        (0x3A, 0x21, 1464, 94),
        (0x3B, 0x21, 1558, 94),
        (0x3C, 0x21, 1652, 94),
        (0x3D, 0x21, 1746, 94),
        (0x3E, 0x21, 1840, 94),
        (0x3F, 0x21, 1934, 94),
        (0x40, 0x21, 2028, 94),
        (0x41, 0x21, 2122, 94),
        (0x42, 0x21, 2216, 94),
        (0x43, 0x21, 2310, 94),
        (0x44, 0x21, 2404, 94),
        (0x45, 0x21, 2498, 94),
        (0x46, 0x21, 2592, 94),
        (0x47, 0x21, 2686, 94),
        (0x48, 0x21, 2780, 94),
        (0x49, 0x21, 2874, 94),
        (0x4A, 0x21, 2968, 94),
        (0x4B, 0x21, 3062, 94),
        (0x4C, 0x21, 3156, 94),
        (0x4D, 0x21, 3250, 94),
        (0x4E, 0x21, 3344, 94),
        (0x4F, 0x21, 3438, 51),
        (0x50, 0x21, 3489, 94),
        (0x51, 0x21, 3583, 94),
        (0x52, 0x21, 3677, 94),
        (0x53, 0x21, 3771, 94),
        (0x54, 0x21, 3865, 94),
        (0x55, 0x21, 3959, 94),
        (0x56, 0x21, 4053, 94),
        (0x57, 0x21, 4147, 94),
        (0x58, 0x21, 4241, 94),
        (0x59, 0x21, 4335, 94),
        (0x5A, 0x21, 4429, 94),
        (0x5B, 0x21, 4523, 94),
        (0x5C, 0x21, 4617, 94),
        (0x5D, 0x21, 4711, 94),
        (0x5E, 0x21, 4805, 94),
        (0x5F, 0x21, 4899, 94),
        (0x60, 0x21, 4993, 94),
        (0x61, 0x21, 5087, 94),
        (0x62, 0x21, 5181, 94),
        (0x63, 0x21, 5275, 94),
        (0x64, 0x21, 5369, 94),
        (0x65, 0x21, 5463, 94),
        (0x66, 0x21, 5557, 94),
        (0x67, 0x21, 5651, 94),
        (0x68, 0x21, 5745, 94),
        (0x69, 0x21, 5839, 94),
        (0x6A, 0x21, 5933, 94),
        (0x6B, 0x21, 6027, 94),
        (0x6C, 0x21, 6121, 94),
        (0x6D, 0x21, 6215, 94),
        (0x6E, 0x21, 6309, 94),
        (0x6F, 0x21, 6403, 94),
        (0x70, 0x21, 6497, 94),
        (0x71, 0x21, 6591, 94),
        (0x72, 0x21, 6685, 94),
        (0x73, 0x21, 6779, 94),
        (0x74, 0x21, 6873, 6),
    ]

    /// 见 `jis0208Segments` 的文档。
    private static let jis0208Map: [UInt32] = [
        0x3000, 0x3001, 0x3002, 0xFF0C, 0xFF0E, 0x30FB, 0xFF1A, 0xFF1B, 0xFF1F, 0xFF01, 0x309B,
        0x309C, 0x00B4, 0xFF40, 0x00A8, 0xFF3E, 0xFFE3, 0xFF3F, 0x30FD, 0x30FE, 0x309D, 0x309E,
        0x3003, 0x4EDD, 0x3005, 0x3006, 0x3007, 0x30FC, 0x2014, 0x2010, 0xFF0F, 0xFF3C, 0x301C,
        0x2016, 0xFF5C, 0x2026, 0x2025, 0x2018, 0x2019, 0x201C, 0x201D, 0xFF08, 0xFF09, 0x3014,
        0x3015, 0xFF3B, 0xFF3D, 0xFF5B, 0xFF5D, 0x3008, 0x3009, 0x300A, 0x300B, 0x300C, 0x300D,
        0x300E, 0x300F, 0x3010, 0x3011, 0xFF0B, 0x2212, 0x00B1, 0x00D7, 0x00F7, 0xFF1D, 0x2260,
        0xFF1C, 0xFF1E, 0x2266, 0x2267, 0x221E, 0x2234, 0x2642, 0x2640, 0x00B0, 0x2032, 0x2033,
        0x2103, 0xFFE5, 0xFF04, 0x00A2, 0x00A3, 0xFF05, 0xFF03, 0xFF06, 0xFF0A, 0xFF20, 0x00A7,
        0x2606, 0x2605, 0x25CB, 0x25CF, 0x25CE, 0x25C7, 0x25C6, 0x25A1, 0x25A0, 0x25B3, 0x25B2,
        0x25BD, 0x25BC, 0x203B, 0x3012, 0x2192, 0x2190, 0x2191, 0x2193, 0x3013, 0x2208, 0x220B,
        0x2286, 0x2287, 0x2282, 0x2283, 0x222A, 0x2229, 0x2227, 0x2228, 0x00AC, 0x21D2, 0x21D4,
        0x2200, 0x2203, 0x2220, 0x22A5, 0x2312, 0x2202, 0x2207, 0x2261, 0x2252, 0x226A, 0x226B,
        0x221A, 0x223D, 0x221D, 0x2235, 0x222B, 0x222C, 0x212B, 0x2030, 0x266F, 0x266D, 0x266A,
        0x2020, 0x2021, 0x00B6, 0x25EF, 0xFF10, 0xFF11, 0xFF12, 0xFF13, 0xFF14, 0xFF15, 0xFF16,
        0xFF17, 0xFF18, 0xFF19, 0xFF21, 0xFF22, 0xFF23, 0xFF24, 0xFF25, 0xFF26, 0xFF27, 0xFF28,
        0xFF29, 0xFF2A, 0xFF2B, 0xFF2C, 0xFF2D, 0xFF2E, 0xFF2F, 0xFF30, 0xFF31, 0xFF32, 0xFF33,
        0xFF34, 0xFF35, 0xFF36, 0xFF37, 0xFF38, 0xFF39, 0xFF3A, 0xFF41, 0xFF42, 0xFF43, 0xFF44,
        0xFF45, 0xFF46, 0xFF47, 0xFF48, 0xFF49, 0xFF4A, 0xFF4B, 0xFF4C, 0xFF4D, 0xFF4E, 0xFF4F,
        0xFF50, 0xFF51, 0xFF52, 0xFF53, 0xFF54, 0xFF55, 0xFF56, 0xFF57, 0xFF58, 0xFF59, 0xFF5A,
        0x3041, 0x3042, 0x3043, 0x3044, 0x3045, 0x3046, 0x3047, 0x3048, 0x3049, 0x304A, 0x304B,
        0x304C, 0x304D, 0x304E, 0x304F, 0x3050, 0x3051, 0x3052, 0x3053, 0x3054, 0x3055, 0x3056,
        0x3057, 0x3058, 0x3059, 0x305A, 0x305B, 0x305C, 0x305D, 0x305E, 0x305F, 0x3060, 0x3061,
        0x3062, 0x3063, 0x3064, 0x3065, 0x3066, 0x3067, 0x3068, 0x3069, 0x306A, 0x306B, 0x306C,
        0x306D, 0x306E, 0x306F, 0x3070, 0x3071, 0x3072, 0x3073, 0x3074, 0x3075, 0x3076, 0x3077,
        0x3078, 0x3079, 0x307A, 0x307B, 0x307C, 0x307D, 0x307E, 0x307F, 0x3080, 0x3081, 0x3082,
        0x3083, 0x3084, 0x3085, 0x3086, 0x3087, 0x3088, 0x3089, 0x308A, 0x308B, 0x308C, 0x308D,
        0x308E, 0x308F, 0x3090, 0x3091, 0x3092, 0x3093, 0x30A1, 0x30A2, 0x30A3, 0x30A4, 0x30A5,
        0x30A6, 0x30A7, 0x30A8, 0x30A9, 0x30AA, 0x30AB, 0x30AC, 0x30AD, 0x30AE, 0x30AF, 0x30B0,
        0x30B1, 0x30B2, 0x30B3, 0x30B4, 0x30B5, 0x30B6, 0x30B7, 0x30B8, 0x30B9, 0x30BA, 0x30BB,
        0x30BC, 0x30BD, 0x30BE, 0x30BF, 0x30C0, 0x30C1, 0x30C2, 0x30C3, 0x30C4, 0x30C5, 0x30C6,
        0x30C7, 0x30C8, 0x30C9, 0x30CA, 0x30CB, 0x30CC, 0x30CD, 0x30CE, 0x30CF, 0x30D0, 0x30D1,
        0x30D2, 0x30D3, 0x30D4, 0x30D5, 0x30D6, 0x30D7, 0x30D8, 0x30D9, 0x30DA, 0x30DB, 0x30DC,
        0x30DD, 0x30DE, 0x30DF, 0x30E0, 0x30E1, 0x30E2, 0x30E3, 0x30E4, 0x30E5, 0x30E6, 0x30E7,
        0x30E8, 0x30E9, 0x30EA, 0x30EB, 0x30EC, 0x30ED, 0x30EE, 0x30EF, 0x30F0, 0x30F1, 0x30F2,
        0x30F3, 0x30F4, 0x30F5, 0x30F6, 0x0391, 0x0392, 0x0393, 0x0394, 0x0395, 0x0396, 0x0397,
        0x0398, 0x0399, 0x039A, 0x039B, 0x039C, 0x039D, 0x039E, 0x039F, 0x03A0, 0x03A1, 0x03A3,
        0x03A4, 0x03A5, 0x03A6, 0x03A7, 0x03A8, 0x03A9, 0x03B1, 0x03B2, 0x03B3, 0x03B4, 0x03B5,
        0x03B6, 0x03B7, 0x03B8, 0x03B9, 0x03BA, 0x03BB, 0x03BC, 0x03BD, 0x03BE, 0x03BF, 0x03C0,
        0x03C1, 0x03C3, 0x03C4, 0x03C5, 0x03C6, 0x03C7, 0x03C8, 0x03C9, 0x0410, 0x0411, 0x0412,
        0x0413, 0x0414, 0x0415, 0x0401, 0x0416, 0x0417, 0x0418, 0x0419, 0x041A, 0x041B, 0x041C,
        0x041D, 0x041E, 0x041F, 0x0420, 0x0421, 0x0422, 0x0423, 0x0424, 0x0425, 0x0426, 0x0427,
        0x0428, 0x0429, 0x042A, 0x042B, 0x042C, 0x042D, 0x042E, 0x042F, 0x0430, 0x0431, 0x0432,
        0x0433, 0x0434, 0x0435, 0x0451, 0x0436, 0x0437, 0x0438, 0x0439, 0x043A, 0x043B, 0x043C,
        0x043D, 0x043E, 0x043F, 0x0440, 0x0441, 0x0442, 0x0443, 0x0444, 0x0445, 0x0446, 0x0447,
        0x0448, 0x0449, 0x044A, 0x044B, 0x044C, 0x044D, 0x044E, 0x044F, 0x2500, 0x2502, 0x250C,
        0x2510, 0x2518, 0x2514, 0x251C, 0x252C, 0x2524, 0x2534, 0x253C, 0x2501, 0x2503, 0x250F,
        0x2513, 0x251B, 0x2517, 0x2523, 0x2533, 0x252B, 0x253B, 0x254B, 0x2520, 0x252F, 0x2528,
        0x2537, 0x253F, 0x251D, 0x2530, 0x2525, 0x2538, 0x2542, 0x4E9C, 0x5516, 0x5A03, 0x963F,
        0x54C0, 0x611B, 0x6328, 0x59F6, 0x9022, 0x8475, 0x831C, 0x7A50, 0x60AA, 0x63E1, 0x6E25,
        0x65ED, 0x8466, 0x82A6, 0x9BF5, 0x6893, 0x5727, 0x65A1, 0x6271, 0x5B9B, 0x59D0, 0x867B,
        0x98F4, 0x7D62, 0x7DBE, 0x9B8E, 0x6216, 0x7C9F, 0x88B7, 0x5B89, 0x5EB5, 0x6309, 0x6697,
        0x6848, 0x95C7, 0x978D, 0x674F, 0x4EE5, 0x4F0A, 0x4F4D, 0x4F9D, 0x5049, 0x56F2, 0x5937,
        0x59D4, 0x5A01, 0x5C09, 0x60DF, 0x610F, 0x6170, 0x6613, 0x6905, 0x70BA, 0x754F, 0x7570,
        0x79FB, 0x7DAD, 0x7DEF, 0x80C3, 0x840E, 0x8863, 0x8B02, 0x9055, 0x907A, 0x533B, 0x4E95,
        0x4EA5, 0x57DF, 0x80B2, 0x90C1, 0x78EF, 0x4E00, 0x58F1, 0x6EA2, 0x9038, 0x7A32, 0x8328,
        0x828B, 0x9C2F, 0x5141, 0x5370, 0x54BD, 0x54E1, 0x56E0, 0x59FB, 0x5F15, 0x98F2, 0x6DEB,
        0x80E4, 0x852D, 0x9662, 0x9670, 0x96A0, 0x97FB, 0x540B, 0x53F3, 0x5B87, 0x70CF, 0x7FBD,
        0x8FC2, 0x96E8, 0x536F, 0x9D5C, 0x7ABA, 0x4E11, 0x7893, 0x81FC, 0x6E26, 0x5618, 0x5504,
        0x6B1D, 0x851A, 0x9C3B, 0x59E5, 0x53A9, 0x6D66, 0x74DC, 0x958F, 0x5642, 0x4E91, 0x904B,
        0x96F2, 0x834F, 0x990C, 0x53E1, 0x55B6, 0x5B30, 0x5F71, 0x6620, 0x66F3, 0x6804, 0x6C38,
        0x6CF3, 0x6D29, 0x745B, 0x76C8, 0x7A4E, 0x9834, 0x82F1, 0x885B, 0x8A60, 0x92ED, 0x6DB2,
        0x75AB, 0x76CA, 0x99C5, 0x60A6, 0x8B01, 0x8D8A, 0x95B2, 0x698E, 0x53AD, 0x5186, 0x5712,
        0x5830, 0x5944, 0x5BB4, 0x5EF6, 0x6028, 0x63A9, 0x63F4, 0x6CBF, 0x6F14, 0x708E, 0x7114,
        0x7159, 0x71D5, 0x733F, 0x7E01, 0x8276, 0x82D1, 0x8597, 0x9060, 0x925B, 0x9D1B, 0x5869,
        0x65BC, 0x6C5A, 0x7525, 0x51F9, 0x592E, 0x5965, 0x5F80, 0x5FDC, 0x62BC, 0x65FA, 0x6A2A,
        0x6B27, 0x6BB4, 0x738B, 0x7FC1, 0x8956, 0x9D2C, 0x9D0E, 0x9EC4, 0x5CA1, 0x6C96, 0x837B,
        0x5104, 0x5C4B, 0x61B6, 0x81C6, 0x6876, 0x7261, 0x4E59, 0x4FFA, 0x5378, 0x6069, 0x6E29,
        0x7A4F, 0x97F3, 0x4E0B, 0x5316, 0x4EEE, 0x4F55, 0x4F3D, 0x4FA1, 0x4F73, 0x52A0, 0x53EF,
        0x5609, 0x590F, 0x5AC1, 0x5BB6, 0x5BE1, 0x79D1, 0x6687, 0x679C, 0x67B6, 0x6B4C, 0x6CB3,
        0x706B, 0x73C2, 0x798D, 0x79BE, 0x7A3C, 0x7B87, 0x82B1, 0x82DB, 0x8304, 0x8377, 0x83EF,
        0x83D3, 0x8766, 0x8AB2, 0x5629, 0x8CA8, 0x8FE6, 0x904E, 0x971E, 0x868A, 0x4FC4, 0x5CE8,
        0x6211, 0x7259, 0x753B, 0x81E5, 0x82BD, 0x86FE, 0x8CC0, 0x96C5, 0x9913, 0x99D5, 0x4ECB,
        0x4F1A, 0x89E3, 0x56DE, 0x584A, 0x58CA, 0x5EFB, 0x5FEB, 0x602A, 0x6094, 0x6062, 0x61D0,
        0x6212, 0x62D0, 0x6539, 0x9B41, 0x6666, 0x68B0, 0x6D77, 0x7070, 0x754C, 0x7686, 0x7D75,
        0x82A5, 0x87F9, 0x958B, 0x968E, 0x8C9D, 0x51F1, 0x52BE, 0x5916, 0x54B3, 0x5BB3, 0x5D16,
        0x6168, 0x6982, 0x6DAF, 0x788D, 0x84CB, 0x8857, 0x8A72, 0x93A7, 0x9AB8, 0x6D6C, 0x99A8,
        0x86D9, 0x57A3, 0x67FF, 0x86CE, 0x920E, 0x5283, 0x5687, 0x5404, 0x5ED3, 0x62E1, 0x64B9,
        0x683C, 0x6838, 0x6BBB, 0x7372, 0x78BA, 0x7A6B, 0x899A, 0x89D2, 0x8D6B, 0x8F03, 0x90ED,
        0x95A3, 0x9694, 0x9769, 0x5B66, 0x5CB3, 0x697D, 0x984D, 0x984E, 0x639B, 0x7B20, 0x6A2B,
        0x6A7F, 0x68B6, 0x9C0D, 0x6F5F, 0x5272, 0x559D, 0x6070, 0x62EC, 0x6D3B, 0x6E07, 0x6ED1,
        0x845B, 0x8910, 0x8F44, 0x4E14, 0x9C39, 0x53F6, 0x691B, 0x6A3A, 0x9784, 0x682A, 0x515C,
        0x7AC3, 0x84B2, 0x91DC, 0x938C, 0x565B, 0x9D28, 0x6822, 0x8305, 0x8431, 0x7CA5, 0x5208,
        0x82C5, 0x74E6, 0x4E7E, 0x4F83, 0x51A0, 0x5BD2, 0x520A, 0x52D8, 0x52E7, 0x5DFB, 0x559A,
        0x582A, 0x59E6, 0x5B8C, 0x5B98, 0x5BDB, 0x5E72, 0x5E79, 0x60A3, 0x611F, 0x6163, 0x61BE,
        0x63DB, 0x6562, 0x67D1, 0x6853, 0x68FA, 0x6B3E, 0x6B53, 0x6C57, 0x6F22, 0x6F97, 0x6F45,
        0x74B0, 0x7518, 0x76E3, 0x770B, 0x7AFF, 0x7BA1, 0x7C21, 0x7DE9, 0x7F36, 0x7FF0, 0x809D,
        0x8266, 0x839E, 0x89B3, 0x8ACC, 0x8CAB, 0x9084, 0x9451, 0x9593, 0x9591, 0x95A2, 0x9665,
        0x97D3, 0x9928, 0x8218, 0x4E38, 0x542B, 0x5CB8, 0x5DCC, 0x73A9, 0x764C, 0x773C, 0x5CA9,
        0x7FEB, 0x8D0B, 0x96C1, 0x9811, 0x9854, 0x9858, 0x4F01, 0x4F0E, 0x5371, 0x559C, 0x5668,
        0x57FA, 0x5947, 0x5B09, 0x5BC4, 0x5C90, 0x5E0C, 0x5E7E, 0x5FCC, 0x63EE, 0x673A, 0x65D7,
        0x65E2, 0x671F, 0x68CB, 0x68C4, 0x6A5F, 0x5E30, 0x6BC5, 0x6C17, 0x6C7D, 0x757F, 0x7948,
        0x5B63, 0x7A00, 0x7D00, 0x5FBD, 0x898F, 0x8A18, 0x8CB4, 0x8D77, 0x8ECC, 0x8F1D, 0x98E2,
        0x9A0E, 0x9B3C, 0x4E80, 0x507D, 0x5100, 0x5993, 0x5B9C, 0x622F, 0x6280, 0x64EC, 0x6B3A,
        0x72A0, 0x7591, 0x7947, 0x7FA9, 0x87FB, 0x8ABC, 0x8B70, 0x63AC, 0x83CA, 0x97A0, 0x5409,
        0x5403, 0x55AB, 0x6854, 0x6A58, 0x8A70, 0x7827, 0x6775, 0x9ECD, 0x5374, 0x5BA2, 0x811A,
        0x8650, 0x9006, 0x4E18, 0x4E45, 0x4EC7, 0x4F11, 0x53CA, 0x5438, 0x5BAE, 0x5F13, 0x6025,
        0x6551, 0x673D, 0x6C42, 0x6C72, 0x6CE3, 0x7078, 0x7403, 0x7A76, 0x7AAE, 0x7B08, 0x7D1A,
        0x7CFE, 0x7D66, 0x65E7, 0x725B, 0x53BB, 0x5C45, 0x5DE8, 0x62D2, 0x62E0, 0x6319, 0x6E20,
        0x865A, 0x8A31, 0x8DDD, 0x92F8, 0x6F01, 0x79A6, 0x9B5A, 0x4EA8, 0x4EAB, 0x4EAC, 0x4F9B,
        0x4FA0, 0x50D1, 0x5147, 0x7AF6, 0x5171, 0x51F6, 0x5354, 0x5321, 0x537F, 0x53EB, 0x55AC,
        0x5883, 0x5CE1, 0x5F37, 0x5F4A, 0x602F, 0x6050, 0x606D, 0x631F, 0x6559, 0x6A4B, 0x6CC1,
        0x72C2, 0x72ED, 0x77EF, 0x80F8, 0x8105, 0x8208, 0x854E, 0x90F7, 0x93E1, 0x97FF, 0x9957,
        0x9A5A, 0x4EF0, 0x51DD, 0x5C2D, 0x6681, 0x696D, 0x5C40, 0x66F2, 0x6975, 0x7389, 0x6850,
        0x7C81, 0x50C5, 0x52E4, 0x5747, 0x5DFE, 0x9326, 0x65A4, 0x6B23, 0x6B3D, 0x7434, 0x7981,
        0x79BD, 0x7B4B, 0x7DCA, 0x82B9, 0x83CC, 0x887F, 0x895F, 0x8B39, 0x8FD1, 0x91D1, 0x541F,
        0x9280, 0x4E5D, 0x5036, 0x53E5, 0x533A, 0x72D7, 0x7396, 0x77E9, 0x82E6, 0x8EAF, 0x99C6,
        0x99C8, 0x99D2, 0x5177, 0x611A, 0x865E, 0x55B0, 0x7A7A, 0x5076, 0x5BD3, 0x9047, 0x9685,
        0x4E32, 0x6ADB, 0x91E7, 0x5C51, 0x5C48, 0x6398, 0x7A9F, 0x6C93, 0x9774, 0x8F61, 0x7AAA,
        0x718A, 0x9688, 0x7C82, 0x6817, 0x7E70, 0x6851, 0x936C, 0x52F2, 0x541B, 0x85AB, 0x8A13,
        0x7FA4, 0x8ECD, 0x90E1, 0x5366, 0x8888, 0x7941, 0x4FC2, 0x50BE, 0x5211, 0x5144, 0x5553,
        0x572D, 0x73EA, 0x578B, 0x5951, 0x5F62, 0x5F84, 0x6075, 0x6176, 0x6167, 0x61A9, 0x63B2,
        0x643A, 0x656C, 0x666F, 0x6842, 0x6E13, 0x7566, 0x7A3D, 0x7CFB, 0x7D4C, 0x7D99, 0x7E4B,
        0x7F6B, 0x830E, 0x834A, 0x86CD, 0x8A08, 0x8A63, 0x8B66, 0x8EFD, 0x981A, 0x9D8F, 0x82B8,
        0x8FCE, 0x9BE8, 0x5287, 0x621F, 0x6483, 0x6FC0, 0x9699, 0x6841, 0x5091, 0x6B20, 0x6C7A,
        0x6F54, 0x7A74, 0x7D50, 0x8840, 0x8A23, 0x6708, 0x4EF6, 0x5039, 0x5026, 0x5065, 0x517C,
        0x5238, 0x5263, 0x55A7, 0x570F, 0x5805, 0x5ACC, 0x5EFA, 0x61B2, 0x61F8, 0x62F3, 0x6372,
        0x691C, 0x6A29, 0x727D, 0x72AC, 0x732E, 0x7814, 0x786F, 0x7D79, 0x770C, 0x80A9, 0x898B,
        0x8B19, 0x8CE2, 0x8ED2, 0x9063, 0x9375, 0x967A, 0x9855, 0x9A13, 0x9E78, 0x5143, 0x539F,
        0x53B3, 0x5E7B, 0x5F26, 0x6E1B, 0x6E90, 0x7384, 0x73FE, 0x7D43, 0x8237, 0x8A00, 0x8AFA,
        0x9650, 0x4E4E, 0x500B, 0x53E4, 0x547C, 0x56FA, 0x59D1, 0x5B64, 0x5DF1, 0x5EAB, 0x5F27,
        0x6238, 0x6545, 0x67AF, 0x6E56, 0x72D0, 0x7CCA, 0x88B4, 0x80A1, 0x80E1, 0x83F0, 0x864E,
        0x8A87, 0x8DE8, 0x9237, 0x96C7, 0x9867, 0x9F13, 0x4E94, 0x4E92, 0x4F0D, 0x5348, 0x5449,
        0x543E, 0x5A2F, 0x5F8C, 0x5FA1, 0x609F, 0x68A7, 0x6A8E, 0x745A, 0x7881, 0x8A9E, 0x8AA4,
        0x8B77, 0x9190, 0x4E5E, 0x9BC9, 0x4EA4, 0x4F7C, 0x4FAF, 0x5019, 0x5016, 0x5149, 0x516C,
        0x529F, 0x52B9, 0x52FE, 0x539A, 0x53E3, 0x5411, 0x540E, 0x5589, 0x5751, 0x57A2, 0x597D,
        0x5B54, 0x5B5D, 0x5B8F, 0x5DE5, 0x5DE7, 0x5DF7, 0x5E78, 0x5E83, 0x5E9A, 0x5EB7, 0x5F18,
        0x6052, 0x614C, 0x6297, 0x62D8, 0x63A7, 0x653B, 0x6602, 0x6643, 0x66F4, 0x676D, 0x6821,
        0x6897, 0x69CB, 0x6C5F, 0x6D2A, 0x6D69, 0x6E2F, 0x6E9D, 0x7532, 0x7687, 0x786C, 0x7A3F,
        0x7CE0, 0x7D05, 0x7D18, 0x7D5E, 0x7DB1, 0x8015, 0x8003, 0x80AF, 0x80B1, 0x8154, 0x818F,
        0x822A, 0x8352, 0x884C, 0x8861, 0x8B1B, 0x8CA2, 0x8CFC, 0x90CA, 0x9175, 0x9271, 0x783F,
        0x92FC, 0x95A4, 0x964D, 0x9805, 0x9999, 0x9AD8, 0x9D3B, 0x525B, 0x52AB, 0x53F7, 0x5408,
        0x58D5, 0x62F7, 0x6FE0, 0x8C6A, 0x8F5F, 0x9EB9, 0x514B, 0x523B, 0x544A, 0x56FD, 0x7A40,
        0x9177, 0x9D60, 0x9ED2, 0x7344, 0x6F09, 0x8170, 0x7511, 0x5FFD, 0x60DA, 0x9AA8, 0x72DB,
        0x8FBC, 0x6B64, 0x9803, 0x4ECA, 0x56F0, 0x5764, 0x58BE, 0x5A5A, 0x6068, 0x61C7, 0x660F,
        0x6606, 0x6839, 0x68B1, 0x6DF7, 0x75D5, 0x7D3A, 0x826E, 0x9B42, 0x4E9B, 0x4F50, 0x53C9,
        0x5506, 0x5D6F, 0x5DE6, 0x5DEE, 0x67FB, 0x6C99, 0x7473, 0x7802, 0x8A50, 0x9396, 0x88DF,
        0x5750, 0x5EA7, 0x632B, 0x50B5, 0x50AC, 0x518D, 0x6700, 0x54C9, 0x585E, 0x59BB, 0x5BB0,
        0x5F69, 0x624D, 0x63A1, 0x683D, 0x6B73, 0x6E08, 0x707D, 0x91C7, 0x7280, 0x7815, 0x7826,
        0x796D, 0x658E, 0x7D30, 0x83DC, 0x88C1, 0x8F09, 0x969B, 0x5264, 0x5728, 0x6750, 0x7F6A,
        0x8CA1, 0x51B4, 0x5742, 0x962A, 0x583A, 0x698A, 0x80B4, 0x54B2, 0x5D0E, 0x57FC, 0x7895,
        0x9DFA, 0x4F5C, 0x524A, 0x548B, 0x643E, 0x6628, 0x6714, 0x67F5, 0x7A84, 0x7B56, 0x7D22,
        0x932F, 0x685C, 0x9BAD, 0x7B39, 0x5319, 0x518A, 0x5237, 0x5BDF, 0x62F6, 0x64AE, 0x64E6,
        0x672D, 0x6BBA, 0x85A9, 0x96D1, 0x7690, 0x9BD6, 0x634C, 0x9306, 0x9BAB, 0x76BF, 0x6652,
        0x4E09, 0x5098, 0x53C2, 0x5C71, 0x60E8, 0x6492, 0x6563, 0x685F, 0x71E6, 0x73CA, 0x7523,
        0x7B97, 0x7E82, 0x8695, 0x8B83, 0x8CDB, 0x9178, 0x9910, 0x65AC, 0x66AB, 0x6B8B, 0x4ED5,
        0x4ED4, 0x4F3A, 0x4F7F, 0x523A, 0x53F8, 0x53F2, 0x55E3, 0x56DB, 0x58EB, 0x59CB, 0x59C9,
        0x59FF, 0x5B50, 0x5C4D, 0x5E02, 0x5E2B, 0x5FD7, 0x601D, 0x6307, 0x652F, 0x5B5C, 0x65AF,
        0x65BD, 0x65E8, 0x679D, 0x6B62, 0x6B7B, 0x6C0F, 0x7345, 0x7949, 0x79C1, 0x7CF8, 0x7D19,
        0x7D2B, 0x80A2, 0x8102, 0x81F3, 0x8996, 0x8A5E, 0x8A69, 0x8A66, 0x8A8C, 0x8AEE, 0x8CC7,
        0x8CDC, 0x96CC, 0x98FC, 0x6B6F, 0x4E8B, 0x4F3C, 0x4F8D, 0x5150, 0x5B57, 0x5BFA, 0x6148,
        0x6301, 0x6642, 0x6B21, 0x6ECB, 0x6CBB, 0x723E, 0x74BD, 0x75D4, 0x78C1, 0x793A, 0x800C,
        0x8033, 0x81EA, 0x8494, 0x8F9E, 0x6C50, 0x9E7F, 0x5F0F, 0x8B58, 0x9D2B, 0x7AFA, 0x8EF8,
        0x5B8D, 0x96EB, 0x4E03, 0x53F1, 0x57F7, 0x5931, 0x5AC9, 0x5BA4, 0x6089, 0x6E7F, 0x6F06,
        0x75BE, 0x8CEA, 0x5B9F, 0x8500, 0x7BE0, 0x5072, 0x67F4, 0x829D, 0x5C61, 0x854A, 0x7E1E,
        0x820E, 0x5199, 0x5C04, 0x6368, 0x8D66, 0x659C, 0x716E, 0x793E, 0x7D17, 0x8005, 0x8B1D,
        0x8ECA, 0x906E, 0x86C7, 0x90AA, 0x501F, 0x52FA, 0x5C3A, 0x6753, 0x707C, 0x7235, 0x914C,
        0x91C8, 0x932B, 0x82E5, 0x5BC2, 0x5F31, 0x60F9, 0x4E3B, 0x53D6, 0x5B88, 0x624B, 0x6731,
        0x6B8A, 0x72E9, 0x73E0, 0x7A2E, 0x816B, 0x8DA3, 0x9152, 0x9996, 0x5112, 0x53D7, 0x546A,
        0x5BFF, 0x6388, 0x6A39, 0x7DAC, 0x9700, 0x56DA, 0x53CE, 0x5468, 0x5B97, 0x5C31, 0x5DDE,
        0x4FEE, 0x6101, 0x62FE, 0x6D32, 0x79C0, 0x79CB, 0x7D42, 0x7E4D, 0x7FD2, 0x81ED, 0x821F,
        0x8490, 0x8846, 0x8972, 0x8B90, 0x8E74, 0x8F2F, 0x9031, 0x914B, 0x916C, 0x96C6, 0x919C,
        0x4EC0, 0x4F4F, 0x5145, 0x5341, 0x5F93, 0x620E, 0x67D4, 0x6C41, 0x6E0B, 0x7363, 0x7E26,
        0x91CD, 0x9283, 0x53D4, 0x5919, 0x5BBF, 0x6DD1, 0x795D, 0x7E2E, 0x7C9B, 0x587E, 0x719F,
        0x51FA, 0x8853, 0x8FF0, 0x4FCA, 0x5CFB, 0x6625, 0x77AC, 0x7AE3, 0x821C, 0x99FF, 0x51C6,
        0x5FAA, 0x65EC, 0x696F, 0x6B89, 0x6DF3, 0x6E96, 0x6F64, 0x76FE, 0x7D14, 0x5DE1, 0x9075,
        0x9187, 0x9806, 0x51E6, 0x521D, 0x6240, 0x6691, 0x66D9, 0x6E1A, 0x5EB6, 0x7DD2, 0x7F72,
        0x66F8, 0x85AF, 0x85F7, 0x8AF8, 0x52A9, 0x53D9, 0x5973, 0x5E8F, 0x5F90, 0x6055, 0x92E4,
        0x9664, 0x50B7, 0x511F, 0x52DD, 0x5320, 0x5347, 0x53EC, 0x54E8, 0x5546, 0x5531, 0x5617,
        0x5968, 0x59BE, 0x5A3C, 0x5BB5, 0x5C06, 0x5C0F, 0x5C11, 0x5C1A, 0x5E84, 0x5E8A, 0x5EE0,
        0x5F70, 0x627F, 0x6284, 0x62DB, 0x638C, 0x6377, 0x6607, 0x660C, 0x662D, 0x6676, 0x677E,
        0x68A2, 0x6A1F, 0x6A35, 0x6CBC, 0x6D88, 0x6E09, 0x6E58, 0x713C, 0x7126, 0x7167, 0x75C7,
        0x7701, 0x785D, 0x7901, 0x7965, 0x79F0, 0x7AE0, 0x7B11, 0x7CA7, 0x7D39, 0x8096, 0x83D6,
        0x848B, 0x8549, 0x885D, 0x88F3, 0x8A1F, 0x8A3C, 0x8A54, 0x8A73, 0x8C61, 0x8CDE, 0x91A4,
        0x9266, 0x937E, 0x9418, 0x969C, 0x9798, 0x4E0A, 0x4E08, 0x4E1E, 0x4E57, 0x5197, 0x5270,
        0x57CE, 0x5834, 0x58CC, 0x5B22, 0x5E38, 0x60C5, 0x64FE, 0x6761, 0x6756, 0x6D44, 0x72B6,
        0x7573, 0x7A63, 0x84B8, 0x8B72, 0x91B8, 0x9320, 0x5631, 0x57F4, 0x98FE, 0x62ED, 0x690D,
        0x6B96, 0x71ED, 0x7E54, 0x8077, 0x8272, 0x89E6, 0x98DF, 0x8755, 0x8FB1, 0x5C3B, 0x4F38,
        0x4FE1, 0x4FB5, 0x5507, 0x5A20, 0x5BDD, 0x5BE9, 0x5FC3, 0x614E, 0x632F, 0x65B0, 0x664B,
        0x68EE, 0x699B, 0x6D78, 0x6DF1, 0x7533, 0x75B9, 0x771F, 0x795E, 0x79E6, 0x7D33, 0x81E3,
        0x82AF, 0x85AA, 0x89AA, 0x8A3A, 0x8EAB, 0x8F9B, 0x9032, 0x91DD, 0x9707, 0x4EBA, 0x4EC1,
        0x5203, 0x5875, 0x58EC, 0x5C0B, 0x751A, 0x5C3D, 0x814E, 0x8A0A, 0x8FC5, 0x9663, 0x976D,
        0x7B25, 0x8ACF, 0x9808, 0x9162, 0x56F3, 0x53A8, 0x9017, 0x5439, 0x5782, 0x5E25, 0x63A8,
        0x6C34, 0x708A, 0x7761, 0x7C8B, 0x7FE0, 0x8870, 0x9042, 0x9154, 0x9310, 0x9318, 0x968F,
        0x745E, 0x9AC4, 0x5D07, 0x5D69, 0x6570, 0x67A2, 0x8DA8, 0x96DB, 0x636E, 0x6749, 0x6919,
        0x83C5, 0x9817, 0x96C0, 0x88FE, 0x6F84, 0x647A, 0x5BF8, 0x4E16, 0x702C, 0x755D, 0x662F,
        0x51C4, 0x5236, 0x52E2, 0x59D3, 0x5F81, 0x6027, 0x6210, 0x653F, 0x6574, 0x661F, 0x6674,
        0x68F2, 0x6816, 0x6B63, 0x6E05, 0x7272, 0x751F, 0x76DB, 0x7CBE, 0x8056, 0x58F0, 0x88FD,
        0x897F, 0x8AA0, 0x8A93, 0x8ACB, 0x901D, 0x9192, 0x9752, 0x9759, 0x6589, 0x7A0E, 0x8106,
        0x96BB, 0x5E2D, 0x60DC, 0x621A, 0x65A5, 0x6614, 0x6790, 0x77F3, 0x7A4D, 0x7C4D, 0x7E3E,
        0x810A, 0x8CAC, 0x8D64, 0x8DE1, 0x8E5F, 0x78A9, 0x5207, 0x62D9, 0x63A5, 0x6442, 0x6298,
        0x8A2D, 0x7A83, 0x7BC0, 0x8AAC, 0x96EA, 0x7D76, 0x820C, 0x8749, 0x4ED9, 0x5148, 0x5343,
        0x5360, 0x5BA3, 0x5C02, 0x5C16, 0x5DDD, 0x6226, 0x6247, 0x64B0, 0x6813, 0x6834, 0x6CC9,
        0x6D45, 0x6D17, 0x67D3, 0x6F5C, 0x714E, 0x717D, 0x65CB, 0x7A7F, 0x7BAD, 0x7DDA, 0x7E4A,
        0x7FA8, 0x817A, 0x821B, 0x8239, 0x85A6, 0x8A6E, 0x8CCE, 0x8DF5, 0x9078, 0x9077, 0x92AD,
        0x9291, 0x9583, 0x9BAE, 0x524D, 0x5584, 0x6F38, 0x7136, 0x5168, 0x7985, 0x7E55, 0x81B3,
        0x7CCE, 0x564C, 0x5851, 0x5CA8, 0x63AA, 0x66FE, 0x66FD, 0x695A, 0x72D9, 0x758F, 0x758E,
        0x790E, 0x7956, 0x79DF, 0x7C97, 0x7D20, 0x7D44, 0x8607, 0x8A34, 0x963B, 0x9061, 0x9F20,
        0x50E7, 0x5275, 0x53CC, 0x53E2, 0x5009, 0x55AA, 0x58EE, 0x594F, 0x723D, 0x5B8B, 0x5C64,
        0x531D, 0x60E3, 0x60F3, 0x635C, 0x6383, 0x633F, 0x63BB, 0x64CD, 0x65E9, 0x66F9, 0x5DE3,
        0x69CD, 0x69FD, 0x6F15, 0x71E5, 0x4E89, 0x75E9, 0x76F8, 0x7A93, 0x7CDF, 0x7DCF, 0x7D9C,
        0x8061, 0x8349, 0x8358, 0x846C, 0x84BC, 0x85FB, 0x88C5, 0x8D70, 0x9001, 0x906D, 0x9397,
        0x971C, 0x9A12, 0x50CF, 0x5897, 0x618E, 0x81D3, 0x8535, 0x8D08, 0x9020, 0x4FC3, 0x5074,
        0x5247, 0x5373, 0x606F, 0x6349, 0x675F, 0x6E2C, 0x8DB3, 0x901F, 0x4FD7, 0x5C5E, 0x8CCA,
        0x65CF, 0x7D9A, 0x5352, 0x8896, 0x5176, 0x63C3, 0x5B58, 0x5B6B, 0x5C0A, 0x640D, 0x6751,
        0x905C, 0x4ED6, 0x591A, 0x592A, 0x6C70, 0x8A51, 0x553E, 0x5815, 0x59A5, 0x60F0, 0x6253,
        0x67C1, 0x8235, 0x6955, 0x9640, 0x99C4, 0x9A28, 0x4F53, 0x5806, 0x5BFE, 0x8010, 0x5CB1,
        0x5E2F, 0x5F85, 0x6020, 0x614B, 0x6234, 0x66FF, 0x6CF0, 0x6EDE, 0x80CE, 0x817F, 0x82D4,
        0x888B, 0x8CB8, 0x9000, 0x902E, 0x968A, 0x9EDB, 0x9BDB, 0x4EE3, 0x53F0, 0x5927, 0x7B2C,
        0x918D, 0x984C, 0x9DF9, 0x6EDD, 0x7027, 0x5353, 0x5544, 0x5B85, 0x6258, 0x629E, 0x62D3,
        0x6CA2, 0x6FEF, 0x7422, 0x8A17, 0x9438, 0x6FC1, 0x8AFE, 0x8338, 0x51E7, 0x86F8, 0x53EA,
        0x53E9, 0x4F46, 0x9054, 0x8FB0, 0x596A, 0x8131, 0x5DFD, 0x7AEA, 0x8FBF, 0x68DA, 0x8C37,
        0x72F8, 0x9C48, 0x6A3D, 0x8AB0, 0x4E39, 0x5358, 0x5606, 0x5766, 0x62C5, 0x63A2, 0x65E6,
        0x6B4E, 0x6DE1, 0x6E5B, 0x70AD, 0x77ED, 0x7AEF, 0x7BAA, 0x7DBB, 0x803D, 0x80C6, 0x86CB,
        0x8A95, 0x935B, 0x56E3, 0x58C7, 0x5F3E, 0x65AD, 0x6696, 0x6A80, 0x6BB5, 0x7537, 0x8AC7,
        0x5024, 0x77E5, 0x5730, 0x5F1B, 0x6065, 0x667A, 0x6C60, 0x75F4, 0x7A1A, 0x7F6E, 0x81F4,
        0x8718, 0x9045, 0x99B3, 0x7BC9, 0x755C, 0x7AF9, 0x7B51, 0x84C4, 0x9010, 0x79E9, 0x7A92,
        0x8336, 0x5AE1, 0x7740, 0x4E2D, 0x4EF2, 0x5B99, 0x5FE0, 0x62BD, 0x663C, 0x67F1, 0x6CE8,
        0x866B, 0x8877, 0x8A3B, 0x914E, 0x92F3, 0x99D0, 0x6A17, 0x7026, 0x732A, 0x82E7, 0x8457,
        0x8CAF, 0x4E01, 0x5146, 0x51CB, 0x558B, 0x5BF5, 0x5E16, 0x5E33, 0x5E81, 0x5F14, 0x5F35,
        0x5F6B, 0x5FB4, 0x61F2, 0x6311, 0x66A2, 0x671D, 0x6F6E, 0x7252, 0x753A, 0x773A, 0x8074,
        0x8139, 0x8178, 0x8776, 0x8ABF, 0x8ADC, 0x8D85, 0x8DF3, 0x929A, 0x9577, 0x9802, 0x9CE5,
        0x52C5, 0x6357, 0x76F4, 0x6715, 0x6C88, 0x73CD, 0x8CC3, 0x93AE, 0x9673, 0x6D25, 0x589C,
        0x690E, 0x69CC, 0x8FFD, 0x939A, 0x75DB, 0x901A, 0x585A, 0x6802, 0x63B4, 0x69FB, 0x4F43,
        0x6F2C, 0x67D8, 0x8FBB, 0x8526, 0x7DB4, 0x9354, 0x693F, 0x6F70, 0x576A, 0x58F7, 0x5B2C,
        0x7D2C, 0x722A, 0x540A, 0x91E3, 0x9DB4, 0x4EAD, 0x4F4E, 0x505C, 0x5075, 0x5243, 0x8C9E,
        0x5448, 0x5824, 0x5B9A, 0x5E1D, 0x5E95, 0x5EAD, 0x5EF7, 0x5F1F, 0x608C, 0x62B5, 0x633A,
        0x63D0, 0x68AF, 0x6C40, 0x7887, 0x798E, 0x7A0B, 0x7DE0, 0x8247, 0x8A02, 0x8AE6, 0x8E44,
        0x9013, 0x90B8, 0x912D, 0x91D8, 0x9F0E, 0x6CE5, 0x6458, 0x64E2, 0x6575, 0x6EF4, 0x7684,
        0x7B1B, 0x9069, 0x93D1, 0x6EBA, 0x54F2, 0x5FB9, 0x64A4, 0x8F4D, 0x8FED, 0x9244, 0x5178,
        0x586B, 0x5929, 0x5C55, 0x5E97, 0x6DFB, 0x7E8F, 0x751C, 0x8CBC, 0x8EE2, 0x985B, 0x70B9,
        0x4F1D, 0x6BBF, 0x6FB1, 0x7530, 0x96FB, 0x514E, 0x5410, 0x5835, 0x5857, 0x59AC, 0x5C60,
        0x5F92, 0x6597, 0x675C, 0x6E21, 0x767B, 0x83DF, 0x8CED, 0x9014, 0x90FD, 0x934D, 0x7825,
        0x783A, 0x52AA, 0x5EA6, 0x571F, 0x5974, 0x6012, 0x5012, 0x515A, 0x51AC, 0x51CD, 0x5200,
        0x5510, 0x5854, 0x5858, 0x5957, 0x5B95, 0x5CF6, 0x5D8B, 0x60BC, 0x6295, 0x642D, 0x6771,
        0x6843, 0x68BC, 0x68DF, 0x76D7, 0x6DD8, 0x6E6F, 0x6D9B, 0x706F, 0x71C8, 0x5F53, 0x75D8,
        0x7977, 0x7B49, 0x7B54, 0x7B52, 0x7CD6, 0x7D71, 0x5230, 0x8463, 0x8569, 0x85E4, 0x8A0E,
        0x8B04, 0x8C46, 0x8E0F, 0x9003, 0x900F, 0x9419, 0x9676, 0x982D, 0x9A30, 0x95D8, 0x50CD,
        0x52D5, 0x540C, 0x5802, 0x5C0E, 0x61A7, 0x649E, 0x6D1E, 0x77B3, 0x7AE5, 0x80F4, 0x8404,
        0x9053, 0x9285, 0x5CE0, 0x9D07, 0x533F, 0x5F97, 0x5FB3, 0x6D9C, 0x7279, 0x7763, 0x79BF,
        0x7BE4, 0x6BD2, 0x72EC, 0x8AAD, 0x6803, 0x6A61, 0x51F8, 0x7A81, 0x6934, 0x5C4A, 0x9CF6,
        0x82EB, 0x5BC5, 0x9149, 0x701E, 0x5678, 0x5C6F, 0x60C7, 0x6566, 0x6C8C, 0x8C5A, 0x9041,
        0x9813, 0x5451, 0x66C7, 0x920D, 0x5948, 0x90A3, 0x5185, 0x4E4D, 0x51EA, 0x8599, 0x8B0E,
        0x7058, 0x637A, 0x934B, 0x6962, 0x99B4, 0x7E04, 0x7577, 0x5357, 0x6960, 0x8EDF, 0x96E3,
        0x6C5D, 0x4E8C, 0x5C3C, 0x5F10, 0x8FE9, 0x5302, 0x8CD1, 0x8089, 0x8679, 0x5EFF, 0x65E5,
        0x4E73, 0x5165, 0x5982, 0x5C3F, 0x97EE, 0x4EFB, 0x598A, 0x5FCD, 0x8A8D, 0x6FE1, 0x79B0,
        0x7962, 0x5BE7, 0x8471, 0x732B, 0x71B1, 0x5E74, 0x5FF5, 0x637B, 0x649A, 0x71C3, 0x7C98,
        0x4E43, 0x5EFC, 0x4E4B, 0x57DC, 0x56A2, 0x60A9, 0x6FC3, 0x7D0D, 0x80FD, 0x8133, 0x81BF,
        0x8FB2, 0x8997, 0x86A4, 0x5DF4, 0x628A, 0x64AD, 0x8987, 0x6777, 0x6CE2, 0x6D3E, 0x7436,
        0x7834, 0x5A46, 0x7F75, 0x82AD, 0x99AC, 0x4FF3, 0x5EC3, 0x62DD, 0x6392, 0x6557, 0x676F,
        0x76C3, 0x724C, 0x80CC, 0x80BA, 0x8F29, 0x914D, 0x500D, 0x57F9, 0x5A92, 0x6885, 0x6973,
        0x7164, 0x72FD, 0x8CB7, 0x58F2, 0x8CE0, 0x966A, 0x9019, 0x877F, 0x79E4, 0x77E7, 0x8429,
        0x4F2F, 0x5265, 0x535A, 0x62CD, 0x67CF, 0x6CCA, 0x767D, 0x7B94, 0x7C95, 0x8236, 0x8584,
        0x8FEB, 0x66DD, 0x6F20, 0x7206, 0x7E1B, 0x83AB, 0x99C1, 0x9EA6, 0x51FD, 0x7BB1, 0x7872,
        0x7BB8, 0x8087, 0x7B48, 0x6AE8, 0x5E61, 0x808C, 0x7551, 0x7560, 0x516B, 0x9262, 0x6E8C,
        0x767A, 0x9197, 0x9AEA, 0x4F10, 0x7F70, 0x629C, 0x7B4F, 0x95A5, 0x9CE9, 0x567A, 0x5859,
        0x86E4, 0x96BC, 0x4F34, 0x5224, 0x534A, 0x53CD, 0x53DB, 0x5E06, 0x642C, 0x6591, 0x677F,
        0x6C3E, 0x6C4E, 0x7248, 0x72AF, 0x73ED, 0x7554, 0x7E41, 0x822C, 0x85E9, 0x8CA9, 0x7BC4,
        0x91C6, 0x7169, 0x9812, 0x98EF, 0x633D, 0x6669, 0x756A, 0x76E4, 0x78D0, 0x8543, 0x86EE,
        0x532A, 0x5351, 0x5426, 0x5983, 0x5E87, 0x5F7C, 0x60B2, 0x6249, 0x6279, 0x62AB, 0x6590,
        0x6BD4, 0x6CCC, 0x75B2, 0x76AE, 0x7891, 0x79D8, 0x7DCB, 0x7F77, 0x80A5, 0x88AB, 0x8AB9,
        0x8CBB, 0x907F, 0x975E, 0x98DB, 0x6A0B, 0x7C38, 0x5099, 0x5C3E, 0x5FAE, 0x6787, 0x6BD8,
        0x7435, 0x7709, 0x7F8E, 0x9F3B, 0x67CA, 0x7A17, 0x5339, 0x758B, 0x9AED, 0x5F66, 0x819D,
        0x83F1, 0x8098, 0x5F3C, 0x5FC5, 0x7562, 0x7B46, 0x903C, 0x6867, 0x59EB, 0x5A9B, 0x7D10,
        0x767E, 0x8B2C, 0x4FF5, 0x5F6A, 0x6A19, 0x6C37, 0x6F02, 0x74E2, 0x7968, 0x8868, 0x8A55,
        0x8C79, 0x5EDF, 0x63CF, 0x75C5, 0x79D2, 0x82D7, 0x9328, 0x92F2, 0x849C, 0x86ED, 0x9C2D,
        0x54C1, 0x5F6C, 0x658C, 0x6D5C, 0x7015, 0x8CA7, 0x8CD3, 0x983B, 0x654F, 0x74F6, 0x4E0D,
        0x4ED8, 0x57E0, 0x592B, 0x5A66, 0x5BCC, 0x51A8, 0x5E03, 0x5E9C, 0x6016, 0x6276, 0x6577,
        0x65A7, 0x666E, 0x6D6E, 0x7236, 0x7B26, 0x8150, 0x819A, 0x8299, 0x8B5C, 0x8CA0, 0x8CE6,
        0x8D74, 0x961C, 0x9644, 0x4FAE, 0x64AB, 0x6B66, 0x821E, 0x8461, 0x856A, 0x90E8, 0x5C01,
        0x6953, 0x98A8, 0x847A, 0x8557, 0x4F0F, 0x526F, 0x5FA9, 0x5E45, 0x670D, 0x798F, 0x8179,
        0x8907, 0x8986, 0x6DF5, 0x5F17, 0x6255, 0x6CB8, 0x4ECF, 0x7269, 0x9B92, 0x5206, 0x543B,
        0x5674, 0x58B3, 0x61A4, 0x626E, 0x711A, 0x596E, 0x7C89, 0x7CDE, 0x7D1B, 0x96F0, 0x6587,
        0x805E, 0x4E19, 0x4F75, 0x5175, 0x5840, 0x5E63, 0x5E73, 0x5F0A, 0x67C4, 0x4E26, 0x853D,
        0x9589, 0x965B, 0x7C73, 0x9801, 0x50FB, 0x58C1, 0x7656, 0x78A7, 0x5225, 0x77A5, 0x8511,
        0x7B86, 0x504F, 0x5909, 0x7247, 0x7BC7, 0x7DE8, 0x8FBA, 0x8FD4, 0x904D, 0x4FBF, 0x52C9,
        0x5A29, 0x5F01, 0x97AD, 0x4FDD, 0x8217, 0x92EA, 0x5703, 0x6355, 0x6B69, 0x752B, 0x88DC,
        0x8F14, 0x7A42, 0x52DF, 0x5893, 0x6155, 0x620A, 0x66AE, 0x6BCD, 0x7C3F, 0x83E9, 0x5023,
        0x4FF8, 0x5305, 0x5446, 0x5831, 0x5949, 0x5B9D, 0x5CF0, 0x5CEF, 0x5D29, 0x5E96, 0x62B1,
        0x6367, 0x653E, 0x65B9, 0x670B, 0x6CD5, 0x6CE1, 0x70F9, 0x7832, 0x7E2B, 0x80DE, 0x82B3,
        0x840C, 0x84EC, 0x8702, 0x8912, 0x8A2A, 0x8C4A, 0x90A6, 0x92D2, 0x98FD, 0x9CF3, 0x9D6C,
        0x4E4F, 0x4EA1, 0x508D, 0x5256, 0x574A, 0x59A8, 0x5E3D, 0x5FD8, 0x5FD9, 0x623F, 0x66B4,
        0x671B, 0x67D0, 0x68D2, 0x5192, 0x7D21, 0x80AA, 0x81A8, 0x8B00, 0x8C8C, 0x8CBF, 0x927E,
        0x9632, 0x5420, 0x982C, 0x5317, 0x50D5, 0x535C, 0x58A8, 0x64B2, 0x6734, 0x7267, 0x7766,
        0x7A46, 0x91E6, 0x52C3, 0x6CA1, 0x6B86, 0x5800, 0x5E4C, 0x5954, 0x672C, 0x7FFB, 0x51E1,
        0x76C6, 0x6469, 0x78E8, 0x9B54, 0x9EBB, 0x57CB, 0x59B9, 0x6627, 0x679A, 0x6BCE, 0x54E9,
        0x69D9, 0x5E55, 0x819C, 0x6795, 0x9BAA, 0x67FE, 0x9C52, 0x685D, 0x4EA6, 0x4FE3, 0x53C8,
        0x62B9, 0x672B, 0x6CAB, 0x8FC4, 0x4FAD, 0x7E6D, 0x9EBF, 0x4E07, 0x6162, 0x6E80, 0x6F2B,
        0x8513, 0x5473, 0x672A, 0x9B45, 0x5DF3, 0x7B95, 0x5CAC, 0x5BC6, 0x871C, 0x6E4A, 0x84D1,
        0x7A14, 0x8108, 0x5999, 0x7C8D, 0x6C11, 0x7720, 0x52D9, 0x5922, 0x7121, 0x725F, 0x77DB,
        0x9727, 0x9D61, 0x690B, 0x5A7F, 0x5A18, 0x51A5, 0x540D, 0x547D, 0x660E, 0x76DF, 0x8FF7,
        0x9298, 0x9CF4, 0x59EA, 0x725D, 0x6EC5, 0x514D, 0x68C9, 0x7DBF, 0x7DEC, 0x9762, 0x9EBA,
        0x6478, 0x6A21, 0x8302, 0x5984, 0x5B5F, 0x6BDB, 0x731B, 0x76F2, 0x7DB2, 0x8017, 0x8499,
        0x5132, 0x6728, 0x9ED9, 0x76EE, 0x6762, 0x52FF, 0x9905, 0x5C24, 0x623B, 0x7C7E, 0x8CB0,
        0x554F, 0x60B6, 0x7D0B, 0x9580, 0x5301, 0x4E5F, 0x51B6, 0x591C, 0x723A, 0x8036, 0x91CE,
        0x5F25, 0x77E2, 0x5384, 0x5F79, 0x7D04, 0x85AC, 0x8A33, 0x8E8D, 0x9756, 0x67F3, 0x85AE,
        0x9453, 0x6109, 0x6108, 0x6CB9, 0x7652, 0x8AED, 0x8F38, 0x552F, 0x4F51, 0x512A, 0x52C7,
        0x53CB, 0x5BA5, 0x5E7D, 0x60A0, 0x6182, 0x63D6, 0x6709, 0x67DA, 0x6E67, 0x6D8C, 0x7336,
        0x7337, 0x7531, 0x7950, 0x88D5, 0x8A98, 0x904A, 0x9091, 0x90F5, 0x96C4, 0x878D, 0x5915,
        0x4E88, 0x4F59, 0x4E0E, 0x8A89, 0x8F3F, 0x9810, 0x50AD, 0x5E7C, 0x5996, 0x5BB9, 0x5EB8,
        0x63DA, 0x63FA, 0x64C1, 0x66DC, 0x694A, 0x69D8, 0x6D0B, 0x6EB6, 0x7194, 0x7528, 0x7AAF,
        0x7F8A, 0x8000, 0x8449, 0x84C9, 0x8981, 0x8B21, 0x8E0A, 0x9065, 0x967D, 0x990A, 0x617E,
        0x6291, 0x6B32, 0x6C83, 0x6D74, 0x7FCC, 0x7FFC, 0x6DC0, 0x7F85, 0x87BA, 0x88F8, 0x6765,
        0x83B1, 0x983C, 0x96F7, 0x6D1B, 0x7D61, 0x843D, 0x916A, 0x4E71, 0x5375, 0x5D50, 0x6B04,
        0x6FEB, 0x85CD, 0x862D, 0x89A7, 0x5229, 0x540F, 0x5C65, 0x674E, 0x68A8, 0x7406, 0x7483,
        0x75E2, 0x88CF, 0x88E1, 0x91CC, 0x96E2, 0x9678, 0x5F8B, 0x7387, 0x7ACB, 0x844E, 0x63A0,
        0x7565, 0x5289, 0x6D41, 0x6E9C, 0x7409, 0x7559, 0x786B, 0x7C92, 0x9686, 0x7ADC, 0x9F8D,
        0x4FB6, 0x616E, 0x65C5, 0x865C, 0x4E86, 0x4EAE, 0x50DA, 0x4E21, 0x51CC, 0x5BEE, 0x6599,
        0x6881, 0x6DBC, 0x731F, 0x7642, 0x77AD, 0x7A1C, 0x7CE7, 0x826F, 0x8AD2, 0x907C, 0x91CF,
        0x9675, 0x9818, 0x529B, 0x7DD1, 0x502B, 0x5398, 0x6797, 0x6DCB, 0x71D0, 0x7433, 0x81E8,
        0x8F2A, 0x96A3, 0x9C57, 0x9E9F, 0x7460, 0x5841, 0x6D99, 0x7D2F, 0x985E, 0x4EE4, 0x4F36,
        0x4F8B, 0x51B7, 0x52B1, 0x5DBA, 0x601C, 0x73B2, 0x793C, 0x82D3, 0x9234, 0x96B7, 0x96F6,
        0x970A, 0x9E97, 0x9F62, 0x66A6, 0x6B74, 0x5217, 0x52A3, 0x70C8, 0x88C2, 0x5EC9, 0x604B,
        0x6190, 0x6F23, 0x7149, 0x7C3E, 0x7DF4, 0x806F, 0x84EE, 0x9023, 0x932C, 0x5442, 0x9B6F,
        0x6AD3, 0x7089, 0x8CC2, 0x8DEF, 0x9732, 0x52B4, 0x5A41, 0x5ECA, 0x5F04, 0x6717, 0x697C,
        0x6994, 0x6D6A, 0x6F0F, 0x7262, 0x72FC, 0x7BED, 0x8001, 0x807E, 0x874B, 0x90CE, 0x516D,
        0x9E93, 0x7984, 0x808B, 0x9332, 0x8AD6, 0x502D, 0x548C, 0x8A71, 0x6B6A, 0x8CC4, 0x8107,
        0x60D1, 0x67A0, 0x9DF2, 0x4E99, 0x4E98, 0x9C10, 0x8A6B, 0x85C1, 0x8568, 0x6900, 0x6E7E,
        0x7897, 0x8155, 0x5F0C, 0x4E10, 0x4E15, 0x4E2A, 0x4E31, 0x4E36, 0x4E3C, 0x4E3F, 0x4E42,
        0x4E56, 0x4E58, 0x4E82, 0x4E85, 0x8C6B, 0x4E8A, 0x8212, 0x5F0D, 0x4E8E, 0x4E9E, 0x4E9F,
        0x4EA0, 0x4EA2, 0x4EB0, 0x4EB3, 0x4EB6, 0x4ECE, 0x4ECD, 0x4EC4, 0x4EC6, 0x4EC2, 0x4ED7,
        0x4EDE, 0x4EED, 0x4EDF, 0x4EF7, 0x4F09, 0x4F5A, 0x4F30, 0x4F5B, 0x4F5D, 0x4F57, 0x4F47,
        0x4F76, 0x4F88, 0x4F8F, 0x4F98, 0x4F7B, 0x4F69, 0x4F70, 0x4F91, 0x4F6F, 0x4F86, 0x4F96,
        0x5118, 0x4FD4, 0x4FDF, 0x4FCE, 0x4FD8, 0x4FDB, 0x4FD1, 0x4FDA, 0x4FD0, 0x4FE4, 0x4FE5,
        0x501A, 0x5028, 0x5014, 0x502A, 0x5025, 0x5005, 0x4F1C, 0x4FF6, 0x5021, 0x5029, 0x502C,
        0x4FFE, 0x4FEF, 0x5011, 0x5006, 0x5043, 0x5047, 0x6703, 0x5055, 0x5050, 0x5048, 0x505A,
        0x5056, 0x506C, 0x5078, 0x5080, 0x509A, 0x5085, 0x50B4, 0x50B2, 0x50C9, 0x50CA, 0x50B3,
        0x50C2, 0x50D6, 0x50DE, 0x50E5, 0x50ED, 0x50E3, 0x50EE, 0x50F9, 0x50F5, 0x5109, 0x5101,
        0x5102, 0x5116, 0x5115, 0x5114, 0x511A, 0x5121, 0x513A, 0x5137, 0x513C, 0x513B, 0x513F,
        0x5140, 0x5152, 0x514C, 0x5154, 0x5162, 0x7AF8, 0x5169, 0x516A, 0x516E, 0x5180, 0x5182,
        0x56D8, 0x518C, 0x5189, 0x518F, 0x5191, 0x5193, 0x5195, 0x5196, 0x51A4, 0x51A6, 0x51A2,
        0x51A9, 0x51AA, 0x51AB, 0x51B3, 0x51B1, 0x51B2, 0x51B0, 0x51B5, 0x51BD, 0x51C5, 0x51C9,
        0x51DB, 0x51E0, 0x8655, 0x51E9, 0x51ED, 0x51F0, 0x51F5, 0x51FE, 0x5204, 0x520B, 0x5214,
        0x520E, 0x5227, 0x522A, 0x522E, 0x5233, 0x5239, 0x524F, 0x5244, 0x524B, 0x524C, 0x525E,
        0x5254, 0x526A, 0x5274, 0x5269, 0x5273, 0x527F, 0x527D, 0x528D, 0x5294, 0x5292, 0x5271,
        0x5288, 0x5291, 0x8FA8, 0x8FA7, 0x52AC, 0x52AD, 0x52BC, 0x52B5, 0x52C1, 0x52CD, 0x52D7,
        0x52DE, 0x52E3, 0x52E6, 0x98ED, 0x52E0, 0x52F3, 0x52F5, 0x52F8, 0x52F9, 0x5306, 0x5308,
        0x7538, 0x530D, 0x5310, 0x530F, 0x5315, 0x531A, 0x5323, 0x532F, 0x5331, 0x5333, 0x5338,
        0x5340, 0x5346, 0x5345, 0x4E17, 0x5349, 0x534D, 0x51D6, 0x535E, 0x5369, 0x536E, 0x5918,
        0x537B, 0x5377, 0x5382, 0x5396, 0x53A0, 0x53A6, 0x53A5, 0x53AE, 0x53B0, 0x53B6, 0x53C3,
        0x7C12, 0x96D9, 0x53DF, 0x66FC, 0x71EE, 0x53EE, 0x53E8, 0x53ED, 0x53FA, 0x5401, 0x543D,
        0x5440, 0x542C, 0x542D, 0x543C, 0x542E, 0x5436, 0x5429, 0x541D, 0x544E, 0x548F, 0x5475,
        0x548E, 0x545F, 0x5471, 0x5477, 0x5470, 0x5492, 0x547B, 0x5480, 0x5476, 0x5484, 0x5490,
        0x5486, 0x54C7, 0x54A2, 0x54B8, 0x54A5, 0x54AC, 0x54C4, 0x54C8, 0x54A8, 0x54AB, 0x54C2,
        0x54A4, 0x54BE, 0x54BC, 0x54D8, 0x54E5, 0x54E6, 0x550F, 0x5514, 0x54FD, 0x54EE, 0x54ED,
        0x54FA, 0x54E2, 0x5539, 0x5540, 0x5563, 0x554C, 0x552E, 0x555C, 0x5545, 0x5556, 0x5557,
        0x5538, 0x5533, 0x555D, 0x5599, 0x5580, 0x54AF, 0x558A, 0x559F, 0x557B, 0x557E, 0x5598,
        0x559E, 0x55AE, 0x557C, 0x5583, 0x55A9, 0x5587, 0x55A8, 0x55DA, 0x55C5, 0x55DF, 0x55C4,
        0x55DC, 0x55E4, 0x55D4, 0x5614, 0x55F7, 0x5616, 0x55FE, 0x55FD, 0x561B, 0x55F9, 0x564E,
        0x5650, 0x71DF, 0x5634, 0x5636, 0x5632, 0x5638, 0x566B, 0x5664, 0x562F, 0x566C, 0x566A,
        0x5686, 0x5680, 0x568A, 0x56A0, 0x5694, 0x568F, 0x56A5, 0x56AE, 0x56B6, 0x56B4, 0x56C2,
        0x56BC, 0x56C1, 0x56C3, 0x56C0, 0x56C8, 0x56CE, 0x56D1, 0x56D3, 0x56D7, 0x56EE, 0x56F9,
        0x5700, 0x56FF, 0x5704, 0x5709, 0x5708, 0x570B, 0x570D, 0x5713, 0x5718, 0x5716, 0x55C7,
        0x571C, 0x5726, 0x5737, 0x5738, 0x574E, 0x573B, 0x5740, 0x574F, 0x5769, 0x57C0, 0x5788,
        0x5761, 0x577F, 0x5789, 0x5793, 0x57A0, 0x57B3, 0x57A4, 0x57AA, 0x57B0, 0x57C3, 0x57C6,
        0x57D4, 0x57D2, 0x57D3, 0x580A, 0x57D6, 0x57E3, 0x580B, 0x5819, 0x581D, 0x5872, 0x5821,
        0x5862, 0x584B, 0x5870, 0x6BC0, 0x5852, 0x583D, 0x5879, 0x5885, 0x58B9, 0x589F, 0x58AB,
        0x58BA, 0x58DE, 0x58BB, 0x58B8, 0x58AE, 0x58C5, 0x58D3, 0x58D1, 0x58D7, 0x58D9, 0x58D8,
        0x58E5, 0x58DC, 0x58E4, 0x58DF, 0x58EF, 0x58FA, 0x58F9, 0x58FB, 0x58FC, 0x58FD, 0x5902,
        0x590A, 0x5910, 0x591B, 0x68A6, 0x5925, 0x592C, 0x592D, 0x5932, 0x5938, 0x593E, 0x7AD2,
        0x5955, 0x5950, 0x594E, 0x595A, 0x5958, 0x5962, 0x5960, 0x5967, 0x596C, 0x5969, 0x5978,
        0x5981, 0x599D, 0x4F5E, 0x4FAB, 0x59A3, 0x59B2, 0x59C6, 0x59E8, 0x59DC, 0x598D, 0x59D9,
        0x59DA, 0x5A25, 0x5A1F, 0x5A11, 0x5A1C, 0x5A09, 0x5A1A, 0x5A40, 0x5A6C, 0x5A49, 0x5A35,
        0x5A36, 0x5A62, 0x5A6A, 0x5A9A, 0x5ABC, 0x5ABE, 0x5ACB, 0x5AC2, 0x5ABD, 0x5AE3, 0x5AD7,
        0x5AE6, 0x5AE9, 0x5AD6, 0x5AFA, 0x5AFB, 0x5B0C, 0x5B0B, 0x5B16, 0x5B32, 0x5AD0, 0x5B2A,
        0x5B36, 0x5B3E, 0x5B43, 0x5B45, 0x5B40, 0x5B51, 0x5B55, 0x5B5A, 0x5B5B, 0x5B65, 0x5B69,
        0x5B70, 0x5B73, 0x5B75, 0x5B78, 0x6588, 0x5B7A, 0x5B80, 0x5B83, 0x5BA6, 0x5BB8, 0x5BC3,
        0x5BC7, 0x5BC9, 0x5BD4, 0x5BD0, 0x5BE4, 0x5BE6, 0x5BE2, 0x5BDE, 0x5BE5, 0x5BEB, 0x5BF0,
        0x5BF6, 0x5BF3, 0x5C05, 0x5C07, 0x5C08, 0x5C0D, 0x5C13, 0x5C20, 0x5C22, 0x5C28, 0x5C38,
        0x5C39, 0x5C41, 0x5C46, 0x5C4E, 0x5C53, 0x5C50, 0x5C4F, 0x5B71, 0x5C6C, 0x5C6E, 0x4E62,
        0x5C76, 0x5C79, 0x5C8C, 0x5C91, 0x5C94, 0x599B, 0x5CAB, 0x5CBB, 0x5CB6, 0x5CBC, 0x5CB7,
        0x5CC5, 0x5CBE, 0x5CC7, 0x5CD9, 0x5CE9, 0x5CFD, 0x5CFA, 0x5CED, 0x5D8C, 0x5CEA, 0x5D0B,
        0x5D15, 0x5D17, 0x5D5C, 0x5D1F, 0x5D1B, 0x5D11, 0x5D14, 0x5D22, 0x5D1A, 0x5D19, 0x5D18,
        0x5D4C, 0x5D52, 0x5D4E, 0x5D4B, 0x5D6C, 0x5D73, 0x5D76, 0x5D87, 0x5D84, 0x5D82, 0x5DA2,
        0x5D9D, 0x5DAC, 0x5DAE, 0x5DBD, 0x5D90, 0x5DB7, 0x5DBC, 0x5DC9, 0x5DCD, 0x5DD3, 0x5DD2,
        0x5DD6, 0x5DDB, 0x5DEB, 0x5DF2, 0x5DF5, 0x5E0B, 0x5E1A, 0x5E19, 0x5E11, 0x5E1B, 0x5E36,
        0x5E37, 0x5E44, 0x5E43, 0x5E40, 0x5E4E, 0x5E57, 0x5E54, 0x5E5F, 0x5E62, 0x5E64, 0x5E47,
        0x5E75, 0x5E76, 0x5E7A, 0x9EBC, 0x5E7F, 0x5EA0, 0x5EC1, 0x5EC2, 0x5EC8, 0x5ED0, 0x5ECF,
        0x5ED6, 0x5EE3, 0x5EDD, 0x5EDA, 0x5EDB, 0x5EE2, 0x5EE1, 0x5EE8, 0x5EE9, 0x5EEC, 0x5EF1,
        0x5EF3, 0x5EF0, 0x5EF4, 0x5EF8, 0x5EFE, 0x5F03, 0x5F09, 0x5F5D, 0x5F5C, 0x5F0B, 0x5F11,
        0x5F16, 0x5F29, 0x5F2D, 0x5F38, 0x5F41, 0x5F48, 0x5F4C, 0x5F4E, 0x5F2F, 0x5F51, 0x5F56,
        0x5F57, 0x5F59, 0x5F61, 0x5F6D, 0x5F73, 0x5F77, 0x5F83, 0x5F82, 0x5F7F, 0x5F8A, 0x5F88,
        0x5F91, 0x5F87, 0x5F9E, 0x5F99, 0x5F98, 0x5FA0, 0x5FA8, 0x5FAD, 0x5FBC, 0x5FD6, 0x5FFB,
        0x5FE4, 0x5FF8, 0x5FF1, 0x5FDD, 0x60B3, 0x5FFF, 0x6021, 0x6060, 0x6019, 0x6010, 0x6029,
        0x600E, 0x6031, 0x601B, 0x6015, 0x602B, 0x6026, 0x600F, 0x603A, 0x605A, 0x6041, 0x606A,
        0x6077, 0x605F, 0x604A, 0x6046, 0x604D, 0x6063, 0x6043, 0x6064, 0x6042, 0x606C, 0x606B,
        0x6059, 0x6081, 0x608D, 0x60E7, 0x6083, 0x609A, 0x6084, 0x609B, 0x6096, 0x6097, 0x6092,
        0x60A7, 0x608B, 0x60E1, 0x60B8, 0x60E0, 0x60D3, 0x60B4, 0x5FF0, 0x60BD, 0x60C6, 0x60B5,
        0x60D8, 0x614D, 0x6115, 0x6106, 0x60F6, 0x60F7, 0x6100, 0x60F4, 0x60FA, 0x6103, 0x6121,
        0x60FB, 0x60F1, 0x610D, 0x610E, 0x6147, 0x613E, 0x6128, 0x6127, 0x614A, 0x613F, 0x613C,
        0x612C, 0x6134, 0x613D, 0x6142, 0x6144, 0x6173, 0x6177, 0x6158, 0x6159, 0x615A, 0x616B,
        0x6174, 0x616F, 0x6165, 0x6171, 0x615F, 0x615D, 0x6153, 0x6175, 0x6199, 0x6196, 0x6187,
        0x61AC, 0x6194, 0x619A, 0x618A, 0x6191, 0x61AB, 0x61AE, 0x61CC, 0x61CA, 0x61C9, 0x61F7,
        0x61C8, 0x61C3, 0x61C6, 0x61BA, 0x61CB, 0x7F79, 0x61CD, 0x61E6, 0x61E3, 0x61F6, 0x61FA,
        0x61F4, 0x61FF, 0x61FD, 0x61FC, 0x61FE, 0x6200, 0x6208, 0x6209, 0x620D, 0x620C, 0x6214,
        0x621B, 0x621E, 0x6221, 0x622A, 0x622E, 0x6230, 0x6232, 0x6233, 0x6241, 0x624E, 0x625E,
        0x6263, 0x625B, 0x6260, 0x6268, 0x627C, 0x6282, 0x6289, 0x627E, 0x6292, 0x6293, 0x6296,
        0x62D4, 0x6283, 0x6294, 0x62D7, 0x62D1, 0x62BB, 0x62CF, 0x62FF, 0x62C6, 0x64D4, 0x62C8,
        0x62DC, 0x62CC, 0x62CA, 0x62C2, 0x62C7, 0x629B, 0x62C9, 0x630C, 0x62EE, 0x62F1, 0x6327,
        0x6302, 0x6308, 0x62EF, 0x62F5, 0x6350, 0x633E, 0x634D, 0x641C, 0x634F, 0x6396, 0x638E,
        0x6380, 0x63AB, 0x6376, 0x63A3, 0x638F, 0x6389, 0x639F, 0x63B5, 0x636B, 0x6369, 0x63BE,
        0x63E9, 0x63C0, 0x63C6, 0x63E3, 0x63C9, 0x63D2, 0x63F6, 0x63C4, 0x6416, 0x6434, 0x6406,
        0x6413, 0x6426, 0x6436, 0x651D, 0x6417, 0x6428, 0x640F, 0x6467, 0x646F, 0x6476, 0x644E,
        0x652A, 0x6495, 0x6493, 0x64A5, 0x64A9, 0x6488, 0x64BC, 0x64DA, 0x64D2, 0x64C5, 0x64C7,
        0x64BB, 0x64D8, 0x64C2, 0x64F1, 0x64E7, 0x8209, 0x64E0, 0x64E1, 0x62AC, 0x64E3, 0x64EF,
        0x652C, 0x64F6, 0x64F4, 0x64F2, 0x64FA, 0x6500, 0x64FD, 0x6518, 0x651C, 0x6505, 0x6524,
        0x6523, 0x652B, 0x6534, 0x6535, 0x6537, 0x6536, 0x6538, 0x754B, 0x6548, 0x6556, 0x6555,
        0x654D, 0x6558, 0x655E, 0x655D, 0x6572, 0x6578, 0x6582, 0x6583, 0x8B8A, 0x659B, 0x659F,
        0x65AB, 0x65B7, 0x65C3, 0x65C6, 0x65C1, 0x65C4, 0x65CC, 0x65D2, 0x65DB, 0x65D9, 0x65E0,
        0x65E1, 0x65F1, 0x6772, 0x660A, 0x6603, 0x65FB, 0x6773, 0x6635, 0x6636, 0x6634, 0x661C,
        0x664F, 0x6644, 0x6649, 0x6641, 0x665E, 0x665D, 0x6664, 0x6667, 0x6668, 0x665F, 0x6662,
        0x6670, 0x6683, 0x6688, 0x668E, 0x6689, 0x6684, 0x6698, 0x669D, 0x66C1, 0x66B9, 0x66C9,
        0x66BE, 0x66BC, 0x66C4, 0x66B8, 0x66D6, 0x66DA, 0x66E0, 0x663F, 0x66E6, 0x66E9, 0x66F0,
        0x66F5, 0x66F7, 0x670F, 0x6716, 0x671E, 0x6726, 0x6727, 0x9738, 0x672E, 0x673F, 0x6736,
        0x6741, 0x6738, 0x6737, 0x6746, 0x675E, 0x6760, 0x6759, 0x6763, 0x6764, 0x6789, 0x6770,
        0x67A9, 0x677C, 0x676A, 0x678C, 0x678B, 0x67A6, 0x67A1, 0x6785, 0x67B7, 0x67EF, 0x67B4,
        0x67EC, 0x67B3, 0x67E9, 0x67B8, 0x67E4, 0x67DE, 0x67DD, 0x67E2, 0x67EE, 0x67B9, 0x67CE,
        0x67C6, 0x67E7, 0x6A9C, 0x681E, 0x6846, 0x6829, 0x6840, 0x684D, 0x6832, 0x684E, 0x68B3,
        0x682B, 0x6859, 0x6863, 0x6877, 0x687F, 0x689F, 0x688F, 0x68AD, 0x6894, 0x689D, 0x689B,
        0x6883, 0x6AAE, 0x68B9, 0x6874, 0x68B5, 0x68A0, 0x68BA, 0x690F, 0x688D, 0x687E, 0x6901,
        0x68CA, 0x6908, 0x68D8, 0x6922, 0x6926, 0x68E1, 0x690C, 0x68CD, 0x68D4, 0x68E7, 0x68D5,
        0x6936, 0x6912, 0x6904, 0x68D7, 0x68E3, 0x6925, 0x68F9, 0x68E0, 0x68EF, 0x6928, 0x692A,
        0x691A, 0x6923, 0x6921, 0x68C6, 0x6979, 0x6977, 0x695C, 0x6978, 0x696B, 0x6954, 0x697E,
        0x696E, 0x6939, 0x6974, 0x693D, 0x6959, 0x6930, 0x6961, 0x695E, 0x695D, 0x6981, 0x696A,
        0x69B2, 0x69AE, 0x69D0, 0x69BF, 0x69C1, 0x69D3, 0x69BE, 0x69CE, 0x5BE8, 0x69CA, 0x69DD,
        0x69BB, 0x69C3, 0x69A7, 0x6A2E, 0x6991, 0x69A0, 0x699C, 0x6995, 0x69B4, 0x69DE, 0x69E8,
        0x6A02, 0x6A1B, 0x69FF, 0x6B0A, 0x69F9, 0x69F2, 0x69E7, 0x6A05, 0x69B1, 0x6A1E, 0x69ED,
        0x6A14, 0x69EB, 0x6A0A, 0x6A12, 0x6AC1, 0x6A23, 0x6A13, 0x6A44, 0x6A0C, 0x6A72, 0x6A36,
        0x6A78, 0x6A47, 0x6A62, 0x6A59, 0x6A66, 0x6A48, 0x6A38, 0x6A22, 0x6A90, 0x6A8D, 0x6AA0,
        0x6A84, 0x6AA2, 0x6AA3, 0x6A97, 0x8617, 0x6ABB, 0x6AC3, 0x6AC2, 0x6AB8, 0x6AB3, 0x6AAC,
        0x6ADE, 0x6AD1, 0x6ADF, 0x6AAA, 0x6ADA, 0x6AEA, 0x6AFB, 0x6B05, 0x8616, 0x6AFA, 0x6B12,
        0x6B16, 0x9B31, 0x6B1F, 0x6B38, 0x6B37, 0x76DC, 0x6B39, 0x98EE, 0x6B47, 0x6B43, 0x6B49,
        0x6B50, 0x6B59, 0x6B54, 0x6B5B, 0x6B5F, 0x6B61, 0x6B78, 0x6B79, 0x6B7F, 0x6B80, 0x6B84,
        0x6B83, 0x6B8D, 0x6B98, 0x6B95, 0x6B9E, 0x6BA4, 0x6BAA, 0x6BAB, 0x6BAF, 0x6BB2, 0x6BB1,
        0x6BB3, 0x6BB7, 0x6BBC, 0x6BC6, 0x6BCB, 0x6BD3, 0x6BDF, 0x6BEC, 0x6BEB, 0x6BF3, 0x6BEF,
        0x9EBE, 0x6C08, 0x6C13, 0x6C14, 0x6C1B, 0x6C24, 0x6C23, 0x6C5E, 0x6C55, 0x6C62, 0x6C6A,
        0x6C82, 0x6C8D, 0x6C9A, 0x6C81, 0x6C9B, 0x6C7E, 0x6C68, 0x6C73, 0x6C92, 0x6C90, 0x6CC4,
        0x6CF1, 0x6CD3, 0x6CBD, 0x6CD7, 0x6CC5, 0x6CDD, 0x6CAE, 0x6CB1, 0x6CBE, 0x6CBA, 0x6CDB,
        0x6CEF, 0x6CD9, 0x6CEA, 0x6D1F, 0x884D, 0x6D36, 0x6D2B, 0x6D3D, 0x6D38, 0x6D19, 0x6D35,
        0x6D33, 0x6D12, 0x6D0C, 0x6D63, 0x6D93, 0x6D64, 0x6D5A, 0x6D79, 0x6D59, 0x6D8E, 0x6D95,
        0x6FE4, 0x6D85, 0x6DF9, 0x6E15, 0x6E0A, 0x6DB5, 0x6DC7, 0x6DE6, 0x6DB8, 0x6DC6, 0x6DEC,
        0x6DDE, 0x6DCC, 0x6DE8, 0x6DD2, 0x6DC5, 0x6DFA, 0x6DD9, 0x6DE4, 0x6DD5, 0x6DEA, 0x6DEE,
        0x6E2D, 0x6E6E, 0x6E2E, 0x6E19, 0x6E72, 0x6E5F, 0x6E3E, 0x6E23, 0x6E6B, 0x6E2B, 0x6E76,
        0x6E4D, 0x6E1F, 0x6E43, 0x6E3A, 0x6E4E, 0x6E24, 0x6EFF, 0x6E1D, 0x6E38, 0x6E82, 0x6EAA,
        0x6E98, 0x6EC9, 0x6EB7, 0x6ED3, 0x6EBD, 0x6EAF, 0x6EC4, 0x6EB2, 0x6ED4, 0x6ED5, 0x6E8F,
        0x6EA5, 0x6EC2, 0x6E9F, 0x6F41, 0x6F11, 0x704C, 0x6EEC, 0x6EF8, 0x6EFE, 0x6F3F, 0x6EF2,
        0x6F31, 0x6EEF, 0x6F32, 0x6ECC, 0x6F3E, 0x6F13, 0x6EF7, 0x6F86, 0x6F7A, 0x6F78, 0x6F81,
        0x6F80, 0x6F6F, 0x6F5B, 0x6FF3, 0x6F6D, 0x6F82, 0x6F7C, 0x6F58, 0x6F8E, 0x6F91, 0x6FC2,
        0x6F66, 0x6FB3, 0x6FA3, 0x6FA1, 0x6FA4, 0x6FB9, 0x6FC6, 0x6FAA, 0x6FDF, 0x6FD5, 0x6FEC,
        0x6FD4, 0x6FD8, 0x6FF1, 0x6FEE, 0x6FDB, 0x7009, 0x700B, 0x6FFA, 0x7011, 0x7001, 0x700F,
        0x6FFE, 0x701B, 0x701A, 0x6F74, 0x701D, 0x7018, 0x701F, 0x7030, 0x703E, 0x7032, 0x7051,
        0x7063, 0x7099, 0x7092, 0x70AF, 0x70F1, 0x70AC, 0x70B8, 0x70B3, 0x70AE, 0x70DF, 0x70CB,
        0x70DD, 0x70D9, 0x7109, 0x70FD, 0x711C, 0x7119, 0x7165, 0x7155, 0x7188, 0x7166, 0x7162,
        0x714C, 0x7156, 0x716C, 0x718F, 0x71FB, 0x7184, 0x7195, 0x71A8, 0x71AC, 0x71D7, 0x71B9,
        0x71BE, 0x71D2, 0x71C9, 0x71D4, 0x71CE, 0x71E0, 0x71EC, 0x71E7, 0x71F5, 0x71FC, 0x71F9,
        0x71FF, 0x720D, 0x7210, 0x721B, 0x7228, 0x722D, 0x722C, 0x7230, 0x7232, 0x723B, 0x723C,
        0x723F, 0x7240, 0x7246, 0x724B, 0x7258, 0x7274, 0x727E, 0x7282, 0x7281, 0x7287, 0x7292,
        0x7296, 0x72A2, 0x72A7, 0x72B9, 0x72B2, 0x72C3, 0x72C6, 0x72C4, 0x72CE, 0x72D2, 0x72E2,
        0x72E0, 0x72E1, 0x72F9, 0x72F7, 0x500F, 0x7317, 0x730A, 0x731C, 0x7316, 0x731D, 0x7334,
        0x732F, 0x7329, 0x7325, 0x733E, 0x734E, 0x734F, 0x9ED8, 0x7357, 0x736A, 0x7368, 0x7370,
        0x7378, 0x7375, 0x737B, 0x737A, 0x73C8, 0x73B3, 0x73CE, 0x73BB, 0x73C0, 0x73E5, 0x73EE,
        0x73DE, 0x74A2, 0x7405, 0x746F, 0x7425, 0x73F8, 0x7432, 0x743A, 0x7455, 0x743F, 0x745F,
        0x7459, 0x7441, 0x745C, 0x7469, 0x7470, 0x7463, 0x746A, 0x7476, 0x747E, 0x748B, 0x749E,
        0x74A7, 0x74CA, 0x74CF, 0x74D4, 0x73F1, 0x74E0, 0x74E3, 0x74E7, 0x74E9, 0x74EE, 0x74F2,
        0x74F0, 0x74F1, 0x74F8, 0x74F7, 0x7504, 0x7503, 0x7505, 0x750C, 0x750E, 0x750D, 0x7515,
        0x7513, 0x751E, 0x7526, 0x752C, 0x753C, 0x7544, 0x754D, 0x754A, 0x7549, 0x755B, 0x7546,
        0x755A, 0x7569, 0x7564, 0x7567, 0x756B, 0x756D, 0x7578, 0x7576, 0x7586, 0x7587, 0x7574,
        0x758A, 0x7589, 0x7582, 0x7594, 0x759A, 0x759D, 0x75A5, 0x75A3, 0x75C2, 0x75B3, 0x75C3,
        0x75B5, 0x75BD, 0x75B8, 0x75BC, 0x75B1, 0x75CD, 0x75CA, 0x75D2, 0x75D9, 0x75E3, 0x75DE,
        0x75FE, 0x75FF, 0x75FC, 0x7601, 0x75F0, 0x75FA, 0x75F2, 0x75F3, 0x760B, 0x760D, 0x7609,
        0x761F, 0x7627, 0x7620, 0x7621, 0x7622, 0x7624, 0x7634, 0x7630, 0x763B, 0x7647, 0x7648,
        0x7646, 0x765C, 0x7658, 0x7661, 0x7662, 0x7668, 0x7669, 0x766A, 0x7667, 0x766C, 0x7670,
        0x7672, 0x7676, 0x7678, 0x767C, 0x7680, 0x7683, 0x7688, 0x768B, 0x768E, 0x7696, 0x7693,
        0x7699, 0x769A, 0x76B0, 0x76B4, 0x76B8, 0x76B9, 0x76BA, 0x76C2, 0x76CD, 0x76D6, 0x76D2,
        0x76DE, 0x76E1, 0x76E5, 0x76E7, 0x76EA, 0x862F, 0x76FB, 0x7708, 0x7707, 0x7704, 0x7729,
        0x7724, 0x771E, 0x7725, 0x7726, 0x771B, 0x7737, 0x7738, 0x7747, 0x775A, 0x7768, 0x776B,
        0x775B, 0x7765, 0x777F, 0x777E, 0x7779, 0x778E, 0x778B, 0x7791, 0x77A0, 0x779E, 0x77B0,
        0x77B6, 0x77B9, 0x77BF, 0x77BC, 0x77BD, 0x77BB, 0x77C7, 0x77CD, 0x77D7, 0x77DA, 0x77DC,
        0x77E3, 0x77EE, 0x77FC, 0x780C, 0x7812, 0x7926, 0x7820, 0x792A, 0x7845, 0x788E, 0x7874,
        0x7886, 0x787C, 0x789A, 0x788C, 0x78A3, 0x78B5, 0x78AA, 0x78AF, 0x78D1, 0x78C6, 0x78CB,
        0x78D4, 0x78BE, 0x78BC, 0x78C5, 0x78CA, 0x78EC, 0x78E7, 0x78DA, 0x78FD, 0x78F4, 0x7907,
        0x7912, 0x7911, 0x7919, 0x792C, 0x792B, 0x7940, 0x7960, 0x7957, 0x795F, 0x795A, 0x7955,
        0x7953, 0x797A, 0x797F, 0x798A, 0x799D, 0x79A7, 0x9F4B, 0x79AA, 0x79AE, 0x79B3, 0x79B9,
        0x79BA, 0x79C9, 0x79D5, 0x79E7, 0x79EC, 0x79E1, 0x79E3, 0x7A08, 0x7A0D, 0x7A18, 0x7A19,
        0x7A20, 0x7A1F, 0x7980, 0x7A31, 0x7A3B, 0x7A3E, 0x7A37, 0x7A43, 0x7A57, 0x7A49, 0x7A61,
        0x7A62, 0x7A69, 0x9F9D, 0x7A70, 0x7A79, 0x7A7D, 0x7A88, 0x7A97, 0x7A95, 0x7A98, 0x7A96,
        0x7AA9, 0x7AC8, 0x7AB0, 0x7AB6, 0x7AC5, 0x7AC4, 0x7ABF, 0x9083, 0x7AC7, 0x7ACA, 0x7ACD,
        0x7ACF, 0x7AD5, 0x7AD3, 0x7AD9, 0x7ADA, 0x7ADD, 0x7AE1, 0x7AE2, 0x7AE6, 0x7AED, 0x7AF0,
        0x7B02, 0x7B0F, 0x7B0A, 0x7B06, 0x7B33, 0x7B18, 0x7B19, 0x7B1E, 0x7B35, 0x7B28, 0x7B36,
        0x7B50, 0x7B7A, 0x7B04, 0x7B4D, 0x7B0B, 0x7B4C, 0x7B45, 0x7B75, 0x7B65, 0x7B74, 0x7B67,
        0x7B70, 0x7B71, 0x7B6C, 0x7B6E, 0x7B9D, 0x7B98, 0x7B9F, 0x7B8D, 0x7B9C, 0x7B9A, 0x7B8B,
        0x7B92, 0x7B8F, 0x7B5D, 0x7B99, 0x7BCB, 0x7BC1, 0x7BCC, 0x7BCF, 0x7BB4, 0x7BC6, 0x7BDD,
        0x7BE9, 0x7C11, 0x7C14, 0x7BE6, 0x7BE5, 0x7C60, 0x7C00, 0x7C07, 0x7C13, 0x7BF3, 0x7BF7,
        0x7C17, 0x7C0D, 0x7BF6, 0x7C23, 0x7C27, 0x7C2A, 0x7C1F, 0x7C37, 0x7C2B, 0x7C3D, 0x7C4C,
        0x7C43, 0x7C54, 0x7C4F, 0x7C40, 0x7C50, 0x7C58, 0x7C5F, 0x7C64, 0x7C56, 0x7C65, 0x7C6C,
        0x7C75, 0x7C83, 0x7C90, 0x7CA4, 0x7CAD, 0x7CA2, 0x7CAB, 0x7CA1, 0x7CA8, 0x7CB3, 0x7CB2,
        0x7CB1, 0x7CAE, 0x7CB9, 0x7CBD, 0x7CC0, 0x7CC5, 0x7CC2, 0x7CD8, 0x7CD2, 0x7CDC, 0x7CE2,
        0x9B3B, 0x7CEF, 0x7CF2, 0x7CF4, 0x7CF6, 0x7CFA, 0x7D06, 0x7D02, 0x7D1C, 0x7D15, 0x7D0A,
        0x7D45, 0x7D4B, 0x7D2E, 0x7D32, 0x7D3F, 0x7D35, 0x7D46, 0x7D73, 0x7D56, 0x7D4E, 0x7D72,
        0x7D68, 0x7D6E, 0x7D4F, 0x7D63, 0x7D93, 0x7D89, 0x7D5B, 0x7D8F, 0x7D7D, 0x7D9B, 0x7DBA,
        0x7DAE, 0x7DA3, 0x7DB5, 0x7DC7, 0x7DBD, 0x7DAB, 0x7E3D, 0x7DA2, 0x7DAF, 0x7DDC, 0x7DB8,
        0x7D9F, 0x7DB0, 0x7DD8, 0x7DDD, 0x7DE4, 0x7DDE, 0x7DFB, 0x7DF2, 0x7DE1, 0x7E05, 0x7E0A,
        0x7E23, 0x7E21, 0x7E12, 0x7E31, 0x7E1F, 0x7E09, 0x7E0B, 0x7E22, 0x7E46, 0x7E66, 0x7E3B,
        0x7E35, 0x7E39, 0x7E43, 0x7E37, 0x7E32, 0x7E3A, 0x7E67, 0x7E5D, 0x7E56, 0x7E5E, 0x7E59,
        0x7E5A, 0x7E79, 0x7E6A, 0x7E69, 0x7E7C, 0x7E7B, 0x7E83, 0x7DD5, 0x7E7D, 0x8FAE, 0x7E7F,
        0x7E88, 0x7E89, 0x7E8C, 0x7E92, 0x7E90, 0x7E93, 0x7E94, 0x7E96, 0x7E8E, 0x7E9B, 0x7E9C,
        0x7F38, 0x7F3A, 0x7F45, 0x7F4C, 0x7F4D, 0x7F4E, 0x7F50, 0x7F51, 0x7F55, 0x7F54, 0x7F58,
        0x7F5F, 0x7F60, 0x7F68, 0x7F69, 0x7F67, 0x7F78, 0x7F82, 0x7F86, 0x7F83, 0x7F88, 0x7F87,
        0x7F8C, 0x7F94, 0x7F9E, 0x7F9D, 0x7F9A, 0x7FA3, 0x7FAF, 0x7FB2, 0x7FB9, 0x7FAE, 0x7FB6,
        0x7FB8, 0x8B71, 0x7FC5, 0x7FC6, 0x7FCA, 0x7FD5, 0x7FD4, 0x7FE1, 0x7FE6, 0x7FE9, 0x7FF3,
        0x7FF9, 0x98DC, 0x8006, 0x8004, 0x800B, 0x8012, 0x8018, 0x8019, 0x801C, 0x8021, 0x8028,
        0x803F, 0x803B, 0x804A, 0x8046, 0x8052, 0x8058, 0x805A, 0x805F, 0x8062, 0x8068, 0x8073,
        0x8072, 0x8070, 0x8076, 0x8079, 0x807D, 0x807F, 0x8084, 0x8086, 0x8085, 0x809B, 0x8093,
        0x809A, 0x80AD, 0x5190, 0x80AC, 0x80DB, 0x80E5, 0x80D9, 0x80DD, 0x80C4, 0x80DA, 0x80D6,
        0x8109, 0x80EF, 0x80F1, 0x811B, 0x8129, 0x8123, 0x812F, 0x814B, 0x968B, 0x8146, 0x813E,
        0x8153, 0x8151, 0x80FC, 0x8171, 0x816E, 0x8165, 0x8166, 0x8174, 0x8183, 0x8188, 0x818A,
        0x8180, 0x8182, 0x81A0, 0x8195, 0x81A4, 0x81A3, 0x815F, 0x8193, 0x81A9, 0x81B0, 0x81B5,
        0x81BE, 0x81B8, 0x81BD, 0x81C0, 0x81C2, 0x81BA, 0x81C9, 0x81CD, 0x81D1, 0x81D9, 0x81D8,
        0x81C8, 0x81DA, 0x81DF, 0x81E0, 0x81E7, 0x81FA, 0x81FB, 0x81FE, 0x8201, 0x8202, 0x8205,
        0x8207, 0x820A, 0x820D, 0x8210, 0x8216, 0x8229, 0x822B, 0x8238, 0x8233, 0x8240, 0x8259,
        0x8258, 0x825D, 0x825A, 0x825F, 0x8264, 0x8262, 0x8268, 0x826A, 0x826B, 0x822E, 0x8271,
        0x8277, 0x8278, 0x827E, 0x828D, 0x8292, 0x82AB, 0x829F, 0x82BB, 0x82AC, 0x82E1, 0x82E3,
        0x82DF, 0x82D2, 0x82F4, 0x82F3, 0x82FA, 0x8393, 0x8303, 0x82FB, 0x82F9, 0x82DE, 0x8306,
        0x82DC, 0x8309, 0x82D9, 0x8335, 0x8334, 0x8316, 0x8332, 0x8331, 0x8340, 0x8339, 0x8350,
        0x8345, 0x832F, 0x832B, 0x8317, 0x8318, 0x8385, 0x839A, 0x83AA, 0x839F, 0x83A2, 0x8396,
        0x8323, 0x838E, 0x8387, 0x838A, 0x837C, 0x83B5, 0x8373, 0x8375, 0x83A0, 0x8389, 0x83A8,
        0x83F4, 0x8413, 0x83EB, 0x83CE, 0x83FD, 0x8403, 0x83D8, 0x840B, 0x83C1, 0x83F7, 0x8407,
        0x83E0, 0x83F2, 0x840D, 0x8422, 0x8420, 0x83BD, 0x8438, 0x8506, 0x83FB, 0x846D, 0x842A,
        0x843C, 0x855A, 0x8484, 0x8477, 0x846B, 0x84AD, 0x846E, 0x8482, 0x8469, 0x8446, 0x842C,
        0x846F, 0x8479, 0x8435, 0x84CA, 0x8462, 0x84B9, 0x84BF, 0x849F, 0x84D9, 0x84CD, 0x84BB,
        0x84DA, 0x84D0, 0x84C1, 0x84C6, 0x84D6, 0x84A1, 0x8521, 0x84FF, 0x84F4, 0x8517, 0x8518,
        0x852C, 0x851F, 0x8515, 0x8514, 0x84FC, 0x8540, 0x8563, 0x8558, 0x8548, 0x8541, 0x8602,
        0x854B, 0x8555, 0x8580, 0x85A4, 0x8588, 0x8591, 0x858A, 0x85A8, 0x856D, 0x8594, 0x859B,
        0x85EA, 0x8587, 0x859C, 0x8577, 0x857E, 0x8590, 0x85C9, 0x85BA, 0x85CF, 0x85B9, 0x85D0,
        0x85D5, 0x85DD, 0x85E5, 0x85DC, 0x85F9, 0x860A, 0x8613, 0x860B, 0x85FE, 0x85FA, 0x8606,
        0x8622, 0x861A, 0x8630, 0x863F, 0x864D, 0x4E55, 0x8654, 0x865F, 0x8667, 0x8671, 0x8693,
        0x86A3, 0x86A9, 0x86AA, 0x868B, 0x868C, 0x86B6, 0x86AF, 0x86C4, 0x86C6, 0x86B0, 0x86C9,
        0x8823, 0x86AB, 0x86D4, 0x86DE, 0x86E9, 0x86EC, 0x86DF, 0x86DB, 0x86EF, 0x8712, 0x8706,
        0x8708, 0x8700, 0x8703, 0x86FB, 0x8711, 0x8709, 0x870D, 0x86F9, 0x870A, 0x8734, 0x873F,
        0x8737, 0x873B, 0x8725, 0x8729, 0x871A, 0x8760, 0x875F, 0x8778, 0x874C, 0x874E, 0x8774,
        0x8757, 0x8768, 0x876E, 0x8759, 0x8753, 0x8763, 0x876A, 0x8805, 0x87A2, 0x879F, 0x8782,
        0x87AF, 0x87CB, 0x87BD, 0x87C0, 0x87D0, 0x96D6, 0x87AB, 0x87C4, 0x87B3, 0x87C7, 0x87C6,
        0x87BB, 0x87EF, 0x87F2, 0x87E0, 0x880F, 0x880D, 0x87FE, 0x87F6, 0x87F7, 0x880E, 0x87D2,
        0x8811, 0x8816, 0x8815, 0x8822, 0x8821, 0x8831, 0x8836, 0x8839, 0x8827, 0x883B, 0x8844,
        0x8842, 0x8852, 0x8859, 0x885E, 0x8862, 0x886B, 0x8881, 0x887E, 0x889E, 0x8875, 0x887D,
        0x88B5, 0x8872, 0x8882, 0x8897, 0x8892, 0x88AE, 0x8899, 0x88A2, 0x888D, 0x88A4, 0x88B0,
        0x88BF, 0x88B1, 0x88C3, 0x88C4, 0x88D4, 0x88D8, 0x88D9, 0x88DD, 0x88F9, 0x8902, 0x88FC,
        0x88F4, 0x88E8, 0x88F2, 0x8904, 0x890C, 0x890A, 0x8913, 0x8943, 0x891E, 0x8925, 0x892A,
        0x892B, 0x8941, 0x8944, 0x893B, 0x8936, 0x8938, 0x894C, 0x891D, 0x8960, 0x895E, 0x8966,
        0x8964, 0x896D, 0x896A, 0x896F, 0x8974, 0x8977, 0x897E, 0x8983, 0x8988, 0x898A, 0x8993,
        0x8998, 0x89A1, 0x89A9, 0x89A6, 0x89AC, 0x89AF, 0x89B2, 0x89BA, 0x89BD, 0x89BF, 0x89C0,
        0x89DA, 0x89DC, 0x89DD, 0x89E7, 0x89F4, 0x89F8, 0x8A03, 0x8A16, 0x8A10, 0x8A0C, 0x8A1B,
        0x8A1D, 0x8A25, 0x8A36, 0x8A41, 0x8A5B, 0x8A52, 0x8A46, 0x8A48, 0x8A7C, 0x8A6D, 0x8A6C,
        0x8A62, 0x8A85, 0x8A82, 0x8A84, 0x8AA8, 0x8AA1, 0x8A91, 0x8AA5, 0x8AA6, 0x8A9A, 0x8AA3,
        0x8AC4, 0x8ACD, 0x8AC2, 0x8ADA, 0x8AEB, 0x8AF3, 0x8AE7, 0x8AE4, 0x8AF1, 0x8B14, 0x8AE0,
        0x8AE2, 0x8AF7, 0x8ADE, 0x8ADB, 0x8B0C, 0x8B07, 0x8B1A, 0x8AE1, 0x8B16, 0x8B10, 0x8B17,
        0x8B20, 0x8B33, 0x97AB, 0x8B26, 0x8B2B, 0x8B3E, 0x8B28, 0x8B41, 0x8B4C, 0x8B4F, 0x8B4E,
        0x8B49, 0x8B56, 0x8B5B, 0x8B5A, 0x8B6B, 0x8B5F, 0x8B6C, 0x8B6F, 0x8B74, 0x8B7D, 0x8B80,
        0x8B8C, 0x8B8E, 0x8B92, 0x8B93, 0x8B96, 0x8B99, 0x8B9A, 0x8C3A, 0x8C41, 0x8C3F, 0x8C48,
        0x8C4C, 0x8C4E, 0x8C50, 0x8C55, 0x8C62, 0x8C6C, 0x8C78, 0x8C7A, 0x8C82, 0x8C89, 0x8C85,
        0x8C8A, 0x8C8D, 0x8C8E, 0x8C94, 0x8C7C, 0x8C98, 0x621D, 0x8CAD, 0x8CAA, 0x8CBD, 0x8CB2,
        0x8CB3, 0x8CAE, 0x8CB6, 0x8CC8, 0x8CC1, 0x8CE4, 0x8CE3, 0x8CDA, 0x8CFD, 0x8CFA, 0x8CFB,
        0x8D04, 0x8D05, 0x8D0A, 0x8D07, 0x8D0F, 0x8D0D, 0x8D10, 0x9F4E, 0x8D13, 0x8CCD, 0x8D14,
        0x8D16, 0x8D67, 0x8D6D, 0x8D71, 0x8D73, 0x8D81, 0x8D99, 0x8DC2, 0x8DBE, 0x8DBA, 0x8DCF,
        0x8DDA, 0x8DD6, 0x8DCC, 0x8DDB, 0x8DCB, 0x8DEA, 0x8DEB, 0x8DDF, 0x8DE3, 0x8DFC, 0x8E08,
        0x8E09, 0x8DFF, 0x8E1D, 0x8E1E, 0x8E10, 0x8E1F, 0x8E42, 0x8E35, 0x8E30, 0x8E34, 0x8E4A,
        0x8E47, 0x8E49, 0x8E4C, 0x8E50, 0x8E48, 0x8E59, 0x8E64, 0x8E60, 0x8E2A, 0x8E63, 0x8E55,
        0x8E76, 0x8E72, 0x8E7C, 0x8E81, 0x8E87, 0x8E85, 0x8E84, 0x8E8B, 0x8E8A, 0x8E93, 0x8E91,
        0x8E94, 0x8E99, 0x8EAA, 0x8EA1, 0x8EAC, 0x8EB0, 0x8EC6, 0x8EB1, 0x8EBE, 0x8EC5, 0x8EC8,
        0x8ECB, 0x8EDB, 0x8EE3, 0x8EFC, 0x8EFB, 0x8EEB, 0x8EFE, 0x8F0A, 0x8F05, 0x8F15, 0x8F12,
        0x8F19, 0x8F13, 0x8F1C, 0x8F1F, 0x8F1B, 0x8F0C, 0x8F26, 0x8F33, 0x8F3B, 0x8F39, 0x8F45,
        0x8F42, 0x8F3E, 0x8F4C, 0x8F49, 0x8F46, 0x8F4E, 0x8F57, 0x8F5C, 0x8F62, 0x8F63, 0x8F64,
        0x8F9C, 0x8F9F, 0x8FA3, 0x8FAD, 0x8FAF, 0x8FB7, 0x8FDA, 0x8FE5, 0x8FE2, 0x8FEA, 0x8FEF,
        0x9087, 0x8FF4, 0x9005, 0x8FF9, 0x8FFA, 0x9011, 0x9015, 0x9021, 0x900D, 0x901E, 0x9016,
        0x900B, 0x9027, 0x9036, 0x9035, 0x9039, 0x8FF8, 0x904F, 0x9050, 0x9051, 0x9052, 0x900E,
        0x9049, 0x903E, 0x9056, 0x9058, 0x905E, 0x9068, 0x906F, 0x9076, 0x96A8, 0x9072, 0x9082,
        0x907D, 0x9081, 0x9080, 0x908A, 0x9089, 0x908F, 0x90A8, 0x90AF, 0x90B1, 0x90B5, 0x90E2,
        0x90E4, 0x6248, 0x90DB, 0x9102, 0x9112, 0x9119, 0x9132, 0x9130, 0x914A, 0x9156, 0x9158,
        0x9163, 0x9165, 0x9169, 0x9173, 0x9172, 0x918B, 0x9189, 0x9182, 0x91A2, 0x91AB, 0x91AF,
        0x91AA, 0x91B5, 0x91B4, 0x91BA, 0x91C0, 0x91C1, 0x91C9, 0x91CB, 0x91D0, 0x91D6, 0x91DF,
        0x91E1, 0x91DB, 0x91FC, 0x91F5, 0x91F6, 0x921E, 0x91FF, 0x9214, 0x922C, 0x9215, 0x9211,
        0x925E, 0x9257, 0x9245, 0x9249, 0x9264, 0x9248, 0x9295, 0x923F, 0x924B, 0x9250, 0x929C,
        0x9296, 0x9293, 0x929B, 0x925A, 0x92CF, 0x92B9, 0x92B7, 0x92E9, 0x930F, 0x92FA, 0x9344,
        0x932E, 0x9319, 0x9322, 0x931A, 0x9323, 0x933A, 0x9335, 0x933B, 0x935C, 0x9360, 0x937C,
        0x936E, 0x9356, 0x93B0, 0x93AC, 0x93AD, 0x9394, 0x93B9, 0x93D6, 0x93D7, 0x93E8, 0x93E5,
        0x93D8, 0x93C3, 0x93DD, 0x93D0, 0x93C8, 0x93E4, 0x941A, 0x9414, 0x9413, 0x9403, 0x9407,
        0x9410, 0x9436, 0x942B, 0x9435, 0x9421, 0x943A, 0x9441, 0x9452, 0x9444, 0x945B, 0x9460,
        0x9462, 0x945E, 0x946A, 0x9229, 0x9470, 0x9475, 0x9477, 0x947D, 0x945A, 0x947C, 0x947E,
        0x9481, 0x947F, 0x9582, 0x9587, 0x958A, 0x9594, 0x9596, 0x9598, 0x9599, 0x95A0, 0x95A8,
        0x95A7, 0x95AD, 0x95BC, 0x95BB, 0x95B9, 0x95BE, 0x95CA, 0x6FF6, 0x95C3, 0x95CD, 0x95CC,
        0x95D5, 0x95D4, 0x95D6, 0x95DC, 0x95E1, 0x95E5, 0x95E2, 0x9621, 0x9628, 0x962E, 0x962F,
        0x9642, 0x964C, 0x964F, 0x964B, 0x9677, 0x965C, 0x965E, 0x965D, 0x965F, 0x9666, 0x9672,
        0x966C, 0x968D, 0x9698, 0x9695, 0x9697, 0x96AA, 0x96A7, 0x96B1, 0x96B2, 0x96B0, 0x96B4,
        0x96B6, 0x96B8, 0x96B9, 0x96CE, 0x96CB, 0x96C9, 0x96CD, 0x894D, 0x96DC, 0x970D, 0x96D5,
        0x96F9, 0x9704, 0x9706, 0x9708, 0x9713, 0x970E, 0x9711, 0x970F, 0x9716, 0x9719, 0x9724,
        0x972A, 0x9730, 0x9739, 0x973D, 0x973E, 0x9744, 0x9746, 0x9748, 0x9742, 0x9749, 0x975C,
        0x9760, 0x9764, 0x9766, 0x9768, 0x52D2, 0x976B, 0x9771, 0x9779, 0x9785, 0x977C, 0x9781,
        0x977A, 0x9786, 0x978B, 0x978F, 0x9790, 0x979C, 0x97A8, 0x97A6, 0x97A3, 0x97B3, 0x97B4,
        0x97C3, 0x97C6, 0x97C8, 0x97CB, 0x97DC, 0x97ED, 0x9F4F, 0x97F2, 0x7ADF, 0x97F6, 0x97F5,
        0x980F, 0x980C, 0x9838, 0x9824, 0x9821, 0x9837, 0x983D, 0x9846, 0x984F, 0x984B, 0x986B,
        0x986F, 0x9870, 0x9871, 0x9874, 0x9873, 0x98AA, 0x98AF, 0x98B1, 0x98B6, 0x98C4, 0x98C3,
        0x98C6, 0x98E9, 0x98EB, 0x9903, 0x9909, 0x9912, 0x9914, 0x9918, 0x9921, 0x991D, 0x991E,
        0x9924, 0x9920, 0x992C, 0x992E, 0x993D, 0x993E, 0x9942, 0x9949, 0x9945, 0x9950, 0x994B,
        0x9951, 0x9952, 0x994C, 0x9955, 0x9997, 0x9998, 0x99A5, 0x99AD, 0x99AE, 0x99BC, 0x99DF,
        0x99DB, 0x99DD, 0x99D8, 0x99D1, 0x99ED, 0x99EE, 0x99F1, 0x99F2, 0x99FB, 0x99F8, 0x9A01,
        0x9A0F, 0x9A05, 0x99E2, 0x9A19, 0x9A2B, 0x9A37, 0x9A45, 0x9A42, 0x9A40, 0x9A43, 0x9A3E,
        0x9A55, 0x9A4D, 0x9A5B, 0x9A57, 0x9A5F, 0x9A62, 0x9A65, 0x9A64, 0x9A69, 0x9A6B, 0x9A6A,
        0x9AAD, 0x9AB0, 0x9ABC, 0x9AC0, 0x9ACF, 0x9AD1, 0x9AD3, 0x9AD4, 0x9ADE, 0x9ADF, 0x9AE2,
        0x9AE3, 0x9AE6, 0x9AEF, 0x9AEB, 0x9AEE, 0x9AF4, 0x9AF1, 0x9AF7, 0x9AFB, 0x9B06, 0x9B18,
        0x9B1A, 0x9B1F, 0x9B22, 0x9B23, 0x9B25, 0x9B27, 0x9B28, 0x9B29, 0x9B2A, 0x9B2E, 0x9B2F,
        0x9B32, 0x9B44, 0x9B43, 0x9B4F, 0x9B4D, 0x9B4E, 0x9B51, 0x9B58, 0x9B74, 0x9B93, 0x9B83,
        0x9B91, 0x9B96, 0x9B97, 0x9B9F, 0x9BA0, 0x9BA8, 0x9BB4, 0x9BC0, 0x9BCA, 0x9BB9, 0x9BC6,
        0x9BCF, 0x9BD1, 0x9BD2, 0x9BE3, 0x9BE2, 0x9BE4, 0x9BD4, 0x9BE1, 0x9C3A, 0x9BF2, 0x9BF1,
        0x9BF0, 0x9C15, 0x9C14, 0x9C09, 0x9C13, 0x9C0C, 0x9C06, 0x9C08, 0x9C12, 0x9C0A, 0x9C04,
        0x9C2E, 0x9C1B, 0x9C25, 0x9C24, 0x9C21, 0x9C30, 0x9C47, 0x9C32, 0x9C46, 0x9C3E, 0x9C5A,
        0x9C60, 0x9C67, 0x9C76, 0x9C78, 0x9CE7, 0x9CEC, 0x9CF0, 0x9D09, 0x9D08, 0x9CEB, 0x9D03,
        0x9D06, 0x9D2A, 0x9D26, 0x9DAF, 0x9D23, 0x9D1F, 0x9D44, 0x9D15, 0x9D12, 0x9D41, 0x9D3F,
        0x9D3E, 0x9D46, 0x9D48, 0x9D5D, 0x9D5E, 0x9D64, 0x9D51, 0x9D50, 0x9D59, 0x9D72, 0x9D89,
        0x9D87, 0x9DAB, 0x9D6F, 0x9D7A, 0x9D9A, 0x9DA4, 0x9DA9, 0x9DB2, 0x9DC4, 0x9DC1, 0x9DBB,
        0x9DB8, 0x9DBA, 0x9DC6, 0x9DCF, 0x9DC2, 0x9DD9, 0x9DD3, 0x9DF8, 0x9DE6, 0x9DED, 0x9DEF,
        0x9DFD, 0x9E1A, 0x9E1B, 0x9E1E, 0x9E75, 0x9E79, 0x9E7D, 0x9E81, 0x9E88, 0x9E8B, 0x9E8C,
        0x9E92, 0x9E95, 0x9E91, 0x9E9D, 0x9EA5, 0x9EA9, 0x9EB8, 0x9EAA, 0x9EAD, 0x9761, 0x9ECC,
        0x9ECE, 0x9ECF, 0x9ED0, 0x9ED4, 0x9EDC, 0x9EDE, 0x9EDD, 0x9EE0, 0x9EE5, 0x9EE8, 0x9EEF,
        0x9EF4, 0x9EF6, 0x9EF7, 0x9EF9, 0x9EFB, 0x9EFC, 0x9EFD, 0x9F07, 0x9F08, 0x76B7, 0x9F15,
        0x9F21, 0x9F2C, 0x9F3E, 0x9F4A, 0x9F52, 0x9F54, 0x9F63, 0x9F5F, 0x9F60, 0x9F61, 0x9F66,
        0x9F67, 0x9F6C, 0x9F6A, 0x9F77, 0x9F72, 0x9F76, 0x9F95, 0x9F9C, 0x9FA0, 0x582F, 0x69C7,
        0x9059, 0x7464, 0x51DC, 0x7199,
    ]

    /// JIS X 0201 片假名区（`ESC ( I`）：单字节 `21-5F` → 全角片假名 `U+FF61…`。
    private static let jis0201Katakana: [UInt32] = [
        0xFF61, 0xFF62, 0xFF63, 0xFF64, 0xFF65, 0xFF66, 0xFF67, 0xFF68, 0xFF69, 0xFF6A, 0xFF6B,
        0xFF6C, 0xFF6D, 0xFF6E, 0xFF6F, 0xFF70, 0xFF71, 0xFF72, 0xFF73, 0xFF74, 0xFF75, 0xFF76,
        0xFF77, 0xFF78, 0xFF79, 0xFF7A, 0xFF7B, 0xFF7C, 0xFF7D, 0xFF7E, 0xFF7F, 0xFF80, 0xFF81,
        0xFF82, 0xFF83, 0xFF84, 0xFF85, 0xFF86, 0xFF87, 0xFF88, 0xFF89, 0xFF8A, 0xFF8B, 0xFF8C,
        0xFF8D, 0xFF8E, 0xFF8F, 0xFF90, 0xFF91, 0xFF92, 0xFF93, 0xFF94, 0xFF95, 0xFF96, 0xFF97,
        0xFF98, 0xFF99, 0xFF9A, 0xFF9B, 0xFF9C, 0xFF9D, 0xFF9E, 0xFF9F,
    ]

    #if canImport(Darwin)
    /// `MALFORMED`/`UNMAPPABLE` 消耗语义逐字节对齐。
    ///
    /// 只在「整块解码失败」时才会走到（即输入确实含非法字节的少数样本）。
    ///
    /// ### 算法
    ///
    /// 每一步在位置 `i` 上先由 `MBCSProfile` 算出「这一段应该是几字节」：
    ///
    /// 1. 若 `bytes[i]` 是单字节有效值 → 吃 1 字节，用 CF 解出该字符；
    /// 2. 否则若 `bytes[i]` 是合法 lead 且**后续字节构成完整合法序列** → 吃整段（2/3/4 字节），
    ///    用 CF 解出；CF 解不出（JDK 判 `UNMAPPABLE` 但 Apple 表不同）→ 输出 1 个 `U+FFFD`；
    /// 3. 否则若 `bytes[i]` 是合法 lead 但 trail 落在**高位带** → `UNMAPPABLE[n]`：
    ///    吃整段，输出 1 个 `U+FFFD`；
    /// 4. 否则（含 trail 落低位带、lead 本身非法）→ `MALFORMED[1]`：吃 1 字节，输出 1 个 `U+FFFD`。
    ///
    /// 第 3/4 步的区分是本次修复的核心：旧实现一律「吃 1 字节」，导致每个 `UNMAPPABLE[2]`
    /// 位置都比 JDK 多出 1 个 `U+FFFD`（CI run `37211011044`：283 vs 234）。
    ///
    /// ### 与旧实现的对比
    ///
    /// 旧实现从 `min(maxCharLength, n-i)` 起**由长到短**试探「能否解出 1 个标量」，这在两处出错：
    /// - 窗口可能**跨过字符边界**：`maxCharLength=4` 时窗口含 4 字节，`0x80 0xE7 0xB0 0x87`
    ///   会被当成候选，而 Apple `GB_18030_2000` 把单个 `0x80` 解成 `U+20AC`（欧元符号），
    ///   于是一路降到 1 字节窗口后「成功」接受 —— JDK 在此给 `U+FFFD`（`0x80` 是非法单字节）。
    ///   真实 CI 实测：`utf8-chinese` 的 `decodedExplicitGbk` 在位置 79 处 Java `U+FFFD` /
    ///   旧 Swift `U+20AC`。
    /// - 只看「能否解出 1 个标量」而**不看消耗了几个字节**，无法复刻 `MALFORMED[1]` 与
    ///   `UNMAPPABLE[2]` 的差别。
    ///
    /// 新实现的两条不变量：
    /// - **单字节窗口只接受 `profile.isSingle(...)` 的字节**，因此 `0x80` 在 GB 系绝不可能是
    ///   「1 个字符」，只能走 `MALFORMED[1]`；
    /// - **窗口长度由字节结构决定，不由试探结果决定**，因此绝不跨字符边界、绝不吞掉后续 ASCII。
    ///
    /// 结果与 Java `new String(bytes, charset)` 的替换语义逐码位一致
    /// （真实 JVM 已核对：`0x97 0x2A` → `U+FFFD U+002A`；`AC E4` → 1 个 `U+FFFD`；
    /// `B8 80` → 1 个 `U+FFFD`）。
    private static func incrementalLossyDecode(_ bytes: [UInt8],
                                               cfEncoding: CFStringEncoding,
                                               profile: MBCSProfile,
                                               puaIsFailure: Bool = false) -> String {
        var out = ""
        var i = 0
        let n = bytes.count
        /// 把一段字节交出去解；解出恰好 1 个标量且（按需）不含 PUA 才算成功。
        ///
        /// ⚠️ **Big5 不走 CF**：`profile.useJdkBig5Table` 为 `true` 时，双字节序列直接查
        /// 内嵌的 JDK 严格 Big5 表（`lookupJdkBig5`）。Apple 的 `CFStringEncodings.big5`
        /// 是 CP950，与 JDK 严格表有 263 处值差 + 44 处「CP950 有值而 JDK 判不可映射」，
        /// 后者**无法用 `puaIsFailure` 表达**，只能以 JDK 表为准。
        func tryDecode(_ start: Int, _ len: Int) -> String? {
            guard start + len <= n else { return nil }
            if len == 2, profile.useJdkBig5Table {
                guard let scalar = Self.lookupJdkBig5(bytes[start], bytes[start + 1]),
                      let us = Unicode.Scalar(scalar) else { return nil }
                return String(us)
            }
            let slice = Array(bytes[start..<(start + len)])
            guard let s = decodeCFString(slice, cfEncoding: cfEncoding),
                  s.unicodeScalars.count == 1 else { return nil }
            if puaIsFailure && containsPrivateUse(s) { return nil }
            return s
        }
        while i < n {
            let b = bytes[i]
            // ⓪ 固定码元宽度（UTF-16 = 2 字节）：整体解 1 个码元。
            //
            // JDK 语义（`new String(bytes, "UTF-16LE")`）：
            //   - 每 `unitWidth` 字节为 1 个码元；高代理 + 低代理 → 1 个补充平面标量；
            //   - 孤立代理 → 1 个 U+FFFD（仍占满 1 个码元）；
            //   - 末尾不足 `unitWidth` 字节 → 1 个 U+FFFD。
            //
            // ⚠️ 必须**先于**下面的逐字节路径处理，否则代理对会被拆成两个半码元
            //（CI run `37219082032` 的 `ext-cn-3-utf-16be` 即因此多出 1 个标量）。
            if profile.unitWidth > 0 {
                let w = profile.unitWidth
                let avail = n - i
                if avail >= w {
                    let take = min(2 * w, avail)   // 尝试「码元对」以合并代理
                    if let s = tryDecode(i, take), s.unicodeScalars.count == 1 {
                        out += s; i += take; continue
                    }
                    if let s = tryDecode(i, w), s.unicodeScalars.count == 1 {
                        out += s; i += w; continue
                    }
                    // 该码元非法（孤立代理等）→ 1 个 U+FFFD，吃掉 1 个码元。
                    out += "\u{FFFD}"; i += w; continue
                } else {
                    // 末尾残字节（不足 1 个完整码元）→ 1 个 U+FFFD，全部吃掉。
                    out += "\u{FFFD}"; i = n; continue
                }
            }
            // ① 单字节
            if profile.isSingle(b) {
                if let s = tryDecode(i, 1) { out += s; i += 1; continue }
                // 理论上单字节合法段一定能解出；真解不出就按 U+FFFD 处理。
                out += "\u{FFFD}"; i += 1; continue
            }
            // ② 多字节：先由结构算出应有的长度
            var seqLen = 0
            var isUnmappableSeq = false
            // ⚠️ EUC-JP 的 `0x8E`/`0x8F` 也是 `0x80-0xFE` 的「lead」，但它们不是普通双字节
            // lead（`8E` 固定 2 字节、`8F` 固定 3 字节），必须**优先**交给下面的三字节分支处理，
            // 否则 `8F A1 A1` 会被当成普通 2 字节序列吃掉前两字节。
            let isSpecialPrefix = profile.threeByteLead.contains(b)
            if profile.isLead(b), !isSpecialPrefix {
                if i + 1 < n {
                    let t = bytes[i + 1]
                    if profile.isTrail(t) {
                        if profile.isMalformedException(b, t) {
                            // 映射区内的「洞」→ MALFORMED[1]（吃 1 字节），不进入下面的分支。
                            out += "\u{FFFD}"; i += 1; continue
                        }
                        if profile.isUnmappableException(b, t) {
                            // 形状像 trail、但码表无映射，且 JDK 判 `UNMAPPABLE[2]`（吃 **2** 字节）。
                            // 与上面的 `MALFORMED[1]` 唯一区别就是消耗字节数。EUC-JP 用它。
                            out += "\u{FFFD}"; i += 2; continue
                        }
                        seqLen = 2
                    } else if profile.isU2Trail(t) {
                        // trail 落 UNMAPPABLE 带 → 吃整段 2 字节，出 1 个 U+FFFD。
                        seqLen = 2
                        isUnmappableSeq = true
                    } else if profile.isM2Trail(t) {
                        // GB18030 的 `hi + 30-39`。
                        //
                        // ⚠️ 4 字节判定必须放在**这里**，不能放在 `isTrail(t)` 分支里：
                        // `30-39` 是数字，**不在 trail 区间**（trail 为 `40-7E`/`80-FE`），
                        // 所以 `isTrail(t)` 恒为 false。早期把它写在 trail 分支内，
                        // 导致 4 字节序列永远识别不出，被当成 `MALFORMED[2]` 吃掉 2 字节，
                        // 后续 `82 36` 等字节又各自失败 → 整段 `𠀀` 变成一个 6 连 U+FFFD
                        // （CI run `37219082032` 的 `gb18030-rare-han`/`decodedDefault`：
                        // Java `历史地名：𠀀𠀁𠀂 …` 20 码位 vs Swift 23 码位）。
                        //
                        // 命中条件 `b1 + b2(digit) + b3(lead) + b4(digit)` 时吃 4 字节；
                        // 否则（后续不构成合法 4 字节）JDK 报 `MALFORMED[2]`，吃 2 字节。
                        if let digit = profile.fourByteDigitRange,
                           i + 3 < n,
                           profile.isLead(bytes[i + 2]), digit.contains(bytes[i + 3]) {
                            seqLen = 4
                        } else {
                            seqLen = 2
                            isUnmappableSeq = true
                        }
                    }
                }
            }
            // EUC-JP 的 0x8E / 0x8F 前置形式（形如「半段序列」）
            //
            // 真实 JVM 探针（`JdkProf`/`C3`–`C6`，JDK 21）给出的**原子步**语义：
            //
            // | 输入 | JDK | 单向替换行为 |
            // |---|---|---|
            // | `8E` （缓冲只剩它） | `MALFORMED[1]` | 吃 1 → 1 个 U+FFFD |
            // | `8E X`，`X∈A1–DF` | 映射（半角片假名） | 吃 2 → 1 个字符 |
            // | `8E X`，其它 `X` | `UNMAPPABLE[2]` | 吃 2 → 1 个 U+FFFD |
            // | `8F` （缓冲只剩它） | `MALFORMED[1]` | 吃 1 → 1 个 U+FFFD |
            // | `8F X`（`i+2 >= n`） | `MALFORMED[2]` | 吃 2 → 1 个 U+FFFD |
            // | `8F X Y` | **恒按 3 字节**：`X,Y∈A1–FE` 且 JIS X 0212 有映射 → 1 个字符；否则 `UNMAPPABLE[3]` | 吃 3 → 1 个 U+FFFD |
            //
            // ⚠️ 旧实现只在「`X`、`Y` 都是合法 trail」时才吃 3 字节，其余落到 `MALFORMED[1]` 吃 1 字节 ——
            // 这正是 CI run `37212186047` 里 `euc-jp-japanese-2`/`decodedExplicitBig5` 位置 22 的
            // 偏差点（Java `U+3000` vs Swift `U+FFFD`）：`8F` 后面接的 2 字节形状不合法时，
            // JDK 仍**整体吃掉 3 字节**，而旧实现只吃 1 字节，此后所有位置都错位。
            //
            // 另注：`8E` 后的非法 trail 判 `UNMAPPABLE[2]`（吃 2），**不是** `MALFORMED[1]` ——
            // 探针 `8E 20 A1 A1` → `U+FFFD U+3000` 证实吃掉了 `8E 20` 两个字节。
            if seqLen == 0, profile.threeByteLead.contains(b), i + 1 < n {
                let t = bytes[i + 1]
                if b == 0x8E {
                    // 映射区（半角片假名）→ 2 字节；其余一律 UNMAPPABLE[2]（同样吃 2 字节）。
                    seqLen = 2
                    if !(t >= 0xA1 && t <= 0xDF) { isUnmappableSeq = true }
                } else {  // 0x8F：恒 3 字节
                    if i + 2 < n {
                        seqLen = 3
                        // 形状合法才可能映射；否则 UNMAPPABLE[3]。
                        let shapeOK = profile.isTrail(t) && profile.isTrail(bytes[i + 2])
                            && !profile.isMalformedException(b, t)
                            && !profile.isMalformedException(b, bytes[i + 2])
                        if !shapeOK { isUnmappableSeq = true }
                    } else {
                        // `8F X` 后缓冲不足 → MALFORMED[2]：吃 2 字节。
                        seqLen = 2
                        isUnmappableSeq = true
                    }
                }
            }
            if seqLen > 0 {
                if !isUnmappableSeq, let s = tryDecode(i, seqLen) {
                    out += s; i += seqLen; continue
                }
                // 序列合法（或 UNMAPPABLE 带）但码表无对应 → 1 个 U+FFFD，吃掉整段。
                out += "\u{FFFD}"; i += seqLen; continue
            }
            // ③ 这里只剩 MALFORMED[1]：lead 本身非法，或 trail 落低位带（00-3F / 7F）。
            out += "\u{FFFD}"; i += 1
        }
        return out
    }
    #endif

    /// 通用容错解码退路：对 Foundation 严格解码失败的字节，按「UTF-8 用 `String(decoding:)`
    /// 的替换字符语义；ISO-8859-1 逐字节映射」产出字符串。
    ///
    /// 这条路径只会在系统缺该编码（`cfEncoding == invalidId`）时进入，目的只有一个：
    /// **永不返回 nil**，从而保持 Java `new String(bytes, charset)` 的语义，不触发上游静默回落。
    private static func lossyFallback(_ bytes: [UInt8], nsEncoding: UInt) -> String? {
        switch nsEncoding {
        case NSUTF8StringEncoding:
            // 与 Java 的 UTF-8 解码一致：非法序列插入 U+FFFD。
            return String(decoding: bytes, as: UTF8.self)
        case NSISOLatin1StringEncoding:
            // ISO-8859-1 是全单字节映射：1 字节 = 1 个码位，永不失败。
            return String(bytes.map { Character(UnicodeScalar(UInt32($0))!) })
        default:
            // 编码在系统里不可用：按 UTF-8 替换语义兜底（不返回 nil）。
            return String(decoding: bytes, as: UTF8.self)
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
