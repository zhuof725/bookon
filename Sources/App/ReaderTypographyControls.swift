import SwiftUI

/// 字号、边距使用 pt；行高和段后间距使用字高倍率，每步 0.1。
struct ReaderTypographyControls: View {
    @ObservedObject var settings: ReadSettings

    var body: some View {
        Section("字体大小") {
            ReaderLayoutControl(title: "字号", identifier: "font", value: $settings.fontSize, range: 12...36)
        }
        Section {
            ReaderLayoutControl(title: "行高倍率", identifier: "line", value: $settings.lineSpacing, range: 0...20, usesHeightMultiplier: true)
            ReaderLayoutControl(title: "段后倍率", identifier: "paragraph", value: $settings.paragraphSpacing, range: 0...20, usesHeightMultiplier: true)
        } header: { Text("间距") } footer: {
            Text("按实际字高计算，随字号缩放；每步调整 0.1 倍。行高 1.0 倍表示不增加行间距。")
        }
        Section {
            Toggle("两端对齐", isOn: $settings.fullJustify)
                .accessibilityIdentifier("layout-full-justify")
            Toggle("底部对齐", isOn: $settings.bottomJustify)
                .accessibilityIdentifier("layout-bottom-justify")
        } header: { Text("对齐") } footer: {
            Text("正文首行始终顶齐。近满页小幅均分行间余量，同时齐底；短末页保持自然行距，留白在下方。")
        }
        Section {
            ReaderLayoutControl(title: "左边距", identifier: "left", value: $settings.leftMargin, range: 0...60)
            ReaderLayoutControl(title: "右边距", identifier: "right", value: $settings.rightMargin, range: 0...60)
            ReaderLayoutControl(title: "上边距", identifier: "top", value: $settings.topMargin, range: 0...80)
            ReaderLayoutControl(title: "下边距", identifier: "bottom", value: $settings.bottomMargin, range: 0...80)
        } header: { Text("边距") } footer: {
            Text("单位为 pt。上下边距在系统安全区内计算；调整后即时生效并自动保存。")
        }
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
