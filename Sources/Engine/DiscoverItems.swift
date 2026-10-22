import Foundation

// MARK: - 板块条目

/// 板块里的一个书籍条目。只带排版需要的字段，不依赖任何 UI 框架。
struct DeckItem: Identifiable, Hashable {
    let id: String
    var title: String
    var caption: String
    var cover: URL?

    init(id: String, title: String, caption: String = "", cover: URL? = nil) {
        self.id = id
        self.title = title
        self.caption = caption
        self.cover = cover
    }
}

/// 阅读记录条目（history 模板）。数据来自书架里每本书的进度字段。
struct HistoryItem: Identifiable, Hashable {
    let id: String
    var title: String
    /// 「读到 第 128 章 · 共 520 章」
    var chapterText: String
    /// 0...1，用于进度条
    var progress: Double
    /// 「今天」「昨天」「3 天前」
    var timeText: String
    /// 「继续阅读」/「从头开始」
    var actionText: String
    var cover: URL?

    init(id: String, title: String, chapterText: String, progress: Double,
         timeText: String, actionText: String = "继续阅读", cover: URL? = nil) {
        self.id = id
        self.title = title
        self.chapterText = chapterText
        self.progress = min(max(progress, 0), 1)
        self.timeText = timeText
        self.actionText = actionText
        self.cover = cover
    }
}

// MARK: - 由 Book 构造

extension DeckItem {
    /// 书源书籍 → 卡片条目。封面只认远端地址；本地书请用 App 层的 `init(localCover:)`。
    init(book: Book) {
        self.init(id: book.bookUrl,
                  title: book.name,
                  caption: book.author,
                  cover: DeckItem.remoteCoverURL(book))
    }

    /// 远端封面：只接受 http/https，避免把本地路径当网络地址去请求。
    static func remoteCoverURL(_ book: Book) -> URL? {
        guard let raw = book.coverUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty,
              let url = URL(string: raw),
              url.scheme == "http" || url.scheme == "https" else { return nil }
        return url
    }
}

extension HistoryItem {
    /// 书架书籍 → 记录条目。chapterCount 传章节目录数量，未知时传 nil。
    /// `cover` 由调用方解析（Engine 不依赖 App 层的 BookCoverLocation）。
    init(book: Book, chapterCount: Int?, now: Date = Date(), cover: URL? = nil) {
        let index = max(book.durChapterIndex, 0)
        let total = max(chapterCount ?? (index + 1), 1)
        let ratio = Double(index) / Double(total)
        self.init(
            id: book.bookUrl,
            title: book.name,
            chapterText: chapterCount.map { "读到 第 \(index + 1) 章 · 共 \($0) 章" }
                ?? "读到 第 \(index + 1) 章",
            progress: ratio,
            timeText: HistoryItem.relativeText(book.lastReadAt, now: now),
            actionText: index == 0 ? "从头开始" : "继续阅读",
            cover: cover
        )
    }

    /// 「今天」「昨天」「3 天前」「上周」——只到「上周」为止，更久的显示日期。
    static func relativeText(_ date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day],
                                           from: calendar.startOfDay(for: date),
                                           to: calendar.startOfDay(for: now)).day ?? 0
        switch days {
        case ..<0: return "刚刚"
        case 0: return "今天"
        case 1: return "昨天"
        case 2...6: return "\(days) 天前"
        case 7...13: return "上周"
        default:
            let formatter = DateFormatter()
            formatter.dateFormat = "M 月 d 日"
            return formatter.string(from: date)
        }
    }
}
