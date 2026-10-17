import SwiftUI

/// 阅读器书签列表：按章节排序，点按回到原处，左滑删除。只读本机文件。
struct ReaderBookmarkList: View {
    @ThemePalette private var palette
    @Environment(\.dismiss) private var dismiss
    let book: Book
    let currentChapter: Int
    let onOpen: (ReaderBookmark) -> Void
    let onDelete: (String) -> Void
    @State private var items: [ReaderBookmark] = []

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "bookmark").font(.system(size: 34)).foregroundStyle(palette.secondary)
                        Text("还没有书签").appFont(.headline)
                        Text("长按正文选中文字，在菜单里点「书签」就能记住这一段。")
                            .appFont(.subheadline).foregroundStyle(palette.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(36).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("reader.bookmarks.empty")
                } else {
                    List {
                        ForEach(items) { item in
                            Button {
                                onOpen(item)
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(item.label).appFont(.subheadline).foregroundStyle(palette.primary)
                                        .lineLimit(3).multilineTextAlignment(.leading)
                                    Text(item.chapterTitle).appFont(.caption).foregroundStyle(palette.secondary).lineLimit(1)
                                    Text(item.createdAt, style: .date).appFont(.caption2).foregroundStyle(palette.secondary)
                                }
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("reader.bookmark.\(item.id)")
                        }
                        .onDelete { offsets in
                            for index in offsets where items.indices.contains(index) {
                                onDelete(items[index].id)
                            }
                            items.remove(atOffsets: offsets)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background { AppThemeCanvas().ignoresSafeArea() }
            .navigationTitle("书签（\(items.count)）")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
        }
        .onAppear { items = ReaderBookmarkStore.shared.list(bookURL: book.bookUrl) }
        .accessibilityIdentifier("reader.bookmarks")
    }
}
