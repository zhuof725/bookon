import SwiftUI

/// 发现分类的板块：标题 +「查看全部」+ 前几本书预览。
/// 榜单类（含「榜 / 推荐 / 排行 / 热门 / 热搜」）用排名横条，其余用三列封面网格。
struct DiscoverSectionBlock: View {
    @ThemePalette private var palette
    let source: BookSource
    let kind: SourceDiagnostics.ExploreKind

    @State private var books: [Book] = []
    @State private var loading = true
    @State private var failed = false

    private var isRanking: Bool { DiscoverCatalog.isRankingTitle(kind.title) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(kind.title)
                    .appFont(.title3.weight(.bold))
                    .foregroundStyle(palette.primary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if let url = kind.url, !url.isEmpty {
                    NavigationLink {
                        DiscoverBooksView(source: source, kindTitle: kind.title, kindUrl: url)
                    } label: {
                        HStack(spacing: 3) {
                            Text("查看全部").appFont(.footnote)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundStyle(palette.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("discover.block.more.\(kind.title)")
                }
            }
            content
        }
        .task(id: kind) { await loadIfNeeded() }
    }

    @ViewBuilder private var content: some View {
        if loading {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("加载中…").appFont(.footnote).foregroundStyle(palette.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
        } else if failed {
            HStack(spacing: 10) {
                Text("加载失败").appFont(.footnote).foregroundStyle(palette.secondary)
                Button("重试") { Task { await loadIfNeeded(force: true) } }
                    .appFont(.footnote.weight(.semibold))
                    .accessibilityIdentifier("discover.block.retry.\(kind.title)")
            }
        } else if books.isEmpty {
            Text("暂无内容").appFont(.footnote).foregroundStyle(palette.secondary)
        } else if isRanking {
            VStack(spacing: 12) {
                ForEach(Array(books.prefix(3).enumerated()), id: \.element.id) { pair in
                    NavigationLink {
                        BookDetailView(book: pair.element)
                    } label: {
                        DiscoverRankRow(rank: pair.offset + 1, book: pair.element)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("discover.book.\(pair.element.id)")
                }
            }
        } else {
            HStack(alignment: .top, spacing: 10) {
                ForEach(books.prefix(3)) { book in
                    NavigationLink {
                        BookDetailView(book: book)
                    } label: {
                        DiscoverCoverCard(book: book)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("discover.book.\(book.id)")
                }
            }
        }
    }

    private func loadIfNeeded(force: Bool = false) async {
        guard let url = kind.url, !url.isEmpty else { loading = false; return }
        if !force, !books.isEmpty { return }
        loading = true
        failed = false
        let src = source
        do {
            let list = try await SourceDiagnostics.explore(source: src, url: url, page: 1)
            books = list
        } catch {
            failed = true
        }
        loading = false
    }
}

/// 榜单板块的排名横条：排名徽章 + 封面 + 书名 / 作者 / 简介。
struct DiscoverRankRow: View {
    @ThemePalette private var palette
    let rank: Int
    let book: Book

    private var badgeColor: Color {
        switch rank {
        case 1: return Color(red: 0.93, green: 0.26, blue: 0.27)
        case 2: return Color(red: 0.98, green: 0.62, blue: 0.20)
        default: return Color(red: 0.98, green: 0.78, blue: 0.20)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(rank)")
                .appFont(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(badgeColor, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            BookCoverImage(url: BookCoverLocation.url(for: book))
                .frame(width: 58, height: 78)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(book.name)
                    .appFont(.system(size: 16, weight: .semibold))
                    .foregroundStyle(palette.primary)
                    .lineLimit(1)
                if !book.author.isEmpty {
                    Text(book.author)
                        .appFont(.system(size: 12))
                        .foregroundStyle(palette.secondary)
                        .lineLimit(1)
                }
                if let intro = Self.intro(book) {
                    Text(intro)
                        .appFont(.system(size: 12))
                        .foregroundStyle(palette.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    static func intro(_ book: Book) -> String? {
        let value = book.intro?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }
}

/// 封面网格卡：封面 + 书名（两行）+ 简介或作者（两行）。
struct DiscoverCoverCard: View {
    @ThemePalette private var palette
    let book: Book

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Color.clear
                .aspectRatio(3.0 / 4.0, contentMode: .fit)
                .overlay { BookCoverImage(url: BookCoverLocation.url(for: book)) }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(book.name)
                .appFont(.system(size: 13, weight: .medium))
                .foregroundStyle(palette.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let line = subtitle {
                Text(line)
                    .appFont(.system(size: 11))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    private var subtitle: String? {
        if let intro = DiscoverRankRow.intro(book) { return intro }
        let author = book.author.trimmingCharacters(in: .whitespacesAndNewlines)
        return author.isEmpty ? nil : author
    }
}

/// 发现页控件行（书山聚合扩展）：select 控件显示为胶囊，点开选择后执行 action。
struct DiscoverFilterBar: View {
    @ThemePalette private var palette
    let controls: [SourceDiagnostics.ExploreKind]
    let values: [String: String]
    let onSelect: (SourceDiagnostics.ExploreKind, String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(controls, id: \.title) { control in
                    Menu {
                        ForEach(control.chars ?? [], id: \.self) { option in
                            Button {
                                onSelect(control, option)
                            } label: {
                                if values[control.title] == option {
                                    Label(option, systemImage: "checkmark")
                                } else {
                                    Text(option)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Text(control.title)
                                .appFont(.system(size: 13))
                                .foregroundStyle(palette.secondary)
                            Text(values[control.title] ?? control.defaultValue ?? "")
                                .appFont(.system(size: 13, weight: .semibold))
                                .foregroundStyle(palette.primary)
                                .lineLimit(1)
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(palette.secondary)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background { ThemeSurface(shape: Capsule()) }
                    }
                    .accessibilityIdentifier("discover.filter.\(control.title)")
                }
            }
        }
    }
}
