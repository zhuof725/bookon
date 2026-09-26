import Foundation

struct Chapter: Codable, Identifiable, Hashable {
    var id: Int { index }
    let index: Int
    let title: String
    /// 本地书：UTF-16 偏移；网络书：无意义（用 url）
    var start: Int = 0
    var end: Int = 0
    var url: String = ""
    var isVolume: Bool = false

    init(index: Int, title: String, start: Int, end: Int) {
        self.index = index; self.title = title; self.start = start; self.end = end
    }
    init(index: Int, title: String, url: String, isVolume: Bool = false) {
        self.index = index; self.title = title; self.url = url; self.isVolume = isVolume
    }
    enum CodingKeys: String, CodingKey { case index, title, start, end, url, isVolume }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        index = try c.decode(Int.self, forKey: .index)
        title = try c.decode(String.self, forKey: .title)
        start = try c.decodeIfPresent(Int.self, forKey: .start) ?? 0
        end = try c.decodeIfPresent(Int.self, forKey: .end) ?? 0
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
        isVolume = try c.decodeIfPresent(Bool.self, forKey: .isVolume) ?? false
    }
}

enum BookType: String, Codable { case local, web }

struct Book: Codable, Identifiable, Hashable {
    let id: UUID
    var type: BookType = .local
    var title: String
    var author: String
    var intro: String = ""
    var coverUrl: String = ""
    var kind: String = ""
    var lastChapter: String = ""
    /// 本地：Documents/Books 内文件名；网络：空
    var fileName: String = ""
    /// 网络书
    var sourceUrl: String = ""
    var sourceName: String = ""
    var bookUrl: String = ""
    var tocUrl: String = ""
    var variables: [String: String] = [:]

    var addedAt: Date
    var lastReadAt: Date?
    var chapterCount: Int
    var currentChapter: Int
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

    init(web sb: SearchBook) {
        id = UUID()
        type = .web
        title = sb.name; author = sb.author; intro = sb.intro; coverUrl = sb.coverUrl
        kind = sb.kind; lastChapter = sb.lastChapter
        sourceUrl = sb.sourceUrl; sourceName = sb.sourceName
        bookUrl = sb.bookUrl; tocUrl = sb.tocUrl; variables = sb.variables
        addedAt = Date(); lastReadAt = nil
        chapterCount = 0; currentChapter = 0; currentProgress = 0
    }

    var asSearchBook: SearchBook {
        SearchBook(sourceUrl: sourceUrl, sourceName: sourceName, name: title, author: author, kind: kind, intro: intro,
                   lastChapter: lastChapter, coverUrl: coverUrl, bookUrl: bookUrl, wordCount: "", tocUrl: tocUrl, infoHtml: nil, variables: variables)
    }

    var progressText: String {
        guard chapterCount > 0 else { return type == .web ? "未加载目录" : "未读" }
        if lastReadAt == nil { return "未读 · 共 \(chapterCount) 章" }
        let pct = Double(currentChapter + 1) / Double(chapterCount) * 100
        return String(format: "%.1f%%  第 %d/%d 章", pct, currentChapter + 1, chapterCount)
    }

    // Codable 兼容旧版本（字段缺省）
    enum CodingKeys: String, CodingKey {
        case id, type, title, author, intro, coverUrl, kind, lastChapter, fileName, sourceUrl, sourceName, bookUrl, tocUrl, variables,
             addedAt, lastReadAt, chapterCount, currentChapter, currentProgress
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        type = try c.decodeIfPresent(BookType.self, forKey: .type) ?? .local
        title = try c.decode(String.self, forKey: .title)
        author = try c.decodeIfPresent(String.self, forKey: .author) ?? ""
        intro = try c.decodeIfPresent(String.self, forKey: .intro) ?? ""
        coverUrl = try c.decodeIfPresent(String.self, forKey: .coverUrl) ?? ""
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? ""
        lastChapter = try c.decodeIfPresent(String.self, forKey: .lastChapter) ?? ""
        fileName = try c.decodeIfPresent(String.self, forKey: .fileName) ?? ""
        sourceUrl = try c.decodeIfPresent(String.self, forKey: .sourceUrl) ?? ""
        sourceName = try c.decodeIfPresent(String.self, forKey: .sourceName) ?? ""
        bookUrl = try c.decodeIfPresent(String.self, forKey: .bookUrl) ?? ""
        tocUrl = try c.decodeIfPresent(String.self, forKey: .tocUrl) ?? ""
        variables = try c.decodeIfPresent([String: String].self, forKey: .variables) ?? [:]
        addedAt = try c.decodeIfPresent(Date.self, forKey: .addedAt) ?? Date()
        lastReadAt = try c.decodeIfPresent(Date.self, forKey: .lastReadAt)
        chapterCount = try c.decodeIfPresent(Int.self, forKey: .chapterCount) ?? 0
        currentChapter = try c.decodeIfPresent(Int.self, forKey: .currentChapter) ?? 0
        currentProgress = try c.decodeIfPresent(Double.self, forKey: .currentProgress) ?? 0
    }
}
