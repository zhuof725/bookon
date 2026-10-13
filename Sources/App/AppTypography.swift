import SwiftUI
import UIKit

/// Keeps the exact original SwiftUI font for the system-default selection.
struct AppFontStyle {
    let original: Font
    let size: CGFloat
    let relativeTo: Font.TextStyle
    let uiStyle: UIFont.TextStyle
    var fontWeight: Font.Weight = .regular

    static func semantic(_ style: Font.TextStyle, _ ui: UIFont.TextStyle) -> Self {
        Self(original: .system(style), size: UIFont.preferredFont(forTextStyle: ui,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: .large)).pointSize,
             relativeTo: style, uiStyle: ui)
    }
    static let largeTitle = semantic(.largeTitle, .largeTitle)
    static let title = semantic(.title, .title1)
    static let title2 = semantic(.title2, .title2)
    static let title3 = semantic(.title3, .title3)
    static let headline = semantic(.headline, .headline).weight(.semibold)
    static let subheadline = semantic(.subheadline, .subheadline)
    static let body = semantic(.body, .body)
    static let callout = semantic(.callout, .callout)
    static let footnote = semantic(.footnote, .footnote)
    static let caption = semantic(.caption, .caption1)
    static let caption2 = semantic(.caption2, .caption2)

    static func system(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Self {
        Self(original: .system(size: size, weight: weight, design: design), size: size,
             relativeTo: .body, uiStyle: .body, fontWeight: weight)
    }
    static func system(_ style: Font.TextStyle, design: Font.Design = .default, weight: Font.Weight? = nil) -> Self {
        let ui: UIFont.TextStyle
        switch style {
        case .largeTitle: ui = .largeTitle
        case .title: ui = .title1
        case .title2: ui = .title2
        case .title3: ui = .title3
        case .headline: ui = .headline
        case .subheadline: ui = .subheadline
        case .callout: ui = .callout
        case .footnote: ui = .footnote
        case .caption: ui = .caption1
        case .caption2: ui = .caption2
        default: ui = .body
        }
        let base = semantic(style, ui)
        return Self(original: .system(style, design: design, weight: weight), size: base.size,
                    relativeTo: style, uiStyle: ui, fontWeight: weight ?? (ui == .headline ? .semibold : .regular))
    }
    func weight(_ weight: Font.Weight) -> Self {
        Self(original: original.weight(weight), size: size, relativeTo: relativeTo, uiStyle: uiStyle, fontWeight: weight)
    }
    func bold() -> Self { weight(.bold) }

    func resolve(_ name: String) -> Font {
        guard !name.isEmpty, UIFont(name: name, size: size) != nil else { return original }
        return .custom(name, size: size, relativeTo: relativeTo).weight(fontWeight)
    }
    /// Public UIKit resolver for app-owned UIKit text and native regression checks.
    func uiFont(_ name: String, category: UIContentSizeCategory = .large) -> UIFont {
        let traits = UITraitCollection(preferredContentSizeCategory: category)
        let base = UIFont(name: name, size: size) ?? UIFont.systemFont(ofSize: size)
        return UIFontMetrics(forTextStyle: uiStyle).scaledFont(for: base, compatibleWith: traits)
    }
}

struct AppTypography: ViewModifier {
    @ObservedObject private var manager = ReadingFontManager.shared
    @Environment(\.appTheme) private var theme
    let style: AppFontStyle
    private var selectedName: String {
        guard let override = theme.customization?.fontPostScriptName else { return manager.selectedPostScriptName }
        guard !override.isEmpty else { return "" }
        let available = manager.builtInFonts.contains { $0.id == override }
            || manager.importedFonts.contains { $0.faces.contains { $0.id == override } }
        // CoreText can retain a deleted font while a view still references it;
        // UIFont alone is not proof that the user's font remains available.
        return available && UIFont(name: override, size: style.size) != nil ? override : ""
    }
    func body(content: Content) -> some View {
        // nil follows the font manager; "" deliberately selects the original font.
        // Never write the manager: app typography must not repaginate reader text.
        content.font(style.resolve(selectedName))
    }
}

/// Inherited by implicit app text and fields, including presented SwiftUI content.
/// No identity reset, global appearance proxy, private traversal or swizzling.
/// UIKit/system navigation titles, system pickers and keyboards remain system-owned.
struct AppTypographyRoot: ViewModifier {
    func body(content: Content) -> some View { content.appFont(.body) }
}

extension View {
    func appFont(_ style: AppFontStyle) -> some View { modifier(AppTypography(style: style)) }
}
