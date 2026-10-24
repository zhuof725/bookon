import SwiftUI
import UserNotifications

// MARK: - 每日 / 年度目标

struct DailyGoalSheet: View {
    @ThemePalette private var palette
    @Environment(\.dismiss) private var dismiss
    @Binding var goal: Int
    @State private var draft = ReadingGoals.defaultDailyMinutes

    private let presets = [10, 15, 20, 30, 45, 60]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("每日阅读目标").appFont(.system(size: 20, weight: .bold))
                Spacer(minLength: 8)
                Button("完成") { commit() }
                    .appFont(.system(size: 17, weight: .semibold))
                    .accessibilityIdentifier("goal.daily.done")
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(draft)").monospacedDigit().appFont(.system(size: 52, weight: .bold))
                Text("分钟").appFont(.system(size: 17)).foregroundStyle(palette.secondary)
            }
            Slider(value: Binding(get: { Double(draft) }, set: { draft = Int($0) }),
                   in: 5...120, step: 5)
                .tint(palette.primary)
                .accessibilityIdentifier("goal.daily.slider")
            HStack(spacing: 8) {
                ForEach(presets, id: \.self) { value in
                    Button { draft = value } label: {
                        Text("\(value)")
                            .appFont(.system(size: 15, weight: draft == value ? .semibold : .regular))
                            .foregroundStyle(draft == value ? palette.primary : palette.secondary)
                            .frame(maxWidth: .infinity).frame(height: 34)
                            .background {
                                Capsule().fill(palette.primary.opacity(draft == value ? 0.13 : 0.05))
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("当天阅读和听书加起来达到目标，就算完成今天。")
                .appFont(.system(size: 13))
                .foregroundStyle(palette.secondary)
            Spacer(minLength: 0)
            Button { commit() } label: {
                Text("保存")
                    .appFont(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity).frame(height: 46)
                    .background { Capsule().fill(palette.primary) }
                    .foregroundStyle(palette.onAccent)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("goal.daily.save")
        }
        .foregroundStyle(palette.primary)
        .padding(24)
        .background { AppThemeCanvas().ignoresSafeArea() }
        .presentationDetents([.height(400)])
        .presentationDragIndicator(.visible)
        .onAppear { draft = goal }
    }

    private func commit() {
        goal = min(max(draft, ReadingGoals.dailyRange.lowerBound), ReadingGoals.dailyRange.upperBound)
        dismiss()
    }
}

struct YearlyGoalSheet: View {
    @ThemePalette private var palette
    @Environment(\.dismiss) private var dismiss
    @Binding var goal: Int
    @State private var draft = ReadingGoals.defaultYearlyBooks

    private let presets = [6, 12, 24, 50]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("年度阅读目标").appFont(.system(size: 20, weight: .bold))
                Spacer(minLength: 8)
                Button("完成") { commit() }
                    .appFont(.system(size: 17, weight: .semibold))
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(draft)").monospacedDigit().appFont(.system(size: 52, weight: .bold))
                Text("本").appFont(.system(size: 17)).foregroundStyle(palette.secondary)
            }
            Stepper(value: $draft, in: ReadingGoals.yearlyRange) {
                Text("今年想读完 \(draft) 本")
                    .appFont(.system(size: 15))
                    .foregroundStyle(palette.secondary)
            }
            .accessibilityIdentifier("goal.yearly.stepper")
            HStack(spacing: 8) {
                ForEach(presets, id: \.self) { value in
                    Button { draft = value } label: {
                        Text("\(value)")
                            .appFont(.system(size: 15, weight: draft == value ? .semibold : .regular))
                            .foregroundStyle(draft == value ? palette.primary : palette.secondary)
                            .frame(maxWidth: .infinity).frame(height: 34)
                            .background {
                                Capsule().fill(palette.primary.opacity(draft == value ? 0.13 : 0.05))
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer(minLength: 0)
            Button { commit() } label: {
                Text("保存")
                    .appFont(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity).frame(height: 46)
                    .background { Capsule().fill(palette.primary) }
                    .foregroundStyle(palette.onAccent)
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(palette.primary)
        .padding(24)
        .background { AppThemeCanvas().ignoresSafeArea() }
        .presentationDetents([.height(360)])
        .presentationDragIndicator(.visible)
        .onAppear { draft = goal }
    }

    private func commit() {
        goal = min(max(draft, ReadingGoals.yearlyRange.lowerBound), ReadingGoals.yearlyRange.upperBound)
        dismiss()
    }
}

// MARK: - 标记读完

struct MarkFinishedSheet: View {
    @ThemePalette private var palette
    @EnvironmentObject private var store: AppStore
    @ObservedObject private var finished = FinishedBookStore.shared
    @Environment(\.dismiss) private var dismiss

    private var books: [Book] {
        store.books.sorted { $0.lastReadAt > $1.lastReadAt }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("标记读完").appFont(.system(size: 20, weight: .bold))
                Spacer(minLength: 8)
                Button("完成") { dismiss() }
                    .appFont(.system(size: 17, weight: .semibold))
            }
            .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 10)
            if books.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "books.vertical").font(.system(size: 32)).foregroundStyle(palette.secondary)
                    Text("书架还是空的").appFont(.subheadline).foregroundStyle(palette.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(books) { book in
                            Button { finished.toggle(book) } label: {
                                HStack(spacing: 14) {
                                    BookCoverImage(url: BookCoverLocation.url(for: book), origin: book.origin)
                                        .frame(width: 32, height: 44)
                                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(book.name).appFont(.system(size: 16)).lineLimit(1)
                                        if let entry = finished.entry(book.bookUrl) {
                                            Text("读完于 " + Self.dateText(entry.finishedAt))
                                                .appFont(.system(size: 13)).foregroundStyle(palette.secondary)
                                        } else {
                                            Text(book.author.isEmpty ? "未标记" : book.author)
                                                .appFont(.system(size: 13)).foregroundStyle(palette.secondary)
                                        }
                                    }
                                    Spacer(minLength: 8)
                                    Image(systemName: finished.isFinished(book.bookUrl) ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 22))
                                        .foregroundStyle(finished.isFinished(book.bookUrl) ? palette.primary : palette.secondary.opacity(0.5))
                                }
                                .padding(.horizontal, 24)
                                .frame(minHeight: 62)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("markFinished." + book.id)
                            Divider().opacity(0.35).padding(.leading, 70)
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
        }
        .foregroundStyle(palette.primary)
        .background { AppThemeCanvas().ignoresSafeArea() }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "yyyy年M月d日"
        return formatter.string(from: date)
    }
}

// MARK: - 新建阅读计划

struct NewReadingPlanSheet: View {
    @ThemePalette private var palette
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var planStore = ReadingPlanStore.shared

    @State private var bookURL = ""
    @State private var mode: ReadingPlan.Mode = .minutes
    @State private var minutes = 15
    @State private var chapters = 2
    @State private var targetDate = Calendar.current.date(byAdding: .day, value: 14, to: Date()) ?? Date()
    @State private var reminderOn = true
    @State private var reminderTime = Calendar.current.date(bySettingHour: 21, minute: 0, second: 0, of: Date()) ?? Date()

    private var books: [Book] { store.books.sorted { $0.lastReadAt > $1.lastReadAt } }
    private var selectedBook: Book? { books.first { $0.bookUrl == bookURL } }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("新建阅读计划").appFont(.system(size: 20, weight: .bold))
                Spacer(minLength: 8)
                Button("关闭") { dismiss() }
                    .appFont(.system(size: 17)).foregroundStyle(palette.secondary)
            }
            .padding(.horizontal, 24).padding(.top, 22).padding(.bottom, 8)

            if books.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "book.closed").font(.system(size: 32)).foregroundStyle(palette.secondary)
                    Text("先往书架里加一本书").appFont(.subheadline).foregroundStyle(palette.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        field("给哪本书") {
                            Menu {
                                ForEach(books) { book in
                                    Button(book.name) { bookURL = book.bookUrl }
                                }
                            } label: {
                                HStack {
                                    Text(selectedBook?.name ?? "选择一本书").appFont(.system(size: 16)).lineLimit(1)
                                    Spacer(minLength: 8)
                                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(palette.secondary)
                                }
                                .foregroundStyle(palette.primary)
                                .padding(.horizontal, 14).frame(height: 44)
                                .background { RoundedRectangle(cornerRadius: 14, style: .continuous).fill(palette.primary.opacity(0.05)) }
                            }
                        }

                        field("节奏") {
                            HStack(spacing: 6) {
                                ForEach(ReadingPlan.Mode.allCases) { item in
                                    Button { mode = item } label: {
                                        Text(item.title)
                                            .appFont(.system(size: 14, weight: mode == item ? .semibold : .regular))
                                            .foregroundStyle(mode == item ? palette.primary : palette.secondary)
                                            .frame(maxWidth: .infinity).frame(height: 34)
                                            .background {
                                                Capsule().fill(palette.primary.opacity(mode == item ? 0.13 : 0.05))
                                            }
                                            .contentShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        switch mode {
                        case .deadline:
                            field("目标日期") {
                                DatePicker("", selection: $targetDate, displayedComponents: .date)
                                    .datePickerStyle(.compact)
                                    .labelsHidden()
                                    .environment(\.locale, Locale(identifier: "zh_Hans_CN"))
                            }
                        case .chapters:
                            field("每天读几章") {
                                Stepper(value: $chapters, in: 1...50) {
                                    Text("每天 \(chapters) 章").appFont(.system(size: 16))
                                }
                            }
                        case .minutes:
                            field("每天读多久") {
                                Stepper(value: $minutes, in: 5...180, step: 5) {
                                    Text("每天 \(minutes) 分钟").appFont(.system(size: 16))
                                }
                            }
                        }

                        field("提醒") {
                            VStack(spacing: 12) {
                                Toggle("到点提醒", isOn: $reminderOn)
                                    .appFont(.system(size: 16))
                                if reminderOn {
                                    DatePicker("提醒时间", selection: $reminderTime, displayedComponents: .hourAndMinute)
                                        .appFont(.system(size: 16))
                                        .environment(\.locale, Locale(identifier: "zh_Hans_CN"))
                                }
                            }
                        }

                        Text(previewText)
                            .appFont(.system(size: 14))
                            .foregroundStyle(palette.secondary)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 24).padding(.top, 10).padding(.bottom, 20)
                }
                Button { save() } label: {
                    Text("开始计划")
                        .appFont(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity).frame(height: 46)
                        .background { Capsule().fill(palette.primary) }
                        .foregroundStyle(palette.onAccent)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(selectedBook == nil)
                .opacity(selectedBook == nil ? 0.4 : 1)
                .padding(.horizontal, 24).padding(.bottom, 24)
            }
        }
        .foregroundStyle(palette.primary)
        .background { AppThemeCanvas().ignoresSafeArea() }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear {
            if bookURL.isEmpty { bookURL = books.first?.bookUrl ?? "" }
        }
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).appFont(.system(size: 14)).foregroundStyle(palette.secondary)
            content()
        }
    }

    private var previewText: String {
        guard let book = selectedBook else { return "" }
        let plan = makePlan()
        let count = store.cachedToc(book)?.count
        let summary = ReadingPlanEngine.summary(plan, chapterCount: count, currentChapter: book.durChapterIndex)
        return summary + (reminderOn ? " · 每天 \(timeText) 提醒" : "")
    }

    private var timeText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: reminderTime)
    }

    private var reminderMinutes: Int? {
        guard reminderOn else { return nil }
        let calendar = Calendar.current
        return calendar.component(.hour, from: reminderTime) * 60 + calendar.component(.minute, from: reminderTime)
    }

    private func makePlan() -> ReadingPlan {
        ReadingPlan(id: UUID().uuidString.lowercased(),
                    bookURL: selectedBook?.bookUrl ?? "",
                    bookName: selectedBook?.name ?? "",
                    mode: mode,
                    targetDate: mode == .deadline ? targetDate : nil,
                    perDayChapters: mode == .chapters ? chapters : nil,
                    perDayMinutes: mode == .minutes ? minutes : nil,
                    reminderMinutes: reminderMinutes,
                    createdAt: Date(),
                    checkedDays: [])
    }

    private func save() {
        guard selectedBook != nil else { return }
        let plan = makePlan()
        planStore.add(plan)
        ReadingPlanNotifier.schedule(plan)
        dismiss()
    }
}

// MARK: - 计划卡片

struct ReadingPlanCard: View {
    @ThemePalette private var palette
    let plan: ReadingPlan
    let chapterCount: Int?
    let currentChapter: Int
    let today: (minutes: Int, chapters: Int)
    let calendar: Calendar
    var onDelete: () -> Void

    private var todayKey: String { ReadingStatsEngine.dayKey(Date(), calendar: calendar) }
    private var checkedToday: Bool { plan.checkedDays.contains(todayKey) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(plan.bookName).appFont(.system(size: 17, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 4)
                Menu {
                    Button("删除计划", role: .destructive) { onDelete() }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.secondary)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
            }
            Text(ReadingPlanEngine.summary(plan, chapterCount: chapterCount,
                                           currentChapter: currentChapter, calendar: calendar))
                .appFont(.system(size: 15))
                .foregroundStyle(palette.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 5) {
                ForEach(weekMarks, id: \.key) { mark in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(mark.checked ? palette.primary : palette.primary.opacity(0.1))
                        .overlay {
                            if mark.isToday {
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .strokeBorder(palette.primary, lineWidth: 1.4)
                            }
                        }
                        .frame(width: 13, height: 13)
                }
                Spacer(minLength: 8)
                Text(checkedToday ? "今天已打卡" : "今天 \(today.minutes) 分钟")
                    .appFont(.system(size: 13))
                    .foregroundStyle(palette.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(checkedToday ? "今天已打卡" : "今天阅读 \(today.minutes) 分钟")
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(palette.surface)
                .shadow(color: .black.opacity(0.045), radius: 12, x: 0, y: 5)
        }
    }

    private struct WeekMark { var key: String; var checked: Bool; var isToday: Bool }

    private var weekMarks: [WeekMark] {
        let start = calendar.startOfDay(for: Date())
        return (0..<7).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: start) else { return nil }
            let key = ReadingStatsEngine.dayKey(date, calendar: calendar)
            return WeekMark(key: key, checked: plan.checkedDays.contains(key), isToday: offset == 0)
        }
    }
}

// MARK: - 提醒

/// 阅读计划的本地提醒：每天固定时间提醒一次；没有提醒时间就不排。
/// 通知权限只在第一次真的需要提醒时申请，拒绝也不影响计划本身。
enum ReadingPlanNotifier {
    static func identifier(_ plan: ReadingPlan) -> String { "reading.plan." + plan.id }

    static func cancel(_ plan: ReadingPlan) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier(plan)])
    }

    static func schedule(_ plan: ReadingPlan) {
        let identifier = identifier(plan)
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        guard let reminder = plan.reminderMinutes else { return }
        let book = plan.bookName
        let detail = plan.mode.title
        var components = DateComponents()
        components.hour = reminder / 60
        components.minute = reminder % 60
        Task {
            let granted = (try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])) ?? false
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "该读《\(book)》了"
            content.body = "今天的计划：\(detail)"
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            try? await UNUserNotificationCenter.current()
                .add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
        }
    }
}
