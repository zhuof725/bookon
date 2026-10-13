import SwiftUI

/// The appearance mode of the app-owned interface. Reader paper themes remain
/// a separate preference because they are part of reading layout and content.
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

/// The appearance entry point combines the saved theme selection with the
/// system/light/dark mode preference. Browsing a card never changes selection;
/// the explicit “使用主题” action does that.
struct AppAppearanceSettingsView: View {
    @ObservedObject private var store: AppThemeStore
    @AppStorage(AppAppearance.storageKey) private var rawAppearance = AppAppearance.system.rawValue

    @State private var browsedID: String?
    @State private var showingTemplateGallery = false
    @State private var pendingDraft: AppTheme?
    @State private var editorTheme: AppTheme?
    @State private var pendingDelete: AppTheme?
    @State private var notice: String?
    @State private var searchText = ""
    @State private var themeFilter: ThemeFilter = .all
    @State private var revealBrowsedTheme = 0
    @FocusState private var searchFocused: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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

    private var appearance: AppAppearance {
        AppAppearance(rawValue: rawAppearance) ?? .system
    }

    private var browsedTheme: AppTheme? {
        if let browsedID,
           let theme = store.themes.first(where: { $0.id == browsedID }) {
            return theme
        }
        if let theme = store.themes.first(where: { $0.id == store.selectedID }) {
            return theme
        }
        return store.themes.first
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
                VStack(alignment: .leading, spacing: 16) {
                    modeSection.id("theme.hub.top")
                    browsedThemeActions
                    if let message = notice ?? store.notice {
                        Text(message)
                            .appFont(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 4)
                    }
                    themeGallerySection
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: revealBrowsedTheme) { _ in
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                    proxy.scrollTo("theme.hub.top", anchor: .top)
                }
            }
        }
        .foregroundStyle(.primary)
        .tint(.primary)
        .background(ThemeHubSurface.canvas.ignoresSafeArea())
        .navigationTitle("外观主题")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .modifier(AppTypographyRoot())
        // Browsing never changes the saved environment or navigation identity.
        .environment(\.appTheme, store.selectedTheme)
        .onAppear { normalizeBrowsedTheme() }
        .onChange(of: store.selectedID) { _ in
            if browsedID == nil { normalizeBrowsedTheme() }
        }
        .onChange(of: store.customThemes) { _ in normalizeBrowsedTheme() }
        .fullScreenCover(isPresented: $showingTemplateGallery, onDismiss: {
            if let pendingDraft {
                editorTheme = pendingDraft
                self.pendingDraft = nil
            }
        }) {
            ThemeGalleryView(
                onCancel: {
                    pendingDraft = nil
                    showingTemplateGallery = false
                },
                onSelect: { draft in
                    pendingDraft = draft
                    showingTemplateGallery = false
                }
            )
        }
        .fullScreenCover(item: $editorTheme) { theme in
            ThemeEditorView(
                theme: theme,
                store: store,
                onCancel: { editorTheme = nil },
                onSaved: {
                    editorTheme = nil
                    browsedID = theme.id
                    searchText = ""
                    themeFilter = .all
                    revealBrowsedTheme += 1
                    notice = "主题已保存"
                }
            )
        }
        .alert("删除主题？", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        ), presenting: pendingDelete) { theme in
            Button("取消", role: .cancel) { pendingDelete = nil }
                .appFont(.body)
            Button("删除", role: .destructive) {
                delete(theme)
                pendingDelete = nil
            }
            .appFont(.body)
            .accessibilityIdentifier("theme.delete.confirm")
        } message: { theme in
            Text("“\(theme.name)”将从本机移除。")
                .appFont(.body)
        }
    }

    private var themeGallerySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("我的主题")
                    .appFont(.headline)
                Text("\(store.themes.count)")
                    .appFont(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button {
                    searchFocused = false
                    pendingDraft = nil
                    showingTemplateGallery = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .background(ThemeHubSurface.card, in: Circle())
                        .overlay(Circle().strokeBorder(ThemeHubSurface.border, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("添加主题")
                .accessibilityIdentifier("theme.add")
            }
            searchField
            filterPicker
            if filteredThemes.isEmpty {
                emptyGallery
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(filteredThemes) { theme in
                        Button { browse(theme) } label: {
                            ThemeSplitPreview(theme: theme, isSelected: theme.id == store.selectedID)
                                .overlay(alignment: .topLeading) {
                                    if theme.id == browsedTheme?.id {
                                        Text("浏览中")
                                            .appFont(.caption2.weight(.medium))
                                            .foregroundStyle(.primary)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(ThemeHubSurface.card, in: Capsule())
                                            .padding(9)
                                            .accessibilityHidden(true)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(theme.name)，\(theme.isBuiltIn ? "内置" : "自创")主题")
                        .accessibilityValue(browseStatus(for: theme))
                        .accessibilityHint("查看此主题的操作，不会立即应用")
                        .accessibilityAddTraits(theme.id == store.selectedID ? .isSelected : [])
                        .accessibilityIdentifier("theme.browse.\(theme.id)")
                    }
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("搜索 \(store.themes.count) 个主题", text: $searchText)
                .appFont(.subheadline)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .submitLabel(.search)
                .focused($searchFocused)
                .onSubmit { searchFocused = false }
                .accessibilityLabel("搜索主题")
                .accessibilityIdentifier("theme.search")
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜索")
            }
        }
        .padding(.leading, 13)
        .padding(.trailing, searchText.isEmpty ? 13 : 0)
        .padding(.vertical, 2)
        .frame(minHeight: 46)
        .background(ThemeHubSurface.card, in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(ThemeHubSurface.border, lineWidth: 0.5))
    }

    private var filterPicker: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 3)) : AnyLayout(HStackLayout(spacing: 3))
        return layout {
            ForEach(ThemeFilter.allCases) { filter in
                Button { themeFilter = filter } label: {
                    Text(filter.title)
                        .appFont(.subheadline.weight(themeFilter == filter ? .semibold : .regular))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(themeFilter == filter ? ThemeHubSurface.card : .clear,
                                    in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("theme.filter.\(filter.rawValue)")
                .accessibilityAddTraits(themeFilter == filter ? .isSelected : [])
            }
        }
        .padding(3)
        .background(ThemeHubSurface.control, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("主题筛选")
    }

    private var emptyGallery: some View {
        VStack(spacing: 8) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(searchText.isEmpty ? "暂无\(themeFilter == .custom ? "自创" : "可用")主题" : "没有找到匹配的主题")
                .appFont(.headline)
            Text(searchText.isEmpty ? "点按加号，从内置模板创建主题。" : "试试其他名称，或调整筛选条件。")
                .appFont(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(ThemeHubSurface.card, in: RoundedRectangle(cornerRadius: 16))
    }

    private func browseStatus(for theme: AppTheme) -> String {
        let active = theme.id == store.selectedID
        let browsed = theme.id == browsedTheme?.id
        if active { return browsed ? "当前使用，正在浏览" : "当前使用" }
        return browsed ? "正在浏览，尚未使用" : "尚未使用"
    }

    private func browse(_ theme: AppTheme) {
        searchFocused = false
        browsedID = theme.id
        revealBrowsedTheme += 1
    }

    @ViewBuilder
    private var browsedThemeActions: some View {
        if let theme = browsedTheme {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(theme.id == store.selectedID ? "正在使用" : "正在浏览 · 尚未使用")
                            .appFont(.caption)
                            .foregroundStyle(.secondary)
                        Text(theme.name)
                            .appFont(.headline)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("theme.gallery.name")
                        ThemeSwatchStrip(theme: theme)
                            .padding(.top, 2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if !theme.isBuiltIn {
                        Button(role: .destructive) {
                            searchFocused = false
                            pendingDelete = theme
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 16, weight: .regular))
                                .foregroundStyle(.red)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("删除主题")
                        .accessibilityIdentifier("theme.delete")
                    }
                }
                themeActions(for: theme)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11, weight: .medium))
                        .accessibilityHidden(true)
                    Text("当前使用")
                        .appFont(.caption)
                    Text(store.selectedTheme.name)
                        .appFont(.caption.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("theme.gallery.selected")
                }
                .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ThemeHubSurface.card, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(ThemeHubSurface.border, lineWidth: 0.5))
            .shadow(color: .black.opacity(0.025), radius: 6, x: 0, y: 2)
        }
    }

    private func themeActions(for theme: AppTheme) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            Button { customizeBrowsedTheme() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 14, weight: .medium))
                    Text("自定")
                        .appFont(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(ThemeHubSurface.control, in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .accessibilityHint(theme.isBuiltIn ? "从此主题创建副本" : "编辑此自创主题")
            .accessibilityIdentifier("theme.customize")
            Button { apply(theme) } label: {
                HStack(spacing: 6) {
                    if theme.id == store.selectedID {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    Text(theme.id == store.selectedID ? "正在使用" : "使用主题")
                        .appFont(.subheadline.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(ThemeHubSurface.card)
                .background(Color.primary, in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .disabled(theme.id == store.selectedID)
            .accessibilityIdentifier("theme.use")
        }
    }

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            modePicker
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("应用外观")
                    .appFont(.caption)
                Text(appearance.title)
                    .appFont(.caption.weight(.medium))
                    .accessibilityIdentifier("appearance.current.value")
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
        }
    }

    private var modePicker: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 3)) : AnyLayout(HStackLayout(spacing: 3))
        return layout {
            ForEach(AppAppearance.allCases) { mode in
                Button { rawAppearance = mode.rawValue } label: {
                    HStack(spacing: 5) {
                        Image(systemName: mode.symbol)
                            .font(.system(size: 13, weight: .medium))
                            .accessibilityHidden(true)
                        Text(mode == .system ? "系统" : mode.title)
                            .appFont(.subheadline.weight(mode == appearance ? .semibold : .regular))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(mode == appearance ? ThemeHubSurface.card : .clear,
                                in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mode.title)
                .accessibilityHint(mode.detail)
                .accessibilityIdentifier("appearance.theme.\(mode.rawValue)")
                .accessibilityAddTraits(mode == appearance ? .isSelected : [])
            }
        }
        .padding(3)
        .background(ThemeHubSurface.control, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("应用外观")
    }

    private func normalizeBrowsedTheme() {
        guard !store.themes.isEmpty else {
            browsedID = nil
            return
        }
        if let browsedID, store.themes.contains(where: { $0.id == browsedID }) { return }
        browsedID = store.themes.first(where: { $0.id == store.selectedID })?.id ?? store.themes[0].id
    }

    private func customizeBrowsedTheme() {
        guard let theme = browsedTheme else { return }
        searchFocused = false
        editorTheme = theme.isBuiltIn ? theme.draft() : theme
    }

    private func apply(_ theme: AppTheme) {
        searchFocused = false
        do {
            try store.apply(id: theme.id)
            notice = "已使用“\(theme.name)”"
        } catch {
            notice = "使用主题失败：\(error.localizedDescription)"
        }
    }

    private func delete(_ theme: AppTheme) {
        do {
            try store.delete(id: theme.id)
            normalizeBrowsedTheme()
            notice = "已删除“\(theme.name)”"
        } catch {
            notice = "删除主题失败：\(error.localizedDescription)"
        }
    }
}
