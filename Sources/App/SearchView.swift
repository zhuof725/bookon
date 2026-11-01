import SwiftUI
import UIKit

// MARK: - Search

struct SearchView: View {
    @ThemePalette private var palette
    @EnvironmentObject var store: AppStore
    @State private var keyword = ""
    @State private var hits: [SearchHit] = []
    @State private var failedCount = 0
    @State private var searching = false
    @State private var progress = ""
    @State private var task: Task<Void, Never>?
    @State private var requestID = UUID()
    @StateObject private var history = BookSearchHistory()
    /// 搜索范围、精确、不聚合会记住；单源与原版一样不记忆，每次需要重新指定。
    @AppStorage("search.scope.group") private var scopeGroup = ""
    @AppStorage("search.precision") private var precision = false
    @AppStorage("search.noAggregate") private var noAggregate = false
    @State private var singleSource = ""
    @FocusState private var fieldFocused: Bool

    private var searchable: [BookSource] { store.sources.filter { $0.isEnabled && !($0.searchUrl ?? "").isEmpty } }
    private var groups: [String] {
        var seen = Set<String>(); var out: [String] = []
        for s in searchable { for g in s.sourceGroupNames where seen.insert(g).inserted { out.append(g) } }
        return out
    }

    var body: some View {
        List {
            Section { header }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
            if !searching && (hits.isEmpty || BookSearchHistory.normalized(keyword).isEmpty) {
                BookSearchHistorySection(history: history, onSelect: searchAgain)
            }
            if searching || !progress.isEmpty {
                HStack {
                    if searching { ProgressView() }
                    Text(progress).appFont(.footnote).foregroundStyle(palette.secondary)
                }
                .independentGlassRow()
            }
            ForEach(hits) { h in
                NavigationLink {
                    BookDetailView(book: h.book)
                } label: {
                    BookRow(book: h.book, subtitle: h.sourceCount > 1
                            ? "来源：\(h.book.originName) 等 \(h.sourceCount) 个书源"
                            : "来源：" + h.book.originName)
                }
            }
            .independentGlassRow()
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .foregroundStyle(palette.primary)
        .background { AppThemeCanvas().ignoresSafeArea() }
        .navigationTitle("搜索")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            if searching { Button("停止") { task?.cancel(); requestID = UUID(); searching = false } }
        }
        .onChange(of: scopeGroup) { rerun() }
        .onChange(of: singleSource) { rerun() }
        .onChange(of: precision) { rerun() }
        .onChange(of: noAggregate) { rerun() }
        .onAppear {
            history.reload()
            if !scopeGroup.isEmpty && !groups.contains(scopeGroup) { scopeGroup = "" }
        }
        .onDisappear { task?.cancel(); requestID = UUID(); searching = false }
    }

    // MARK: 顶部：输入框 + 四个选项

    private var header: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(palette.secondary)
                TextField("", text: $keyword, prompt: Text("书名或作者").foregroundColor(palette.secondary))
                    .focused($fieldFocused)
                    .submitLabel(.search)
                    .onSubmit { start() }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundStyle(palette.primary)
                    .accessibilityIdentifier("search.field")
                if !keyword.isEmpty {
                    Button { keyword = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(palette.secondary)
                    }
                    .buttonStyle(.plain).accessibilityLabel("清除输入")
                }
            }
            .appFont(.body)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .modifier(ShelfGlass(shape: Capsule(), isCard: true))

            HStack(spacing: 8) {
                Menu {
                    Picker("分组", selection: $scopeGroup) {
                        Text("全部分组").tag("")
                        ForEach(groups, id: \.self) { Text($0).tag($0) }
                    }
                } label: {
                    optionLabel(scopeGroup.isEmpty ? "全部分组" : scopeGroup, symbol: "square.stack.3d.up",
                                active: !scopeGroup.isEmpty && singleSource.isEmpty)
                }
                .accessibilityIdentifier("search.group")
                optionToggle("精确", isOn: $precision, id: "search.precision")
                Menu {
                    Picker("书源", selection: $singleSource) {
                        Text("全部书源").tag("")
                        ForEach(searchable) { Text($0.bookSourceName).tag($0.bookSourceUrl) }
                    }
                } label: {
                    optionLabel(searchable.first { $0.bookSourceUrl == singleSource }?.bookSourceName ?? "单源",
                                symbol: "scope", active: !singleSource.isEmpty)
                }
                .accessibilityIdentifier("search.single")
                optionToggle("不聚合", isOn: $noAggregate, id: "search.noAggregate")
            }
        }
    }

    private func optionLabel(_ title: String, symbol: String, active: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
            Text(title).lineLimit(1).minimumScaleFactor(0.75)
        }
        .appFont(.footnote)
        .foregroundStyle(active ? palette.accent : palette.primary)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, minHeight: 34)
        .modifier(ShelfGlass(shape: Capsule(), isCard: true))
        .contentShape(Capsule())
    }

    private func optionToggle(_ title: String, isOn: Binding<Bool>, id: String) -> some View {
        Button { isOn.wrappedValue.toggle() } label: {
            optionLabel(title, symbol: isOn.wrappedValue ? "checkmark.circle.fill" : "circle", active: isOn.wrappedValue)
        }
        .buttonStyle(.plain)
        .accessibilityValue(isOn.wrappedValue ? "已开启" : "已关闭")
        .accessibilityIdentifier(id)
    }

    // MARK: 搜索

    /// 改了范围或选项后，已有结果时自动按新条件重搜。
    private func rerun() {
        guard !BookSearchHistory.normalized(keyword).isEmpty, searching || !hits.isEmpty else { return }
        start()
    }

    private func searchAgain(_ query: String) {
        keyword = query
        start()
    }

    private func start() {
        let key = BookSearchHistory.normalized(keyword)
        guard !key.isEmpty else { return }
        keyword = key
        fieldFocused = false
        history.record(key)
        task?.cancel()
        let token = UUID()
        requestID = token
        searching = false
        hits = []
        failedCount = 0
        let sources = SearchRanking.scope(searchable, group: scopeGroup, single: singleSource)
        if searchable.isEmpty { progress = "没有可用书源，请先导入书源"; return }
        if sources.isEmpty { progress = "当前分组没有可用书源"; return }
        let precise = precision
        let aggregate = !noAggregate
        searching = true
        progress = "0/\(sources.count)"
        task = Task {
            var done = 0
            await withTaskGroup(of: ([Book], Bool).self) { group in
                var iter = sources.makeIterator()
                let fanout = NetworkSettings.searchFanout
                func addNext() {
                    if let s = iter.next() {
                        group.addTask {
                            if let cached = SearchResultCache.cached(source: s.bookSourceUrl, key: key) {
                                return (cached, false)
                            }
                            guard let list = await WebBook.searchWithTimeout(source: s, key: key) else {
                                return ([], true)
                            }
                            SearchResultCache.store(list, source: s.bookSourceUrl, key: key)
                            return (list, false)
                        }
                    }
                }
                for _ in 0..<fanout { addNext() }
                for await (list, failed) in group {
                    if Task.isCancelled || requestID != token { group.cancelAll(); break }
                    done += 1
                    if failed { failedCount += 1 }
                    // 精确：只保留书名/作者/分类含关键词的结果（原版 precisionSearch）。
                    // 非精确：不相关结果只在没有相关结果时保留少量，避免淹没真正的匹配。
                    let related = list.filter { SearchRanking.isRelated($0, key: key) }
                    let kept = precise ? related : (related.isEmpty ? Array(list.prefix(3)) : related)
                    hits = SearchRanking.merge(existing: hits, new: kept, key: key, aggregate: aggregate)
                    progress = "\(done)/\(sources.count)，找到 \(hits.count) 本" + (failedCount > 0 ? "，\(failedCount) 个书源失败" : "")
                    addNext()
                }
            }
            if requestID == token { searching = false }
        }
    }
}
