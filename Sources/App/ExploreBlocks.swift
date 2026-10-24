import SwiftUI

/// 「探索」页的一张板块卡片：按配置的版式，把书源分类的书单排成参考图的样式。
struct ExploreBoardCard: View {
    @ThemePalette private var palette
    @ObservedObject var store: ExploreStore
    let board: ExploreBoard
    var onEdit: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    @State private var tab = 0

    private var categories: [ExploreCategory] { board.visibleCategories }
    private var activeTab: Int {
        guard !categories.isEmpty else { return 0 }
        return min(max(tab, 0), categories.count - 1)
    }

    /// 当前正在看的分类：带标签的版式跟随选中标签，其余用第一个分类。
    private var activeCategory: ExploreCategory? {
        guard !categories.isEmpty else { return nil }
        if board.layout.supportsTabs { return categories[activeTab] }
        return categories.first
    }

    private var books: [Book] {
        guard let activeCategory else { return [] }
        return store.books(for: activeCategory) ?? []
    }

    private var visibleBooks: [Book] { board.visibleBooks(books) }

    private var isLoading: Bool {
        guard let activeCategory else { return false }
        return store.isLoading(activeCategory) || store.isIdle(activeCategory)
    }

    private var hasFailed: Bool {
        guard let activeCategory else { return false }
        return store.hasFailed(activeCategory)
    }

    var body: some View {
        Group {
            if board.layout == .forYou {
                forYouLayout
            } else {
                ExploreCard {
                    header
                    content
                }
            }
        }
        .task(id: activeCategory?.key) {
            guard let activeCategory else { return }
            await store.load(activeCategory)
        }
        .contextMenu {
            if let onEdit {
                Button { onEdit() } label: { Label("编辑板块", systemImage: "slider.horizontal.3") }
            }
            if let onDelete {
                Button(role: .destructive) { onDelete() } label: { Label("删除板块", systemImage: "trash") }
            }
        }
        .accessibilityIdentifier("explore.board.\(board.id)")
    }

    // MARK: - 页头

    @ViewBuilder private var header: some View {
        switch board.layout {
        case .bestseller, .coverGrid:
            ExploreCardHeader(title: board.displayTitle, more: board.moreCategory)
        case .rankColumns, .categoryFeed:
            ExploreTabHeader(titles: categories.map(\.title),
                             selection: activeTab,
                             more: activeCategory) { index in
                tab = index
            }
        case .newBookRank:
            VStack(alignment: .leading, spacing: 12) {
                ExploreCardHeader(title: board.displayTitle,
                                  subtitle: board.displaySubtitle,
                                  more: activeCategory)
                chipRow
            }
        case .forYou:
            EmptyView()
        }
    }

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(categories.enumerated()), id: \.element.id) { index, category in
                    ExploreChip(text: category.title, selected: index == activeTab) {
                        tab = index
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - 内容

    @ViewBuilder private var content: some View {
        if categories.isEmpty {
            Text("这个板块还没有选分类。长按卡片可以编辑。")
                .appFont(.footnote)
                .foregroundStyle(palette.secondary)
                .padding(.vertical, 6)
        } else if hasFailed {
            ExploreStateRow(loading: false, failed: true, onRetry: retry)
        } else if visibleBooks.isEmpty {
            ExploreStateRow(loading: isLoading, failed: false)
        } else {
            switch board.layout {
            case .bestseller:
                bestsellerList
            case .coverGrid:
                coverGrid
            case .rankColumns:
                rankColumns
            case .newBookRank:
                newBookList
            case .categoryFeed:
                categoryFeedList
            case .forYou:
                EmptyView()
            }
        }
    }

    private func retry() {
        guard let activeCategory else { return }
        Task { await store.load(activeCategory, force: true) }
    }

    // MARK: - 畅销精选

    private var bestsellerList: some View {
        VStack(spacing: 18) {
            ForEach(Array(visibleBooks.prefix(board.count).enumerated()), id: \.element.id) { _, book in
                ExploreBookLink(book: book) {
                    ExploreBestsellerRow(book: book, fallbackTags: board.tags)
                }
            }
        }
    }

    // MARK: - 品质好书

    private var coverGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .topLeading), count: 4),
                  alignment: .leading, spacing: 14) {
            ForEach(visibleBooks.prefix(board.count)) { book in
                ExploreBookLink(book: book) {
                    VStack(alignment: .leading, spacing: 6) {
                        Color.clear
                            .aspectRatio(3.0 / 4.0, contentMode: .fit)
                            .overlay { ExploreCover(book: book) }
                            .frame(maxWidth: .infinity)
                        Text(book.name)
                            .appFont(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(palette.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if let kind = ExploreBookText.kind(book) {
                            Text(kind)
                                .appFont(.system(size: 10.5))
                                .foregroundStyle(palette.secondary)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 双列榜单

    private var rankColumns: some View {
        LazyVGrid(columns: twoColumns, alignment: .leading, spacing: 16) {
            ForEach(Array(visibleBooks.prefix(board.count).enumerated()), id: \.element.id) { index, book in
                ExploreBookLink(book: book) {
                    HStack(alignment: .top, spacing: 8) {
                        ExploreRankBadge(rank: index + 1)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(book.name)
                                .appFont(.system(size: 16, weight: .semibold))
                                .foregroundStyle(palette.primary)
                                .lineLimit(1)
                            if let intro = ExploreBookText.intro(book) {
                                Text(intro)
                                    .appFont(.system(size: 11.5))
                                    .foregroundStyle(palette.secondary)
                                    .lineLimit(1)
                                    .multilineTextAlignment(.leading)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: - 新书榜

    private var newBookList: some View {
        LazyVGrid(columns: twoColumns, alignment: .leading, spacing: 18) {
            ForEach(Array(visibleBooks.prefix(board.count).enumerated()), id: \.element.id) { index, book in
                ExploreBookLink(book: book) {
                    ExploreCoverRow(book: book,
                                    rank: index + 1,
                                    coverWidth: 56,
                                    coverHeight: 74,
                                    titleSize: 15.5,
                                    tags: board.tags)
                }
            }
        }
    }

    // MARK: - 分类推荐

    private var categoryFeedList: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(board.displaySubtitle ?? "根据你感兴趣的分类推荐")
                .appFont(.system(size: 12.5))
                .foregroundStyle(palette.secondary)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(palette.selection.opacity(0.5))
                }
            LazyVGrid(columns: twoColumns, alignment: .leading, spacing: 18) {
                ForEach(visibleBooks.prefix(board.count)) { book in
                    ExploreBookLink(book: book) {
                        ExploreCoverRow(book: book,
                                        rank: nil,
                                        coverWidth: 60,
                                        coverHeight: 80,
                                        titleSize: 15.5,
                                        tags: board.tags)
                    }
                }
            }
        }
    }

    // MARK: - 猜你喜欢

    private var forYouLayout: some View {
        VStack(alignment: .leading, spacing: 14) {
            ExploreCenteredTitle(title: board.displayTitle)
            if categories.isEmpty {
                Text("这个板块还没有选分类。长按标题可以编辑。")
                    .appFont(.footnote)
                    .foregroundStyle(palette.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if hasFailed {
                ExploreStateRow(loading: false, failed: true, onRetry: retry)
            } else if visibleBooks.isEmpty {
                ExploreStateRow(loading: isLoading, failed: false)
            } else {
                ForEach(visibleBooks.prefix(board.count)) { book in
                    ExploreForYouCard(book: book,
                                      reason: ExploreBookText.reason(book),
                                      tags: ExploreBookText.tags(book, fallback: board.tags)) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            store.hide(bookURL: book.bookUrl, in: board.id)
                        }
                    }
                }
            }
        }
    }

    private var twoColumns: [GridItem] {
        [GridItem(.flexible(), spacing: 14, alignment: .topLeading),
         GridItem(.flexible(), spacing: 14, alignment: .topLeading)]
    }
}

// MARK: - 行 / 卡

/// 畅销精选的一行：大封面 + 书名 + 两行简介 + 分类字数与标签。
struct ExploreBestsellerRow: View {
    @ThemePalette private var palette
    let book: Book
    let fallbackTags: [String]

    private var tags: [String] { ExploreBookText.tags(book, fallback: fallbackTags) }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ExploreCover(book: book)
                .frame(width: 76, height: 100)
            VStack(alignment: .leading, spacing: 6) {
                Text(book.name)
                    .appFont(.system(size: 17.5, weight: .semibold))
                    .foregroundStyle(palette.primary)
                    .lineLimit(1)
                if let intro = ExploreBookText.intro(book) {
                    Text(intro)
                        .appFont(.system(size: 12.5))
                        .foregroundStyle(palette.secondary)
                        .lineLimit(2)
                        .lineSpacing(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 5) {
                        metaText
                        Spacer(minLength: 6)
                        tagPills
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        metaText
                        tagPills
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder private var metaText: some View {
        if let meta = ExploreBookText.meta(book) {
            Text(meta)
                .appFont(.system(size: 11.5))
                .foregroundStyle(palette.secondary)
                .lineLimit(1)
        }
    }

    private var tagPills: some View {
        HStack(spacing: 5) {
            ForEach(Array(tags.prefix(3).enumerated()), id: \.offset) { index, tag in
                ExploreTagPill(text: tag, kind: index == 0 ? .warm : .plain)
            }
        }
    }
}

/// 带封面的双列行（新书榜 / 分类推荐）：可选的序号 + 书名 + 徽标 + 两行简介。
struct ExploreCoverRow: View {
    @ThemePalette private var palette
    let book: Book
    let rank: Int?
    let coverWidth: CGFloat
    let coverHeight: CGFloat
    let titleSize: CGFloat
    let tags: [String]

    private var bookTags: [String] { ExploreBookText.tags(book, fallback: tags) }

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            ExploreCover(book: book)
                .frame(width: coverWidth, height: coverHeight)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    if let rank {
                        ExploreRankNumber(rank: rank)
                    }
                    Text(book.name)
                        .appFont(.system(size: titleSize, weight: .semibold))
                        .foregroundStyle(palette.primary)
                        .lineLimit(1)
                }
                HStack(alignment: .top, spacing: 5) {
                    if let tag = bookTags.first {
                        ExploreTagPill(text: tag, kind: .hot)
                            .fixedSize()
                    }
                    if let intro = ExploreBookText.intro(book) {
                        Text(intro)
                            .appFont(.system(size: 11.5))
                            .foregroundStyle(palette.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: max(coverHeight, 66), alignment: .top)
        .contentShape(Rectangle())
    }
}

/// 猜你喜欢的一张卡：推荐理由 + 书目 + 关闭按钮。
struct ExploreForYouCard: View {
    @ThemePalette private var palette
    let book: Book
    let reason: String
    let tags: [String]
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                ExploreReasonText(reason: reason, size: 13.5)
                Spacer(minLength: 6)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(palette.secondary)
                        .frame(width: 22, height: 22)
                        .background { Circle().fill(palette.selection.opacity(0.55)) }
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("不感兴趣")
            }
            ExploreBookLink(book: book) {
                HStack(alignment: .top, spacing: 12) {
                    ExploreCover(book: book)
                        .frame(width: 78, height: 100)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(book.name)
                            .appFont(.system(size: 17, weight: .semibold))
                            .foregroundStyle(palette.primary)
                            .lineLimit(1)
                        if let intro = ExploreBookText.intro(book) {
                            Text(intro)
                                .appFont(.system(size: 12.5))
                                .foregroundStyle(palette.secondary)
                                .lineLimit(2)
                                .lineSpacing(1.5)
                                .multilineTextAlignment(.leading)
                        }
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 5) {
                                metaText
                                Spacer(minLength: 6)
                                tagPills
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                metaText
                                tagPills
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(palette.surface)
        }
    }

    @ViewBuilder private var metaText: some View {
        if let meta = ExploreBookText.meta(book) {
            Text(meta)
                .appFont(.system(size: 11))
                .foregroundStyle(palette.secondary)
                .lineLimit(1)
        }
    }

    private var tagPills: some View {
        HStack(spacing: 5) {
            ForEach(Array(tags.prefix(2).enumerated()), id: \.offset) { index, tag in
                ExploreTagPill(text: tag, kind: index == 0 ? .warm : .plain)
            }
        }
    }
}
