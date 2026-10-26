import SwiftUI

/// 章节标题样式：直接写一小段 CSS，下面实时预览。
/// 空内容 = 默认外观（跟随主题、居中、稍大一号的半粗体）。
struct ChapterTitleStyleEditor: View {
    @ObservedObject var settings: ReadSettings
    @ThemePalette private var palette
    @State private var draft: String = ""
    @State private var loaded = false
    @FocusState private var editing: Bool

    private var style: ChapterTitleStyle { ChapterTitleStyle.parse(draft) }

    private let presets: [(title: String, css: String)] = [
        ("默认", ""),
        ("居中加粗", "font-weight: 700; text-align: center; letter-spacing: 1px;"),
        ("左对齐", "text-align: left; letter-spacing: 0.5px;"),
        ("下划线", "text-decoration: underline;"),
        ("细底边", "padding-bottom: 10px; border-bottom: 1px solid rgba(128,128,128,0.4);"),
        ("大标题", "font-size: 1.3em; letter-spacing: 2px;"),
        ("灰色小字", "font-size: 0.85em; color: #8a8a8a; letter-spacing: 2px;")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                preview
                presetsView
                editor
                help
            }
            .padding(16)
        }
        .scrollContentBackground(.hidden)
        .background { AppThemeCanvas().ignoresSafeArea() }
        .navigationTitle("章节标题样式")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("完成") { editing = false }
                    .accessibilityIdentifier("chapterTitle.done")
            }
        }
        .task {
            guard !loaded else { return }
            draft = settings.chapterTitleCSS
            loaded = true
        }
        .onChange(of: draft) { value in
            // 键盘每敲一个字就写回：阅读器那边只重排版式，不会整章重抓。
            guard loaded else { return }
            settings.chapterTitleCSS = value
        }
    }

    // MARK: 预览

    private var preview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("预览")
                .appFont(.footnote.weight(.semibold))
                .foregroundStyle(palette.secondary)
            VStack(alignment: .leading, spacing: 12) {
                ChapterTitleView(title: "第一章 空屋", fontSize: CGFloat(settings.fontSize),
                                 color: UIColor(palette.primary), style: style)
                    .frame(maxWidth: .infinity)
                Text("　　那年，我离开家乡，跟着堂嫂来到港城打工。")
                    .appFont(.system(size: CGFloat(settings.fontSize)))
                    .foregroundStyle(palette.primary.opacity(0.9))
                    .lineSpacing(CGFloat(settings.lineSpacingPoints))
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(palette.surface)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(palette.primary.opacity(0.08))
            }
        }
    }

    // MARK: 预设

    private var presetsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("预设")
                .appFont(.footnote.weight(.semibold))
                .foregroundStyle(palette.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(presets, id: \.title) { preset in
                        Button {
                            draft = preset.css
                            settings.chapterTitleCSS = preset.css
                        } label: {
                            Text(preset.title)
                                .appFont(.footnote)
                                .foregroundStyle(palette.primary)
                                .padding(.horizontal, 12)
                                .frame(height: 32)
                                .background { AppGlassSurface(shape: Capsule(), tint: palette.surface) }
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("chapterTitle.preset.\(preset.title)")
                    }
                }
            }
        }
    }

    // MARK: 编辑

    private var editor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("CSS")
                    .appFont(.footnote.weight(.semibold))
                    .foregroundStyle(palette.secondary)
                Spacer()
                if !draft.isEmpty {
                    Button("清空") {
                        draft = ""
                        settings.chapterTitleCSS = ""
                    }
                    .appFont(.footnote)
                    .accessibilityIdentifier("chapterTitle.clear")
                }
            }
            TextEditor(text: $draft)
                .appFont(.system(size: 14, design: .monospaced))
                .foregroundStyle(palette.primary)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 140)
                .padding(10)
                .background {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(palette.surface)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(palette.primary.opacity(editing ? 0.28 : 0.08))
                }
                .focused($editing)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityIdentifier("chapterTitle.css")
            if draft.isEmpty {
                Text("留空使用默认样式。")
                    .appFont(.caption)
                    .foregroundStyle(palette.secondary)
            }
        }
    }

    private var help: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("支持的属性")
                .appFont(.footnote.weight(.semibold))
                .foregroundStyle(palette.secondary)
            Text("""
            font-size（px / pt / em / %）、font-weight、font-style、
            color、background-color、text-align、letter-spacing、line-height、
            text-decoration、text-transform、opacity、
            margin-top / margin-bottom、padding、border-bottom
            """)
            .appFont(.caption)
            .foregroundStyle(palette.secondary)
            .accessibilityIdentifier("chapterTitle.help")
        }
    }
}
