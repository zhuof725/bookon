import SwiftUI

/// 复现发现页导航栏：标题很长（书源名）+ 右上角「登录 / 分类」。
/// 组件是生产代码 `NavTextButton`，这里只搭导航栏与标题。
struct NavBarOverflowHarnessView: View {
    /// --nav-bar-mode=long / --nav-bar-mode=short
    let mode: String

    private var title: String {
        mode == "short" ? "发现" : "🍅木里番茄 0922[GO 聚合版]"
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(0..<12) { index in
                    Text("内容行 \(index)")
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    NavTextButton(title: "登录", symbol: "person.crop.circle", tint: .accentColor) {}
                        .accessibilityIdentifier("harness.nav.login")
                    NavTextButton(title: "分类", symbol: "square.grid.2x2", tint: .accentColor) {}
                        .accessibilityIdentifier("harness.nav.category")
                }
            }
            .accessibilityIdentifier("harness.nav.root")
        }
    }
}
