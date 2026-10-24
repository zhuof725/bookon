import SwiftUI

/// UI 夹具专用的最小书架：统计页只读 `books` 与目录缓存，
/// 不需要真实的 AppStore（书源解析、导入、本地书全都不参与渲染）。
@MainActor
final class AppStore: ObservableObject {
    @Published var books: [Book] = []

    func cachedToc(_ book: Book) -> [BookChapter]? { nil }
}

struct StatsFixture {
    static var books: [Book] {
        var a = Book(bookUrl: "fixture-a", name: "A 林间札记", author: "离线示例", origin: "fixture-local")
        a.durChapterIndex = 3
        var b = Book(bookUrl: "fixture-b", name: "B 山海手记", author: "合成占位", origin: "fixture-local")
        b.durChapterIndex = 1
        return [a, b]
    }

    static func dayStats(days: Int) -> [ReadingDayStat] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let reading: [Double] = [0, 12, 25, 8, 30, 0, 18, 22, 5, 0, 14, 40, 16, 9]
        let listening: [Double] = [0, 5, 0, 10, 0, 7, 3, 0, 8, 12, 0, 4, 6, 0]
        return (0..<days).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return ReadingDayStat(dayKey: ReadingStatsEngine.dayKey(date, calendar: calendar),
                                  date: date,
                                  reading: reading[offset % reading.count] * 60,
                                  listening: listening[offset % listening.count] * 60)
        }
    }

    static var plan: ReadingPlan {
        let calendar = Calendar.current
        let marks = (0..<3).compactMap { offset -> String? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: Date()) else { return nil }
            return ReadingStatsEngine.dayKey(date, calendar: calendar)
        }
        return ReadingPlan(id: "fixture-plan", bookURL: "fixture-a", bookName: "A 林间札记",
                           mode: .chapters, targetDate: nil, perDayChapters: 2, perDayMinutes: nil,
                           reminderMinutes: 21 * 60, createdAt: Date(), checkedDays: marks)
    }
}

/// 统计页空态：与参考设计的 0 数据一致（目标 15 分钟 / 12 本，无会话、无读完记录）。
struct StatsHarnessView: View {
    @StateObject private var store = AppStore()
    private let month = ProcessInfo.processInfo.arguments.contains("--stats-month")

    var body: some View {
        NavigationStack {
            LibraryStatisticsView(initialRange: month ? .month : .week)
        }
        .environmentObject(store)
        .onAppear { store.books = StatsFixture.books }
    }
}

/// 组件夹具：只画图表与计划卡片，验证有数据时的排版（不写任何统计文件）。
struct StatsDataHarnessView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("有数据：近 7 天").appFont(.system(size: 15)).foregroundStyle(.secondary)
                ReadingStatsChart(days: StatsFixture.dayStats(days: 7), goalMinutes: 15, range: .week)
                    .frame(height: 150)
                Text("有数据：近 30 天").appFont(.system(size: 15)).foregroundStyle(.secondary)
                ReadingStatsChart(days: StatsFixture.dayStats(days: 30), goalMinutes: 15, range: .month)
                    .frame(height: 150)
                Text("有数据：今年已读").appFont(.system(size: 15)).foregroundStyle(.secondary)
                YearlyFinishedChart(counts: [1, 0, 2, 1, 3, 0, 1, 2, 0, 1, 0, 0], total: 11)
                    .frame(height: 96)
                ReadingPlanCard(plan: StatsFixture.plan, chapterCount: 40, currentChapter: 10,
                                today: (20, 3), calendar: .current) {}
            }
            .padding(20)
        }
        .background { AppThemeCanvas().ignoresSafeArea() }
        .accessibilityIdentifier("stats.dataHarness")
    }
}
