//
//  CookieStore.swift
//  LegadoBookSource
//
//  第 6 步 6A：help/http/CookieStore.kt 的纯逻辑移植（协议 + 内存 + 文件实现）。
//
//  对应 Kotlin object CookieStore：
//   - setCookie(url, cookie)：按二级域名（NetworkUtils.getSubDomain）归属，写内存 + 持久化；
//   - replaceCookie(url, cookie)：老 cookie 为空则直接 set，否则按键合并后 set；
//   - getCookie(url)：持久化 cookie 与 session cookie 合并；**长度 > 4096 时循环删键**直到降下来；
//   - getKey(url, key)、removeCookie(url)、clear()、cookieToMap / mapToCookie。
//
//  ⚠️ 已知差异（README 登记）：
//   1. Kotlin 的 4096 截断用 `cookieMap.keys.random()`（随机删），本移植改为「按插入顺序删第一个」，
//      以保证行为可复现（语义同为"降到 4096 以下"；golden 用长度可控的用例对照）；
//   2. Kotlin 的持久化是 Room（appDb.cookieDao），本移植用「协议 + 单 JSON 文件原子写」；
//   3. setWebCookie / android.webkit.CookieManager 相关分支不适用（无 WebView）。
//

import Foundation

/// 持久化接口（对应 Kotlin `appDb.cookieDao`）。
public protocol CookiePersistenceProtocol: AnyObject {
    func get(domain: String) throws -> String?
    func insert(domain: String, cookie: String) throws
    func delete(domain: String) throws
    func clearAll() throws
}

public extension CookiePersistenceProtocol {
    func clearAll() throws {}
}

public final class MemoryCookiePersistence: CookiePersistenceProtocol, @unchecked Sendable {
    private var map: [String: String] = [:]
    private let lock = NSLock()
    public init() {}
    public func get(domain: String) throws -> String? {
        lock.lock(); defer { lock.unlock() }
        return map[domain]
    }
    public func insert(domain: String, cookie: String) throws {
        lock.lock(); defer { lock.unlock() }
        map[domain] = cookie
    }
    public func delete(domain: String) throws {
        lock.lock(); defer { lock.unlock() }
        map.removeValue(forKey: domain)
    }
    public func clearAll() throws {
        lock.lock(); defer { lock.unlock() }
        map.removeAll()
    }
}

/// 文件实现（JSON，原子写）。
public final class FileCookiePersistence: CookiePersistenceProtocol, @unchecked Sendable {
    private let fileURL: URL
    private let lock = NSLock()
    public init(fileURL: URL) { self.fileURL = fileURL }

    private func load() -> [String: String] {
        guard let data = try? Data(contentsOf: fileURL),
              let map = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return map
    }
    private func save(_ map: [String: String]) throws {
        let data = try JSONEncoder().encode(map)
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let tmp = dir.appendingPathComponent("\(fileURL.lastPathComponent).tmp")
        try data.write(to: tmp, options: .atomic)
        if FileManager.default.fileExists(atPath: fileURL.path) {
            _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: tmp)
        } else {
            try FileManager.default.moveItem(at: tmp, to: fileURL)
        }
    }

    public func get(domain: String) throws -> String? {
        lock.lock(); defer { lock.unlock() }
        return load()[domain]
    }
    public func insert(domain: String, cookie: String) throws {
        lock.lock(); defer { lock.unlock() }
        var map = load(); map[domain] = cookie; try save(map)
    }
    public func delete(domain: String) throws {
        lock.lock(); defer { lock.unlock() }
        var map = load(); map.removeValue(forKey: domain); try save(map)
    }
    public func clearAll() throws {
        lock.lock(); defer { lock.unlock() }
        try save([:])
    }
}

/// 对应 Kotlin `object CookieStore`。
public final class CookieStore: CookieStoreProtocol, @unchecked Sendable {
    /// 单个 cookie 串的长度上限（Kotlin: 4096）。
    public static let maxCookieLength = 4096

    private let persistence: CookiePersistenceProtocol
    private let cache: CacheManager
    private let diagnostics: RuleEngineDiagnostics?

    public init(persistence: CookiePersistenceProtocol = MemoryCookiePersistence(),
                cache: CacheManager = CacheManager(),
                diagnostics: RuleEngineDiagnostics? = nil) {
        self.persistence = persistence
        self.cache = cache
        self.diagnostics = diagnostics
    }

    // MARK: - 纯函数（对应 cookieToMap / mapToCookie）

    /// 对应 Kotlin `CookieStore.cookieToMap`（保序数组承载 LinkedHashMap 语义）。
    public static func cookieToMap(_ cookie: String) -> [(String, String)] {
        return CookieMerge.cookieToMap(cookie)
    }

    /// 对应 Kotlin `CookieStore.mapToCookie`（空 -> nil）。
    public static func mapToCookie(_ map: [(String, String)]) -> String? {
        return CookieMerge.mapToCookie(map)
    }

    // MARK: - 存取

    /// 对应 Kotlin `setCookie(url, cookie)`。
    public func setCookie(_ url: String, _ cookie: String?) {
        let domain = NetworkUtils.getSubDomain(url)
        cache.putMemory("\(domain)_cookie", cookie ?? "")
        do {
            try persistence.insert(domain: domain, cookie: cookie ?? "")
        } catch {
            diagnostics?.record(source: "CookieStore.setCookie", rule: url, message: "保存 Cookie 失败：\(error)")
        }
    }

    /// 对应 Kotlin `replaceCookie(url, cookie)`。
    public func replaceCookie(_ url: String, _ cookie: String) {
        if url.isEmpty || cookie.isEmpty { return }
        let old = getCookieNoSession(url)
        if old.isEmpty {
            setCookie(url, cookie)
        } else {
            var map = CookieStore.cookieToMap(old)
            for (k, v) in CookieStore.cookieToMap(cookie) {
                if let idx = map.firstIndex(where: { $0.0 == k }) { map[idx].1 = v } else { map.append((k, v)) }
            }
            if let newCookie = CookieStore.mapToCookie(map) {
                setCookie(url, newCookie)
            }
        }
    }

    /// 对应 Kotlin `getCookie(url)`：持久化 + session 合并，超过 4096 循环删键。
    public func getCookie(_ url: String) -> String {
        let domain = NetworkUtils.getSubDomain(url)
        let cookie = getCookieNoSession(url)
        let sessionCookie = CookieManager.getSessionCookie(domain, cache: cache)
        var map: [(String, String)] = []
        for part in [cookie, sessionCookie] {
            guard let part = part else { continue }
            for (k, v) in CookieStore.cookieToMap(part) {
                if let idx = map.firstIndex(where: { $0.0 == k }) { map[idx].1 = v } else { map.append((k, v)) }
            }
        }
        var ck = CookieStore.mapToCookie(map) ?? ""
        while ck.utf16.count > CookieStore.maxCookieLength, !map.isEmpty {
            // Kotlin: cookieMap.keys.random() 随机删；本移植按插入顺序删第一个（可复现，README 登记）
            let removeKey = map[0].0
            CookieManager.removeCookie(url, key: removeKey, store: self, cache: cache)
            map.removeAll { $0.0 == removeKey }
            ck = CookieStore.mapToCookie(map) ?? ""
        }
        return ck
    }

    /// 对应 Kotlin `getKey(url, key)`。
    public func getKey(_ url: String, _ key: String) -> String {
        let cookie = getCookie(url)
        let sessionCookie = CookieManager.getSessionCookie(url, cache: cache)
        var map: [(String, String)] = []
        for part in [cookie, sessionCookie] {
            guard let part = part else { continue }
            for (k, v) in CookieStore.cookieToMap(part) {
                if let idx = map.firstIndex(where: { $0.0 == k }) { map[idx].1 = v } else { map.append((k, v)) }
            }
        }
        return map.first { $0.0 == key }?.1 ?? ""
    }

    /// 对应 Kotlin `getCookieNoSession(url)`：内存缓存优先，否则持久化。
    public func getCookieNoSession(_ url: String) -> String {
        let domain = NetworkUtils.getSubDomain(url)
        if let cached = cache.getFromMemory("\(domain)_cookie") as? String {
            return cached
        }
        return (try? persistence.get(domain: domain)) ?? ""
    }

    /// 对应 Kotlin `removeCookie(url)`：清持久化 + 两个内存键（WebView 分支不适用）。
    public func removeCookie(_ url: String) {
        let domain = NetworkUtils.getSubDomain(url)
        try? persistence.delete(domain: domain)
        cache.deleteMemory("\(domain)_cookie")
        cache.deleteMemory("\(domain)_session_cookie")
    }

    /// 对应 Kotlin `clear()`：清持久化（Android 侧只清 okhttp 的 cookie 行）。
    public func clear() {
        try? persistence.clearAll()
        cache.clearMemory()
    }
}
