import Foundation

// MARK: - 模板图标

/// 模板 → SF Symbol，设置页和卡片角标共用一份，避免两处 switch 走样。
enum DiscoverTemplateIcon {
    static func symbol(_ kind: DiscoverTemplateKind) -> String {
        switch kind {
        case .badgeGrid: return "square.grid.2x2"
        case .covers: return "rectangle.split.3x1"
        case .rankRow: return "list.number"
        case .waterfall: return "rectangle.grid.2x2"
        case .curve: return "rectangle.on.rectangle.angled"
        case .fan: return "fan.fill"
        case .deck: return "square.stack.3d.down.right"
        case .history: return "clock.arrow.circlepath"
        }
    }
}
