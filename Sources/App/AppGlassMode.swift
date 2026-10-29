import SwiftUI

/// 全局「玻璃模式」。
///
/// 默认开启，保持原来的毛玻璃 / Liquid Glass 外观；关闭后所有 App 自绘的
/// 半透明表面（卡片、按钮胶囊、浮层、设置行）改用主题实色底。
/// 只影响界面材质，不改主题配色；系统自带的底栏玻璃由 iOS 管理，不在范围内。
enum AppGlassMode {
    static let storageKey = "app.glass.v1"

    /// 给非 SwiftUI 场景读取当前值。
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: storageKey) as? Bool ?? true
    }
}
