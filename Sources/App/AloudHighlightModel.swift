import UIKit

/// 仅广播绘制状态；进度不会发布到 ReaderView，避免每个字触发分页宿主更新。
final class AloudHighlightModel: NSObject {
    static let changedName = Notification.Name("ReaderAloudHighlightChanged")
    private(set) var value: AloudHighlight?

    func update(_ next: AloudHighlight?) {
        precondition(Thread.isMainThread)
        guard next != value else { return }
        value = next
        NotificationCenter.default.post(name: Self.changedName, object: self)
    }

    func clear() { update(nil) }
}

/// 朗读高亮的颜色：暖色半透明底，深浅主题都能看清且不遮字（对应参考图二）。
enum ReaderAloudHighlightStyle {
    static let color = UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0.95, green: 0.78, blue: 0.45, alpha: 0.28)
            : UIColor(red: 0.86, green: 0.70, blue: 0.40, alpha: 0.38)
    }

    /// 按阅读背景亮度选色（阅读主题与系统深浅色无关）。
    static func color(forBackground background: UIColor) -> UIColor {
        var white: CGFloat = 1
        var alpha: CGFloat = 1
        if !background.getWhite(&white, alpha: &alpha) {
            var r: CGFloat = 1, g: CGFloat = 1, b: CGFloat = 1
            background.getRed(&r, green: &g, blue: &b, alpha: &alpha)
            white = 0.299 * r + 0.587 * g + 0.114 * b
        }
        return white < 0.45
            ? UIColor(red: 0.95, green: 0.78, blue: 0.45, alpha: 0.28)
            : UIColor(red: 0.86, green: 0.70, blue: 0.40, alpha: 0.38)
    }
}
