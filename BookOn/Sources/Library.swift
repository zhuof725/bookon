import Foundation
import Combine

final class Library: ObservableObject {
    static let shared = Library()

    @Published private(set) var books: [Book] = []

    private let fm = FileManager.default
    private let booksDir: URL
    private let indexURL: URL
    private var chapterCache: [UUID: [Chapter]] = [:]

    private init() {
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        booksDir = docs.appendingPathComponent("Books", isDirectory: true)
        indexURL = docs.appendingPathComponent("library.json")
        try? fm.createDirectory(at: booksDir, withIntermediateDirectories: true)
        load()
    }

    // MARK: persistence

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let list = try? JSONDecoder().decode([Book].self, from: data) else { return }
        books = list.sorted { ($0.lastReadAt ?? $0.addedAt) > ($1.lastReadAt ?? $1.addedAt) }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(books) {
            try? data.write(to: indexURL, options: .atomic)
        }
    }

    // MARK: import

    enum ImportError: LocalizedError {
        case unreadable, empty
        var errorDescription: String? {
            switch self {
            case .unreadable: return "无法读取文件"
            case .empty: return "文件内容为空"
            }
        }
    }

    /// Import a TXT picked from UIDocumentPicker (security-scoped URL).
    func importTxt(from url: URL) throws -> Book {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else { throw ImportError.unreadable }
        let text = TxtParser.decode(data)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ImportError.empty }

        let chapters = TxtParser.splitChapters(text)
        let (title, author) = TxtParser.meta(fromFileName: url.lastPathComponent)
        let id = UUID()
        let fileName = id.uuidString + ".txt"
        // normalise to UTF-8 on disk so later reads are cheap
        try text.write(to: booksDir.appendingPathComponent(fileName), atomically: true, encoding: .utf8)
        try JSONEncoder().encode(chapters)
            .write(to: booksDir.appendingPathComponent(id.uuidString + ".toc.json"), options: .atomic)

        let book = Book(id: id, title: title.isEmpty ? "未命名" : title, author: author,
                        fileName: fileName, chapterCount: chapters.count)
        chapterCache[id] = chapters
        books.insert(book, at: 0)
        save()
        return book
    }

    func delete(_ book: Book) {
        books.removeAll { $0.id == book.id }
        chapterCache[book.id] = nil
        try? fm.removeItem(at: booksDir.appendingPathComponent(book.fileName))
        try? fm.removeItem(at: booksDir.appendingPathComponent(book.id.uuidString + ".toc.json"))
        save()
    }

    // MARK: reading

    func text(of book: Book) -> NSString {
        let url = booksDir.appendingPathComponent(book.fileName)
        return (try? String(contentsOf: url, encoding: .utf8)) as NSString? ?? ""
    }

    func chapters(of book: Book) -> [Chapter] {
        if let c = chapterCache[book.id] { return c }
        let url = booksDir.appendingPathComponent(book.id.uuidString + ".toc.json")
        let c = (try? JSONDecoder().decode([Chapter].self, from: Data(contentsOf: url))) ?? []
        chapterCache[book.id] = c
        return c
    }

    func updateProgress(_ book: Book, chapter: Int, progress: Double) {
        guard let i = books.firstIndex(where: { $0.id == book.id }) else { return }
        books[i].currentChapter = chapter
        books[i].currentProgress = progress
        books[i].lastReadAt = Date()
        save()
    }
}
