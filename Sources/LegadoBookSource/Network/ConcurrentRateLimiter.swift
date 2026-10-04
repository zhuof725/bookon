//
//  ConcurrentRateLimiter.swift
//  LegadoBookSource
//
//  第 6 步 6A：help/ConcurrentRateLimiter.kt 的完整移植（actor 化 + 时钟/存储可注入）。
//
//  Kotlin 语义（逐条对照）：
//   - concurrentRecordMap 是 companion 里的**全局** map（按书源 key 共享），记录
//     time/accessLimit/interval/frequency；
//   - concurrentRate 两种写法："次数/毫秒" 与 "纯毫秒"（等价于 1/毫秒）；
//   - concurrentRate 为空串或 "0" 时不限速；
//   - fetchStart：新记录直接放行；否则在同一把锁里算 nextTime = time + interval：
//        now >= nextTime  -> time = now, frequency = 1, 等待 0
//        frequency < limit -> frequency++，等待 0
//        否则              -> 等待 nextTime - now（抛 ConcurrentException）
//   - getConcurrentRecord：循环 fetchStart，被限速就 sleep(waitTime) 再试；
//   - updateConcurrentRate：非法输入（非数字、<=0、无斜杠且解析失败）时保留旧记录。
//
//  与 Kotlin 的差异（README 登记）：
//   1. Kotlin 的 ConcurrentRecord 是可变对象、被多线程直接改；Swift 用 actor 串行化 +
//      值类型记录，语义等价；
//   2. delay/Thread.sleep 换成注入时钟的 `sleep`，测试用假时钟可确定性复现。
//

import Foundation

/// 对应 Kotlin `AnalyzeUrl.ConcurrentRecord`。
public struct ConcurrentRecord: Equatable, Sendable {
    public var time: Int64
    public var accessLimit: Int
    public var interval: Int
    public var frequency: Int

    public init(time: Int64, accessLimit: Int, interval: Int, frequency: Int) {
        self.time = time
        self.accessLimit = accessLimit
        self.interval = interval
        self.frequency = frequency
    }
}

/// 对应 Kotlin 的 `ConcurrentException`（message + waitTime）。
public struct ConcurrentLimitError: Error, Equatable {
    public let message: String
    public let waitTime: Int64
    public init(message: String, waitTime: Int64) {
        self.message = message
        self.waitTime = waitTime
    }
}

/// 时钟注入点：生产用系统时钟，测试用假时钟。
public protocol RateLimitClock: AnyObject, Sendable {
    func now() -> Int64
    func sleep(millis: Int64) async
}

public final class SystemRateLimitClock: RateLimitClock, @unchecked Sendable {
    public init() {}
    public func now() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }
    public func sleep(millis: Int64) async {
        guard millis > 0 else { return }
        try? await Task.sleep(nanoseconds: UInt64(millis) * 1_000_000)
    }
}

/// 对应 Kotlin companion 里的 `concurrentRecordMap`（全局共享、线程安全）。
public final class ConcurrentRecordStore: @unchecked Sendable {
    /// 全局共享实例（对齐 Kotlin companion object 的静态 map）。
    public static let shared = ConcurrentRecordStore()

    private var map: [String: ConcurrentRecord] = [:]
    private let lock = NSLock()

    public init() {}

    func record(for key: String) -> ConcurrentRecord? {
        lock.lock(); defer { lock.unlock() }
        return map[key]
    }

    /// computeIfAbsent 语义：不存在则用 make 创建并放入，同时返回 isNew = true。
    func getOrCreate(for key: String, make: () -> ConcurrentRecord) -> (record: ConcurrentRecord, isNew: Bool) {
        lock.lock(); defer { lock.unlock() }
        if let existing = map[key] { return (existing, false) }
        let created = make()
        map[key] = created
        return (created, true)
    }

    /// 原地更新（对应 Kotlin 直接在 ConcurrentRecord 上改字段）。
    func update(for key: String, _ body: (inout ConcurrentRecord) -> Void) {
        lock.lock(); defer { lock.unlock() }
        guard var r = map[key] else { return }
        body(&r)
        map[key] = r
    }

    func replace(for key: String, with record: ConcurrentRecord) {
        lock.lock(); defer { lock.unlock() }
        map[key] = record
    }

    public func removeAll() {
        lock.lock(); defer { lock.unlock() }
        map.removeAll()
    }
}

/// 对应 Kotlin `ConcurrentRateLimiter`。
public actor ConcurrentRateLimiter {

    private let concurrentRate: String?
    private let key: String?
    private let store: ConcurrentRecordStore
    private let clock: RateLimitClock

    public init(concurrentRate: String?, key: String?,
                store: ConcurrentRecordStore = .shared,
                clock: RateLimitClock = SystemRateLimitClock()) {
        self.concurrentRate = concurrentRate
        self.key = key
        self.store = store
        self.clock = clock
    }

    public init(source: (any ConcurrentRateSource)?,
                store: ConcurrentRecordStore = .shared,
                clock: RateLimitClock = SystemRateLimitClock()) {
        self.concurrentRate = source?.concurrentRate
        self.key = source?.getKey()
        self.store = store
        self.clock = clock
    }

    // MARK: - companion 里的 updateConcurrentRate

    /// 对应 Kotlin `ConcurrentRateLimiter.updateConcurrentRate(key, concurrentRate)`。
    /// 非法输入时保留旧记录（不抛错）。
    public static func updateConcurrentRate(key: String, concurrentRate: String,
                                            store: ConcurrentRecordStore = .shared,
                                            clock: RateLimitClock = SystemRateLimitClock()) {
        store.update(for: key) { record in
            let rateIndex = concurrentRate.firstIndex(of: "/")
            if let idx = rateIndex, idx != concurrentRate.startIndex {
                let accessLimit = Int(concurrentRate[concurrentRate.startIndex..<idx]) ?? Int.min
                let interval = Int(concurrentRate[concurrentRate.index(after: idx)...]) ?? Int.min
                if accessLimit <= 0 || interval <= 0 { return } // Kotlin: throw -> record 不变
                record = ConcurrentRecord(time: record.time, accessLimit: accessLimit,
                                          interval: interval, frequency: record.frequency)
            } else if let ms = Int(concurrentRate), ms > 0 {
                record = ConcurrentRecord(time: record.time, accessLimit: 1,
                                          interval: ms, frequency: record.frequency)
            }
        }
        // update 只在已有记录时生效；不存在时按 Kotlin compute 语义会创建一条——
        // 这里保持同样效果：不存在则用当前时间新建。
        if store.record(for: key) == nil {
            let rateIndex = concurrentRate.firstIndex(of: "/")
            if let idx = rateIndex, idx != concurrentRate.startIndex,
               let accessLimit = Int(concurrentRate[concurrentRate.startIndex..<idx]),
               let interval = Int(concurrentRate[concurrentRate.index(after: idx)...]),
               accessLimit > 0, interval > 0 {
                store.replace(for: key, with: ConcurrentRecord(time: clock.now(), accessLimit: accessLimit,
                                                               interval: interval, frequency: 0))
            } else if let ms = Int(concurrentRate), ms > 0 {
                store.replace(for: key, with: ConcurrentRecord(time: clock.now(), accessLimit: 1,
                                                               interval: ms, frequency: 0))
            }
        }
    }

    // MARK: - fetchStart / getConcurrentRecord

    /// 对应 Kotlin 私有 `fetchStart()`：被限速时抛 ConcurrentLimitError（含 waitTime）。
    public func fetchStart() throws -> ConcurrentRecord? {
        guard let rate = concurrentRate, !rate.isEmpty, rate != "0" else { return nil }
        guard let key = key else { return nil }

        let (existing, isNew) = store.getOrCreate(for: key) {
            let rateIndex = rate.firstIndex(of: "/")
            if let idx = rateIndex, idx != rate.startIndex {
                let accessLimit = Int(rate[rate.startIndex..<idx]) ?? 1
                let interval = Int(rate[rate.index(after: idx)...]) ?? 0
                return ConcurrentRecord(time: clock.now(), accessLimit: accessLimit,
                                        interval: interval, frequency: 1)
            } else {
                return ConcurrentRecord(time: clock.now(), accessLimit: 1,
                                        interval: Int(rate) ?? 0, frequency: 1)
            }
        }
        if isNew { return existing }

        // 对应 Kotlin 的 synchronized(fetchRecord) 块
        var waitTime: Int64 = 0
        var updated: ConcurrentRecord = existing
        var shouldWrite = false
        let nextTime = existing.time + Int64(existing.interval)
        let nowTime = clock.now()
        if nowTime >= nextTime {
            updated.time = nowTime
            updated.frequency = 1
            waitTime = 0
            shouldWrite = true
        } else if existing.frequency < existing.accessLimit {
            updated.frequency = existing.frequency + 1
            waitTime = 0
            shouldWrite = true
        } else {
            waitTime = nextTime - nowTime
        }
        if shouldWrite {
            // 只有当内存里的记录仍是同一版本时才写回（避免并发覆盖）
            if let cur = store.record(for: key), cur.frequency == existing.frequency, cur.time == existing.time {
                store.replace(for: key, with: updated)
            }
        }
        if waitTime > 0 {
            throw ConcurrentLimitError(message: "根据并发率还需等待\(waitTime)毫秒才可以访问", waitTime: waitTime)
        }
        return updated
    }

    /// 对应 Kotlin `getConcurrentRecord()`：被限速则等待后重试，直到拿到记录。
    public func getConcurrentRecord() async -> ConcurrentRecord? {
        while true {
            do {
                return try fetchStart()
            } catch let e as ConcurrentLimitError {
                await clock.sleep(millis: e.waitTime)
            } catch {
                return nil
            }
        }
    }

    /// 对应 Kotlin `withLimit { }`：先过限速再执行。
    public func withLimit<T>(_ block: () async throws -> T) async rethrows -> T {
        _ = await getConcurrentRecord()
        return try await block()
    }
}

/// 限速器需要的最小书源信息（concurrentRate + key）。BaseSource 等可自由实现。
public protocol ConcurrentRateSource: AnyObject {
    var concurrentRate: String? { get }
    func getKey() -> String
}
