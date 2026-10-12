import SwiftUI
import UIKit

/// Small native control fixture: no copied app screens, covers or saved settings.
struct ThemeHarnessView: View {
    @State private var enabled = true
    @State private var level = 0.5
    @State private var sheetEnabled = true
    @State private var sheetLevel = 0.5
    @State private var showingSheet = false
    private let dark = ProcessInfo.processInfo.arguments.contains("--theme-dark")

    var body: some View {
        NavigationStack {
            Form {
                Section("原生控件") {
                    Toggle("启用选项", isOn: $enabled)
                        .accessibilityIdentifier("theme.toggle")
                    Slider(value: $level) { Text("调节数值") }
                        .accessibilityIdentifier("theme.slider")
                    Link("系统链接", destination: URL(string: "https://example.com")!)
                        .accessibilityIdentifier("theme.link")
                    NavigationLink {
                        Text("原生导航目标")
                            .accessibilityIdentifier("theme.destination")
                            .navigationTitle("导航")
                    } label: {
                        Text("打开导航")
                    }
                    .accessibilityIdentifier("theme.navigation")
                    Button("打开表单") { showingSheet = true }
                        .accessibilityIdentifier("theme.openSheet")
                }
                Section("确定性检查") {
                    Text(dark ? "深色模式" : "浅色模式")
                        .accessibilityIdentifier("theme.mode")
                    Text("生产调色板 · 双模式 RGB")
                        .font(.footnote)
                        .accessibilityIdentifier("theme.palette")
                        .accessibilityValue(Self.paletteReport)
                }
            }
            .navigationTitle("全局黑白灰")
            .sheet(isPresented: $showingSheet) {
                // Deliberately no tint/accent/style modifier here: inherit root.
                NavigationStack {
                    Form {
                        Toggle("表单选项", isOn: $sheetEnabled)
                            .accessibilityIdentifier("theme.sheet.toggle")
                        Slider(value: $sheetLevel) { Text("表单数值") }
                            .accessibilityIdentifier("theme.sheet.slider")
                        Link("表单链接", destination: URL(string: "https://example.com")!)
                            .accessibilityIdentifier("theme.sheet.link")
                        Button("完成") { showingSheet = false }
                            .accessibilityIdentifier("theme.sheet.done")
                    }
                    .navigationTitle("继承全局主题")
                }
            }
        }
        .preferredColorScheme(dark ? .dark : .light)
    }

    /// Resolve actual production tokens against explicit UIKit traits, never
    /// against whichever style happens to be active when the test launches.
    private static var paletteReport: String {
        let tokens: [(String, Color)] = [
            ("accent", AppPalette.accent), ("background", AppPalette.background),
            ("surface", AppPalette.surface), ("secondary", AppPalette.secondary),
            ("selection", AppPalette.selection), ("border", AppPalette.border),
            ("placeholderTop", AppPalette.placeholderTop),
            ("placeholderBottom", AppPalette.placeholderBottom),
            ("highlight", AppPalette.highlight)
        ]
        var result: [String: [String: [Double]]] = [:]
        let styles: [(String, UIUserInterfaceStyle)] = [("light", .light), ("dark", .dark)]
        for (name, style) in styles {
            let traits = UITraitCollection(userInterfaceStyle: style)
            var values: [String: [Double]] = [:]
            for (key, token) in tokens {
                let color = UIColor(token).resolvedColor(with: traits)
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                if color.getRed(&r, green: &g, blue: &b, alpha: &a) {
                    values[key] = [Double(r), Double(g), Double(b), Double(a)]
                } // Missing channels fail the test; do not substitute fake RGB.
            }
            result[name] = values
        }
        guard let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]),
              let report = String(data: data, encoding: .utf8) else { return "invalid" }
        return report
    }
}
