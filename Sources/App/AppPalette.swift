import SwiftUI
import UIKit

/// The original neutral tokens remain the default and a compatibility reference.
/// Custom themes are delivered through the environment, never mutable globals.
enum AppPalette {
    private static func neutral(light: CGFloat, dark: CGFloat) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(white: traits.userInterfaceStyle == .dark ? dark : light, alpha: 1)
        })
    }

    static let accent = neutral(light: 0.10, dark: 0.92)
    static let background = neutral(light: 0.975, dark: 0.065)
    static let surface = neutral(light: 1.0, dark: 0.12)
    static let secondary = neutral(light: 0.43, dark: 0.67)
    static let selection = neutral(light: 0.90, dark: 0.23)
    static let border = neutral(light: 0.87, dark: 0.27)
    static let placeholderTop = neutral(light: 0.86, dark: 0.28)
    static let placeholderBottom = neutral(light: 0.65, dark: 0.17)
    static let highlight = neutral(light: 0.82, dark: 0.30)
}

/// One root modifier propagates to navigation, controls and presented SwiftUI
/// sheets. System destructive roles retain their native warning semantics.
struct MonochromeAppStyle: ViewModifier {
    @ThemePalette private var palette
    func body(content: Content) -> some View {
        content
            .tint(palette.accent)
            .accentColor(palette.accent)
    }
}
