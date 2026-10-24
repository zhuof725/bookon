import SwiftUI

/// 多分类竖排榜：一排可切换的分类标签，下面是该分类的竖排榜单。
///
/// 参照图一：标签是胶囊（选中填色），右边一个圆形箭头；每个分类一屏 4-5 条，
/// 每条 = 序号徽章 + 封面 + 书名 / 作者 / 简介。
///
/// 数据来源：添加板块时勾选的那几个分类。每个分类各自拉一次书单，
/// 切换标签就是换一份数据，不重新请求已经拿到过的分类。
struct DiscoverMultiRankSection: View {
    @ThemePalette private var palette
    let title: String
    let moreTitle: String
    /// 勾选过的分类（按用户勾选顺序）
    let kinds: [MultiRankKind]
    /// 这些分类属于哪个书源；nil 表示预览（用内置示例数据，不联网）
    let source: BookSource?
    var onMore: (() -> Void)? = nil
    var onSelect: (DeckItem, Int) -> Void = { _, _ in }

    @State private var selected: String
    /// 每个分类的榜单数据与加载状态
    @State private var loaded: [String: [DeckItem]] = [:]
    @State private var loading: Set<String> = []
    @State private var failed: Set<String> = []

    init(title: String,
         moreTitle: String,
         kinds: [MultiRankKind],
         source: BookSource?,
         onMore: (() -> Void)? = nil,
         onSelect: @escaping (DeckItem, Int) -> Void = { _, _ in }) {
        self.title = title
        self.moreTitle = moreTitle
        self.kinds = kinds
        self.source = source
        self.onMore = onMore
        self.onSelect = onSelect
        _selected = State(initialValue: kinds.first?.url ?? "")
    }

    private var currentKind: MultiRankKind? {
        kinds.first { $0.url == selected } ?? kinds.first
    }
    private var currentItems: [DeckItem] { loaded[selected] ?? [] }
    private var isLoadingCurrent: Bool { loading.contains(selected) }
    private var isFailedCurrent: Bool { failed.contains(selected) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            tabs
            content
        }
        .padding(.bottom, 18)
        .task(id: selected) { await loadCurrentIfNeeded() }
    }

    // MARK: 标题行

    @ViewBuilder private var header: some View {
        if !title.isEmpty || onMore != nil {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .appFont(.system(size: 20, weight: .bold))
                    .foregroundStyle(palette.primary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let onMore {
                    Button(action: onMore) {
                        Text(moreTitle)
                            .appFont(.system(size: 13))
                            .foregroundStyle(palette.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: 分类标签

    private var tabs: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(kinds.enumerated()), id: \.offset) { pair in
                        tab(pair.element, index: pair.offset)
                            .id(pair.offset)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 2)
            }
            .onChange(of: selected) { _, _ in
                if let index = kinds.firstIndex(where: { $0.url == selected }) {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(index, anchor: .center)
                    }
                }
            }
        }
    }

    private func tab(_ kind: MultiRankKind, index: Int) -> some View {
        let on = kind.url == selected
        return Button {
            guard !on else { return }
            selected = kind.url
        } label: {
            Text(kind.title)
                .appFont(.system(size: 15, weight: on ? .semibold : .regular))
                .foregroundStyle(on ? palette.onAccent : palette.primary)
                .padding(.horizontal, 16)
                .frame(height: 36)
                .background {
                    if on {
                        Capsule().fill(palette.accent)
                    } else {
                        Capsule().fill(palette.primary.opacity(0.06))
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("multirank.tab.\(kind.title)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: 榜单内容

    @ViewBuilder private var content: some View {
        if kinds.isEmpty {
            Text("没有选择分类")
                .appFont(.system(size: 12))
                .foregroundStyle(palette.secondary)
                .padding(.horizontal, 20)
        } else if isFailedCurrent {
            HStack(spacing: 10) {
                Text("加载失败").appFont(.system(size: 12)).foregroundStyle(palette.secondary)
                Button("重试") {
                    failed.remove(selected)
                    Task { await load(force: true) }
                }
                .appFont(.system(size: 12, weight: .semibold))
            }
            .padding(.horizontal, 20)
        } else if currentItems.isEmpty && isLoadingCurrent {
            VStack(spacing: 10) {
                ForEach(0..<4, id: \.self) { _ in skeletonRow }
            }
            .padding(.horizontal, 20)
        } else if currentItems.isEmpty {
            Text("这个分类没有内容")
                .appFont(.system(size: 12))
                .foregroundStyle(palette.secondary)
                .padding(.horizontal, 20)
        } else {
            VStack(spacing: 14) {
                ForEach(Array(currentItems.enumerated()), id: \.element.id) { pair in
                    Button { onSelect(pair.element, pair.offset) } label: {
                        row(pair.element, rank: pair.offset + 1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("multirank.item.\(pair.element.id)")
                }
            }
            .padding(.horizontal, 20)
        }
    }

    /// 一条榜单：序号徽章 + 封面 + 书名 / 作者 / 简介（参照图一的排法）。
    private func row(_ item: DeckItem, rank: Int) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Color.clear
                .frame(width: 52, height: 70)
                .overlay { DeckCoverImage(url: item.cover) }
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .appFont(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if !item.caption.isEmpty {
                    Text(item.caption)
                        .appFont(.system(size: 12))
                        .foregroundStyle(palette.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 6)

            Text("\(rank)")
                .appFont(.system(size: 15, weight: .bold))
                .foregroundStyle(rank <= 3 ? .white : palette.secondary)
                .frame(width: 26, height: 26)
                .background {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(rank <= 3 ? palette.accent : palette.primary.opacity(0.08))
                }
        }
        .contentShape(Rectangle())
    }

    private var skeletonRow: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(palette.primary.opacity(0.06))
                .frame(width: 52, height: 70)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 3).fill(palette.primary.opacity(0.07))
                    .frame(height: 12)
                RoundedRectangle(cornerRadius: 3).fill(palette.primary.opacity(0.05))
                    .frame(width: 80, height: 10)
            }
            Spacer(minLength: 0)
        }
        .redacted(reason: .placeholder)
    }

    // MARK: 数据

    private func loadCurrentIfNeeded() async {
        guard !currentItems.isEmpty || isLoadingCurrent else {
            await load()
            return
        }
    }

    private func load(force: Bool = false) async {
        guard let kind = currentKind else { return }
        if !force, loaded[kind.url] != nil { return }
        // 预览模式（没有书源）：用示例数据，不联网，也能切换标签看效果
        guard let source else {
            loaded[kind.url] = MultiRankPreview.items(for: kind, index: kinds.firstIndex(of: kind) ?? 0)
            return
        }
        guard !loading.contains(kind.url) else { return }
        // 命中共享缓存就不必再等网络
        if let hit = MultiRankLoader.cached(sourceUrl: source.bookSourceUrl, kindUrl: kind.url) {
            loaded[kind.url] = hit
            return
        }
        loading.insert(kind.url)
        failed.remove(kind.url)
        defer { loading.remove(kind.url) }
        let result = await MultiRankLoader.load(kind, source: source)
        if let result {
            loaded[kind.url] = result
        } else {
            failed.insert(kind.url)
        }
    }
}


/// 多分类竖排榜在「添加模板」预览里的示例数据。
/// 不联网、瞬间出图，只为让人看清版式。
enum MultiRankPreview {
    /// 每个标签给一组不同的书，切标签能看出内容真的变了。
    /// 封面用 `preview://` 自绘地址，不请求网络。
    static func items(for kind: MultiRankKind, index: Int) -> [DeckItem] {
        DiscoverPreviewCatalog.cards(count: 12)
            .enumerated()
            .filter { $0.offset % 3 == index % 3 }
            .map { offset, card in
                DeckItem(id: "\(kind.url)#\(offset)",
                         title: card.title,
                         caption: card.caption,
                         cover: card.cover)
            }
    }
}
