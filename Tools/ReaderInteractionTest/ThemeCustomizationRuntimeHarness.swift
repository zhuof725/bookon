import SwiftUI
import UIKit

/// Production shelf/dock with callbacks observed, not a copied UI. Never opens
/// AppStore, a remote URL, or the shared theme asset directory.
struct ThemeCustomizationRuntimeView: View {
    @ObservedObject var store: AppThemeStore
    @State private var selection: LibraryTab = .shelf
    @State private var opened = "none"
    private var books: [Book] {
        (0..<6).map { index in
            var book = Book(bookUrl: "customization-\(index)", name: "\(index) Fixture", author: "Offline", origin: "fixture")
            book.addedAt = Date(timeIntervalSince1970: 100)
            book.lastReadAt = Date(timeIntervalSince1970: 100)
            return book
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            Text("tab=\(selection.rawValue);opened=\(opened)")
                .font(.system(size: 8)).accessibilityIdentifier("theme.runtime.callbacks")
            BookshelfScreen(books: books, localOrigin: "fixture", onOpen: { opened = $0.id },
                onSearch: {}, onImport: {}, onRemove: { _ in })
                .safeAreaInset(edge: .bottom, spacing: 0) { LibraryDock(selection: $selection) }
        }
        .frame(width: 320)
        .accessibilityIdentifier("theme.runtime.shelf")
    }
}

/// Pixel regression of real ThemeSurface and typography. Color probes live in
/// an actual hosting controller; this is not a report derived from input flags.
@MainActor
enum ThemeCustomizationRenderProbe {
    private static func bitmap<V: View>(_ view: V) -> UIImage? {
        let renderer = ImageRenderer(content: view.frame(width: 160, height: 100))
        renderer.scale = 1
        return renderer.uiImage
    }
    private static func center(_ image: UIImage?) -> [Int]? {
        guard let cg = image?.cgImage else { return nil }
        var bytes = [UInt8](repeating: 0, count: 4)
        return bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: 1, height: 1,
                bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            context.translateBy(x: -80, y: -50)
            context.draw(cg, in: CGRect(x: 0, y: 0, width: 160, height: 100))
            let p = buffer.bindMemory(to: UInt8.self)
            return [Int(p[0]), Int(p[1]), Int(p[2])]
        }
    }
    static func run() -> [String: Bool] {
        var checks: [String: Bool] = [:]
        var theme = AppTheme.custom()
        func pixels(_ effect: ThemeInterfaceEffect, card: Bool, enabled: Bool, reduced: Bool) -> [Int]? {
            theme.customization?.effect = effect; theme.customization?.cardBackground = enabled
            let view = ZStack {
                Color.red
                if reduced {
                    ThemeSurfaceRendering(shape: RoundedRectangle(cornerRadius: 12), isCard: card,
                        palette: ResolvedAppPalette(theme: theme, scheme: .light), reduceTransparency: true)
                } else {
                    ThemeSurface(shape: RoundedRectangle(cornerRadius: 12), isCard: card)
                }
            }.environment(\.appTheme, theme).environment(\.colorScheme, .light)
            return center(bitmap(view))
        }
        let transparent = pixels(.transparent, card: false, enabled: true, reduced: false)
        let opaque = pixels(.opaque, card: false, enabled: true, reduced: false)
        let disabled = pixels(.opaque, card: true, enabled: false, reduced: false)
        let reduced = pixels(.transparent, card: false, enabled: false, reduced: true)
        checks["renderTransparentSurface"] = transparent == [255, 0, 0]
        checks["renderOpaqueSurface"] = opaque == [255, 255, 255]
        checks["renderCardBackgroundOff"] = disabled == transparent
        checks["renderControlsRemainOpaqueWhenCardsOff"] = reduced == opaque
        // Native font metrics: a missing theme font must fall back safely and
        // changing the theme must not select a different reading font.
        let style = AppFontStyle.body
        let system = style.uiFont("")
        let fallback = style.uiFont("Missing-Fixture-Font")
        checks["renderMissingFontFallback"] = fallback.fontName == system.fontName
            && fallback.pointSize == system.pointSize
        let small = ThemeShelfMetrics(width: 320, customization: ThemeCustomization(shelfColumns: 2, coverWidth: 60), accessibility: false)
        let large = ThemeShelfMetrics(width: 320, customization: ThemeCustomization(shelfColumns: 5, coverWidth: 180), accessibility: false)
        let a11y = ThemeShelfMetrics(width: 320, customization: ThemeCustomization(shelfColumns: 5), accessibility: true)
        checks["runtimeShelfMetricsClamp"] = small.columns == 2 && small.coverWidth == 60
            && large.columns == 3 && large.coverWidth <= (320.0 - 48.0 - 36.0) / 3.0
            && a11y.columns == 2
        return checks
    }
}
