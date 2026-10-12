import SwiftUI

/// A compact, synthetic app snapshot used by both the selected-theme carousel
/// and the template gallery. It intentionally contains no user bookshelf data.
struct ThemePreviewCard: View {
    let theme: AppTheme
    let scheme: ColorScheme
    let isSelected: Bool
    var nameAccessibilityIdentifier: String?

    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / 300, geometry.size.height / 430)
            ThemePreviewCardContent(
                theme: theme,
                scheme: scheme,
                isSelected: isSelected,
                nameAccessibilityIdentifier: nameAccessibilityIdentifier
            )
            .frame(width: 300, height: 430)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: 300 * scale, height: 430 * scale, alignment: .topLeading)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .environment(\.appTheme, theme)
        .environment(\.colorScheme, scheme)
    }
}

private struct ThemePreviewCardContent: View {
    let theme: AppTheme
    let scheme: ColorScheme
    let isSelected: Bool
    let nameAccessibilityIdentifier: String?
    @ThemePalette private var palette

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                AppThemeCanvas()
                VStack(spacing: 0) {
                    previewStatusBar
                    previewNavigationBar
                    shelfContent
                }
                .padding(.horizontal, 17)
                .padding(.top, 15)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(palette.onAccent)
                        .frame(width: 31, height: 31)
                        .background(palette.accent, in: Circle())
                        .padding(.top, 14)
                        .padding(.trailing, 14)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 27, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 27, style: .continuous)
                    .stroke(palette.border.opacity(0.9), lineWidth: 1)
            }
            .shadow(color: .black.opacity(scheme == .dark ? 0.22 : 0.10), radius: 16, y: 8)

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(theme.name)
                        .appFont(.headline)
                        .foregroundStyle(palette.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .ifAccessibilityIdentifier(nameAccessibilityIdentifier)
                    Text(theme.isBuiltIn ? "内置主题" : "自创主题")
                        .appFont(.caption)
                        .foregroundStyle(palette.secondary)
                }
                Spacer(minLength: 8)
                HStack(spacing: 5) {
                    Circle().fill(AppThemeColor.color(theme.swatches(for: scheme).accent))
                    Circle().fill(AppThemeColor.color(theme.swatches(for: scheme).surface))
                    Circle().fill(AppThemeColor.color(theme.swatches(for: scheme).background))
                }
                .frame(width: 48, height: 18)
                .accessibilityHidden(true)
            }
            .padding(12)
            .background(palette.surface, in: RoundedRectangle(cornerRadius: 16))
            .padding(.top, 12)
            .padding(.bottom, 2)
        }
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("主题 \(theme.name)")
        .accessibilityValue(isSelected ? "当前使用" : "未使用")
    }

    private var previewStatusBar: some View {
        HStack {
            Text("9:41")
                .appFont(.system(size: 9, weight: .semibold))
            Spacer()
            HStack(spacing: 4) {
                Image(systemName: "wifi")
                Image(systemName: "battery.100")
            }
            .font(.system(size: 8, weight: .semibold))
        }
        .foregroundStyle(palette.primary.opacity(0.72))
        .frame(height: 15)
    }

    private var previewNavigationBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "books.vertical.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(palette.accent)
            Text("我的书架")
                .appFont(.system(size: 17, weight: .semibold))
                .foregroundStyle(palette.primary)
            Spacer()
            Image(systemName: "magnifyingglass")
            Image(systemName: "ellipsis.circle")
        }
        .foregroundStyle(palette.primary.opacity(0.78))
        .frame(height: 46)
    }

    private var shelfContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("最近阅读")
                    .appFont(.subheadline.weight(.semibold))
                Spacer()
                Text("查看全部")
                    .appFont(.caption)
                    .foregroundStyle(palette.accent)
            }
            .foregroundStyle(palette.primary)

            HStack(spacing: 11) {
                ForEach(Array(previewBooks.enumerated()), id: \.offset) { item in
                    MiniBookTile(
                        title: item.element.title,
                        detail: item.element.detail,
                        tint: item.element.tint,
                        palette: palette
                    )
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("阅读进度")
                    .appFont(.caption.weight(.semibold))
                    .foregroundStyle(palette.primary)
                ProgressView(value: 0.64)
                    .tint(palette.accent)
                HStack {
                    Text("山海之间")
                    Spacer()
                    Text("64%")
                }
                .appFont(.caption2)
                .foregroundStyle(palette.secondary)
            }
            .padding(13)
            .background(palette.surface.opacity(0.86), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).stroke(palette.border.opacity(0.65), lineWidth: 1))

            Spacer(minLength: 0)
        }
        .padding(.top, 12)
    }

    private var previewBooks: [(title: String, detail: String, tint: String)] {
        [
            ("远方灯塔", "第 12 章", "365A72"),
            ("春日札记", "阅读中", "8D5B62"),
            ("星河来信", "未读", "65744A")
        ]
    }
}

private struct MiniBookTile: View {
    let title: String
    let detail: String
    let tint: String
    let palette: ResolvedAppPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(
                    colors: [AppThemeColor.color(tint), AppThemeColor.mixColor(tint, "FFFFFF", fraction: 0.34)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Text("阅")
                    .appFont(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white.opacity(0.88))
                    .padding(7)
            }
            .frame(height: 113)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            Text(title)
                .appFont(.caption.weight(.semibold))
                .foregroundStyle(palette.primary)
                .lineLimit(1)
            Text(detail)
                .appFont(.caption2)
                .foregroundStyle(palette.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension Color {
    // Kept local to the preview so all synthetic cover colors remain opaque.
    static func appThemeColor(_ hex: String) -> Color { AppThemeColor.color(hex) }
}

private extension AppThemeColor {
    static func mixColor(_ a: String, _ b: String, fraction: Double) -> Color {
        color(mix(a, b, fraction: fraction))
    }
}

private extension View {
    @ViewBuilder
    func ifAccessibilityIdentifier(_ value: String?) -> some View {
        if let value {
            accessibilityIdentifier(value)
        } else {
            self
        }
    }
}
