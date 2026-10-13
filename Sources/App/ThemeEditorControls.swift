import SwiftUI

/// Sections describe controls that are actually consumed by app-owned views.
enum ThemeEditorSection: String, CaseIterable, Identifiable {
    case colors, background, cards, components
    var id: String { rawValue }
    var title: String {
        switch self {
        case .colors: return "颜色"
        case .background: return "背景"
        case .cards: return "卡片"
        case .components: return "控件"
        }
    }
    var symbol: String {
        switch self {
        case .colors: return "paintpalette"
        case .background: return "rectangle.fill"
        case .cards: return "rectangle.on.rectangle"
        case .components: return "slider.horizontal.3"
        }
    }
}

enum ThemeColorField: String, Identifiable {
    case accent, background, backgroundEnd, surface, primaryText, secondaryText, border, selection
    var id: String { rawValue }
    var title: String {
        switch self {
        case .accent: return "强调色"
        case .background: return "页面背景"
        case .backgroundEnd: return "渐变末端"
        case .surface: return "卡片背景"
        case .primaryText: return "主要文字"
        case .secondaryText: return "辅助文字"
        case .border: return "边框"
        case .selection: return "选中背景"
        }
    }
    var detail: String {
        switch self {
        case .accent: return "按钮、图标与链接"
        case .background: return "应用页面的底色"
        case .backgroundEnd: return "从左上向右下过渡"
        case .surface: return "列表与内容卡片"
        case .primaryText: return "应用内标题与内容"
        case .secondaryText: return "说明与次要信息"
        case .border: return "卡片及控件描边"
        case .selection: return "选中标签与分类"
        }
    }
    var pickerID: String {
        switch self {
        case .background: return "0"
        case .backgroundEnd: return "1"
        case .surface: return "2"
        case .accent: return "3"
        default: return rawValue
        }
    }
}

struct ThemeEditorColorRow: View {
    let field: ThemeColorField
    let hex: String
    @Binding var color: Color
    let editHex: () -> Void
    @Environment(\.dynamicTypeSize) private var textSize

    var body: some View {
        Group {
            if textSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) { label; controls }
            } else {
                HStack(spacing: 10) { label; Spacer(minLength: 2); controls }
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
    }
    private var label: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(field.title).appFont(.subheadline.weight(.semibold))
            Text(field.detail).appFont(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    private var controls: some View {
        HStack(spacing: 4) {
            Button(action: editHex) {
                Text("#" + hex.uppercased())
                    .appFont(.system(size: 13, weight: .medium, design: .monospaced))
                    .lineLimit(1).minimumScaleFactor(0.8)
                    .frame(minWidth: 72, minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("编辑\(field.title)颜色值")
            .accessibilityValue(hex.uppercased())
            .accessibilityIdentifier("theme.editor.hex.\(field.rawValue)")
            ColorPicker(field.title, selection: $color, supportsOpacity: false)
                .labelsHidden().frame(width: 44, height: 44)
                .accessibilityIdentifier("theme.editor.color.\(field.pickerID)")
        }
        .padding(.leading, 6)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).stroke(Color.primary.opacity(0.10), lineWidth: 0.7))
        .fixedSize(horizontal: true, vertical: false)
    }
}

/// Exact color entry stays local until Confirm; invalid and translucent values
/// never reach the theme draft. Accept opaque AARRGGBB as a convenience.
struct ThemeHexEditor: View {
    let field: ThemeColorField
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var input: String
    @FocusState private var focused: Bool

    init(field: ThemeColorField, hex: String, onSave: @escaping (String) -> Void) {
        self.field = field; self.onSave = onSave
        _input = State(initialValue: "#" + hex.uppercased())
    }
    private var normalized: String? {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if value.hasPrefix("#") { value.removeFirst() }
        if value.count == 8 && value.hasPrefix("FF") { value = String(value.dropFirst(2)) }
        return AppThemeColor.isValid(value) ? value : nil
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                hexContents
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(field.title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }.accessibilityIdentifier("theme.hex.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确定") { save() }.disabled(normalized == nil)
                        .accessibilityIdentifier("theme.hex.save")
                }
            }
        }
        .modifier(AppTypographyRoot())
    }
    private var hexContents: some View {
            VStack(alignment: .leading, spacing: 20) {
                RoundedRectangle(cornerRadius: 22)
                    .fill(normalized.map(AppThemeColor.color) ?? Color(uiColor: .secondarySystemBackground))
                    .frame(height: 100)
                    .overlay(RoundedRectangle(cornerRadius: 22).stroke(.secondary.opacity(0.2), lineWidth: 1))
                    .accessibilityHidden(true)
                TextField("#RRGGBB", text: $input)
                    .appFont(.system(size: 20, weight: .medium, design: .monospaced)).textInputAutocapitalization(.characters)
                    .autocorrectionDisabled().keyboardType(.asciiCapable)
                    .padding(16).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
                    .focused($focused).submitLabel(.done)
                    .onSubmit { save() }
                    .accessibilityLabel("十六进制颜色")
                    .accessibilityIdentifier("theme.hex.input")
                Text(normalized == nil ? "请输入 6 位 RGB，或以 FF 开头的 8 位不透明颜色。" : "颜色值有效；存储主题前仍会检查文字对比度。")
                    .appFont(.footnote).foregroundStyle(normalized == nil ? Color.red : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("theme.hex.validation")
                Spacer(minLength: 0)
            }
            .padding(22)
    }
    private func save() {
        guard let normalized else { return }
        onSave(normalized); dismiss()
    }
}

struct ThemeAccentSwatches: View {
    let scheme: ColorScheme
    let selectedHex: String
    let onSelect: (String) -> Void
    private var colors: [String] {
        scheme == .light
            ? ["1F4E79", "6B3D57", "356859", "8A4B2A", "5A4A8B", "7A3E22"]
            : ["B9D9F2", "F0BDD7", "BFE7CC", "F2C89E", "D0C2F5", "F0C1AC"]
    }
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(colors.enumerated()), id: \.offset) { item in
                Button { onSelect(item.element) } label: {
                    Circle().fill(AppThemeColor.color(item.element))
                        .frame(width: 26, height: 26)
                        .overlay {
                            if selectedHex.uppercased() == item.element {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(AppThemeColor.color(AppThemeColor.foreground(over: [item.element])))
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("强调色 \(item.element)")
                .accessibilityIdentifier("theme.editor.swatch.\(item.offset)")
            }
        }
    }
}
