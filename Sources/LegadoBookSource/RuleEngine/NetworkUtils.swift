//
//  NetworkUtils.swift
//  LegadoBookSource
//
//  对应 Kotlin: utils/NetworkUtils.kt 中 AnalyzeRule 依赖的子集：
//   - getAbsoluteURL(baseURL: String?, relativePath)
//   - getAbsoluteURL(baseURL: URL?, relativePath)
//   - getBaseUrl(url)
//   - isAbsUrl / isDataUrl（委托 LegadoStringUtils）
//
//  ⚠️ 关键：Kotlin 用 `java.net.URL(base, relative)` 做相对解析，其算法与 Swift 的
//  `URL(string:relativeTo:)` 不同（../、//host、?query 开头、空相对、含空格/中文等）。
//  本文件**不用 Swift Foundation URL 拼接**，而是按 java.net.URL 的 RFC 相对解析 + java 特例
//  自实现（见 resolve(base:relative:)）。最终正确性待 C 部分 golden（真实 java.net.URL 对照）验证。
//
//  —— 全局规范：绝不崩溃；解析失败返回 trim 后原串（对齐 Kotlin catch 分支）。
//

import Foundation

/// java.net.URL 的解析结果（scheme://authority/path?query#ref 的最小分解）。
public struct JavaURL {
    var scheme: String          // 不含 ":"，如 "http"
    var authority: String?      // host[:port]（可含 userinfo），可为 nil（如 file:）
    var path: String            // 以 "/" 开头或相对
    var query: String?          // 不含 "?"
    var ref: String?            // 不含 "#"

    /// 对齐 java.net.URL.toString()：scheme: + //authority + path + ?query + #ref
    func toURLString() -> String {
        var s = scheme + ":"
        if let a = authority {
            s += "//" + a
        }
        s += path
        if let q = query { s += "?" + q }
        if let r = ref { s += "#" + r }
        return s
    }
}

public enum NetworkUtils {

    // MARK: - 公共 API

    /// 对应 Kotlin: fun getAbsoluteURL(baseURL: String?, relativePath): String
    public static func getAbsoluteURL(_ baseURL: String?, _ relativePath: String) -> String {
        // 用 guard 展开可选值，替代原先的 `baseURL == nil || baseURL!.isEmpty` +
        // `baseURL!`（仓库硬规则禁止强解包）。
        guard let baseURL = baseURL, !baseURL.isEmpty else {
            return relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Kotlin: URL(baseURL.substringBefore(","))
        let base = substringBefore(baseURL, ",")
        let absoluteUrl = JavaURL.parse(base)   // 解析失败 -> nil（对齐 catch）
        return getAbsoluteURL(parsedBase: absoluteUrl, relativePath)
    }

    /// 对应 Kotlin: fun getAbsoluteURL(baseURL: URL?, relativePath): String
    /// Swift 用 JavaURL? 表达 java.net.URL?。（命名区分 String 重载，避免 nil 实参歧义。）
    static func getAbsoluteURL(parsedBase baseURL: JavaURL?, _ relativePath: String) -> String {
        let relativePathTrim = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let baseURL = baseURL else { return relativePathTrim }
        if LegadoStringUtils.isAbsUrl(relativePathTrim) { return relativePathTrim }
        if LegadoStringUtils.isDataUrl(relativePathTrim) { return relativePathTrim }
        if relativePathTrim.hasPrefix("javascript") { return "" }
        // Kotlin: URL(baseURL, relativePath) —— 注意用的是未 trim 的 relativePath（与 Kotlin 一致）
        if let parsed = JavaURL.resolve(base: baseURL, relative: relativePath) {
            return parsed.toURLString()
        }
        // catch 分支：返回 relativeUrl（初值 = relativePathTrim）
        return relativePathTrim
    }

    /// 便于测试：直接传字符串 base 和 relative 返回解析结果字符串。
    static func getAbsoluteURLDebug(base: String, relative: String) -> String {
        return getAbsoluteURL(base, relative)
    }

    /// 对应 Kotlin: fun getBaseUrl(url: String?): String?
    public static func getBaseUrl(_ url: String?) -> String? {
        guard let url = url else { return nil }
        let lower = url.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            // Kotlin: url.indexOf("/", 9)
            let ns = url as NSString
            if ns.length <= 9 {
                return url
            }
            let searchRange = NSRange(location: 9, length: ns.length - 9)
            let r = ns.range(of: "/", options: [], range: searchRange)
            if r.location == NSNotFound {
                return url
            }
            return ns.substring(to: r.location)
        }
        return nil
    }

    public static func isAbsUrl(_ s: String?) -> Bool { LegadoStringUtils.isAbsUrl(s) }
    public static func isDataUrl(_ s: String?) -> Bool { LegadoStringUtils.isDataUrl(s) }

    // MARK: - 辅助

    /// 对齐 Kotlin String.substringBefore(delimiter)：首个分隔符之前；无分隔符返回整串。
    static func substringBefore(_ s: String, _ delimiter: String) -> String {
        if let r = s.range(of: delimiter) {
            return String(s[s.startIndex..<r.lowerBound])
        }
        return s
    }
}
