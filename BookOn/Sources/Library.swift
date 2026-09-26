import Foundation
import Combine

final class Library: ObservableObject {
    static let shared = Library()

    @Published private(set) var books: [Book] = []

    private let fm = FileManager.default
    private let booksDir: URL
    private let cacheDir: URL
    private let indexURL: URL
    private var chapterCache: [UUID: [Chapter]] = [:]

    private init() {
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        booksDir = docs.appendingPathComponent("Books", isDirectory: true)
        cacheDir = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("Chapters", isDirectory: true)
        indexURL = docs.appendingPathComponent("library.json")
        try? fm.createDirectory(at: booksDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: cacheDir, withIntermediateDirectories: true)
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

    private func tocURL(_ id: UUID) -> URL { booksDir.appendingPathComponent(id.uuidString + ".toc.json") }

    // MARK: import local

    enum ImportError: LocalizedError {
        case unreadable, empty
        var errorDescription: String? {
            switch self {
            case .unreadable: return "无法读取文件"
            case .empty: return "文件内容为空"
            }
        }
    }

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
        try text.write(to: booksDir.appendingPathComponent(fileName), atomically: true, encoding: .utf8)
        try JSONEncoder().encode(chapters).write(to: tocURL(id), options: .atomic)

        let book = Book(id: id, title: title.isEmpty ? "未命名" : title, author: author,
                        fileName: fileName, chapterCount: chapters.count)
        chapterCache[id] = chapters
        books.insert(book, at: 0)
        save()
        return book
    }

    // MARK: web books

    func contains(_ sb: SearchBook) -> Book? {
        books.first { $0.type == .web && $0.bookUrl == sb.bookUrl && $0.sourceUrl == sb.sourceUrl }
            ?? books.first { $0.type == .web && $0.title == sb.name && $0.author == sb.author }
    }

    @discardableResult
    func add(web sb: SearchBook) -> Book {
        if let b = contains(sb) { return b }
        let book = Book(web: sb)
        books.insert(book, at: 0)
        save()
        return book
    }

    func update(_ book: Book) {
        guard let i = books.firstIndex(where: { $0.id == book.id }) else { return }
        books[i] = book
        save()
    }

    func saveChapters(_ chapters: [Chapter], for book: Book) {
        chapterCache[book.id] = chapters
        try? JSONEncoder().encode(chapters).write(to: tocURL(book.id), options: .atomic)
        if let i = books.firstIndex(where: { $0.id == book.id }) {
            books[i].chapterCount = chapters.count
            if let last = chapters.last { books[i].lastChapter = last.title }
            save()
        }
    }

    // 正文缓存
    private func contentURL(_ book: Book, _ idx: Int) -> URL {
        cacheDir.appendingPathComponent("\(book.id.uuidString)_\(idx).txt")
    }
    func cachedContent(_ book: Book, _ idx: Int) -> String? {
        try? String(contentsOf: contentURL(book, idx), encoding: .utf8)
    }
    func cacheContent(_ text: String, _ book: Book, _ idx: Int) {
        try? text.write(to: contentURL(book, idx), atomically: true, encoding: .utf8)
    }
    func clearCache(_ book: Book) {
        (try? fm.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil))?
            .filter { $0.lastPathComponent.hasPrefix(book.id.uuidString) }
            .forEach { try? fm.removeItem(at: $0) }
    }

    // MARK: delete

    func delete(_ book: Book) {
        books.removeAll { $0.id == book.id }
        chapterCache[book.id] = nil
        if !book.fileName.isEmpty { try? fm.removeItem(at: booksDir.appendingPathComponent(book.fileName)) }
        try? fm.removeItem(at: tocURL(book.id))
        clearCache(book)
        save()
    }

    // MARK: reading

    func text(of book: Book) -> NSString {
        guard !book.fileName.isEmpty else { return "" }
        let url = booksDir.appendingPathComponent(book.fileName)
        return (try? String(contentsOf: url, encoding: .utf8)) as NSString? ?? ""
    }

    func chapters(of book: Book) -> [Chapter] {
        if let c = chapterCache[book.id] { return c }
        let c = (try? JSONDecoder().decode([Chapter].self, from: Data(contentsOf: tocURL(book.id)))) ?? []
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
