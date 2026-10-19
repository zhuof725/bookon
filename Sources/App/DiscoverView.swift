import SwiftUI

/// 「发现」：按分组浏览书源 → 书源的发现分类 → 分类书单 → 书籍详情。
/// 一级/二级的整理规则见 DiscoverCatalog，本文件只负责展示与导航。
struct DiscoverView: View {
    @ThemePalette private var palette
    @EnvironmentObject var store: AppStore

    private var sections: [(name: String, sources: [BookSource])] {
        DiscoverCatalog.sections(store.sources)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer(minLength: 0)
                DiscoverLayoutMenu()
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            List {
                if sections.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("没有可以浏览的书源").appFont(.headline)
                        Text("在「我的 → 书库管理 → 书源」里给书源填写「发现地址」并保持启用，带发现规则的书源会按分组出现在这里。")
                            .appFont(.footnote).foregroundStyle(palette.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .independentGlassRow()
                } else {
                    ForEach(sections, id: \.name) { section in
                        NavigationLink {
                            DiscoverGroupView(groupName: section.name)
                        } label: {
                            DiscoverGroupCard(name: section.name, count: section.sources.count)
                        }
                        .independentGlassRow()
                        .accessibilityIdentifier("discover.group.\(section.name)")
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .foregroundStyle(palette.primary)
        .background { AppThemeCanvas().ignoresSafeArea() }
        .navigationTitle("发现")
        .toolbar(.visible, for: .navigationBar)
        .accessibilityIdentifier("discover.page")
    }
}

// MARK: - 二级：分组里的书源

struct DiscoverGroupView: View {
    @ThemePalette private var palette
    @EnvironmentObject var store: AppStore
    let groupName: String
    @AppStorage(SourceListLayout.layoutKey) private var layoutRaw = SourceListLayout.grid.rawValue

    private var sources: [BookSource] {
        DiscoverCatalog.sources(inGroup: groupName, from: store.sources)
    }
    private var layout: SourceListLayout { SourceListLayout(rawValue: layoutRaw) ?? .grid }

    var body: some View {
        List {
            if sources.isEmpty {
                Text("这个分组暂时没有可以浏览的书源")
                    .appFont(.footnote).foregroundStyle(palette.secondary)
                    .independentGlassRow()
            } else if layout == .grid {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
                    ForEach(sources) { source in
                        NavigationLink {
                            DiscoverSourceView(source: source)
                        } label: {
                            SourceGridCard(source: source,
                                           subtitle: DiscoverCatalog.displayDomain(source.bookSourceUrl))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("discover.source.\(source.bookSourceName)")
                    }
                }
                .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            } else {
                ForEach(sources) { source in
                    NavigationLink {
                        DiscoverSourceView(source: source)
                    } label: {
                        DiscoverSourceCard(source: source)
                    }
                    .independentGlassRow()
                    .accessibilityIdentifier("discover.source.\(source.bookSourceName)")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .foregroundStyle(palette.primary)
        .background { AppThemeCanvas().ignoresSafeArea() }
        .navigationTitle(groupName)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 三级：某个书源的发现分类

struct DiscoverSourceView: View {
    @ThemePalette private var palette
    let source: BookSource
    @State private var kinds: [SourceDiagnostics.ExploreKind] = []
    @State private var loading = true
    @State private var reloadToken = UUID()

    private var errorText: String? { DiscoverCatalog.kindError(kinds) }
    private var sections: [(header: String?, items: [SourceDiagnostics.ExploreKind])] {
        DiscoverCatalog.kindSections(kinds)
    }

    var body: some View {
        List {
            Section {
                DiscoverSourceHeader(source: source)
                    .independentGlassRow()
                    .accessibilityIdentifier("discover.source.header")
            }
            if loading {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("正在读取发现分类…").appFont(.footnote).foregroundStyle(palette.secondary)
                }
                .independentGlassRow()
            } else if let errorText = errorText {
                VStack(alignment: .leading, spacing: 8) {
                    Text(errorText).appFont(.footnote).foregroundStyle(palette.secondary)
                    Button("重试") { reloadToken = UUID() }
                        .appFont(.footnote.weight(.semibold))
                        .accessibilityIdentifier("discover.retry")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .independentGlassRow()
            } else if sections.isEmpty {
                Text("这个书源暂时没有发现分类；可以在书源编辑里检查「发现地址」。")
                    .appFont(.footnote).foregroundStyle(palette.secondary)
                    .independentGlassRow()
            } else {
                ForEach(Array(sections.enumerated()), id: \.offset) { pair in
                    Section {
                        ForEach(Array(pair.element.items.enumerated()), id: \.offset) { entry in
                            NavigationLink {
                                DiscoverBooksView(source: source, kindTitle: entry.element.title,
                                                  kindUrl: entry.element.url ?? "")
                            } label: {
                                Text(entry.element.title).appFont(.body).lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .independentGlassRow()
                        }
                    } header: {
                        if let header = pair.element.header {
                            Text(header).textCase(nil)
                        }
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .foregroundStyle(palette.primary)
        .background { AppThemeCanvas().ignoresSafeArea() }
        .navigationTitle(source.bookSourceName)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: reloadToken) { await load() }
        .accessibilityIdentifier("discover.source.page")
    }

    private func load() async {
        loading = true
        let src = source
        let result = await Task.detached(priority: .userInitiated) {
            SourceDiagnostics.exploreKinds(source: src)
        }.value
        kinds = result
        loading = false
    }
}

// MARK: - 四级：某个分类下的书单

struct DiscoverBooksView: View {
    @ThemePalette private var palette
    let source: BookSource
    let kindTitle: String
    let kindUrl: String

    @State private var books: [Book] = []
    @State private var loading = true
    @State private var loadingMore = false
    @State private var errorText: String?
    @State private var moreError: String?
    @State private var noMore = false
    @State private var page = 1

    private var supportsMore: Bool { kindUrl.contains("{{page}}") }

    var body: some View {
        List {
            if loading {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("正在加载书单…").appFont(.footnote).foregroundStyle(palette.secondary)
                }
                .independentGlassRow()
            } else if let errorText = errorText {
                VStack(alignment: .leading, spacing: 8) {
                    Text(errorText).appFont(.footnote).foregroundStyle(palette.secondary)
                    Button("重试") { Task { await reload() } }
                        .appFont(.footnote.weight(.semibold))
                        .accessibilityIdentifier("discover.books.retry")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .independentGlassRow()
            } else if books.isEmpty {
                Text("没有获取到书籍").appFont(.footnote).foregroundStyle(palette.secondary)
                    .independentGlassRow()
            } else {
                ForEach(books) { book in
                    NavigationLink {
                        BookDetailView(book: book)
                    } label: {
                        BookRow(book: book, subtitle: "来源：\(source.bookSourceName)")
                    }
                    .independentGlassRow()
                }
                footer
            }
        }
        .scrollContentBackground(.hidden)
        .foregroundStyle(palette.primary)
        .background { AppThemeCanvas().ignoresSafeArea() }
        .navigationTitle(kindTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { if books.isEmpty { await reload() } }
        .accessibilityIdentifier("discover.books.page")
    }

    @ViewBuilder private var footer: some View {
        if supportsMore && !noMore {
            VStack(spacing: 8) {
                if let moreError = moreError {
                    Text(moreError).appFont(.caption2).foregroundStyle(palette.secondary)
                        .multilineTextAlignment(.center).lineLimit(3)
                }
                if loadingMore {
                    ProgressView()
                } else {
                    Button(moreError == nil ? "加载更多" : "重试加载") { Task { await loadNextPage() } }
                        .appFont(.footnote.weight(.semibold))
                        .accessibilityIdentifier("discover.books.more")
                }
            }
            .frame(maxWidth: .infinity)
            .independentGlassRow()
        } else {
            Text(noMore ? "没有更多了" : "共 \(books.count) 本")
                .appFont(.caption).foregroundStyle(palette.secondary)
                .frame(maxWidth: .infinity)
                .independentGlassRow()
        }
    }

    private func reload() async {
        loading = true; errorText = nil; moreError = nil; noMore = false; page = 1
        do {
            let list = try await SourceDiagnostics.explore(source: source, url: kindUrl, page: 1)
            books = list
            loading = false
        } catch {
            errorText = error.localizedDescription
            loading = false
        }
    }

    private func loadNextPage() async {
        guard !loadingMore else { return }
        loadingMore = true
        moreError = nil
        defer { loadingMore = false }
        do {
            let next = page + 1
            let list = try await SourceDiagnostics.explore(source: source, url: kindUrl, page: next)
            let known = Set(books.map(\.bookUrl))
            let fresh = list.filter { !known.contains($0.bookUrl) }
            page = next
            if fresh.isEmpty { noMore = true } else { books += fresh }
        } catch {
            moreError = error.localizedDescription
        }
    }
}

// MARK: - 卡片组件

/// 圆角方块头像：名字首字 + 由名字决定的稳定渐变底色。
struct SourceAvatarView: View {
    let name: String
    var size: CGFloat = 46

    private var initial: String {
        let text = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "书" : String(text.prefix(1))
    }
    private var colors: [Color] {
        let hue = DiscoverCatalog.avatarHue(for: name)
        return [Color(hue: hue, saturation: 0.55, brightness: 0.95),
                Color(hue: (hue + 0.09).truncatingRemainder(dividingBy: 1),
                      saturation: 0.72, brightness: 0.80)]
    }

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay {
                Text(initial)
                    .appFont(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }
}

private struct SourceTagPill: View {
    @ThemePalette private var palette
    let text: String

    var body: some View {
        Text(text)
            .appFont(.caption2)
            .foregroundStyle(palette.accent)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(palette.accent.opacity(0.14), in: Capsule())
    }
}

private struct DiscoverGroupCard: View {
    @ThemePalette private var palette
    let name: String
    let count: Int

    var body: some View {
        HStack(spacing: 12) {
            SourceAvatarView(name: name)
            VStack(alignment: .leading, spacing: 4) {
                Text(name).appFont(.headline).lineLimit(1)
                Text(count == 1 ? "1 个书源" : "\(count) 个书源")
                    .appFont(.caption).foregroundStyle(palette.secondary)
            }
            Spacer(minLength: 8)
        }
    }
}

private struct DiscoverSourceCard: View {
    @ThemePalette private var palette
    let source: BookSource

    var body: some View {
        HStack(spacing: 12) {
            SourceAvatarView(name: source.bookSourceName)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(source.bookSourceName).appFont(.headline).lineLimit(1)
                    if let tag = source.discoverTypeLabel { SourceTagPill(text: tag) }
                }
                Text(DiscoverCatalog.displayDomain(source.bookSourceUrl))
                    .appFont(.caption).foregroundStyle(palette.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
        }
    }
}

private struct DiscoverSourceHeader: View {
    @ThemePalette private var palette
    let source: BookSource

    var body: some View {
        HStack(spacing: 12) {
            SourceAvatarView(name: source.bookSourceName, size: 52)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(source.bookSourceName).appFont(.title3.weight(.semibold)).lineLimit(1)
                    if let tag = source.discoverTypeLabel { SourceTagPill(text: tag) }
                }
                Text(DiscoverCatalog.displayDomain(source.bookSourceUrl))
                    .appFont(.caption).foregroundStyle(palette.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
        }
    }
}

/// 发现页右上角「…」：切换书源排列方式（宫格 / 列表）。
/// 切换后分组里的书源列表立即按所选方式显示。
struct DiscoverLayoutMenu: View {
    @ThemePalette private var palette
    @AppStorage(SourceListLayout.layoutKey) private var layoutRaw = SourceListLayout.grid.rawValue

    private var layout: SourceListLayout { SourceListLayout(rawValue: layoutRaw) ?? .grid }

    var body: some View {
        Menu {
            Section("排列方式") {
                ForEach(SourceListLayout.allCases, id: \.rawValue) { value in
                    Button {
                        layoutRaw = value.rawValue
                    } label: {
                        if value == layout {
                            Label(value.title, systemImage: "checkmark")
                        } else {
                            Text(value.title)
                        }
                    }
                    .accessibilityIdentifier("discover.layout.\(value.rawValue)")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 20, weight: .bold))
                .frame(width: 44, height: 44)
                .background { ThemeSurface(shape: Circle()) }
        }
        .buttonStyle(.plain)
        .foregroundStyle(palette.primary)
        .accessibilityLabel("排列方式")
        .accessibilityIdentifier("discover.layout.menu")
    }
}
