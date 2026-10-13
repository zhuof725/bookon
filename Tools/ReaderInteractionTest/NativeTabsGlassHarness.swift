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
            } statistics: {
                Text("统计测试页").accessibilityIdentifier("native.page.statistics")
            } profile: {
                Text("我的测试页").accessibilityIdentifier("native.page.profile")
            }
        }
        .environment(\.appTheme, theme)
    }
}

/// A real displayed backdrop, not ImageRenderer (which cannot test native blur).
struct NativeGlassHarness: View {
    @State private var effect: ThemeInterfaceEffect = .transparent
    private var theme: AppTheme {
        var value = AppTheme.custom()
        value.customization?.effect = effect
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
                ThemeSurface(shape: RoundedRectangle(cornerRadius: 16), isCard: true)
            }
            .frame(width: 280, height: 200)
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("glass.sample")
            ForEach(ThemeInterfaceEffect.allCases) { item in
                Button(item.title) { effect = item }
                    .accessibilityIdentifier("glass.mode.\(item.rawValue)")
            }
            Text(effect.rawValue).accessibilityIdentifier("glass.current")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.gray)
        .environment(\.appTheme, theme)
        .preferredColorScheme(.light)
    }
}
