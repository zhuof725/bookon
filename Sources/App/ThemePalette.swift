import SwiftUI

struct ResolvedAppPalette {
    let accent: Color
    let background: Color
    let backgroundEnd: Color
    let surface: Color
    let primary: Color
    let secondary: Color
    let selection: Color
    let border: Color
    let placeholderTop: Color
    let placeholderBottom: Color
    let highlight: Color
    let onAccent: Color
    let gradient: Bool

    init(theme: AppTheme, scheme: ColorScheme) {
        if theme.id == AppTheme.defaultID {
            accent = AppPalette.accent
            background = AppPalette.background
            backgroundEnd = AppPalette.background
            surface = AppPalette.surface
            primary = .primary; secondary = .secondary
            selection = AppPalette.selection; border = AppPalette.border
            placeholderTop = AppPalette.placeholderTop; placeholderBottom = AppPalette.placeholderBottom
            highlight = AppPalette.highlight
            onAccent = scheme == .dark ? .black : .white
            gradient = false
            return
        }
        let colors = theme.swatches(for: scheme)
        let backgrounds = theme.backgroundStyle == .gradient
            ? [colors.surface] + (0...12).map { AppThemeColor.mix(colors.background, colors.backgroundEnd, fraction: Double($0) / 12) }
            : [colors.background, colors.surface]
        let ink = AppThemeColor.foreground(over: backgrounds)
        accent = AppThemeColor.color(colors.accent)
        background = AppThemeColor.color(colors.background)
        backgroundEnd = AppThemeColor.color(colors.backgroundEnd)
        surface = AppThemeColor.color(colors.surface)
        primary = AppThemeColor.color(ink)
        // Use opaque colors so labels stay legible over both gradient endpoints.
        let muted = AppThemeColor.mix(ink, colors.surface, fraction: 0.25)
        secondary = AppThemeColor.color(backgrounds.allSatisfy { AppThemeColor.contrast(muted, $0) >= 4.5 } ? muted : ink)
        let selectionHex = AppThemeColor.mix(colors.surface, colors.accent, fraction: 0.12)
        let highlightHex = AppThemeColor.mix(colors.surface, colors.accent, fraction: 0.18)
        // Tinted pills still carry accent-colored labels; never trade their
        // readability for a stronger selected/background tint.
        selection = AppThemeColor.color(AppThemeColor.contrast(colors.accent, selectionHex) >= 4.5
            && AppThemeColor.contrast(ink, selectionHex) >= 4.5 ? selectionHex : colors.surface)
        border = AppThemeColor.color(AppThemeColor.mix(colors.surface, ink, fraction: 0.20))
        placeholderTop = AppThemeColor.color(AppThemeColor.mix(colors.surface, colors.accent, fraction: 0.25))
        placeholderBottom = AppThemeColor.color(AppThemeColor.mix(colors.surface, colors.accent, fraction: 0.48))
        highlight = AppThemeColor.color(AppThemeColor.contrast(ink, highlightHex) >= 4.5 ? highlightHex : colors.surface)
        let buttonInk = AppThemeColor.contrast("000000", colors.accent) >= AppThemeColor.contrast("FFFFFF", colors.accent)
            ? "000000" : "FFFFFF"
        onAccent = AppThemeColor.color(buttonInk)
        gradient = theme.backgroundStyle == .gradient
    }
}

private struct AppThemeEnvironmentKey: EnvironmentKey {
    static let defaultValue = AppTheme.monochrome
}
extension EnvironmentValues {
    var appTheme: AppTheme {
        get { self[AppThemeEnvironmentKey.self] }
        set { self[AppThemeEnvironmentKey.self] = newValue }
    }
}

/// Every consumer observes both values; editing an active theme or changing the
/// system appearance invalidates the view without resetting navigation identity.
@propertyWrapper
struct ThemePalette: DynamicProperty {
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    var wrappedValue: ResolvedAppPalette { ResolvedAppPalette(theme: theme, scheme: scheme) }
}

struct AppThemeCanvas: View {
    @ThemePalette private var palette
    var body: some View {
        if palette.gradient {
            LinearGradient(colors: [palette.background, palette.backgroundEnd], startPoint: .topLeading, endPoint: .bottomTrailing)
        } else { palette.background }
    }
}

struct AppThemeRoot: ViewModifier {
    @ObservedObject var store: AppThemeStore
    init(store: AppThemeStore = .shared) { self.store = store }
    func body(content: Content) -> some View {
        content.modifier(MonochromeAppStyle()).environment(\.appTheme, store.selectedTheme)
    }
}
