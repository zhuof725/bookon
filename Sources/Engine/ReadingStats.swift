import Foundation
import Combine

/// 一次阅读会话的记录。只记录事实：起止时间、书籍与切换到的章节。
struct ReadingSession: Codable, Equatable {
    var start: Date
    var end: Date
    var bookURL: String
    var bookName: String
    var source: String
    var chapters: [Int]
    var seconds: TimeInterval {
        max(0, end.timeIntervalSince(start))
    }
}

/// 参考阅读应用的统计口径：同一次打开阅读器算一个「翻开」，首次点开的页签本会
/// 计入在读，之后再点同一本不算新书；一次连续的阅读区间算「一口气」。
struct ReadingDayAggregate: Equatable {
    var seconds: TimeInterval = 0
    var sessions: Int = 0
    var books: Set<String> = []
    var chapters: Set<String> = []
    var bouts: [TimeInterval] = []
    var days: Set<String> = []

    static var zero: ReadingDayAggregate { ReadingDayAggregate() }

    var isActive: Bool { seconds > 0 }

    mutating func add(_ session: ReadingSession, key: String) {
        days.insert(key)
        guard session.seconds > 0 else { return }
        seconds += session.seconds
        sessions += 1
        books.insert(session.bookURL)
        chapters.formUnion(session.chapters.map { session.bookURL + "#\($0)" })
        bouts.append(session.seconds)
    }
}

enum ReadingStatsPeriod: String, CaseIterable, Codable {
    case week, month, year
}

/// 阅读统计的纯数据计算：全部来自已落盘的会话文件，不联网、不推断。
enum ReadingStatsEngine {

    // MARK: 时间区间

    static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "zh_Hans_CN")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    static func startOfDay(_ date: Date, calendar: Calendar) -> Date {
        calendar.startOfDay(for: date)
    }

    /// 完整周期区间 [含起, 不含止)：周一至周日（ISO8601）、整月、整年。
    static func range(period: ReadingStatsPeriod, anchor: Date, calendar: Calendar) -> (start: Date, end: Date) {
        let interval: DateInterval?
        switch period {
        case .week:
            var iso = Calendar(identifier: .iso8601)
            iso.timeZone = calendar.timeZone
            interval = iso.dateInterval(of: .weekOfYear, for: anchor)
        case .month: interval = calendar.dateInterval(of: .month, for: anchor)
        case .year: interval = calendar.dateInterval(of: .year, for: anchor)
        }
        let start = interval?.start ?? startOfDay(anchor, calendar: calendar)
        return (start, interval?.end ?? calendar.date(byAdding: .day, value: 1, to: start)!)
    }

    static func bucketCount(period: ReadingStatsPeriod, anchor: Date, calendar: Calendar) -> Int {
        switch period {
        case .week: return 7
        case .month:
            let start = range(period: .month, anchor: anchor, calendar: calendar).start
            return calendar.range(of: .day, in: .month, for: start)?.count ?? 30
        case .year: return 12
        }
    }

    static func bucketStart(index: Int, period: ReadingStatsPeriod, anchor: Date, calendar: Calendar) -> Date {
        let start = range(period: period, anchor: anchor, calendar: calendar).start
        switch period {
        case .week, .month:
            return calendar.date(byAdding: .day, value: index, to: start)!
        case .year:
            return calendar.date(byAdding: .month, value: index, to: start)!
        }
    }

    static func bucketIndex(of date: Date, period: ReadingStatsPeriod, anchor: Date, calendar: Calendar) -> Int? {
        let start = range(period: period, anchor: anchor, calendar: calendar).start
        switch period {
        case .week, .month:
            let days = calendar.dateComponents([.day], from: startOfDay(start, calendar: calendar), to: startOfDay(date, calendar: calendar)).day ?? -1
            return (0..<bucketCount(period: period, anchor: anchor, calendar: calendar)).contains(days) ? days : nil
        case .year:
            let months = calendar.dateComponents([.month], from: start, to: date).month ?? -1
            return (0..<12).contains(months) ? months : nil
        }
    }

    // MARK: 聚合

    static func aggregate(_ sessions: [ReadingSession], start: Date, end: Date, calendar: Calendar) -> ReadingDayAggregate {
        var result = ReadingDayAggregate()
        for session in sessions where session.start >= start && session.start < end {
            result.add(session, key: dayKey(session.start, calendar: calendar))
        }
        return result
    }

    static func series(_ sessions: [ReadingSession], period: ReadingStatsPeriod, anchor: Date, calendar: Calendar) -> [Double] {
        let range = self.range(period: period, anchor: anchor, calendar: calendar)
        var bars = Array(repeating: 0.0, count: bucketCount(period: period, anchor: anchor, calendar: calendar))
        for session in sessions where session.start >= range.start && session.start < range.end {
            if let index = bucketIndex(of: session.start, period: period, anchor: anchor, calendar: calendar) {
                bars[index] += session.seconds / 60
            }
        }
        return bars
    }

    // MARK: 衍生文案

    /// 阅读时长最多的起始小时。
    static func peakHour(_ sessions: [ReadingSession], start: Date, end: Date, calendar: Calendar) -> Int? {
        var byHour: [Int: TimeInterval] = [:]
        for session in sessions where session.start >= start && session.start < end {
            let hour = calendar.component(.hour, from: session.start)
            byHour[hour, default: 0] += session.seconds
        }
        return byHour.max(by: { $0.value < $1.value })?.key
    }

    /// 深夜（23:00-次日5:00）阅读次数。
    static func lateNightCount(_ sessions: [ReadingSession], start: Date, end: Date, calendar: Calendar) -> Int {
        sessions.filter { session in
            guard session.start >= start, session.start < end, session.seconds > 0 else { return false }
            let hour = calendar.component(.hour, from: session.start)
            return hour >= 23 || hour < 5
        }.count
    }

    static func formatHour(_ hour: Int) -> String {
        String(format: "%02d:00", hour)
    }

    static func formatRange(_ start: Date, _ end: Date, period: ReadingStatsPeriod, calendar: Calendar) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "zh_Hans_CN")
        switch period {
        case .week, .month: f.dateFormat = "M.d"
        case .year: f.dateFormat = "yyyy.M"
        }
        // end 为开区间，显示时用最后一天
        let displayEnd = calendar.date(byAdding: .day, value: -1, to: end) ?? end
        return f.string(from: start) + " - " + f.string(from: displayEnd)
    }

    static func formatMinutes(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes)分钟" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours)小时" : "\(hours)小时\(rest)分"
    }

    /// 每分钟少于 1 记为「<1分」。
    static func formatAverage(_ seconds: TimeInterval, per days: Int) -> String {
        guard days > 0, seconds > 0 else { return "0分钟" }
        let minutes = Int((seconds / Double(days) / 60).rounded())
        return minutes <= 0 ? "<1分钟" : "\(minutes)分钟"
    }

    // MARK: 对比

    static func compare(current: TimeInterval, previous: TimeInterval) -> Int? {
        guard previous > 0, current != previous else { return nil }
        return Int(((current - previous) / previous * 100).rounded())
    }
}

/// 阅读统计的页面模型：主线程缓存聚合结果，会话落盘后自动失效。
/// UI 只读这里；计算全部交给 ReadingStatsEngine / ReadingStatsStore。
final class ReadingStatsModel: ObservableObject {
    nonisolated(unsafe) static let shared = ReadingStatsModel()
    let store: ReadingStatsStore

    @Published private(set) var revision = 0

    init(store: ReadingStatsStore = .shared) {
        self.store = store
    }

    /// 回到统计页时重新读取（会话在阅读器关闭时才写入）。
    func refresh() { revision += 1 }

    var todayMinutes: Int { Int((store.today().seconds / 60).rounded()) }
    var todayAverage: String {
        // 本月已过天数作为日均分母
        let anchor = Date()
        let calendar = Calendar.current
        let monthStart = ReadingStatsEngine.range(period: .month, anchor: anchor, calendar: calendar).start
        let days = max(1, calendar.dateComponents([.day], from: monthStart, to: anchor).day! + 1)
        let aggregate = store.aggregate(period: .month, anchor: anchor)
        return ReadingStatsEngine.formatAverage(aggregate.seconds, per: days)
    }
    var todayCompare: String? {
        let calendar = Calendar.current
        let today = store.today().seconds
        let yesterday = calendar.date(byAdding: .day, value: -1, to: Date())!
        let yesterdayStart = ReadingStatsEngine.startOfDay(yesterday, calendar: calendar)
        let yesterdayEnd = calendar.date(byAdding: .day, value: 1, to: yesterdayStart)!
        let before = ReadingStatsEngine.aggregate(store.sessions(from: yesterdayStart, to: yesterdayEnd),
                                                  start: yesterdayStart, end: yesterdayEnd, calendar: calendar).seconds
        guard let diff = ReadingStatsEngine.compare(current: today, previous: before) else { return nil }
        return (diff >= 0 ? "↑比昨天 +" : "↓比昨天 -") + "\(abs(Int((today - before) / 60)))分"
    }

    func series(period: ReadingStatsPeriod) -> [Double] {
        store.series(period: period)
    }

    func periodTotalMinutes(period: ReadingStatsPeriod) -> String {
        let minutes = Int((store.aggregate(period: period).seconds / 60).rounded())
        return ReadingStatsEngine.formatMinutes(minutes)
    }

    func periodTrend(period: ReadingStatsPeriod) -> String? {
        store.periodTrend(period: period)
    }

    func rangeLine(period: ReadingStatsPeriod, calendar: Calendar) -> String {
        let range = ReadingStatsEngine.range(period: period, anchor: Date(), calendar: calendar)
        return ReadingStatsEngine.formatRange(range.start, range.end, period: period, calendar: calendar)
    }

    func highlights(period: ReadingStatsPeriod, calendar: Calendar) -> [ReadingStatsStore.StatsHighlight] {
        store.highlights(period: period)
    }
}

/// 落盘并聚合阅读会话。与 PersistentVariableStore 同思路：内存 + 防抖写盘，
/// 应用退到后台时 flush。
final class ReadingStatsStore: @unchecked Sendable {
    static let shared = ReadingStatsStore()

    private let fileURL: URL
    private let lock = NSLock()
    private var all: [ReadingSession] = []
    private var scheduled = false
    private let calendar: Calendar

    init(fileURL: URL? = nil, calendar: Calendar = .current) {
        self.calendar = calendar
        self.fileURL = fileURL ?? Self.defaultFileURL()
        let url = self.fileURL
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([ReadingSession].self, from: data) {
            all = decoded
        }
    }

    static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("LegadoReading", isDirectory: true)
            .appendingPathComponent("sessions.json")
    }

    // MARK: 写入

    /// 关闭阅读器或退到后台时记录一次会话。不足 3 秒视为误触，不记。
    func record(book: Book, start: Date, end: Date, chapters: [Int]) {
        let seconds = end.timeIntervalSince(start)
        guard seconds >= 3 else { return }
        let session = ReadingSession(start: start, end: end,
                                     bookURL: book.bookUrl, bookName: book.name,
                                     source: book.originName, chapters: chapters)
        lock.lock()
        all.append(session)
        lock.unlock()
        scheduleWrite()
    }

    // MARK: 查询

    func sessions(from start: Date, to end: Date) -> [ReadingSession] {
        lock.lock(); defer { lock.unlock() }
        return all.filter { $0.start >= start && $0.start < end }
    }

    func aggregate(period: ReadingStatsPeriod, anchor: Date = Date()) -> ReadingDayAggregate {
        let range = ReadingStatsEngine.range(period: period, anchor: anchor, calendar: calendar)
        return ReadingStatsEngine.aggregate(sessions(from: range.start, to: range.end), start: range.start, end: range.end, calendar: calendar)
    }

    func today(anchor: Date = Date()) -> ReadingDayAggregate {
        let start = ReadingStatsEngine.startOfDay(anchor, calendar: calendar)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        return ReadingStatsEngine.aggregate(sessions(from: start, to: end), start: start, end: end, calendar: calendar)
    }

    func series(period: ReadingStatsPeriod, anchor: Date = Date()) -> [Double] {
        let range = ReadingStatsEngine.range(period: period, anchor: anchor, calendar: calendar)
        return ReadingStatsEngine.series(sessions(from: range.start, to: range.end), period: period, anchor: anchor, calendar: calendar)
    }

    // MARK: 概览派生

    struct StatsHighlight: Equatable {
        var symbol: String
        var title: String
        var detail: String
        var value: String
    }

    /// 三个轻量事实卡：高峰时段、深夜次数、最常读的书。
    func highlights(period: ReadingStatsPeriod, anchor: Date = Date()) -> [StatsHighlight] {
        let range = ReadingStatsEngine.range(period: period, anchor: anchor, calendar: calendar)
        let list = sessions(from: range.start, to: range.end).filter { $0.seconds > 0 }
        var cards: [StatsHighlight] = []
        if let peak = ReadingStatsEngine.peakHour(list, start: range.start, end: range.end, calendar: calendar) {
            cards.append(StatsHighlight(symbol: "clock", title: "你的一天",
                                        detail: "高峰 \(ReadingStatsEngine.formatHour(peak)) 前后",
                                        value: ReadingStatsEngine.formatHour(peak)))
        }
        let late = ReadingStatsEngine.lateNightCount(list, start: range.start, end: range.end, calendar: calendar)
        if late > 0 {
            cards.append(StatsHighlight(symbol: "moon.stars", title: "你的深夜",
                                        detail: "23 点后还在读", value: "\(late) 次"))
        }
        var byBook: [String: (name: String, seconds: TimeInterval)] = [:]
        for session in list {
            var entry = byBook[session.bookURL] ?? (session.bookName, 0)
            entry.seconds += session.seconds
            byBook[session.bookURL] = entry
        }
        if let top = byBook.max(by: { $0.value.seconds < $1.value.seconds }) {
            cards.append(StatsHighlight(symbol: "book", title: "最常读",
                                        detail: "《\(top.value.name)》",
                                        value: ReadingStatsEngine.formatMinutes(Int((top.value.seconds / 60).rounded()))))
        }
        return cards
    }

    /// 对比上一周期：正数用 ↑，负数用 ↓，没有上一周期数据返回 nil。
    func periodTrend(period: ReadingStatsPeriod, anchor: Date = Date()) -> String? {
        let current = ReadingStatsEngine.range(period: period, anchor: anchor, calendar: calendar)
        let component: Calendar.Component = period == .week ? .weekOfYear : (period == .month ? .month : .year)
        guard let previousAnchor = calendar.date(byAdding: component, value: -1, to: anchor) else { return nil }
        let previous = ReadingStatsEngine.range(period: period, anchor: previousAnchor, calendar: calendar)
        let now = aggregate(sessions(from: current.start, to: current.end)).seconds
        let before = aggregate(sessions(from: previous.start, to: previous.end)).seconds
        guard let percent = ReadingStatsEngine.compare(current: now, previous: before) else { return nil }
        return (percent >= 0 ? "↑" : "↓") + " \(abs(percent))%"
    }

    private func aggregate(_ sessions: [ReadingSession]) -> ReadingDayAggregate {
        ReadingStatsEngine.aggregate(sessions, start: .distantPast, end: .distantFuture, calendar: calendar)
    }

    // MARK: 落盘

    private func scheduleWrite() {
        lock.lock()
        guard !scheduled else { lock.unlock(); return }
        scheduled = true
        lock.unlock()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.flush()
        }
    }

    func flush() {
        lock.lock()
        let snapshot = all
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
