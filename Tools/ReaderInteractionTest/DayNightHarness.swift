import SwiftUI

/// 阅读设置里的日间/夜间：验证两套排版各自保存、切换整套生效。
/// 启动参数 `--reset-day-night` 把相关 UserDefaults 清回默认，供 UI 测试重复运行。
struct DayNightHarnessView: View {
    @StateObject private var settings: ReadSettings

    init() {
        let defaults = UserDefaults.standard
        if ProcessInfo.processInfo.arguments.contains("--reset-day-night") {
            for key in ["reader.mode.v1", "reader.mode.day.layout.v1", "reader.mode.night.layout.v1",
                        "reader.mode.migrated.v1", "fontSize", "readerLineHeightTenths",
                        "readerParagraphHeightTenths", "readerFullJustify", "readerBottomJustify",
                        "leftMargin", "rightMargin", "topMargin", "bottomMargin", "theme"] {
                defaults.removeObject(forKey: key)
            }
        }
        _settings = StateObject(wrappedValue: ReadSettings())
    }

    private func bumpFont(_ delta: Double) {
        settings.objectWillChange.send()
        settings.fontSize = min(36, max(12, settings.fontSize + delta))
    }

    private func bumpLeft(_ delta: Double) {
        settings.objectWillChange.send()
        settings.leftMargin = min(60, max(0, settings.leftMargin + delta))
    }

    private var stateText: String {
        "mode=\(settings.mode) theme=\(settings.theme) font=\(Int(settings.fontSize)) left=\(Int(settings.leftMargin))"
    }

    var body: some View {
        NavigationStack {
            Form {
                ReaderAppearanceControls(settings: settings)
                Section("测试排版") {
                    HStack {
                        Text("字号")
                        Spacer()
                        Button("－") { bumpFont(-1) }
                            .buttonStyle(.borderless)
                            .accessibilityIdentifier("day-night-font-minus")
                        Text("\(Int(settings.fontSize)) pt")
                            .accessibilityIdentifier("day-night-font")
                        Button("＋") { bumpFont(1) }
                            .buttonStyle(.borderless)
                            .accessibilityIdentifier("day-night-font-plus")
                    }
                    HStack {
                        Text("左边距")
                        Spacer()
                        Button("－") { bumpLeft(-1) }
                            .buttonStyle(.borderless)
                            .accessibilityIdentifier("day-night-left-minus")
                        Text("\(Int(settings.leftMargin)) pt")
                            .accessibilityIdentifier("day-night-left")
                        Button("＋") { bumpLeft(1) }
                            .buttonStyle(.borderless)
                            .accessibilityIdentifier("day-night-left-plus")
                    }
                }
                Section {
                    Text(stateText)
                        .appFont(.footnote)
                        .accessibilityIdentifier("day-night-state")
                }
            }
            .navigationTitle("阅读设置")
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.light)
    }
}
