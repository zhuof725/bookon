import Foundation

/// 发现（书签）页设置：展示布局、榜单样式、展示数量、性能与缓存。
/// 纯读取逻辑放在这里便于离线回归；界面用 @AppStorage 读写同一批键。
enum DiscoverSettings {
    static let gridEnabledKey = "discover.grid.enabled"
    static let gridColumnsKey = "discover.grid.columns"
    static let pageLayoutKey = "discover.page.layout"
    static let rankingModeKey = "discover.ranking.mode"
    static let rankingKeywordsKey = "discover.ranking.keywords"
    static let verticalCountKey = "discover.vertical.count"
    static let horizontalCountKey = "discover.horizontal.count"
    static let preloadCountKey = "discover.preload.count"
    static let coverConcurrencyKey = "discover.cover.concurrency"
    static let cacheDaysKey = "discover.cache.days"
    static let cycleVerticalKey = "discover.cycle.vertical"
    static let cycleHorizontalKey = "discover.cycle.horizontal"

    static let defaultKeywords = ["榜", "排行", "热门", "推荐", "最热", "畅销"]
    static let defaultVerticalCount = 4
    static let defaultHorizontalCount = 8
    static let defaultCycleVertical = 1
    static let defaultCycleHorizontal = 1
    static let defaultPreloadCount = 5
    static let defaultCoverConcurrency = 6
    static let defaultCacheDays = 3

    /// 网格列数可选 2...5。
    static let columnChoices = [2, 3, 4, 5]
    static func clampedColumns(_ value: Int) -> Int {
        let low = columnChoices.first ?? 2
        let high = columnChoices.last ?? 5
        return min(max(value, low), high)
    }

    /// 缓存有效期可选（天）。
    static let cacheDayChoices = [1, 3, 7, 30]

    /// 展示布局：杂志（所有榜单平铺）或列表（分类筛选 + 书卡列表）。
    enum PageLayout: String, CaseIterable {
        case magazine
        case list
        var title: String { self == .magazine ? "杂志" : "列表" }
    }

    /// 榜单排列方式：循环顺序 / 关键词排列 / 全部竖排 / 全部横滑。
    enum RankingMode: String, CaseIterable {
        case cycle
        case keyword
        case vertical
        case horizontal
        var title: String {
            switch self {
            case .cycle: return "循环顺序"
            case .keyword: return "关键词排列"
            case .vertical: return "全部竖排"
            case .horizontal: return "全部横滑"
            }
        }
    }

    /// 关键词列表：逗号分隔存储，空时回落到默认值。
    static func keywords(from raw: String?) -> [String] {
        let list = (raw ?? "")
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return list.isEmpty ? defaultKeywords : list
    }

    static func keywordsText(_ list: [String]) -> String {
        list.joined(separator: ",")
    }

    /// 板块是否用竖排（排名序号）样式。
    /// 循环顺序：按板块顺序，每个周期「竖排 cycleVertical 个、横滑 cycleHorizontal 个」。
    static func usesVerticalStyle(index: Int, title: String, mode: RankingMode, keywords: [String],
                                  cycleVertical: Int = defaultCycleVertical,
                                  cycleHorizontal: Int = defaultCycleHorizontal) -> Bool {
        switch mode {
        case .vertical: return true
        case .horizontal: return false
        case .keyword: return keywords.contains { title.contains($0) }
        case .cycle:
            let vertical = max(cycleVertical, 0)
            let horizontal = max(cycleHorizontal, 0)
            let period = vertical + horizontal
            guard period > 0 else { return false }
            return (max(index, 0) % period) < vertical
        }
    }
}
