import Foundation

struct Chapter: Codable, Identifiable, Hashable {
    var id: Int { index }
    let index: Int
    let title: String
    /// UTF-16 offsets into the full text
    let start: Int
    let end: Int
}

struct Book: Codable, Identifiable, Hashable {
    let id: UUID
    var title: String
    var author: String
    /// file name inside Documents/Books
    var fileName: String
    var addedAt: Date
    var lastReadAt: Date?
    var chapterCount: Int
    var currentChapter: Int
    /// 0...1 scroll progress within the chapter
    var currentProgress: Double

    init(id: UUID = UUID(), title: String, author: String = "", fileName: String, chapterCount: Int) {
        self.id = id
        self.title = title
        self.author = author
        self.fileName = fileName
        addedAt = Date()
        lastReadAt = nil
        self.chapterCount = chapterCount
        currentChapter = 0
        currentProgress = 0
    }

    var progressText: String {
        guard chapterCount > 0 else { return "未读" }
        if lastReadAt == nil { return "未读" }
        let pct = Double(currentChapter + 1) / Double(chapterCount) * 100
        return String(format: "%.1f%%  第 %d/%d 章", pct, currentChapter + 1, chapterCount)
    }
}
