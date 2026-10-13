import SwiftUI
import UIKit

/// All controls write through one editor-owned draft; subpages never save or apply.
struct ThemePaletteEditor: View {
    enum Page { case colors, background, cards }
    @Binding var draft: AppTheme
    @Binding var previewScheme: ColorScheme
    let page: Page
    @State private var hexField: ThemeColorField?

    private var colors: AppThemeSwatches { draft.swatches(for: previewScheme) }
    private var resolved: ResolvedAppPalette { ResolvedAppPalette(theme: draft, scheme: previewScheme) }
    private var surface: Color { Color(uiColor: .secondarySystemGroupedBackground) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ThemeEditorSchemePicker(selection: $previewScheme)
            switch page {
            case .colors: colorsSection
            case .background: backgroundSection
            case .cards: cardsSection
            }
            if let message = draft.validationMessage {
                Label(message, systemImage: "exclamationmark.circle")
                    .appFont(.footnote).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("theme.editor.error")
            }
        }
        .sheet(item: $hexField) { field in
            ThemeHexEditor(field: field, hex: hex(for: field)) { update(field, hex: $0) }
                .presentationDetents([.medium, .large])
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
                VStack(alignment: .leading, spacing: 8) {
                    Text("卡片圆角").appFont(.subheadline.weight(.semibold))
                    Text(colors.cardRadius.map { "当前 \(Int($0.rounded())) pt" } ?? "跟随界面默认")
                        .appFont(.caption).foregroundStyle(.secondary)
                    Slider(value: cardRadiusBinding, in: 8...30, step: 1)
                        .accessibilityLabel("卡片圆角")
                        .accessibilityIdentifier("theme.editor.cardRadius")
                    HStack { Text("8 pt"); Spacer(); Text("30 pt") }
                        .appFont(.caption2).foregroundStyle(.secondary)
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

}
