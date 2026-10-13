import SwiftUI

/// Small color cards reflect the saved theme's actual tokens, not display
/// aliases, invented presets, device mockups, or book data.
struct ThemeHomeGrid: View {
    let themes: [AppTheme]
    let selectedID: String
    let browsedID: String?
    let onBrowse: (AppTheme) -> Void
    let onCreate: () -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 0), spacing: 12),
              count: typeSize.isAccessibilitySize ? 2 : 4)
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 18) {
            ForEach(themes) { theme in
                Button { onBrowse(theme) } label: {
                    VStack(spacing: 7) {
                        ThemeHomeSwatch(theme: theme, scheme: scheme,
                                        selected: theme.id == selectedID,
                                        browsed: theme.id == browsedID)
                        tileName(theme.name)
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(theme.name)
                .accessibilityValue(theme.id == selectedID ? "当前使用" : (theme.id == browsedID ? "正在浏览，尚未使用" : "未使用"))
                .accessibilityHint("查看下方主题操作，不会立即应用")
                .accessibilityAddTraits(theme.id == selectedID ? .isSelected : [])
                .accessibilityIdentifier("theme.browse.\(theme.id)")
            }
            Button(action: onCreate) {
                VStack(spacing: 7) {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Color(uiColor: .tertiarySystemFill))
                        .aspectRatio(1.72, contentMode: .fit)
                        .frame(minHeight: 44)
                        .overlay {
                            Image(systemName: "plus")
                                .font(.system(size: 25, weight: .regular))
                                .foregroundStyle(.primary)
                        }
                    tileName("新建")
                }
                .frame(maxWidth: .infinity, alignment: .top)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("新建主题")
            .accessibilityIdentifier("theme.add")
        }
    }

    private func tileName(_ name: String) -> some View {
        Text(name)
            .appFont(.system(size: 12))
            .foregroundStyle(.primary)
            .multilineTextAlignment(.center)
            .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 32, alignment: .top)
    }
}

private struct ThemeHomeSwatch: View {
    let theme: AppTheme
    let scheme: ColorScheme
    let selected: Bool
    let browsed: Bool

    private var palette: ResolvedAppPalette {
        var preview = theme
        // Resolve concrete RGB values, avoiding nested UIKit trait ambiguity.
        if preview.id == AppTheme.defaultID { preview.id = "preview.monochrome" }
        return ResolvedAppPalette(theme: preview, scheme: scheme)
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(palette.background)
            .overlay {
                if palette.gradient {
                    LinearGradient(colors: [palette.background, palette.backgroundEnd],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                GeometryReader { geometry in
                    let width = geometry.size.width
                    let height = geometry.size.height
                    HStack(spacing: width * 0.09) {
                        Circle().fill(palette.accent)
                            .frame(width: width * 0.16, height: width * 0.16)
                        VStack(alignment: .leading, spacing: max(3, height * 0.05)) {
                            Capsule().fill(palette.primary).frame(width: width * 0.42, height: 3)
                            Capsule().fill(palette.secondary).frame(width: width * 0.34, height: 3)
                            Capsule().fill(palette.border).frame(width: width * 0.24, height: 3)
                        }
                    }
                    .frame(width: width, height: height)
                }
            }
            .aspectRatio(1.72, contentMode: .fit)
            .frame(minHeight: 44)
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(selected ? Color.primary : (browsed ? Color.secondary : Color.primary.opacity(0.08)),
                                  style: StrokeStyle(lineWidth: selected ? 2.2 : (browsed ? 1 : 0.5),
                                                     dash: browsed && !selected ? [3, 2] : []))
            }
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color(uiColor: .systemBackground))
                        .frame(width: 17, height: 17)
                        .background(Color.primary, in: Circle())
                        .padding(3)
                }
            }
            .accessibilityHidden(true)
    }
}
