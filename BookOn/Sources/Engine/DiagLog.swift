import Foundation
import Combine

/// 全局诊断日志（线程安全，主线程发布）
final class DiagLog: ObservableObject {
    static let shared = DiagLog()

    struct Entry: Identifiable {
        let id = UUID()
        let time = Date()
        let level: Level
        let tag: String
        let message: String
    }
    enum Level: String { case info = "ℹ️", ok = "✅", warn = "⚠️", error = "❌", js = "🟨", net = "🌐" }

    @Published private(set) var entries: [Entry] = []
    private let queue = DispatchQueue(label: "bookon.diaglog")
    private var buffer: [Entry] = []
    var enabled = true
    var maxEntries = 2000

    private init() {}

    func log(_ level: Level, _ tag: String, _ message: String) {
        guard enabled else { return }
        let e = Entry(level: level, tag: tag, message: message)
        queue.async {
            self.buffer.append(e)
            if self.buffer.count > self.maxEntries { self.buffer.removeFirst(self.buffer.count - self.maxEntries) }
            let snapshot = self.buffer
            DispatchQueue.main.async { self.entries = snapshot }
        }
    }
    func info(_ tag: String, _ m: String) { log(.info, tag, m) }
    func ok(_ tag: String, _ m: String) { log(.ok, tag, m) }
    func warn(_ tag: String, _ m: String) { log(.warn, tag, m) }
    func error(_ tag: String, _ m: String) { log(.error, tag, m) }
    func js(_ tag: String, _ m: String) { log(.js, tag, m) }
    func net(_ tag: String, _ m: String) { log(.net, tag, m) }

    func clear() { queue.async { self.buffer.removeAll(); DispatchQueue.main.async { self.entries = [] } } }

    var exportText: String {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"
        return entries.map { "\(f.string(from: $0.time)) \($0.level.rawValue) [\($0.tag)] \($0.message)" }.joined(separator: "\n")
    }

    static func preview(_ s: String, _ n: Int = 300) -> String {
        let t = s.replacingOccurrences(of: "\n", with: "⏎")
        return t.count > n ? String(t.prefix(n)) + "…(\(s.count) 字)" : t
    }
}

/// 兼容旧 Logger 调用
enum Logger {
    static func log(_ s: String) { DiagLog.shared.js("JS", s) }
}
