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
    let cardRadius: CGFloat
    let cardBorder: Bool
    /// Custom text needs a known backing rather than an unpredictable material.
    let usesOpaqueSurfaces: Bool
    let interfaceEffect: ThemeInterfaceEffect?
    let cardBackground: Bool
    let pageScrimOpacity: Double
    let frostedSurfaceOpacity: Double
    /// Bounded 0...1; only meaningful for themed (non-legacy) surfaces.
    let glowIntensity: Double
    /// Bounded 0...1; drives the frosted effect's tint layer.
    let surfaceOpacity: Double
    private let cardRadiusOverride: CGFloat?

    /// Existing cards keep their own geometry until a radius is explicitly set.
    func cornerRadius(default legacyRadius: CGFloat) -> CGFloat {
        cardRadiusOverride ?? legacyRadius
    }

    init(theme: AppTheme, scheme: ColorScheme) {
        let colors = theme.swatches(for: scheme)
        let radius = colors.cardRadius.flatMap { value -> CGFloat? in
            guard value.isFinite else { return nil }
            return CGFloat(min(max(value, AppTheme.cardRadiusRange.lowerBound), AppTheme.cardRadiusRange.upperBound))
        }
        cardRadiusOverride = radius
        cardRadius = radius ?? CGFloat(AppTheme.defaultCardRadius)
        cardBorder = colors.cardBorder ?? true
        usesOpaqueSurfaces = colors.hasCustomTextOrSelection
        interfaceEffect = theme.customization?.effect
        cardBackground = theme.customization?.cardBackground ?? true
        let ink = colors.resolvedInk(style: theme.backgroundStyle)
        if theme.customization?.pageBackgroundImage != nil {
            let labels = [ink.primary, ink.secondary, colors.accent, scheme == .dark ? "F5F5F5" : "101010"]
            let canvas = theme.backgroundStyle == .gradient
                ? (0...12).map { AppThemeColor.mix(colors.background, colors.backgroundEnd, fraction: Double($0) / 12) }
                : [colors.background]
            // Keep the selected wallpaper visible; a full opaque scrim defeats the setting.
            // Glass rows provide local contrast; Reduce Transparency still uses base only.
            pageScrimOpacity = min(0.35, ThemeReadability.scrimOpacity(backgrounds: canvas, labels: labels))
        } else {
            pageScrimOpacity = 1
        }
        // Native material already provides adaptive contrast. A photographic
        // scrim (72–100% opaque) here hides the very blur it is meant to protect.
        let tint = theme.customization?.surfaceOpacity ?? 0.85
        frostedSurfaceOpacity = 0.18 * (tint.isFinite ? min(max(tint, 0), 1) : 0.85)
        let glow = theme.customization?.glowIntensity ?? 0.5
        glowIntensity = glow.isFinite ? min(max(glow, 0), 1) : 0.5
        let opacity = theme.customization?.surfaceOpacity ?? 0.85
        surfaceOpacity = opacity.isFinite ? min(max(opacity, 0), 1) : 0.85
        // Geometry-only edits must not change Classic Monochrome's native colors.
        var colorDefaults = colors
        colorDefaults.cardRadius = nil
        colorDefaults.cardBorder = nil
        if theme.customization == nil, theme.id == AppTheme.defaultID,
           theme.backgroundStyle == AppTheme.monochrome.backgroundStyle,
           colorDefaults == AppTheme.monochrome.swatches(for: scheme) {
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
        accent = AppThemeColor.color(colors.accent)
        background = AppThemeColor.color(colors.background)
        backgroundEnd = AppThemeColor.color(colors.backgroundEnd)
        surface = AppThemeColor.color(colors.surface)
        // Opaque resolved text and selection exactly match save-time validation.
        primary = AppThemeColor.color(ink.primary)
        secondary = AppThemeColor.color(ink.secondary)
        selection = AppThemeColor.color(ink.selection)
        border = AppThemeColor.color(colors.border ?? AppThemeColor.mix(colors.surface, ink.primary, fraction: 0.20))
        placeholderTop = AppThemeColor.color(AppThemeColor.mix(colors.surface, colors.accent, fraction: 0.25))
        placeholderBottom = AppThemeColor.color(AppThemeColor.mix(colors.surface, colors.accent, fraction: 0.48))
        let highlightHex = AppThemeColor.mix(colors.surface, colors.accent, fraction: 0.18)
        highlight = AppThemeColor.color(AppThemeColor.contrast(ink.primary, highlightHex) >= 4.5 ? highlightHex : colors.surface)
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
    @Environment(\.appTheme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @StateObject private var imageLoader = ThemeAssetImageLoader()
    var body: some View {
        base
            .overlay {
                if let image = imageLoader.image, imageLoader.assetID == theme.customization?.pageBackgroundImage,
                   !reduceTransparency {
                    GeometryReader { geometry in
                        Image(uiImage: image).resizable().scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                            .overlay { base.opacity(palette.pageScrimOpacity) }
                            .overlay {
                                if theme.customization?.effect == .transparent, palette.glowIntensity > 0 {
                                    RadialGradient(
                                        colors: [palette.accent.opacity(0.18 * palette.glowIntensity),
                                                 palette.accent.opacity(0)],
                                        center: .center,
                                        startRadius: 0,
                                        endRadius: max(geometry.size.width, geometry.size.height) * 0.6
                                    )
                                }
                            }
                    }
                }
            }
            .task(id: theme.customization?.pageBackgroundImage) {
                await imageLoader.load(theme.customization?.pageBackgroundImage)
            }
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }

    @ViewBuilder private var base: some View {
        if palette.gradient {
            LinearGradient(colors: [palette.background, palette.backgroundEnd], startPoint: .topLeading, endPoint: .bottomTrailing)
        } else { palette.background }
    }
}

/// Native glass shared by app-owned controls; content and hit regions stay untouched.
/// Older iOS uses real backdrop material, not a translucent solid imitation.
struct AppGlassSurface<S: InsettableShape>: View {
    let shape: S
    var tint: Color
    var tintOpacity: Double
    var reduceTransparency: Bool
    @AppStorage(AppGlassMode.storageKey) private var glassEnabled = true

    init(shape: S, tint: Color = Color(uiColor: .secondarySystemBackground),
         tintOpacity: Double = 0.10, reduceTransparency: Bool = false) {
        self.shape = shape
        self.tint = tint
        self.tintOpacity = tintOpacity
        self.reduceTransparency = reduceTransparency
    }

    var body: some View {
        Group {
            if reduceTransparency || !glassEnabled {
                shape.fill(tint)
            } else if #available(iOS 26.0, *) {
                Color.clear.glassEffect(.regular.tint(tint.opacity(tintOpacity)), in: shape)
            } else {
                shape.fill(.ultraThinMaterial)
                    .overlay { shape.fill(tint.opacity(tintOpacity)) }
                    .overlay { shape.strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5) }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct AppGlassModifier<S: InsettableShape>: ViewModifier {
    let shape: S
    var tint: Color = Color(uiColor: .secondarySystemBackground)
    var tintOpacity: Double = 0.10
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        content.background {
            AppGlassSurface(shape: shape, tint: tint, tintOpacity: tintOpacity,
                            reduceTransparency: reduceTransparency)
        }
    }
}

struct IndependentGlassListRow: ViewModifier {
    @ThemePalette private var palette
    func body(content: Content) -> some View {
        content
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 14, leading: 18, bottom: 14, trailing: 18))
            .listRowBackground(
                ThemeSurface(shape: RoundedRectangle(cornerRadius: palette.cornerRadius(default: AppLayout.radiusCard)))
                    .padding(.vertical, 4)
            )
    }
}

extension View {
    func independentGlassRow() -> some View { modifier(IndependentGlassListRow()) }
    func appGlass<S: InsettableShape>(in shape: S, tint: Color = Color(uiColor: .secondarySystemBackground),
                                      tintOpacity: Double = 0.10) -> some View {
        modifier(AppGlassModifier(shape: shape, tint: tint, tintOpacity: tintOpacity))
    }
}

/// Shared custom-theme surface for shelf glass, detail cards and library cards.
/// Card backgrounds never control buttons/dock; Reduce Transparency keeps those opaque.
struct ThemeSurface<S: InsettableShape>: View {
    @ThemePalette private var palette
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let shape: S
    var isCard: Bool = false

    var body: some View {
        ThemeSurfaceRendering(shape: shape, isCard: isCard, palette: palette,
                              reduceTransparency: reduceTransparency)
    }
}

/// Explicit inputs let the native renderer be checked without attempting to
/// write SwiftUI's read-only accessibility environment. Production passes the
/// real system value through ThemeSurface above.
struct ThemeSurfaceRendering<S: InsettableShape>: View {
    let shape: S
    let isCard: Bool
    let palette: ResolvedAppPalette
    let reduceTransparency: Bool
    @AppStorage(AppGlassMode.storageKey) private var glassEnabled = true

    init(shape: S, isCard: Bool, palette: ResolvedAppPalette, reduceTransparency: Bool) {
        self.shape = shape
        self.isCard = isCard
        self.palette = palette
        self.reduceTransparency = reduceTransparency
    }

    var body: some View {
        ZStack {
            if !isCard || palette.cardBackground {
                if reduceTransparency {
                    shape.fill(palette.surface)
                } else {
                    switch isCard ? (palette.interfaceEffect ?? .frosted) : .frosted {
                    case .transparent:
                        // Real transparency: the contrast-protected canvas shows through.
                        shape.fill(Color.clear)
                        // Subtle radial glow behind the content; brightness stays
                        // capped so it never reads as a filled background.
                        if palette.glowIntensity > 0 {
                            shape.fill(
                                RadialGradient(
                                    colors: [palette.accent.opacity(0.28 * palette.glowIntensity),
                                             palette.accent.opacity(0)],
                                    center: .center,
                                    startRadius: 0,
                                    endRadius: 160
                                )
                            )
                        }
                    case .frosted:
                        AppGlassSurface(shape: shape, tint: palette.surface,
                                        tintOpacity: palette.frostedSurfaceOpacity)
                        if palette.glowIntensity > 0, glassEnabled {
                            shape.fill(RadialGradient(
                                colors: [palette.accent.opacity(0.12 * palette.glowIntensity), .clear],
                                center: .center, startRadius: 0, endRadius: 160))
                        }
                    case .opaque:
                        shape.fill(palette.surface)
                    }
                }
                if !isCard || palette.cardBorder { shape.strokeBorder(palette.border, lineWidth: 0.5) }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Cover the photograph enough that every allowed pixel keeps 4.5:1 label contrast.
/// The black/white extremes bound the luminance of all composited image pixels.
private enum ThemeReadability {
    static func scrimOpacity(backgrounds: [String], labels: [String]) -> Double {
        for step in 36...50 {
            let opacity = Double(step) / 50
            let readable = backgrounds.allSatisfy { base in
                let low = AppThemeColor.luminance(AppThemeColor.mix("000000", base, fraction: opacity))
                let high = AppThemeColor.luminance(AppThemeColor.mix("FFFFFF", base, fraction: opacity))
                return labels.allSatisfy { label in
                    let value = AppThemeColor.luminance(label)
                    if value <= low { return (low + 0.05) / (value + 0.05) >= 4.5 }
                    if value >= high { return (value + 0.05) / (high + 0.05) >= 4.5 }
                    return false
                }
            }
            if readable { return opacity }
        }
        return 1
    }
}

struct AppThemeRoot: ViewModifier {
    @ObservedObject var store: AppThemeStore
    init(store: AppThemeStore = .shared) { self.store = store }
    func body(content: Content) -> some View {
        content.modifier(MonochromeAppStyle()).environment(\.appTheme, store.selectedTheme)
    }
}
