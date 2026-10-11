import SwiftUI

enum LibraryTab: Int, CaseIterable {
    case shelf, statistics, profile
    var title: String { switch self { case .shelf: return "书架"; case .statistics: return "统计"; case .profile: return "我的" } }
    var symbol: String { switch self { case .shelf: return "book.fill"; case .statistics: return "chart.bar.fill"; case .profile: return "person.fill" } }
}

struct LibraryDock: View {
    @Binding var selection: LibraryTab
    var body: some View {
        HStack(spacing: 0) {
            ForEach(LibraryTab.allCases, id: \.rawValue) { tab in
                Button { selection = tab } label: {
                    Image(systemName: tab.symbol)
                        .font(.system(size: 29, weight: .semibold))
                        .frame(maxWidth: .infinity).frame(height: 54)
                        .background { if selection == tab { Capsule().fill(Color.primary.opacity(0.09)) } }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain).foregroundStyle(.primary)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
                .accessibilityIdentifier("library.tab." + String(tab.rawValue))
            }
        }
        .padding(4).frame(maxWidth: 276)
        .modifier(ShelfGlass(shape: Capsule()))
        .shadow(color: .black.opacity(0.035), radius: 10, x: 0, y: 4)
        .padding(.horizontal, 28).padding(.top, 6).padding(.bottom, 2)
    }
}
