import SwiftUI

/// 阅读外观的两种模式：日间、夜间。各自保存一整套排版与背景。
enum ReaderDayNightMode: Int, CaseIterable, Identifiable {
    case day = 0
    case night = 1

    var id: Int { rawValue }
    var title: String { self == .day ? "日间" : "夜间" }
    var symbol: String { self == .day ? "sun.max.fill" : "moon.fill" }
    /// 该模式可选的背景主题（索引对应 ReadSettings.themes）。
    var themeIndices: [Int] { self == .day ? [0, 1, 2] : [3, 4] }
}

/// 一套可独立保存的阅读排版。日间与夜间各存一份，切换时整体生效。
struct ReaderModeLayout: Codable, Equatable {
    var theme: Int
    var fontSize: Double
    var lineSpacing: Double
    var paragraphSpacing: Double
    var fullJustify: Bool
    var bottomJustify: Bool
    var leftMargin: Double
    var rightMargin: Double
    var topMargin: Double
    var bottomMargin: Double
}

final class ReadSettings: ObservableObject {
    // Android ReadBookConfig defaults: 20sp, lineSpacingExtra=12 (1.2H),
    // paragraphSpacing=2 (0.2H), with two full-width indent cells.
    @AppStorage("fontSize") var fontSize: Double = 20
    @AppStorage("readerLineHeightTenths") var lineSpacing: Double = 12
    @AppStorage("readerParagraphHeightTenths") var paragraphSpacing: Double = 2
    @AppStorage("readerFullJustify") var fullJustify: Bool = true
    @AppStorage("readerBottomJustify") var bottomJustify: Bool = true
    @AppStorage("leftMargin") var leftMargin: Double = 20
    @AppStorage("rightMargin") var rightMargin: Double = 20
    @AppStorage("topMargin") var topMargin: Double = 16
    @AppStorage("bottomMargin") var bottomMargin: Double = 10
    @AppStorage("theme") var theme: Int = 0
    /// 当前阅读模式：0 日间，1 夜间。两套排版各自保存。
    @AppStorage("reader.mode.v1") var mode: Int = 0
    static let modeStorageKey = "reader.mode.v1"
    static let dayLayoutKey = "reader.mode.day.layout.v1"
    static let nightLayoutKey = "reader.mode.night.layout.v1"
    private static let modeMigrationKey = "reader.mode.migrated.v1"
    @AppStorage("pageMode") var pageMode: Int = 0
    @AppStorage("pageTurnStyle") var pageTurnStyle: Int = 0
    /// 章节标题的 CSS 样式（空串 = 默认外观）。
    @AppStorage("readerChapterTitleCSS") var chapterTitleCSS: String = ""
    /// 章节标题简单设置：字号（0 = 跟随正文）、字重、位置，以及是否叠加高级 CSS。
    @AppStorage("readerChapterTitleSize") var chapterTitleSize: Double = 0
    @AppStorage("readerChapterTitleWeight") var chapterTitleWeight: Int = 600
    @AppStorage("readerChapterTitleAlign") var chapterTitleAlign: String = "center"
    @AppStorage("readerChapterTitleAdvanced") var chapterTitleAdvanced: Bool = false
    /// 正文里「本章说」原生卡片的大小：0 小、1 标准、2 大。默认偏小，避免挡住正文。
    @AppStorage("readerCommentCardSize") var commentCardSize: Int = 0
    /// 书源只给「查看评论」入口、没有评论内容时是否显示。默认显示，避免章评入口凭空消失。
    @AppStorage("readerShowCommentEntries") var showCommentEntries: Bool = true
    /// 阅读背景：0 预设、1 纯色、2 图片。纯色/图片模式下 hex 是底色（图片时兼作遮罩）。
    @AppStorage("readerBackgroundMode") var backgroundMode: Int = 0
    @AppStorage("readerCustomBackgroundHex") var customBackgroundHex: String = "F5EFE0"
    @AppStorage("readerBackgroundImageID") var backgroundImageID: String = ""

    init() {
        // Old keys store extra spacing in points; new keys store tenths of
        // the actual font height. Migrate each value only once, using the
        // saved font size without changing it or rounding custom spacing.
        // Missing old keys retain the Android defaults (12 / 2).
        let defaults = UserDefaults.standard
        let fontHeight = Double(ReaderTextLayout.androidParagraphSpacingPoints(
            fontSize: CGFloat(fontSize), setting: 10))
        if fontHeight.isFinite, fontHeight > 0 {
            if defaults.object(forKey: "readerLineHeightTenths") == nil,
               let oldPoints = defaults.object(forKey: "lineSpacing") as? NSNumber,
               oldPoints.doubleValue.isFinite {
                lineSpacing = 10 * (1 + max(oldPoints.doubleValue, 0) / fontHeight)
            }
            if defaults.object(forKey: "readerParagraphHeightTenths") == nil,
               let oldPoints = defaults.object(forKey: "paragraphSpacing") as? NSNumber,
               oldPoints.doubleValue.isFinite {
                paragraphSpacing = 10 * max(oldPoints.doubleValue, 0) / fontHeight
            }
        }
        // 旧版淡入淡出值 2 回退到原生滑动，保留字号、主题与阅读进度。
        if pageTurnStyle != 0 && pageTurnStyle != 1 { pageTurnStyle = 0 }
        migrateReadingModeIfNeeded()
    }

    // MARK: 日间 / 夜间

    var dayNightMode: ReaderDayNightMode { ReaderDayNightMode(rawValue: mode) ?? .day }

    /// 切换日间/夜间：先保存当前模式的一整套设置，再恢复目标模式的设置。
    /// 主动通知观察者：@AppStorage 写在 ObservableObject 里不会自动发 objectWillChange。
    func setMode(_ newValue: Int) {
        guard let target = ReaderDayNightMode(rawValue: newValue), target.rawValue != mode else { return }
        objectWillChange.send()
        saveCurrentLayout(for: dayNightMode)
        mode = target.rawValue
        apply(storedLayout(for: target) ?? defaultLayout(for: target), for: target)
    }

    /// 背景主题只在当前模式允许的色板里选；选预设会退出自定义背景。
    func selectTheme(_ index: Int) {
        guard dayNightMode.themeIndices.contains(index),
              theme != index || backgroundMode != 0 else { return }
        objectWillChange.send()
        backgroundMode = 0
        theme = index
    }

    /// 当前实际使用的纸面：自定义背景优先，否则按当前模式的预设。
    var usesImageBackground: Bool {
        backgroundMode == 2 && !backgroundImageID.isEmpty
    }

    var currentPaper: (bg: Color, fg: Color, name: String) {
        if backgroundMode != 0 {
            return (customBackgroundColor, customForegroundColor,
                    backgroundMode == 2 ? "图片" : "自定义")
        }
        return Self.themes[min(max(theme, 0), Self.themes.count - 1)]
    }

    /// 图片模式用半透明底色当遮罩，页面叠在根视图的背景图上；纯色/预设仍是实色。
    var pageBackground: Color {
        usesImageBackground ? currentPaper.bg.opacity(0.82) : currentPaper.bg
    }

    var paperSignature: String {
        "mode-\(backgroundMode)-\(customBackgroundHex)-\(backgroundImageID)-theme-\(theme)"
    }

    var customBackgroundColor: Color { customBackgroundComponents.color }
    var customForegroundColor: Color {
        customBackgroundComponents.luminance < 0.45
            ? Color.white : Color(red: 0.13, green: 0.13, blue: 0.13)
    }

    private var customBackgroundComponents: (color: Color, luminance: Double) {
        let hex = customBackgroundHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else {
            return (Color(red: 0.96, green: 0.94, blue: 0.88), 0.92)
        }
        let red = Double((value >> 16) & 255) / 255
        let green = Double((value >> 8) & 255) / 255
        let blue = Double(value & 255) / 255
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let luminance = 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
        return (Color(red: red, green: green, blue: blue), luminance)
    }

    private func currentLayout() -> ReaderModeLayout {
        ReaderModeLayout(theme: theme, fontSize: fontSize, lineSpacing: lineSpacing,
                         paragraphSpacing: paragraphSpacing, fullJustify: fullJustify,
                         bottomJustify: bottomJustify, leftMargin: leftMargin, rightMargin: rightMargin,
                         topMargin: topMargin, bottomMargin: bottomMargin)
    }

    private func saveCurrentLayout(for mode: ReaderDayNightMode) {
        guard let data = try? JSONEncoder().encode(currentLayout()) else { return }
        UserDefaults.standard.set(data, forKey: mode == .day ? Self.dayLayoutKey : Self.nightLayoutKey)
    }

    private func storedLayout(for mode: ReaderDayNightMode) -> ReaderModeLayout? {
        let key = mode == .day ? Self.dayLayoutKey : Self.nightLayoutKey
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(ReaderModeLayout.self, from: data)
    }

    private func defaultLayout(for mode: ReaderDayNightMode) -> ReaderModeLayout {
        var layout = currentLayout()
        layout.theme = mode == .day ? 0 : 3
        return layout
    }

    private func apply(_ layout: ReaderModeLayout, for mode: ReaderDayNightMode) {
        let allowed = mode.themeIndices
        theme = allowed.contains(layout.theme) ? layout.theme : (allowed.first ?? 0)
        fontSize = min(36, max(12, layout.fontSize))
        lineSpacing = min(20, max(0, layout.lineSpacing))
        paragraphSpacing = min(20, max(0, layout.paragraphSpacing))
        fullJustify = layout.fullJustify
        bottomJustify = layout.bottomJustify
        leftMargin = min(60, max(0, layout.leftMargin))
        rightMargin = min(60, max(0, layout.rightMargin))
        topMargin = min(80, max(0, layout.topMargin))
        bottomMargin = min(80, max(0, layout.bottomMargin))
    }

    /// 老用户第一次升级：按当前主题落到日间或夜间，两套初始设置都保留现有排版。
    private func migrateReadingModeIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: Self.modeMigrationKey) == nil else { return }
        let dark = theme >= 3
        let active: ReaderDayNightMode = dark ? .night : .day
        var activeLayout = currentLayout()
        activeLayout.theme = dark ? max(0, min(theme, 4)) : max(0, min(theme, 2))
        var otherLayout = activeLayout
        otherLayout.theme = active == .day ? 3 : 0
        if let data = try? JSONEncoder().encode(activeLayout) {
            defaults.set(data, forKey: active == .day ? Self.dayLayoutKey : Self.nightLayoutKey)
        }
        if let data = try? JSONEncoder().encode(otherLayout) {
            defaults.set(data, forKey: active == .day ? Self.nightLayoutKey : Self.dayLayoutKey)
        }
        defaults.set(active.rawValue, forKey: Self.modeStorageKey)
        defaults.set(true, forKey: Self.modeMigrationKey)
    }

    /// Android stores line/paragraph spacing as tenths of the actual font
    /// height. Keep those values in settings, and expose point values only at
    /// the UIKit layout boundary.
    var lineSpacingPoints: Double {
        Double(ReaderTextLayout.androidLineSpacingPoints(fontSize: CGFloat(fontSize),
                                                          setting: CGFloat(lineSpacing)))
    }

    var paragraphSpacingPoints: Double {
        Double(ReaderTextLayout.androidParagraphSpacingPoints(fontSize: CGFloat(fontSize),
                                                               setting: CGFloat(paragraphSpacing)))
    }

    /// 最终生效的章节标题样式：简单设置打底，开启高级 CSS 时由 CSS 覆盖。
    var chapterTitleStyle: ChapterTitleStyle {
        var style = ChapterTitleStyle.simple(size: chapterTitleSize, weight: chapterTitleWeight,
                                             alignment: chapterTitleAlign)
        guard chapterTitleAdvanced else { return style }
        style.merge(ChapterTitleStyle.parse(chapterTitleCSS))
        return style
    }

    /// 标题样式的版本串：阅读器据此重排版（简单设置 + 高级 CSS 都算）。
    var chapterTitleSignature: String {
        "\(chapterTitleSize)|\(chapterTitleWeight)|\(chapterTitleAlign)|\(chapterTitleAdvanced)|\(chapterTitleCSS)"
    }

    /// 有没有改过标题样式（设置页显示「默认 / 自定义」）。
    var chapterTitleIsDefault: Bool {
        if chapterTitleAdvanced, !ChapterTitleStyle.parse(chapterTitleCSS).isEmpty { return false }
        return chapterTitleSize <= 0 && chapterTitleWeight == 600 && chapterTitleAlign == "center"
    }

    var typographyValues: [Double] {
        [fontSize, lineSpacing, paragraphSpacing, leftMargin, rightMargin, topMargin, bottomMargin,
         fullJustify ? 1 : 0, bottomJustify ? 1 : 0, Double(commentCardSize),
         showCommentEntries ? 1 : 0]
    }

    /// 本章说卡片的字号倍率；跟随正文字号，再乘这个系数。
    var commentCardScaleFactor: CGFloat {
        switch commentCardSize {
        case 1: return 1
        case 2: return 1.15
        default: return 0.85
        }
    }

    static let themes: [(bg: Color, fg: Color, name: String)] = [
        (Color(red: 0.98, green: 0.96, blue: 0.90), Color(red: 0.2, green: 0.2, blue: 0.2), "米黄"),
        (Color.white, Color.black, "白色"),
        (Color(red: 0.80, green: 0.91, blue: 0.81), Color(red: 0.15, green: 0.25, blue: 0.15), "护眼"),
        (Color(red: 0.11, green: 0.11, blue: 0.12), Color(red: 0.65, green: 0.65, blue: 0.65), "夜间"),
        (Color.black, Color(red: 0.74, green: 0.74, blue: 0.78), "纯黑")
    ]
}
