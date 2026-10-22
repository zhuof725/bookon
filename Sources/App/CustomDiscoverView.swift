import SwiftUI

/// 渲染一页自定义板块：轮播 + 每条板块按自己的模板画。
/// 它只做三件事：读 Store、按模板分发、处理点击。排版全在模板里。
struct CustomDiscoverView: View {
    @ThemePalette private var palette
    @EnvironmentObject private var store: AppStore
    @ObservedObject private var model = DiscoverBoardStore.shared
    @State private var showSettings = false
    @State private var selectedBook: Book?
    @State private var fullPage: CustomDiscoverEntry?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if model.isEmpty {
                    emptyState
                } else {
                    carousel
                    ForEach(model.sections) { section in
                        sectionBlock(section)
                    }
                }
            }
            .padding(.bottom, 28)
        }
        .background { AppThemeCanvas().ignoresSafeArea() }
        .foregroundStyle(palette.primary)
        .navigationTitle("发现")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSettings = true } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 15, weight: .semibold))
                }
                .accessibilityIdentifier("customdiscover.settings")
            }
        }
        .sheet(isPresented: $showSettings) {
            CustomDiscoverSettingsView()
                .environmentObject(store)
                .environmentObject(model)
        }
        .navigationDestination(item: $selectedBook) { book in
            BookDetailView(book: book)
        }
        .navigationDestination(item: $fullPage) { entry in
            CustomDiscoverFullPage(entry: entry)
                .environmentObject(store)
                .environmentObject(model)
        }
        .task {
            if model.isEmpty { model.reloadConfig() }
            await model.loadInitial()
        }
        .refreshable { await model.refresh() }
        .onChange(of: model.revision) { _, _ in
            Task { await model.loadInitial() }
        }
        .accessibilityIdentifier("customdiscover.page")
    }

    // MARK: 顶部轮播

    @ViewBuilder private var carousel: some View {
        let heroes = model.carouselHeroes
        if !heroes.isEmpty {
            CustomDiscoverCarousel(heroes: heroes)
                .padding(.bottom, 20)
        }
    }

    // MARK: 单条板块

    @ViewBuilder private func sectionBlock(_ section: DiscoverSectionModel) -> some View {
        if section.kind == .history {
            DiscoverTemplateView(
                kind: .history,
                title: section.title,
                moreTitle: "全部",
                history: model.historyItems,
                count: section.count,
                onMore: { fullPage = section.entry },
                onSelectHistory: { item in
                    selectedBook = store.books.first { $0.bookUrl == item.id }
                }
            )
        } else if section.failed {
            failedRow(section)
        } else if section.books.isEmpty && section.loading {
            loadingRow(section)
        } else {
            DiscoverTemplateView(
                kind: section.kind,
                title: section.title,
                moreTitle: "全部",
                books: section.books,
                count: section.count,
                onMore: { fullPage = section.entry },
                onSelectBook: { book in selectedBook = book }
            )
            .task { await model.load(section) }
        }
    }

    private func loadingRow(_ section: DiscoverSectionModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header(section.title)
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("加载中…")
                    .appFont(.system(size: 12))
                    .foregroundStyle(palette.secondary)
            }
            .frame(height: 60)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 18)
    }

    private func failedRow(_ section: DiscoverSectionModel) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            header(section.title)
            HStack(spacing: 10) {
                Text(section.errorText ?? "加载失败")
                    .appFont(.system(size: 12))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(2)
                Button("重试") { Task { await model.load(section, force: true) } }
                    .appFont(.system(size: 12, weight: .semibold))
            }
            .frame(height: 60)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 18)
    }

    private func header(_ title: String) -> some View {
        HStack {
            Text(title)
                .appFont(.system(size: 20, weight: .bold))
                .foregroundStyle(palette.primary)
            Spacer()
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("还没有配置板块").appFont(.headline)
            Text("点右上角，从书源的发现分类里挑几条，各选一个模板，拼成你自己的首页。")
                .appFont(.footnote)
                .foregroundStyle(palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("开始配置") { showSettings = true }
                .appFont(.footnote.weight(.semibold))
                .padding(.top, 3)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 全部内容页

/// 「全部」：同一条板块，不限数量。
struct CustomDiscoverFullPage: View {
    @ThemePalette private var palette
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var model: DiscoverBoardStore
    let entry: CustomDiscoverEntry
    @State private var selectedBook: Book?
    @State private var extra: [Book] = []
    @State private var loadingMore = false
    @State private var noMore = false
    @State private var page = 1

    private var loaded: [Book] {
        let base = model.sections.first { $0.id == entry.id }?.books ?? []
        return base + extra
    }

    private var supportsMore: Bool { entry.kindUrl.contains("{{page}}") }

    var body: some View {
        ScrollView {
            DiscoverTemplateView(
                kind: entry.template,
                title: "",
                moreTitle: "",
                books: loaded,
                history: model.historyItems,
                count: DiscoverTemplate.unlimited,
                onSelectBook: { selectedBook = $0 }
            )
            .padding(.top, 8)

            if supportsMore {
                Group {
                    if loadingMore {
                        ProgressView().padding(.vertical, 14)
                    } else if noMore {
                        Text("没有更多了")
                            .appFont(.system(size: 12))
                            .foregroundStyle(palette.secondary)
                            .padding(.vertical, 14)
                    } else {
                        Button("加载更多") { Task { await loadNext() } }
                            .appFont(.system(size: 13, weight: .semibold))
                            .padding(.vertical, 14)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .background { AppThemeCanvas().ignoresSafeArea() }
        .foregroundStyle(palette.primary)
        .navigationTitle(entry.boardTitle)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedBook) { book in
            BookDetailView(book: book)
        }
        .accessibilityIdentifier("customdiscover.full")
    }

    private func loadNext() async {
        guard let source = store.source(for: entry.sourceUrl) else { return }
        loadingMore = true
        defer { loadingMore = false }
        do {
            let next = page + 1
            let list = try await SourceDiagnostics.explore(source: source, url: entry.kindUrl, page: next)
            let known = Set(loaded.map(\.bookUrl))
            let fresh = list.filter { !known.contains($0.bookUrl) }
            page = next
            if fresh.isEmpty { noMore = true } else { extra += fresh }
        } catch {
            noMore = true
        }
    }
}

// MARK: - 顶部轮播

/// 轮播一屏所需的字段，由 Store 组装。
struct CustomDiscoverHero: Identifiable, Hashable {
    let id: String
    var title: String
    var subtitle: String
    var detail: String
    var covers: [URL?]
}

/// 左文右图，右侧三张封面错开成「一摞」。
struct CustomDiscoverCarousel: View {
    @ThemePalette private var palette
    let heroes: [CustomDiscoverHero]
    @State private var index = 0

    private let height: CGFloat = 184

    var body: some View {
        VStack(spacing: 8) {
            TabView(selection: $index) {
                ForEach(Array(heroes.enumerated()), id: \.element.id) { pair in
                    page(pair.element)
                        .tag(pair.offset)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: height)

            if heroes.count > 1 {
                HStack(spacing: 6) {
                    ForEach(0..<heroes.count, id: \.self) { i in
                        Capsule()
                            .fill(palette.primary.opacity(i == index ? 0.55 : 0.16))
                            .frame(width: i == index ? 14 : 5, height: 5)
                            .animation(.easeInOut(duration: 0.2), value: index)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, 6)
    }

    private func page(_ hero: CustomDiscoverHero) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 7) {
                Text(hero.title)
                    .appFont(.system(size: 26, weight: .bold))
                    .foregroundStyle(palette.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                if !hero.subtitle.isEmpty {
                    Text(hero.subtitle)
                        .appFont(.system(size: 13.5))
                        .foregroundStyle(palette.secondary)
                        .lineLimit(1)
                }
                if !hero.detail.isEmpty {
                    Text(hero.detail)
                        .appFont(.system(size: 12.5))
                        .foregroundStyle(palette.secondary)
                        .lineSpacing(3)
                        .lineLimit(3)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            stack(hero.covers)
                .frame(width: 150, height: 150)
        }
        .padding(.horizontal, 20)
        .frame(height: height, alignment: .top)
    }

    private func stack(_ covers: [URL?]) -> some View {
        var slots = covers
        while slots.count < 3 { slots.append(nil) }
        let side: CGFloat = 150
        return ZStack {
            card(slots[2]).frame(width: side * 0.86, height: side * 0.86)
                .rotationEffect(.degrees(6))
                .offset(x: side * 0.03, y: -side * 0.04)
                .opacity(0.55)
            card(slots[1]).frame(width: side * 0.92, height: side * 0.92)
                .rotationEffect(.degrees(3))
                .offset(x: side * 0.02, y: -side * 0.02)
                .opacity(0.8)
            card(slots[0]).frame(width: side, height: side)
                .shadow(color: .black.opacity(0.16), radius: 11, x: 0, y: 5)
        }
    }

    private func card(_ url: URL?) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color(uiColor: .secondarySystemFill))
            .overlay {
                DeckCoverImage(url: url)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.32), lineWidth: 0.5)
            }
    }
}
