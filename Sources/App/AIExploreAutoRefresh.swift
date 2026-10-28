import Foundation

/// 「探索」页的 AI 自动生成推荐语。
///
/// 打开探索页时，如果开关打开、距上次运行超过冷却时间、并且配置了可用的 AI 服务，
/// 就在后台给还没有推荐语的书生成一批，避免每次进页面都消耗额度。
enum AIExploreAutoRefresh {
    private static let enabledKey = "explore.ai.autoRefresh.v1"
    private static let lastRunKey = "explore.ai.autoRefresh.lastRun.v1"

    /// 两次自动刷新之间的最短间隔。
    static let cooldown: TimeInterval = 6 * 3600

    static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static var lastRun: Date? {
        get { UserDefaults.standard.object(forKey: lastRunKey) as? Date }
        set {
            if let newValue { UserDefaults.standard.set(newValue, forKey: lastRunKey) }
            else { UserDefaults.standard.removeObject(forKey: lastRunKey) }
        }
    }

    /// 现在是否应该自动跑一次。
    static var shouldRun: Bool {
        guard enabled else { return false }
        guard let last = lastRun else { return true }
        return Date().timeIntervalSince(last) >= cooldown
    }

    /// 冷却状态的可读描述，设置页用。
    static func statusText(now: Date = Date()) -> String {
        guard enabled else { return "关闭" }
        guard let last = lastRun else { return "下次打开探索时运行" }
        let remaining = cooldown - now.timeIntervalSince(last)
        guard remaining > 0 else { return "下次打开探索时运行" }
        let hours = Int(remaining / 3600)
        let minutes = Int(remaining.truncatingRemainder(dividingBy: 3600) / 60)
        return hours > 0 ? "\(hours) 小时 \(minutes) 分后可再次运行" : "\(minutes) 分后可再次运行"
    }
}
