import Foundation

/// 「探索」页的 AI 自动生成推荐语。
///
/// 打开探索页时，如果开关打开、距上次运行超过冷却时间、并且配置了可用的 AI 服务，
/// 就在后台给还没有推荐语的书生成一批，避免每次进页面都消耗额度。
enum AIExploreAutoRefresh {
    private static let enabledKey = "explore.ai.autoRefresh.v1"
    private static let lastRunKey = "explore.ai.autoRefresh.lastRun.v1"
    private static let picksEnabledKey = "explore.ai.picks.v1"
    private static let picksLastRunKey = "explore.ai.picks.lastRun.v1"

    /// 两次自动刷新之间的最短间隔。
    static let cooldown: TimeInterval = 6 * 3600

    /// 默认开启：推荐板块里的书应该自带推荐语。
    static var enabled: Bool {
        get {
            let defaults = UserDefaults.standard
            guard defaults.object(forKey: enabledKey) != nil else { return true }
            return defaults.bool(forKey: enabledKey)
        }
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

    // MARK: 自动挑选书源分类

    /// 是否让 AI 自动挑选书源分类，生成「AI 推荐」板块。
    /// 默认开启：用户不该为了"有推荐"先去翻设置。
    static var picksEnabled: Bool {
        get {
            let defaults = UserDefaults.standard
            guard defaults.object(forKey: picksEnabledKey) != nil else { return true }
            return defaults.bool(forKey: picksEnabledKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: picksEnabledKey) }
    }

    static var picksLastRun: Date? {
        get { UserDefaults.standard.object(forKey: picksLastRunKey) as? Date }
        set {
            if let newValue { UserDefaults.standard.set(newValue, forKey: picksLastRunKey) }
            else { UserDefaults.standard.removeObject(forKey: picksLastRunKey) }
        }
    }

    static var shouldPick: Bool {
        guard picksEnabled else { return false }
        guard let last = picksLastRun else { return true }
        return Date().timeIntervalSince(last) >= cooldown
    }

    static func picksStatusText(now: Date = Date()) -> String {
        guard picksEnabled else { return "关闭" }
        guard let last = picksLastRun else { return "下次打开探索时挑选" }
        let remaining = cooldown - now.timeIntervalSince(last)
        guard remaining > 0 else { return "下次打开探索时挑选" }
        let hours = Int(remaining / 3600)
        let minutes = Int(remaining.truncatingRemainder(dividingBy: 3600) / 60)
        return hours > 0 ? "\(hours) 小时 \(minutes) 分后可再次挑选" : "\(minutes) 分后可再次挑选"
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
