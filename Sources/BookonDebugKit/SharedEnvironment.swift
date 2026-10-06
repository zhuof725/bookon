//
//  SharedEnvironment.swift
//  BookonDebugKit
//
//  第 7 步 C 段返工：App 内**唯一共享**的 Cookie / 缓存实例。
//
//  背景：此前 DebugView.makeHTTPClient() 每次 new 一个内存 CookieStore()/CacheManager()，
//  导致 Cookie 与缓存既不能跨次调试保留，设置页的「清除」也清不到真正的实例。
//  现在改为：持久化文件固定在 Documents 下（与 sources.json / logs 同目录），
//  整个 App 共用同一个实例，跨次启动保留；设置页的清除按钮清的就是这些实例。
//
//  ⚠️ 已知差异（README 登记）：第 6 步 CacheManager 的默认路径是 .cachesDirectory，
//  本 App 为「跨次调试保留」显式改用 Documents，语义仍是同一份 JSON 缓存文件。
//

import Foundation
import LegadoBookSource

/// App 共享的持久化环境（Cookie + 缓存）。
///
/// 用 `public final class` + 可注入目录，便于：
///  - App 运行时用 `Documents` 下的固定文件（`makeDefault()`）；
///  - 测试用临时目录构造独立实例，互不干扰。
public final class SharedEnvironment {

    /// 共享 Cookie 存储（文件持久化）。
    public let cookieStore: CookieStore
    /// 共享缓存管理器（文件持久化 + 内存 LRU）。
    public let cacheManager: CacheManager

    /// 用于「清除缓存」时同时清空内存与磁盘。
    public init(cookieFileURL: URL, cacheFileURL: URL) {
        let cache = CacheManager(storage: FileCacheStorage(fileURL: cacheFileURL))
        self.cacheManager = cache
        // CookieStore 复用同一个 CacheManager（Kotlin 里两者也是同一份内存缓存）。
        self.cookieStore = CookieStore(
            persistence: FileCookiePersistence(fileURL: cookieFileURL),
            cache: cache
        )
    }

    /// Documents 默认目录（App 运行时用）。
    public static func defaultDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
    }

    /// Documents 下的 cookie 文件 URL。
    public static func defaultCookieFileURL() -> URL {
        defaultDirectory().appendingPathComponent("cookies.json")
    }

    /// Documents 下的缓存文件 URL。
    public static func defaultCacheFileURL() -> URL {
        defaultDirectory().appendingPathComponent("legado_cache.json")
    }

    /// 用 Documents 下固定路径构造（App 启动时调用一次，全局共用）。
    public static func makeDefault() -> SharedEnvironment {
        SharedEnvironment(
            cookieFileURL: defaultCookieFileURL(),
            cacheFileURL: defaultCacheFileURL()
        )
    }

    // MARK: - 清除

    /// 仅清 Cookie（持久化 + 内存）。
    public func clearCookies() {
        cookieStore.clear()
    }

    /// 仅清缓存（内存 + 磁盘）。
    public func clearCache() {
        cacheManager.clearAll()
    }

    /// 同时清 Cookie 与缓存。
    public func clearAll() {
        clearCookies()
        clearCache()
    }
}
