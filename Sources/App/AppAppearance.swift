import SwiftUI

/// App-owned appearance, independent from reader paper preferences.
enum AppAppearance: Int, CaseIterable, Identifiable {
    case system = 0
    case light = 1
    case dark = 2
    static let storageKey = "app.appearance.v1"
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }
    var detail: String {
        switch self {
        case .system: return "根据系统外观自动切换"
        case .light: return "始终使用浅色界面"
        case .dark: return "始终使用深色界面"
        }
    }
    var symbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// Preserve the saved palette grid. New themes start with independent settings;
/// built-ins remain available to apply or copy through the edit action.
struct AppAppearanceSettingsView: View {
    @ObservedObject private var store: AppThemeStore
    @AppStorage(AppAppearance.storageKey) private var rawAppearance = AppAppearance.system.rawValue
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var searchFocused: Bool
    @State private var browsedID: String?
    @State private var editorTheme: AppTheme?
    @State private var pendingDelete: AppTheme?
    @State private var notice: String?
    @State private var showingSearch = false
    @State private var searchText = ""
    @State private var themeFilter: ThemeFilter = .all
    @State private var revealEditor = 0

    private enum ThemeFilter: String, CaseIterable, Identifiable {
        case all, builtin, custom
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: return "全部"
            case .builtin: return "内置"
            case .custom: return "自创"
            }
        }
        func includes(_ theme: AppTheme) -> Bool {
            switch self {
            case .all: return true
            case .builtin: return theme.isBuiltIn
            case .custom: return !theme.isBuiltIn
            }
        }
    }

    init(store: AppThemeStore = .shared) {
        _store = ObservedObject(wrappedValue: store)
    }
    private var appearance: AppAppearance { AppAppearance(rawValue: rawAppearance) ?? .system }
    private var browsedTheme: AppTheme {
        store.themes.first { $0.id == browsedID } ?? store.selectedTheme
    }
    private var filteredThemes: [AppTheme] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.themes.filter {
            themeFilter.includes($0) && (query.isEmpty || $0.name.localizedStandardContains(query))
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    paletteSection.id("theme.hub.top")
                    modeSection
                    interfaceSection.id("theme.hub.editor")
                    if let message = notice ?? store.notice {
                        Text(message).appFont(.footnote).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("theme.notice")
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 28)
                .padding(.bottom, 32)
            }
            .accessibilityIdentifier("theme.hub.scroll")
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: revealEditor) { _ in
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                    proxy.scrollTo("theme.hub.editor", anchor: .center)
                }
            }
            .onChange(of: showingSearch) { expanded in
                if expanded {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                        proxy.scrollTo("theme.hub.top", anchor: .top)
                    }
                }
            }
        }
        .foregroundStyle(.primary)
        .tint(Color.primary)
        .background { AppThemeCanvas().ignoresSafeArea() }
        .navigationTitle("外观主题")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    searchFocused = false
                    showingSearch.toggle()
                    if !showingSearch { searchText = ""; themeFilter = .all }
                } label: {
                    Image(systemName: showingSearch ? "xmark" : "magnifyingglass")
                        .font(.system(size: 16, weight: .regular))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel(showingSearch ? "收起搜索与筛选" : "搜索与筛选主题")
                .accessibilityIdentifier("theme.search.toggle")
            }
        }
        .modifier(AppTypographyRoot())
        .environment(\.appTheme, store.selectedTheme)
        .onAppear { normalizeBrowsedTheme() }
        .onChange(of: store.customThemes) { _ in normalizeBrowsedTheme() }
        .fullScreenCover(item: $editorTheme) { theme in
            ThemeEditorView(theme: theme, store: store, onCancel: { editorTheme = nil }, onSaved: {
                editorTheme = nil
                browsedID = theme.id
                searchText = ""; themeFilter = .all; showingSearch = false
                notice = "主题已保存"
                revealEditor += 1
            })
        }
        .alert("删除主题？", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        ), presenting: pendingDelete) { theme in
            Button("取消", role: .cancel) { pendingDelete = nil }
            Button("删除", role: .destructive) {
                delete(theme); pendingDelete = nil
            }.accessibilityIdentifier("theme.delete.confirm")
        } message: { theme in
            Text("“\(theme.name)”将从本机移除。")
        }
    }

    private var paletteSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            if showingSearch {
                searchField
                filterPicker
            }
            // No artificial eight-item cap: every saved custom theme stays reachable.
            ThemeHomeGrid(themes: filteredThemes, selectedID: store.selectedID,
                          browsedID: browsedTheme.id, onBrowse: { theme in
                searchFocused = false
                browsedID = theme.id
            }, onCreate: {
                searchFocused = false; editorTheme = AppTheme.custom()
            })
            if filteredThemes.isEmpty {
                Text(searchText.isEmpty ? "暂无此类主题，点按新建开始。" : "没有匹配的主题，请调整搜索或筛选。")
                    .appFont(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("主题切换").appFont(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            valueRow(title: "应用外观") {
                Text(appearance.title).appFont(.body)
                    .accessibilityIdentifier("appearance.current.value")
            }
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 4)) : AnyLayout(HStackLayout(spacing: 4))
            layout {
                ForEach(AppAppearance.allCases) { mode in
                    Button { rawAppearance = mode.rawValue } label: {
                        HStack(spacing: 5) {
                            Image(systemName: mode.symbol).font(.system(size: 13))
                            Text(mode == .system ? "系统" : mode.title)
                                .appFont(.subheadline.weight(mode == appearance ? .semibold : .regular))
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(mode == appearance ? Color(uiColor: .secondarySystemGroupedBackground) : .clear,
                                    in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(mode.title)
                    .accessibilityHint(mode.detail)
                    .accessibilityIdentifier("appearance.theme.\(mode.rawValue)")
                    .accessibilityAddTraits(mode == appearance ? .isSelected : [])
                }
            }
            .padding(3)
            .appGlass(in: RoundedRectangle(cornerRadius: 13))
            valueRow(title: "当前主题") {
                Text(store.selectedTheme.name).appFont(.body)
                    .accessibilityIdentifier("theme.gallery.selected")
            }
        }
    }

    private var interfaceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("界面与外观").appFont(.title3.weight(.semibold))
                .padding(.bottom, 10).accessibilityAddTraits(.isHeader)
            glassModeRow
            valueRow(title: "配色方案") {
                Text(browsedTheme.name).appFont(.body)
                    .accessibilityIdentifier("theme.gallery.name")
            }
            Button { customizeBrowsedTheme() } label: {
                settingLabel(title: "编辑主题", symbol: "slider.horizontal.3",
                             value: browsedTheme.isBuiltIn ? "创建副本" : "编辑", chevron: true)
            }
            .buttonStyle(.plain).accessibilityIdentifier("theme.customize")
            Button { apply(browsedTheme) } label: {
                settingLabel(title: browsedTheme.id == store.selectedID ? "正在使用" : "使用主题",
                             symbol: "checkmark.circle", value: "", chevron: false)
            }
            .buttonStyle(.plain)
            .disabled(browsedTheme.id == store.selectedID)
            .accessibilityIdentifier("theme.use")
            if !browsedTheme.isBuiltIn {
                Button(role: .destructive) { pendingDelete = browsedTheme } label: {
                    settingLabel(title: "删除主题", symbol: "trash", value: "", chevron: false)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain).accessibilityIdentifier("theme.delete")
            }
        }
    }

    private var glassModeRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "rectangle.on.rectangle.angled")
                .font(.system(size: 21, weight: .regular))
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("玻璃模式").appFont(.body)
                Text(glassEnabled
                     ? "卡片、按钮与浮层使用毛玻璃模糊"
                     : "已关闭：改用实色背景，滚动更省电")
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: $glassEnabled)
                .labelsHidden()
                .accessibilityLabel("玻璃模式")
                .accessibilityIdentifier("appearance.glassMode")
        }
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
        .padding(.horizontal, 16).padding(.vertical, 8)
        .modifier(SettingsGlassSurface())
    }

    private func valueRow<Value: View>(title: String, @ViewBuilder value: () -> Value) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
        return layout {
            Text(title).appFont(.body)
            if !typeSize.isAccessibilitySize { Spacer(minLength: 4) }
            value().fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .padding(14).modifier(SettingsGlassSurface())
    }

    private func settingLabel(title: String, symbol: String, value: String, chevron: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 23, weight: .regular))
                .frame(width: 28).accessibilityHidden(true)
            Text(title).appFont(.body).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if !value.isEmpty {
                Text(value).appFont(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if chevron {
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary).accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
        .padding(.horizontal, 16).padding(.vertical, 4)
        .modifier(SettingsGlassSurface())
        .contentShape(Rectangle())
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("搜索 \(store.themes.count) 个主题", text: $searchText)
                .appFont(.subheadline).textInputAutocapitalization(.never).autocorrectionDisabled()
                .focused($searchFocused).submitLabel(.search).onSubmit { searchFocused = false }
                .accessibilityLabel("搜索主题").accessibilityIdentifier("theme.search")
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain).accessibilityLabel("清除搜索")
            }
        }
        .padding(.leading, 13).padding(.trailing, searchText.isEmpty ? 13 : 0)
        .frame(minHeight: 46)
        .appGlass(in: RoundedRectangle(cornerRadius: 13))
    }

    private var filterPicker: some View {
        HStack(spacing: 5) {
            ForEach(ThemeFilter.allCases) { filter in
                Button { themeFilter = filter } label: {
                    Text(filter.title).appFont(.subheadline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(themeFilter == filter ? Color(uiColor: .tertiarySystemFill) : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(themeFilter == filter ? .isSelected : [])
                .accessibilityIdentifier("theme.filter.\(filter.rawValue)")
            }
        }
    }

    private func normalizeBrowsedTheme() {
        if let browsedID, store.themes.contains(where: { $0.id == browsedID }) { return }
        browsedID = store.selectedID
    }
    private func customizeBrowsedTheme() {
        searchFocused = false
        editorTheme = browsedTheme.isBuiltIn ? browsedTheme.draft() : browsedTheme
    }
    private func apply(_ theme: AppTheme) {
        do { try store.apply(id: theme.id); notice = "已使用“\(theme.name)”" }
        catch { notice = "使用主题失败：\(error.localizedDescription)" }
    }
    private func delete(_ theme: AppTheme) {
        do {
            try store.delete(id: theme.id)
            normalizeBrowsedTheme()
            notice = "已删除“\(theme.name)”"
        } catch { notice = "删除主题失败：\(error.localizedDescription)" }
    }
}
