import SwiftUI

// MARK: - 模板展示库

/// 模板展示库：一页往下滑，每个模板都按**真实尺寸**整屏铺开一遍，
/// 模板名称居中写在它下面。就是「加到首页会长什么样」的直接预览。
///
/// 点任意一个模板立刻用它添加板块——和参考图一样的分组成列浏览方式。
struct DiscoverTemplateLibrary: View {
    @ThemePalette private var palette
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore

    /// 当前已选的模板，用来打勾。
    var current: DiscoverTemplateKind = .deck
    /// 选中某个模板（调用方负责据此添加板块）。
    var onPick: (DiscoverTemplateKind) -> Void = { _ in }

    /// 展示库用的书：优先书架里的真实书籍（连封面一起），书架太空才回落到公版书目。
    ///
    /// 用真实书籍是关键——预览里看到的封面、书名、作者，和加到首页后完全一致。
    private var samples: [DeckItem] {
        let shelf = Array(store.books.prefix(12))
        if shelf.count >= 4 {
            return shelf.map { DeckItem(localCover: $0) }
        }
        return DiscoverPreviewCatalog.cards(count: 12)
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(DiscoverTemplate.all) { template in
                    section(template)
                }
                footNote
            }
            .padding(.bottom, 40)
        }
        .background { AppThemeCanvas().ignoresSafeArea() }
        .foregroundStyle(palette.primary)
        .navigationTitle("添加栏目")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("template.library")
    }

    // MARK: 一个模板 = 一块真实预览 + 居中名字

    private func section(_ template: DiscoverTemplate) -> some View {
        let picked = template.kind == current
        return Button {
            onPick(template.kind)
            dismiss()
        } label: {
            VStack(spacing: 0) {
                // 真身：与首页里那一块完全一致，标题留空（名字在下面居中显示）
                DiscoverTemplateView(
                    kind: template.kind,
                    title: "",
                    moreTitle: "",
                    cards: previewCards(for: template.kind),
                    history: historySamples,
                    count: previewCount(for: template.kind)
                )
                .allowsHitTesting(false)
                .padding(.top, 18)

                // 模板名：居中，选中时略加粗并用强调色
                Text(template.title)
                    .appFont(.system(size: 17, weight: picked ? .semibold : .regular))
                    .foregroundStyle(picked ? palette.accent : palette.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 14)
                    .padding(.bottom, 26)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("library.template.\(template.kind.rawValue)")
        .accessibilityLabel("\(template.title)，\(template.detail)")
    }

    /// 卡片型模板（弧形 / 堆叠）自带一行「书名 + 作者」说明，
    /// 展示库里它紧挨着居中的模板名，读起来会串行，所以这里把说明清空。
    private func previewCards(for kind: DiscoverTemplateKind) -> [DeckItem] {
        guard kind.isCardStage else { return samples }
        return samples.map { DeckItem(id: $0.id, title: $0.title, caption: "", cover: $0.cover) }
    }

    /// 预览里放几本：卡片型排太多会挤出屏，列表型多给几本才看得出节奏。
    private func previewCount(for kind: DiscoverTemplateKind) -> Int {
        switch kind {
        case .largeCard, .compactCard, .featureCard, .deck, .curve: return 6
        case .dualRow, .covers: return 12
        case .fixedList, .updateFeed: return 5
        case .history: return 4
        // 三列 / 大封面 / 榜单 / 瀑布默认多放几本；新增模板也走这里，不会漏分支。
        default: return 9
        }
    }

    private var footNote: some View {
        Text("点任意一个模板，就用它添加栏目")
            .appFont(.system(size: 11.5))
            .foregroundStyle(palette.secondary)
            .frame(maxWidth: .infinity)
            .padding(.top, 6)
    }

    /// 记录模板要的进度数据：优先用书架里真实的阅读进度和封面。
    private var historySamples: [HistoryItem] {
        let shelf = store.books.filter { $0.durChapterIndex > 0 }.prefix(4)
        if shelf.count >= 2 {
            return shelf.map { HistoryItem(localCover: $0, chapterCount: nil) }
        }
        // 书架没有进度数据时，用公版书目编一组，保证预览不是空的。
        return DiscoverPreviewCatalog.samples.prefix(4).enumerated().map { index, sample in
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
