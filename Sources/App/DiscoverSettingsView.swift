import SwiftUI

/// 书签（发现）设置：展示布局、榜单样式、展示数量、预加载、封面并发与缓存。
struct DiscoverSettingsView: View {
    @ThemePalette private var palette
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SourceListLayout.layoutKey) private var layoutRaw = SourceListLayout.grid.rawValue
    @AppStorage(DiscoverSettings.gridColumnsKey) private var gridColumns = 2
    @AppStorage(DiscoverSettings.pageLayoutKey) private var pageLayoutRaw = DiscoverSettings.PageLayout.magazine.rawValue
    @AppStorage(DiscoverSettings.rankingModeKey) private var rankingModeRaw = DiscoverSettings.RankingMode.cycle.rawValue
    @AppStorage(DiscoverSettings.rankingKeywordsKey) private var keywordsRaw = ""
    @AppStorage(DiscoverSettings.verticalCountKey) private var verticalCount = DiscoverSettings.defaultVerticalCount
    @AppStorage(DiscoverSettings.horizontalCountKey) private var horizontalCount = DiscoverSettings.defaultHorizontalCount
    @AppStorage(DiscoverSettings.cycleVerticalKey) private var cycleVertical = DiscoverSettings.defaultCycleVertical
    @AppStorage(DiscoverSettings.cycleHorizontalKey) private var cycleHorizontal = DiscoverSettings.defaultCycleHorizontal
    @AppStorage(DiscoverSettings.preloadCountKey) private var preloadCount = DiscoverSettings.defaultPreloadCount
    @AppStorage(DiscoverSettings.homeGroupKey) private var homeGroup = ""
    @AppStorage(DiscoverSettings.coverConcurrencyKey) private var coverConcurrency = DiscoverSettings.defaultCoverConcurrency
    @AppStorage(DiscoverSettings.cacheDaysKey) private var cacheDays = DiscoverSettings.defaultCacheDays
    @State private var showAddKeyword = false
    @State private var newKeyword = ""

    private var gridEnabled: Bool { layoutRaw == SourceListLayout.grid.rawValue }
    private var gridBinding: Binding<Bool> {
        Binding(
            get: { layoutRaw == SourceListLayout.grid.rawValue },
            set: { layoutRaw = $0 ? SourceListLayout.grid.rawValue : SourceListLayout.list.rawValue }
        )
    }
    private var pageLayout: DiscoverSettings.PageLayout {
        DiscoverSettings.PageLayout(rawValue: pageLayoutRaw) ?? .magazine
    }
    private var rankingMode: DiscoverSettings.RankingMode {
        DiscoverSettings.RankingMode(rawValue: rankingModeRaw) ?? .cycle
    }
    private var keywords: [String] { DiscoverSettings.keywords(from: keywordsRaw) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("书签页网格布局", isOn: gridBinding)
                        .accessibilityIdentifier("discover.settings.grid")
                    if gridEnabled {
                        Picker("网格列数", selection: $gridColumns) {
                            ForEach(DiscoverSettings.columnChoices, id: \.self) { value in
                                Text("\(value)").tag(value)
                            }
                        }
                        .accessibilityIdentifier("discover.settings.columns")
                    }
                } header: {
                    Text("书签页")
                } footer: {
                    Text("书签页站点和配置的展示方式。")
                }

                Section {
                    Picker("书签布局", selection: $pageLayoutRaw) {
                        Text(DiscoverSettings.PageLayout.magazine.title)
                            .tag(DiscoverSettings.PageLayout.magazine.rawValue)
                        Text(DiscoverSettings.PageLayout.list.title)
                            .tag(DiscoverSettings.PageLayout.list.rawValue)
                    }
                    .accessibilityIdentifier("discover.settings.pageLayout")
                } header: {
                    Text("布局")
                } footer: {
                    Text(pageLayout == .magazine ? "杂志布局把配置的所有榜单平铺成一屏。" : "列表布局是分类筛选 + 书卡列表。")
                }

                Section {
                    NavigationLink {
                        DiscoverHomeGroupPicker()
                    } label: {
                        HStack {
                            Label("首屏配置", systemImage: "arrow.right.circle")
                            Spacer()
                            Text(homeGroup.isEmpty ? "不启用" : homeGroup)
                                .foregroundStyle(palette.secondary)
                        }
                    }
                } header: {
                    Text("首屏配置")
                } footer: {
                    Text("设置后，打开书签时会直接进入该配置。")
                }

                Section {
                    Picker("排列方式", selection: $rankingModeRaw) {
                        ForEach(DiscoverSettings.RankingMode.allCases, id: \.rawValue) { mode in
                            Text(mode.title).tag(mode.rawValue)
                        }
                    }
                    .accessibilityIdentifier("discover.settings.rankingMode")
                } header: {
                    Text("榜单排列方式")
                } footer: {
                    Text("标题命中关键词的用竖排榜单，其余横滑。")
                }

                if rankingMode == .cycle {
                    Section {
                        Picker("竖排数量", selection: $cycleVertical) {
                            ForEach(0...10, id: \.self) { value in
                                Text("\(value)").tag(value)
                            }
                        }
                        Picker("横滑数量", selection: $cycleHorizontal) {
                            ForEach(0...10, id: \.self) { value in
                                Text("\(value)").tag(value)
                            }
                        }
                    } header: {
                        Text("循环数量")
                    } footer: {
                        Text("每个周期先 \(cycleVertical) 个竖排榜单、再 \(cycleHorizontal) 个横滑榜单，如此循环。")
                    }
                }

                if rankingMode == .keyword {
                    Section {
                        ForEach(keywords, id: \.self) { keyword in
                            HStack(spacing: 10) {
                                Image(systemName: "number")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(palette.accent)
                                    .frame(width: 22)
                                Text(keyword).appFont(.body)
                            }
                            .accessibilityIdentifier("discover.keyword.\(keyword)")
                        }
                        .onDelete(perform: deleteKeywords)
                        Button {
                            newKeyword = ""
                            showAddKeyword = true
                        } label: {
                            Label("添加关键词", systemImage: "plus.circle")
                        }
                        Button {
                            keywordsRaw = ""
                        } label: {
                            Label("恢复默认关键词", systemImage: "arrow.counterclockwise")
                        }
                    } header: {
                        Text("竖排榜单关键词")
                    } footer: {
                        Text("标题包含任一关键词的榜单用竖排序号样式，其余用横滑封面。左滑可删除。")
                    }
                }

                Section {
                    Picker("竖排展示数", selection: $verticalCount) {
                        ForEach(1...10, id: \.self) { value in
                            Text("\(value)").tag(value)
                        }
                    }
                    Picker("横滑展示数", selection: $horizontalCount) {
                        ForEach(1...20, id: \.self) { value in
                            Text("\(value)").tag(value)
                        }
                    }
                } header: {
                    Text("榜单展示数量")
                } footer: {
                    Text("每个榜单展示的书籍数量。竖排序号榜单与横滑封面榜单可分别设置。")
                }

                Section {
                    Picker("预加载数量", selection: $preloadCount) {
                        ForEach(0...10, id: \.self) { value in
                            Text("\(value)").tag(value)
                        }
                    }
                } header: {
                    Text("预加载")
                } footer: {
                    Text("滚动到某个榜单时，向后多加载几个榜单。数值越大滑动越不易看到加载占位，但同时发起的网络请求也越多。")
                }

                Section {
                    Picker("封面并发数", selection: $coverConcurrency) {
                        ForEach(1...10, id: \.self) { value in
                            Text("\(value)").tag(value)
                        }
                    }
                } header: {
                    Text("封面并发")
                } footer: {
                    Text("同时下载的封面图片数量上限。数值越低滚动时越不易发热，但封面加载稍慢；分类多的配置建议调低。")
                }

                Section {
                    Picker("缓存有效期", selection: $cacheDays) {
                        ForEach(DiscoverSettings.cacheDayChoices, id: \.self) { value in
                            Text("\(value) 天").tag(value)
                        }
                    }
                } header: {
                    Text("书签缓存")
                } footer: {
                    Text("缓存期内进出书签直接用本地数据，不重新加载；下拉刷新始终拉取最新。")
                }
            }
            .scrollContentBackground(.hidden)
            .foregroundStyle(palette.primary)
            .background { AppThemeCanvas().ignoresSafeArea() }
            .navigationTitle("书签设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .accessibilityIdentifier("discover.settings.done")
                }
            }
            .alert("添加关键词", isPresented: $showAddKeyword) {
                TextField("关键词", text: $newKeyword)
                Button("取消", role: .cancel) {}
                Button("添加") { addKeyword() }
            }
        }
    }

    private func addKeyword() {
        let value = newKeyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        var list = keywords
        if !list.contains(value) { list.append(value) }
        keywordsRaw = DiscoverSettings.keywordsText(list)
    }

    private func deleteKeywords(_ offsets: IndexSet) {
        var list = keywords
        list.remove(atOffsets: offsets)
        keywordsRaw = DiscoverSettings.keywordsText(list)
    }
}

/// 首屏配置：选择打开发现时直接进入的分组（或「不启用」）。
private struct DiscoverHomeGroupPicker: View {
    @ThemePalette private var palette
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage(DiscoverSettings.homeGroupKey) private var homeGroup = ""

    private var groups: [String] {
        DiscoverCatalog.sections(store.sources).map(\.name)
    }

    var body: some View {
        List {
            row(title: "不启用", selected: homeGroup.isEmpty) {
                homeGroup = ""
                dismiss()
            }
            ForEach(groups, id: \.self) { group in
                row(title: group, selected: homeGroup == group) {
                    homeGroup = group
                    dismiss()
                }
            }
        }
        .scrollContentBackground(.hidden)
        .foregroundStyle(palette.primary)
        .background { AppThemeCanvas().ignoresSafeArea() }
        .navigationTitle("首屏配置")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                if selected {
                    Image(systemName: "checkmark").foregroundStyle(palette.accent)
                }
            }
        }
    }
}
