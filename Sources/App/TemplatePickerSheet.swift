import SwiftUI

/// 选模板：一屏一个模板，带真实观感的预览缩略图。
///
/// 预览数据来自 `DiscoverPreviewCatalog`（公有领域书目）+ `PreviewCoverArt`（现画封面），
/// 不联网、不需要书源，打开就能看到版式的真实样子。
/// 选中一个模板后才进入「选书源 → 选分类」。
struct TemplatePickerSheet: View {
    @ThemePalette private var palette
    @Environment(\.dismiss) private var dismiss
    var onConfirm: ([CustomDiscoverEntry]) -> Void

    @State private var selected: DiscoverTemplateKind?
    @State private var showSourcePicker = false

    var body: some View {
        NavigationStack {
            ScrollView {
                if let selected {
                    // 第二步：选书源
                    sourceStep(selected)
                } else {
                    templateStep
                }
            }
            .background { AppThemeCanvas().ignoresSafeArea() }
            .navigationTitle(selected == nil ? "选择模板" : "选择数据源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                if selected != nil {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            selected = nil
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                    }
                }
            }
            .sheet(isPresented: $showSourcePicker) {
                if let selected {
                    SourceAndCategoryPicker(template: selected) { entries in
                        onConfirm(entries)
                        showSourcePicker = false
                    }
                }
            }
        }
    }

    // MARK: 第一步：模板列表（带预览）

    private var templateStep: some View {
        LazyVStack(spacing: 16) {
            ForEach(DiscoverTemplate.all) { template in
                Button {
                    if template.kind.dataSource == .readingProgress {
                        // 继续阅读不依赖书源，直接添加
                        onConfirm([CustomDiscoverEntry(
                            sourceUrl: "",
                            sourceName: "书架",
                            kindTitle: "继续阅读",
                            kindUrl: "history://shelf",
                            template: .history,
                            count: DiscoverTemplate.template(for: .history).defaultCount
                        )])
                        dismiss()
                    } else {
                        selected = template.kind
                        showSourcePicker = true
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 7) {
                            Image(systemName: DiscoverTemplateIcon.symbol(template.kind))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(palette.accent)
                            Text(template.title)
                                .appFont(.system(size: 16, weight: .semibold))
                                .foregroundStyle(palette.primary)
                            Spacer(minLength: 0)
                            Text(template.detail)
                                .appFont(.system(size: 11))
                                .foregroundStyle(palette.secondary)
                                .lineLimit(1)
                        }

                        // 预览
                        DiscoverTemplateThumbnail(kind: template.kind)
                            .padding(10)
                            .background {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(palette.primary.opacity(0.035))
                            }
                    }
                    .padding(12)
                    .background {
                        ThemeSurface(shape: RoundedRectangle(cornerRadius: 16, style: .continuous), isCard: true)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("template.pick.\(template.kind.rawValue)")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: 第二步：选书源

    private func sourceStep(_ kind: DiscoverTemplateKind) -> some View {
        VStack(spacing: 16) {
            // 选定模板的预览，确认没选错
            VStack(alignment: .leading, spacing: 8) {
                Text("已选：\(kind.title)")
                    .appFont(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.primary)
                DiscoverTemplateThumbnail(kind: kind)
                    .padding(10)
                    .background {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(palette.primary.opacity(0.035))
                    }
            }
            .padding(12)
            .background {
                ThemeSurface(shape: RoundedRectangle(cornerRadius: 16, style: .continuous), isCard: true)
            }

            Button {
                showSourcePicker = true
            } label: {
                HStack {
                    Label("选择书源与分类", systemImage: "square.stack.3d.up")
                        .appFont(.system(size: 15, weight: .semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(palette.primary)
                .padding(.horizontal, 16)
                .frame(height: 54)
                .background {
                    ThemeSurface(shape: RoundedRectangle(cornerRadius: 14, style: .continuous), isCard: true)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}
