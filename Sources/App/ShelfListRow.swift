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
        let status: String
        if !ShelfBooks.isStarted(book) { status = "未读过" }
        else if let remainingCount { status = remainingCount > 0 ? "\(remainingCount)章未读" : "已读完" }
        else { status = "阅读中" }
        return "\(author) · \(status)"
    }
    /// 网格封面下的小字：只显示作者（没有则显示来源名）。
    static func authorName(_ book: Book) -> String {
        nonempty(book.author) ?? nonempty(book.originName) ?? "作者未知"
    }
    static func source(_ book: Book, localOrigin: String) -> String {
        "来源：" + (book.origin == localOrigin ? "本地书籍" : (nonempty(book.originName) ?? "书源未命名"))
    }
    /// 当前章的展示行：已读章节标题。
    static func currentLine(_ book: Book) -> String? {
        guard ShelfBooks.isStarted(book) else { return nil }
        if let title = nonempty(book.durChapterTitle) { return title }
        return "第\(max(book.durChapterIndex, 0) + 1)章"
    }
    /// 最新一章（带时间，若有）。
    var latestLine: String {
        guard let latestTitle else { return "暂无章节信息" }
        return latestTime.map { "\($0) · \(latestTitle)" } ?? latestTitle
    }
    /// 网格/列表右上角的百分比：当前章位置 ÷ 目录章数。无目录不显示。
    static func progressPercent(_ book: Book, chapterCount: Int?) -> Int? {
        guard ShelfBooks.isStarted(book) else { return nil }
        if let chapterCount, chapterCount > 0 {
            return min(100, max(0, Int((Double(book.durChapterIndex) / Double(chapterCount) * 100).rounded())))
        }
        return nil
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
        HStack(alignment: .center, spacing: 12) {
            BookCoverImage(url: BookCoverLocation.url(for: book))
                .frame(width: large ? 52 : 58, height: large ? 76 : 84)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if selecting {
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20)).foregroundStyle(palette.primary)
                            .background(palette.surface, in: Circle()).padding(3)
                    }
                }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(book.name).appFont(.headline).foregroundStyle(palette.primary)
                        .lineLimit(large ? nil : 1)
                    if let author = ShelfListSummary.nonempty(summary.authorLine(book)) {
                        line(author)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let current = ShelfListSummary.currentLine(book) {
                    line("读至 " + current)
                }
                line(summary.latestLine)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let percent = ShelfListSummary.progressPercent(book, chapterCount: summary.chapterCount) {
                Text("\(percent)%")
                    .appFont(.caption).foregroundStyle(palette.secondary)
                    .fixedSize(horizontal: true, vertical: false)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
        .contentShape(Rectangle())
    }
    private func line(_ value: String) -> some View {
        Text(value).appFont(.subheadline).foregroundStyle(palette.secondary)
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
        .accessibilityLabel([book.name, value.authorLine(book), ShelfListSummary.currentLine(book),
                             ShelfListSummary.source(book, localOrigin: localOrigin), value.latestLine].compactMap { $0 }.joined(separator: "，"))
        .accessibilityValue(selecting ? (selected ? "已选择" : "未选择") : "打开阅读")
        .accessibilityIdentifier("shelf.book." + book.id)
        .contextMenu {
            Button(action: open) { Label("开始阅读", systemImage: "book") }
            Button(action: select) { Label("选择书籍", systemImage: "checkmark.circle") }
        }
        .task(id: book) { summary = ShelfListSummary(book: book, chapters: loadChapters(book)) }
    }
}
