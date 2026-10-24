import SwiftUI

// Offline fixture: use the production-generated gradient/book-symbol placeholders.
// No remote covers, AppStore, import picker, or filesystem deletion is involved.
enum ShelfFixture {
    static let localOrigin = "fixture-local"

    static func resetDefaults() {
        UserDefaults.standard.set(ShelfLayout.grid.rawValue, forKey: "shelf.layout.v1")
        UserDefaults.standard.set(ShelfSort.recent.rawValue, forKey: "shelf.sort.v1")
    }

    static var summaryChecks: Bool {
        let chapters = [BookChapter(url: "volume", title: "第一卷", index: 0, isVolume: true),
                        BookChapter(url: "one", title: "第一章", index: 1),
                        BookChapter(url: "two", title: "第二章", index: 2, updateTime: "昨天")]
        var book = books[0]
        let unread = ShelfListSummary(book: book, chapters: chapters)
        guard unread.authorLine(book).contains("未读过"), unread.chapterCount == 2 else { return false }
        book.durChapterIndex = 1
        let reading = ShelfListSummary(book: book, chapters: chapters)
        guard reading.remainingCount == 1, reading.authorLine(book).contains("1章未读"),
              reading.latestLine == "昨天 · 第二章" else { return false }
        book.durChapterIndex = 2
        guard ShelfListSummary(book: book, chapters: chapters).authorLine(book).contains("已读完") else { return false }
        book.durChapterIndex = 999
        guard ShelfListSummary(book: book, chapters: chapters).authorLine(book).contains("阅读中") else { return false }
        book.lastChapter = "新章节"
        let newer = ShelfListSummary(book: book, chapters: chapters)
        return newer.latestTime == nil && newer.latestLine == "新章节"
    }

    static var books: [Book] {
        var a = Book(bookUrl: "fixture-a", name: "A 林间札记", author: "离线示例", origin: localOrigin)
        a.addedAt = Date(timeIntervalSince1970: 200)
        a.lastReadAt = Date(timeIntervalSince1970: 100)
        var b = Book(bookUrl: "fixture-b", name: "B 山海手记", author: "合成占位", origin: "fixture-catalog")
        b.durChapterIndex = 1
        b.durChapterTitle = "第二章"
        b.addedAt = Date(timeIntervalSince1970: 100)
        b.lastReadAt = Date(timeIntervalSince1970: 200)
        return [a, b]
    }
}

struct ShelfHarnessView: View {
    @State private var books = ShelfFixture.books
    @State private var selection: LibraryTab = .shelf
    @State private var selectedBook: Book?
    @State private var showReader = false
    @State private var searches = 0
    @State private var imports = 0
    @State private var removals = 0
    @State private var refreshes = 0
    @State private var refreshMessage: String?
    @AppStorage("shelf.layout.v1") private var layout = ShelfLayout.grid.rawValue
    @AppStorage("shelf.sort.v1") private var sort = ShelfSort.recent.rawValue

    private var report: String {
        let counts = ShelfFilter.allCases.map {
            ShelfBooks.visible(books, filter: $0, sort: .recent, localOrigin: ShelfFixture.localOrigin).count
        }.map(String.init).joined(separator: ",")
        let orders = ShelfSort.allCases.map { order in
            ShelfBooks.visible(books, filter: .all, sort: order, localOrigin: ShelfFixture.localOrigin)
                .map(\.id).joined(separator: ",")
        }.joined(separator: "|")
        return "summaryChecks=\(ShelfFixture.summaryChecks);books=\(books.count);counts=\(counts);orders=\(orders);layout=\(layout);sort=\(sort);search=\(searches);import=\(imports);removed=\(removals);refreshes=\(refreshes);refresh=\(refreshMessage ?? "-");tab=\(selection.rawValue)"
    }

    var body: some View {
        NavigationStack {
            // Match RootView: inset belongs to the root content, NOT NavigationStack.
            Group {
                switch selection {
                case .shelf:
                    BookshelfScreen(books: books, localOrigin: ShelfFixture.localOrigin,
                        onOpen: { selectedBook = $0; showReader = true },
                        onImport: { imports += 1 },
                        onRemove: { selected in
                            removals += selected.count
                            let ids = Set(selected.map(\.id))
                            books.removeAll { ids.contains($0.id) }
                        }, loadListChapters: { book in
                            guard book.id == "fixture-b" else { return nil }
                            return (0..<169).map { BookChapter(url: "fixture-chapter-\($0)",
                                title: "第\($0 + 1)章 测试章节", index: $0,
                                updateTime: $0 == 168 ? "2026-10-13" : nil) }
                        }, onRefresh: {
                            refreshes += 1
                            refreshMessage = "已更新 \(books.count) 本"
                            return refreshMessage
                        })
                        .navigationDestination(isPresented: $showReader) {
                            VStack(spacing: 24) {
                                Text(selectedBook?.name ?? "").accessibilityIdentifier("shelf.reader.title")
                                Text("离线阅读占位页").accessibilityIdentifier("shelf.reader")
                                Button("返回书架") { showReader = false }
                                    .accessibilityIdentifier("shelf.reader.back")
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .toolbar(.hidden, for: .navigationBar)
                        }
                case .statistics:
                    Text("统计占位页").accessibilityIdentifier("shelf.statistics")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .explore:
                    Text("探索占位页").accessibilityIdentifier("shelf.explore")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .profile:
                    Text("我的占位页").accessibilityIdentifier("shelf.profile")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .search:
                    Text("搜索占位页").accessibilityIdentifier("shelf.searchPage")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .discover:
                    Text("发现占位页").accessibilityIdentifier("shelf.discover")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                LibraryDock(selection: $selection)
            }
            .background(Color(uiColor: .systemBackground).ignoresSafeArea())
            .overlay(alignment: .topLeading) {
                // Accessibility-only diagnostics; no visible debug text in screenshots.
                Color.clear.frame(width: 1, height: 1)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Offline shelf fixture")
                    .accessibilityValue(report)
                    .accessibilityIdentifier("shelf.fixture.report")
                    .allowsHitTesting(false)
            }
        }
        .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("--shelf-dark") ? .dark : .light)
        .frame(maxWidth: ProcessInfo.processInfo.arguments.contains("--shelf-large") ? 320 : .infinity)
        .environment(\.dynamicTypeSize, ProcessInfo.processInfo.arguments.contains("--shelf-large") ? .accessibility3 : .large)
    }
}
