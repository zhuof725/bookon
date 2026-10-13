import SwiftUI

/// Draft-only, real production surfaces. Sample labels never enter the library.
struct ThemeSettingPreview: View {
    let theme: AppTheme
    let scheme: ColorScheme
    let destination: ThemeEditorDestination
    @State private var tab: LibraryTab = .shelf
    @StateObject private var launch = ThemeAssetImageLoader()
    @Environment(\.dynamicTypeSize) private var typeSize
    private var settings: ThemeCustomization { theme.customization ?? ThemeCustomization() }
    private var palette: ResolvedAppPalette { ResolvedAppPalette(theme: theme, scheme: scheme) }
    private var compactHeight: CGFloat { typeSize.isAccessibilitySize ? 150 : 132 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(destination.title + " · 实时预览").appFont(.caption.weight(.semibold))
                .foregroundStyle(palette.secondary)
            Group {
                switch destination {
                case .tab: tabs
                case .shelf: shelf
                case .cover:
                    HStack(spacing: 18) {
                        BookCoverImage(url: nil).frame(width: 70, height: 102)
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                        Text("缺少封面时的实际效果\n已有书封不会被替换").appFont(.caption)
                    }.frame(maxWidth: .infinity, minHeight: compactHeight)
                case .launch:
                    ZStack {
                        Color.black
                        if let image = launch.image {
                            Image(uiImage: image).resizable().scaledToFit()
                        } else { Text("启动图已关闭").appFont(.caption).foregroundStyle(.white) }
                    }.frame(height: compactHeight)
                    .task(id: settings.launchImage) { await launch.load(settings.launchImage) }
                case .colors, .background, .effect, .cards: surfaceSample
                }
            }
            .background { AppThemeCanvas() }
            .clipShape(RoundedRectangle(cornerRadius: 16))
            Text(summary).appFont(.caption2).foregroundStyle(palette.secondary)
                .lineLimit(typeSize.isAccessibilitySize ? 3 : 2)
                .accessibilityIdentifier("theme.preview.summary")
        }
        .padding(12)
        .background { AppThemeCanvas() }
        .environment(\.appTheme, theme)
        .environment(\.colorScheme, scheme)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("theme.preview.live." + destination.rawValue)
    }

    private var tabs: some View {
        Group {
            if #available(iOS 26.0, *) {
                LibraryTabContainer(selection: $tab) {
                    Text("书架预览").appFont(.caption)
                } statistics: {
                    Text("统计预览").appFont(.caption)
                } profile: {
                    Text("我的预览").appFont(.caption)
                }
            } else { LibraryDock(selection: $tab) }
        }.frame(height: compactHeight)
    }
    private var shelf: some View {
        GeometryReader { proxy in
            let metrics = ThemeShelfMetrics(width: proxy.size.width + 48, customization: settings,
                                            accessibility: typeSize.isAccessibilitySize)
            HStack(alignment: .top, spacing: 18) {
                ForEach(0..<metrics.columns, id: \.self) { _ in
                    VStack(spacing: 4) {
                        // Same cover loader/cropping and real metric clamp as the shelf.
                        BookCoverImage(url: nil)
                            .frame(width: metrics.coverWidth * 0.55, height: metrics.coverWidth / 0.70 * 0.55)
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                        Text("示例书名").appFont(.caption2).lineLimit(1)
                    }.frame(maxWidth: .infinity)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }.frame(height: compactHeight).padding(.horizontal, 8)
    }
    private var surfaceSample: some View {
        ZStack {
            // The actual user canvas, not a hardcoded wallpaper. Contrast marks
            // beneath the card make blur/transparency observable on solid themes.
            if destination == .effect {
                HStack(spacing: 9) {
                    ForEach(0..<18, id: \.self) { index in
                        Rectangle().fill(index.isMultiple(of: 2) ? palette.accent.opacity(0.55) : palette.backgroundEnd)
                    }
                }.accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "book").foregroundStyle(palette.accent)
                    Text("标题与界面字体").font(AppFontStyle.headline.resolve(ThemeEditorFonts.resolved(settings.fontPostScriptName, manager: .shared)))
                        .foregroundStyle(palette.primary)
                }
                Text("辅助文字 · 卡片圆角与边框").appFont(.caption).foregroundStyle(palette.secondary)
                HStack {
                    Text("选中状态").appFont(.caption).padding(4).background(palette.selection, in: Capsule())
                    Spacer()
                    Text("按钮").appFont(.caption).padding(6).appGlass(in: Capsule(), tint: palette.accent)
                }.foregroundStyle(palette.primary)
            }.padding(14)
                .modifier(ShelfGlass(shape: RoundedRectangle(cornerRadius: palette.cardRadius), isCard: true))
                .padding(12)
        }.frame(minHeight: compactHeight)
    }
    private var summary: String {
        switch destination {
        case .tab:
            if #available(iOS 26.0, *) { return "原生 Tab 栏：点按切换；图标随草稿更新，文字布局由系统管理。" }
            return settings.tabStyle.title
        case .shelf: return "\(settings.shelfColumns)列 · 期望宽度\(Int(settings.coverWidth))pt；预览依可用宽度缩小。"
        case .cover: return settings.defaultCoverImage == nil ? "系统默认封面" : "所选默认封面 · 实际比例裁切"
        case .launch: return "无跳过按钮 · 启动约1.2秒自动结束；可在下方全屏试播。"
        case .colors: return "\(scheme == .dark ? "深色" : "浅色")配色 · " + ThemeEditorFonts.name(settings.fontPostScriptName, manager: .shared)
        case .background: return settings.pageBackgroundImage == nil ? theme.backgroundStyle.title : "已选背景图片 · 与实际页面相同的显示方式"
        case .effect: return "\(settings.effect.title) · 光晕\(Int(settings.glowIntensity * 100))% · 透明\(Int((1-settings.surfaceOpacity)*100))%"
        case .cards: return "\(settings.cardBackground ? "显示" : "隐藏")卡片 · 圆角\(Int(palette.cardRadius))pt · \(palette.cardBorder ? "有" : "无")边框"
        }
    }
}
