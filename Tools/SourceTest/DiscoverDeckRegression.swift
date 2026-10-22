import Foundation

/// 3D 板块与续读卡的数据换算：进度、相对时间、书名裁剪。
/// 全部离纯函数，不联网、不依赖 UIKit。
enum DiscoverDeckRegression {
    static func run(_ check: (Bool, String) -> Void) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!

        func day(_ text: String) -> Date {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd HH:mm"
            f.timeZone = calendar.timeZone
            f.calendar = calendar
            return f.date(from: text)!
        }

        let now = day("2026-10-22 15:00")

        // 1. 相对时间
        check(HistoryItem.relativeText(day("2026-10-22 09:00"), now: now) == "今天",
              "续读：今天")
        check(HistoryItem.relativeText(day("2026-10-21 23:00"), now: now) == "昨天",
              "续读：昨天（跨日按自然日算）")
        check(HistoryItem.relativeText(day("2026-10-19 10:00"), now: now) == "3 天前",
              "续读：3 天前")
        check(HistoryItem.relativeText(day("2026-10-16 10:00"), now: now) == "6 天前",
              "续读：6 天前")
        check(HistoryItem.relativeText(day("2026-10-14 10:00"), now: now) == "上周",
              "续读：8 天前显示上周")
        let old = HistoryItem.relativeText(day("2026-09-01 10:00"), now: now)
        check(old.contains("9") && old.contains("月"), "续读：超过两周显示月日")
        check(HistoryItem.relativeText(day("2026-10-25 10:00"), now: now) == "刚刚",
              "续读：未来时间不显示负数")

        // 2. 进度与章节文案
        var book = Book(bookUrl: "https://a.invalid/1", name: "盗墓笔记", origin: "src")
        book.durChapterIndex = 127
        book.lastReadAt = day("2026-10-22 09:00")

        let withCount = HistoryItem(book: book, chapterCount: 520, now: now)
        check(withCount.chapterText == "读到 第 128 章 · 共 520 章",
              "续读：章节文案（下标从 0 起，展示从 1 起）")
        check(abs(withCount.progress - 127.0 / 520.0) < 0.0001, "续读：进度 = 已读章 / 总章")
        check(withCount.actionText == "继续阅读", "续读：读过第一章显示继续阅读")

        let noCount = HistoryItem(book: book, chapterCount: nil, now: now)
        check(noCount.chapterText == "读到 第 128 章", "续读：目录未知时不显示总章数")
        check(noCount.progress > 0.9 && noCount.progress <= 1.0,
              "续读：目录未知时进度钳制在 1 以内")

        // 3. 没开始读：显示「从头开始」，进度 0
        var fresh = Book(bookUrl: "https://a.invalid/2", name: "新书", origin: "src")
        fresh.durChapterIndex = 0
        fresh.lastReadAt = now
        let freshItem = HistoryItem(book: fresh, chapterCount: 100, now: now)
        check(freshItem.progress == 0, "续读：没开始读进度为 0")
        check(freshItem.actionText == "从头开始", "续读：第 0 章显示从头开始")

        // 4. 非法输入不崩
        var weird = Book(bookUrl: "https://a.invalid/3", name: "异常", origin: "src")
        weird.durChapterIndex = -5
        let weirdItem = HistoryItem(book: weird, chapterCount: 0, now: now)
        check(weirdItem.progress == 0, "续读：负下标与 0 章不崩，进度为 0")
        check(weirdItem.chapterText.contains("第 1 章"), "续读：负下标回落到第 1 章")

        // 5. 进度永远在 0...1
        var far = Book(bookUrl: "https://a.invalid/4", name: "越界", origin: "src")
        far.durChapterIndex = 999
        let farItem = HistoryItem(book: far, chapterCount: 10, now: now)
        check(farItem.progress == 1.0, "续读：读到超出总章数时进度钳到 1")

        // 6. 书名原样保留（不做裁剪，交给 Text 的 lineLimit 处理）
        check(withCount.title == "盗墓笔记", "续读：书名原样保留")
        check(withCount.id == "https://a.invalid/1", "续读：id 用 bookUrl，去重靠它")

        // 7. 两种条目的 id 稳定性
        let deck = DeckItem(book: book)
        check(deck.id == book.bookUrl && deck.title == "盗墓笔记" && deck.caption == "src",
              "卡片：bookUrl 作 id，name 作标题，author 作副标题")
    }
}
