//
//  ConcurrentRateLimiterTests.swift
//  LegadoNetworkTests
//
//  第 6 步 6A：ConcurrentRateLimiter 的单元测试（假时钟，确定性）。
//  对应 Kotlin help/ConcurrentRateLimiter.kt 的语义，逐条覆盖：
//   "次数/毫秒" 与 "纯毫秒" 两种写法、frequency 递增、超限等待、到时重置、
//   updateConcurrentRate 的非法输入保留旧记录、withLimit 等待后执行。
//

import XCTest
@testable import LegadoBookSource

/// 假时钟：now() 返回可控时间，sleep 直接推进时间并记录。
final class FakeRateClock: RateLimitClock, @unchecked Sendable {
    private let lock = NSLock()
    private var current: Int64
    private var slept: [Int64] = []

    init(start: Int64 = 1_000_000) { current = start }

    func now() -> Int64 {
        lock.lock(); defer { lock.unlock() }
        return current
    }

    func sleep(millis: Int64) async {
        lock.lock()
        slept.append(millis)
        current += max(0, millis)
        lock.unlock()
    }

    func advance(_ ms: Int64) {
        lock.lock(); current += ms; lock.unlock()
    }

    var sleptValues: [Int64] {
        lock.lock(); defer { lock.unlock() }
        return slept
    }
}

final class ConcurrentRateLimiterTests: XCTestCase {

    private func makeLimiter(rate: String?, key: String?, clock: FakeRateClock)
        -> (ConcurrentRateLimiter, ConcurrentRecordStore) {
        let store = ConcurrentRecordStore()
        return (ConcurrentRateLimiter(concurrentRate: rate, key: key, store: store, clock: clock), store)
    }

    // 1
    func testNilRatePassesThrough() async throws {
        let clock = FakeRateClock()
        let (limiter, _) = makeLimiter(rate: nil, key: "a", clock: clock)
        let record = try await limiter.fetchStart()
        XCTAssertNil(record)
    }

    // 2
    func testEmptyRatePassesThrough() async throws {
        let clock = FakeRateClock()
        let (limiter, _) = makeLimiter(rate: "", key: "a", clock: clock)
        let record = try await limiter.fetchStart()
        XCTAssertNil(record)
    }

    // 3
    func testZeroRatePassesThrough() async throws {
        let clock = FakeRateClock()
        let (limiter, _) = makeLimiter(rate: "0", key: "a", clock: clock)
        let record = try await limiter.fetchStart()
        XCTAssertNil(record)
    }

    // 4
    func testNilKeyPassesThrough() async throws {
        let clock = FakeRateClock()
        let (limiter, _) = makeLimiter(rate: "5/1000", key: nil, clock: clock)
        let record = try await limiter.fetchStart()
        XCTAssertNil(record)
    }

    // 5
    func testNewRecordUsesSlashForm() async throws {
        let clock = FakeRateClock(start: 1000)
        let (limiter, _) = makeLimiter(rate: "5/2000", key: "k", clock: clock)
        let record = try await limiter.fetchStart()
        XCTAssertEqual(record?.accessLimit, 5)
        XCTAssertEqual(record?.interval, 2000)
        XCTAssertEqual(record?.frequency, 1)
        XCTAssertEqual(record?.time, 1000)
    }

    // 6
    func testNewRecordUsesBareMillisForm() async throws {
        let clock = FakeRateClock(start: 42)
        let (limiter, _) = makeLimiter(rate: "3000", key: "k", clock: clock)
        let record = try await limiter.fetchStart()
        XCTAssertEqual(record?.accessLimit, 1)
        XCTAssertEqual(record?.interval, 3000)
        XCTAssertEqual(record?.frequency, 1)
        XCTAssertEqual(record?.time, 42)
    }

    // 7
    func testFrequencyIncrementsWithinLimit() async throws {
        let clock = FakeRateClock()
        let (limiter, _) = makeLimiter(rate: "3/1000", key: "k", clock: clock)
        _ = try await limiter.fetchStart()
        let second = try await limiter.fetchStart()
        XCTAssertEqual(second?.frequency, 2)
        let third = try await limiter.fetchStart()
        XCTAssertEqual(third?.frequency, 3)
    }

    // 8
    func testThrowsWhenLimitReached() async throws {
        let clock = FakeRateClock()
        let (limiter, _) = makeLimiter(rate: "2/1000", key: "k", clock: clock)
        _ = try await limiter.fetchStart()
        _ = try await limiter.fetchStart()
        do {
            _ = try await limiter.fetchStart()
            XCTFail("应当抛 ConcurrentLimitError")
        } catch let e as ConcurrentLimitError {
            XCTAssertEqual(e.waitTime, 1000)
            XCTAssertTrue(e.message.contains("1000"))
        }
    }

    // 9
    func testWaitTimeCountsDownWithClock() async throws {
        let clock = FakeRateClock()
        let (limiter, _) = makeLimiter(rate: "1/1000", key: "k", clock: clock)
        _ = try await limiter.fetchStart()
        clock.advance(400)
        do {
            _ = try await limiter.fetchStart()
            XCTFail("应当抛 ConcurrentLimitError")
        } catch let e as ConcurrentLimitError {
            XCTAssertEqual(e.waitTime, 600)
        }
    }

    // 10
    func testResetsAfterInterval() async throws {
        let clock = FakeRateClock()
        let (limiter, _) = makeLimiter(rate: "2/1000", key: "k", clock: clock)
        _ = try await limiter.fetchStart()
        _ = try await limiter.fetchStart()
        clock.advance(1000)
        let record = try await limiter.fetchStart()
        XCTAssertEqual(record?.frequency, 1)
        XCTAssertEqual(record?.time, clock.now())
    }

    // 11
    func testGetConcurrentRecordWaitsAndSucceeds() async throws {
        let clock = FakeRateClock()
        let (limiter, _) = makeLimiter(rate: "1/1000", key: "k", clock: clock)
        _ = await limiter.getConcurrentRecord()
        let second = await limiter.getConcurrentRecord()
        XCTAssertNotNil(second)
        XCTAssertEqual(clock.sleptValues, [1000])
    }

    // 12
    func testWithLimitExecutesAfterWaiting() async throws {
        let clock = FakeRateClock()
        let (limiter, _) = makeLimiter(rate: "1/500", key: "k", clock: clock)
        var counter = 0
        _ = try await limiter.withLimit { counter += 1 }
        _ = try await limiter.withLimit { counter += 1 }
        XCTAssertEqual(counter, 2)
        XCTAssertEqual(clock.sleptValues, [500])
    }

    // 13
    func testWithLimitPropagatesError() async throws {
        struct Boom: Error {}
        let clock = FakeRateClock()
        let (limiter, _) = makeLimiter(rate: nil, key: "k", clock: clock)
        do {
            _ = try await limiter.withLimit { throw Boom() }
            XCTFail("应当抛出闭包里的错误")
        } catch is Boom {
            // ok
        }
    }

    // 14
    func testSharedStoreAcrossLimiters() async throws {
        let clock = FakeRateClock()
        let store = ConcurrentRecordStore()
        let a = ConcurrentRateLimiter(concurrentRate: "2/1000", key: "same", store: store, clock: clock)
        let b = ConcurrentRateLimiter(concurrentRate: "2/1000", key: "same", store: store, clock: clock)
        _ = try await a.fetchStart()
        let second = try await b.fetchStart()
        XCTAssertEqual(second?.frequency, 2, "同一 key 共享记录（Kotlin companion map 语义）")
    }

    // 15
    func testDifferentKeysDoNotShare() async throws {
        let clock = FakeRateClock()
        let store = ConcurrentRecordStore()
        let a = ConcurrentRateLimiter(concurrentRate: "2/1000", key: "k1", store: store, clock: clock)
        let b = ConcurrentRateLimiter(concurrentRate: "2/1000", key: "k2", store: store, clock: clock)
        _ = try await a.fetchStart()
        let other = try await b.fetchStart()
        XCTAssertEqual(other?.frequency, 1)
    }

    // 16
    func testUpdateConcurrentRateReplacesParsedValues() {
        let clock = FakeRateClock(start: 777)
        let store = ConcurrentRecordStore()
        ConcurrentRateLimiter.updateConcurrentRate(key: "k", concurrentRate: "10/2000", store: store, clock: clock)
        let r = store.record(for: "k")
        XCTAssertEqual(r?.accessLimit, 10)
        XCTAssertEqual(r?.interval, 2000)
        XCTAssertEqual(r?.time, 777)
        XCTAssertEqual(r?.frequency, 0)
    }

    // 17
    func testUpdateConcurrentRateKeepsOldOnInvalid() {
        let clock = FakeRateClock()
        let store = ConcurrentRecordStore()
        ConcurrentRateLimiter.updateConcurrentRate(key: "k", concurrentRate: "5/1000", store: store, clock: clock)
        ConcurrentRateLimiter.updateConcurrentRate(key: "k", concurrentRate: "abc", store: store, clock: clock)
        let r = store.record(for: "k")
        XCTAssertEqual(r?.accessLimit, 5)
        XCTAssertEqual(r?.interval, 1000)
    }

    // 18
    func testUpdateConcurrentRateRejectsZeroZero() {
        let clock = FakeRateClock()
        let store = ConcurrentRecordStore()
        ConcurrentRateLimiter.updateConcurrentRate(key: "k", concurrentRate: "1/1000", store: store, clock: clock)
        ConcurrentRateLimiter.updateConcurrentRate(key: "k", concurrentRate: "0/0", store: store, clock: clock)
        XCTAssertEqual(store.record(for: "k")?.accessLimit, 1)
    }

    // 19
    func testUpdateConcurrentRateRejectsNegative() {
        let clock = FakeRateClock()
        let store = ConcurrentRecordStore()
        ConcurrentRateLimiter.updateConcurrentRate(key: "k", concurrentRate: "-1/5", store: store, clock: clock)
        XCTAssertNil(store.record(for: "k"), "非法输入不创建记录（Kotlin compute 返回 null 移除）")
    }

    // 20
    func testUpdateConcurrentRateBareMillis() {
        let clock = FakeRateClock()
        let store = ConcurrentRecordStore()
        ConcurrentRateLimiter.updateConcurrentRate(key: "k", concurrentRate: "1500", store: store, clock: clock)
        let r = store.record(for: "k")
        XCTAssertEqual(r?.accessLimit, 1)
        XCTAssertEqual(r?.interval, 1500)
    }

    // 21
    func testNoSleepWhenNoLimit() async {
        let clock = FakeRateClock()
        let (limiter, _) = makeLimiter(rate: nil, key: "k", clock: clock)
        _ = await limiter.getConcurrentRecord()
        XCTAssertTrue(clock.sleptValues.isEmpty)
    }

    // 22
    func testSlashFormWithLeadingSlashIsBareForm() async throws {
        // "/1000" 的 rateIndex == 0，Kotlin 走 else 分支（toIntOrNull 失败 -> 0）
        let clock = FakeRateClock()
        let (limiter, _) = makeLimiter(rate: "/1000", key: "k", clock: clock)
        let record = try await limiter.fetchStart()
        XCTAssertEqual(record?.accessLimit, 1)
        XCTAssertEqual(record?.interval, 0)
    }
}
