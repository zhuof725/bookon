import Foundation
import SwiftUI

@MainActor
final class AppStore: ObservableObject {
    static let shared = AppStore()

    @Published var sources: [BookSource] = []
    @Published var books: [Book] = []

    private let dir: URL = {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return d
    }()
    private var sourcesFile: URL { dir.appendingPathComponent("bookSources.json") }
    private var booksFile: URL { dir.appendingPathComponent("bookshelf.json") }
    private var cacheDir: URL {
        let c = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("chapters")
        try? FileManager.default.createDirectory(at: c, withIntermediateDirectories: true)
        return c
    }

    init() { load() }

    func load() {
        if let d = try? Data(contentsOf: sourcesFile), let text = String(data: d, encoding: .utf8) {
            // 本机文件也可能被外部编辑/旧版本写坏：逐条解析，坏项不拖垮全部书源。
            if let outcome = try? SourceImportParser.parse(text), !outcome.sources.isEmpty {
                sources = outcome.sources
            } else if let s = try? JSONDecoder().decode([BookSource].self, from: d) {
                sources = s
            }
        }
        if let d = try? Data(contentsOf: booksFile), let b = try? JSONDecoder().decode([Book].self, from: d) {
            // Repair legacy absolute container URLs without reimporting EPUBs or
            // touching chapter contents/progress. Persist only portable references.
            books = b.map { saved in
                guard saved.origin == Self.localOrigin else { return saved }
                var updated = saved
                let canonical = BookCoverLocation.localURL(for: saved.bookUrl, documentsDirectory: dir)
                if saved.coverUrl?.isEmpty == false || FileManager.default.fileExists(atPath: canonical.path) {
                    updated.coverUrl = BookCoverLocation.localReference(for: saved.bookUrl)
                }
                return updated
            }
            if books != b { saveBooks() }
        }
    }

    func saveSources() {
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted]
        if let d = try? enc.encode(sources) { try? d.write(to: sourcesFile, options: .atomic) }
    }

    func saveBooks() {
        if let d = try? JSONEncoder().encode(books) { try? d.write(to: booksFile, options: .atomic) }
    }

    func source(for url: String) -> BookSource? { sources.first { $0.bookSourceUrl == url } }

    // MARK: 本地书

    static let localOrigin = "local"
    private var localDir: URL {
        let d = dir.appendingPathComponent("LocalBooks", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    private func localFolder(_ b: Book) -> URL { localDir.appendingPathComponent(key(b.bookUrl), isDirectory: true) }

    func isLocal(_ b: Book) -> Bool { b.origin == AppStore.localOrigin }

    /// 导入 TXT / EPUB。成功返回加入书架的书；同一文件（内容一致）重复导入会覆盖同一本。
    @discardableResult
    func importLocalBook(url: URL) throws -> Book {
        let ext = url.pathExtension.lowercased()
        let data = try Data(contentsOf: url)
        let name = url.lastPathComponent
        let parsed: LocalBookData
        switch ext {
        case "txt", "text": parsed = try LocalBook.parseTXT(data, fileName: name)
        case "epub": parsed = try LocalBook.parseEPUB(data, fileName: name)
        default: throw LocalBookError.unsupported(ext)
        }
        let id = "local://" + JavaBridge().md5Encode(String(data.count) + parsed.title + (parsed.chapters.first?.text.prefix(200).description ?? ""))
        var book = Book(bookUrl: id, name: parsed.title, origin: AppStore.localOrigin)
        book.author = parsed.author
        book.originName = ext.uppercased() + " 本地"
        book.lastChapter = parsed.chapters.last?.title
        book.wordCount = String(parsed.chapters.reduce(0) { $0 + $1.text.count }) + " 字"
        let folder = localFolder(book)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var toc: [BookChapter] = []
        for (i, ch) in parsed.chapters.enumerated() {
            let u = "\(id)#\(i)"
            toc.append(BookChapter(url: u, title: ch.title, index: i))
            try ch.text.write(to: folder.appendingPathComponent("\(i).txt"), atomically: true, encoding: .utf8)
        }
        if let cover = parsed.coverData {
            let f = folder.appendingPathComponent("cover.img")
            try cover.write(to: f, options: .atomic)
            book.coverUrl = BookCoverLocation.localReference(for: id)
        }
        saveLocalToc(book, toc)
        if let old = books.first(where: { $0.bookUrl == book.bookUrl }) {
            book.durChapterIndex = old.durChapterIndex; book.durChapterPos = old.durChapterPos; book.durChapterTitle = old.durChapterTitle
        }
        addToShelf(book)
        return book
    }

    func localToc(_ b: Book) -> [BookChapter]? {
        guard let d = try? Data(contentsOf: localFolder(b).appendingPathComponent("toc.json")) else { return nil }
        return try? JSONDecoder().decode([BookChapter].self, from: d)
    }
    private func saveLocalToc(_ b: Book, _ toc: [BookChapter]) {
        if let d = try? JSONEncoder().encode(toc) { try? d.write(to: localFolder(b).appendingPathComponent("toc.json")) }
    }
    func localContent(_ b: Book, index: Int) -> String? {
        try? String(contentsOf: localFolder(b).appendingPathComponent("\(index).txt"), encoding: .utf8)
    }

    func deleteLocalFiles(_ b: Book) { try? FileManager.default.removeItem(at: localFolder(b)) }

    // MARK: Import
    /// 宽松导入：逐条解析，坏数据只计入失败数，不影响其余书源（与原版 Gson 行为一致）。
    @discardableResult
    func importSources(json text: String) throws -> SourceImportReport {
        let outcome = try SourceImportParser.parse(text)
        for s in outcome.sources {
            if let i = sources.firstIndex(where: { $0.bookSourceUrl == s.bookSourceUrl }) { sources[i] = s }
            else { sources.append(s) }
        }
        if !outcome.sources.isEmpty { saveSources() }
        return outcome.report
    }

    func importSources(from urlString: String) async throws -> SourceImportReport {
        let au = AnalyzeUrl(rawUrl: urlString)
        let (body, _) = try await au.fetch()
        return try importSources(json: body)
    }

    /// 书源编辑保存：编辑时按原源 URL 替换（URL 改了也原位替换），新建则追加到末尾。
    func saveEditedSource(_ s: BookSource, replacing oldURL: String?) {
        if let old = oldURL, let i = sources.firstIndex(where: { $0.bookSourceUrl == old }) {
            sources[i] = s
        } else if let i = sources.firstIndex(where: { $0.bookSourceUrl == s.bookSourceUrl }) {
            sources[i] = s
        } else {
            sources.append(s)
        }
        saveSources()
    }

    func deleteSource(_ s: BookSource) {
        sources.removeAll { $0.bookSourceUrl == s.bookSourceUrl }
        saveSources()
    }

    /// 移动到分组：用新分组替换原分组（空白则清空分组）。
    func moveSource(_ s: BookSource, toGroup group: String) {
        guard let i = sources.firstIndex(where: { $0.bookSourceUrl == s.bookSourceUrl }) else { return }
        let t = group.trimmingCharacters(in: .whitespacesAndNewlines)
        sources[i].bookSourceGroup = t.isEmpty ? nil : t
        saveSources()
    }

    /// 单个书源的配置 JSON（与导入格式一致，可直接再导入）。
    func sourceJSON(_ s: BookSource) -> String? {
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        guard let d = try? enc.encode(s) else { return nil }
        return String(data: d, encoding: .utf8)
    }

    func toggleSource(_ s: BookSource) {
        guard let i = sources.firstIndex(of: s) else { return }
        sources[i].enabled = !(sources[i].enabled ?? true)
        saveSources()
    }

    /// 批量写回：一次修改书源数组（只触发一次界面刷新），在后台串行队列编码写盘，不阻塞主线程。
    /// 逐源同步写整份书源 JSON 在书源多、校验快时会长时间占住主线程并反复分配大块内存。
    func applySourceChecks(_ updated: [BookSource]) {
        guard !updated.isEmpty else { return }
        var list = sources
        var index: [String: Int] = [:]
        for (i, s) in list.enumerated() where index[s.bookSourceUrl] == nil { index[s.bookSourceUrl] = i }
        var changed = false
        for u in updated {
            if let i = index[u.bookSourceUrl] { list[i] = u; changed = true }
        }
        guard changed else { return }
        sources = list
        saveSourcesInBackground()
    }

    private let sourcesSaveQueue = DispatchQueue(label: "AppStore.sourcesSave", qos: .utility)
    private func saveSourcesInBackground() {
        let snapshot = sources
        let file = sourcesFile
        sourcesSaveQueue.async {
            let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted]
            if let d = try? enc.encode(snapshot) { try? d.write(to: file, options: .atomic) }
        }
    }

    // MARK: Bookshelf
    func isOnShelf(_ b: Book) -> Bool { books.contains { $0.bookUrl == b.bookUrl } }

    func addToShelf(_ b: Book) {
        if let i = books.firstIndex(where: { $0.bookUrl == b.bookUrl }) { books[i] = b } else { books.insert(b, at: 0) }
        saveBooks()
        SourceCallBack.fire(SourceCallBack.addBookShelf, source: source(for: b.origin), book: b)
    }

    /// 下拉刷新写回：更新书目信息并缓存新目录，保留阅读进度；写盘合并，避免逐本重写书架 JSON。
    func applyShelfRefresh(_ book: Book, chapters: [BookChapter]) {
        if !chapters.isEmpty { saveToc(book, chapters) }
        guard let i = books.firstIndex(where: { $0.bookUrl == book.bookUrl }) else { return }
        books[i] = book
        saveBooksDebounced()
    }

    func removeFromShelf(_ b: Book) {
        if isLocal(b) { deleteLocalFiles(b) }
        books.removeAll { $0.bookUrl == b.bookUrl }; saveBooks()
        SourceCallBack.fire(SourceCallBack.delBookShelf, source: source(for: b.origin), book: b)
    }

    func updateProgress(_ b: Book, index: Int, title: String?) {
        guard let i = books.firstIndex(where: { $0.bookUrl == b.bookUrl }) else { return }
        // 换章时章内位置归零；同一章内只更新时间。
        if books[i].durChapterIndex != index { books[i].durChapterPos = 0 }
        books[i].durChapterIndex = index
        books[i].durChapterTitle = title
        books[i].lastReadAt = Date()
        saveBooks()
    }

    /// 章内阅读位置：0...1000 的千分比（滚动偏移 / 可滚动总长）。用比例而不是像素，改字号后位置大致仍对。
    func updateScrollPosition(_ b: Book, permille: Int) {
        guard let i = books.firstIndex(where: { $0.bookUrl == b.bookUrl }) else { return }
        let v = min(max(permille, 0), 1000)
        guard books[i].durChapterPos != v else { return }
        books[i].durChapterPos = v
        books[i].lastReadAt = Date()
        saveBooksDebounced()
    }

    func scrollPosition(_ b: Book) -> Int {
        books.first(where: { $0.bookUrl == b.bookUrl })?.durChapterPos ?? b.durChapterPos
    }

    /// 漫画进度：durChapterPos 存「本章第几张图」（0 起），与原版 ReadManga 一致。
    /// 与文字阅读的千分比位置共用同一字段，但一本漫画只会被漫画阅读器写入。
    func updateMangaProgress(_ b: Book, chapterIndex: Int, title: String?, page: Int) {
        guard let i = books.firstIndex(where: { $0.bookUrl == b.bookUrl }) else { return }
        books[i].durChapterIndex = chapterIndex
        books[i].durChapterTitle = title
        books[i].durChapterPos = max(page, 0)
        books[i].lastReadAt = Date()
        saveBooksDebounced()
    }

    private var saveTask: Task<Void, Never>?
    /// 滚动时会频繁更新，合并写盘；进入后台或离开页面时调用 flushProgress 立即落盘。
    private func saveBooksDebounced() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if Task.isCancelled { return }
            self?.saveBooks()
        }
    }

    func flushProgress() {
        saveTask?.cancel()
        saveTask = nil
        saveBooks()
    }

    // MARK: Chapter cache
    private func key(_ s: String) -> String { JavaBridge().md5Encode(s) }

    func cachedToc(_ b: Book) -> [BookChapter]? {
        let f = cacheDir.appendingPathComponent("toc_" + key(b.bookUrl) + ".json")
        guard let d = try? Data(contentsOf: f) else { return nil }
        return try? JSONDecoder().decode([BookChapter].self, from: d)
    }
    func saveToc(_ b: Book, _ c: [BookChapter]) {
        let f = cacheDir.appendingPathComponent("toc_" + key(b.bookUrl) + ".json")
        if let d = try? JSONEncoder().encode(c) { try? d.write(to: f) }
    }
}
