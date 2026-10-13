import SwiftUI
import UIKit

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

struct ThemeEditorSchemePicker: View {
    @Binding var selection: ColorScheme
    @Environment(\.dynamicTypeSize) private var textSize
    var body: some View {
        let layout = textSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 4)) : AnyLayout(HStackLayout(spacing: 4))
        layout {
            mode(.light, title: "浅色主题", symbol: "sun.max", id: "light")
            mode(.dark, title: "深色主题", symbol: "moon", id: "dark")
        }
        .padding(4)
        .background(Color.primary.opacity(0.065), in: RoundedRectangle(cornerRadius: 14))
    }
    private func mode(_ scheme: ColorScheme, title: String, symbol: String, id: String) -> some View {
        Button { selection = scheme } label: {
            Label(title, systemImage: symbol).appFont(.subheadline.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(selection == scheme ? Color(uiColor: .secondarySystemGroupedBackground) : .clear,
                            in: RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection == scheme ? .isSelected : [])
        .accessibilityIdentifier("theme.editor.mode.\(id)")
    }
}

enum ThemeEditorFonts {
    static func choices(_ manager: ReadingFontManager) -> [ReadingFontChoice] {
        var seen = Set<String>()
        return (manager.builtInFonts + manager.importedFonts.flatMap(\.faces))
            .filter { !$0.id.isEmpty && seen.insert($0.id).inserted }
    }
    static func isAvailable(_ name: String, manager: ReadingFontManager) -> Bool {
        name.isEmpty || (choices(manager).contains { $0.id == name } && UIFont(name: name, size: 17) != nil)
    }
    static func name(_ selection: String?, manager: ReadingFontManager) -> String {
        guard let selection else { return "跟随全局字体" }
        if selection.isEmpty { return "系统默认" }
        guard let choice = choices(manager).first(where: { $0.id == selection }) else {
            return "字体不可用 · 系统默认"
        }
        return isAvailable(selection, manager: manager) ? choice.name : "\(choice.name) · 不可用"
    }
    static func resolved(_ selection: String?, manager: ReadingFontManager) -> String {
        let name = selection ?? manager.selectedPostScriptName
        return isAvailable(name, manager: manager) ? name : ""
    }
}

struct ThemeEditorFontChoices: View {
    @Binding var selection: String?
    @ObservedObject private var manager = ReadingFontManager.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("界面字体").appFont(.headline)
            Text("仅影响应用界面，不改变阅读字体或分页。以下选择会随主题保存。")
                .appFont(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 0) {
                row("跟随全局字体", detail: "当前：\(manager.selectedDisplayName)", value: nil,
                    id: "theme.editor.font.follow")
                Divider()
                row("系统默认", detail: nil, value: "", id: "theme.editor.font.system")
                ForEach(ThemeEditorFonts.choices(manager)) { choice in
                    Divider()
                    row(choice.name, detail: ThemeEditorFonts.isAvailable(choice.id, manager: manager) ? nil : "字体不可用",
                        value: choice.id, id: "theme.editor.font.\(choice.id)")
                }
            }.padding(.horizontal, 16).themeEditorSurface()
            if let selection, !ThemeEditorFonts.isAvailable(selection, manager: manager) {
                Label("已选字体不可用，暂以系统字体显示；可选择其他字体。", systemImage: "exclamationmark.circle")
                    .appFont(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("theme.editor.font.unavailable")
            }
            Text("文字预览 · 阅读，让时间慢下来。")
                .font(AppFontStyle.body.resolve(ThemeEditorFonts.resolved(selection, manager: manager)))
                .frame(maxWidth: .infinity, alignment: .leading).padding(16).themeEditorSurface()
                .accessibilityIdentifier("theme.editor.font.preview")
            Text("列表包含内置字体和已导入字体。新增字体请先退出编辑，在字体管理中导入。")
                .appFont(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    private func row(_ title: String, detail: String?, value: String?, id: String) -> some View {
        Button { selection = value } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).appFont(.body)
                    if let detail { Text(detail).appFont(.caption).foregroundStyle(.secondary) }
                }.fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 6)
                if selection == value { Image(systemName: "checkmark").accessibilityHidden(true) }
            }
            .padding(.vertical, 8).frame(minHeight: 48).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(value.map { !ThemeEditorFonts.isAvailable($0, manager: manager) } ?? false)
        .accessibilityAddTraits(selection == value ? .isSelected : [])
        .accessibilityIdentifier(id)
    }
}

/// Real app components resolve the draft via a local environment only.
struct ThemeEditorLivePreview: View {
    let theme: AppTheme
    let scheme: ColorScheme
    @State private var tab: LibraryTab = .shelf
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("当前主题预览").appFont(.caption).foregroundStyle(.secondary)
            ThemePreviewCard(theme: theme, scheme: scheme, isSelected: false)
            LibraryDock(selection: $tab)
                .padding(.vertical, 14)
                .background { AppThemeCanvas() }
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .allowsHitTesting(false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Tab栏预览")
                .accessibilityValue(theme.customization?.tabStyle.title ?? "仅图标")
                .accessibilityIdentifier("theme.editor.tab.preview")
        }
        .environment(\.appTheme, theme)
        .environment(\.colorScheme, scheme)
    }
}

/// Width guides are measurements, not invented books or library content.
struct ThemeEditorShelfSizing: View {
    let columns: Int
    let requestedWidth: Double
    @State private var availableWidth: CGFloat = 0
    @Environment(\.dynamicTypeSize) private var textSize
    private var metrics: ThemeShelfMetrics {
        ThemeShelfMetrics(width: availableWidth + 48,
            customization: ThemeCustomization(shelfColumns: columns, coverWidth: requestedWidth),
            accessibility: textSize.isAccessibilitySize)
    }
    private var columnWidth: CGFloat {
        max(0, (availableWidth - CGFloat(metrics.columns - 1) * 18) / CGFloat(metrics.columns))
    }
    private var actualWidth: CGFloat { metrics.coverWidth }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("列宽示意").appFont(.headline)
            GeometryReader { proxy in
                HStack(spacing: 18) {
                    ForEach(0..<metrics.columns, id: \.self) { _ in
                        ZStack {
                            Capsule().fill(Color.primary.opacity(0.07))
                            Capsule().fill(Color.primary.opacity(0.32)).frame(width: actualWidth)
                        }.frame(maxWidth: .infinity)
                    }
                }
                .onAppear { availableWidth = proxy.size.width }
                .onChange(of: proxy.size.width) { availableWidth = $0 }
            }.frame(height: 10).accessibilityHidden(true)
            Text("此示意区每列可用 \(Int(columnWidth.rounded(.down))) pt，封面显示宽度为 \(Int(actualWidth.rounded(.down))) pt；当前空间容纳 \(metrics.columns) 列。实际书架按当时的窗口宽度计算。")
                .appFont(.footnote).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("theme.editor.shelf.clamp")
        }.padding(16).themeEditorSurface()
    }
}
