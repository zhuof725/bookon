import SwiftUI

/// Visual-only treatment for existing settings links. No actions or destinations
/// live here, so changing the presentation cannot add or redirect a feature.
struct SettingsGlassSurface: ViewModifier {
    @ThemePalette private var palette
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content
            .appGlass(in: RoundedRectangle(cornerRadius: palette.cornerRadius(default: AppLayout.radiusCard), style: .continuous), tint: palette.surface)
            .overlay {
                RoundedRectangle(cornerRadius: palette.cornerRadius(default: AppLayout.radiusCard), style: .continuous)
                    .strokeBorder(.white.opacity(scheme == .dark ? 0.12 : 0.42), lineWidth: 0.5)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
            .shadow(color: .black.opacity(scheme == .dark ? 0.09 : 0.035), radius: 4, x: 0, y: 2)
    }
}

struct SettingsGlassLabel: View {
    @ThemePalette private var palette
    @Environment(\.colorScheme) private var scheme
    let title: String
    let symbol: String
    var value: String = ""
    var chevron: Bool = true
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 23

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: min(iconSize, 32), weight: .regular))
                .foregroundStyle(palette.accent)
                .frame(width: 28).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).appFont(.body).foregroundStyle(palette.primary)
                if !value.isEmpty { Text(value).appFont(.caption).foregroundStyle(palette.secondary) }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if chevron {
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.secondary.opacity(0.55)).accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .modifier(SettingsGlassSurface())
        .contentShape(RoundedRectangle(cornerRadius: palette.cornerRadius(default: AppLayout.radiusCard), style: .continuous))
    }
}

struct SettingsGlassValue: View {
    @ThemePalette private var palette
    let title: String
    let value: String
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                Text(title).foregroundStyle(palette.primary).fixedSize()
                Spacer(minLength: 4)
                Text(value).foregroundStyle(palette.secondary).fixedSize()
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(title).foregroundStyle(palette.primary)
                Text(value).foregroundStyle(palette.secondary)
            }.fixedSize(horizontal: false, vertical: true)
        }
        .appFont(.body)
        .padding(.horizontal, 20).padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .modifier(SettingsGlassSurface())
        .accessibilityElement(children: .combine)
    }
}
