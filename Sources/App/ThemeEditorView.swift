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
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 18) {
                        previewSection
                            .frame(height: max(240, min(420, geometry.size.height * 0.52)))
                        VStack(spacing: 16) {
                            nameSection
                            HStack(spacing: 12) {
                                styleSection
                                Spacer(minLength: 0)
                                schemePicker
                            }
                            colorSection
                            if let message = errorMessage ?? validationMessage {
                                Text(message)
                                    .appFont(.footnote)
                                    .foregroundStyle(.red)
                                    .accessibilityIdentifier("theme.editor.error")
                            }
                        }
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28))
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .padding(.bottom, 20)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)
            }
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
        .interactiveDismissDisabled(hasChanges)
        .modifier(AppTypographyRoot())
    }

    private var canSave: Bool {
        !draft.isBuiltIn && validationMessage == nil && !isSaving
    }

    private var editorBackground: Color {
        Color(uiColor: .systemGroupedBackground)
    }

    private var previewSection: some View {
        ThemePreviewCard(theme: draft, scheme: previewScheme, isSelected: false)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("主题实时预览")
            .accessibilityValue("\(draft.name)，\(previewScheme == .light ? "浅色" : "深色")，\(colors.accent)")
            .accessibilityIdentifier("theme.editor.preview")
            .animation(UIAccessibility.isReduceMotionEnabled ? nil : .easeInOut(duration: 0.25), value: draft)
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
        HStack(spacing: 12) {
            TextField("主题名称", text: $draft.name)
                .appFont(.title3.weight(.semibold))
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .focused($nameFocused)
                .submitLabel(.done)
                .onSubmit { nameFocused = false }
                .accessibilityLabel("主题名称")
                .accessibilityIdentifier("theme.editor.name")
            Image(systemName: "pencil")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .frame(minHeight: 44)
    }

    private var styleSection: some View {
        HStack(spacing: 2) {
            ForEach(AppThemeBackgroundStyle.allCases) { style in
                Button {
                    nameFocused = false
                    draft.backgroundStyle = style
                } label: {
                    Text(style.title)
                        .appFont(.subheadline.weight(.medium))
                        .frame(minWidth: 44, minHeight: 44)
                        .padding(.horizontal, 5)
                        .background(draft.backgroundStyle == style ? Color.primary.opacity(0.10) : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(style == .solid ? "theme.editor.style.solid" : "theme.editor.style.gradient")
                .accessibilityAddTraits(draft.backgroundStyle == style ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Color.primary.opacity(0.04), in: Capsule())
    }

    private var colorSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 4) {
                colorControl(title: "背景", index: 0)
                if draft.backgroundStyle == .gradient {
                    colorControl(title: "末端", index: 1)
                }
                colorControl(title: "卡片", index: 2)
                colorControl(title: "强调", index: 3)
            }
            Divider()
            quickSwatches
                .frame(maxWidth: .infinity)
                .accessibilityLabel("快速强调色")
        }
    }

    private func colorControl(title: String, index: Int) -> some View {
        VStack(spacing: 4) {
            ColorPicker("", selection: colorBinding(at: index), supportsOpacity: false)
                .labelsHidden()
                .frame(width: 44, height: 44)
                .accessibilityLabel(title)
                .accessibilityIdentifier("theme.editor.color.\(index)")
            Text(title)
                .appFont(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var quickSwatches: some View {
        let swatches = previewScheme == .light
            ? ["1F4E79", "6B3D57", "356859", "8A4B2A", "5A4A8B", "7A3E22"]
            : ["B9D9F2", "F0BDD7", "BFE7CC", "F2C89E", "D0C2F5", "F0C1AC"]
        return HStack(spacing: 0) {
            ForEach(Array(swatches.enumerated()), id: \.offset) { item in
                Button {
                    updateSwatch(index: 3, hex: item.element)
                } label: {
                    Circle()
                        .fill(AppThemeColor.color(item.element))
                        .frame(width: 28, height: 28)
                        .overlay(Circle().stroke(Color.primary.opacity(colors.accent.uppercased() == item.element ? 0.8 : 0.12), lineWidth: colors.accent.uppercased() == item.element ? 2 : 1))
                        .overlay {
                            if colors.accent.uppercased() == item.element {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(AppThemeColor.foreground(over: [item.element]) == "101010" ? .black : .white)
                            }
                        }
                }
                .frame(maxWidth: .infinity, minHeight: 44)
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
