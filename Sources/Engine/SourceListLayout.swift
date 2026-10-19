import Foundation

/// 发现页书源列表的展示方式：网格卡片或列表行。
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

    /// UserDefaults 键：发现页书源的排列方式（grid / list）。
    static let layoutKey = "sources.layout.v1"
}
