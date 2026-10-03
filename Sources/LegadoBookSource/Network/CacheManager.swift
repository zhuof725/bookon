//
//  CacheManager.swift
//  LegadoBookSource
//
//  第 6 步 6A：help/CacheManager.kt 的纯逻辑移植（协议 + 内存 + 文件实现）。
//
//  对应 Kotlin object CacheManager：
//   - put(key, value, saveTime)：saveTime 单位秒，0 表示永不过期（deadline = 0）；
//     非零时 deadline = now + saveTime*1000（毫秒）；
//   - putMemory/getFromMemory/deleteMemory：内存 LRU（Kotlin 上限 50MB，按 value 字符串长度近似）；
//   - get(key)：先内存，后存储；存储命中要求 deadline == 0 或 deadline > now，命中后回填内存；
//   - get(key, onlyDisk)：只查存储；
//   - getInt/getLong：内存里非对应类型时回退到磁盘并按文本解析。
//
//  ⚠️ 已知差异（README 登记）：
//   1. Kotlin 的 LruCache 按 value.toString().memorySize() 计字节，这里用「UTF-8 字节数」近似；
//   2. Kotlin 的磁盘实现是 ACache（Android 专用），本移植用「单 JSON 文件 + 原子写」；
//   3. 内存 LRU 的淘汰顺序用「最近使用序」简单维护（非严格 LRU），并删掉最早使用的条目。
//

import Foundation

/// 磁盘/自定义存储接口（对应 Kotlin 的 ACache + cacheDao 组合）。
public protocol CacheStorageProtocol: AnyObject {
    func put(key: String, value: String, deadline: Int64) throws
    func get(key: String) throws -> String?
    /// 带过期时间的读取（对应 Kotlin cacheDao 返回的 Cache(deadline)）。
    func getEntry(key: String) throws -> (value: String, deadline: Int64)?
    func delete(key: String) throws
    func deleteAll() throws
}

public extension CacheStorageProtocol {
    /// 默认实现：不支持 deadline 的存储按「永不过期」处理。
    func getEntry(key: String) throws -> (value: String, deadline: Int64)? {
        guard let v = try get(key: key) else { return nil }
        return (v, 0)
    }
}

/// 内存实现（对应 Kotlin 的 memoryLruCache，容量近似）。
public final class MemoryCacheStorage: CacheStorageProtocol, @unchecked Sendable {
    private let limitBytes: Int
    private var order: [String] = []
    private var values: [String: String] = [:]
    private var deadlines: [String: Int64] = [:]
    private let lock = NSLock()

    public init(limitBytes: Int = 1024 * 1024 * 50) { self.limitBytes = limitBytes }

    private func byteSize(_ s: String) -> Int { s.utf8.count }

    private func touch(_ key: String) {
        order.removeAll { $0 == key }
        order.append(key)
    }

    private func evictIfNeeded() {
        var total = values.reduce(0) { $0 + byteSize($1.value) }
        while total > limitBytes, !order.isEmpty {
            let oldest = order.removeFirst()
            if let v = values.removeValue(forKey: oldest) {
                total -= byteSize(v)
                deadlines.removeValue(forKey: oldest)
            }
        }
    }

    public func put(key: String, value: String, deadline: Int64) throws {
        lock.lock(); defer { lock.unlock() }
        values[key] = value
        deadlines[key] = deadline
        touch(key)
        evictIfNeeded()
    }

    public func get(key: String) throws -> String? {
        lock.lock(); defer { lock.unlock() }
        guard let v = values[key] else { return nil }
        touch(key)
        return v
    }

    public func delete(key: String) throws {
        lock.lock(); defer { lock.unlock() }
        values.removeValue(forKey: key)
        deadlines.removeValue(forKey: key)
        order.removeAll { $0 == key }
    }

    public func deleteAll() throws {
        lock.lock(); defer { lock.unlock() }
        values.removeAll(); deadlines.removeAll(); order.removeAll()
    }

    /// 仅用于测试/诊断：当前条目数。
    public var count: Int {
        lock.lock(); defer { lock.unlock() }
        return values.count
    }
}

/// 文件实现：单个 JSON 文件保存 {key: {value, deadline}}，写入走「临时文件 + 替换」的原子写。
public final class FileCacheStorage: CacheStorageProtocol, @unchecked Sendable {
    private let fileURL: URL
    private let lock = NSLock()

    public init(fileURL: URL) { self.fileURL = fileURL }

    private struct Entry: Codable { var value: String; var deadline: Int64 }

    private func load() -> [String: Entry] {
        guard let data = try? Data(contentsOf: fileURL),
              let map = try? JSONDecoder().decode([String: Entry].self, from: data) else { return [:] }
        return map
    }

    private func save(_ map: [String: Entry]) throws {
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

    public func put(key: String, value: String, deadline: Int64) throws {
        lock.lock(); defer { lock.unlock() }
        var map = load()
        map[key] = Entry(value: value, deadline: deadline)
        try save(map)
    }

    public func get(key: String) throws -> String? {
        lock.lock(); defer { lock.unlock() }
        return load()[key]?.value
    }

    public func getEntry(key: String) throws -> (value: String, deadline: Int64)? {
        lock.lock(); defer { lock.unlock() }
        guard let e = load()[key] else { return nil }
        return (e.value, e.deadline)
    }

    public func delete(key: String) throws {
        lock.lock(); defer { lock.unlock() }
        var map = load()
        map.removeValue(forKey: key)
        try save(map)
    }

    public func deleteAll() throws {
        lock.lock(); defer { lock.unlock() }
        try save([:])
    }
}

/// 对应 Kotlin `object CacheManager`。
public final class CacheManager: CacheManagerProtocol, @unchecked Sendable {
    private let storage: CacheStorageProtocol
    private let memory = MemoryCacheStorage()
    private let now: () -> Int64

    public init(storage: CacheStorageProtocol = FileCacheStorage(fileURL: CacheManager.defaultFileURL),
                now: @escaping () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }) {
        self.storage = storage
        self.now = now
    }

    public static var defaultFileURL: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return dir.appendingPathComponent("legado_cache.json")
    }

    // MARK: - 对应 Kotlin 的 API

    /// 对应 `CacheManager.put(key, value, saveTime)`：saveTime 秒，0 表示永不过期。
    public func put(_ key: String, _ value: String, saveTime: Int = 0) {
        let deadline: Int64 = saveTime == 0 ? 0 : now() + Int64(saveTime) * 1000
        putMemory(key, value)
        try? storage.put(key: key, value: value, deadline: deadline)
    }

    public func putMemory(_ key: String, _ value: Any) {
        // Kotlin 的 memoryLruCache 接受任意类型；本移植只缓存字符串（其余类型忽略）。
        if let s = value as? String {
            try? memory.put(key: key, value: s, deadline: 0)
        }
    }

    public func getFromMemory(_ key: String) -> Any? {
        return try? memory.get(key: key)
    }

    public func deleteMemory(_ key: String) {
        try? memory.delete(key: key)
    }

    /// 协议实现（JS 里 `cache.get(key)`）。
    public func get(_ key: String) -> String? {
        return get(key, onlyDisk: false)
    }

    public func get(_ key: String, onlyDisk: Bool) -> String? {
        if !onlyDisk, let cached = try? memory.get(key: key) {
            return cached
        }
        guard let wrapped = try? storage.getEntry(key: key), let entry = wrapped else { return nil }
        // 存储命中条件：deadline == 0（永不过期）或未过期（对应 Kotlin
        // `cache.deadline == 0L || cache.deadline > System.currentTimeMillis()`）
        guard entry.deadline == 0 || entry.deadline > now() else { return nil }
        if !onlyDisk { try? memory.put(key: key, value: entry.value, deadline: 0) }
        return entry.value
    }

    /// 协议实现（JS 里 `cache.put(key, value)`，无过期）。
    public func put(_ key: String, _ value: String) {
        put(key, value, saveTime: 0)
    }

    public func delete(_ key: String) {
        deleteMemory(key)
        try? storage.delete(key: key)
    }

    public func getInt(_ key: String) -> Int? {
        if let v = getFromMemory(key) as? String { return Int(v) }
        return get(key, onlyDisk: true).flatMap { Int($0) }
    }

    public func getLong(_ key: String) -> Int64? {
        if let v = getFromMemory(key) as? String { return Int64(v) }
        return get(key, onlyDisk: true).flatMap { Int64($0) }
    }

    public func clearMemory() { try? memory.deleteAll() }
}
