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
                // 与生产代码一致：登录 / 分类各自成组（iOS 26 隐藏共享玻璃底），
                // 每个按钮自带胶囊，不再被并进同一个按键。
                loginItem
                categoryItem
            }
            .accessibilityIdentifier("harness.nav.root")
        }
    }

    @ToolbarContentBuilder
    private var loginItem: some ToolbarContent {
        if #available(iOS 26.0, *) {
            ToolbarItem(placement: .navigationBarTrailing) { loginButton }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .navigationBarTrailing) { loginButton }
        }
    }

    @ToolbarContentBuilder
    private var categoryItem: some ToolbarContent {
        if #available(iOS 26.0, *) {
            ToolbarItem(placement: .navigationBarTrailing) { categoryButton }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .navigationBarTrailing) { categoryButton }
        }
    }

    private var loginButton: some View {
        NavTextButton(title: "登录", symbol: "person.crop.circle", tint: .accentColor, pill: true) {}
            .accessibilityIdentifier("harness.nav.login")
    }

    private var categoryButton: some View {
        NavTextButton(title: "分类", symbol: "square.grid.2x2", tint: .accentColor, pill: true) {}
            .accessibilityIdentifier("harness.nav.category")
    }
}
