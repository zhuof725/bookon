import Foundation

/// 规则正则编译的统一入口。
/// Java（Rhino）与 ICU 的正则语法有细微差别，`try?` 静默失败会表现成「规则没生效」。
/// 这里把失败同时写进书源调试日志与进程内问题列表，便于在调试页/校验页定位。
enum RegexLog {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var issues: [String] = []
    private nonisolated(unsafe) static var seen = Set<String>()

    static func compile(_ pattern: String,
                        options: NSRegularExpression.Options = []) -> NSRegularExpression? {
        do {
            return try NSRegularExpression(pattern: pattern, options: options)
        } catch {
            let message = "正则编译失败：\(pattern)（\(error.localizedDescription)）"
            lock.lock()
            if seen.insert(message).inserted {
                issues.append(message)
                if issues.count > 80 { issues.removeFirst(issues.count - 80) }
            }
            lock.unlock()
            DebugLog.add("◇" + message)
            return nil
        }
    }

    /// 最近的正则失败（去重，最多 80 条）。
    static func recentIssues() -> [String] {
        lock.lock(); defer { lock.unlock() }
        return issues
    }

    static func reset() {
        lock.lock(); issues.removeAll(); seen.removeAll(); lock.unlock()
    }
}
