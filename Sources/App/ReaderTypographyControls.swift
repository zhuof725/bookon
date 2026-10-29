import SwiftUI

/// 日间 / 夜间：两套独立保存的阅读排版与背景。
struct ReaderAppearanceControls: View {
    @ObservedObject var settings: ReadSettings

    private var mode: ReaderDayNightMode { settings.dayNightMode }
    private var modeSelection: Binding<Int> {
        let settings = self.settings
        return Binding(get: { settings.mode }, set: { settings.setMode($0) })
    }

    var body: some View {
        Section {
            Picker("阅读模式", selection: modeSelection) {
                ForEach(ReaderDayNightMode.allCases) { item in
                    Text(item.title).tag(item.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("reader.mode.picker")

            HStack(spacing: 10) {
                ForEach(mode.themeIndices, id: \.self) { index in
                    swatch(index)
                }
            }
            .padding(.vertical, 2)
        } header: {
            HStack(spacing: 6) {
                Image(systemName: mode.symbol)
                Text(mode == .day ? "日间阅读" : "夜间阅读")
            }
        } footer: {
            Text("日间与夜间各自保存背景、字号、行距和边距；切换模式时整套生效。")
        }
    }

    private func swatch(_ index: Int) -> some View {
        let paper = ReadSettings.themes[index]
        let selected = settings.theme == index
        return Button {
            settings.selectTheme(index)
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: AppLayout.radiusControl, style: .continuous)
                        .fill(paper.bg)
                    Text("文").font(.system(size: 20, weight: .medium)).foregroundStyle(paper.fg)
                }
                .frame(height: 56)
                .overlay {
                    RoundedRectangle(cornerRadius: AppLayout.radiusControl, style: .continuous)
                        .strokeBorder(selected ? Color.accentColor : Color.secondary.opacity(0.28),
                                      lineWidth: selected ? 2.5 : 1)
                }
                .overlay(alignment: .topTrailing) {
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .symbolRenderingMode(.palette)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(paper.bg, paper.fg)
                            .padding(6)
                            .accessibilityHidden(true)
                    }
                }
                Text(paper.name)
                    .appFont(.caption)
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("背景\(paper.name)")
        .accessibilityIdentifier("reader.theme.\(index)")
    }
}

/// 字号、边距使用 pt；行高和段后间距使用字高倍率，每步 0.1。
struct ReaderTypographyControls: View {
    @ObservedObject var settings: ReadSettings

    var body: some View {
        Section {
            ReaderLayoutControl(title: "字号", identifier: "font", value: $settings.fontSize, range: 12...36)
            ReaderLayoutControl(title: "行高倍率", identifier: "line", value: $settings.lineSpacing, range: 0...20, usesHeightMultiplier: true)
            ReaderLayoutControl(title: "段后倍率", identifier: "paragraph", value: $settings.paragraphSpacing, range: 0...20, usesHeightMultiplier: true)
            Picker("本章说卡片", selection: $settings.commentCardSize) {
                Text("小").tag(0)
                Text("标准").tag(1)
                Text("大").tag(2)
            }
            .accessibilityIdentifier("reader.commentCard.size")
        } header: { Text("文字排版") } footer: {
            Text("字号单位 pt；行高与段后按字高倍率计算，每步 0.1。本章说卡片只影响正文里的评论摘要。")
        }
        Section {
            Toggle("两端对齐", isOn: $settings.fullJustify)
                .accessibilityIdentifier("layout-full-justify")
            Toggle("底部对齐", isOn: $settings.bottomJustify)
                .accessibilityIdentifier("layout-bottom-justify")
            ReaderLayoutControl(title: "左边距", identifier: "left", value: $settings.leftMargin, range: 0...60)
            ReaderLayoutControl(title: "右边距", identifier: "right", value: $settings.rightMargin, range: 0...60)
            ReaderLayoutControl(title: "上边距", identifier: "top", value: $settings.topMargin, range: 0...80)
            ReaderLayoutControl(title: "下边距", identifier: "bottom", value: $settings.bottomMargin, range: 0...80)
        } header: { Text("边距与对齐") } footer: {
            Text("边距单位 pt，调整后即时生效。")
        }
    }
}

/// 阅读设置里统一的入口行：图标 + 标题 + 当前值；箭头由 NavigationLink 绘制。
struct ReaderSettingsLinkRow<Destination: View>: View {
    let symbol: String
    let title: String
    let detail: String
    let identifier: String
    let destination: Destination

    init(symbol: String, title: String, detail: String = "", identifier: String,
         @ViewBuilder destination: () -> Destination) {
        self.symbol = symbol
        self.title = title
        self.detail = detail
        self.identifier = identifier
        self.destination = destination()
    }

    var body: some View {
        NavigationLink {
            destination
        } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 24, alignment: .center)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text(title)
                Spacer(minLength: 8)
                if !detail.isEmpty {
                    Text(detail)
                        .appFont(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier(identifier)
    }
}

private struct ReaderLayoutControl: View {
    let title: String
    let identifier: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var usesHeightMultiplier: Bool = false

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(usesHeightMultiplier ? String(format: "%.1f 倍", value / 10) : "\(Int(value)) pt")
                    .monospacedDigit().foregroundStyle(.secondary)
                    .accessibilityIdentifier("layout-value-" + identifier)
            }
            HStack(spacing: 8) {
                Button { value = min(range.upperBound, max(range.lowerBound, value - 1)) } label: {
                    Image(systemName: "minus.circle").frame(width: 44, height: 36)
                }
                .buttonStyle(.borderless).disabled(value <= range.lowerBound)
                .accessibilityLabel("减小" + title).accessibilityIdentifier("layout-minus-" + identifier)
                Slider(value: $value, in: range, step: 1)
                    .accessibilityLabel(title).accessibilityIdentifier("layout-slider-" + identifier)
                Button { value = min(range.upperBound, max(range.lowerBound, value + 1)) } label: {
                    Image(systemName: "plus.circle").frame(width: 44, height: 36)
                }
                .buttonStyle(.borderless).disabled(value >= range.upperBound)
                .accessibilityLabel("增大" + title).accessibilityIdentifier("layout-plus-" + identifier)
            }
        }
    }
}
