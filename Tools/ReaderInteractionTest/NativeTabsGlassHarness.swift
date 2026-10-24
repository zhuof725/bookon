import SwiftUI

struct NativeTabsGlassHarness: View {
    @State private var selection: LibraryTab = .shelf
    @State private var theme = AppTheme.custom()
    var body: some View {
        NavigationStack {
            LibraryTabContainer(selection: $selection) {
                VStack(spacing: 24) {
                    Text("书架测试页").accessibilityIdentifier("native.page.shelf")
                    NavigationLink("打开详情") {
                        Text("详情测试页").accessibilityIdentifier("native.detail")
                    }.accessibilityIdentifier("native.push")
                    Button("星形图标") { theme.customization?.tabIcons = ["shelf": "star.fill"] }
                        .accessibilityIdentifier("native.icon")
                }
            } discover: {
                Text("发现测试页").accessibilityIdentifier("native.page.discover")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } statistics: {
                Text("统计测试页").accessibilityIdentifier("native.page.statistics")
            } profile: {
                Text("我的测试页").accessibilityIdentifier("native.page.profile")
            } search: {
                Text("搜索测试页").accessibilityIdentifier("native.page.search")
            } home: {
                Text("首页测试页").accessibilityIdentifier("native.page.home")
            }
        }
        .environment(\.appTheme, theme)
    }
}

/// A real displayed backdrop, not ImageRenderer (which cannot test native blur).
struct NativeGlassHarness: View {
    @State private var effect: ThemeInterfaceEffect = .transparent
    @State private var control = false
    @State private var reduced = false
    @State private var hideCards = false
    private var theme: AppTheme {
        var value = AppTheme.custom()
        value.customization?.effect = effect
        value.customization?.cardBackground = !hideCards
        value.customization?.glowIntensity = 0
        value.customization?.surfaceOpacity = 0.85
        return value
    }
    var body: some View {
        VStack(spacing: 24) {
            Text("原生背景模糊验证")
            ZStack {
                Canvas { context, size in
                    for x in 0..<100 {
                        for y in 0..<100 {
                            let color: Color = (x / 14) % 2 == 0 ? .red : .blue
                            context.fill(Path(CGRect(x: x * 4, y: y * 4, width: 4, height: 4)),
                                         with: .color((x + y) % 2 == 0 ? color : .white))
                        }
                    }
                }
                ThemeSurfaceRendering(shape: RoundedRectangle(cornerRadius: 16), isCard: !control,
                                      palette: ResolvedAppPalette(theme: theme, scheme: .light),
                                      reduceTransparency: reduced)
            }
            .frame(width: 280, height: 200)
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("glass.sample")
            ForEach(ThemeInterfaceEffect.allCases) { item in
                Button(item.title) { effect = item }
                    .accessibilityIdentifier("glass.mode.\(item.rawValue)")
            }
            Text(effect.rawValue).accessibilityIdentifier("glass.current")
            Button("控件模式") { control.toggle() }.accessibilityIdentifier("glass.control")
            Button("关闭卡片") { hideCards.toggle() }.accessibilityIdentifier("glass.hideCards")
            Button("降低透明度") { reduced.toggle() }.accessibilityIdentifier("glass.reduced")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.gray)
        .environment(\.appTheme, theme)
        .preferredColorScheme(.light)
    }
}
