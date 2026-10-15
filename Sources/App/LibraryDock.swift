import SwiftUI

enum LibraryTab: Int, CaseIterable {
    // 搜索固定在底栏最右边；rawValue 顺序即显示顺序，前三个保持不变以免影响已存设置与测试标识。
    case shelf, statistics, profile, search
    var title: String {
        switch self {
        case .shelf: return "书架"; case .statistics: return "统计"
        case .profile: return "我的"; case .search: return "搜索"
        }
    }
    var symbol: String {
        switch self {
        case .shelf: return "book.fill"; case .statistics: return "chart.bar.fill"
        case .profile: return "person.fill"; case .search: return "magnifyingglass"
        }
    }
    /// Customization key for ThemeCustomization.tabIcons.
    var key: String {
        switch self {
        case .shelf: return "shelf"; case .statistics: return "statistics"
        case .profile: return "profile"; case .search: return "search"
        }
    }
}

struct LibraryDock: View {
    @ThemePalette private var palette
    @Environment(\.appTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Binding var selection: LibraryTab
    // Old snapshots keep the original icon-only dock, not the new-theme default.
    private var style: ThemeTabStyle { theme.customization?.tabStyle ?? .icons }
    var body: some View {
        HStack(spacing: 0) {
            ForEach(LibraryTab.allCases, id: \.rawValue) { tab in
                Button { selection = tab } label: {
                    Group {
                        if theme.customization == nil {
                            Image(systemName: tab.symbol).font(.system(size: 29, weight: .semibold))
                        } else {
                            VStack(spacing: 3) {
                                if style != .text {
                                    TabIconView(tab: tab, iconOverride: theme.customization?.tabIcons?[tab.key],
                                                size: style == .icons ? 29 : 22)
                                        .accessibilityHidden(true)
                                }
                                if style != .icons {
                                    Text(tab.title).appFont(style == .text ? .body.weight(.semibold) : .caption)
                                        .multilineTextAlignment(.center)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }.padding(.vertical, 5).padding(.horizontal, 2)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background { if selection == tab { Capsule().fill(palette.selection) } }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain).foregroundStyle(palette.primary)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
                .accessibilityIdentifier("library.tab." + String(tab.rawValue))
            }
        }
        .padding(4)
        .frame(maxWidth: theme.customization != nil && typeSize.isAccessibilitySize ? .infinity : 276)
        .modifier(ShelfGlass(shape: Capsule()))
        .shadow(color: .black.opacity(0.035), radius: 10, x: 0, y: 4)
        .padding(.horizontal, 28).padding(.top, 6).padding(.bottom, 2)
    }
}

/// Custom-theme tab icon: imported image, SF Symbol name, or the default symbol.
/// Fills at most a square the size of the legacy glyph, so hit targets and layout
/// match an unstyled dock; decode failures silently fall back to the default.
private struct TabIconView: View {
    let tab: LibraryTab
    let iconOverride: String?
    let size: CGFloat
    @StateObject private var imageLoader = ThemeAssetImageLoader()

    private var assetID: String? {
        guard let iconOverride, ThemeAssetStore.isValidID(iconOverride) else { return nil }
        return iconOverride
    }
    private var symbolName: String {
        guard let iconOverride, !ThemeAssetStore.isValidID(iconOverride),
              ThemeAssetStore.shared.symbolImage(for: iconOverride) != nil else { return tab.symbol }
        return iconOverride
    }

    var body: some View {
        Group {
            if let image = imageLoader.image, imageLoader.assetID == assetID {
                Image(uiImage: image).resizable().scaledToFit()
                    .frame(width: 22, height: 22)
            } else {
                Image(systemName: symbolName)
                    .font(.system(size: size, weight: .semibold))
            }
        }
        .task(id: iconOverride) {
            await imageLoader.load(assetID)
        }
    }
}
