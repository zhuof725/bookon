import SwiftUI
import UIKit

/// App-owned colors, independent from ReadSettings' reader paper themes.
enum AppThemeBackgroundStyle: String, Codable, CaseIterable, Identifiable {
    case solid, gradient
    var id: String { rawValue }
    var title: String { self == .solid ? "纯色" : "渐变" }
}

struct AppThemeSwatches: Codable, Equatable {
    var background: String
    var backgroundEnd: String
    var surface: String
    var accent: String
    // Optional additions keep v1 snapshots and the four-color initializer valid.
    // Synthesized Codable uses decodeIfPresent / encodeIfPresent for these.
    var primaryText: String? = nil
    var secondaryText: String? = nil
    var border: String? = nil
    var selection: String? = nil
    // Shape is independently configurable in each light/dark variant too.
    var cardRadius: Double? = nil
    var cardBorder: Bool? = nil

    var allColors: [String] {
        [background, backgroundEnd, surface, accent]
            + [primaryText, secondaryText, border, selection].compactMap { $0 }
    }

    var hasCustomTextOrSelection: Bool {
        primaryText != nil || secondaryText != nil || selection != nil
    }

    func readableBackgrounds(style: AppThemeBackgroundStyle) -> [String] {
        style == .gradient
            ? [surface] + (0...12).map { AppThemeColor.mix(background, backgroundEnd, fraction: Double($0) / 12) }
            : [background, surface]
    }

    /// Shared by validation and rendering: the selection checked at save time
    /// must be the same background used by real pills and selected controls.
    func resolvedInk(style: AppThemeBackgroundStyle) -> (primary: String, secondary: String, selection: String) {
        let backgrounds = readableBackgrounds(style: style)
        let primary = primaryText ?? AppThemeColor.foreground(over: backgrounds)
        let muted = AppThemeColor.mix(primary, surface, fraction: 0.25)
        let tint = AppThemeColor.mix(surface, accent, fraction: 0.12)
        let pillLabels = [accent, primary] + [secondaryText].compactMap { $0 }
        let automaticSelection = pillLabels.allSatisfy { AppThemeColor.contrast($0, tint) >= 4.5 } ? tint : surface
        let selected = selection ?? automaticSelection
        // Preserve the exact legacy secondary default when all additions are nil.
        // New selected colors also participate in automatic secondary resolution.
        let secondaryBackgrounds = backgrounds + (hasCustomTextOrSelection ? [selected] : [])
        let secondary = secondaryText ?? (secondaryBackgrounds.allSatisfy {
            AppThemeColor.contrast(muted, $0) >= 4.5
        } ? muted : primary)
        return (primary, secondary, selected)
    }
}

struct AppTheme: Codable, Equatable, Identifiable {
    var id: String
    var name: String
    var backgroundStyle: AppThemeBackgroundStyle
    var light: AppThemeSwatches
    var dark: AppThemeSwatches
    /// Absent in legacy snapshots: retain the original layouts and font behavior.
    var customization: ThemeCustomization? = nil

    var assetIDs: Set<String> { customization?.assetIDs ?? [] }

    /// Start a neutral, independent theme; never select or clone a template.
    static func custom() -> AppTheme {
        AppTheme(id: UUID().uuidString.lowercased(), name: "自定义主题", backgroundStyle: .solid,
            light: .init(background: "F9F9F9", backgroundEnd: "F9F9F9", surface: "FFFFFF", accent: "1A1A1A"),
            dark: .init(background: "111111", backgroundEnd: "111111", surface: "1F1F1F", accent: "EBEBEB"),
            customization: ThemeCustomization())
    }

    static let cardRadiusRange: ClosedRange<Double> = 8...30
    static let defaultCardRadius: Double = 20
    static let defaultID = "builtin.monochrome"
    var isBuiltIn: Bool { id.hasPrefix("builtin.") }
    func swatches(for scheme: ColorScheme) -> AppThemeSwatches { scheme == .dark ? dark : light }

    /// Copy built-ins into a user-owned draft; never mutate a preset in place.
    func draft() -> AppTheme {
        var copy = self
        copy.id = UUID().uuidString.lowercased()
        copy.name = isBuiltIn ? name + " · 自定" : name + " 副本"
        return copy
    }

    var validationMessage: String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "请为主题填写名称。" }
        if trimmed.count > 40 { return "主题名称最多 40 个字。" }
        if let message = customization?.validationMessage { return message }
        for (label, colors) in [("浅色", light), ("深色", dark)] {
            if let radius = colors.cardRadius,
               !radius.isFinite || !Self.cardRadiusRange.contains(radius) {
                return "\(label)卡片圆角须在 8–30 点之间。"
            }
            guard colors.allColors.allSatisfy(AppThemeColor.isValid) else { return "\(label)配色包含无效颜色，请重新选择。" }
            let backgrounds = colors.readableBackgrounds(style: backgroundStyle)
            // Keep native labels/navigation legible in the chosen system mode.
            // Custom text cannot make a dark canvas valid in the light variant.
            let text = label == "深色" ? "F5F5F5" : "101010"
            guard backgrounds.allSatisfy({ AppThemeColor.contrast(text, $0) >= 4.5 }) else {
                return "\(label)背景与卡片明暗不合适，请调整颜色，以保证文字清晰。"
            }
            guard backgrounds.allSatisfy({ AppThemeColor.contrast(colors.accent, $0) >= 4.5 }) else {
                return "\(label)强调色与背景太接近，请提高对比度。"
            }
            if let primary = colors.primaryText,
               !backgrounds.allSatisfy({ AppThemeColor.contrast(primary, $0) >= 4.5 }) {
                return "\(label)主要文字与背景或卡片太接近，请提高对比度。"
            }
            if let secondary = colors.secondaryText,
               !backgrounds.allSatisfy({ AppThemeColor.contrast(secondary, $0) >= 4.5 }) {
                return "\(label)辅助文字与背景或卡片太接近，请提高对比度。"
            }
            if colors.hasCustomTextOrSelection {
                let ink = colors.resolvedInk(style: backgroundStyle)
                guard [ink.primary, ink.secondary, colors.accent].allSatisfy({
                    AppThemeColor.contrast($0, ink.selection) >= 4.5
                }) else {
                    return "\(label)选中背景与文字或强调色太接近，请调整选中背景或文字颜色。"
                }
            }
        }
        return nil
    }

    static let monochrome = AppTheme(id: defaultID, name: "经典黑白", backgroundStyle: .solid,
        light: .init(background: "F9F9F9", backgroundEnd: "F9F9F9", surface: "FFFFFF", accent: "1A1A1A"),
        dark: .init(background: "111111", backgroundEnd: "111111", surface: "1F1F1F", accent: "EBEBEB"))
    static let templates: [AppTheme] = [
        monochrome,
        AppTheme(id: "builtin.mist", name: "晨雾", backgroundStyle: .gradient,
            light: .init(background: "E4EDF6", backgroundEnd: "F5F7FC", surface: "FFFFFF", accent: "36597C"),
            dark: .init(background: "121E2B", backgroundEnd: "1F3044", surface: "293E53", accent: "BCD9F6")),
        AppTheme(id: "builtin.sage", name: "松间", backgroundStyle: .gradient,
            light: .init(background: "E1EDE5", backgroundEnd: "F5F2E8", surface: "FAFCF8", accent: "34634E"),
            dark: .init(background: "11251C", backgroundEnd: "25362B", surface: "304839", accent: "C5E5CF")),
        AppTheme(id: "builtin.rose", name: "暮色", backgroundStyle: .gradient,
            light: .init(background: "F5DFE8", backgroundEnd: "EDE6F7", surface: "FFFAFC", accent: "824460"),
            dark: .init(background: "271824", backgroundEnd: "362738", surface: "4A3546", accent: "F4C2DB")),
        AppTheme(id: "builtin.sand", name: "暖沙", backgroundStyle: .solid,
            light: .init(background: "F2EBDD", backgroundEnd: "F2EBDD", surface: "FFF9EE", accent: "72502F"),
            dark: .init(background: "272018", backgroundEnd: "272018", surface: "3D3228", accent: "EACCA1"))
    ]
}

/// Opaque sRGB colors only. Never store UIColor archives or user file paths.
enum AppThemeColor {
    static func isValid(_ hex: String) -> Bool {
        hex.utf8.count == 6 && hex.utf8.allSatisfy { (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }
    }
    static func components(_ hex: String) -> (Double, Double, Double) {
        guard isValid(hex), let value = UInt32(hex, radix: 16) else { return (0, 0, 0) }
        return (Double((value >> 16) & 255) / 255, Double((value >> 8) & 255) / 255, Double(value & 255) / 255)
    }
    static func color(_ hex: String) -> Color {
        let (r, g, b) = components(hex)
        return Color(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
    static func hex(_ color: Color, scheme: ColorScheme) -> String {
        let native = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard native.getRed(&r, green: &g, blue: &b, alpha: &a), r.isFinite, g.isFinite, b.isFinite else { return "000000" }
        return String(format: "%02X%02X%02X", Int((min(max(r, 0), 1) * 255).rounded()),
                      Int((min(max(g, 0), 1) * 255).rounded()), Int((min(max(b, 0), 1) * 255).rounded()))
    }
    static func luminance(_ hex: String) -> Double {
        let (r, g, b) = components(hex)
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }
    static func contrast(_ a: String, _ b: String) -> Double {
        let x = luminance(a), y = luminance(b)
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }
    static func foreground(over backgrounds: [String]) -> String {
        let black = backgrounds.map { contrast("101010", $0) }.min() ?? 21
        let white = backgrounds.map { contrast("F5F5F5", $0) }.min() ?? 21
        return black >= white ? "101010" : "F5F5F5"
    }
    static func mix(_ a: String, _ b: String, fraction: Double) -> String {
        let x = components(a), y = components(b), t = min(max(fraction, 0), 1)
        func channel(_ a: Double, _ b: Double) -> Int { Int(((a * (1-t) + b * t) * 255).rounded()) }
        return String(format: "%02X%02X%02X", channel(x.0, y.0), channel(x.1, y.1), channel(x.2, y.2))
    }
}
