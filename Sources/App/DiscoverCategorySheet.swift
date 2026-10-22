import SwiftUI

/// 「分类筛选」面板（书源发现页左上角「分类」打开）：
/// 顶部标题 + 分类标签搜索框 + 快捷操作（搜索 / 刷新 / 登录）+ 分类标签网格。
struct DiscoverCategorySheet: View {
    @ThemePalette private var palette
    @Environment(\.dismiss) private var dismiss
    let source: BookSource
    let kinds: [SourceDiagnostics.ExploreKind]
    /// 当前选中的分类地址（高亮用）。
    let selectedURL: String?
    let onSelect: (SourceDiagnostics.ExploreKind) -> Void
    /// 重新读取分类（清缓存）。
    let onRefresh: () -> Void

    @State private var query = ""
    @State private var keyword = ""
    @State private var searching = false
    @State private var results: [Book] = []
    @State private var searchError: String?
    @State private var showLogin = false

    /// 分类标签：书源发现规则里能当分类用的项（有地址的分类一律保留，空标题给兜底名）。
    private var tags: [DiscoverCatalog.DiscoverCategoryTag] {
        let items = DiscoverCatalog.categoryTags(kinds)
        let key = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return items }
        return items.filter { $0.title.localizedCaseInsensitiveContains(key) }
    }

    private var hasLogin: Bool { SourceLoginForm.hasLogin(source) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("选择想看的分类")
                        .appFont(.footnote)
                        .foregroundStyle(palette.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                    searchField
                    quickActions
                    if searching {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("正在搜索…").appFont(.footnote).foregroundStyle(palette.secondary)
                        }
                    }
                    if let searchError {
                        Text(searchError).appFont(.footnote).foregroundStyle(palette.secondary)
                    }
                    if !results.isEmpty {
                        searchResults
                    }
                    categories
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .scrollDismissesKeyboard(.interactively)
            .background { AppThemeCanvas().ignoresSafeArea() }
            .navigationTitle("分类筛选")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Label("关闭", systemImage: "xmark")
                            .appFont(.system(size: 14, weight: .medium))
                            .foregroundStyle(palette.secondary)
                    }
                    .accessibilityIdentifier("discover.category.close")
                }
            }
            .sheet(isPresented: $showLogin) {
                SourceLoginView(source: source)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(palette.secondary)
            TextField("搜索这个页面的分类标签", text: $query)
                .appFont(.system(size: 15))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(palette.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background { ThemeSurface(shape: RoundedRectangle(cornerRadius: 10, style: .continuous)) }
        .accessibilityIdentifier("discover.category.search")
    }

    // MARK: 快捷操作

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("快捷操作")
                .appFont(.footnote.weight(.semibold))
                .foregroundStyle(palette.secondary)
            HStack(spacing: 8) {
                TextField("输入关键词…", text: $keyword)
                    .appFont(.system(size: 14))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit { runSearch() }
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background { ThemeSurface(shape: Capsule()) }
                quickButton("搜索", symbol: "magnifyingglass", id: "discover.category.searchAction") {
                    runSearch()
                }
                quickButton("刷新", symbol: "arrow.clockwise", id: "discover.category.refresh") {
                    onRefresh()
                    dismiss()
                }
                if hasLogin {
                    quickButton("登录", symbol: "person.crop.circle", id: "discover.category.login") {
                        showLogin = true
                    }
                }
            }
        }
    }

    private func quickButton(_ title: String, symbol: String, id: String,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 12, weight: .medium))
                Text(title).appFont(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(palette.primary)
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background { ThemeSurface(shape: Capsule()) }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    // MARK: 搜索结果

    private var searchResults: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("搜索结果")
                .appFont(.footnote.weight(.semibold))
                .foregroundStyle(palette.secondary)
            ForEach(results) { book in
                NavigationLink {
                    BookDetailView(book: book)
                } label: {
                    DiscoverBookListRow(book: book)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: 分类网格

    private var categories: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("分类")
                .appFont(.footnote.weight(.semibold))
                .foregroundStyle(palette.secondary)
            if tags.isEmpty {
                Text("这个书源暂时没有分类标签")
                    .appFont(.footnote)
                    .foregroundStyle(palette.secondary)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                    ForEach(tags) { tag in
                        let selected = !tag.isSection && (tag.kind.url ?? "") == (selectedURL ?? "")
                        Button {
                            onSelect(tag.kind)
                            dismiss()
                        } label: {
                            Text(tag.title)
                                .appFont(.system(size: 12))
                                .lineLimit(1)
                                .foregroundStyle(selected ? palette.accent : palette.primary)
                                .frame(maxWidth: .infinity, minHeight: 32)
                                .background {
                                    // 纯色填充：一格一个玻璃面（这里 80 个格子）滚动时会闪，也卡。
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .fill(palette.selection)
                                }
                                .overlay {
                                    if selected {
                                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                                            .strokeBorder(palette.accent, lineWidth: 1.5)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("discover.category.\(tag.title)")
                    }
                }
            }
        }
    }

    // MARK: 搜索书源

    private func runSearch() {
        let key = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        searching = true
        searchError = nil
        Task { @MainActor in
            do {
                let list = try await WebBook.search(source: source, key: key)
                results = list
                if list.isEmpty { searchError = "没有搜到结果" }
            } catch {
                results = []
                searchError = "搜索失败：\(error.localizedDescription)"
            }
            searching = false
        }
    }
}
