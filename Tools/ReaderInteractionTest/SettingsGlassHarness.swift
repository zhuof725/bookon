import SwiftUI

/// Production row components with isolated callbacks. The backdrop is a test
/// gradient, not the user's screenshot or a bundled wallpaper.
struct SettingsGlassHarness: View {
    @State private var selection = ""
    private var dark: Bool { ProcessInfo.processInfo.arguments.contains("--settings-dark") }
    private var large: Bool { ProcessInfo.processInfo.arguments.contains("--settings-large") }
    private let rows = [("书源管理", "square.stack.3d.up"), ("目录规则", "list.bullet.rectangle"),
                        ("替换规则", "text.badge.checkmark"), ("字体管理", "textformat"),
                        ("外观主题", "circle.lefthalf.filled"), ("搜索书籍", "magnifyingglass"),
                        ("缓存管理", "internaldrive")]
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        Button { selection = row.0 } label: {
                            SettingsGlassLabel(title: row.0, symbol: row.1)
                        }.buttonStyle(.plain).accessibilityIdentifier("settings.row.\(index)")
                    }
                    SettingsGlassValue(title: "已导入书源", value: "0 个")
                    SettingsGlassValue(title: "书架书籍", value: "0 本")
                }.padding(.horizontal, 24).padding(.vertical, 16)
            }
            .background {
                LinearGradient(colors: dark ? [.black, Color(white: 0.15)] : [Color(red: 0.48, green: 0.69, blue: 0.77), Color(white: 0.94)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .ignoresSafeArea()
            }
            .navigationTitle("我的")
            .safeAreaInset(edge: .bottom) {
                Text(selection.isEmpty ? "未操作" : selection)
                    .accessibilityIdentifier("settings.callback").padding(8)
            }
        }
        .frame(maxWidth: large ? 320 : .infinity)
        .environment(\.dynamicTypeSize, large ? .accessibility3 : .large)
        .preferredColorScheme(dark ? .dark : .light)
    }
}
