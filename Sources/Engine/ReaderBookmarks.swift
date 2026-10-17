import Foundation

/// 书签：记录书籍、章节、当时选中的文字与章节内位置。只存本机。
struct ReaderBookmark: Codable, Identifiable, Equatable {
    var id: String
    var bookURL: String
    var bookName: String
    var chapterIndex: Int
    var chapterTitle: String
    /// 选中文字；未选中时为空，表示只标记这一章。
    var text: String
    /// 章节内位置（滚动模式为千分比，分页模式为页码）。
    var position: Int
    var createdAt: Date

    var label: String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? chapterTitle : trimmed
    }
}

/// 书签列表落盘。与阅读会话统计使用同一个目录，退到后台时 flush。
final class ReaderBookmarkStore {
    static let shared = ReaderBookmarkStore()

    private let fileURL: URL
    private let lock = NSLock()
    private var items: [ReaderBookmark] = []
    private var scheduled = false

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        if let data = try? Data(contentsOf: self.fileURL),
           let decoded = try? JSONDecoder().decode([ReaderBookmark].self, from: data) {
            items = decoded
        }
    }

    static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("LegadoReading", isDirectory: true)
            .appendingPathComponent("bookmarks.json")
    }

    /// 某章里是否已有相同文字（或同章无文字标记）的书签。
    func contains(bookURL: String, chapterIndex: Int, text: String) -> Bool {
        let key = Self.normalized(text)
        lock.lock(); defer { lock.unlock() }
        return items.contains { $0.bookURL == bookURL && $0.chapterIndex == chapterIndex && Self.normalized($0.text) == key }
    }

    func list(bookURL: String) -> [ReaderBookmark] {
        lock.lock(); defer { lock.unlock() }
        return items.filter { $0.bookURL == bookURL }
            .sorted { ($0.chapterIndex, $0.createdAt) < ($1.chapterIndex, $1.createdAt) }
    }

    func list() -> [ReaderBookmark] {
        lock.lock(); defer { lock.unlock() }
        return items.sorted { $0.createdAt > $1.createdAt }
    }

    /// 添加书签；同一章同一段文字视为切换（再加一次即删除）。
    @discardableResult
    func toggle(_ bookmark: ReaderBookmark) -> Bool {
        let key = Self.normalized(bookmark.text)
        lock.lock()
        if let index = items.firstIndex(where: {
            $0.bookURL == bookmark.bookURL && $0.chapterIndex == bookmark.chapterIndex && Self.normalized($0.text) == key
        }) {
            items.remove(at: index)
            lock.unlock()
            scheduleWrite()
            return false
        }
        items.append(bookmark)
        lock.unlock()
        scheduleWrite()
        return true
    }

    func remove(id: String) {
        lock.lock()
        let removed = items.contains { $0.id == id }
        items.removeAll { $0.id == id }
        lock.unlock()
        if removed { scheduleWrite() }
    }

    private static func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\u{200B}", with: "")
    }

    private func scheduleWrite() {
        lock.lock()
        guard !scheduled else { lock.unlock(); return }
        scheduled = true
        lock.unlock()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.flush()
        }
    }

    func flush() {
        lock.lock()
        let snapshot = items
        scheduled = false
        lock.unlock()
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
        var u = fileURL
        var rv = URLResourceValues(); rv.isExcludedFromBackup = true
        try? u.setResourceValues(rv)
    }
}
