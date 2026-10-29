import Combine
import Foundation

/// 预取诊断：让「预加载到底有没有下载」在界面上可见。
final class AloudPrefetchStatus: ObservableObject {
    nonisolated(unsafe) static let shared = AloudPrefetchStatus()

    @Published private(set) var cached = 0
    @Published private(set) var failed = 0
    @Published private(set) var running = 0
    @Published private(set) var lastError: String?

    func reset() {
        cached = 0
        failed = 0
        running = 0
        lastError = nil
    }

    func started() {
        running += 1
    }

    func finished() {
        running = max(running - 1, 0)
        cached += 1
    }

    func failed(_ message: String) {
        running = max(running - 1, 0)
        failed += 1
        lastError = message
    }
}
