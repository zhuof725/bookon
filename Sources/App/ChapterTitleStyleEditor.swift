import SwiftUI

/// 章节标题样式：常用项直接调（字号 / 字重 / 位置），需要时再打开「高级 CSS」写样式。
/// 高级 CSS 覆盖在简单设置之上：CSS 写了哪一项就换哪一项。
struct ChapterTitleStyleEditor: View {
    @ObservedObject var settings: ReadSettings
    @ThemePalette private var palette
    @State private var draft: String = ""
    @State private var loaded = false
    @State private var size: Double = 0
    @State private var weight: Int = 600
    @State private var align: String = "center"
    @State private var advanced = false
    @FocusState private var editing: Bool

    private var cssStyle: ChapterTitleStyle { ChapterTitleStyle.parse(draft) }

    private var effective: ChapterTitleStyle {
        var style = ChapterTitleStyle.simple(size: size, weight: weight, alignment: align)
        if advanced { style.merge(cssStyle) }
        return style
    }

    private let weights: [(title: String, value: Int)] = [
        ("常规", 400), ("中粗", 500), ("半粗", 600), ("粗体", 700)
    ]

    private let alignments: [(title: String, value: String)] = [
        ("居左", "left"), ("居中", "center"), ("居右", "right")
    ]

    private let presets: [(title: String, css: String)] = [
        ("默认", ""),
        ("下划线", "text-decoration: underline;"),
        ("细底边", "padding-bottom: 10px; border-bottom: 1px solid rgba(128,128,128,0.4);"),
        ("大标题", "font-size: 1.3em; letter-spacing: 2px;"),
        ("灰色小字", "font-size: 0.85em; color: #8a8a8a; letter-spacing: 2px;"),
        ("左右留白", "padding: 6px 12px; background-color: rgba(128,128,128,0.12);"),
        ("行高宽松", "line-height: 1.6; letter-spacing: 1px;")
    ]

    var body: some View {
        Form {
            Section {
                preview
                    .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                    .listRowBackground(Color.clear)
            }

            Section {
                VStack(spacing: 6) {
                    HStack {
                        Text("字号")
                        Spacer()
                        Text(size <= 0 ? "跟随正文" : "\(Int(size)) pt")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("chapterTitle.sizeValue")
                    }
                    Slider(value: $size, in: 0...36, step: 1)
                        .accessibilityLabel("字号")
                        .accessibilityIdentifier("chapterTitle.size")
                }
                Picker("字重", selection: $weight) {
                    ForEach(weights, id: \.value) { item in Text(item.title).tag(item.value) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("chapterTitle.weight")
                Picker("位置", selection: $align) {
                    ForEach(alignments, id: \.value) { item in Text(item.title).tag(item.value) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("chapterTitle.align")
            } header: {
                Text("标题样式")
            } footer: {
                Text("字号选「跟随正文」时按正文字号自动放大两号；字重与位置对分页、滚动两种模式都生效。")
            }

            Section {
                Toggle("高级 CSS", isOn: $advanced)
                    .accessibilityIdentifier("chapterTitle.advanced")
            } footer: {
                Text("打开后用一段 CSS 覆盖上面的设置。支持 font-size、font-weight、color、background-color、text-align、letter-spacing、line-height、text-decoration、padding、border-bottom 等；可以直接粘带选择器的规则，只取花括号里的声明。")
            }

            if advanced {
                Section {
                    TextEditor(text: $draft)
                        .appFont(.system(size: 14, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 130)
                        .focused($editing)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .accessibilityIdentifier("chapterTitle.css")
                } header: {
                    HStack {
                        Text("CSS")
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
                } footer: {
                    if cssStyle.isEmpty {
                        Text("留空则只用上面的简单设置。")
                    } else {
                        Text("示例：color: #333; font-size: 22px; text-align: left; border-bottom: 1px solid #ddd;")
                    }
                }

                Section("预设") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(presets, id: \.title) { preset in
                                Button {
                                    draft = preset.css
                                    settings.chapterTitleCSS = preset.css
                                } label: {
                                    Text(preset.title)
                                        .appFont(.footnote)
                                        .padding(.horizontal, 12)
                                        .frame(height: 30)
                                        .background { AppGlassSurface(shape: Capsule(), tint: palette.surface) }
                                        .contentShape(Capsule())
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("chapterTitle.preset.\(preset.title)")
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            Section {
                Button("恢复默认样式", role: .destructive) { resetToDefault() }
                    .accessibilityIdentifier("chapterTitle.reset")
            } footer: {
                Text("标题恢复成跟随主题的居中半粗体，并关闭高级 CSS。")
            }
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
            size = settings.chapterTitleSize
            weight = settings.chapterTitleWeight
            align = settings.chapterTitleAlign
            advanced = settings.chapterTitleAdvanced
            loaded = true
        }
        .onChange(of: draft) { value in
            guard loaded else { return }
            settings.chapterTitleCSS = value
        }
        .onChange(of: size) { value in guard loaded else { return }; settings.chapterTitleSize = value }
        .onChange(of: weight) { value in guard loaded else { return }; settings.chapterTitleWeight = value }
        .onChange(of: align) { value in guard loaded else { return }; settings.chapterTitleAlign = value }
        .onChange(of: advanced) { value in guard loaded else { return }; settings.chapterTitleAdvanced = value }
    }

    private func resetToDefault() {
        draft = ""
        size = 0
        weight = 600
        align = "center"
        advanced = false
        settings.chapterTitleCSS = ""
        settings.chapterTitleSize = 0
        settings.chapterTitleWeight = 600
        settings.chapterTitleAlign = "center"
        settings.chapterTitleAdvanced = false
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 10) {
            ChapterTitleView(title: "第一章 空屋", fontSize: CGFloat(settings.fontSize),
                             color: UIColor(palette.primary), style: effective)
                .frame(maxWidth: .infinity)
            Text("　　那年，我离开家乡，跟着堂嫂来到港城打工。")
                .appFont(.system(size: CGFloat(settings.fontSize)))
                .foregroundStyle(palette.primary.opacity(0.9))
                .lineSpacing(CGFloat(settings.lineSpacingPoints))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: AppLayout.radiusCard, style: .continuous).fill(palette.surface)
        }
        .overlay {
            RoundedRectangle(cornerRadius: AppLayout.radiusCard, style: .continuous)
                .strokeBorder(palette.primary.opacity(0.08))
        }
    }
}
