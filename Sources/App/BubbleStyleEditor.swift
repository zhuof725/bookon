import SwiftUI
import PhotosUI
import ImageIO
import UIKit

struct BubbleStyleSettingsView: View {
    @ObservedObject var store = BubbleStyleStore.shared
    @State private var draft: BubbleStyle?
    @State private var deleting: BubbleStyle?
    @State private var error: String?
    var body: some View {
        List {
            Section {
                Button { perform { try store.select(nil) } } label: {
                    HStack { Text("默认气泡"); Spacer(); if store.selectedID == nil { Image(systemName: "checkmark") } }
                }.accessibilityIdentifier("bubble.default")
            }
            ForEach(store.styles) { style in
                HStack {
                    Button { perform { try store.select(style.id) } } label: {
                        HStack {
                            Image(uiImage: BubbleStyleRenderer.image(style: style, count: 42, fontSize: 23, color: .label))
                            Text(style.name)
                            if store.selectedID == style.id { Image(systemName: "checkmark") }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.borderless)
                    Button("编辑") { draft = style }.buttonStyle(.borderless)
                    Button(role: .destructive) { deleting = style } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
                }
            }
            Section {
                Button("新建气泡") { draft = BubbleStyle() }.accessibilityIdentifier("bubble.new")
                Text("选中的样式应用到所有书源的原生段评气泡，不改变评论点击行为。书源完整图片卡片保持原样。")
                    .font(.footnote).foregroundStyle(.secondary)
                if let error { Text(error).foregroundStyle(.red) }
            }
        }
        .navigationTitle("段评气泡")
        .sheet(item: $draft) { style in BubbleStyleEditor(store: store, draft: style) }
        .alert("删除这个气泡样式？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("取消", role: .cancel) { deleting = nil }
            Button("删除", role: .destructive) { if let deleting { perform { try store.delete(deleting.id) } }; deleting = nil }
        } message: { Text("删除正在使用的样式后会恢复默认气泡。") }
    }
    private func perform(_ work: () throws -> Void) { do { try work(); error = nil } catch { self.error = error.localizedDescription } }
}

struct BubbleStyleEditor: View {
    @ObservedObject var store: BubbleStyleStore
    @State var draft: BubbleStyle
    @Environment(\.dismiss) private var dismiss
    @State private var photo: PhotosPickerItem?
    @State private var error: String?
    @State private var importing = false
    private var customColor: Binding<Color> {
        Binding(get: { Color(uiColor: BubbleStyleRenderer.hex(draft.colorHex)) }, set: { value in
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            if UIColor(value).getRed(&r, green: &g, blue: &b, alpha: &a) {
                draft.colorHex = String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
            }
        })
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("样式名称") { TextField("自定义气泡", text: $draft.name).accessibilityIdentifier("bubble.name") }
                Section("创建方式") {
                    Picker("创建方式", selection: $draft.mode) {
                        Text("模板").tag("template"); Text("SVG").tag("svg"); Text("图片").tag("image")
                    }.pickerStyle(.segmented)
                }
                if draft.mode == "template" {
                    Section("模板") {
                        Picker("模板", selection: $draft.template) {
                            Text("气泡").tag("bubble"); Text("白色糖果").tag("candy"); Text("方泡").tag("square")
                        }.pickerStyle(.segmented)
                        Text("气泡：简洁轮廓；白色糖果：白底黑边、深灰数字；方泡：方形轮廓和左下尾巴。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } else if draft.mode == "svg" {
                    Section("SVG 背景") {
                        TextEditor(text: $draft.svg).font(.system(.caption, design: .monospaced)).frame(minHeight: 150)
                            .accessibilityIdentifier("bubble.svg")
                        Button("填入示例") { draft.svg = "<svg viewBox=\"0 0 40 30\"><rect x=\"2\" y=\"2\" width=\"36\" height=\"26\" rx=\"9\" fill=\"none\" stroke=\"currentColor\"/></svg>" }
                        Text("仅支持静态背景：rect/circle/ellipse/line/polygon/polyline/path（M L H V C Q Z）。颜色用 #RRGGBB 或 currentColor。暂不支持分组、变换、文字、渐变、脚本、外链或嵌入图片；不支持的内容会提示错误，不会加载网络。数字由下方格式绘制。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } else {
                    Section("背景图片") {
                        PhotosPicker("从相册选择背景图", selection: $photo, matching: .images)
                        if importing { ProgressView("正在导入…") }
                        Text("建议透明 PNG。导入后缩小至 512 像素并保留透明度，原相册图片不修改。最大原图 8 MB。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section("文字与数字") {
                    Toggle("显示评论数字", isOn: $draft.showNumber)
                    TextField("显示格式，可用 {n} 代表评论数", text: $draft.format).accessibilityIdentifier("bubble.format")
                    Toggle("文字颜色跟随正文", isOn: $draft.followText)
                    if !draft.followText { ColorPicker("自定义颜色", selection: customColor, supportsOpacity: false) }
                }
                Section("尺寸") {
                    HStack { Text("整体大小"); Spacer(); Text(String(format: "%.2fx", draft.scale)) }
                    Slider(value: $draft.scale, in: 0.6...1.8, step: 0.05).accessibilityIdentifier("bubble.scale")
                    HStack { Text("宽高比"); Spacer(); Text(String(format: "%.2fx", draft.aspect)) }
                    Slider(value: $draft.aspect, in: 0.6...2, step: 0.05)
                }
                if let warning = BubbleStyleStore.validate(draft) { Section { Text(warning).foregroundStyle(.orange) } }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }
            .safeAreaInset(edge: .top) {
                VStack(spacing: 8) {
                    if BubbleStyleStore.validate(draft) == nil {
                        Image(uiImage: BubbleStyleRenderer.image(style: draft, count: 42, fontSize: 32, color: .label))
                            .accessibilityLabel("气泡实时预览，评论数 42").accessibilityIdentifier("bubble.preview")
                    } else { Image(systemName: "bubble.right").font(.largeTitle) }
                    Text(draft.name).font(.headline)
                    Text("显示 42 · 保存后选用，取消不改变原设置").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity).padding(12).background(.regularMaterial)
            }
            .navigationTitle("新建/编辑气泡").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        do { try store.save(draft); try store.select(draft.id); dismiss() }
                        catch { self.error = error.localizedDescription }
                    }.disabled(importing || BubbleStyleStore.validate(draft) != nil).accessibilityIdentifier("bubble.save")
                }
            }
            .task(id: photo) {
                guard let photo else { return }
                importing = true
                defer { importing = false }
                do {
                    guard let data = try await photo.loadTransferable(type: Data.self), data.count <= 8_000_000,
                          let src = CGImageSourceCreateWithData(data as CFData, nil),
                          let image = CGImageSourceCreateThumbnailAtIndex(src, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 512, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary),
                          let png = UIImage(cgImage: image).pngData(), png.count <= 2_000_000 else {
                        error = "图片无效或超过大小限制，请选择其他图片"; return
                    }
                    try Task.checkCancellation()
                    draft.imageData = png; error = nil
                } catch is CancellationError {} catch { self.error = error.localizedDescription }
            }
        }
    }
}
