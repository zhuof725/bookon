import SwiftUI

// MARK: - 统计页（阅读目标 / 连续阅读 / 今年已读 / 阅读计划 / 阅读统计）

enum StatsRange: String, CaseIterable, Identifiable {
    case week, month
    var id: String { rawValue }
    var days: Int { self == .week ? 7 : 30 }
    var title: String { self == .week ? "近 7 天" : "近 30 天" }
}

struct LibraryStatisticsView: View {
    @ThemePalette private var palette
    @Environment(\.calendar) private var calendar
    @EnvironmentObject private var store: AppStore
    @ObservedObject private var stats = ReadingStatsModel.shared
    @ObservedObject private var finished = FinishedBookStore.shared
    @ObservedObject private var plans = ReadingPlanStore.shared
    @AppStorage(ReadingGoals.dailyMinutesKey) private var dailyGoal = ReadingGoals.defaultDailyMinutes
    @AppStorage(ReadingGoals.yearlyBooksKey) private var yearlyGoal = ReadingGoals.defaultYearlyBooks

    @State private var showDailyGoal = false
    @State private var showYearlyGoal = false
    @State private var showNewPlan = false
    @State private var showMarkFinished = false
    @State private var showStreakInfo = false
    @State private var showStatsInfo = false
    @State private var range: StatsRange
    @State private var planChapterCounts: [String: Int] = [:]

    init(initialRange: StatsRange = .week) {
        _range = State(initialValue: initialRange)
    }

    private var todayReading: TimeInterval { stats.todayReadingSeconds }
    private var todayListening: TimeInterval { stats.todayListeningSeconds }
    private var todayTotal: TimeInterval { todayReading + todayListening }
    private var goalSeconds: TimeInterval { Double(max(dailyGoal, 1)) * 60 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.top, 10)
                sectionTitle("阅读目标")
                dailyCard
                streakCard.padding(.top, 14)
                yearlyCard.padding(.top, 14)
                sectionTitle("阅读计划")
                planSection
                sectionTitle("阅读统计")
                statsCard
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 44)
        }
        .background { AppThemeCanvas().ignoresSafeArea() }
        .foregroundStyle(palette.primary)
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityIdentifier("stats.page")
        .onAppear {
            stats.refresh()
            ReadingStatsStore.shared.flush()
            ListeningStatsStore.shared.flush()
            refreshPlanChapterCounts()
            checkPlans()
        }
        .onChange(of: plans.plans.count) { _ in
            refreshPlanChapterCounts()
            checkPlans()
        }
        .sheet(isPresented: $showDailyGoal) {
            DailyGoalSheet(goal: $dailyGoal)
        }
        .sheet(isPresented: $showYearlyGoal) {
            YearlyGoalSheet(goal: $yearlyGoal)
        }
        .sheet(isPresented: $showNewPlan) {
            NewReadingPlanSheet()
        }
        .sheet(isPresented: $showMarkFinished) {
            MarkFinishedSheet()
        }
        .alert("连续阅读", isPresented: $showStreakInfo) {
            Button("好", role: .cancel) {}
        } message: {
            Text("一天里读过正文或听过书（超过 30 秒）就算连续。今天还没读时，记录会保留到昨天为止。")
        }
        .alert("阅读统计", isPresented: $showStatsInfo) {
            Button("好", role: .cancel) {}
        } message: {
            Text("日均与合计都包含阅读和听书；虚线是每日目标。听书时长从播放器真正开始播放时累计。")
        }
    }

    // MARK: 页头

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Self.weekdayName(calendar: calendar))
                .appFont(.system(size: 15, weight: .medium))
                .foregroundStyle(palette.secondary)
            Text(Self.monthDay(calendar: calendar))
                .appFont(.system(size: 34, weight: .bold))
                .accessibilityIdentifier("stats.date")
            Text(todayTotal < 30 ? "今天还没开始读" : "今天已读 \(Self.minutesText(todayTotal))")
                .appFont(.system(size: 17))
                .foregroundStyle(palette.secondary)
                .padding(.top, 4)
                .accessibilityIdentifier("stats.todayStatus")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func weekdayName(calendar: Calendar) -> String {
        let symbols = ["星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六"]
        return symbols[min(max(calendar.component(.weekday, from: Date()) - 1, 0), 6)]
    }

    static func monthDay(calendar: Calendar) -> String {
        "\(calendar.component(.month, from: Date()))月\(calendar.component(.day, from: Date()))日"
    }

    static func minutesText(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 { return "\(minutes) 分钟" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) 小时" : "\(hours) 小时 \(rest) 分钟"
    }

    static func clockText(_ seconds: TimeInterval) -> String {
        let total = Int(seconds / 60)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: 版式

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .appFont(.system(size: 20, weight: .bold))
            .padding(.top, 30)
            .padding(.bottom, 12)
            .accessibilityAddTraits(.isHeader)
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(palette.surface)
                    .shadow(color: .black.opacity(0.045), radius: 14, x: 0, y: 6)
            }
    }

    private var dotsButton: some View {
        Image(systemName: "ellipsis")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(palette.secondary)
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
    }

    // MARK: 今日阅读

    private var dailyCard: some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Text("今日阅读").appFont(.system(size: 17, weight: .semibold))
                    Spacer(minLength: 0)
                    Button("调整目标") { showDailyGoal = true }
                        .buttonStyle(.plain)
                        .appFont(.system(size: 15))
                        .foregroundStyle(palette.secondary)
                        .accessibilityIdentifier("stats.dailyGoal")
                    Menu {
                        Button("调整每日目标") { showDailyGoal = true }
                        Button("调整年度目标") { showYearlyGoal = true }
                    } label: {
                        dotsButton
                    }
                    .accessibilityIdentifier("stats.today.more")
                }
                HStack(alignment: .center, spacing: 16) {
                    ReadingGoalRing(progress: min(todayTotal / goalSeconds, 1))
                        .frame(width: 102, height: 102)
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline, spacing: 7) {
                            Text(Self.clockText(todayTotal))
                                .monospacedDigit()
                                .appFont(.system(size: 38, weight: .bold))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .accessibilityIdentifier("stats.todayClock")
                            Text("目标 \(dailyGoal) 分钟")
                                .appFont(.system(size: 14))
                                .foregroundStyle(palette.secondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        HStack(spacing: 22) {
                            statColumn(icon: "book", title: "阅读", seconds: todayReading)
                            statColumn(icon: "headphones", title: "听书", seconds: todayListening)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.leading, -6)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("stats.today")
    }

    private func statColumn(icon: String, title: String, seconds: TimeInterval) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 18)
                Text(title).appFont(.system(size: 15))
            }
            .foregroundStyle(palette.secondary)
            Text("\(Int((seconds / 60).rounded())) 分钟")
                .appFont(.system(size: 14, weight: .semibold))
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(Int((seconds / 60).rounded())) 分钟")
    }

    // MARK: 连续阅读

    private var streak: (current: Int, maximum: Int) { stats.streak(calendar: calendar) }

    private var streakCard: some View {
        card {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("连续阅读").appFont(.system(size: 17, weight: .semibold))
                    Spacer(minLength: 0)
                    Menu {
                        Button("连续阅读怎么算") { showStreakInfo = true }
                    } label: { dotsButton }
                }
                HStack(alignment: .top, spacing: 12) {
                    streakNumber(title: "当前连续", days: streak.current)
                    streakNumber(title: "最长纪录", days: streak.maximum)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ReadingHeatmapView(activity: stats.activityByDay(calendar: calendar), goalMinutes: dailyGoal)
                    .accessibilityIdentifier("stats.heatmap")
                HStack(spacing: 0) {
                    Text("近 18 周").appFont(.system(size: 12)).foregroundStyle(palette.secondary)
                    Spacer(minLength: 8)
                    HeatmapLegend()
                }
            }
        }
        .accessibilityIdentifier("stats.streak")
    }

    private func streakNumber(title: String, days: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).appFont(.system(size: 13)).foregroundStyle(palette.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(days)").monospacedDigit().appFont(.system(size: 30, weight: .bold))
                Text("天").appFont(.system(size: 13)).foregroundStyle(palette.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(days) 天")
    }

    // MARK: 今年已读

    private var currentYear: Int { calendar.component(.year, from: Date()) }
    private var finishedThisYear: Int { stats.finishedCount(year: currentYear, calendar: calendar) }
    private var monthlyFinished: [Int] { stats.finishedMonthly(year: currentYear, calendar: calendar) }

    private var yearlyCard: some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("今年已读").appFont(.system(size: 17, weight: .semibold))
                    Spacer(minLength: 0)
                    Menu {
                        Button("调整年度目标") { showYearlyGoal = true }
                        Button("标记读完…") { showMarkFinished = true }
                    } label: { dotsButton }
                }
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("\(finishedThisYear)")
                        .monospacedDigit()
                        .appFont(.system(size: 38, weight: .bold))
                        .accessibilityIdentifier("stats.finishedCount")
                    Text("/ \(yearlyGoal) 本")
                        .appFont(.system(size: 17))
                        .foregroundStyle(palette.secondary)
                }
                YearlyFinishedChart(counts: monthlyFinished, total: finishedThisYear)
                    .frame(height: 96)
                Text("读到最后一章末尾会自动记为读完，也可以在书架「···」里标记")
                    .appFont(.system(size: 14))
                    .foregroundStyle(palette.secondary)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
                Button { showYearlyGoal = true } label: {
                    Text("调整目标")
                        .appFont(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background { Capsule().fill(palette.primary.opacity(0.07)) }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("stats.yearlyGoal")
            }
        }
        .accessibilityIdentifier("stats.books")
    }

    // MARK: 阅读计划

    private var planSection: some View {
        VStack(spacing: 14) {
            ForEach(plans.plans) { plan in
                let book = store.books.first { $0.bookUrl == plan.bookURL }
                ReadingPlanCard(plan: plan,
                                chapterCount: planChapterCounts[plan.bookURL],
                                currentChapter: book?.durChapterIndex ?? 0,
                                today: stats.todayProgress(bookURL: plan.bookURL, calendar: calendar),
                                calendar: calendar) {
                    ReadingPlanNotifier.cancel(plan)
                    plans.remove(id: plan.id)
                }
            }
            planPromoCard
        }
        .accessibilityIdentifier("stats.plans")
    }

    private var planPromoCard: some View {
        card {
            VStack(alignment: .leading, spacing: 0) {
                Text("给一本书定个节奏").appFont(.system(size: 16, weight: .semibold))
                Text("按日期读完、每天几章或每天几分钟，到点提醒，达成自动打卡")
                    .appFont(.system(size: 13))
                    .foregroundStyle(palette.secondary)
                    .lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
                Rectangle()
                    .fill(palette.border.opacity(0.55))
                    .frame(height: 0.5)
                    .padding(.vertical, 14)
                Button { showNewPlan = true } label: {
                    Text("新建阅读计划")
                        .appFont(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background { Capsule().fill(palette.primary.opacity(0.07)) }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("stats.newPlan")
            }
        }
        .accessibilityIdentifier("stats.planPromo")
    }

    private func refreshPlanChapterCounts() {
        var counts: [String: Int] = [:]
        for plan in plans.plans {
            guard let book = store.books.first(where: { $0.bookUrl == plan.bookURL }) else { continue }
            if let toc = store.cachedToc(book), !toc.isEmpty { counts[plan.bookURL] = toc.count }
        }
        planChapterCounts = counts
    }

    /// 打开统计页时补一次自动打卡（阅读器关闭时也会调用同一个引擎）。
    private func checkPlans() {
        for plan in plans.plans {
            ReadingPlanEngine.checkDay(bookURL: plan.bookURL, calendar: calendar)
        }
    }

    // MARK: 阅读统计

    private var statsCard: some View {
        card {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    StatsRangePicker(range: $range)
                    Spacer(minLength: 0)
                    Menu {
                        Button("近 7 天") { range = .week }
                        Button("近 30 天") { range = .month }
                        Button("统计说明") { showStatsInfo = true }
                    } label: { dotsButton }
                }
                let days = stats.dayStats(days: range.days, calendar: calendar)
                let totalSeconds = days.reduce(0) { $0 + $1.total }
                let average = range.days > 0 ? totalSeconds / Double(range.days) : 0
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("日均").appFont(.system(size: 13)).foregroundStyle(palette.secondary)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(Int((average / 60).rounded()))")
                                .monospacedDigit()
                                .appFont(.system(size: 32, weight: .bold))
                                .accessibilityIdentifier("stats.average")
                            Text("分钟").appFont(.system(size: 13)).foregroundStyle(palette.secondary)
                        }
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("合计").appFont(.system(size: 13)).foregroundStyle(palette.secondary)
                        Text(Self.minutesText(totalSeconds))
                            .appFont(.system(size: 17, weight: .bold))
                            .monospacedDigit()
                            .accessibilityIdentifier("stats.total")
                    }
                }
                ReadingStatsChart(days: days, goalMinutes: dailyGoal, range: range)
                    .frame(height: 150)
                    .accessibilityIdentifier("stats.chart")
                HStack(spacing: 16) {
                    legendDot(color: palette.primary, title: "阅读")
                    legendDot(color: palette.secondary.opacity(0.55), title: "听书")
                }
            }
        }
        .accessibilityIdentifier("stats.trend")
    }

    private func legendDot(color: Color, title: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(title).appFont(.system(size: 12)).foregroundStyle(palette.secondary)
        }
    }
}

// MARK: - 目标环

struct ReadingGoalRing: View {
    @ThemePalette private var palette
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .inset(by: 5)
                .stroke(palette.primary.opacity(0.15), lineWidth: 10)
            Circle()
                .inset(by: 5)
                .trim(from: 0, to: max(0.0001, min(progress, 1)))
                .stroke(palette.primary, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .opacity(progress > 0.001 ? 1 : 0)
            if progress <= 0.001 {
                Circle()
                    .fill(palette.primary)
                    .frame(width: 10, height: 10)
                    .offset(y: -46)
            }
            Text("\(Int((min(max(progress, 0), 1) * 100).rounded()))%")
                .monospacedDigit()
                .appFont(.system(size: 16, weight: .semibold))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("今日目标完成 \(Int((min(max(progress, 0), 1) * 100).rounded()))%")
    }
}

// MARK: - 热力图

struct ReadingHeatmapView: View {
    @ThemePalette private var palette
    let activity: [String: TimeInterval]
    let goalMinutes: Int

    private let weeks = 18

    var body: some View {
        let calendar = Calendar.current
        let columns = ReadingHeatmapEngine.weeks(activity: activity, weekCount: weeks, today: Date(),
                                                 calendar: calendar, goalMinutes: goalMinutes)
        let todayRow = ReadingHeatmapEngine.todayPosition(today: Date(), calendar: calendar).row
        HStack(spacing: 3.5) {
            ForEach(columns.indices, id: \.self) { column in
                VStack(spacing: 3.5) {
                    ForEach(columns[column].indices, id: \.self) { row in
                        cell(level: columns[column][row],
                             isToday: column == max(columns.count - 1, 0) && row == todayRow)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("近 18 周阅读记录")
    }

    private func cell(level: Int, isToday: Bool) -> some View {
        RoundedRectangle(cornerRadius: 3.5, style: .continuous)
            .fill(fill(level))
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if isToday {
                    RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                        .strokeBorder(palette.primary, lineWidth: 1.5)
                }
            }
            .frame(maxWidth: .infinity)
    }

    private func fill(_ level: Int) -> Color {
        switch level {
        case 0: return palette.primary.opacity(0.07)
        case 1: return palette.primary.opacity(0.30)
        case 2: return palette.primary.opacity(0.55)
        case 3: return palette.primary.opacity(0.80)
        default: return palette.primary
        }
    }
}

struct HeatmapLegend: View {
    @ThemePalette private var palette
    var body: some View {
        HStack(spacing: 4) {
            Text("少").appFont(.system(size: 12)).foregroundStyle(palette.secondary)
            ForEach(0..<5, id: \.self) { level in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(fill(level))
                    .frame(width: 10, height: 10)
            }
            Text("多").appFont(.system(size: 12)).foregroundStyle(palette.secondary)
        }
    }

    private func fill(_ level: Int) -> Color {
        switch level {
        case 0: return palette.primary.opacity(0.07)
        case 1: return palette.primary.opacity(0.30)
        case 2: return palette.primary.opacity(0.55)
        case 3: return palette.primary.opacity(0.80)
        default: return palette.primary
        }
    }
}

// MARK: - 今年已读柱状图

struct YearlyFinishedChart: View {
    @ThemePalette private var palette
    let counts: [Int]
    let total: Int

    /// 没有数据时的虚线示意高度（与参考页一致）。
    private let ghostHeights: [CGFloat] = [0.78, 0.66, 0.9, 0.74, 0.58, 0.62, 0.86, 0.78, 0.72, 0.9, 0.8, 0.62]

    var body: some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            let barArea = max(height - 6, 1)
            let slot = geometry.size.width / 12
            let barWidth = min(24, slot * 0.84)
            ZStack(alignment: .bottomLeading) {
                if total == 0 {
                    HStack(alignment: .bottom, spacing: 0) {
                        ForEach(0..<12, id: \.self) { index in
                            ghostBar(height: barArea * ghostHeights[index], width: barWidth)
                                .frame(width: slot)
                        }
                    }
                } else {
                    let maximum = max(counts.max() ?? 1, 1)
                    HStack(alignment: .bottom, spacing: 0) {
                        ForEach(0..<12, id: \.self) { index in
                            let value = counts.indices.contains(index) ? counts[index] : 0
                            VStack(spacing: 0) {
                                if value > 0 {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(palette.primary)
                                        .frame(width: barWidth,
                                               height: max(6, barArea * CGFloat(value) / CGFloat(maximum)))
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
                Capsule()
                    .fill(palette.primary.opacity(0.14))
                    .frame(height: 2.5)
                    .padding(.bottom, 2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("今年每月读完的书")
    }

    private func ghostBar(height: CGFloat, width: CGFloat) -> some View {
        UnevenRoundedRectangle(topLeadingRadius: 7, topTrailingRadius: 7, style: .continuous)
            .stroke(palette.primary.opacity(0.2),
                    style: StrokeStyle(lineWidth: 1.4, lineCap: .round, dash: [5, 5]))
            .frame(width: width, height: max(height, 12))
    }
}

// MARK: - 统计图表

struct ReadingStatsChart: View {
    @ThemePalette private var palette
    let days: [ReadingDayStat]
    let goalMinutes: Int
    let range: StatsRange

    var body: some View {
        let axis = axisValues
        GeometryReader { geometry in
            let labelWidth: CGFloat = 30
            let plotWidth = max(geometry.size.width - labelWidth, 1)
            let plotHeight = max(geometry.size.height - 26, 1)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 0) {
                    plot(maximum: axis.maximum, step: axis.step)
                        .frame(width: plotWidth, height: plotHeight)
                    axisLabels(maximum: axis.maximum, step: axis.step, height: plotHeight)
                        .frame(width: labelWidth, height: plotHeight)
                }
                dayLabels(width: plotWidth)
            }
        }
    }

    /// 4 段等分的「整」刻度：5/10/15…，数据再高也保持整数标签。
    private var axisValues: (maximum: Double, step: Double) {
        let peak = (days.map(\.total).max() ?? 0) / 60
        let need = max(peak, Double(goalMinutes) * 1.25, 8)
        let step = max(ceil(need / 4 / 5) * 5, 5)
        return (step * 4, step)
    }

    private func y(minutes: Double, height: CGFloat, maximum: Double) -> CGFloat {
        height - CGFloat(min(max(minutes / maximum, 0), 1)) * height
    }

    private func plot(maximum: Double, step: Double) -> some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            ZStack(alignment: .topLeading) {
                ForEach(0...4, id: \.self) { step in
                    let value = maximum * Double(step) / 4
                    Rectangle()
                        .fill(palette.primary.opacity(0.08))
                        .frame(height: 0.5)
                        .offset(y: y(minutes: value, height: height, maximum: maximum))
                }
                // 目标虚线
                let goalY = y(minutes: Double(goalMinutes), height: height, maximum: maximum)
                Path { path in
                    path.move(to: CGPoint(x: 0, y: goalY))
                    path.addLine(to: CGPoint(x: geometry.size.width, y: goalY))
                }
                .stroke(palette.primary.opacity(0.32),
                        style: StrokeStyle(lineWidth: 1, lineCap: .butt, dash: [4, 4]))
                let segment = height / 4
                let goalOnGrid = abs(Double(goalMinutes) / step - (Double(goalMinutes) / step).rounded()) < 0.01
                Text("目标")
                    .appFont(.system(size: 11))
                    .foregroundStyle(palette.secondary)
                    .padding(.horizontal, 3)
                    .background(palette.surface)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .offset(y: max(goalY - (goalOnGrid ? segment / 2 : 18) - 6, 0))
                bars(width: geometry.size.width, height: height, maximum: maximum)
            }
        }
    }

    private func bars(width: CGFloat, height: CGFloat, maximum: Double) -> some View {
        let slot = width / CGFloat(max(days.count, 1))
        let barWidth: CGFloat = range == .week ? min(20, slot * 0.42) : max(3, slot * 0.5)
        return HStack(alignment: .bottom, spacing: 0) {
            ForEach(days.indices, id: \.self) { index in
                let reading = days[index].reading / 60
                let listening = days[index].listening / 60
                let readingHeight = CGFloat(reading / maximum) * height
                let listeningHeight = CGFloat(listening / maximum) * height
                let stackHeight = max(readingHeight + listeningHeight, 0)
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    VStack(spacing: 0) {
                        if listeningHeight > 0 {
                            Rectangle()
                                .fill(palette.secondary.opacity(0.55))
                                .frame(width: barWidth, height: max(listeningHeight, 2))
                        }
                        if readingHeight > 0 {
                            Rectangle()
                                .fill(palette.primary)
                                .frame(width: barWidth, height: max(readingHeight, 2))
                        }
                    }
                    .frame(width: barWidth, height: max(stackHeight, 2), alignment: .bottom)
                    .clipShape(RoundedRectangle(cornerRadius: min(barWidth / 2, 4), style: .continuous))
                }
                .frame(width: slot, height: height, alignment: .bottom)
            }
        }
        .frame(width: width, height: height, alignment: .bottomLeading)
    }

    private func axisLabels(maximum: Double, step: Double, height: CGFloat) -> some View {
        ZStack(alignment: .topTrailing) {
            ForEach(0...4, id: \.self) { index in
                let value = maximum - step * Double(index)
                Text(Self.tickText(value))
                    .appFont(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(palette.secondary)
                    .frame(height: 14)
                    .offset(y: y(minutes: value, height: height, maximum: maximum) - 7)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    }

    private static func tickText(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    private func dayLabels(width: CGFloat) -> some View {
        let step = days.count <= 7 ? 1 : 5
        var indices = Array(stride(from: 0, to: max(days.count, 1), by: step))
        if let last = indices.last, days.count - 1 - last >= 3 {
            indices.append(days.count - 1)
        }
        let slot = width / CGFloat(max(days.count, 1))
        return ZStack(alignment: .topLeading) {
            ForEach(indices, id: \.self) { index in
                Text(label(at: index, count: days.count))
                    .appFont(.system(size: 12))
                    .foregroundStyle(palette.secondary)
                    .fixedSize()
                    .position(x: slot * (CGFloat(index) + 0.5), y: 8)
            }
        }
        .frame(width: width, height: 16, alignment: .topLeading)
    }

    private func label(at index: Int, count: Int) -> String {
        guard days.indices.contains(index) else { return "" }
        if count <= 7 {
            let symbols = ["一", "二", "三", "四", "五", "六", "日"]
            let weekday = Calendar.current.component(.weekday, from: days[index].date)
            return symbols[(weekday + 5) % 7]
        }
        if index % 5 == 0 || index == count - 1 {
            let calendar = Calendar.current
            return "\(calendar.component(.month, from: days[index].date)).\(calendar.component(.day, from: days[index].date))"
        }
        return ""
    }
}

struct StatsRangePicker: View {
    @ThemePalette private var palette
    @Binding var range: StatsRange
    @Namespace private var animation

    var body: some View {
        HStack(spacing: 0) {
            ForEach(StatsRange.allCases) { item in
                Button {
                    withAnimation(.snappy(duration: 0.18)) { range = item }
                } label: {
                    Text(item.title)
                        .appFont(.system(size: 15, weight: range == item ? .semibold : .regular))
                        .foregroundStyle(range == item ? palette.primary : palette.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .background {
                            if range == item {
                                Capsule()
                                    .fill(palette.surface)
                                    .matchedGeometryEffect(id: "stats.range", in: animation)
                                    .shadow(color: .black.opacity(0.06), radius: 3, x: 0, y: 1)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(range == item ? AccessibilityTraits.isSelected : AccessibilityTraits())
                .accessibilityIdentifier("stats.range." + item.rawValue)
            }
        }
        .padding(2.5)
        .background { Capsule().fill(palette.primary.opacity(0.06)) }
        .frame(width: 286)
    }
}
