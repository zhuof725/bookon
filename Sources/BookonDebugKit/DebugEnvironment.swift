//
//  DebugEnvironment.swift
//  BookonDebugKit
//
//  第 7 步 B 段：Cookie / 缓存清理（复用第 6 步 CookieStore / CacheManager 实现）。
//  全部非界面逻辑。
//

import Foundation
import LegadoBookSource

public final class DebugEnvironment {

    /// 清空全部 Cookie（持久化 + 内存）。
    public static func clearCookies(_ cookieStore: CookieStore) {
        cookieStore.clear()
    }

    /// 清空全部缓存（内存 + 磁盘）。
    public static func clearCache(_ cacheManager: CacheManager) {
        cacheManager.clearAll()
    }

    /// 同时清空 Cookie 与缓存。
    public static func clearAll(cookieStore: CookieStore, cacheManager: CacheManager) {
        clearCookies(cookieStore)
        clearCache(cacheManager)
    }
}
