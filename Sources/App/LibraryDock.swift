import SwiftUI

enum LibraryTab: Int, CaseIterable {
    case shelf, statistics, profile
    var title: String { switch self { case .shelf: return "书架"; case .statistics: return "统计"; case .profile: return "我的" } }
    var symbol: String { switch self { case .shelf: return "book.fill"; case .statistics: return "chart.bar.fill"; case .profile: return "person.fill" } }
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
                                    Image(systemName: tab.symbol)
                                        .font(.system(size: style == .icons ? 29 : 22, weight: .semibold))
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
