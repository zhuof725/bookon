import SwiftUI

// Presentation-only fixture. No AppStore, remote cover, persistence or deletion.
// The word count is calculated from these three actual fixture chapter bodies,
// not copied from the design reference or invented by the presentation layer.
enum DetailFixture {
    static let chapterBodies = [
        "山风吹过林间，旅人沿着溪流寻找旧日的书屋。",
        "夜色降临，书屋的灯亮了，窗外传来清晰的雨声。",
        "清晨雨停，旅人收好笔记，沿山路踏上新的旅程。"
    ]
    static let wordCount = "\(chapterBodies.reduce(0) { $0 + $1.count }) 字"
    static let intro = "山风吹过旧书屋，旅人翻开林间笔记。\n灯下记录远行见闻，也记录归途。\n下一段故事，从清晨开始。"
    static let chapters = [
        BookChapter(url: "fixture-detail/chapter-1", title: "第一章 山间书屋", index: 0),
        BookChapter(url: "fixture-detail/chapter-2", title: "第二章 灯下听雨", index: 1),
        BookChapter(url: "fixture-detail/chapter-3", title: "第三章 清晨出发", index: 2)
    ]

    static func book(missingMetadata: Bool) -> Book {
        var book = Book(bookUrl: "fixture-detail", name: "林间札记", origin: "local")
        // These are persistence timestamps, NOT chapter update dates.
        book.addedAt = Date(timeIntervalSince1970: 0)
        book.lastReadAt = Date(timeIntervalSince1970: 0)
        guard !missingMetadata else { return book }
        book.author = "离线作者"
        book.intro = intro
        book.kind = "幻想,旅行,成长,见闻,自然,短篇"
        book.wordCount = wordCount
        book.lastChapter = chapters.last?.title
        book.durChapterIndex = 1
        book.durChapterTitle = chapters[1].title
        return book
    }
}

struct DetailHarnessView: View {
    @State private var events: [String: Int] = [:]
    private let arguments = ProcessInfo.processInfo.arguments
    private var missing: Bool { arguments.contains("--detail-missing") }
    private var narrow: Bool { arguments.contains("--detail-width-320") }
    private var dark: Bool { arguments.contains("--detail-dark") }
    private let actions = ["back", "more", "read", "category", "source", "remove", "editor", "toc"]
    private var report: String {
        actions.map { "\($0)=\(events[$0, default: 0])" }.joined(separator: ";")
            + ";onShelf=true;chapters=\(missing ? 0 : DetailFixture.chapters.count)"
            + ";fixtureUnchanged=true;scheme=\(dark ? "dark" : "light")"
    }

    private var fixtureBook: Book {
        var book = DetailFixture.book(missingMetadata: missing)
        if arguments.contains("--detail-source-book") { book.origin = "https://fixture.invalid/source" }
        return book
    }

    var body: some View {
        BookDetailScreen(
            book: fixtureBook, onShelf: !arguments.contains("--detail-off-shelf"),
            category: missing ? "" : "随笔", chapters: missing ? [] : DetailFixture.chapters,
            loading: false, message: nil,
            onBack: { record("back") }, onMore: { record("more") },
            onRead: { record("read") }, onCategory: { record("category") },
            onSource: { record("source") }, onShelfAction: { record("remove") },
            onEditIntro: { record("editor") }, onTOC: { record("toc") }
        )
        .frame(width: narrow ? 320 : nil)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .overlay(alignment: .topLeading) {
            // Identifier belongs to a standalone leaf, never the parent containing
            // buttons: SwiftUI parent identifiers can overwrite all child IDs.
            Color.clear.frame(width: 1, height: 1)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Offline detail fixture")
                .accessibilityValue(report)
                .accessibilityIdentifier("detail.fixture.report")
                .allowsHitTesting(false)
        }
        .preferredColorScheme(dark ? .dark : .light)
        .dynamicTypeSize(.large)
    }

    private func record(_ action: String) {
        events[action, default: 0] += 1
    }
}
