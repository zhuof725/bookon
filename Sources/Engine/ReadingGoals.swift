import Foundation
import Combine

// MARK: - 目标设置

/// 阅读目标只落在 UserDefaults 里：视图用 @AppStorage 直接读写，
/// 引擎按同一组键读取，避免出现「界面显示 15、计算按 30」的两套值。
enum ReadingGoals {
    static let dailyMinutesKey = "reading.goal.dailyMinutes.v1"
    static let yearlyBooksKey = "reading.goal.yearlyBooks.v1"

    static let defaultDailyMinutes = 15
    static let defaultYearlyBooks = 12
    static let dailyRange = 5...180
    static let yearlyRange = 1...200

    static func dailyMinutes(defaults: UserDefaults = .standard) -> Int {
        let stored = defaults.integer(forKey: dailyMinutesKey)
        guard stored > 0 else { return defaultDailyMinutes }
        return min(max(stored, dailyRange.lowerBound), dailyRange.upperBound)
    }

    static func yearlyBooks(defaults: UserDefaults = .standard) -> Int {
        let stored = defaults.integer(forKey: yearlyBooksKey)
        guard stored > 0 else { return defaultYearlyBooks }
        return min(max(stored, yearlyRange.lowerBound), yearlyRange.upperBound)
    }
}

// MARK: - 听书时长

/// 听书不计入 ReadingSession（会话是「打开阅读器」的区间），单独按天累计秒数。
/// 播放器每 0.5 秒推进一次，只在真正播放时把增量交给这里。
final class ListeningStatsStore: @unchecked Sendable {
    static let shared = ListeningStatsStore()

    private let fileURL: URL
    private let calendar: Calendar
    private let lock = NSLock()
    private var totals: [String: TimeInterval] = [:]
    private var scheduled = false

    init(fileURL: URL? = nil, calendar: Calendar = .current) {
        self.calendar = calendar
        self.fileURL = fileURL ?? Self.defaultFileURL()
        if let data = try? Data(contentsOf: self.fileURL) {
            if let decoded = try? JSONDecoder().decode([String: TimeInterval].self, from: data) {
                totals = decoded
            } else if let legacy = try? JSONDecoder().decode([String: Double].self, from: data) {
                totals = legacy
            }
        }
    }

    static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("LegadoReading", isDirectory: true)
            .appendingPathComponent("listening.json")
    }

    func add(seconds: TimeInterval, at date: Date = Date()) {
        guard seconds.isFinite, seconds > 0 else { return }
        let key = ReadingStatsEngine.dayKey(date, calendar: calendar)
        lock.lock()
        totals[key, default: 0] += seconds
        lock.unlock()
        scheduleWrite()
    }

    func seconds(on date: Date) -> TimeInterval {
        seconds(dayKey: ReadingStatsEngine.dayKey(date, calendar: calendar))
    }

    func seconds(dayKey: String) -> TimeInterval {
        lock.lock(); defer { lock.unlock() }
        return totals[dayKey] ?? 0
    }

    func seconds(from start: Date, to end: Date) -> TimeInterval {
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        lock.lock()
        let snapshot = totals
        lock.unlock()
        var total: TimeInterval = 0
        var day = startDay
        while day <= endDay {
            total += snapshot[ReadingStatsEngine.dayKey(day, calendar: calendar)] ?? 0
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return total
    }

    /// 有听书时长的日期（用于连续阅读）。
    func activeDays() -> Set<String> {
        lock.lock(); defer { lock.unlock() }
        return Set(totals.filter { $0.value >= 30 }.keys)
    }

    func allTotals() -> [String: TimeInterval] {
        lock.lock(); defer { lock.unlock() }
        return totals
    }

    private func scheduleWrite() {
        lock.lock()
        guard !scheduled else { lock.unlock(); return }
        scheduled = true
        lock.unlock()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.flush()
        }
    }

    func flush() {
        lock.lock()
        let snapshot = totals
        scheduled = false
        lock.unlock()
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
        var url = fileURL
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }
}

// MARK: - 连续阅读

enum ReadingStreakEngine {
    /// 阅读会话的日期 ∪ 听书超过 30 秒的日期。
    static func activeDays(reading: Set<String>, listening: Set<String>) -> Set<String> {
        reading.union(listening)
    }

    /// 今天还没读时，连续记录保留到昨天为止，不会在零点归零。
    static func streak(days: Set<String>, today: Date, calendar: Calendar) -> (current: Int, maximum: Int) {
        guard !days.isEmpty else { return (0, 0) }
        let todayStart = calendar.startOfDay(for: today)
        var cursor = todayStart
        if !days.contains(ReadingStatsEngine.dayKey(todayStart, calendar: calendar)) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: todayStart) else { return (0, maximum(days, calendar: calendar)) }
            cursor = yesterday
        }
        var current = 0
        while days.contains(ReadingStatsEngine.dayKey(cursor, calendar: calendar)) {
            current += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
            if current > 3650 { break }
        }
        return (current, max(current, maximum(days, calendar: calendar)))
    }

    static func maximum(_ days: Set<String>, calendar: Calendar) -> Int {
        guard !days.isEmpty else { return 0 }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let dates = days.compactMap { formatter.date(from: $0) }.sorted()
        var best = 1
        var run = 1
        for index in 1..<dates.count {
            let gap = calendar.dateComponents([.day], from: calendar.startOfDay(for: dates[index - 1]),
                                              to: calendar.startOfDay(for: dates[index])).day ?? 0
            if gap == 1 {
                run += 1
                best = max(best, run)
            } else {
                run = 1
            }
        }
        return best
    }
}

// MARK: - 热力图

enum ReadingHeatmapEngine {
    /// 0 = 没有记录，1...4 按当天完成目标的百分比加深。
    static func level(seconds: TimeInterval, goalMinutes: Int) -> Int {
        guard seconds > 0 else { return 0 }
        let goal = Double(max(goalMinutes, 1)) * 60
        let ratio = seconds / goal
        if ratio < 0.25 { return 1 }
        if ratio < 0.5 { return 2 }
        if ratio < 1 { return 3 }
        return 4
    }

    /// 列 = 周（周一起），行 = 周一…周日；最后一列是今天所在周。
    static func weeks(activity: [String: TimeInterval], weekCount: Int, today: Date,
                      calendar: Calendar, goalMinutes: Int) -> [[Int]] {
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = calendar.timeZone
        guard let currentWeek = iso.dateInterval(of: .weekOfYear, for: today)?.start,
              let firstDay = calendar.date(byAdding: .day, value: -7 * max(weekCount - 1, 0), to: currentWeek)
        else { return [] }
        var columns: [[Int]] = []
        for week in 0..<max(weekCount, 1) {
            var column: [Int] = []
            for weekday in 0..<7 {
                let offset = week * 7 + weekday
                let date = calendar.date(byAdding: .day, value: offset, to: firstDay) ?? firstDay
                let key = ReadingStatsEngine.dayKey(date, calendar: calendar)
                column.append(level(seconds: activity[key] ?? 0, goalMinutes: goalMinutes))
            }
            columns.append(column)
        }
        return columns
    }

    /// 今天在网格里的位置：最后一列的星期几（周一 = 0）。
    static func todayPosition(today: Date, calendar: Calendar) -> (column: Int, row: Int) {
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = calendar.timeZone
        let weekday = iso.component(.weekday, from: today) // 周一 = 2 … 周日 = 1
        let row = (weekday + 5) % 7
        return (0, row)
    }
}

// MARK: - 读完的书

struct FinishedBook: Codable, Equatable, Identifiable {
    var bookURL: String
    var bookName: String
    var author: String = ""
    var finishedAt: Date
    var id: String { bookURL }
}

/// 「今年已读」只认这本书的最后一次读完时间；重新打开不会取消已完成。
final class FinishedBookStore: ObservableObject, @unchecked Sendable {
    static let shared = FinishedBookStore()

    @Published private(set) var revision = 0

    private let fileURL: URL
    private let lock = NSLock()
    private var books: [String: FinishedBook] = [:]

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        if let data = try? Data(contentsOf: self.fileURL),
           let decoded = try? JSONDecoder().decode([FinishedBook].self, from: data) {
            // 手写/旧版本文件可能有重复项：逐个覆盖，不用 uniqueKeysWithValues 触发崩溃。
            for entry in decoded { books[entry.bookURL] = entry }
        }
    }

    static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("LegadoReading", isDirectory: true)
            .appendingPathComponent("finished.json")
    }

    func mark(_ book: Book, at date: Date = Date()) {
        let entry = FinishedBook(bookURL: book.bookUrl, bookName: book.name,
                                 author: book.author, finishedAt: date)
        lock.lock()
        let existed = books[book.bookUrl] != nil
        books[book.bookUrl] = entry
        lock.unlock()
        if !existed { bump() }
        save()
    }

    func unmark(_ bookURL: String) {
        lock.lock()
        let removed = books.removeValue(forKey: bookURL) != nil
        lock.unlock()
        guard removed else { return }
        bump()
        save()
    }

    func toggle(_ book: Book) {
        if isFinished(book.bookUrl) { unmark(book.bookUrl) } else { mark(book) }
    }

    func isFinished(_ bookURL: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return books[bookURL] != nil
    }

    func entry(_ bookURL: String) -> FinishedBook? {
        lock.lock(); defer { lock.unlock() }
        return books[bookURL]
    }

    func all() -> [FinishedBook] {
        lock.lock(); defer { lock.unlock() }
        return books.values.sorted { $0.finishedAt > $1.finishedAt }
    }

    func finished(inYear year: Int, calendar: Calendar) -> [FinishedBook] {
        all().filter { calendar.component(.year, from: $0.finishedAt) == year }
    }

    func count(inYear year: Int, calendar: Calendar) -> Int {
        finished(inYear: year, calendar: calendar).count
    }

    /// 12 个月各读完几本。
    func monthlyCounts(year: Int, calendar: Calendar) -> [Int] {
        var counts = Array(repeating: 0, count: 12)
        for entry in finished(inYear: year, calendar: calendar) {
            let month = calendar.component(.month, from: entry.finishedAt)
            if (1...12).contains(month) { counts[month - 1] += 1 }
        }
        return counts
    }

    private func bump() { revision += 1 }

    private func save() {
        lock.lock()
        let snapshot = books.values.sorted { $0.finishedAt < $1.finishedAt }
        lock.unlock()
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

// MARK: - 阅读计划

struct ReadingPlan: Codable, Equatable, Identifiable {
    enum Mode: String, Codable, CaseIterable, Identifiable {
        case deadline, chapters, minutes
        var id: String { rawValue }
        var title: String {
            switch self {
            case .deadline: return "按日期读完"
            case .chapters: return "每天几章"
            case .minutes: return "每天几分钟"
            }
        }
    }

    var id: String
    var bookURL: String
    var bookName: String
    var mode: Mode
    var targetDate: Date?
    var perDayChapters: Int?
    var perDayMinutes: Int?
    /// 提醒时间（从 0 点起的分钟数），nil 表示不提醒。
    var reminderMinutes: Int?
    var createdAt: Date = Date()
    var checkedDays: [String] = []

    var reminderLabel: String? {
        guard let reminderMinutes else { return nil }
        return String(format: "%02d:%02d", reminderMinutes / 60, reminderMinutes % 60)
    }
}

enum ReadingPlanEngine {
    static func daysLeft(until date: Date, today: Date, calendar: Calendar) -> Int {
        let start = calendar.startOfDay(for: today)
        let end = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: start, to: end).day ?? 0
        return max(days, 0)
    }

    static func requiredChapters(remaining: Int, daysLeft: Int) -> Int {
        guard remaining > 0 else { return 0 }
        return max(1, Int(ceil(Double(remaining) / Double(max(daysLeft, 1)))))
    }

    static func summary(_ plan: ReadingPlan, chapterCount: Int?, currentChapter: Int,
                        today: Date = Date(), calendar: Calendar = .current) -> String {
        let remaining = chapterCount.map { max($0 - currentChapter, 0) }
        switch plan.mode {
        case .deadline:
            guard let target = plan.targetDate else { return "按日期读完" }
            let days = daysLeft(until: target, today: today, calendar: calendar)
            let dateText = formatDate(target, calendar: calendar)
            if let remaining, remaining > 0, days > 0 {
                let perDay = requiredChapters(remaining: remaining, daysLeft: days)
                return "还剩 \(remaining) 章 · 每天约 \(perDay) 章 · \(dateText) 读完"
            }
            return "\(dateText) 读完"
        case .chapters:
            let perDay = max(plan.perDayChapters ?? 1, 1)
            if let remaining, remaining > 0 {
                let days = Int(ceil(Double(remaining) / Double(perDay)))
                let end = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: today))
                return "每天 \(perDay) 章 · 还剩 \(remaining) 章 · \(end.map { formatDate($0, calendar: calendar) } ?? "") 读完"
            }
            return "每天 \(perDay) 章"
        case .minutes:
            return "每天 \(max(plan.perDayMinutes ?? 10, 1)) 分钟"
        }
    }

    static func formatDate(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "M月d日"
        return formatter.string(from: date)
    }

    /// 当天有没有达成这个计划。
    static func satisfies(_ plan: ReadingPlan, minutes: Int, chapters: Int) -> Bool {
        switch plan.mode {
        case .deadline:
            return minutes > 0 || chapters > 0
        case .chapters:
            return chapters >= max(plan.perDayChapters ?? 1, 1)
        case .minutes:
            return minutes >= max(plan.perDayMinutes ?? 10, 1)
        }
    }

    static func isChecked(_ plan: ReadingPlan, on date: Date, calendar: Calendar) -> Bool {
        plan.checkedDays.contains(ReadingStatsEngine.dayKey(date, calendar: calendar))
    }

    /// 用当天的阅读会话给计划打卡；阅读器关闭和打开统计页都会调用。
    static func checkDay(bookURL: String, date: Date = Date(), calendar: Calendar = .current) {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? date
        let sessions = ReadingStatsStore.shared.sessions(from: start, to: end)
            .filter { $0.bookURL == bookURL && $0.seconds > 0 }
        guard !sessions.isEmpty else { return }
        let seconds = sessions.reduce(0) { $0 + $1.seconds }
        var chapters = Set<Int>()
        for session in sessions { chapters.formUnion(session.chapters) }
        let key = ReadingStatsEngine.dayKey(start, calendar: calendar)
        let minutes = Int((seconds / 60).rounded())
        let count = chapters.count
        let update = {
            ReadingPlanStore.shared.check(dayKey: key, bookURL: bookURL, minutes: minutes, chapters: count)
        }
        if Thread.isMainThread {
            update()
        } else {
            DispatchQueue.main.async(execute: update)
        }
    }
}

final class ReadingPlanStore: ObservableObject, @unchecked Sendable {
    static let shared = ReadingPlanStore()

    @Published private(set) var plans: [ReadingPlan] = []

    private let fileURL: URL
    private let lock = NSLock()

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        if let data = try? Data(contentsOf: self.fileURL),
           let decoded = try? JSONDecoder().decode([ReadingPlan].self, from: data) {
            plans = decoded
        }
    }

    static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("LegadoReading", isDirectory: true)
            .appendingPathComponent("plans.json")
    }

    func add(_ plan: ReadingPlan) {
        plans.append(plan)
        save()
    }

    func remove(id: String) {
        plans.removeAll { $0.id == id }
        save()
    }

    func update(_ plan: ReadingPlan) {
        guard let index = plans.firstIndex(where: { $0.id == plan.id }) else { return }
        plans[index] = plan
        save()
    }

    /// 阅读器记录会话后调用：当天达成的计划自动打卡。
    func check(dayKey: String, bookURL: String, minutes: Int, chapters: Int) {
        var changed = false
        for index in plans.indices where plans[index].bookURL == bookURL {
            guard !plans[index].checkedDays.contains(dayKey) else { continue }
            guard ReadingPlanEngine.satisfies(plans[index], minutes: minutes, chapters: chapters) else { continue }
            plans[index].checkedDays.append(dayKey)
            changed = true
        }
        if changed { save() }
    }

    func checkedDays(_ plan: ReadingPlan) -> Set<String> { Set(plan.checkedDays) }

    private func save() {
        let snapshot = plans
        let url = fileURL
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

// MARK: - 统计页所需的分日数据

struct ReadingDayStat: Identifiable, Equatable {
    var dayKey: String
    var date: Date
    var reading: TimeInterval = 0
    var listening: TimeInterval = 0
    var id: String { dayKey }
    var total: TimeInterval { reading + listening }
}
