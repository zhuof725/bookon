import SwiftUI

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
