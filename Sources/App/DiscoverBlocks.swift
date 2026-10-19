import SwiftUI

/// 板块书单请求并发闸门（预加载会同时发起多个请求）。
actor BlockRequestGate {
    static let shared = BlockRequestGate()
    private let limit = 4
    private var active = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if active < limit {
            active += 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if waiters.isEmpty {
            active = max(0, active - 1)
        } else {
            waiters.removeFirst().resume()
        }
    }
}

/// 发现板块数据：负责书单请求、缓存（缓存有效期）与预加载。
@MainActor
final class DiscoverBlockLoader: ObservableObject {
    @Published private(set) var books: [String: [Book]] = [:]
    @Published private(set) var failed: Set<String> = []
    @Published private(set) var loading: Set<String> = []

    let source: BookSource
    private var pending: Set<String> = []

    init(source: BookSource) { self.source = source }

    func books(for url: String) -> [Book]? { books[url] }
    func hasFailed(_ url: String) -> Bool { failed.contains(url) }
    func isLoading(_ url: String) -> Bool { loading.contains(url) }

    /// 读取板块：优先新鲜缓存，否则请求一次；force 用于下拉刷新/重试。
    func load(_ url: String, force: Bool = false) async {
        if url.isEmpty { return }
        if loading.contains(url) { return }
        if !force, books[url] != nil { return }
        if !force, let cached = DiscoverBlockCache.cached(source: source.bookSourceUrl, url: url) {
            books[url] = cached
            return
        }
        loading.insert(url)
        failed.remove(url)
        await BlockRequestGate.shared.acquire()
        do {
            let list = try await SourceDiagnostics.explore(source: source, url: url, page: 1)
            books[url] = list
            DiscoverBlockCache.store(source: source.bookSourceUrl, url: url, books: list)
        } catch {
            failed.insert(url)
        }
        await BlockRequestGate.shared.release()
        loading.remove(url)
    }

    /// 预加载：滚动到某个板块时，向后多加载几个板块。
    func preload(_ urls: [String]) {
        for url in urls where !url.isEmpty {
            if books[url] != nil || loading.contains(url) || pending.contains(url) { continue }
            if DiscoverBlockCache.cached(source: source.bookSourceUrl, url: url) != nil {
                Task { await load(url) }
                continue
            }
            pending.insert(url)
            Task {
                await load(url)
                pending.remove(url)
            }
        }
    }

    /// 清空（下拉刷新）。
    func reset() {
        books.removeAll()
        failed.removeAll()
        loading.removeAll()
        pending.removeAll()
    }
}

/// 发现分类的板块：标题 +「查看全部」+ 前几本书预览。
/// 竖排（榜单）用排名横条，横滑用一行可左右滑动的封面卡。
struct DiscoverSectionBlock: View {
    @ThemePalette private var palette
    @ObservedObject var loader: DiscoverBlockLoader
    let kind: SourceDiagnostics.ExploreKind
    let vertical: Bool
    let itemCount: Int
    var onAppear: (() -> Void)? = nil

    private var url: String { kind.url ?? "" }
    private var books: [Book] { loader.books(for: url) ?? [] }
    private var isLoading: Bool {
        loader.isLoading(url) || (loader.books(for: url) == nil && !loader.hasFailed(url))
    }
    private var isFailed: Bool { loader.hasFailed(url) && loader.books(for: url) == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            content
        }
        .onAppear { onAppear?() }
        .task(id: url) { await loader.load(url) }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(kind.title)
                .appFont(.title3.weight(.bold))
                .foregroundStyle(palette.primary)
                .lineLimit(1)
            Spacer(minLength: 8)
            if !url.isEmpty {
                NavigationLink {
                    DiscoverBooksView(source: loader.source, kindTitle: kind.title, kindUrl: url)
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
    }

    @ViewBuilder private var content: some View {
        if isFailed {
            HStack(spacing: 10) {
                Text("加载失败").appFont(.footnote).foregroundStyle(palette.secondary)
                Button("重试") { Task { await loader.load(url, force: true) } }
                    .appFont(.footnote.weight(.semibold))
                    .accessibilityIdentifier("discover.block.retry.\(kind.title)")
            }
        } else if books.isEmpty {
            HStack(spacing: 8) {
                if isLoading { ProgressView().controlSize(.small) }
                Text(isLoading ? "加载中…" : "暂无内容")
                    .appFont(.footnote).foregroundStyle(palette.secondary)
            }
            .padding(.vertical, 6)
        } else if vertical {
            VStack(spacing: 12) {
                ForEach(Array(books.prefix(itemCount).enumerated()), id: \.element.id) { pair in
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
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(books.prefix(itemCount)) { book in
                        NavigationLink {
                            BookDetailView(book: book)
                        } label: {
                            DiscoverCoverCard(book: book)
                                .frame(width: 108)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("discover.book.\(book.id)")
                    }
                }
                .padding(.vertical, 2)
            }
        }
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
            DiscoverCoverImage(url: BookCoverLocation.url(for: book))
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

/// 横滑封面卡：封面 + 书名（两行）+ 简介或作者（两行）。
struct DiscoverCoverCard: View {
    @ThemePalette private var palette
    let book: Book

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Color.clear
                .aspectRatio(3.0 / 4.0, contentMode: .fit)
                .overlay { DiscoverCoverImage(url: BookCoverLocation.url(for: book)) }
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

/// 列表布局的书行：封面 + 书名 / 作者 / 简介（无排名）。
struct DiscoverBookListRow: View {
    @ThemePalette private var palette
    let book: Book

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            DiscoverCoverImage(url: BookCoverLocation.url(for: book))
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
                if let intro = DiscoverRankRow.intro(book) {
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
}

/// 发现页筛选控件行（书山聚合扩展）：select 控件显示为胶囊，点开选择后执行书源 action。
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
            .padding(.vertical, 2)
        }
    }
}
