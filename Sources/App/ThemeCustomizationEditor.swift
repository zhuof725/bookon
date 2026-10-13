import SwiftUI
import UIKit

/// The only owner of this editing transaction. Child pages receive bindings only.
struct ThemeEditorView: View {
    let initialTheme: AppTheme
    let onCancel: () -> Void
    let onSaved: () -> Void
    @ObservedObject private var store: AppThemeStore
    @ObservedObject private var fonts = ReadingFontManager.shared
    @Environment(\.dismiss) private var dismiss
    @State private var draft: AppTheme
    @State private var previewScheme: ColorScheme = .light
    @State private var showingDiscardConfirmation = false
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var imageTarget: ThemeEditorImageKind?
    @State private var pendingImage: (url: URL, kind: ThemeEditorImageKind)?
    @State private var newlyImportedIDs: Set<String> = []
    @State private var iconImportTab: LibraryTab?
    @State private var pendingIcon: (url: URL, tab: LibraryTab)?
    @FocusState private var nameFocused: Bool

    init(theme: AppTheme, store: AppThemeStore = .shared,
         onCancel: @escaping () -> Void = {}, onSaved: @escaping () -> Void = {}) {
        initialTheme = theme; self.onCancel = onCancel; self.onSaved = onSaved
        _store = ObservedObject(wrappedValue: store)
        _draft = State(initialValue: theme)
    }
    private var settings: ThemeCustomization { draft.customization ?? ThemeCustomization() }
    private var hasChanges: Bool { draft != initialTheme }
    private var canSave: Bool { !draft.isBuiltIn && draft.validationMessage == nil && !isSaving }
    private var isNew: Bool { !store.customThemes.contains { $0.id == draft.id } }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
            Form {
                Section {
                    TextField("主题名称", text: $draft.name)
                        .appFont(.body).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .focused($nameFocused).submitLabel(.done).onSubmit { nameFocused = false }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture { nameFocused = true }
                        .accessibilityLabel("主题名称").accessibilityIdentifier("theme.editor.name")
                } header: { Text("主题名称") }
                if draft.customization == nil {
                    Section {
                        Text("此主题保留原有布局；首次修改界面设置时，将启用自定义默认值：图标与文字、3列、112pt、玻璃。颜色编辑不会启用这些设置。")
                            .appFont(.footnote).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Section("界面") {
                    row(.tab, value: draft.customization == nil ? "仅图标 · 原有" : tabSummary)
                    row(.shelf, value: draft.customization == nil ? "自动适配 · 原有" : "\(settings.shelfColumns)列 · \(Int(settings.coverWidth.rounded()))pt")
                    row(.cover, value: imageSummary(settings.defaultCoverImage, empty: "系统默认"))
                    row(.launch, value: imageSummary(settings.launchImage, empty: "关"))
                }
                Section("外观") {
                    row(.colors, value: ThemeEditorFonts.name(settings.fontPostScriptName, manager: fonts))
                    row(.background, value: imageSummary(settings.pageBackgroundImage, empty: draft.backgroundStyle.title))
                    row(.effect, value: draft.customization == nil ? "原有样式" : effectSummary)
                    row(.cards, value: settings.cardBackground ? "已开启" : "已关闭")
                }
                Section {
                    DisclosureGroup("当前主题预览") {
                        ThemeEditorSchemePicker(selection: $previewScheme)
                        ThemeEditorLivePreview(theme: draft, scheme: previewScheme)
                            .padding(.vertical, 8)
                            .accessibilityIdentifier("theme.editor.preview")
                    }
                    .accessibilityIdentifier("theme.editor.preview.toggle")
                } footer: {
                    Text(draft.id == store.selectedID
                         ? "保存后更新正在使用的主题。返回各设置页不会丢失草稿。"
                         : "保存到主题列表后，可点按“使用主题”应用。")
                }
                if let message = errorMessage ?? draft.validationMessage {
                    Section {
                        Label(message, systemImage: "exclamationmark.circle")
                            .appFont(.footnote).foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("theme.editor.error")
                    }
                }
            }
            .environment(\.defaultMinListRowHeight, 48)
            .scrollContentBackground(.hidden)
            .background(Color(uiColor: .systemBackground).ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(isNew ? "新建主题" : "编辑主题")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { requestClose() }.accessibilityIdentifier("theme.editor.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }.disabled(!canSave)
                        .accessibilityIdentifier("theme.editor.save")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("收起键盘") { nameFocused = false }
                        .accessibilityIdentifier("theme.editor.keyboardDone")
                }
            }
            .navigationDestination(for: ThemeEditorDestination.self) { destination in
                ThemeCustomizationEditor(draft: $draft, previewScheme: $previewScheme,
                                         destination: destination, importImage: { imageTarget = $0 },
                                         importIcon: { iconImportTab = $0 })
            }
            .navigationDestination(for: LibraryTab.self) { tab in
                ThemeEditorTabIconPicker(tab: tab, icon: tabIconBinding(for: tab),
                                         importIcon: { iconImportTab = tab })
            }
        }
        .environment(\.appTheme, draft)
        .preferredColorScheme(previewScheme)
        .tint(Color.primary)
        .interactiveDismissDisabled(hasChanges || !newlyImportedIDs.isEmpty)
        .modifier(AppTypographyRoot())
        .sheet(item: $imageTarget, onDismiss: importPendingImage) { target in
            ThemeImagePicker(onPick: { url in
                pendingImage = (url, target); imageTarget = nil
            }, onCancel: { pendingImage = nil; imageTarget = nil })
                .ignoresSafeArea()
        }
        .sheet(item: $iconImportTab, onDismiss: importPendingIcon) { tab in
            ThemeImagePicker(onPick: { url in
                pendingIcon = (url, tab); iconImportTab = nil
            }, onCancel: { pendingIcon = nil; iconImportTab = nil })
                .ignoresSafeArea()
        }
        .alert("放弃更改？", isPresented: $showingDiscardConfirmation) {
            Button("继续编辑", role: .cancel) {}
            Button("放弃", role: .destructive) { closeWithoutSaving() }
                .accessibilityIdentifier("theme.editor.discard")
        } message: { Text("尚未保存的名称、界面、外观和导入图片会被丢弃。") }
        .alert("无法完成操作", isPresented: Binding(
            get: { errorMessage != nil && !isSaving },
            set: { if !$0 { errorMessage = nil } }
        )) { Button("好") { errorMessage = nil } } message: { Text(errorMessage ?? "") }
        // Do not clean up onDisappear: pushing a page or preview also disappears.
        // Imports are released only by the explicit save/cancel transaction.
    }

    private func row(_ destination: ThemeEditorDestination, value: String) -> some View {
        NavigationLink(value: destination) {
            HStack(spacing: 14) {
                Image(systemName: destination.symbol)
                    .font(.system(size: 20, weight: .regular))
                    .frame(width: 25).accessibilityHidden(true)
                ThemeEditorSummaryLabel(title: destination.title, value: value)
            }
        }
        .listRowInsets(EdgeInsets(top: 3, leading: 16, bottom: 3, trailing: 16))
        .listRowBackground(Color(uiColor: .systemBackground))
        .accessibilityIdentifier("theme.editor.row.\(destination.rawValue)")
    }
    private func imageSummary(_ id: String?, empty: String) -> String {
        guard let id else { return empty }
        return ThemeAssetStore.shared.image(for: id) == nil ? "图片不可用" : "自定义"
    }
    private var tabSummary: String {
        let count = LibraryTab.allCases.filter { settings.tabIcons?[$0.key] != nil }.count
        return count > 0 ? "\(settings.tabStyle.title) · \(count)个自定义" : settings.tabStyle.title
    }
    private var effectSummary: String {
        let glow = Int((min(max(settings.glowIntensity, 0), 1) * 100).rounded())
        let opacity = Int(((1 - min(max(settings.surfaceOpacity, 0), 1)) * 100).rounded())
        return "\(settings.effect.title) · 光晕\(glow)% · 透明\(opacity)%"
    }
    /// Tab icons share the same import transaction: the entry is created only
    /// after the store accepts the file, and cancel/save still own cleanup.
    private func tabIconBinding(for tab: LibraryTab) -> Binding<String?> {
        Binding<String?>(
            get: { (draft.customization ?? ThemeCustomization()).tabIcons?[tab.key] },
            set: { value in
                var theme = draft
                var settings = theme.customization ?? ThemeCustomization()
                var icons = settings.tabIcons ?? [:]
                if let value, ThemeAssetStore.isValidSymbolName(value) || ThemeAssetStore.isValidID(value) {
                    icons[tab.key] = value
                } else {
                    icons.removeValue(forKey: tab.key)
                }
                settings.tabIcons = icons.isEmpty ? nil : icons
                theme.customization = settings
                draft = theme
            })
    }
    private func importPendingIcon() {
        guard let pendingIcon else { return }
        self.pendingIcon = nil
        do {
            let id = try ThemeAssetStore.shared.importFile(pendingIcon.url)
            newlyImportedIDs.insert(id)
            tabIconBinding(for: pendingIcon.tab).wrappedValue = id
        } catch { errorMessage = error.localizedDescription }
    }
    private func importPendingImage() {
        guard let pendingImage else { return }
        self.pendingImage = nil
        do {
            let id = try ThemeAssetStore.shared.importFile(pendingImage.url)
            newlyImportedIDs.insert(id)
            $draft.themeSetting(pendingImage.kind.keyPath).wrappedValue = id
        } catch { errorMessage = error.localizedDescription }
    }
    private func requestClose() {
        nameFocused = false
        if hasChanges { showingDiscardConfirmation = true } else { closeWithoutSaving() }
    }
    private func closeWithoutSaving() {
        releaseUnusedImports()
        onCancel(); dismiss()
    }
    private func releaseUnusedImports() {
        guard !newlyImportedIDs.isEmpty else { return }
        // Other saved themes may reference an asset. Never remove preexisting IDs.
        store.reload()
        let retained = store.themes.reduce(into: Set<String>()) { $0.formUnion($1.assetIDs) }
        for id in newlyImportedIDs.subtracting(retained) { ThemeAssetStore.shared.remove(id) }
        newlyImportedIDs.removeAll()
    }
    private func save() {
        guard canSave else { return }
        nameFocused = false; isSaving = true; errorMessage = nil
        do {
            // Preserve whichever theme is currently selected, including an edited selection.
            try store.save(draft, apply: false)
            releaseUnusedImports(); isSaving = false
            onSaved(); dismiss()
        } catch { isSaving = false; errorMessage = error.localizedDescription }
    }
}

// Identifiable conformance lets the editor present an image picker per tab
// without touching the shared model file; `LibraryTab.key` (the tabIcons
// dictionary key) is owned by the model layer.
extension LibraryTab: Identifiable {
    var id: Int { rawValue }
}

enum ThemeEditorDestination: String, Hashable {
    case tab, shelf, cover, launch, colors, background, effect, cards
    var symbol: String {
        switch self {
        case .tab: return "rectangle.bottomthird.inset.filled"
        case .shelf: return "books.vertical"
        case .cover: return "book.closed"
        case .launch: return "sparkles.rectangle.stack"
        case .colors: return "paintpalette"
        case .background: return "photo"
        case .effect: return "square.3.layers.3d"
        case .cards: return "rectangle.on.rectangle"
        }
    }
    var title: String {
        switch self {
        case .tab: return "Tab栏"
        case .shelf: return "书架"
        case .cover: return "默认封面"
        case .launch: return "启动图"
        case .colors: return "颜色与字体"
        case .background: return "页面背景"
        case .effect: return "界面效果"
        case .cards: return "卡片背景"
        }
    }
}

extension Binding where Value == AppTheme {
    /// Reading legacy themes never materializes customization or dirties the draft.
    func themeSetting<T>(_ keyPath: WritableKeyPath<ThemeCustomization, T>) -> Binding<T> {
        Binding<T>(get: { (wrappedValue.customization ?? ThemeCustomization())[keyPath: keyPath] },
                   set: { value in
            var theme = wrappedValue
            var settings = theme.customization ?? ThemeCustomization()
            settings[keyPath: keyPath] = value
            theme.customization = settings
            wrappedValue = theme
        })
    }
}

struct ThemeEditorSummaryLabel: View {
    let title: String
    let value: String
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                Text(title).appFont(.body).fixedSize()
                Spacer(minLength: 8)
                Text(value).appFont(.subheadline).foregroundStyle(.secondary).fixedSize()
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(title).appFont(.body)
                Text(value).appFont(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Pushed in the editor's one NavigationStack, with no independent save buttons.
struct ThemeCustomizationEditor: View {
    @Binding var draft: AppTheme
    @Binding var previewScheme: ColorScheme
    let destination: ThemeEditorDestination
    let importImage: (ThemeEditorImageKind) -> Void
    let importIcon: (LibraryTab) -> Void
    private var settings: ThemeCustomization { draft.customization ?? ThemeCustomization() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if draft.customization == nil {
                    note(legacyNote)
                }
                page
            }
            .padding(18).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(destination.title)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("theme.editor.page.\(destination.rawValue)")
    }
    private var legacyNote: String {
        switch destination {
        case .tab:
            return "正在保留原有布局。下方显示方式展示自定义初始值，选择任一方式后可继续自定义标签图标；颜色与圆角可独立修改。"
        case .effect:
            return "正在保留原有布局。下方界面效果展示自定义初始值（光晕50% · 透明85%），首次更改后启用；颜色与圆角可独立修改。"
        default:
            return "正在保留原有布局。下方界面设置展示自定义初始值，首次更改后启用；颜色与圆角可独立修改。"
        }
    }
    @ViewBuilder private var page: some View {
        switch destination {
        case .tab: tabPage
        case .shelf: shelfPage
        case .cover: imagePage(.cover)
        case .launch: imagePage(.launch)
        case .colors:
            ThemePaletteEditor(draft: $draft, previewScheme: $previewScheme, page: .colors)
            ThemeEditorFontChoices(selection: $draft.themeSetting(\.fontPostScriptName))
            ThemeEditorLivePreview(theme: draft, scheme: previewScheme)
        case .background:
            imagePage(.background)
            ThemePaletteEditor(draft: $draft, previewScheme: $previewScheme, page: .background)
            ThemeEditorLivePreview(theme: draft, scheme: previewScheme)
        case .effect: effectPage
        case .cards:
            Toggle("显示卡片背景", isOn: $draft.themeSetting(\.cardBackground))
                .appFont(.body).accessibilityIdentifier("theme.editor.cards.enabled")
            note("关闭后，卡片内容直接显示在页面背景上；圆角和边框设置会保留。")
            ThemePaletteEditor(draft: $draft, previewScheme: $previewScheme, page: .cards)
            ThemeEditorLivePreview(theme: draft, scheme: previewScheme)
        }
    }
    private var tabPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            note("iOS 26 使用系统原生底栏，保留自定义图标；标签文字、布局和玻璃外观由系统管理。下方显示方式用于旧版 iOS 的自定义底栏。")
            VStack(spacing: 0) {
                choice(ThemeTabStyle.iconsAndText.title, selected: draft.customization?.tabStyle == .iconsAndText,
                       id: "theme.editor.tab.iconsAndText") { $draft.themeSetting(\.tabStyle).wrappedValue = .iconsAndText }
                Divider()
                choice(ThemeTabStyle.icons.title, selected: (draft.customization?.tabStyle ?? .icons) == .icons,
                       id: "theme.editor.tab.icons") { $draft.themeSetting(\.tabStyle).wrappedValue = .icons }
                Divider()
                choice(ThemeTabStyle.text.title, selected: draft.customization?.tabStyle == .text,
                       id: "theme.editor.tab.text") { $draft.themeSetting(\.tabStyle).wrappedValue = .text }
            }.padding(.horizontal, 16).themeEditorSurface()
            if draft.customization == nil {
                note("自定义每个标签的图标前，请先选择上方任一显示方式。")
            } else {
                tabIconSection
            }
            ThemeEditorLivePreview(theme: draft, scheme: previewScheme)
        }
    }
    private var tabIconSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("自定义标签图标").appFont(.headline)
            VStack(spacing: 0) {
                ForEach(LibraryTab.allCases, id: \.rawValue) { tab in
                    if tab != LibraryTab.allCases.first { Divider() }
                    tabIconRow(tab)
                }
            }.padding(.horizontal, 16).themeEditorSurface()
            note("每个标签可使用内置图标或导入的自定义图片；图片不超过 20 MB，导入时压缩至最长边 2000 像素。恢复默认后使用应用原有图标。")
        }
    }
    private func tabIconRow(_ tab: LibraryTab) -> some View {
        NavigationLink(value: tab) {
            HStack(spacing: 12) {
                Text(tab.title).appFont(.body)
                Spacer(minLength: 8)
                Text(settings.tabIcons?[tab.key] == nil ? "默认" : "自定义")
                    .appFont(.caption).foregroundStyle(.secondary)
                ThemeEditorTabIcon(value: settings.tabIcons?[tab.key], fallback: tab.symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.primary)
                    .frame(width: 28, height: 28)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 52).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(tab.title)图标")
        .accessibilityValue(settings.tabIcons?[tab.key] == nil ? "默认" : "自定义")
        .accessibilityIdentifier("theme.editor.tab.icon.\(tab.key)")
    }
    private var shelfPage: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 18) {
                Stepper(value: $draft.themeSetting(\.shelfColumns), in: 2...5) {
                    Text("每行 \(settings.shelfColumns) 列").appFont(.body)
                }.accessibilityIdentifier("theme.editor.shelf.columns")
                Divider()
                Text("封面宽度 · \(Int(settings.coverWidth.rounded())) pt").appFont(.body)
                Slider(value: $draft.themeSetting(\.coverWidth), in: 60...180, step: 1)
                    .accessibilityLabel("封面宽度")
                    .accessibilityValue("\(Int(settings.coverWidth.rounded())) 点")
                    .accessibilityIdentifier("theme.editor.shelf.width")
                HStack { Text("60 pt"); Spacer(); Text("180 pt") }
                    .appFont(.caption).foregroundStyle(.secondary)
            }.padding(16).themeEditorSurface()
            note("书架支持 2–5 列，封面宽度为 60–180 pt。这是期望值；实际宽度不会超过当前列空间。窄窗会自动减少列数以尽量保留至少 60pt 列宽；辅助大字号最多显示 2 列。仅影响网格书架，列表布局保持原样。")
            ThemeEditorShelfSizing(columns: settings.shelfColumns, requestedWidth: settings.coverWidth)
        }
    }
    private var effectPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(spacing: 0) {
                choice(ThemeInterfaceEffect.transparent.title, selected: settings.effect == .transparent,
                       id: "theme.editor.effect.transparent") { $draft.themeSetting(\.effect).wrappedValue = .transparent }
                Divider()
                choice(ThemeInterfaceEffect.frosted.title, selected: settings.effect == .frosted,
                       id: "theme.editor.effect.frosted") { $draft.themeSetting(\.effect).wrappedValue = .frosted }
                Divider()
                choice(ThemeInterfaceEffect.opaque.title, selected: settings.effect == .opaque,
                       id: "theme.editor.effect.opaque") { $draft.themeSetting(\.effect).wrappedValue = .opaque }
            }.padding(.horizontal, 16).themeEditorSurface()
            note("此选项控制内容卡片：透明保留背景，玻璃柔化背景，不透明使用卡片底色。按钮、搜索框和浮动菜单统一使用玻璃；iOS 26 使用原生 Liquid Glass。开启系统降低透明度时使用实色。")
            effectSliderSection
            note("光晕用于透明和毛玻璃效果；透明度越高，毛玻璃底色越淡。系统材质会自适应明暗，滑条调节叠加底色，不会移除模糊；系统开启降低透明度时改用实色。不透明效果不使用这两个数值；取消编辑不会应用。")
            ThemeEditorLivePreview(theme: draft, scheme: previewScheme)
        }
    }
    private var effectSliderSection: some View {
        let glow = Int((min(max(settings.glowIntensity, 0), 1) * 100).rounded())
        let opacity = Int(((1 - min(max(settings.surfaceOpacity, 0), 1)) * 100).rounded())
        return VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("光晕强度 · \(glow)%").appFont(.body)
                Slider(value: $draft.themeSetting(\.glowIntensity), in: 0...1, step: 0.01)
                    .accessibilityLabel("光晕强度")
                    .accessibilityValue("\(glow)%")
                    .accessibilityIdentifier("theme.editor.effect.glow")
                HStack { Text("0%"); Spacer(); Text("100%") }
                    .appFont(.caption2).foregroundStyle(.secondary)
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("透明度 · \(opacity)%").appFont(.body)
                Slider(value: Binding(get: { 1 - settings.surfaceOpacity }, set: {
                    $draft.themeSetting(\.surfaceOpacity).wrappedValue = 1 - $0
                }), in: 0...1, step: 0.01)
                    .accessibilityLabel("透明度")
                    .accessibilityValue("\(opacity)%")
                    .accessibilityIdentifier("theme.editor.effect.opacity")
                HStack { Text("0%"); Spacer(); Text("100%") }
                    .appFont(.caption2).foregroundStyle(.secondary)
            }
        }.padding(16).themeEditorSurface()
    }
    private func imagePage(_ kind: ThemeEditorImageKind) -> some View {
        ThemeEditorImageSettings(kind: kind, assetID: $draft.themeSetting(kind.keyPath),
                                 importImage: { importImage(kind) })
    }
    private func choice(_ title: String, selected: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Text(title).appFont(.body).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if selected { Image(systemName: "checkmark").accessibilityHidden(true) }
            }.frame(minHeight: 52).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier(id)
    }
    private func note(_ text: String) -> some View {
        Text(text).appFont(.footnote).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Icon choice for one tab, pushed inside the editor's NavigationStack.
/// The parent binding applies immediately so back reveals the updated row.
struct ThemeEditorTabIconPicker: View {
    static let symbols = [
        "book.fill", "chart.bar.fill", "person.fill", "house.fill",
        "magnifyingglass", "star.fill", "heart.fill", "bookmark.fill",
        "folder.fill", "gearshape.fill", "books.vertical.fill", "clock.fill"
    ]

    let tab: LibraryTab
    @Binding var icon: String?
    let importIcon: () -> Void
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 62, maximum: 88), spacing: 8)]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                note("为“\(tab.title)”选择内置图标，或导入图片作为自定义图标。更改即时预览，仅随主题保存后生效。")
                VStack(alignment: .leading, spacing: 14) {
                    Text("内置图标").appFont(.headline)
                    LazyVGrid(columns: columns, spacing: 8) {
                        ForEach(Self.symbols, id: \.self) { name in
                            symbolButton(name)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    Button(action: importIcon) {
                        Label("从文件选择图片", systemImage: "folder")
                            .appFont(.body).frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("theme.editor.tab.icon.import")
                    Text("图片导入后保存为主题素材，不超过 20 MB，最长边压缩至 2000 像素。")
                        .appFont(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Button(role: .destructive) { icon = nil } label: {
                        Label("恢复默认", systemImage: "arrow.counterclockwise")
                            .appFont(.body).frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .disabled(icon == nil)
                    .accessibilityIdentifier("theme.editor.tab.icon.reset")
                    Text("恢复应用原有的“\(tab.title)”图标。")
                        .appFont(.footnote).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(18).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("\(tab.title)图标")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("theme.editor.tab.icon.page")
    }

    private func symbolButton(_ name: String) -> some View {
        let selected = icon == name
        return Button { icon = selected ? nil : name } label: {
            ThemeEditorTabIcon(value: name, fallback: tab.symbol)
                .font(.system(size: 22, weight: .regular))
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(selected ? Color.primary.opacity(0.12) : Color.primary.opacity(0.035),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(selected ? Color.primary : Color.clear, lineWidth: 1.2)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("图标 \(name)")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("theme.editor.tab.icon.grid.\(name)")
    }

    private func note(_ text: String) -> some View {
        Text(text).appFont(.footnote).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Resolves one stored icon value the way LibraryDock does: asset identifiers
/// load through the same async loader; other values are SF Symbol names.
struct ThemeEditorTabIcon: View {
    let value: String?
    let fallback: String
    @StateObject private var imageLoader = ThemeAssetImageLoader()

    private var assetID: String? {
        guard let value, ThemeAssetStore.isValidID(value) else { return nil }
        return value
    }
    private var symbolName: String? {
        guard let value, !ThemeAssetStore.isValidID(value),
              ThemeAssetStore.shared.symbolImage(for: value) != nil else { return nil }
        return value
    }

    var body: some View {
        Group {
            if let symbolName {
                Image(systemName: symbolName)
            } else if let image = imageLoader.image, imageLoader.assetID == assetID {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: fallback)
            }
        }
        .task(id: value) {
            await imageLoader.load(assetID)
        }
    }
}

extension View {
    func themeEditorSurface() -> some View {
        appGlass(in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
