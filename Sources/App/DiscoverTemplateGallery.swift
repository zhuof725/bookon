import SwiftUI

// MARK: - 模板展示库

/// 模板展示库：一页往下滑，按「版式 / 视觉 / 阅读记录」分成几块，
/// 每个模板都按**真实尺寸**渲染一遍——看到什么样，加到首页就是什么样。
///
/// 点任意一个模板就选中它并返回，回到「添加板块」继续选书源和分类。
struct DiscoverTemplateLibrary: View {
    @ThemePalette private var palette
    @Environment(\.dismiss) private var dismiss

    /// 当前已选的模板，用来打勾。
    var current: DiscoverTemplateKind = .deck
    /// 选中某个模板。
    var onPick: (DiscoverTemplateKind) -> Void = { _ in }

    /// 预览用的书：公版书目，不联网、不涉及第三方素材。
    private let samples = DiscoverPreviewCatalog.cards(count: 5)

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 30) {
                intro
                ForEach(DiscoverTemplateFamily.allCases) { family in
                    module(family)
                }
                footer
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 48)
        }
        .background { AppThemeCanvas().ignoresSafeArea() }
        .foregroundStyle(palette.primary)
        .navigationTitle("模板展示库")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("template.library")
    }

    // MARK: 页首说明

    private var intro: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(DiscoverTemplate.all.count) 个模板")
                .appFont(.system(size: 22, weight: .bold))
            Text("每个模板按真实尺寸铺开。点任意一个，就用它去添加板块。")
                .appFont(.system(size: 12.5))
                .foregroundStyle(palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "hand.tap")
                .font(.system(size: 11))
            Text("模板只决定排版，内容仍然来自你选的书源分类。")
                .appFont(.system(size: 11.5))
        }
        .foregroundStyle(palette.secondary)
        .padding(.top, 4)
    }

    // MARK: 一个模块（一组模板）

    private func module(_ family: DiscoverTemplateFamily) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(family.title)
                        .appFont(.system(size: 17, weight: .bold))
                    Text("\(family.templates.count)")
                        .appFont(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(palette.primary.opacity(0.06), in: Capsule())
                    Spacer(minLength: 0)
                }
                Text(family.detail)
                    .appFont(.system(size: 11.5))
                    .foregroundStyle(palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(Array(family.templates.enumerated()), id: \.element.id) { pair in
                card(pair.element, number: pair.offset + 1)
            }
        }
    }

    // MARK: 一个模板

    private func card(_ template: DiscoverTemplate, number: Int) -> some View {
        let picked = template.kind == current
        return Button {
            onPick(template.kind)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 10) {
                    Text(String(format: "%02d", number))
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(picked ? palette.onAccent : palette.secondary)
                        .frame(width: 24, height: 20)
                        .background {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(picked ? palette.accent : palette.primary.opacity(0.07))
                        }
                        .padding(.top, 1)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(template.title)
                            .appFont(.system(size: 15, weight: .semibold))
                        Text(template.detail)
                            .appFont(.system(size: 11.5))
                            .foregroundStyle(palette.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 4)

                    if picked {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 17))
                            .foregroundStyle(palette.accent)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.top, 13)

                // 真身渲染：就是首页里那块板块的样子（不加额外内缩，宽度与首页一致）
                DiscoverTemplateView(
                    kind: template.kind,
                    title: previewTitle(for: template.kind),
                    moreTitle: "全部",
                    cards: samples,
                    history: historySamples,
                    count: 5,
                    onMore: {},
                    onSelectBook: { _ in },
                    onSelectHistory: { _ in }
                )
                .padding(.top, 10)
                .padding(.bottom, 4)
                .allowsHitTesting(false)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(palette.primary.opacity(picked ? 0.055 : 0.03))
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(picked ? palette.accent.opacity(0.7) : palette.primary.opacity(0.06),
                                  lineWidth: picked ? 1.5 : 0.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("library.template.\(template.kind.rawValue)")
        .accessibilityLabel("\(template.title)，\(template.detail)")
    }

    /// 预览里板块的假标题：像首页那样有个栏目名，才看得出排版节奏。
    private func previewTitle(for kind: DiscoverTemplateKind) -> String {
        switch kind {
        case .updateFeed: return "最近更新"
        case .history: return "继续阅读"
        case .rankRow: return "本周热榜"
        default: return "热门推荐"
        }
    }

    /// 记录模板要的进度数据，用同一批示例书编出来。
    private var historySamples: [HistoryItem] {
        DiscoverPreviewCatalog.samples.prefix(4).enumerated().map { index, sample in
            let total = 120 + index * 137
            let read = max(1, (total * (3 + index * 2)) / 10)
            return HistoryItem(
                id: "preview-history-\(index)",
                title: sample.title,
                chapterText: "读到 第 \(read) 章 · 共 \(total) 章",
                progress: Double(read) / Double(total),
                timeText: index == 0 ? "今天" : (index == 1 ? "昨天" : "\(index * 2) 天前"),
                actionText: index == 0 ? "继续阅读" : "从头开始"
            )
        }
    }
}

// MARK: - 单模板预览

/// 只渲染一个模板，用于调试或将来的详情页。
/// 不加载网络：传入什么就画什么。
struct DiscoverTemplatePreview: View {
    @ThemePalette private var palette
    let kind: DiscoverTemplateKind

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(kind.title).appFont(.headline)
                Text(kind.detail)
                    .appFont(.caption2)
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)

            DiscoverTemplateView(
                kind: kind,
                title: "预览",
                moreTitle: "全部",
                cards: DiscoverPreviewCatalog.cards(count: 9),
                history: [],
                count: 9
            )
            .padding(.top, 8)
            .allowsHitTesting(false)
        }
        .background { AppThemeCanvas().ignoresSafeArea() }
        .foregroundStyle(palette.primary)
    }
}

// MARK: - 「全部」页

/// 某个板块的全部内容：不限数量，用同一套模板继续往下渲染。
///
/// 传 `count: DiscoverTemplate.unlimited`，模板内部不截断，
/// 列表类模板（瀑布流 / 横滑 / 竖排）会一直往下铺；
/// 卡片类模板（弧形 / 堆叠）本身是翻看交互，按实际数量自己排。
struct DiscoverTemplateFullPage: View {
    @ThemePalette private var palette
    let kind: DiscoverTemplateKind
    let title: String
    let books: [Book]
    var history: [HistoryItem] = []
    var onSelectBook: (Book) -> Void = { _ in }
    var onSelectHistory: (HistoryItem) -> Void = { _ in }

    var body: some View {
        ScrollView {
            DiscoverTemplateView(
                kind: kind,
                title: "",
                moreTitle: "",
                books: books,
                history: history,
                count: DiscoverTemplate.unlimited,
                onMore: nil,
                onSelectBook: onSelectBook,
                onSelectHistory: onSelectHistory
            )
            .padding(.top, 8)
        }
        .background { AppThemeCanvas().ignoresSafeArea() }
        .foregroundStyle(palette.primary)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("template.full.\(kind.rawValue)")
    }
}
