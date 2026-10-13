import SwiftUI

/// Shared by the search landing list and the history sheet after results appear.
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
                ForEach(history.entries, id: \.self) { query in
                    HStack(spacing: 12) {
                        Button { onSelect(query) } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "clock").foregroundStyle(palette.secondary)
                                Text(query).appFont(.body).foregroundStyle(palette.primary).lineLimit(2)
                                Spacer(minLength: 0)
                            }.frame(minHeight: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("再次搜索：" + query)
                        .accessibilityIdentifier("searchHistory.query." + query)
                        Button { history.remove(query) } label: {
                            Image(systemName: "xmark").font(.system(size: 12, weight: .medium))
                                .foregroundStyle(palette.secondary).frame(width: 44, height: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("删除搜索记录：" + query)
                        .accessibilityIdentifier("searchHistory.delete." + query)
                    }
                }
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
