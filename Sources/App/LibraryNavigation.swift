import SwiftUI

struct LibraryStatisticsView: View {
    @ThemePalette private var palette
    @EnvironmentObject var store: AppStore
    private var started: Int { store.books.filter(ShelfBooks.isStarted).count }
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                LibraryCard("书库概览") {
                    LibraryValueRow(title: "书架书籍", value: "\(store.books.count) 本")
                    LibraryCardDivider()
                    LibraryValueRow(title: "已开始阅读", value: "\(started) 本")
                    LibraryCardDivider()
                    LibraryValueRow(title: "未读", value: "\(store.books.count - started) 本")
                    LibraryCardDivider()
                    LibraryValueRow(title: "本地书籍", value: "\(store.books.filter { store.isLocal($0) }.count) 本")
                }
                LibraryCard("最近阅读") {
                    let recent = Array(store.books.filter(ShelfBooks.isStarted).sorted { $0.lastReadAt > $1.lastReadAt }.prefix(10))
                    if recent.isEmpty {
                        Text("暂无阅读记录").foregroundStyle(palette.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                    }
                    ForEach(recent) { book in
                        NavigationLink { ReaderView(book: book) } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(book.name).foregroundStyle(palette.primary)
                                    Text(book.durChapterTitle ?? "阅读中").appFont(.caption).foregroundStyle(palette.secondary)
                                    Text(book.lastReadAt, style: .date).appFont(.caption).foregroundStyle(palette.secondary)
                                }
                                .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                                    .foregroundStyle(palette.secondary).accessibilityHidden(true)
                            }
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .padding(.horizontal, 20).padding(.vertical, 14)
                            .modifier(SettingsGlassSurface())
                            .contentShape(RoundedRectangle(cornerRadius: 24))
                        }
                        .buttonStyle(.plain)
                        if book.id != recent.last?.id { LibraryCardDivider() }
                    }
                }
                LibraryCard {
                    Text("统计来自书架与已保存的阅读进度；尚未记录阅读时长。")
                        .appFont(.footnote).foregroundStyle(palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 16)
        }
        .foregroundStyle(palette.primary)
        .background { AppThemeCanvas().ignoresSafeArea() }
        .navigationTitle("统计")
        .toolbar(.visible, for: .navigationBar)
    }
}

struct LibraryProfileView: View {
    @ThemePalette private var palette
    @EnvironmentObject var store: AppStore
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
                    }
                    Group {
                        NavigationLink { FontManagerView() } label: { LibraryLinkLabel(title: "字体管理", symbol: "textformat") }
                            .accessibilityIdentifier("library.fonts")
                        LibraryCardDivider()
                        NavigationLink { AppAppearanceSettingsView() } label: { LibraryLinkLabel(title: "外观主题", symbol: "circle.lefthalf.filled") }
                            .accessibilityIdentifier("library.appearance")
                        LibraryCardDivider()
                        NavigationLink { SearchView() } label: { LibraryLinkLabel(title: "搜索书籍", symbol: "magnifyingglass") }
                    }
                }
                LibraryCard("本机数据") {
                    NavigationLink { CacheManagementView() } label: { LibraryLinkLabel(title: "缓存管理", symbol: "internaldrive") }
                        .accessibilityIdentifier("library.cache")
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
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24).padding(.vertical, 16)
        }
        .foregroundStyle(palette.primary)
        .background { AppThemeCanvas().ignoresSafeArea() }
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
