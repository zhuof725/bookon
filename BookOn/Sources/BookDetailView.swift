import SwiftUI

struct BookDetailView: View {
    @State var book: SearchBook
    var alternatives: [SearchBook] = []
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var library = Library.shared

    @State private var chapters: [WebChapter] = []
    @State private var loading = true
    @State private var error: String?
    @State private var openBook: Book?
    @State private var showToc = false

    private var source: BookSource? { SourceStore.shared.source(for: book.sourceUrl) }
    private var inShelf: Book? { library.contains(book) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 14) {
                    CoverView(url: book.coverUrl, title: book.name).frame(width: 90, height: 122)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(book.name).font(.title3).bold()
                        Text(book.author.isEmpty ? "未知作者" : book.author).foregroundColor(.secondary)
                        if !book.kind.isEmpty { Text(book.kind).font(.caption).foregroundColor(.accentColor) }
                        if !book.wordCount.isEmpty { Text(book.wordCount).font(.caption).foregroundColor(.secondary) }
                        if alternatives.count > 1 {
                            Menu {
                                ForEach(alternatives) { alt in
                                    Button(alt.sourceName + (alt.lastChapter.isEmpty ? "" : " · \(alt.lastChapter)")) { switchSource(alt) }
                                }
                            } label: {
                                Label("\(book.sourceName) ▾（\(alternatives.count) 源）", systemImage: "arrow.triangle.2.circlepath").font(.caption)
                            }
                        } else {
                            Text("书源：\(book.sourceName)").font(.caption).foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                }

                HStack(spacing: 12) {
                    Button { toggleShelf() } label: {
                        Label(inShelf == nil ? "加入书架" : "移出书架", systemImage: inShelf == nil ? "plus" : "checkmark")
                            .frame(maxWidth: .infinity)
                    }.buttonStyle(.bordered)
                    Button { startReading() } label: {
                        Label("开始阅读", systemImage: "book").frame(maxWidth: .infinity)
                    }.buttonStyle(.borderedProminent).disabled(chapters.isEmpty)
                }

                if !book.intro.isEmpty {
                    Text("简介").font(.headline)
                    Text(book.intro.trimmingCharacters(in: .whitespacesAndNewlines)).font(.subheadline).foregroundColor(.secondary)
                }

                HStack {
                    Text("目录").font(.headline)
                    Spacer()
                    if loading { ProgressView().scaleEffect(0.8) }
                    else if let e = error { Text(e).font(.caption).foregroundColor(.red).lineLimit(2) }
                    else {
                        Button("共 \(chapters.count) 章 ›") { showToc = true }.font(.subheadline)
                    }
                }
                if !chapters.isEmpty {
                    if let last = chapters.last { Text("最新：\(last.title)").font(.caption).foregroundColor(.secondary) }
                }
                if error != nil {
                    Button("重试") { load() }.font(.footnote)
                }
            }
            .padding()
        }
        .navigationTitle("书籍详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
        .task { load() }
        .sheet(isPresented: $showToc) {
            TocView(chapters: chapters.map { Chapter(index: $0.index, title: $0.title, url: $0.url, isVolume: $0.isVolume) },
                    current: inShelf?.currentChapter ?? -1) { idx in
                showToc = false
                startReading(at: idx)
            }
        }
        .fullScreenCover(item: $openBook) { b in ReaderView(book: b) }
    }

    private func load() {
        guard let src = source else { error = "书源不存在"; loading = false; return }
        loading = true; error = nil
        Task {
            do {
                let info = try await WebBook.bookInfo(src, book)
                await MainActor.run { book = info }
                let list = try await WebBook.chapterList(src, info)
                await MainActor.run {
                    chapters = list; loading = false
                    if let b = inShelf { persist(b) }
                }
            } catch {
                await MainActor.run { self.error = error.localizedDescription; loading = false }
            }
        }
    }

    private func switchSource(_ alt: SearchBook) {
        book = alt; chapters = []; load()
    }

    private func toggleShelf() {
        if let b = inShelf { library.delete(b) }
        else { let b = library.add(web: book); persist(b) }
    }

    /// 把详情和目录写入书架里的 Book
    @discardableResult
    private func persist(_ b: Book) -> Book {
        var nb = b
        nb.title = book.name; nb.author = book.author; nb.intro = book.intro; nb.coverUrl = book.coverUrl
        nb.kind = book.kind; nb.tocUrl = book.tocUrl; nb.variables = book.variables
        nb.sourceUrl = book.sourceUrl; nb.sourceName = book.sourceName; nb.bookUrl = book.bookUrl
        library.update(nb)
        if !chapters.isEmpty {
            library.saveChapters(chapters.map { Chapter(index: $0.index, title: $0.title, url: $0.url, isVolume: $0.isVolume) }, for: nb)
        }
        return library.books.first { $0.id == nb.id } ?? nb
    }

    private func startReading(at idx: Int? = nil) {
        var b = inShelf ?? library.add(web: book)
        b = persist(b)
        if let i = idx { library.updateProgress(b, chapter: i, progress: 0); b.currentChapter = i }
        openBook = library.books.first { $0.id == b.id } ?? b
    }
}
