import SwiftUI
import UIKit

/// Edits an in-memory AppTheme draft. Nothing reaches AppThemeStore until the
/// explicit save action succeeds.
struct ThemeEditorView: View {
    let initialTheme: AppTheme
    let onCancel: () -> Void
    let onSaved: () -> Void

    @ObservedObject private var store: AppThemeStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: AppTheme
    @State private var previewScheme: ColorScheme = .light
    @State private var showingDiscardConfirmation = false
    @State private var errorMessage: String?
    @State private var isSaving = false
    @FocusState private var nameFocused: Bool
    @ThemePalette private var palette

    init(
        theme: AppTheme,
        store: AppThemeStore = .shared,
        onCancel: @escaping () -> Void = {},
        onSaved: @escaping () -> Void = {}
    ) {
        self.initialTheme = theme
        self.onCancel = onCancel
        self.onSaved = onSaved
        _store = ObservedObject(wrappedValue: store)
        _draft = State(initialValue: theme)
    }

    private var colors: AppThemeSwatches {
        draft.swatches(for: previewScheme)
    }

    private var validationMessage: String? {
        draft.validationMessage
    }

    private var hasChanges: Bool { draft != initialTheme }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    previewSection
                    nameSection
                    styleSection
                    colorSection
                    if let message = errorMessage ?? validationMessage {
                        Text(message)
                            .appFont(.footnote)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 4)
                            .accessibilityIdentifier("theme.editor.error")
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 34)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(editorBackground.ignoresSafeArea())
            .navigationTitle("编辑主题")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { requestClose() }
                        .accessibilityIdentifier("theme.editor.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("存储") { save() }
                        .appFont(.headline)
                        .disabled(!canSave || isSaving)
                        .accessibilityIdentifier("theme.editor.save")
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("收起键盘") { nameFocused = false }
                        .accessibilityIdentifier("theme.editor.keyboardDone")
                }
            }
            .alert("放弃更改？", isPresented: $showingDiscardConfirmation) {
                Button("继续编辑", role: .cancel) {}
                Button("放弃", role: .destructive) { closeWithoutSaving() }
                    .accessibilityIdentifier("theme.editor.discard")
            } message: {
                Text("尚未保存的颜色和名称会被丢弃。")
            }
        }
        .modifier(AppTypographyRoot())
    }

    private var canSave: Bool {
        !draft.isBuiltIn && validationMessage == nil && !isSaving
    }

    private var editorBackground: Color {
        Color(uiColor: .systemGroupedBackground)
    }

    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("预览示例")
                        .appFont(.headline)
                    Text("只预览当前编辑中的配色")
                        .appFont(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                schemePicker
            }

            ThemePreviewCard(theme: draft, scheme: previewScheme, isSelected: false)
                .frame(maxWidth: .infinity)
                .frame(height: 386)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("主题实时预览")
                .accessibilityValue("\(draft.name)，\(previewScheme == .light ? "浅色" : "深色")，\(colors.accent)")
                .accessibilityIdentifier("theme.editor.preview")
        }
    }

    private var schemePicker: some View {
        HStack(spacing: 3) {
            ForEach([ColorScheme.light, ColorScheme.dark], id: \.self) { scheme in
                Button {
                    nameFocused = false
                    previewScheme = scheme
                } label: {
                    Image(systemName: scheme == .light ? "sun.max.fill" : "moon.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 44, height: 44)
                        .background(previewScheme == scheme ? Color.primary.opacity(0.13) : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(scheme == .light ? "浅色预览" : "深色预览")
                .accessibilityIdentifier(scheme == .light ? "theme.editor.mode.light" : "theme.editor.mode.dark")
                .accessibilityAddTraits(previewScheme == scheme ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Color.primary.opacity(0.06), in: Capsule())
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("主题名称")
                .appFont(.headline)
            TextField("例如：我的夜读", text: $draft.name)
                .appFont(.body)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .focused($nameFocused)
                .submitLabel(.done)
                .onSubmit { nameFocused = false }
                .padding(.horizontal, 14)
                .frame(minHeight: 52)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.primary.opacity(0.12), lineWidth: 1))
                .accessibilityIdentifier("theme.editor.name")
        }
    }

    private var styleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("背景样式")
                .appFont(.headline)
            HStack(spacing: 10) {
                ForEach(AppThemeBackgroundStyle.allCases) { style in
                    Button {
                        draft.backgroundStyle = style
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: style == .solid ? "square.fill" : "circle.lefthalf.filled")
                            Text(style.title)
                                .appFont(.subheadline.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(draft.backgroundStyle == style ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(draft.backgroundStyle == style ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(style == .solid ? "theme.editor.style.solid" : "theme.editor.style.gradient")
                    .accessibilityAddTraits(draft.backgroundStyle == style ? .isSelected : [])
                }
            }
        }
    }

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("配色")
                    .appFont(.headline)
                Spacer()
                Text(previewScheme == .light ? "浅色" : "深色")
                    .appFont(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                colorPickerRow(title: "背景", symbol: "rectangle.fill", index: 0)
                Divider()
                colorPickerRow(title: "背景末端", symbol: "rectangle.righthalf.inset.filled", index: 1)
                Divider()
                colorPickerRow(title: "卡片", symbol: "rectangle.roundedtop.fill", index: 2)
                Divider()
                colorPickerRow(title: "强调色", symbol: "paintpalette.fill", index: 3)
            }
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.primary.opacity(0.12), lineWidth: 1))

            Text("快速强调色")
                .appFont(.subheadline.weight(.semibold))
                .padding(.top, 4)
            quickSwatches
        }
    }

    private func colorPickerRow(title: String, symbol: String, index: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 24)
                .foregroundStyle(.secondary)
            Text(title)
                .appFont(.body)
            Spacer(minLength: 8)
            Text(colorHex(at: index))
                .appFont(.caption2)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            ColorPicker("", selection: colorBinding(at: index), supportsOpacity: false)
                .labelsHidden()
                .frame(width: 48, height: 48)
                .accessibilityLabel(title)
                .accessibilityIdentifier("theme.editor.color.\(index)")
        }
        .padding(.leading, 14)
        .padding(.trailing, 5)
        .frame(minHeight: 58)
    }

    private var quickSwatches: some View {
        let swatches = previewScheme == .light
            ? ["1F4E79", "6B3D57", "356859", "8A4B2A", "5A4A8B", "7A3E22"]
            : ["B9D9F2", "F0BDD7", "BFE7CC", "F2C89E", "D0C2F5", "F0C1AC"]
        return HStack(spacing: 3) {
            ForEach(Array(swatches.enumerated()), id: \.offset) { item in
                Button {
                    updateSwatch(index: 3, hex: item.element)
                } label: {
                    Circle()
                        .fill(AppThemeColor.color(item.element))
                        .frame(width: 36, height: 36)
                        .overlay(Circle().stroke(Color.primary.opacity(colors.accent.uppercased() == item.element ? 0.8 : 0.12), lineWidth: colors.accent.uppercased() == item.element ? 2 : 1))
                        .overlay {
                            if colors.accent.uppercased() == item.element {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(AppThemeColor.foreground(over: [item.element]) == "101010" ? .black : .white)
                            }
                        }
                }
                .frame(width: 44, height: 44)
                .buttonStyle(.plain)
                .accessibilityLabel("强调色 \(item.element)")
                .accessibilityIdentifier("theme.editor.swatch.\(item.offset)")
            }
        }
    }

    private func colorHex(at index: Int) -> String {
        switch index {
        case 0: return colors.background
        case 1: return colors.backgroundEnd
        case 2: return colors.surface
        default: return colors.accent
        }
    }

    private func colorBinding(at index: Int) -> Binding<Color> {
        Binding(
            get: { AppThemeColor.color(colorHex(at: index)) },
            set: { newColor in updateSwatch(index: index, hex: AppThemeColor.hex(newColor, scheme: previewScheme)) }
        )
    }

    private func updateSwatch(index: Int, hex: String) {
        guard AppThemeColor.isValid(hex) else { return }
        if previewScheme == .light {
            switch index {
            case 0: draft.light.background = hex
            case 1: draft.light.backgroundEnd = hex
            case 2: draft.light.surface = hex
            default: draft.light.accent = hex
            }
        } else {
            switch index {
            case 0: draft.dark.background = hex
            case 1: draft.dark.backgroundEnd = hex
            case 2: draft.dark.surface = hex
            default: draft.dark.accent = hex
            }
        }
    }

    private func requestClose() {
        if hasChanges { showingDiscardConfirmation = true } else { closeWithoutSaving() }
    }

    private func closeWithoutSaving() {
        onCancel()
        dismiss()
    }

    private func save() {
        guard canSave else { return }
        isSaving = true
        errorMessage = nil
        let shouldApply = draft.id == store.selectedID
        do {
            try store.save(draft, apply: shouldApply)
            isSaving = false
            onSaved()
            dismiss()
        } catch {
            isSaving = false
            errorMessage = error.localizedDescription
        }
    }
}
