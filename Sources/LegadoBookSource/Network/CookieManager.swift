//
//  CookieManager.swift
//  LegadoBookSource
//
//  第 6 步 6A：help/http/CookieManager.kt 的纯逻辑移植。
//
//  对应 Kotlin object CookieManager：
//   - mergeCookies(vararg) / mergeCookiesToMap(vararg)：后面的覆盖前面的（键相同）；
//   - getSessionCookie(domain) / updateSessionCookie(domain, cookies)：走 CacheManager 内存键
//     `"<domain>_session_cookie"`；
//   - saveCookiesFromHeaders(url, setCookieHeaders)：对应 Kotlin 的 `Cookie.parseAll` +
//     持久化/会话分流（**持久化判定 = 带 Expires 或 Max-Age**）；
//   - loadRequest 等价物 `cookieHeaderFor(url:existingHeader:)`：把请求头里的 Cookie 与存储合并；
//   - removeCookie(url, key)：从 session map 与持久化 cookie 里删掉一个键；
//   - getCookieNoSession(url)：委托 CookieStore。
//
//  ⚠️ 已知差异（README 登记）：
//   1. Kotlin 用 okhttp 的 Cookie.parseAll 解析 Set-Cookie（含 domain/path/expires 属性校验），
//      本移植只解析 name=value 与「是否持久化」两项——书源请求用到的 Cookie 语义只需这两项；
//   2. applyToWebView / android.webkit.CookieManager 不适用（无 WebView）。
//

import Foundation

/// 对应 Kotlin `object CookieManager`。
public final class CookieManager {

    /// 书源启用 cookieJar 时加在请求头上的标记（Kotlin: `const val cookieJarHeader = "CookieJar"`）。
    public static let cookieJarHeader = "CookieJar"

    /// 一条 Set-Cookie 的解析结果（Kotlin 用 okhttp Cookie 表示）。
    public struct ParsedCookie: Equatable {
        public var name: String
        public var value: String
        /// 持久化 = 带 Expires 或 Max-Age（Kotlin: `cookie.persistent`）
        public var persistent: Bool
    }

    // MARK: - 合并（纯函数）

    public static func mergeCookies(_ cookies: String?...) -> String? {
        return CookieMerge.mergeCookies(cookies)
    }

    public static func mergeCookiesToMap(_ cookies: String?...) -> [(String, String)] {
        var map: [(String, String)] = []
        for c in cookies {
            guard let c = c else { continue }
            for (k, v) in CookieMerge.cookieToMap(c) {
                if let idx = map.firstIndex(where: { $0.0 == k }) { map[idx].1 = v } else { map.append((k, v)) }
            }
        }
        return map
    }

    public static func cookieToMap(_ cookie: String) -> [(String, String)] {
        return CookieMerge.cookieToMap(cookie)
    }

    public static func mapToCookie(_ map: [(String, String)]) -> String? {
        return CookieMerge.mapToCookie(map)
    }

    // MARK: - session cookie

    public static func getSessionCookie(_ domain: String, cache: CacheManager) -> String? {
        return cache.getFromMemory("\(domain)_session_cookie") as? String
    }

    public static func updateSessionCookie(_ domain: String, cookies: String, cache: CacheManager) {
        let sessionCookie = getSessionCookie(domain, cache: cache)
        if sessionCookie == nil || (sessionCookie ?? "").isEmpty {
            cache.putMemory("\(domain)_session_cookie", cookies)
            return
        }
        guard let merged = mergeCookies(sessionCookie, cookies) else { return }
        cache.putMemory("\(domain)_session_cookie", merged)
    }

    // MARK: - Set-Cookie 解析

    /// 解析单条 Set-Cookie 头。对应 okhttp `Cookie.parse` 的最小子集。
    public static func parseSetCookie(_ header: String) -> ParsedCookie? {
        let firstPart = header.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? header
        let equalsIdx = firstPart.firstIndex(of: "=")
        guard let idx = equalsIdx else { return nil }
        let name = String(firstPart[firstPart.startIndex..<idx]).trimmingCharacters(in: .whitespaces)
        let value = String(firstPart[firstPart.index(after: idx)...]).trimmingCharacters(in: .whitespaces)
        if name.isEmpty { return nil }
        let lower = header.lowercased()
        let persistent = lower.contains("expires=") || lower.contains("max-age=")
        return ParsedCookie(name: name, value: value, persistent: persistent)
    }

    /// 对应 Kotlin `saveCookiesFromHeaders(url, headers)`：
    /// 持久化 cookie 走 CookieStore.replaceCookie(domain, ...)，会话 cookie 存内存。
    @discardableResult
    public static func saveCookiesFromHeaders(url: String,
                                              setCookieHeaders: [String],
                                              store: CookieStore,
                                              cache: CacheManager) -> [ParsedCookie] {
        let domain = NetworkUtils.getSubDomain(url)
        var parsed: [ParsedCookie] = []
        for h in setCookieHeaders {
            if let c = parseSetCookie(h) { parsed.append(c) }
        }
        let sessionCookies = parsed.filter { !$0.persistent }
        let persistentCookies = parsed.filter { $0.persistent }
        if !sessionCookies.isEmpty {
            let sessionStr = sessionCookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
            updateSessionCookie(domain, cookies: sessionStr, cache: cache)
        }
        if !persistentCookies.isEmpty {
            let persistentStr = persistentCookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
            store.replaceCookie(domain, persistentStr)
        }
        return parsed
    }

    // MARK: - 请求侧

    /// 对应 Kotlin `loadRequest(request)`：把现有 Cookie 头与存储的 cookie 合并。
    /// 返回 nil 表示保持原请求头不变。
    public static func cookieHeaderFor(url: String, existingHeader: String?, store: CookieStore, cache: CacheManager) -> String? {
        let domain = NetworkUtils.getSubDomain(url)
        let cookie = store.getCookieNoSession(url)
        _ = domain
        let session = getSessionCookie(NetworkUtils.getSubDomain(url), cache: cache)
        var map: [(String, String)] = []
        for part in [existingHeader, cookie, session] {
            guard let part = part, !part.isEmpty else { continue }
            for (k, v) in CookieMerge.cookieToMap(part) {
                if let idx = map.firstIndex(where: { $0.0 == k }) { map[idx].1 = v } else { map.append((k, v)) }
            }
        }
        return CookieMerge.mapToCookie(map)
    }

    // MARK: - 删除

    /// 对应 Kotlin `removeCookie(url, key)`：session map 与持久化 cookie 各删一个键。
    public static func removeCookie(_ url: String, key: String, store: CookieStore, cache: CacheManager) {
        let domain = NetworkUtils.getSubDomain(url)
        if let session = getSessionCookie(domain, cache: cache) {
            var map = CookieMerge.cookieToMap(session)
            map.removeAll { $0.0 == key }
            if let newCookie = CookieMerge.mapToCookie(map) {
                cache.putMemory("\(domain)_session_cookie", newCookie)
            }
        }
        let cookie = store.getCookieNoSession(url)
        if !cookie.isEmpty {
            var map = CookieMerge.cookieToMap(cookie)
            map.removeAll { $0.0 == key }
            if let newCookie = CookieMerge.mapToCookie(map) {
                store.setCookie(url, newCookie)
            }
        }
    }

    /// 对应 Kotlin `getCookieNoSession(url)`（转发到 CookieStore）。
    public static func getCookieNoSession(_ url: String, store: CookieStore) -> String {
        return store.getCookieNoSession(url)
    }
}
