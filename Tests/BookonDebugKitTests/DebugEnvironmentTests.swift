//
//  DebugEnvironmentTests.swift
//  BookonDebugKitTests
//
//  第 7 步 B 段：Cookie / 缓存清理测试（复用第 6 步 CookieStore / CacheManager）。
//

import XCTest
@testable import BookonDebugKit
@testable import LegadoBookSource

final class DebugEnvironmentTests: XCTestCase {

    private func tempURL(_ name: String) -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("bookon-env-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(name)
    }

    func testClearCookies() {
        let store = CookieStore(persistence: MemoryCookiePersistence())
        store.setCookie("http://a.test", "k=v")
        XCTAssertFalse(store.getCookie("http://a.test").isEmpty)
        DebugEnvironment.clearCookies(store)
        XCTAssertTrue(store.getCookie("http://a.test").isEmpty)
    }

    func testClearCookiesPersistent() {
        let store = CookieStore(persistence: FileCookiePersistence(fileURL: tempURL("cookies.json")))
        store.setCookie("http://a.test", "k=v")
        XCTAssertFalse(store.getCookie("http://a.test").isEmpty)
        DebugEnvironment.clearCookies(store)
        XCTAssertTrue(store.getCookie("http://a.test").isEmpty)
    }

    func testClearCacheMemoryAndDisk() {
        let cache = CacheManager(storage: MemoryCacheStorage())
        cache.put("key1", "value1")
        cache.putMemory("key2", "value2")
        XCTAssertEqual(cache.get("key1"), "value1")
        XCTAssertEqual(cache.get("key2"), "value2")

        DebugEnvironment.clearCache(cache)
        XCTAssertNil(cache.get("key1"))
        XCTAssertNil(cache.get("key2"))
    }

    func testClearCacheDisk() {
        let cache = CacheManager(storage: FileCacheStorage(fileURL: tempURL("cache.json")))
        cache.put("k", "v")
        XCTAssertEqual(cache.get("k", onlyDisk: true), "v")
        DebugEnvironment.clearCache(cache)
        XCTAssertNil(cache.get("k", onlyDisk: true))
    }

    func testClearAll() {
        let store = CookieStore(persistence: MemoryCookiePersistence())
        store.setCookie("http://a.test", "k=v")
        let cache = CacheManager(storage: MemoryCacheStorage())
        cache.put("k", "v")

        DebugEnvironment.clearAll(cookieStore: store, cacheManager: cache)
        XCTAssertTrue(store.getCookie("http://a.test").isEmpty)
        XCTAssertNil(cache.get("k"))
    }
}
