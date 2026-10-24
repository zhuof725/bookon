import SwiftUI
import UIKit

// Only the web user agent is stubbed. The paragraph, tap recognizer and sheet
// are the production sources; no book source or network access is needed.
enum WebViewSupport { static let userAgent = "ReaderInteractionTests" }

@main
struct HarnessApp: App {
    @StateObject private var customThemeStore: AppThemeStore

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let customThemeDefaults = CustomThemeHarnessSupport.defaults
        if arguments.contains("--custom-theme-seed") {
            // The custom-theme suite is the only persisted state owned by this
            // route. Do not relaunch or clear appearance, font, reader, or
            // other app defaults while seeding a test.
            customThemeDefaults.removeObject(forKey: AppThemeStore.storageKey)
        }
        _customThemeStore = StateObject(wrappedValue: AppThemeStore(defaults: customThemeDefaults,
            assets: CustomThemeHarnessSupport.assets))

        if arguments.contains("--shelf-mode") {
            ShelfFixture.resetDefaults()
        }
        if ProcessInfo.processInfo.arguments.contains("--font-mode") || ProcessInfo.processInfo.arguments.contains("--app-font-mode") {
            FontFixture.resetSharedSelectionBeforeLaunch()
        }
        if ProcessInfo.processInfo.arguments.contains("--appearance-reset") {
            UserDefaults.standard.removeObject(forKey: AppAppearance.storageKey)
        }
        // 仅测试 App：保留 UIKit NSException 的 reason，不能把初次安装崩溃误报为锁未释放。
        NSSetUncaughtExceptionHandler { exception in
            let message = "[ReaderHarness uncaught exception] \(exception.name.rawValue): \(exception.reason ?? "<nil>")\n"
                + exception.callStackSymbols.joined(separator: "\n") + "\n"
            FileHandle.standardError.write(Data(message.utf8))
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if ProcessInfo.processInfo.arguments.contains("--aloud-highlight") {
                    AloudHighlightHarnessView()
                } else if ProcessInfo.processInfo.arguments.contains("--live-appearance-mode") {
                    LiveAppearanceHarness()
                } else if ProcessInfo.processInfo.arguments.contains("--independent-rows-mode") {
                    IndependentRowsHarness()
                } else if ProcessInfo.processInfo.arguments.contains("--appearance-fix-mode") {
                    AppearanceFixHarness()
                } else if ProcessInfo.processInfo.arguments.contains("--settings-glass-mode") {
                    SettingsGlassHarness()
                } else if ProcessInfo.processInfo.arguments.contains("--native-tabs-mode") {
                    NativeTabsGlassHarness()
                } else if ProcessInfo.processInfo.arguments.contains("--native-glass-mode") {
                    NativeGlassHarness()
                } else if ProcessInfo.processInfo.arguments.contains("--cache-management-mode") {
                    CacheManagementHarnessView()
                } else if ProcessInfo.processInfo.arguments.contains("--search-history-mode") {
                    SearchHistoryHarnessView()
                } else if ProcessInfo.processInfo.arguments.contains("--cover-persistence-mode") {
                    CoverPersistenceHarnessView()
                } else if ProcessInfo.processInfo.arguments.contains("--app-font-mode") {
                    AppFontHarnessView()
                } else if ProcessInfo.processInfo.arguments.contains("--font-mode") {
                    FontHarnessView()
                } else if ProcessInfo.processInfo.arguments.contains("--body-rules-mode") {
                    BodyRulesHarnessView()
                } else if ProcessInfo.processInfo.arguments.contains("--toc-rules-mode") {
                    TocRulesHarnessView()
                } else if ProcessInfo.processInfo.arguments.contains("--custom-theme-mode") {
                    CustomThemeHarnessView(store: customThemeStore)
                        .modifier(AppThemeRoot(store: customThemeStore))
                } else if ProcessInfo.processInfo.arguments.contains("--theme-mode") {
                    ThemeHarnessView()
                } else if ProcessInfo.processInfo.arguments.contains("--appearance-mode") {
                    AppearanceHarnessView()
                } else if ProcessInfo.processInfo.arguments.contains("--detail-mode") {
                    DetailHarnessView()
                } else if let mode = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--nav-bar-mode=") }) {
                    NavBarOverflowHarnessView(mode: String(mode.dropFirst("--nav-bar-mode=".count)))
                } else if ProcessInfo.processInfo.arguments.contains("--stats-data-mode") {
                    StatsDataHarnessView()
                } else if ProcessInfo.processInfo.arguments.contains("--stats-mode") {
                    StatsHarnessView()
                } else if ProcessInfo.processInfo.arguments.contains("--shelf-mode") {
                    ShelfHarnessView()
                } else if ProcessInfo.processInfo.arguments.contains("--bottom-bubble-mode") {
                    BottomBubbleHarnessView()
                } else if ProcessInfo.processInfo.arguments.contains("--punctuation-flow-mode") {
                    PunctuationFlowHarnessView()
                } else if ProcessInfo.processInfo.arguments.contains("--reader-page-flow-mode") {
                    ReaderPageFlowHarnessView()
                } else if ProcessInfo.processInfo.arguments.contains("--reader-chrome-mode") {
                    ChromeHarnessView()
                } else if ProcessInfo.processInfo.arguments.contains("--reader-toc-mode") {
                    ReaderTocHarnessView()
                } else if ProcessInfo.processInfo.arguments.contains("--layout-audit-mode") {
                    LayoutAuditHarnessView()
                } else if ProcessInfo.processInfo.arguments.contains("--continuous-scroll-mode") {
                    ContinuousScrollHarnessView()
                } else if ProcessInfo.processInfo.arguments.contains("--typography-mode") {
                    TypographyHarnessView()
                } else if ProcessInfo.processInfo.arguments.contains("--cover-mode") {
                    CoverTurnHarnessView()
                } else if let mode = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--volume-mode=") }) {
                    VolumeHarnessView(mode: String(mode.dropFirst("--volume-mode=".count)))
                } else if let mode = ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--chapter-mode=") }) {
                    ChapterHarnessView(mode: String(mode.dropFirst("--chapter-mode=".count)))
                } else {
                    HarnessView()
                }
            }
            .modifier(MonochromeAppStyle())
        }
    }
}

struct HarnessView: View {
    @State private var comments = 0
    @State private var bars = 0
    @State private var probe = "none"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(0..<40) { i in
                    InlineCommentParagraph(
                        text: "第\(i)段 👨‍👩‍👧‍👦 " + String(repeating: "这是滚动阅读的段评点击测试。", count: 3),
                        count: 82, fontSize: 19, lineSpacing: 8, color: .black,
                        onTextTap: { bars += 1 }, onTap: { comments += 1 })
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 20)
        }
        .background { Color.white.onTapGesture { bars += 1 } }
        .safeAreaInset(edge: .bottom) {
            VStack {
                Text("comments=\(comments);bars=\(bars)").accessibilityIdentifier("counts")
                Button("Locate visible bubble", action: locate).accessibilityIdentifier("locate")
                Text(probe).font(.system(size: 8)).accessibilityIdentifier("probe")
            }.frame(maxWidth: .infinity).background(.white)
        }
    }

    // Read real TextKit glyph coordinates after layout/scrolling. This does not
    // invoke the tap callback: XCUITest sends the actual finger tap or drag.
    private func locate() {
        guard let window = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows).first(where: \.isKeyWindow) else { return }
        func descendants(_ view: UIView) -> [CommentTextView] {
            (view as? CommentTextView).map { [$0] } ?? view.subviews.flatMap(descendants)
        }
        for view in descendants(window) {
            guard let rect = view.bubbleRect else { continue }
            let p = view.convert(CGPoint(x: rect.midX, y: rect.midY), to: window)
            guard p.y > 190, p.y < window.bounds.height - 240 else { continue }
            let body = view.convert(CGPoint(x: 55, y: 10), to: window)
            probe = "\(p.x),\(p.y),\(body.x),\(body.y),\(view.text ?? "")"
            return
        }
        probe = "none"
    }
}
