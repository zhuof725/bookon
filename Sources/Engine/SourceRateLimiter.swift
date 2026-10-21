import Foundation

/// 原版 `ConcurrentRateLimiter`：书源 `concurrentRate` 支持 `次数/毫秒`（并发率）
/// 或单个数字（毫秒间隔）。这里用 actor 串行化同一书源的请求节奏，超限时等待到窗口结束。
actor SourceRateLimiter {
    static let shared = SourceRateLimiter()

    private struct Record {
        var nextTime: UInt64
        var count: Int
        let limit: Int
        let interval: UInt64
    }

    private var records: [String: Record] = [:]

    func acquire(key: String, rate: String?) async throws {
        guard let rule = Self.parse(rate) else { return }
        while true {
            try Task.checkCancellation()
            let now = DispatchTime.now().uptimeNanoseconds
            if var record = records[key] {
                if now >= record.nextTime {
                    record.nextTime = now + rule.interval
                    record.count = 1
                    records[key] = record
                    return
                }
                if record.count < rule.limit {
                    record.count += 1
                    records[key] = record
                    return
                }
                let wait = record.nextTime - now
                // 用 try 而不是 try?：任务被取消时 Task.sleep 抛 CancellationError，
                // 吞掉它会让取消后的请求空转到窗口结束。
                try await Task.sleep(nanoseconds: min(wait, 5_000_000_000))
            } else {
                records[key] = Record(nextTime: now + rule.interval, count: 1,
                                      limit: rule.limit, interval: rule.interval)
                return
            }
        }
    }

    /// "N/M" = 每 M 毫秒最多 N 次；"M" = 每 M 毫秒 1 次；0/空 = 不限。
    static func parse(_ rate: String?) -> (limit: Int, interval: UInt64)? {
        guard let text = rate?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        if let slash = text.firstIndex(of: "/") {
            let left = Int(text[..<slash]) ?? 1
            let right = Int(text[text.index(after: slash)...]) ?? 0
            guard left > 0, right > 0 else { return nil }
            return (left, UInt64(right) * 1_000_000)
        }
        guard let ms = Int(text), ms > 0 else { return nil }
        return (1, UInt64(ms) * 1_000_000)
    }
}
