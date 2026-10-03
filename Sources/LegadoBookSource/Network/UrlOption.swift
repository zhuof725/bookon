//
//  UrlOption.swift
//  LegadoBookSource
//
//  第 6 步 6A：AnalyzeUrl.UrlOption 的完整移植（含 Gson 的宽松解析语义）。
//
//  要点（对应 Kotlin 的 UrlOption + legado 的 GSON/GSONStrict 定制）：
//   - legado 的 INITIAL_GSON 给 String 注册了 StringJsonDeserializer（primitive -> asString，
//     null -> null，对象/数组 -> 紧凑 JSON 文本）、给 Int 注册了 IntJsonDeserializer
//     （只有 JSON number 才 toInt()，其它一律 null，不抛错）；数字用 ToNumberPolicy.LONG_OR_DOUBLE。
//   - `retry`/`serverID`/`webViewDelayTime` 的字段类型分别是 Int?/Long?/Long?：Int 有自定义适配器，
//     Long 没有（走 Gson 默认 nextLong：整数字面量或「整数文本的字符串」都行，3.5 会抛 -> 整个对象解析失败）。
//   - `headers`/`body`/`webView` 是 Any?，走 ObjectTypeAdapter。
//   - UrlOption 的 get*/set* 方法里只有 get* 参与 AnalyzeUrl（Gson 反射直接写字段，不调 set*）。
//
//  ⚠️ 已知差异：Gson 的 GSONStrict(STRICT) 与 GSON(LEGACY_STRICT) 的差别只在少数畸形输入上
//  （NaN/Infinity 等）；本移植用 strict/legacy 两次尝试模拟，具体覆盖见 golden 用例与 README 差异表。
//

import Foundation

/// 对应 Kotlin `AnalyzeUrl.UrlOption`。
public struct UrlOption: Equatable {

    // 字段（与 Kotlin 顺序一致）
    public var method: String?
    public var charset: String?
    /// Any?
    public var headers: GsonValue?
    /// Any?
    public var body: GsonValue?
    public var origin: String?
    public var retry: Int?
    public var type: String?
    /// Any?
    public var webView: GsonValue?
    public var webJs: String?
    public var dnsIp: String?
    public var js: String?
    public var bodyJs: String?
    public var serverID: Int64?
    public var webViewDelayTime: Int64?

    /// 是否走了「严格解析失败、宽松解析成功」的回退（对应 Kotlin 里那条 log）。
    public var usedLenientFallback = false

    public init() {}

    // MARK: - 解析

    /// 对应 `GSONStrict.fromJsonObject<UrlOption>(s)`；失败返回 nil。
    public static func parseStrict(_ json: String) -> UrlOption? {
        guard let value = GsonJSON.parseObject(json, lenient: false) else { return nil }
        return from(value)
    }

    /// 对应 `GSON.fromJsonObject<UrlOption>(s)`（宽松回退）。
    public static func parseLenient(_ json: String) -> UrlOption? {
        guard let value = GsonJSON.parseObject(json, lenient: true) else { return nil }
        return from(value)
    }

    /// 对应 AnalyzeUrl.analyzeUrl 里的两次尝试：先严格，失败再宽松（成功则标记回退）。
    public static func parse(_ json: String) -> UrlOption? {
        if let option = parseStrict(json) { return option }
        if var option = parseLenient(json) {
            option.usedLenientFallback = true
            return option
        }
        return nil
    }

    /// 按 Gson 的字段适配规则把 JsonObject 映射成 UrlOption。返回 nil 表示解析抛错（Gson 会抛）。
    static func from(_ value: GsonValue) -> UrlOption? {
        guard case .object = value else { return nil }
        var option = UrlOption()

        // String?：StringJsonDeserializer
        option.method = value.member("method")?.stringFieldValue
        option.charset = value.member("charset")?.stringFieldValue
        option.origin = value.member("origin")?.stringFieldValue
        option.type = value.member("type")?.stringFieldValue
        option.webJs = value.member("webJs")?.stringFieldValue
        option.dnsIp = value.member("dnsIp")?.stringFieldValue
        option.js = value.member("js")?.stringFieldValue
        option.bodyJs = value.member("bodyJs")?.stringFieldValue

        // Int?：IntJsonDeserializer（只有 number 才取 toInt，其它 null，不抛错）
        if let r = value.member("retry"), r.isNumber, case .number(let n) = r {
            option.retry = n.intValue
        }

        // Long?：Gson 默认 nextLong（整数或整数文本；小数/其它类型 -> 解析失败）
        if let s = value.member("serverID") {
            guard let parsed = longFieldValue(s) else { return nil }
            option.serverID = parsed
        }
        if let s = value.member("webViewDelayTime") {
            guard let parsed = longFieldValue(s) else { return nil }
            option.webViewDelayTime = parsed
        }

        // Any?：ObjectTypeAdapter（JSON null -> 字段为 null）
        if let h = value.member("headers"), h != .null { option.headers = h }
        if let b = value.member("body"), b != .null { option.body = b }
        if let w = value.member("webView"), w != .null { option.webView = w }

        return option
    }

    /// Gson `TypeAdapters.LONG`：number 必须能无损读成 long；string 必须是整数文本；其余抛错。
    private static func longFieldValue(_ v: GsonValue) -> Int64?? {
        switch v {
        case .null: return .some(nil) // JSON null -> 字段 null，正常
        case .number(.long(let l)): return .some(.some(l))
        case .number(.double): return nil  // 3.5 / 3.0 都会让 nextLong 抛错
        case .string(let s):
            // Gson nextLong 允许带引号的整数文本
            if let l = Int64(s) { return .some(.some(l)) }
            return nil
        default: return nil
        }
    }

    // MARK: - getter（与 Kotlin 一一对应；setter 不参与解析，故不移植）

    public func getMethod() -> String? { method }
    public func getCharset() -> String? { charset }
    public func getOrigin() -> String? { origin }
    public func getRetry() -> Int { retry ?? 0 }
    public func getType() -> String? { type }
    public func getWebJs() -> String? { webJs }
    public func getDnsIp() -> String? { dnsIp }
    public func getJs() -> String? { js }
    public func getBodyJs() -> String? { bodyJs }
    public func getServerID() -> Int64? { serverID }
    public func getWebViewDelayTime() -> Int64? { webViewDelayTime }

    /// 对应 Kotlin `useWebView()`：null/""/false/"false" 为 false，其余（含 0、"0"）为 true。
    public func useWebView() -> Bool {
        switch webView {
        case nil: return false
        case .some(.string("")): return false
        case .some(.bool(false)): return false
        case .some(.string("false")): return false
        default: return true
        }
    }

    /// 对应 Kotlin `getHeaderMap()`：Map 直接用；String 再解析成 Map；其它 null。
    /// 返回有序数组（Kotlin Map 的遍历顺序 = LinkedTreeMap 插入顺序）。
    public func getHeaderMap() -> [(String, String)]? {
        switch headers {
        case .some(.object(let entries)):
            return entries.map { ($0.0, UrlOption.javaToString($0.1)) }
        case .some(.string(let s)):
            guard let v = GsonJSON.parseObject(s, lenient: false),
                  case .object(let entries) = v else { return nil }
            return entries.map { ($0.0, UrlOption.javaToString($0.1)) }
        default:
            return nil
        }
    }

    /// 对应 Kotlin `getBody()`：String 原样，其它用 GSON.toJson 重新序列化（紧凑 + 键序保持）。
    public func getBody() -> String? {
        guard let b = body else { return nil }
        switch b {
        case .string(let s): return s
        default: return b.jsonText
        }
    }

    /// Kotlin 的 `Any.toString()`（Java 语义）：Map -> `{k=v}`、List -> `[a, b]`、
    /// Double -> Java Double.toString、null -> "null"。
    static func javaToString(_ v: GsonValue) -> String {
        switch v {
        case .string(let s): return s
        case .number(let n):
            switch n {
            case .long(let l): return String(l)
            case .double(let d): return JavaDoubleFormat.string(d)
            }
        case .bool(let b): return b ? "true" : "false"
        case .null: return "null"
        case .array(let arr): return "[" + arr.map { javaToString($0) }.joined(separator: ", ") + "]"
        case .object(let entries):
            return "{" + entries.map { "\($0.0)=\(javaToString($0.1))" }.joined(separator: ", ") + "}"
        }
    }
}
