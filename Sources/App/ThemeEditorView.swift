import SwiftUI
import UIKit

/// The editor owns a value draft. Switching sections or preview mode never
/// mutates the repository, root appearance, reader paper or typography.
struct ThemeEditorView: View {
    let initialTheme: AppTheme
    let onCancel: () -> Void
    let onSaved: () -> Void
    @ObservedObject private var store: AppThemeStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: AppTheme
    @State private var previewScheme: ColorScheme = .light
    @State private var section: ThemeEditorSection = .colors
    @State private var hexField: ThemeColorField?
    @State private var showingDiscardConfirmation = false
    @State private var errorMessage: String?
    @State private var isSaving = false
    @FocusState private var nameFocused: Bool

    init(theme: AppTheme, store: AppThemeStore = .shared,
         onCancel: @escaping () -> Void = {}, onSaved: @escaping () -> Void = {}) {
        initialTheme = theme; self.onCancel = onCancel; self.onSaved = onSaved
        _store = ObservedObject(wrappedValue: store)
        _draft = State(initialValue: theme)
    }
    private var colors: AppThemeSwatches { draft.swatches(for: previewScheme) }
    private var resolved: ResolvedAppPalette { ResolvedAppPalette(theme: draft, scheme: previewScheme) }
    private var hasChanges: Bool { draft != initialTheme }
    private var canSave: Bool { !draft.isBuiltIn && draft.validationMessage == nil && !isSaving }
    private var canvas: Color { Color(uiColor: .systemGroupedBackground) }
    private var surface: Color { Color(uiColor: .secondarySystemGroupedBackground) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                schemePicker.padding(.horizontal, 18).padding(.vertical, 10)
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        previewSection
                        nameSection
                        if let message = errorMessage ?? draft.validationMessage {
                            Label(message, systemImage: "exclamationmark.circle")
                                .appFont(.footnote).foregroundStyle(.red)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("theme.editor.error")
                        }
                        sectionContent
                    }
                    .padding(.horizontal, 18).padding(.top, 4).padding(.bottom, 22)
                }
                .id(section)
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
            .background(canvas.ignoresSafeArea())
            .safeAreaInset(edge: .bottom, spacing: 0) { sectionBar }
            .navigationTitle("编辑主题")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { requestClose() }.accessibilityIdentifier("theme.editor.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("存储") { save() }.appFont(.headline).disabled(!canSave)
                        .accessibilityIdentifier("theme.editor.save")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("收起键盘") { nameFocused = false }
                        .accessibilityIdentifier("theme.editor.keyboardDone")
                }
            }
            .sheet(item: $hexField) { field in
                ThemeHexEditor(field: field, hex: hex(for: field)) { update(field, hex: $0) }
                    .presentationDetents([.medium, .large])
            }
            .alert("放弃更改？", isPresented: $showingDiscardConfirmation) {
                Button("继续编辑", role: .cancel) {}
                Button("放弃", role: .destructive) { closeWithoutSaving() }
                    .accessibilityIdentifier("theme.editor.discard")
            } message: { Text("尚未保存的名称、颜色和样式会被丢弃。") }
        }
        .preferredColorScheme(previewScheme)
        .tint(Color.primary)
        .interactiveDismissDisabled(hasChanges)
        .modifier(AppTypographyRoot())
    }

    private var schemePicker: some View {
        HStack(spacing: 4) {
            ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
                Button {
                    nameFocused = false; previewScheme = scheme
                } label: {
                    Label(scheme == .light ? "浅色主题" : "深色主题",
                          systemImage: scheme == .light ? "sun.max" : "moon")
                        .appFont(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(previewScheme == scheme ? surface : .clear,
                                    in: RoundedRectangle(cornerRadius: 11))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(scheme == .light ? "theme.editor.mode.light" : "theme.editor.mode.dark")
                .accessibilityAddTraits(previewScheme == scheme ? .isSelected : [])
            }
        }
        .padding(4).background(Color.primary.opacity(0.065), in: RoundedRectangle(cornerRadius: 15))
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("实时预览").appFont(.caption.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                Text(draft.id == store.selectedID ? "存储后更新当前主题" : "存储后可应用").appFont(.caption2).foregroundStyle(.secondary)
            }
            ThemePreviewCard(theme: draft, scheme: previewScheme, isSelected: false)
                .frame(minHeight: 150)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("主题实时预览")
                .accessibilityValue("\(draft.name)，\(previewScheme == .light ? "浅色" : "深色")，\(colors.accent)")
                .accessibilityIdentifier("theme.editor.preview")
        }
    }

    private var nameSection: some View {
        HStack(spacing: 10) {
            Image(systemName: "pencil.line").foregroundStyle(.secondary)
            TextField("主题名称", text: $draft.name)
                .appFont(.headline).textInputAutocapitalization(.never).autocorrectionDisabled()
                .focused($nameFocused).submitLabel(.done).onSubmit { nameFocused = false }
                .accessibilityLabel("主题名称").accessibilityIdentifier("theme.editor.name")
        }
        .padding(.horizontal, 16).frame(minHeight: 58)
        .background(surface, in: RoundedRectangle(cornerRadius: 18))
    }

    private var sectionBar: some View {
        HStack(spacing: 6) {
            ForEach(ThemeEditorSection.allCases) { item in
                Button {
                    nameFocused = false; section = item
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: item.symbol).font(.system(size: 17, weight: .medium))
                        Text(item.title).appFont(.caption.weight(.medium))
                    }
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .foregroundStyle(section == item ? Color(uiColor: .systemBackground) : Color.secondary)
                    .background(section == item ? Color.primary : Color.primary.opacity(0.045),
                                in: RoundedRectangle(cornerRadius: 13))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("theme.editor.section.\(item.rawValue)")
                .accessibilityAddTraits(section == item ? .isSelected : [])
            }
        }
        .padding(.horizontal, 18).padding(.top, 10).padding(.bottom, 8)
        .background(.regularMaterial)
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch section {
        case .colors: colorsSection
        case .background: backgroundSection
        case .cards: cardsSection
        case .components: componentsSection
        }
    }

    private var colorFields: [ThemeColorField] {
        var fields: [ThemeColorField] = [.accent, .background]
        if draft.backgroundStyle == .gradient { fields.append(.backgroundEnd) }
        fields += [.surface, .primaryText, .secondaryText, .border, .selection]
        return fields
    }

    private func colorRow(_ field: ThemeColorField) -> some View {
        ThemeEditorColorRow(field: field, hex: hex(for: field),
                            color: colorBinding(for: field), editHex: { hexField = field })
    }

    private var colorsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("颜色", detail: "浅色与深色分别设置")
                .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 8)
            ThemeAccentSwatches(scheme: previewScheme, selectedHex: colors.accent) {
                update(.accent, hex: $0)
            }
            .padding(.horizontal, 8).padding(.bottom, 8)
            Divider().padding(.horizontal, 16)
            ForEach(colorFields, id: \.rawValue) { field in
                colorRow(field)
                if field.rawValue != colorFields.last?.rawValue {
                    Divider().padding(.leading, 16)
                }
            }
        }
        .background(surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var backgroundSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("页面背景", detail: "应用页面和分组区域使用的底色")
            HStack(spacing: 8) {
                ForEach(AppThemeBackgroundStyle.allCases) { style in
                    Button {
                        draft.backgroundStyle = style
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: style == .solid ? "square.fill" : "circle.lefthalf.filled")
                                .font(.system(size: 18, weight: .medium))
                            Text(style.title).appFont(.subheadline.weight(.medium))
                        }
                        .frame(maxWidth: .infinity, minHeight: 78)
                        .foregroundStyle(draft.backgroundStyle == style ? Color.primary : Color.secondary)
                        .background(draft.backgroundStyle == style ? Color.primary.opacity(0.10) : Color.primary.opacity(0.035),
                                    in: RoundedRectangle(cornerRadius: 15))
                        .overlay(RoundedRectangle(cornerRadius: 15)
                            .stroke(draft.backgroundStyle == style ? Color.primary : Color.primary.opacity(0.10),
                                    lineWidth: draft.backgroundStyle == style ? 1.2 : 0.7))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(style == .solid ? "theme.editor.style.solid" : "theme.editor.style.gradient")
                    .accessibilityAddTraits(draft.backgroundStyle == style ? .isSelected : [])
                }
            }
            colorRow(.background).padding(.horizontal, -16)
            if draft.backgroundStyle == .gradient {
                Divider()
                colorRow(.backgroundEnd).padding(.horizontal, -16)
            }
            Text("纯色或渐变样式由浅深主题共用，两套颜色分别保存。")
                .appFont(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var cardsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("卡片", detail: "书架与详情中应用自有卡片的样式")
            colorRow(.surface).padding(.horizontal, -16)
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("卡片圆角").appFont(.subheadline.weight(.semibold))
                        Text(colors.cardRadius.map { "当前 \(Int($0.rounded())) pt" } ?? "跟随界面默认")
                            .appFont(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("8").appFont(.caption2).foregroundStyle(.secondary)
                    Slider(value: cardRadiusBinding, in: 8...30, step: 1)
                        .frame(maxWidth: 160)
                        .accessibilityIdentifier("theme.editor.cardRadius")
                    Text("30").appFont(.caption2).foregroundStyle(.secondary)
                }
                Toggle(isOn: cardBorderBinding) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("显示卡片边框").appFont(.subheadline.weight(.semibold))
                        Text("让浅色背景上的分组边界更清楚")
                            .appFont(.caption).foregroundStyle(.secondary)
                    }
                }
                .tint(resolved.accent)
                .accessibilityIdentifier("theme.editor.cardBorder")
            }
            Divider()
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: CGFloat(colors.cardRadius ?? 20), style: .continuous)
                    .fill(resolved.surface)
                    .frame(height: 78)
                    .overlay {
                        if colors.cardBorder ?? true {
                            RoundedRectangle(cornerRadius: CGFloat(colors.cardRadius ?? 20), style: .continuous)
                                .stroke(resolved.border, lineWidth: 1)
                        }
                    }
                    .overlay {
                        HStack(spacing: 9) {
                            Circle().fill(resolved.accent).frame(width: 12, height: 12)
                            VStack(alignment: .leading, spacing: 5) {
                                Text("卡片示例").appFont(.subheadline.weight(.semibold)).foregroundStyle(resolved.primary)
                                Text("边框与圆角即时预览").appFont(.caption).foregroundStyle(resolved.secondary)
                            }
                            Spacer()
                        }.padding(.horizontal, 16)
                    }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("卡片样式预览")
        }
        .padding(16)
        .background(surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var componentsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("控件", detail: "按钮、选中状态和辅助文字在应用中的实际表现")
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Text("主要按钮").appFont(.subheadline.weight(.semibold))
                        .foregroundStyle(resolved.onAccent)
                        .padding(.horizontal, 16).frame(minHeight: 42)
                        .background(resolved.accent, in: Capsule())
                    Text("当前选中").appFont(.subheadline.weight(.medium))
                        .padding(.horizontal, 16).frame(minHeight: 42)
                        .foregroundStyle(resolved.primary)
                        .background(resolved.selection, in: Capsule())
                        .overlay(Capsule().stroke(resolved.border, lineWidth: 1))
                }
                Divider()
                HStack(spacing: 10) {
                    Circle().fill(resolved.accent).frame(width: 10, height: 10)
                    Text("主要文字").appFont(.subheadline.weight(.semibold)).foregroundStyle(resolved.primary)
                    Text("辅助文字").appFont(.subheadline).foregroundStyle(resolved.secondary)
                    Spacer(minLength: 0)
                }
            }
            .padding(16)
            .background(resolved.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(resolved.border, lineWidth: 1))
            colorRow(.selection).padding(.horizontal, -16)
            Divider()
            colorRow(.border).padding(.horizontal, -16)
            Text("这些颜色用于应用自有的选中状态与边框；系统菜单、键盘和阅读纸张仍保留各自样式。")
                .appFont(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var cardRadiusBinding: Binding<Double> {
        Binding(get: { colors.cardRadius ?? 20 }, set: { value in
            let radius = min(max(value, 8), 30)
            if previewScheme == .light { draft.light.cardRadius = radius }
            else { draft.dark.cardRadius = radius }
        })
    }
    private var cardBorderBinding: Binding<Bool> {
        Binding(get: { colors.cardBorder ?? true }, set: { value in
            if previewScheme == .light { draft.light.cardBorder = value }
            else { draft.dark.cardBorder = value }
        })
    }

    private func sectionHeader(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).appFont(.headline)
            Text(detail).appFont(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func fallbackHex(for field: ThemeColorField) -> String {
        let value: Color
        switch field {
        case .accent: value = resolved.accent
        case .background: value = resolved.background
        case .backgroundEnd: value = resolved.backgroundEnd
        case .surface: value = resolved.surface
        case .primaryText: value = resolved.primary
        case .secondaryText: value = resolved.secondary
        case .border: value = resolved.border
        case .selection: value = resolved.selection
        }
        return AppThemeColor.hex(value, scheme: previewScheme)
    }

    private func hex(for field: ThemeColorField) -> String {
        switch field {
        case .accent: return colors.accent
        case .background: return colors.background
        case .backgroundEnd: return colors.backgroundEnd
        case .surface: return colors.surface
        case .primaryText: return colors.primaryText ?? fallbackHex(for: field)
        case .secondaryText: return colors.secondaryText ?? fallbackHex(for: field)
        case .border: return colors.border ?? fallbackHex(for: field)
        case .selection: return colors.selection ?? fallbackHex(for: field)
        }
    }

    private func colorBinding(for field: ThemeColorField) -> Binding<Color> {
        Binding(get: { AppThemeColor.color(hex(for: field)) },
                set: { update(field, hex: AppThemeColor.hex($0, scheme: previewScheme)) })
    }

    private func update(_ field: ThemeColorField, hex: String) {
        guard AppThemeColor.isValid(hex) else { return }
        if previewScheme == .light {
            switch field {
            case .accent: draft.light.accent = hex
            case .background: draft.light.background = hex
            case .backgroundEnd: draft.light.backgroundEnd = hex
            case .surface: draft.light.surface = hex
            case .primaryText: draft.light.primaryText = hex
            case .secondaryText: draft.light.secondaryText = hex
            case .border: draft.light.border = hex
            case .selection: draft.light.selection = hex
            }
        } else {
            switch field {
            case .accent: draft.dark.accent = hex
            case .background: draft.dark.background = hex
            case .backgroundEnd: draft.dark.backgroundEnd = hex
            case .surface: draft.dark.surface = hex
            case .primaryText: draft.dark.primaryText = hex
            case .secondaryText: draft.dark.secondaryText = hex
            case .border: draft.dark.border = hex
            case .selection: draft.dark.selection = hex
            }
        }
    }

    private func requestClose() {
        if hasChanges { showingDiscardConfirmation = true } else { closeWithoutSaving() }
    }
    private func closeWithoutSaving() { onCancel(); dismiss() }

    private func save() {
        guard canSave else { return }
        isSaving = true; errorMessage = nil
        do {
            try store.save(draft, apply: draft.id == store.selectedID)
            isSaving = false; onSaved(); dismiss()
        } catch {
            isSaving = false; errorMessage = error.localizedDescription
        }
    }
}
