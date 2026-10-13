import SwiftUI
import UIKit

/// Neutral chrome keeps every theme comparable without applying a preview.
enum ThemeHubSurface {
    static let canvas = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let control = Color(uiColor: .tertiarySystemFill)
    static let border = Color.primary.opacity(0.10)
}

/// A compact, single-scheme component study for the live editor. No user data.
struct ThemePreviewCard: View {
    let theme: AppTheme
    let scheme: ColorScheme
    let isSelected: Bool
    var nameAccessibilityIdentifier: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            ThemeComponentCanvas()
                .environment(\.appTheme, theme)
                .environment(\.colorScheme, scheme)
                .frame(height: 104)
                .accessibilityHidden(true)
            ThemePreviewFooter(theme: theme, scheme: scheme,
                               nameAccessibilityIdentifier: nameAccessibilityIdentifier)
        }
        .modifier(ThemePreviewContainer(isSelected: isSelected))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(theme.name)，\(scheme == .light ? "浅色" : "深色")组件预览")
        .accessibilityValue(isSelected ? "当前使用" : "预览，不会应用")
    }
}

/// Both variants share the exact same component geometry; only tokens change.
struct ThemeSplitPreview: View {
    let theme: AppTheme
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                ThemeComponentCanvas()
                    .environment(\.colorScheme, .light)
                ThemeComponentCanvas()
                    .environment(\.colorScheme, .dark)
                    .mask(ThemeDiagonalMask())
            }
            .environment(\.appTheme, theme)
            .frame(height: 104)
            .accessibilityHidden(true)
            ThemePreviewFooter(theme: theme, scheme: nil, nameAccessibilityIdentifier: nil)
        }
        .modifier(ThemePreviewContainer(isSelected: isSelected))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(theme.name)，浅色与深色预览")
        .accessibilityValue(isSelected ? "当前使用" : "未使用")
    }
}

/// Actual background/surface/accent samples, never invented library metrics.
struct ThemeSwatchStrip: View {
    let theme: AppTheme
    var scheme: ColorScheme? = nil

    private var colors: [String] {
        if let scheme {
            let colors = theme.swatches(for: scheme)
            return [colors.background, colors.surface, colors.accent]
        }
        return [theme.light.background, theme.light.accent, theme.dark.background, theme.dark.accent]
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(colors.enumerated()), id: \.offset) { sample in
                Circle()
                    .fill(AppThemeColor.color(sample.element))
                    .frame(width: 9, height: 9)
                    .overlay(Circle().strokeBorder(ThemeHubSurface.border, lineWidth: 0.5))
            }
        }
        .accessibilityHidden(true)
    }
}

private struct ThemePreviewFooter: View {
    let theme: AppTheme
    let scheme: ColorScheme?
    let nameAccessibilityIdentifier: String?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: 8) {
            name
                .appFont(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            ThemeSwatchStrip(theme: theme, scheme: scheme)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .frame(minHeight: 46)
        .background(ThemeHubSurface.card)
    }

    @ViewBuilder private var name: some View {
        if let nameAccessibilityIdentifier {
            Text(theme.name).accessibilityIdentifier(nameAccessibilityIdentifier)
        } else {
            Text(theme.name)
        }
    }
}

private struct ThemePreviewContainer: ViewModifier {
    let isSelected: Bool

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ThemeHubSurface.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(isSelected ? Color.primary : ThemeHubSurface.border,
                                  lineWidth: isSelected ? 1.5 : 0.5)
            }
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(.black, in: Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(0.85), lineWidth: 1))
                        .padding(9)
                        .accessibilityHidden(true)
                }
            }
            .shadow(color: .black.opacity(0.035), radius: 6, x: 0, y: 2)
    }
}

private struct ThemeDiagonalMask: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.width * 0.62, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.width * 0.40, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

/// Abstract UI primitives intentionally have no titles, books, or progress data.
private struct ThemeComponentCanvas: View {
    @Environment(\.appTheme) private var theme
    @Environment(\.colorScheme) private var scheme

    // UIKit dynamic colors may resolve from the host instead of a nested
    // SwiftUI colorScheme. Resolve every preview through concrete RGB tokens.
    // This local copy never reaches the store or changes a persisted ID.
    private var previewTheme: AppTheme {
        var preview = theme
        if preview.id == AppTheme.defaultID { preview.id = "preview.monochrome" }
        return preview
    }
    private var palette: ResolvedAppPalette {
        ResolvedAppPalette(theme: previewTheme, scheme: scheme)
    }

    private var componentRadius: CGFloat { min(12, max(0, palette.cardRadius * 0.4)) }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                AppThemeCanvas()
                HStack(alignment: .top, spacing: 8) {
                    sidebar
                        .frame(width: max(38, geometry.size.width * 0.18))
                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 6) {
                            Circle().fill(palette.accent).frame(width: 11, height: 11)
                            VStack(alignment: .leading, spacing: 4) {
                                stroke(palette.primary, width: nil, height: 4)
                                stroke(palette.secondary, width: 40, height: 3)
                            }
                        }
                        componentCard
                    }
                    detailRail
                        .frame(width: max(34, geometry.size.width * 0.16))
                }
                .padding(10)
            }
            .environment(\.appTheme, previewTheme)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: 4).fill(palette.accent).frame(height: 13)
            RoundedRectangle(cornerRadius: 4).fill(palette.selection)
            stroke(palette.secondary, width: nil, height: 3)
            HStack(spacing: 4) {
                Capsule().fill(palette.selection)
                Capsule().fill(palette.border)
            }
            .frame(height: 7)
        }
        .padding(6)
        .modifier(ShelfGlass(shape: RoundedRectangle(cornerRadius: componentRadius), isCard: true))
    }

    private var componentCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            stroke(palette.primary, width: nil, height: 4)
            stroke(palette.secondary, width: 48, height: 3)
            Spacer(minLength: 4)
            HStack(spacing: 5) {
                Capsule().fill(palette.accent).frame(width: 28, height: 10)
                Capsule().fill(palette.selection).frame(width: 21, height: 10)
                Spacer(minLength: 0)
                Circle().fill(palette.border).frame(width: 5, height: 5)
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .modifier(ShelfGlass(shape: RoundedRectangle(cornerRadius: componentRadius), isCard: true))
    }

    private var detailRail: some View {
        VStack(alignment: .leading, spacing: 7) {
            Circle().fill(palette.accent).frame(width: 10, height: 10)
            stroke(palette.secondary, width: nil, height: 3)
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 5).fill(palette.surface)
                RoundedRectangle(cornerRadius: 5).fill(palette.selection)
            }
            .frame(maxHeight: .infinity)
            stroke(palette.accent, width: nil, height: 4)
            stroke(palette.secondary, width: nil, height: 3)
        }
    }

    private func stroke(_ color: Color, width: CGFloat?, height: CGFloat) -> some View {
        Capsule().fill(color).frame(width: width, height: height)
    }
}
