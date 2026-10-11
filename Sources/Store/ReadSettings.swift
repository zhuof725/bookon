import SwiftUI

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
    @AppStorage("pageMode") var pageMode: Int = 0
    @AppStorage("pageTurnStyle") var pageTurnStyle: Int = 0

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

    var typographyValues: [Double] {
        [fontSize, lineSpacing, paragraphSpacing, leftMargin, rightMargin, topMargin, bottomMargin,
         fullJustify ? 1 : 0, bottomJustify ? 1 : 0]
    }

    static let themes: [(bg: Color, fg: Color, name: String)] = [
        (Color(red: 0.98, green: 0.96, blue: 0.90), Color(red: 0.2, green: 0.2, blue: 0.2), "米黄"),
        (Color.white, Color.black, "白色"),
        (Color(red: 0.80, green: 0.91, blue: 0.81), Color(red: 0.15, green: 0.25, blue: 0.15), "护眼"),
        (Color(red: 0.11, green: 0.11, blue: 0.12), Color(red: 0.65, green: 0.65, blue: 0.65), "夜间")
    ]
}
