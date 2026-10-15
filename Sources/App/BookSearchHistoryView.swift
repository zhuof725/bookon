import SwiftUI

/// Shared by the search landing list and the history sheet after results appear.
/// 搜索记录以「小胶囊」呈现，自动换行；点胶囊重新搜索，胶囊内的 × 删除单条。
struct BookSearchHistorySection: View {
    @ThemePalette private var palette
    @ObservedObject var history: BookSearchHistory
    let onSelect: (String) -> Void
    @State private var confirmingClear = false

    var body: some View {
        Section {
            if history.entries.isEmpty {
                Text("暂无搜索记录").appFont(.subheadline).foregroundStyle(palette.secondary)
                    .accessibilityIdentifier("searchHistory.empty")
            } else {
                SearchHistoryFlow(spacing: 8) {
                    ForEach(history.entries, id: \.self) { query in chip(query) }
                }
                .padding(.vertical, 2)
            }
        } header: {
            HStack {
                Text("搜索历史").appFont(.subheadline)
                Spacer()
                if !history.entries.isEmpty {
                    Button("清空") { confirmingClear = true }
                        .appFont(.subheadline).buttonStyle(.plain)
                        .foregroundStyle(palette.accent)
                        .accessibilityIdentifier("searchHistory.clear")
                }
            }
        }
        .independentGlassRow()
        .confirmationDialog("清空搜索历史？", isPresented: $confirmingClear, titleVisibility: .visible) {
            Button("清空全部记录", role: .destructive) { history.clear() }
                .accessibilityIdentifier("searchHistory.confirmClear")
            Button("取消", role: .cancel) {}
        } message: { Text("仅删除本机搜索记录，不影响书架和阅读进度。") }
    }

    private func chip(_ query: String) -> some View {
        HStack(spacing: 2) {
            Button { onSelect(query) } label: {
                Text(query).appFont(.subheadline).foregroundStyle(palette.primary)
                    .lineLimit(1).truncationMode(.middle)
                    .padding(.leading, 13).padding(.trailing, 4).padding(.vertical, 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("再次搜索：" + query)
            .accessibilityIdentifier("searchHistory.query." + query)
            Button { history.remove(query) } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.secondary)
                    .frame(width: 22, height: 22).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 8)
            .accessibilityLabel("删除搜索记录：" + query)
            .accessibilityIdentifier("searchHistory.delete." + query)
        }
        .modifier(ShelfGlass(shape: Capsule(), isCard: true))
    }
}

/// 胶囊自动换行布局：一行放不下就换到下一行，行高取该行最高的胶囊。
struct SearchHistoryFlow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .greatestFiniteMagnitude
        var width: CGFloat = 0, rowWidth: CGFloat = 0, rowHeight: CGFloat = 0, height: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + spacing + size.width > maxWidth {
                width = max(width, rowWidth)
                height += rowHeight + spacing
                rowWidth = 0; rowHeight = 0
            }
            rowWidth += rowWidth == 0 ? size.width : size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        width = max(width, rowWidth)
        height += rowHeight
        return CGSize(width: min(width, maxWidth), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

struct BookSearchHistorySheet: View {
    @ObservedObject var history: BookSearchHistory
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                BookSearchHistorySection(history: history) { query in onSelect(query); dismiss() }
            }
            .scrollContentBackground(.hidden)
            .background { AppThemeCanvas().ignoresSafeArea() }
            .navigationTitle("搜索历史").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
        .modifier(MonochromeAppStyle()).modifier(AppTypographyRoot())
        .onAppear { history.reload() }
    }
}
