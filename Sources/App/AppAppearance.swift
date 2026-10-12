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

    @ThemePalette private var palette
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

    private var pageSelection: Binding<String> {
        Binding(
            get: { browsedTheme?.id ?? "" },
            set: { newValue in
                guard store.themes.contains(where: { $0.id == newValue }) else { return }
                browsedID = newValue
            }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                themeGallerySection
                modeSection
                if let notice {
                    Text(notice)
                        .appFont(.footnote)
                        .foregroundStyle(palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .foregroundStyle(palette.primary)
        .background { AppThemeCanvas().ignoresSafeArea() }
        .navigationTitle("外观主题")
        .toolbar(.visible, for: .navigationBar)
        .modifier(MonochromeAppStyle())
        .modifier(AppTypographyRoot())
        // This page can also be hosted by the isolated interaction harness.
        // Keep its controls and surfaces in sync with the store without making
        // a browsed, not-yet-applied card the app-wide theme.
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
                onCancel: { showingTemplateGallery = false },
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
                    notice = "主题已保存"
                }
            )
        }
        .alert("删除主题？", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        ), presenting: pendingDelete) { theme in
            Button("取消", role: .cancel) { pendingDelete = nil }
            Button("删除", role: .destructive) {
                delete(theme)
                pendingDelete = nil
            }
            .accessibilityIdentifier("theme.delete.confirm")
        } message: { theme in
            Text("“\(theme.name)”将从本机移除。")
        }
    }

    @ViewBuilder
    private var themeGallerySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("主题画廊")
                        .appFont(.title3.weight(.semibold))
                    Text("像挑选墙纸一样预览你的阅读界面")
                        .appFont(.footnote)
                        .foregroundStyle(palette.secondary)
                }
                Spacer(minLength: 12)
                Button {
                    showingTemplateGallery = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .background(palette.surface, in: Circle())
                        .overlay(Circle().stroke(palette.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("添加主题")
                .accessibilityIdentifier("theme.add")
            }

            if store.themes.isEmpty {
                emptyGallery
            } else {
                TabView(selection: pageSelection) {
                    ForEach(store.themes) { theme in
                        ThemePreviewCard(
                            theme: theme,
                            scheme: previewScheme,
                            isSelected: theme.id == store.selectedID,
                            nameAccessibilityIdentifier: theme.id == browsedTheme?.id ? "theme.gallery.name" : nil
                        )
                        .padding(.horizontal, 14)
                        .tag(theme.id)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 448)
                .tabViewStyle(.page(indexDisplayMode: .never))

                pageDots
                browsedThemeActions
            }

            HStack(spacing: 12) {
                Button {
                    customizeBrowsedTheme()
                } label: {
                    Label("自定", systemImage: "slider.horizontal.3")
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("theme.customize")
                .disabled(browsedTheme == nil)

                Button {
                    showingTemplateGallery = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 48, height: 48)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("添加新主题")
                .accessibilityIdentifier("theme.add.bottom")
            }
        }
    }

    private var emptyGallery: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(palette.secondary)
            Text("还没有可用主题")
                .appFont(.headline)
            Text("从模板开始，创建一套属于你的阅读界面。")
                .appFont(.footnote)
                .foregroundStyle(palette.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 42)
        .background(palette.surface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(palette.border, lineWidth: 1))
    }

    private var pageDots: some View {
        HStack(spacing: 4) {
            ForEach(store.themes) { theme in
                Capsule(style: .continuous)
                    .fill(theme.id == browsedTheme?.id ? palette.accent : palette.border)
                    .frame(width: theme.id == browsedTheme?.id ? 16 : 4, height: 5)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: browsedTheme?.id)
                    .accessibilityHidden(true)
            }
        }
            .padding(.horizontal, 12)
            .frame(height: 18)
            .frame(maxWidth: .infinity)
            .padding(.top, -6)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var browsedThemeActions: some View {
        if let theme = browsedTheme {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(theme.name)
                            .appFont(.headline)
                        if theme.id == store.selectedID {
                            Text("当前使用")
                                .appFont(.caption)
                                .foregroundStyle(palette.secondary)
                        } else {
                            Text("点击使用主题后应用")
                                .appFont(.caption)
                                .foregroundStyle(palette.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button("使用主题") {
                        apply(theme)
                    }
                    .appFont(.subheadline.weight(.semibold))
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("theme.use")
                }

                HStack(spacing: 14) {
                    Text("已保存主题")
                        .appFont(.caption)
                        .foregroundStyle(palette.secondary)
                    Text(store.selectedTheme.name)
                        .appFont(.caption.weight(.medium))
                        .lineLimit(1)
                        .accessibilityIdentifier("theme.gallery.selected")
                    Spacer(minLength: 0)
                    if !theme.isBuiltIn {
                        Button("删除", role: .destructive) {
                            pendingDelete = theme
                        }
                        .appFont(.caption.weight(.semibold))
                        .accessibilityIdentifier("theme.delete")
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("应用外观")
                .appFont(.headline)
            HStack(spacing: 8) {
                ForEach(AppAppearance.allCases) { mode in
                    Button {
                        rawAppearance = mode.rawValue
                    } label: {
                        VStack(spacing: 7) {
                            Image(systemName: mode.symbol)
                                .font(.system(size: 18, weight: .medium))
                            Text(mode.title)
                                .appFont(.caption.weight(.medium))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        .frame(maxWidth: .infinity, minHeight: 66)
                        .background(
                            mode == appearance ? palette.selection : palette.surface,
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(mode == appearance ? palette.accent : palette.border, lineWidth: mode == appearance ? 1.5 : 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("appearance.theme.\(mode.rawValue)")
                    .accessibilityAddTraits(mode == appearance ? .isSelected : [])
                }
            }
            HStack(spacing: 8) {
                Image(systemName: appearance.symbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(palette.accent)
                Text("当前：")
                    .appFont(.footnote)
                    .foregroundStyle(palette.secondary)
                Text(appearance.title)
                    .appFont(.footnote.weight(.semibold))
                    .accessibilityIdentifier("appearance.current.value")
                Spacer()
            }
            .padding(.horizontal, 4)
        }
    }

    private var previewScheme: ColorScheme {
        switch appearance {
        case .dark: return .dark
        case .system: return colorScheme
        case .light: return .light
        }
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
        editorTheme = theme.isBuiltIn ? theme.draft() : theme
    }

    private func apply(_ theme: AppTheme) {
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
