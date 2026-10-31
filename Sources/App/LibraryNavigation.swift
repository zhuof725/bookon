import SwiftUI

// MARK: - 我的

struct LibraryProfileView: View {
    @ThemePalette private var palette
    @EnvironmentObject var store: AppStore
    @ObservedObject private var fonts = ReadingFontManager.shared
    @ObservedObject private var themeStore = AppThemeStore.shared
    @ObservedObject private var aiStore = AIServiceStore.shared
    @State private var crashCount = 0

    /// 「我的」页底部显示的版本（装错包/没更新时一眼能看出来）。
    static var versionText: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "尚书 \(short) (build \(build))"
    }
    var body: some View {
        ScrollView {
            VStack(spacing: AppLayout.gapL) {
                LibraryCard("阅读") {
                    NavigationLink {
                        LibraryStatisticsView(showsNavigationBar: true)
                    } label: {
                        LibraryLinkLabel(title: "阅读统计", symbol: "chart.bar")
                    }
                    .accessibilityIdentifier("library.statistics")
                    LibraryCardDivider()
                    PrecacheWindowSettingView(manager: .shared)
                }
                LibraryCard("书库") {
                    NavigationLink { SourcesView() } label: {
                        LibraryLinkLabel(title: "书源管理", symbol: "square.stack.3d.up",
                                         detail: "\(store.sources.count) 个")
                    }
                    .accessibilityIdentifier("library.sources")
                    LibraryCardDivider()
                    NavigationLink { TxtTocRulesView() } label: {
                        LibraryLinkLabel(title: "目录规则", symbol: "list.bullet.rectangle")
                    }
                    .accessibilityIdentifier("library.tocRules")
                    LibraryCardDivider()
                    NavigationLink { BodyReplaceRulesView() } label: {
                        LibraryLinkLabel(title: "替换规则", symbol: "text.badge.checkmark")
                    }
                    .accessibilityIdentifier("library.replaceRules")
                }
                LibraryCard("阅读辅助") {
                    NavigationLink { FontManagerView() } label: {
                        LibraryLinkLabel(title: "字体管理", symbol: "textformat",
                                         detail: fonts.selectedDisplayName)
                    }
                    .accessibilityIdentifier("library.fonts")
                    LibraryCardDivider()
                    NavigationLink { SpeakEngineList(aloud: ReaderAloudController()) } label: {
                        LibraryLinkLabel(title: "朗读引擎管理", symbol: "waveform.badge.mic")
                    }
                    .accessibilityIdentifier("library.speakEngines")
                    LibraryCardDivider()
                    NavigationLink { BubbleStyleSettingsView() } label: {
                        LibraryLinkLabel(title: "段评气泡", symbol: "bubble.right")
                    }
                    .accessibilityIdentifier("library.bubbleStyles")
                }
                LibraryCard("应用") {
                    NavigationLink { AIServiceView() } label: {
                        LibraryLinkLabel(title: "AI 提供商", symbol: "sparkles",
                                         detail: aiStore.activeConfig == nil ? "未配置" : "已配置")
                    }
                    .accessibilityIdentifier("library.ai")
                    LibraryCardDivider()
                    NavigationLink { AppAppearanceSettingsView() } label: {
                        LibraryLinkLabel(title: "外观主题", symbol: "circle.lefthalf.filled",
                                         detail: themeStore.selectedTheme.name)
                    }
                    .accessibilityIdentifier("library.appearance")
                    LibraryCardDivider()
                    NavigationLink { NetworkSettingsView() } label: {
                        LibraryLinkLabel(title: "网络设置", symbol: "network")
                    }
                    .accessibilityIdentifier("library.network")
                }
                LibraryCard("本机数据") {
                    NavigationLink { CacheManagementView() } label: {
                        LibraryLinkLabel(title: "缓存管理", symbol: "internaldrive")
                    }
                    .accessibilityIdentifier("library.cache")
                    LibraryCardDivider()
                    NavigationLink { CrashLogView() } label: {
                        LibraryLinkLabel(title: "崩溃日志", symbol: "exclamationmark.triangle",
                                         detail: crashCount > 0 ? "\(crashCount) 条" : "")
                    }
                    .accessibilityIdentifier("library.crashLogs")
                    LibraryCardDivider()
                    NavigationLink { ImportDiagnosticsView() } label: {
                        LibraryLinkLabel(title: "分享导入诊断", symbol: "ladybug")
                    }
                    .accessibilityIdentifier("library.importDiagnostics")
                    LibraryCardDivider()
                    LibraryValueRow(title: "已导入书源", value: "\(store.sources.count) 个")
                    LibraryCardDivider()
                    LibraryValueRow(title: "书架书籍", value: "\(store.books.count) 本")
                }
                LibraryCard {
                    Text("阅读进度、导入书源与本地书籍保存在本机。")
                        .foregroundStyle(palette.secondary).appFont(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                }
                Text(Self.versionText)
                    .foregroundStyle(palette.secondary).appFont(.caption)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("library.version")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, AppLayout.pageInset).padding(.vertical, AppLayout.gapL)
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
    var detail: String = ""
    var body: some View {
        SettingsGlassLabel(title: title, symbol: symbol, trailing: detail)
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
