import SwiftUI

// MARK: - 统计

struct LibraryStatisticsView: View {
    @ThemePalette private var palette
    @EnvironmentObject var store: AppStore
    @Environment(\.calendar) private var calendar
    @ObservedObject private var stats = ReadingStatsModel.shared
    @AppStorage("stats.period.v1") private var periodRaw = ReadingStatsPeriod.week.rawValue
    private var period: ReadingStatsPeriod { ReadingStatsPeriod(rawValue: periodRaw) ?? .week }
    private var recentBooks: [Book] {
        store.books.filter(ShelfBooks.isStarted).sorted { $0.lastReadAt > $1.lastReadAt }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                headerCard
                trendCard
                highlightCards
                booksCard
            }
            .padding(.horizontal, 24).padding(.vertical, 16)
        }
        .foregroundStyle(palette.primary)
        .background { AppThemeCanvas().ignoresSafeArea() }
        .navigationTitle("统计")
        .toolbar(.visible, for: .navigationBar)
        .accessibilityIdentifier("stats.page")
        .onAppear { stats.refresh() }
    }

    // MARK: 今日

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Self.todayLine(calendar: calendar))
                .appFont(.caption).foregroundStyle(palette.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(stats.todayMinutes)").appFont(.system(size: 44, weight: .bold))
                Text("分钟").appFont(.headline).foregroundStyle(palette.secondary)
            }
            HStack(spacing: 8) {
                Text("日均 \(stats.todayAverage)").appFont(.caption).foregroundStyle(palette.secondary)
                if let compare = stats.todayCompare {
                    Text(compare).appFont(.caption).foregroundStyle(palette.accent)
                }
            }
            if stats.todayMinutes == 0 {
                Text("今天还没翻开书").appFont(.caption).foregroundStyle(palette.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .modifier(StatsGlass())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("stats.today")
    }

    static func todayLine(calendar: Calendar) -> String {
        let date = Date()
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        return "今天·\(Self.weekday(calendar: calendar)) \(month)月\(day)日"
    }

    static func weekday(calendar: Calendar) -> String {
        let symbols = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
        return symbols[min(max(calendar.component(.weekday, from: Date()) - 1, 0), 6)]
    }

    // MARK: 趋势

    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("趋势").appFont(.headline)
                Spacer(minLength: 8)
                Picker("", selection: $periodRaw) {
                    ForEach(ReadingStatsPeriod.allCases, id: \.rawValue) { item in
                        Text(Self.periodTitle(item)).tag(item.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 168)
                .accessibilityIdentifier("stats.period")
            }
            Text(stats.rangeLine(period: period, calendar: calendar))
                .appFont(.caption).foregroundStyle(palette.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(Self.periodTitle(period))共读").appFont(.subheadline).foregroundStyle(palette.secondary)
                Text(stats.periodTotalMinutes(period: period)).appFont(.title2.weight(.bold))
                if let trend = stats.periodTrend(period: period) {
                    Text(trend).appFont(.caption).foregroundStyle(palette.accent)
                }
            }
            StatsBarChart(values: stats.series(period: period))
                .frame(height: 84)
                .accessibilityIdentifier("stats.chart")
        }
        .padding(16)
        .modifier(StatsGlass())
        .accessibilityIdentifier("stats.trend")
    }

    static func periodTitle(_ period: ReadingStatsPeriod) -> String {
        switch period {
        case .week: return "本周"
        case .month: return "本月"
        case .year: return "今年"
        }
    }

    // MARK: 高光

    private var highlightCards: some View {
        let items = stats.highlights(period: period, calendar: calendar)
        return VStack(spacing: 14) {
            ForEach(Array(items.enumerated()), id: \.offset) { pair in
                let item = pair.element
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: item.symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(palette.accent)
                        .frame(width: 30, height: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).appFont(.subheadline.weight(.semibold))
                        Text(item.detail).appFont(.caption).foregroundStyle(palette.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Text(item.value).appFont(.headline).foregroundStyle(palette.accent)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .padding(14)
                .modifier(StatsGlass())
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("stats.highlight.\(pair.offset)")
            }
        }
    }

    // MARK: 在读

    private var booksCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("正在读").appFont(.headline)
            if recentBooks.isEmpty {
                Text("暂无阅读记录").appFont(.subheadline).foregroundStyle(palette.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
            } else {
                ForEach(Array(recentBooks.prefix(8))) { book in
                    NavigationLink { ReaderView(book: book) } label: {
                        StatsBookRow(book: book)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("stats.book.\(book.id)")
                    if book.id != recentBooks.prefix(8).last?.id {
                        Divider().opacity(0.28)
                    }
                }
            }
        }
        .padding(16)
        .modifier(StatsGlass())
        .accessibilityIdentifier("stats.books")
    }
}

private struct StatsBookRow: View {
    @ThemePalette private var palette
    let book: Book
    var body: some View {
        HStack(spacing: 12) {
            BookCoverImage(url: BookCoverLocation.url(for: book), origin: book.origin)
                .frame(width: 34, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(book.name).appFont(.subheadline).foregroundStyle(palette.primary).lineLimit(1)
                Text(Self.progress(book)).appFont(.caption).foregroundStyle(palette.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                .foregroundStyle(palette.secondary).accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .contentShape(Rectangle())
    }

    static func progress(_ book: Book) -> String {
        let chapter = max(book.durChapterIndex + 1, 1)
        if let title = ShelfListSummary.nonempty(book.durChapterTitle) {
            return "已读 \(title)"
        }
        return "已读 第\(chapter)章"
    }
}

// MARK: - 图表（自绘柱状图，不依赖 Charts 框架）

struct StatsBarChart: View {
    @ThemePalette private var palette
    let values: [Double]

    var body: some View {
        let maximum = max(values.max() ?? 0, 1)
        HStack(alignment: .bottom, spacing: values.count > 12 ? 2 : 6) {
            ForEach(Array(values.enumerated()), id: \.offset) { item in
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(item.element > 0 ? palette.accent : palette.secondary.opacity(0.2))
                    .frame(height: item.element > 0 ? max(4, 84 * CGFloat(item.element / maximum)) : 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .bottom)
    }
}

struct StatsGlass: ViewModifier {
    func body(content: Content) -> some View {
        content.modifier(SettingsGlassSurface())
    }
}

// MARK: - 我的

struct LibraryProfileView: View {
    @ThemePalette private var palette
    @EnvironmentObject var store: AppStore
    @State private var crashCount = 0
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                LibraryCard("书库管理") {
                    Group {
                        NavigationLink { SourcesView() } label: { LibraryLinkLabel(title: "书源管理", symbol: "square.stack.3d.up") }
                            .accessibilityIdentifier("library.sources")
                        LibraryCardDivider()
                        NavigationLink { TxtTocRulesView() } label: { LibraryLinkLabel(title: "目录规则", symbol: "list.bullet.rectangle") }
                            .accessibilityIdentifier("library.tocRules")
                        LibraryCardDivider()
                        NavigationLink { BodyReplaceRulesView() } label: { LibraryLinkLabel(title: "替换规则", symbol: "text.badge.checkmark") }
                            .accessibilityIdentifier("library.replaceRules")
                        LibraryCardDivider()
                        NavigationLink { SpeakEngineList(aloud: ReaderAloudController()) } label: { LibraryLinkLabel(title: "朗读引擎管理", symbol: "waveform.badge.mic") }
                            .accessibilityIdentifier("library.speakEngines")
                        LibraryCardDivider()
                    }
                    Group {
                        NavigationLink { BubbleStyleSettingsView() } label: { LibraryLinkLabel(title: "段评气泡", symbol: "bubble.right") }
                            .accessibilityIdentifier("library.bubbleStyles")
                        LibraryCardDivider()
                        NavigationLink { FontManagerView() } label: { LibraryLinkLabel(title: "字体管理", symbol: "textformat") }
                            .accessibilityIdentifier("library.fonts")
                        LibraryCardDivider()
                        NavigationLink { AppAppearanceSettingsView() } label: { LibraryLinkLabel(title: "外观主题", symbol: "circle.lefthalf.filled") }
                            .accessibilityIdentifier("library.appearance")
                        LibraryCardDivider()
                        NavigationLink { SearchView() } label: { LibraryLinkLabel(title: "搜索书籍", symbol: "magnifyingglass") }
                        LibraryCardDivider()
                        NavigationLink { NetworkSettingsView() } label: { LibraryLinkLabel(title: "网络设置", symbol: "network") }
                            .accessibilityIdentifier("library.network")
                    }
                }
                LibraryCard("本机数据") {
                    NavigationLink { CacheManagementView() } label: { LibraryLinkLabel(title: "缓存管理", symbol: "internaldrive") }
                        .accessibilityIdentifier("library.cache")
                    LibraryCardDivider()
                    NavigationLink { CrashLogView() } label: { LibraryLinkLabel(title: crashCount > 0 ? "崩溃日志（\(crashCount)）" : "崩溃日志", symbol: "exclamationmark.triangle") }
                        .accessibilityIdentifier("library.crashLogs")
                    LibraryCardDivider()
                    LibraryValueRow(title: "已导入书源", value: "\(store.sources.count) 个")
                    LibraryCardDivider()
                    LibraryValueRow(title: "书架书籍", value: "\(store.books.count) 本")
                }
                PrecacheWindowSettingView(manager: .shared)
                    .padding(.horizontal, 24)
                LibraryCard {
                    Text("阅读进度、导入书源与本地书籍保存在本机。")
                        .foregroundStyle(palette.secondary).appFont(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24).padding(.vertical, 16)
        }
        .foregroundStyle(palette.primary)
        .background { AppThemeCanvas().ignoresSafeArea() }
        .onAppear { crashCount = CrashReporter.reports().count }
        .navigationTitle("我的")
        .toolbar(.visible, for: .navigationBar)
    }
}

/// App-owned grouped surfaces, not a UIKit list background: card geometry and
/// outlines therefore respond to the selected theme without UIAppearance hacks.
private struct LibraryCard<Content: View>: View {
    @ThemePalette private var palette
    let title: String?
    let content: Content

    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title).appFont(.footnote).foregroundStyle(palette.secondary)
                    .padding(.horizontal, 16).accessibilityAddTraits(.isHeader)
            }
            VStack(spacing: 4) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct LibraryCardDivider: View {
    @ThemePalette private var palette
    var body: some View {
        Color.clear.frame(height: 0).accessibilityHidden(true)
    }
}

private struct LibraryLinkLabel: View {
    @ThemePalette private var palette
    let title: String
    let symbol: String
    var body: some View {
        SettingsGlassLabel(title: title, symbol: symbol)
    }
}

/// Native LabeledContent's value style can bypass a custom secondary color.
/// These app-owned values use explicit palette labels and wrap at large sizes.
private struct LibraryValueRow: View {
    @ThemePalette private var palette
    let title: String
    let value: String
    var body: some View {
        SettingsGlassValue(title: title, value: value)
    }
}
