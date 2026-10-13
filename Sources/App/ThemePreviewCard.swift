import SwiftUI

/// An editorial colour study, not a miniature device. Never reads user data.
struct ThemePreviewCard: View {
    let theme: AppTheme
    let scheme: ColorScheme
    let isSelected: Bool
    var nameAccessibilityIdentifier: String?

    var body: some View {
        ThemePreviewCanvas(theme: theme, isSelected: isSelected,
                           nameAccessibilityIdentifier: nameAccessibilityIdentifier)
            .environment(\.appTheme, theme)
            .environment(\.colorScheme, scheme)
    }
}

private struct ThemePreviewCanvas: View {
    let theme: AppTheme
    let isSelected: Bool
    let nameAccessibilityIdentifier: String?
    @ThemePalette private var palette

    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.width < 220
            ZStack {
                AppThemeCanvas()
                VStack(alignment: .leading, spacing: compact ? 14 : 24) {
                    HStack {
                        Image(systemName: "book.closed")
                            .font(.system(size: compact ? 18 : 23, weight: .light))
                        Spacer()
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(palette.accent)
                        }
                    }
                    .foregroundStyle(palette.secondary)
                    Spacer(minLength: 0)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("把时间\n留给阅读")
                            .appFont(.system(size: compact ? 25 : 38, weight: .light, design: .serif))
                            .lineSpacing(5)
                            .fixedSize(horizontal: false, vertical: true)
                            .foregroundStyle(palette.primary)
                        if !compact {
                            Text("一页之间，自有天地。")
                                .appFont(.subheadline)
                                .foregroundStyle(palette.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(palette.accent)
                            .frame(width: 3, height: compact ? 28 : 38)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("山海之间")
                                .appFont(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                                .foregroundStyle(palette.primary)
                            Text("继续阅读 · 64%")
                                .appFont(.caption2)
                                .foregroundStyle(palette.secondary)
                        }
                        Spacer(minLength: 0)
                        if !compact {
                            Image(systemName: "arrow.right")
                                .foregroundStyle(palette.accent)
                        }
                    }
                    .padding(compact ? 12 : 18)
                    .background(palette.surface, in: RoundedRectangle(cornerRadius: compact ? 14 : 20))
                    if let identifier = nameAccessibilityIdentifier {
                        Text(theme.name)
                            .appFont(.caption)
                            .foregroundStyle(palette.secondary)
                            .accessibilityIdentifier(identifier)
                    }
                }
                .padding(compact ? 18 : 28)
            }
            .clipShape(RoundedRectangle(cornerRadius: compact ? 24 : 32, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: compact ? 24 : 32, style: .continuous)
                .stroke(palette.border.opacity(0.45), lineWidth: 0.5))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("主题 \(theme.name)")
        .accessibilityValue(isSelected ? "当前使用" : "未使用")
    }
}
