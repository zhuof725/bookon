import SwiftUI
import UIKit

/// Live sample only: no navigation or progress writes. Reuses reader TextKit.
struct ReaderAppearancePreview: View {
    @ObservedObject var settings: ReadSettings
    @ObservedObject private var fonts = ReadingFontManager.shared
    @StateObject private var backgroundLoader = ThemeAssetImageLoader()
    private var paper: (bg: Color, fg: Color, name: String) { settings.currentPaper }
    private var modeTitle: String { settings.dayNightMode.title }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("阅读外观 · 实时预览").appFont(.caption.weight(.semibold))
            ScrollView {
                VStack(spacing: settings.paragraphSpacingPoints) {
                    paragraph("春风翻动书页，远处的山影渐渐清晰。调整字号、字体、行距与边距，立即查看文字效果。")
                    paragraph("这是预览文字，不会改变书籍内容或阅读进度。")
                }
                .padding(.leading, settings.leftMargin).padding(.trailing, settings.rightMargin)
                .padding(.top, settings.topMargin).padding(.bottom, settings.bottomMargin)
            }
            .frame(height: 130)
            .background {
                ZStack {
                    paper.bg
                    if let image = backgroundLoader.image {
                        Image(uiImage: image).resizable().scaledToFill()
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .task(id: settings.backgroundImageID) {
                await backgroundLoader.load(settings.usesImageBackground ? settings.backgroundImageID : nil)
            }
            Text("\(modeTitle) · \(paper.name) · \(Int(settings.fontSize))pt · \(fonts.selectedDisplayName)；此处为可滚动文字样例，整页齐底与翻页动画以阅读页为准。")
                .appFont(.caption2).foregroundStyle(.secondary).lineLimit(2)
        }.padding(12).modifier(SettingsGlassSurface())
            .accessibilityIdentifier("reader.appearance.preview")
    }
    private func paragraph(_ text: String) -> some View {
        InlineCommentParagraph(text: text, count: 0, fontSize: CGFloat(settings.fontSize),
            lineSpacing: CGFloat(settings.lineSpacingPoints), color: UIColor(paper.fg),
            fullJustify: settings.fullJustify, zhLayout: true, onTap: {})
            .id(fonts.selectedPostScriptName)
    }
}
