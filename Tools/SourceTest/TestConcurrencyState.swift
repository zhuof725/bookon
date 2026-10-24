import Foundation

/// 回归测试用的并发状态盒。
///
/// Swift 6 不允许在 `@Sendable` 闭包里修改捕获的局部 `var`，测试里又要统计
/// 「同时在跑几个 / 回调了几次」，所以统一用这个带锁的小盒子。
final class TestConcurrencyState: @unchecked Sendable {
    private let lock = NSLock()
    private var active = 0
    private var peakValue = 0
    private var startCount = 0
    private var resultCount = 0
    private var finishedIDs: [String] = []

    func enter() {
        lock.lock()
        active += 1
        peakValue = max(peakValue, active)
        lock.unlock()
    }

    func leave() {
        lock.lock()
        active -= 1
        lock.unlock()
    }

    func markStart() {
        lock.lock()
        startCount += 1
        lock.unlock()
    }

    func markResult(_ id: String? = nil) {
        lock.lock()
        resultCount += 1
        if let id { finishedIDs.append(id) }
        lock.unlock()
    }

    var peak: Int { lock.lock(); defer { lock.unlock() }; return peakValue }
    var starts: Int { lock.lock(); defer { lock.unlock() }; return startCount }
    var results: Int { lock.lock(); defer { lock.unlock() }; return resultCount }
    var finished: [String] { lock.lock(); defer { lock.unlock() }; return finishedIDs }
}
