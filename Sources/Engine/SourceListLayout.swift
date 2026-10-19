import Foundation

/// 书源列表（书源管理 / 发现）的展示方式：网格卡片或列表行。
/// 网格列数可选 2...4，其余存储值自动钳制回范围内，纯逻辑便于离线回归。
enum SourceListLayout: String, CaseIterable {
    case grid
    case list

    var title: String {
        switch self {
        case .grid: return "网格"
        case .list: return "列表"
        }
    }

    var symbol: String {
        switch self {
        case .grid: return "square.grid.2x2"
        case .list: return "list.bullet"
        }
    }

    /// UserDefaults 键：书源页布局（grid / list）与网格列数。
    static let layoutKey = "sources.layout.v1"
    static let columnsKey = "sources.columns.v1"
    static let defaultColumns = 2

    /// 网格列数可选项。
    static let columnChoices = [2, 3, 4]

    /// 把存储的列数钳制到可选项范围内；缺省（或越界）回落默认值。
    static func clampedColumns(_ value: Int) -> Int {
        let low = columnChoices.first ?? defaultColumns
        let high = columnChoices.last ?? defaultColumns
        return min(max(value, low), high)
    }
}
