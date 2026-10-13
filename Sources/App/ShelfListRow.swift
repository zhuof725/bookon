import SwiftUI

/// Presentation-only snapshot of an existing local/cached TOC. No networking,
/// persistent book mutation, or invented update dates/unread notifications.
struct ShelfListSummary: Equatable {
    var chapterCount: Int?
    var remainingCount: Int?
    var latestTitle: String?
    var latestTime: String?

    init(book: Book, chapters: [BookChapter]? = nil) {
        let readable = chapters?.filter { !$0.isVolume } ?? []
        chapterCount = readable.isEmpty ? nil : readable.count
        latestTitle = Self.nonempty(book.lastChapter) ?? readable.last.flatMap { Self.nonempty($0.title) }
        // A source's date belongs to its actual last cached chapter, not to a
        // newer title returned by bookInfo. Never substitute lastReadAt/addedAt.
        if let last = readable.last, latestTitle == Self.nonempty(last.title) {
            latestTime = Self.nonempty(last.updateTime)
        }
        if ShelfBooks.isStarted(book), let current = readable.firstIndex(where: { $0.index == book.durChapterIndex }) {
            remainingCount = readable.count - current - 1
        }
    }
    static func nonempty(_ value: String?) -> String? {
        guard let value else { return nil }
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }
    func authorLine(_ book: Book) -> String {
        let author = Self.nonempty(book.author) ?? "作者未知"
        return chapterCount.map { "\(author) · 共\($0)章" } ?? author
    }
    static func progress(_ book: Book) -> String {
        guard ShelfBooks.isStarted(book) else { return "未读" }
        if let title = nonempty(book.durChapterTitle) { return "已读：\(title)" }
        return "已读：第\(max(0, book.durChapterIndex) + 1)章"
    }
    static func source(_ book: Book, localOrigin: String) -> String {
        "来源：" + (book.origin == localOrigin ? "本地书籍" : (nonempty(book.originName) ?? "书源未命名"))
    }
    var latestLine: String {
        guard let latestTitle else { return "最新章节：暂无信息" }
        return latestTime.map { "\($0)：\(latestTitle)" } ?? "最新：\(latestTitle)"
    }
}

struct ShelfListRow: View {
    @ThemePalette private var palette
    @Environment(\.dynamicTypeSize) private var typeSize
    let book: Book
    let localOrigin: String
    let summary: ShelfListSummary
    var selecting = false
    var selected = false
    private var large: Bool { typeSize.isAccessibilitySize }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            BookCoverImage(url: BookCoverLocation.url(for: book))
                .frame(width: large ? 58 : 70, height: large ? 84 : 102)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if selecting {
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20)).foregroundStyle(palette.primary)
                            .background(palette.surface, in: Circle()).padding(3)
                    }
                }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(book.name).appFont(.headline).foregroundStyle(palette.primary)
                        .lineLimit(large ? nil : 1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !large, let remaining = summary.remainingCount, remaining > 0 {
                        Text(remaining > 99 ? "99+" : "\(remaining)")
                            .appFont(.caption2).foregroundStyle(palette.secondary)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(palette.selection, in: Capsule())
                            .accessibilityLabel("当前章之后还有\(remaining)章未读，并非新增章节")
                    }
                }
                line(summary.authorLine(book))
                line(ShelfListSummary.progress(book))
                line(ShelfListSummary.source(book, localOrigin: localOrigin))
                line(summary.latestLine)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
        .modifier(ShelfGlass(shape: RoundedRectangle(cornerRadius: palette.cornerRadius(default: 18), style: .continuous), isCard: true))
        .contentShape(RoundedRectangle(cornerRadius: 18))
    }
    private func line(_ value: String) -> some View {
        Text(value).appFont(.caption).foregroundStyle(palette.secondary)
            .lineLimit(large ? nil : 1).truncationMode(.tail)
            .fixedSize(horizontal: false, vertical: large)
    }
}

/// Lazy per-row read of existing TOCs only; reopening the shelf refreshes it.
struct ShelfListBookButton: View {
    let book: Book
    let localOrigin: String
    let selecting: Bool
    let selected: Bool
    let loadChapters: (Book) -> [BookChapter]?
    let action: () -> Void
    let open: () -> Void
    let select: () -> Void
    @State private var summary: ShelfListSummary?
    var body: some View {
        let value = summary ?? ShelfListSummary(book: book)
        Button(action: action) {
            ShelfListRow(book: book, localOrigin: localOrigin, summary: value, selecting: selecting, selected: selected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel([book.name, value.authorLine(book), ShelfListSummary.progress(book),
                             ShelfListSummary.source(book, localOrigin: localOrigin), value.latestLine].joined(separator: "，"))
        .accessibilityValue(selecting ? (selected ? "已选择" : "未选择") : "打开阅读")
        .accessibilityIdentifier("shelf.book." + book.id)
        .contextMenu {
            Button(action: open) { Label("开始阅读", systemImage: "book") }
            Button(action: select) { Label("选择书籍", systemImage: "checkmark.circle") }
        }
        .task(id: book) { summary = ShelfListSummary(book: book, chapters: loadChapters(book)) }
    }
}
