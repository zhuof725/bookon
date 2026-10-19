import SwiftUI

/// 「发现」：按分组浏览书源 → 书源的发现分类 → 分类书单 → 书籍详情。
/// 一级/二级的整理规则见 DiscoverCatalog，本文件只负责展示与导航。
struct DiscoverView: View {
    @ThemePalette private var palette
    @EnvironmentObject var store: AppStore
    @AppStorage(SourceListLayout.layoutKey) private var layoutRaw = SourceListLayout.grid.rawValue

    private var sections: [(name: String, sources: [BookSource])] {
        DiscoverCatalog.sections(store.sources)
    }
    private var layout: SourceListLayout { SourceListLayout(rawValue: layoutRaw) ?? .grid }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer(minLength: 0)
                DiscoverLayoutMenu()
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            if sections.isEmpty {
                List {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("没有可以浏览的书源").appFont(.headline)
                        Text("在「我的 → 书库管理 → 书源」里给书源填写「发现地址」并保持启用，带发现规则的书源会按分组出现在这里。")
                            .appFont(.footnote).foregroundStyle(palette.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .independentGlassRow()
                }
                .scrollContentBackground(.hidden)
            } else if layout == .grid {
                ScrollView {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
                        ForEach(sections, id: \.name) { section in
                            NavigationLink {
                                DiscoverGroupView(groupName: section.name)
                            } label: {
                                DiscoverGroupGridCard(name: section.name, count: section.sources.count)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("discover.group.\(section.name)")
                        }
                    }
                    .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 24)
                }
            } else {
                List {
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
                .scrollContentBackground(.hidden)
            }
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
        Group {
            if sources.isEmpty {
                List {
                    Text("这个分组暂时没有可以浏览的书源")
                        .appFont(.footnote).foregroundStyle(palette.secondary)
                        .independentGlassRow()
                }
                .scrollContentBackground(.hidden)
            } else if layout == .grid {
                ScrollView {
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
                    .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 24)
                }
            } else {
                List {
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
                .scrollContentBackground(.hidden)
            }
        }
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
    @State private var controlValues: [String: String] = [:]
    @State private var applyingControl = false

    private var errorText: String? { DiscoverCatalog.kindError(kinds) }
    /// 顶部筛选行：只显示有选项的 select 控件（书山聚合扩展）。
    private var controls: [SourceDiagnostics.ExploreKind] {
        kinds.filter { ($0.type ?? "") == "select" && !($0.chars ?? []).isEmpty }
    }
    private var sections: [(header: String?, items: [SourceDiagnostics.ExploreKind])] {
        DiscoverCatalog.kindSections(kinds)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                DiscoverSourceHeader(source: source)
                    .padding(14)
                    .background {
                        ThemeSurface(shape: RoundedRectangle(cornerRadius: 20, style: .continuous), isCard: true)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .accessibilityIdentifier("discover.source.header")

                if !controls.isEmpty {
                    DiscoverFilterBar(controls: controls, values: controlValues) { control, value in
                        applyControl(control, value: value)
                    }
                    .padding(.horizontal, 16)
                }

                if applyingControl {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("正在切换…").appFont(.footnote).foregroundStyle(palette.secondary)
                    }
                    .padding(.horizontal, 16)
                }

                if loading {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("正在读取发现分类…").appFont(.footnote).foregroundStyle(palette.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                } else if let errorText = errorText {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(errorText).appFont(.footnote).foregroundStyle(palette.secondary)
                        Button("重试") { reloadToken = UUID() }
                            .appFont(.footnote.weight(.semibold))
                            .accessibilityIdentifier("discover.retry")
                    }
                    .padding(.horizontal, 16)
                } else if sections.isEmpty {
                    Text("这个书源暂时没有发现分类；可以在书源编辑里检查「发现地址」。")
                        .appFont(.footnote).foregroundStyle(palette.secondary)
                        .padding(.horizontal, 16)
                } else {
                    ForEach(Array(sections.enumerated()), id: \.offset) { pair in
                        if let header = pair.element.header {
                            Text(header)
                                .appFont(.headline)
                                .foregroundStyle(palette.primary)
                                .padding(.horizontal, 16)
                        }
                        ForEach(pair.element.items, id: \.self) { kind in
                            DiscoverSectionBlock(source: source, kind: kind)
                                .padding(.horizontal, 16)
                        }
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .foregroundStyle(palette.primary)
        .background { AppThemeCanvas().ignoresSafeArea() }
        .navigationTitle(source.bookSourceName)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: reloadToken) { await load() }
        .refreshable { await load() }
        .accessibilityIdentifier("discover.source.page")
    }

    private func load() async {
        let src = source
        loading = true
        let result = await Task.detached(priority: .userInitiated) {
            SourceDiagnostics.exploreKinds(source: src)
        }.value
        kinds = result
        controlValues = Self.controlValues(from: result)
        loading = false
    }

    /// 切换筛选控件：执行控件 action（写书源配置），然后重新读取分类列表。
    private func applyControl(_ control: SourceDiagnostics.ExploreKind, value: String) {
        guard let action = control.action, !action.isEmpty else { return }
        var info = controlValues
        info[control.title] = value
        controlValues = info
        applyingControl = true
        let src = source
        Task {
            _ = await Task.detached(priority: .userInitiated) {
                SourceDiagnostics.applyExploreControl(source: src, action: action, info: info)
            }.value
            let result = await Task.detached(priority: .userInitiated) {
                SourceDiagnostics.exploreKinds(source: src)
            }.value
            kinds = result
            var values = Self.controlValues(from: result)
            if values[control.title] == nil { values[control.title] = value }
            controlValues = values
            applyingControl = false
        }
    }

    private static func controlValues(from kinds: [SourceDiagnostics.ExploreKind]) -> [String: String] {
        var values: [String: String] = [:]
        for kind in kinds where (kind.type ?? "") == "select" {
            if let def = kind.defaultValue, !def.isEmpty {
                values[kind.title] = def
            } else if let first = kind.chars?.first {
                values[kind.title] = first
            }
        }
        return values
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

/// 分组网格卡：与书源网格卡同视觉，显示组名与书源数。
private struct DiscoverGroupGridCard: View {
    @ThemePalette private var palette
    let name: String
    let count: Int

    var body: some View {
        VStack(spacing: 11) {
            SourceAvatarView(name: name, size: 62)
            VStack(spacing: 3) {
                Text(name)
                    .appFont(.system(size: 16, weight: .semibold))
                    .foregroundStyle(palette.primary)
                    .lineLimit(1)
                Text(count == 1 ? "1 个书源" : "\(count) 个书源")
                    .appFont(.system(size: 12))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.top, 20)
        .padding(.bottom, 16)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .background {
            ThemeSurface(shape: RoundedRectangle(cornerRadius: 20, style: .continuous), isCard: true)
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

/// 发现页右上角「…」：切换排列方式（网格 / 列表），系统勾选在选项右侧。
/// 首页分组与分组里的书源都按所选方式排列。
struct DiscoverLayoutMenu: View {
    @ThemePalette private var palette
    @AppStorage(SourceListLayout.layoutKey) private var layoutRaw = SourceListLayout.grid.rawValue

    var body: some View {
        Menu {
            Picker("排列方式", selection: $layoutRaw) {
                ForEach(SourceListLayout.allCases, id: \.rawValue) { value in
                    Text(value.title).tag(value.rawValue)
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
