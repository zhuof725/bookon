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
        .onChange(of: scopeGroup) { _ in rerun() }
        .onChange(of: singleSource) { _ in rerun() }
        .onChange(of: precision) { _ in rerun() }
        .onChange(of: noAggregate) { _ in rerun() }
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
                func addNext() {
                    if let s = iter.next() {
                        group.addTask {
                            do { return (try await WebBook.search(source: s, key: key), false) }
                            catch { return ([], true) }
                        }
                    }
                }
                for _ in 0..<8 { addNext() }
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

// MARK: - Detail

// MARK: - Reader

private enum ChapterLanding {
    case start
    case end
    case saved(Int)
}

/// 已准备好的真实章节。提交跨章手势时直接接管这些页，不再加载或播放第二次动画。
private struct PreparedReaderChapter {
    let index: Int
    let contentID: String
    let text: String
    let blocks: [ContentBlock]
    let pages: [BookPage]
    let configuration: ReaderPaginator.Configuration
}

private enum ReaderChapterParser {
    static func content(raw: String, isVolume: Bool, replacement: BodyReplaceEngine) -> (text: String, blocks: [ContentBlock]) {
        if isVolume { return (raw, []) }
        let parsed = ContentBlocks.parse(raw)
        let hasRich = parsed.contains { if case .paragraph(_, let c, _) = $0 { return c > 0 }; if case .paragraph = $0 { return false }; return true }
        if hasRich {
            let displayed = parsed.map { block -> ContentBlock in
                guard case .paragraph(let text, let count, let url) = block else { return block }
                return .paragraph(text: replacement.apply(text), commentCount: count, commentURL: url)
            }
            return ("", displayed)
        }
        let clean = WebBook.cleanText(raw)
        let display = clean.components(separatedBy: "\n").map { replacement.apply($0) }.joined(separator: "\n")
        if clean.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return ("（本章没有内容）", []) }
        if display.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return ("（正文已被替换规则过滤）", []) }
        return (display, [])
    }
}

private struct ScrollReaderChapter: Identifiable {
    let id: Int
    let revision = UUID().uuidString
    let text: String
    let blocks: [ContentBlock]
    let readingBlocks: [ContentBlock]

    init(id: Int, text: String, blocks: [ContentBlock]) {
        self.id = id
        self.text = text
        self.blocks = blocks
        readingBlocks = blocks.isEmpty ? Paginator.blocks(fromPlain: text) : blocks
    }
}

/// 滚动逐帧只更新轻量缓冲，不发布 SwiftUI 状态、不重建全部章节，也不写磁盘。
private final class ReaderScrollProgress {
    var chapter = 0
    var position = 0
}

struct ReaderView: View {
    @ThemePalette private var palette
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var settings: ReadSettings
    @Environment(\.dismiss) private var dismiss
    let book: Book
    /// Explicit catalog tap takes priority over the saved chapter, without resetting stored progress until loading succeeds.
    let requestedChapter: Int?

    init(book: Book, requestedChapter: Int? = nil) {
        self.book = book
        self.requestedChapter = requestedChapter
    }

    @ObservedObject private var bubbleStyles = BubbleStyleStore.shared
    @ObservedObject private var readingFonts = ReadingFontManager.shared
    @State private var bodyReplacement = BodyReplaceEngine(rules: [])
    @State private var chapters: [BookChapter] = []
    @State private var index = 0
    @State private var text = ""
    @State private var blocks: [ContentBlock] = []
    @State private var commentURL: URL?
    @State private var commentBusy = false
    @State private var pages: [BookPage] = []
    @State private var pageIndex = 0
    @State private var screenSize: CGSize = .zero
    @State private var pageInsets = EdgeInsets()
    @State private var pageContentID = UUID().uuidString
    @State private var preparedChapters: [Int: PreparedReaderChapter] = [:]
    @State private var preparationTask: Task<Void, Never>?
    @State private var preparationID = UUID()
    @State private var pendingEdge: Int?
    @State private var pendingChapterDirection = 0
    @State private var contentRequestID: UUID?
    @State private var chapterTask: Task<Void, Never>?
    @State private var prefetchTask: Task<Void, Never>?
    @State private var pendingLanding: ChapterLanding?
    @State private var retryTarget: Int?
    @State private var retryLanding: ChapterLanding = .start
    @State private var scrollChapters: [ScrollReaderChapter] = []
    @State private var scrollRequest: ReaderScrollRequest?
    @State private var scrollTasks: [Int: Task<Void, Never>] = [:]
    @State private var scrollGeneration = UUID()
    @State private var scrollErrors: [Int: String] = [:]
    @State private var scrollProgress = ReaderScrollProgress()
    @Environment(\.scenePhase) private var scenePhase
    /// 本次阅读会话的起点与章节足迹（只统计，不用于恢复进度）。
    @State private var statsStart: Date?
    @State private var statsChapters: Set<Int> = []
    @State private var loading = true
    @State private var error: String?
    @State private var showToc = false
    @State private var showSettings = false
    @State private var showBars = false
    @State private var showReaderSearch = false
    @State private var selectedText = ""
    @State private var showReplaceFromSelection = false
    @State private var showBookmarks = false
    @State private var bookmarkNotice: String?
    @State private var showBookInfo = false
    @State private var quickBusy = false
    @State private var quickMessage: String?
    @State private var quickLogin = false
    @State private var quickRules = false
    @State private var quickSources = false
    @State private var quickPreview: Book?
    @State private var quickBrowser: BrowserTarget?
    @State private var confirmChapterClear = false
    @State private var menuProgress = 0.0
    @State private var scrubbing = false
    @StateObject private var speech = ReaderSpeechController()

    private func toggleBars() {
        if !showBars { persistContinuousProgress(); syncMenuProgress() }
        withAnimation(.easeInOut(duration: 0.18)) { showBars.toggle() }
    }

    private func commentTapped(_ target: String?) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        openComment(target)
    }

    private var theme: (bg: Color, fg: Color, name: String) {
        ReadSettings.themes[min(max(settings.theme, 0), ReadSettings.themes.count - 1)]
    }

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()
            GeometryReader { geo in
                Color.clear.onAppear { updateViewport(geo) }
                    .onChange(of: geo.size) { _ in updateViewport(geo) }
                    .onChange(of: geo.safeAreaInsets) { _ in updateViewport(geo) }
            }.ignoresSafeArea().allowsHitTesting(false)
            if settings.pageMode == 1 {
                pagedBody
            } else {
                continuousScrollBody
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .statusBarHidden(true)
        .overlay(alignment: .top) {
            if showBars {
                ReaderTopChrome(title: book.name, source: readerSourceName,
                    coverURL: BookCoverLocation.url(for: book),
                    background: theme.bg, foreground: theme.fg,
                    onBack: { dismiss() }, onDetails: { showBookInfo = true })
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) {
            if showBars {
                ReaderBottomChrome(chapter: readerChapterTitle, positionLabel: readerPositionLabel,
                    progress: $menuProgress, canScrub: canScrubReader,
                    canPrevious: !loading && readableIndex(from: index - 1, direction: -1) != nil,
                    canNext: !loading && readableIndex(from: index + 1, direction: 1) != nil,
                    isSpeaking: speech.isSpeaking, background: theme.bg, foreground: theme.fg,
                    onScrub: scrubReader, onPrevious: { go(index - 1) }, onNext: { go(index + 1) },
                    onTOC: { showToc = true }, onSpeech: toggleSpeech,
                    onSearch: { showReaderSearch = true }, onSettings: { showSettings = true })
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) {
            if let notice = bookmarkNotice {
                Text(notice).appFont(.caption).foregroundStyle(theme.bg)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Capsule().fill(theme.fg.opacity(0.82)))
                    .padding(.bottom, 90)
                    .transition(.opacity)
                    .accessibilityIdentifier("reader.notice")
            }
        }
        .sheet(isPresented: $showBookmarks) {
            ReaderBookmarkList(book: book, currentChapter: index, onOpen: { item in
                showBookmarks = false
                openBookmark(item)
            }, onDelete: { id in ReaderBookmarkStore.shared.remove(id: id) })
        }
        .sheet(isPresented: $showReplaceFromSelection) {
            BodyReplaceRulesView(seed: selectedText)
        }
        .sheet(isPresented: $showReaderSearch) {
            ReaderChapterSearch(blocks: readerBlocks, chapter: readerChapterTitle,
                                pages: settings.pageMode == 1 ? pages : [],
                                onSelect: selectSearchResult)
        }
        .sheet(isPresented: $showBookInfo) {
            NavigationStack {
                ReaderQuickPanel(book: book, sourceName: readerSourceName,
                    position: "\(chapters.isEmpty ? 0 : index + 1)/\(chapters.count)",
                    busy: quickBusy || loading, message: quickMessage,
                    enabled: quickEnabled, loggedIn: quickLoggedIn, action: quickAction)
                .navigationTitle("书籍操作")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showBookInfo = false } } }
                .sheet(isPresented: $quickLogin) {
                    if let source = store.source(for: book.origin) { SourceLoginView(source: source) }
                }
                .sheet(isPresented: $quickRules, onDismiss: {
                    bodyReplacement = BodyReplaceEngine(rules: BodyReplaceRepository().rules())
                    quickMessage = "规则已更新，点击刷新应用到当前章节"
                }) { BodyReplaceRulesView() }
                .sheet(isPresented: $quickSources) {
                    BookDetailSourcePicker(book: book) { replacement in
                        quickPreview = replacement
                    }
                    .sheet(item: $quickPreview) { replacement in
                        NavigationStack { BookDetailView(book: replacement) }
                    }
                }
                .sheet(item: $quickBrowser) { target in
                    InAppBrowserSheet(target: target, host: book.origin,
                        cookieJar: store.source(for: book.origin)?.enabledCookieJar != false,
                        onClose: { quickBrowser = nil })
                }
                .alert("清除当前章节缓存并重新下载？", isPresented: $confirmChapterClear) {
                    Button("取消", role: .cancel) {}
                    Button("清缓存并刷新", role: .destructive) { Task { await quickReload(clear: true) } }
                } message: { Text("仅清除当前章节的正文缓存，不删除书籍、目录或阅读进度。") }
            }
            .presentationDetents([.height(440), .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showToc) {
            ReaderTocSheet(chapters: chapters, currentIndex: index,
                           manager: .shared,
                           onSelect: { target in showToc = false; go(target) },
                           onRefresh: tocRefreshAction)
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                Form {
                    Section("阅读方式") {
                        Picker("方式", selection: $settings.pageMode) {
                            Text("滚动").tag(0)
                            Text("翻页").tag(1)
                        }
                        .pickerStyle(.segmented)
                        if settings.pageMode == 1 {
                            Picker("翻页动画", selection: $settings.pageTurnStyle) {
                                ForEach(PageTurnStyle.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                    .independentGlassRow()
                    ReaderTypographyControls(settings: settings)
                        .independentGlassRow()
                    NavigationLink("段评气泡") { BubbleStyleSettingsView() }
                        .independentGlassRow()
                    Section("背景") {
                        Picker("主题", selection: $settings.theme) {
                            ForEach(0..<ReadSettings.themes.count, id: \.self) { Text(ReadSettings.themes[$0].name).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                    .independentGlassRow()
                }
                .foregroundStyle(palette.primary)
                .scrollContentBackground(.hidden)
                .background { AppThemeCanvas().ignoresSafeArea() }
                .safeAreaInset(edge: .top, spacing: 8) {
                    ReaderAppearancePreview(settings: settings).padding(.horizontal, 16)
                }
                .navigationTitle("阅读设置")
                .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .overlay {
            if loading && (!text.isEmpty || !blocks.isEmpty || !pages.isEmpty) {
                ZStack {
                    Color.clear.contentShape(Rectangle())
                    ProgressView("正在加载章节…")
                        .padding(18).modifier(SettingsGlassSurface())
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let target = retryTarget, !loading {
                VStack(spacing: 8) {
                    Text(error ?? "章节加载失败").appFont(.caption).lineLimit(2)
                    HStack {
                        Button("重试加载") { loadChapter(target, landing: retryLanding) }
                        Button("留在本章") { retryTarget = nil; error = nil }
                    }
                }
                .padding().frame(maxWidth: .infinity).modifier(SettingsGlassSurface()).padding(12)
            }
        }
        .sheet(item: $commentURL) { link in CommentSheet(url: link) }
        .onChange(of: scenePhase) { phase in
            if phase != .active { persistContinuousProgress(); store.flushProgress(); closeReadingSession() }
            else if !loading, chapters.indices.contains(index) { noteReadingChapter(index) }
        }
        .onChange(of: readingFonts.selectedPostScriptName) { _ in
            speech.stop()
            cancelPreparation()
            preparedChapters.removeAll()
            // Existing Character offsets keep paged reading at the nearest page;
            // scroll layoutID below asks the native container to preserve its anchor.
            repaginate()
        }
        .onChange(of: bubbleStyles.revision) { _ in
            cancelPreparation()
            preparedChapters.removeAll()
            repaginate()
            if settings.pageMode == 0, !loading { resetScroll(landing: .saved(store.scrollPosition(book))) }
        }
        .onChange(of: settings.fontSize) { _ in repaginate() }
        .onChange(of: settings.lineSpacing) { _ in repaginate() }
        .onChange(of: settings.paragraphSpacing) { _ in repaginate() }
        .onChange(of: settings.fullJustify) { _ in repaginate() }
        .onChange(of: settings.bottomJustify) { _ in repaginate() }
        .onChange(of: settings.leftMargin) { _ in repaginate() }
        .onChange(of: settings.rightMargin) { _ in repaginate() }
        .onChange(of: settings.topMargin) { _ in repaginate() }
        .onChange(of: settings.bottomMargin) { _ in repaginate() }
        .onChange(of: settings.pageMode) { mode in
            speech.stop()
            pendingEdge = nil
            pendingChapterDirection = 0
            if mode == 1 {
                persistContinuousProgress()
                cancelScrollLoads()
                scrollChapters.removeAll()
                pendingLanding = .saved(scrollProgress.position)
                repaginate(keepOffset: 0)
            } else {
                cancelPreparation()
                preparedChapters.removeAll()
                if chapters.indices.contains(index), !loading { resetScroll(landing: .saved(store.scrollPosition(book))) }
            }
        }
        .onChange(of: pageIndex) { _ in syncMenuProgress() }
        .onChange(of: pages.count) { _ in syncMenuProgress() }
        .onChange(of: loading) { value in if !value { syncMenuProgress() } }
        .onChange(of: index) { _ in speech.stop(); syncMenuProgress() }
        .onChange(of: screenSize) { _ in repaginate() }
        .onChange(of: pageInsets) { _ in repaginate() }
        .onDisappear {
            speech.stop()
            persistContinuousProgress()
            closeReadingSession()
            cancelScrollLoads()
            cancelPreparation()
            preparedChapters.removeAll()
            contentRequestID = nil
            chapterTask?.cancel()
            chapterTask = nil
            prefetchTask?.cancel()
            prefetchTask = nil
            pendingEdge = nil
            pendingChapterDirection = 0
            loading = false
            pendingLanding = nil
            store.flushProgress()
        }
        .task { await start() }
    }

    private var quickEnabled: Set<String> {
        var items: Set<String> = ["rules"]
        if !chapters.isEmpty { items.insert("bookmarks") }
        if chapters.indices.contains(index) { items.insert("refresh") }
        if !store.isLocal(book), let source = store.source(for: book.origin) {
            items.formUnion(["toc", "source"])
            if chapters.indices.contains(index), !chapters[index].isVolume { items.insert("clear") }
            if !(source.loginUrl ?? "").isEmpty || !(source.loginUi ?? "").isEmpty { items.insert("login") }
        }
        if quickBrowserURL != nil { items.insert("browser") }
        return items
    }

    /// 书源已保存登录凭据（登录成功后脚本或表单写入）即视为已登录，只读本机，不联网探测。
    private var quickLoggedIn: Bool {
        guard !store.isLocal(book), let source = store.source(for: book.origin) else { return false }
        return SourceLoginStatus.state(key: source.bookSourceUrl, login: JSEngine.loginStore,
                                       defaults: .standard) != .none
    }

    private var quickBrowserURL: String? {
        guard !store.isLocal(book) else { return nil }
        return SourceLoginForm.browserURL(AnalyzeUrl.absolute(book.bookUrl, base: book.origin))
    }

    private func quickAction(_ action: String) {
        switch action {
        case "refresh": Task { await quickReload(clear: false) }
        case "clear": confirmChapterClear = true
        case "toc":
            Task { @MainActor in
                guard !quickBusy else { return }
                quickBusy = true
                quickMessage = "正在刷新目录…"
                quickMessage = await refreshToc()
                quickBusy = false
            }
        case "login": quickLogin = true
        case "rules": quickRules = true
        case "bookmarks": showBookmarks = true
        case "source": quickSources = true
        case "browser":
            if let url = quickBrowserURL { quickBrowser = BrowserTarget(url: url, title: book.name) }
        default: break
        }
    }

    @MainActor
    private func quickReload(clear: Bool) async {
        guard !quickBusy, !loading, chapters.indices.contains(index) else { return }
        quickBusy = true
        defer { quickBusy = false }
        let target = index
        let position = store.scrollPosition(book)
        do {
            cancelPreparation()
            preparedChapters.removeAll()
            prefetchTask?.cancel()
            cancelScrollLoads()
            if clear, let source = store.source(for: book.origin) {
                ChapterPrecacheManager.shared.cancelPrecache()
                try await ChapterContentCache.shared.removeChapter(for: ChapterContentKey(
                    sourceURL: source.bookSourceUrl, bookURL: book.bookUrl, chapterURL: chapters[target].url))
            }
            bodyReplacement = BodyReplaceEngine(rules: BodyReplaceRepository().rules())
            let request = UUID()
            contentRequestID = request
            loading = true
            await loadContent(at: target, landing: .saved(position), requestID: request)
            quickMessage = error ?? (clear ? "当前章节缓存已清除并刷新" : "当前章节已刷新")
        } catch {
            quickMessage = "刷新失败：\(error.localizedDescription)"
        }
    }

    private var readerSourceName: String {
        if !book.originName.isEmpty { return book.originName }
        return store.source(for: book.origin)?.bookSourceName ?? (store.isLocal(book) ? "本地书籍" : "未知书源")
    }

    /// 注册预缓存管理器：注入当前书籍的目录、索引与缓存服务。
    /// 预缓存进度条在「我的」页面显示，不在目录页，避免目录卡顿。
    private func registerPrecache() {
        let canPrecache = !store.isLocal(book) && store.source(for: book.origin) != nil
        let services: ReaderTocServices?
        if canPrecache, let source = store.source(for: book.origin) {
            let sourceURL = source.bookSourceUrl
            let bookURL = book.bookUrl
            services = ReaderTocServices(
                isCached: { chapter in
                    await ChapterContentCache.shared.hasCached(for: ChapterContentKey(
                        sourceURL: sourceURL, bookURL: bookURL, chapterURL: chapter.url))
                },
                load: { chapter, nextChapterURL in
                    _ = try await ChapterContentLoader.content(source: source, book: book, chapter: chapter,
                                                               nextChapterURL: nextChapterURL, priority: .utility)
                })
        } else {
            services = nil
        }
        ChapterPrecacheManager.shared.register(chapters: chapters, currentIndex: index,
                                               bookName: book.name, services: services,
                                               canPrecache: canPrecache)
    }

    /// 本地书籍没有书源，不提供刷新目录按钮。
    private var tocRefreshAction: (@MainActor () async -> String?)? {
        guard !store.isLocal(book) else { return nil }
        return { await refreshToc() }
    }

    /// 目录页「刷新目录」：重新从书源拉取目录并写回缓存；当前章按章节地址重新定位，
    /// 失败或返回空目录时保留现有目录不变。
    @MainActor
    private func refreshToc() async -> String? {
        guard let source = store.source(for: book.origin) else { return "找不到书源" }
        do {
            var b = book
            if b.tocUrl == nil { b = try await WebBook.bookInfo(source: source, book: b) }
            let latest = try await WebBook.chapters(source: source, book: b)
            guard !latest.isEmpty else { return "书源返回空目录，已保留原目录" }
            let oldCount = chapters.count
            let currentURL = chapters.indices.contains(index) ? chapters[index].url : nil
            chapters = latest
            store.saveToc(book, latest)
            if let currentURL, let found = latest.firstIndex(where: { $0.url == currentURL }) {
                if found != index { index = found }
            } else if index >= latest.count {
                index = latest.count - 1
            }
            registerPrecache()
            ChapterPrecacheManager.shared.refreshCacheStatusIfNeeded()
            let added = latest.count - oldCount
            return added > 0 ? "目录已刷新：新增 \(added) 章，共 \(latest.count) 章" : "目录已刷新：共 \(latest.count) 章"
        } catch {
            return "刷新失败：\(error.localizedDescription)"
        }
    }

    private var readerChapterTitle: String {
        chapters.indices.contains(index) ? chapters[index].title : "正在加载章节…"
    }

    private var readerBlocks: [ContentBlock] {
        blocks.isEmpty ? Paginator.blocks(fromPlain: text) : blocks
    }

    private var canScrubReader: Bool {
        !loading && (settings.pageMode == 1 ? pages.count > 1 : !readerBlocks.isEmpty)
    }

    private var readerPositionLabel: String {
        if settings.pageMode == 1 {
            guard !pages.isEmpty else { return "— / —" }
            let value = scrubbing ? Int((menuProgress * Double(max(pages.count - 1, 0))).rounded()) : pageIndex
            return "\(min(max(value + 1, 1), pages.count)) / \(pages.count)"
        }
        return "\(Int((menuProgress * 100).rounded()))%"
    }

    private func syncMenuProgress() {
        guard !scrubbing else { return }
        if settings.pageMode == 1 {
            menuProgress = pages.count > 1 ? Double(pageIndex) / Double(pages.count - 1) : 0
        } else {
            menuProgress = Double(scrollProgress.position) / 1000
        }
    }

    private func scrubReader(_ editing: Bool) {
        scrubbing = editing
        guard !editing, canScrubReader else { return }
        speech.stop()
        let progress = min(max(menuProgress, 0), 1)
        if settings.pageMode == 1 {
            pageIndex = Int((progress * Double(pages.count - 1)).rounded())
        } else {
            let position = Int((progress * 1000).rounded())
            scrollProgress.chapter = index
            scrollProgress.position = position
            scrollRequest = ReaderScrollRequest(id: UUID(), chapter: index, permille: position)
            persistContinuousProgress()
        }
    }

    private func toggleSpeech() {
        if speech.isSpeaking { speech.stop(); return }
        guard !loading else { return }
        let paragraphs = ReaderMenuText.paragraphs(readerBlocks)
        let start = settings.pageMode == 1 && pages.indices.contains(pageIndex) ? pages[pageIndex].startOffset : 0
        let remaining = paragraphs.compactMap { paragraph -> String? in
            let skip = max(start - paragraph.offset, 0)
            guard skip < paragraph.text.count else { return nil }
            return String(paragraph.text.dropFirst(skip))
        }.joined(separator: "\n")
        speech.speak(remaining)
    }

    private func selectSearchResult(_ offset: Int) {
        guard settings.pageMode == 1, !pages.isEmpty else { return }
        speech.stop()
        pageIndex = Paginator.pageIndex(containing: offset, in: pages)
        showReaderSearch = false
        showBars = false
    }

    private func start() async {
        // Stable per-reader snapshot: current and prefetched chapters use identical rules.
        bodyReplacement = BodyReplaceEngine(rules: BodyReplaceRepository().rules())
        if store.isLocal(book) { await startLocal(); return }
        guard let s = store.source(for: book.origin) else { error = "找不到书源"; loading = false; return }
        index = requestedChapter ?? (store.books.first(where: { $0.bookUrl == book.bookUrl })?.durChapterIndex ?? book.durChapterIndex)
        if let c = store.cachedToc(book), !c.isEmpty {
            chapters = c
        } else {
            do {
                var b = book
                if b.tocUrl == nil { b = try await WebBook.bookInfo(source: s, book: b) }
                chapters = try await WebBook.chapters(source: s, book: b)
                store.saveToc(book, chapters)
            } catch {
                self.error = "目录加载失败：\(error.localizedDescription)"
                loading = false
                return
            }
        }
        if chapters.isEmpty { error = "目录为空，书源可能不兼容"; loading = false; return }
        registerPrecache()
        let initial = min(max(index, 0), chapters.count - 1)
        guard let first = readableIndex(from: initial, direction: 1)
                ?? readableIndex(from: initial, direction: -1) else {
            error = "目录中没有可读章节"; loading = false; return
        }
        index = first
        await loadInitialChapter()
    }

    private func startLocal() async {
        index = requestedChapter ?? (store.books.first(where: { $0.bookUrl == book.bookUrl })?.durChapterIndex ?? book.durChapterIndex)
        guard let toc = store.localToc(book), !toc.isEmpty else { error = "本地书文件已丢失，请重新导入"; loading = false; return }
        chapters = toc
        index = min(max(index, 0), toc.count - 1)
        registerPrecache()
        await loadInitialChapter()
    }

    private func loadInitialChapter() async {
        let saved = requestedChapter == nil ? store.scrollPosition(book) : 0
        let requestID = UUID()
        contentRequestID = requestID
        loading = true
        await loadContent(at: index, landing: saved > 0 ? .saved(saved) : .start, requestID: requestID)
    }

    // MARK: 连续滚动

    @ViewBuilder
    private var continuousScrollBody: some View {
        if scrollChapters.isEmpty {
            VStack {
                if loading { ProgressView() }
                else if let error { Text(error).foregroundStyle(.red) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ReaderContinuousScrollView(chapters: scrollChapters.map { chapter in
                ReaderScrollChapter(id: chapter.id, revision: chapter.revision,
                                    content: AnyView(scrollChapterBody(chapter)),
                                    appearanceID: "\(settings.theme)-\(scrollBoundaryRevision(for: chapter.id))")
            }, request: scrollRequest,
                layoutID: "\(settings.typographyValues)|\(readingFonts.selectedPostScriptName)",
                background: UIColor(theme.bg),
                onPosition: { chapter, position in recordContinuousPosition(chapter, position: position) },
                onApproachEdge: { direction in loadScrollNeighbor(direction) },
                onSettled: { chapter, position in
                    recordContinuousPosition(chapter, position: position)
                    persistContinuousProgress()
                    if showBars { syncMenuProgress() }
                })
        }
    }

    private func scrollBoundaryRevision(for chapter: Int) -> String {
        let directions = [-1, 1].filter { ($0 < 0 ? scrollChapters.first?.id : scrollChapters.last?.id) == chapter }
        return directions.map { direction in
            guard let target = scrollNeighbor(direction) else { return "\(direction):end" }
            return "\(direction):\(target):\(scrollTasks[target] != nil):\(scrollErrors[target] ?? "")"
        }.joined(separator: "|")
    }

    private func scrollParagraphLeadingGap(in blocks: [ContentBlock], at index: Int) -> CGFloat {
        guard index > 0, case .paragraph = blocks[index - 1], case .paragraph = blocks[index] else { return 0 }
        return ReaderTextLayout.paragraphGap(lineSpacing: CGFloat(settings.lineSpacingPoints), paragraphSpacing: 0)
    }

    private func scrollChapterBody(_ content: ScrollReaderChapter) -> some View {
        let chapter = chapters[content.id]
        return VStack(alignment: .leading, spacing: CGFloat(settings.paragraphSpacingPoints)) {
            if chapter.isVolume {
                VolumeTitleView(title: chapter.title, foreground: theme.fg)
                    .padding(.vertical, 36)
                    .contentShape(Rectangle())
                    .onTapGesture { toggleBars() }
            } else {
                ChapterTitleView(title: chapter.title, fontSize: CGFloat(settings.fontSize), color: UIColor(theme.fg))
                    .padding(.top, max(CGFloat(settings.fontSize), 20))
                    .padding(.bottom, max(CGFloat(settings.fontSize) * 0.8, 14))
                    .contentShape(Rectangle())
                    .onTapGesture { toggleBars() }
                ForEach(Array(content.readingBlocks.enumerated()), id: \.offset) { index, block in
                    blockView(block)
                        .padding(.top, scrollParagraphLeadingGap(in: content.readingBlocks, at: index))
                }
            }
        }
        .foregroundStyle(theme.fg)
        .padding(.leading, CGFloat(settings.leftMargin))
        .padding(.trailing, CGFloat(settings.rightMargin))
        .padding(.top, CGFloat(settings.topMargin))
        .padding(.bottom, max(CGFloat(settings.bottomMargin), 20))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.bg.contentShape(Rectangle()).onTapGesture { toggleBars() })
        .overlay(alignment: .top) {
            if content.id == scrollChapters.first?.id { scrollBoundary(-1) }
        }
        .overlay(alignment: .bottom) {
            if content.id == scrollChapters.last?.id { scrollBoundary(1) }
        }
    }

    @ViewBuilder
    private func scrollBoundary(_ direction: Int) -> some View {
        if let target = scrollNeighbor(direction) {
            if let message = scrollErrors[target] {
                VStack(spacing: 8) {
                    Text(message).appFont(.caption).foregroundStyle(theme.fg.opacity(0.65)).lineLimit(2)
                    Button("重试加载\(direction > 0 ? "下一章" : "上一章")") { loadScrollNeighbor(direction, retry: true) }
                }
                .frame(maxWidth: .infinity).padding(.vertical, 10).background(theme.bg.opacity(0.96))
            } else if scrollTasks[target] != nil {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 4).allowsHitTesting(false)
            }
        }
    }

    private func scrollNeighbor(_ direction: Int) -> Int? {
        guard let edge = direction > 0 ? scrollChapters.last?.id : scrollChapters.first?.id else { return nil }
        return readableIndex(from: edge + direction, direction: direction)
    }

    private func cancelScrollLoads() {
        scrollGeneration = UUID()
        scrollTasks.values.forEach { $0.cancel() }
        scrollTasks.removeAll()
    }

    private func resetScroll(landing: ChapterLanding) {
        cancelScrollLoads()
        scrollErrors.removeAll()
        scrollChapters = [ScrollReaderChapter(id: index, text: text, blocks: blocks)]
        let position: Int
        switch landing {
        case .start: position = 0
        case .end: position = 1000
        case .saved(let value): position = value
        }
        scrollProgress.chapter = index
        scrollProgress.position = position
        scrollRequest = ReaderScrollRequest(id: UUID(), chapter: index, permille: position)
        loadScrollNeighbor(1)
        loadScrollNeighbor(-1)
    }

    private func loadScrollNeighbor(_ direction: Int, retry: Bool = false) {
        guard settings.pageMode == 0, let target = scrollNeighbor(direction), scrollTasks[target] == nil,
              !scrollChapters.contains(where: { $0.id == target }), retry || scrollErrors[target] == nil else { return }
        // 保留当前章前后窗口；短章不会仅因屏幕尚未填满而预读整本书。
        if let position = scrollChapters.firstIndex(where: { $0.id == index }),
           (direction > 0 ? scrollChapters.count - position - 1 : position) >= 2 { return }
        scrollErrors[target] = nil
        let generation = scrollGeneration
        scrollTasks[target] = Task { @MainActor in
            defer { if scrollGeneration == generation { scrollTasks[target] = nil } }
            do {
                let raw = try await rawContent(at: target, priority: .utility)
                try Task.checkCancellation()
                guard scrollGeneration == generation, settings.pageMode == 0,
                      scrollNeighbor(direction) == target else { return }
                let isVolume = chapters[target].isVolume
                let replacement = bodyReplacement
                let chapter = await Task.detached(priority: .utility) {
                    let parsed = ReaderChapterParser.content(raw: raw, isVolume: isVolume, replacement: replacement)
                    return ScrollReaderChapter(id: target, text: parsed.text, blocks: parsed.blocks)
                }.value
                try Task.checkCancellation()
                guard scrollGeneration == generation, scrollNeighbor(direction) == target else { return }
                if direction > 0 { scrollChapters.append(chapter) }
                else { scrollChapters.insert(chapter, at: 0) }
                trimScrollChapters()
            } catch is CancellationError {
                return
            } catch {
                guard scrollGeneration == generation else { return }
                scrollErrors[target] = "章节加载失败：\(error.localizedDescription)"
            }
        }
    }

    private func trimScrollChapters() {
        guard let position = scrollChapters.firstIndex(where: { $0.id == index }) else { return }
        let start = max(position - 2, 0), end = min(position + 3, scrollChapters.count)
        if start > 0 || end < scrollChapters.count { scrollChapters = Array(scrollChapters[start..<end]) }
    }

    private func recordContinuousPosition(_ chapter: Int, position: Int) {
        guard settings.pageMode == 0, !loading, !showToc, !showSettings, commentURL == nil,
              scrollChapters.contains(where: { $0.id == chapter }) else { return }
        scrollProgress.chapter = chapter
        scrollProgress.position = position
    }

    private func persistContinuousProgress() {
        guard !loading, let content = scrollChapters.first(where: { $0.id == scrollProgress.chapter }) else { return }
        let chapter = content.id
        if index != chapter {
            index = chapter
            text = content.text
            blocks = content.blocks
            store.updateProgress(book, index: chapter, title: chapters[chapter].title)
            noteReadingChapter(chapter)
            trimScrollChapters()
            loadScrollNeighbor(1)
            loadScrollNeighbor(-1)
            if let source = store.source(for: book.origin) { prefetch(source) }
        }
        store.updateScrollPosition(book, permille: scrollProgress.position)
    }

    /// 一次阅读会话从首次成功加载本章开始，到离开页面/退到后台结束。
    private func noteReadingChapter(_ chapter: Int) {
        if statsStart == nil { statsStart = Date() }
        statsChapters.insert(chapter)
    }

    private func closeReadingSession() {
        guard let start = statsStart else { return }
        statsStart = nil
        let chapters = statsChapters
        statsChapters = []
        ReadingStatsStore.shared.record(book: book, start: start, end: Date(), chapters: chapters.sorted())
    }

    // MARK: 翻页模式

    private var turnStyle: PageTurnStyle { PageTurnStyle(rawValue: settings.pageTurnStyle) ?? .slide }

    private func pageConfiguration(for target: Int) -> ReaderPaginator.Configuration {
        ReaderPaginator.Configuration(
            pageSize: screenSize,
            safeInsets: UIEdgeInsets(top: pageInsets.top, left: pageInsets.leading,
                                     bottom: pageInsets.bottom, right: pageInsets.trailing),
            fontSize: CGFloat(settings.fontSize),
            lineSpacing: CGFloat(settings.lineSpacingPoints),
            paragraphSpacing: CGFloat(settings.paragraphSpacingPoints),
            fullJustify: settings.fullJustify,
            bottomJustify: settings.bottomJustify,
            leftInset: CGFloat(settings.leftMargin),
            rightInset: CGFloat(settings.rightMargin),
            topInset: CGFloat(settings.topMargin),
            bottomInset: CGFloat(settings.bottomMargin),
            chapterTitle: chapters.indices.contains(target) && !chapters[target].isVolume ? chapters[target].title : "")
    }

    /// 正文与邻章共享版式；只在布局改变时换标识，主题变化直接重绘各个纸面。
    private func repaginate(keepOffset: Int? = nil) {
        cancelPreparation()
        guard settings.pageMode == 1, screenSize.width > 0 else {
            preparedChapters.removeAll()
            return
        }
        defer {
            rememberCurrentChapter()
            prepareNearbyChapters()
        }
        if currentVolume != nil {
            pages = [BookPage(blocks: [], startOffset: 0)]
            pageContentID = UUID().uuidString
            pageIndex = 0
            pendingLanding = nil
            return
        }
        let source = readingBlocks
        guard !source.isEmpty else { pages = []; return }
        let offset = keepOffset ?? (pages.indices.contains(pageIndex) ? pages[pageIndex].startOffset : 0)
        pages = ReaderPaginator.paginate(source, configuration: pageConfiguration(for: index))
        pageContentID = UUID().uuidString
        pageIndex = Paginator.pageIndex(containing: offset, in: pages)
        if !pages.isEmpty, let landing = pendingLanding {
            switch landing {
            case .start: pageIndex = 0
            case .end: pageIndex = pages.count - 1
            case .saved(let permille):
                let total = max((pages.last?.startOffset ?? 0) + 1, 1)
                pageIndex = Paginator.pageIndex(containing: Int(Double(total) * Double(permille) / 1000), in: pages)
            }
            pendingLanding = nil
        }
    }

    private func cancelPreparation() {
        preparationTask?.cancel()
        preparationTask = nil
        preparationID = UUID()
    }

    private func rememberCurrentChapter() {
        guard settings.pageMode == 1, chapters.indices.contains(index), !pages.isEmpty else { return }
        preparedChapters[index] = PreparedReaderChapter(index: index, contentID: pageContentID,
            text: text, blocks: blocks, pages: pages, configuration: pageConfiguration(for: index))
    }

    /// 在手势前准备真实相邻页。网络仍走共享缓存，UIKit 分页只在主线程执行。
    private func prepareNearbyChapters() {
        cancelPreparation()
        guard settings.pageMode == 1, screenSize.width > 0, !pages.isEmpty else { return }
        let center = index
        let targets = [nextChapter, previousChapter].compactMap { $0 }
        let retained = Set(targets + [center])
        preparedChapters = preparedChapters.filter { retained.contains($0.key) }
        let token = preparationID
        preparationTask = Task { @MainActor in
            // 先让当前页提交给 UIKit；预排版不是在 dataSource 查询/触摸回调里进行。
            await Task.yield()
            for target in targets {
                guard !Task.isCancelled, preparationID == token, index == center else { return }
                let configuration = pageConfiguration(for: target)
                if preparedChapters[target]?.configuration == configuration { continue }
                do {
                    let content: (text: String, blocks: [ContentBlock])
                    if let existing = preparedChapters[target] {
                        content = (existing.text, existing.blocks)
                    } else {
                        let raw = try await rawContent(at: target, priority: .utility)
                        content = ReaderChapterParser.content(raw: raw, isVolume: chapters[target].isVolume, replacement: bodyReplacement)
                    }
                    try Task.checkCancellation()
                    guard preparationID == token, index == center,
                          configuration == pageConfiguration(for: target) else { return }
                    let source = content.blocks.isEmpty ? Paginator.blocks(fromPlain: content.text) : content.blocks
                    let laidOut = chapters[target].isVolume
                        ? [BookPage(blocks: [], startOffset: 0)]
                        : ReaderPaginator.paginate(source, configuration: configuration)
                    guard !laidOut.isEmpty else { continue }
                    preparedChapters[target] = PreparedReaderChapter(index: target,
                        contentID: UUID().uuidString, text: content.text, blocks: content.blocks,
                        pages: laidOut, configuration: configuration)
                    await Task.yield()
                } catch is CancellationError {
                    return
                } catch {
                    // 预读失败不改当前章、不写进度；用户翻到边界时走正常加载/重试。
                    continue
                }
            }
            if preparationID == token { preparationTask = nil }
        }
    }

    private func adoptPreparedChapter(_ prepared: PreparedReaderChapter, page: Int) {
        guard chapters.indices.contains(prepared.index), prepared.pages.indices.contains(page) else { return }
        cancelPreparation()
        chapterTask?.cancel()
        chapterTask = nil
        contentRequestID = nil
        prefetchTask?.cancel()
        prefetchTask = nil
        index = prepared.index
        pageContentID = prepared.contentID
        text = prepared.text
        blocks = prepared.blocks
        pages = prepared.pages
        pageIndex = page
        preparedChapters[prepared.index] = prepared
        loading = false
        error = nil
        retryTarget = nil
        pendingLanding = nil
        pendingEdge = nil
        pendingChapterDirection = 0
        store.updateProgress(book, index: index, title: chapters[index].title)
        noteReadingChapter(index)
        recordPage(page)
        // 只有 UIKit 确认提交才写入章号；取消手势不会来到这里。
        // 若手势中版式改变，必须先让容器收到原快照 ID 的接纳，再由完成回调重排；
        // 单纯 main.async 可能被 SwiftUI 合并，导致容器一直等不到接纳 ID。
        if prepared.configuration == pageConfiguration(for: index) { prepareNearbyChapters() }
        if let source = store.source(for: book.origin) { prefetch(source) }
    }

    private var currentVolume: BookChapter? {
        guard chapters.indices.contains(index), chapters[index].isVolume else { return nil }
        return chapters[index]
    }

    private var readingBlocks: [ContentBlock] {
        blocks.isEmpty ? Paginator.blocks(fromPlain: text) : blocks
    }

    private func updateViewport(_ geo: GeometryProxy) {
        let window = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow)
        let safe = window?.safeAreaInsets ?? .zero
        pageInsets = EdgeInsets(top: safe.top, leading: safe.left, bottom: safe.bottom, trailing: safe.right)
        screenSize = geo.size
    }

    private func renderedPages(_ chapterPages: [BookPage], at target: Int) -> [AnyView] {
        let chapter = chapters.indices.contains(target) ? chapters[target] : nil
        return chapterPages.enumerated().map { i, page in
            AnyView(PageContentView(page: page, fontSize: settings.fontSize,
                lineSpacing: settings.lineSpacingPoints, fg: theme.fg, bg: theme.bg,
                title: chapter?.title ?? "",
                pageNumber: i + 1, pageCount: chapterPages.count,
                onTapComment: { commentTapped($0) }, selection: textSelectionActions,
                onCopyImage: { copyImage($0) }, onSaveImage: { saveImageToPhotos($0) }, safeInsets: pageInsets,
                paragraphSpacing: settings.paragraphSpacingPoints,
                leftMargin: settings.leftMargin, rightMargin: settings.rightMargin,
                topMargin: settings.topMargin, bottomMargin: settings.bottomMargin,
                volumeTitle: chapter?.isVolume == true ? chapter?.title : nil,
                showsChapterTitle: chapter?.isVolume != true).ignoresSafeArea())
        }
    }

    private func preparedChapter(at target: Int?) -> PreparedReaderChapter? {
        guard let target, let prepared = preparedChapters[target],
              prepared.configuration == pageConfiguration(for: target) else { return nil }
        return prepared
    }

    private func pageTurnChapter(_ prepared: PreparedReaderChapter?) -> PageTurnChapter? {
        guard let prepared else { return nil }
        return PageTurnChapter(contentID: prepared.contentID,
                               pages: renderedPages(prepared.pages, at: prepared.index))
    }

    private var pageTurnContainer: some View {
        let previous = preparedChapter(at: previousChapter)
        let next = preparedChapter(at: nextChapter)
        return PageTurnView(pages: renderedPages(pages, at: index), current: $pageIndex, style: turnStyle,
                     background: UIColor(theme.bg),
                     onEdge: { dir in DispatchQueue.main.async { goAcrossEdge(dir) } },
                     onTapCenter: { toggleBars() }, contentID: pageContentID,
                     chapterDirection: pendingChapterDirection,
                     onContentTransitionCompleted: {
                         pendingEdge = nil
                         pendingChapterDirection = 0
                         if let current = preparedChapters[index], current.contentID == pageContentID,
                            current.configuration != pageConfiguration(for: index) { repaginate() }
                     },
                     previousChapter: pageTurnChapter(previous),
                     nextChapter: pageTurnChapter(next),
                     onChapterTransition: { direction, page in
                         if let target = direction > 0 ? next : previous {
                             adoptPreparedChapter(target, page: page)
                         }
                     })
    }

    @ViewBuilder
    private var pagedBody: some View {
        if pages.isEmpty {
            VStack { if loading { ProgressView() } else if let e = error { Text(e).foregroundStyle(.red) } else { Text("") } }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onTapGesture { toggleBars() }
        } else {
            pageTurnContainer
                .id("turn-style-\(settings.pageTurnStyle)")
                .ignoresSafeArea()
                .onChange(of: pageIndex) { i in recordPage(i) }
        }
    }

    /// 翻页模式的位置 = 当前页第一个字的字符偏移；换算成千分比存进已有的 durChapterPos，滚动模式也能读。
    private func recordPage(_ i: Int) {
        guard !loading, retryTarget == nil, pages.indices.contains(i), let last = pages.last else { return }
        let total = max(last.startOffset + 1, 1)
        store.updateScrollPosition(book, permille: Int(Double(pages[i].startOffset) / Double(total) * 1000))
    }

    private var nextChapter: Int? { readableIndex(from: index + 1, direction: 1) }
    private var previousChapter: Int? { readableIndex(from: index - 1, direction: -1) }

    private func goAcrossEdge(_ dir: Int) {
        guard !loading, pendingEdge == nil, !showToc, !showSettings, commentURL == nil, !commentBusy else { return }
        let step = dir > 0 ? 1 : -1
        guard let target = readableIndex(from: index + step, direction: step) else { return }
        // 必须直到这次请求成功/失败才解锁，不能用固定 0.6 秒窗口。
        pendingEdge = step
        pendingChapterDirection = settings.pageMode == 1 ? step : 0
        loadChapter(target, landing: step < 0 && settings.pageMode == 1 ? .end : .start)
    }

    /// 点击评论：网址直接弹评论页；`js:` 开头是书源函数调用，先在后台执行拿到网址。
    private func openComment(_ target: String?) {
        guard let t = target, !t.isEmpty else { return }
        if t.hasPrefix("js:") {
            guard let src = store.source(for: book.origin), !commentBusy else { return }
            commentBusy = true
            let call = String(t.dropFirst(3))
            Task {
                let url = await Task.detached { JSEngine.shared.resolveClickURL(source: src, click: call) }.value
                commentBusy = false
                if let u = url, let link = URL(string: u) { commentURL = link }
            }
        } else if let link = URL(string: t) {
            commentURL = link
        }
    }

    @ViewBuilder
    private func blockView(_ block: ContentBlock) -> some View {
        switch block {
        case .paragraph(let t, let count, let url):
            InlineCommentParagraph(text: t, count: count,
                                    fontSize: settings.fontSize,
                                    lineSpacing: settings.lineSpacingPoints,
                                    color: UIColor(theme.fg),
                                    fullJustify: settings.fullJustify,
                                    onTextTap: { toggleBars() },
                                    selection: textSelectionActions,
                                    onTap: { commentTapped(url) })
                .frame(maxWidth: .infinity, alignment: .leading)
        case .inlineBubble:
            EmptyView()
        case .image(let src, let click):
            ContentImageView(src: src)
                .onTapGesture { commentTapped(click) }
                .contextMenu {
                    Button { copyImage(src) } label: { Label("拷贝图像", systemImage: "doc.on.doc") }
                    Button { saveImageToPhotos(src) } label: { Label("保存到相机胶卷", systemImage: "square.and.arrow.down") }
                }
        case .hotComment(let label, let t, let click):
            HStack(spacing: 10) {
                Text(label).appFont(.system(size: max(settings.fontSize - 5, 11), weight: .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(Capsule().fill(Color(white: 0.23)))
                Text(t).appFont(.system(size: max(settings.fontSize - 3, 12))).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 22).fill(theme.fg.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(theme.fg.opacity(0.12), lineWidth: 0.5))
            .contentShape(Rectangle())
            .onTapGesture { commentTapped(click) }
        case .chapterComments(let title, let count, _, let click):
            HStack {
                Text(title).appFont(.system(size: settings.fontSize - 2, weight: .bold))
                Spacer()
                Text(count).appFont(.system(size: settings.fontSize - 4)).foregroundStyle(theme.fg.opacity(0.7))
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 16).fill(theme.fg.opacity(0.07)))
            .contentShape(Rectangle())
            .onTapGesture { commentTapped(click) }
        }
    }

    private func readableIndex(from value: Int, direction: Int) -> Int? {
        ChapterNavigation.displayIndex(from: value, direction: direction, chapters: chapters)
    }

    private func go(_ i: Int) {
        guard !loading, let target = readableIndex(from: i, direction: i >= index ? 1 : -1) else { return }
        loadChapter(target, landing: .start)
    }

    /// 打开书签：跳到原章节，并尽量回到记录的位置。
    private func openBookmark(_ item: ReaderBookmark) {
        guard chapters.indices.contains(item.chapterIndex) else { return }
        let landing: ChapterLanding = settings.pageMode == 1 ? .start : .saved(item.position)
        if item.chapterIndex == index { return }
        loadChapter(item.chapterIndex, landing: landing)
    }

    /// 长按选词的菜单动作：拷贝走系统剪贴板，替换用选中文字新建净化规则，书签记录选段。
    private var textSelectionActions: ReaderTextSelectionActions {
        ReaderTextSelectionActions(
            onCopy: { UIPasteboard.general.string = $0 },
            onReplace: { selected in
                selectedText = selected
                showReplaceFromSelection = true
            },
            onBookmark: { selected in bookmarkSelection(selected) })
    }

    private func bookmarkSelection(_ selected: String) {
        let added = ReaderBookmarkStore.shared.toggle(ReaderBookmark(
            id: UUID().uuidString, bookURL: book.bookUrl, bookName: book.name,
            chapterIndex: index, chapterTitle: readerChapterTitle,
            text: selected, position: currentReadingPosition(), createdAt: Date()))
        bookmarkNotice = added ? "已加入书签" : "已取消书签"
        let notice = bookmarkNotice
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if bookmarkNotice == notice { bookmarkNotice = nil }
        }
    }

    /// 当前章内位置：滚动模式用千分比，分页模式用页码，仅用于书签回到原处。
    private func currentReadingPosition() -> Int {
        settings.pageMode == 1 ? pageIndex : scrollProgress.position
    }

    /// 图片长按：拷贝图像（走剪贴板）与保存到相册。data: URI 与网络地址都支持。
    private func copyImage(_ src: String) {
        Task { @MainActor in
            guard let image = await ReaderImageExport.image(from: src) else {
                bookmarkNotice = "图片不可用"
                return
            }
            UIPasteboard.general.image = image
            bookmarkNotice = "已拷贝图像"
            let notice = bookmarkNotice
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if bookmarkNotice == notice { bookmarkNotice = nil }
        }
    }

    private func saveImageToPhotos(_ src: String) {
        Task { @MainActor in
            guard let image = await ReaderImageExport.image(from: src) else {
                bookmarkNotice = "图片不可用"
                return
            }
            let message = await ReaderImageExport.saveToPhotos(image)
            bookmarkNotice = message
            let notice = bookmarkNotice
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if bookmarkNotice == notice { bookmarkNotice = nil }
        }
    }

    private func loadChapter(_ target: Int, landing: ChapterLanding) {
        guard !loading, chapters.indices.contains(target) else { return }
        speech.stop()
        cancelScrollLoads()
        cancelPreparation()
        chapterTask?.cancel()
        // 停止旧预读队列的后续任务；在途的目标章由共享缓存接管，不会重复抓取。
        prefetchTask?.cancel()
        prefetchTask = nil
        let requestID = UUID()
        contentRequestID = requestID
        retryTarget = nil
        error = nil
        // 同一主线程回调立即上锁；不等 Task 启动后才设置 loading。
        loading = true
        chapterTask = Task { await loadContent(at: target, landing: landing, requestID: requestID) }
    }

    private func loadContent(at target: Int, landing: ChapterLanding, requestID: UUID) async {
        defer {
            if contentRequestID == requestID {
                contentRequestID = nil
                loading = false
                if settings.pageMode != 1 || pages.isEmpty { pendingChapterDirection = 0 }
                if pendingChapterDirection == 0 { pendingEdge = nil }
                chapterTask = nil
            }
        }
        guard chapters.indices.contains(target), contentRequestID == requestID else { return }
        let chapter = chapters[target]
        do {
            let raw = try await rawContent(at: target, priority: .userInitiated)
            try Task.checkCancellation()
            guard contentRequestID == requestID else { return }
            // 网络失败时不改章号、不清旧文、不覆盖已保存的阅读位置。
            index = target
            ChapterPrecacheManager.shared.updateCurrentIndex(target)
            retryTarget = nil
            error = nil
            show(raw: raw, landing: landing)
            store.updateProgress(book, index: target, title: chapter.title)
            noteReadingChapter(target)
            if settings.pageMode == 1, pages.indices.contains(pageIndex) {
                let total = max((pages.last?.startOffset ?? 0) + 1, 1)
                store.updateScrollPosition(book, permille: Int(Double(pages[pageIndex].startOffset) / Double(total) * 1000))
            } else {
                let position: Int
                switch landing {
                case .start: position = 0
                case .end: position = 1000
                case .saved(let value): position = value
                }
                store.updateScrollPosition(book, permille: position)
            }
            if let source = store.source(for: book.origin) { prefetch(source) }
        } catch is CancellationError {
            // 离开阅读器后不再呈现旧请求的错误，但取消路径也必须解锁。
            if contentRequestID == requestID { pendingEdge = nil; pendingChapterDirection = 0 }
        } catch {
            guard contentRequestID == requestID else { return }
            self.error = "正文加载失败：\(error.localizedDescription)"
            pendingEdge = nil
            pendingChapterDirection = 0
            retryTarget = target
            retryLanding = landing
        }
    }

    @MainActor
    private func rawContent(at target: Int, priority: TaskPriority) async throws -> String {
        let chapter = chapters[target]
        if chapter.isVolume { return chapter.title }
        if store.isLocal(book) {
            guard let local = store.localContent(book, index: target) else {
                throw NSError(domain: "Reader", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "本地章节文件不存在"])
            }
            return local.isEmpty ? "（本章没有内容）" : local
        }
        guard let source = store.source(for: book.origin) else {
            throw NSError(domain: "Reader", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "找不到书源"])
        }
        let next = ChapterNavigation.contentIndex(from: target + 1, direction: 1, chapters: chapters)
            .map { chapters[$0].url }
        return try await ChapterContentLoader.content(source: source, book: book, chapter: chapter,
                                                       nextChapterURL: next, priority: priority)
    }

    /// 前台与预排版使用同一解析流程，保留原始段评标记和续段字符偏移。
    private func show(raw: String, landing: ChapterLanding) {
        let content = ReaderChapterParser.content(raw: raw, isVolume: currentVolume != nil, replacement: bodyReplacement)
        text = content.text
        blocks = content.blocks
        pages = []
        pageIndex = 0
        if settings.pageMode == 1 {
            pendingLanding = landing
            repaginate(keepOffset: 0)
        } else {
            pendingLanding = nil
            resetScroll(landing: landing)
        }
    }

    private func prefetch(_ source: BookSource) {
        prefetchTask?.cancel()
        guard !store.isLocal(book) else { return }
        let snapshot = chapters
        // 预读章数由「我的 → 章节预缓存」全局设置控制，对所有书源生效。
        let limit = ChapterPrecacheManager.shared.window
        let queue = ChapterNavigation.prefetchIndices(after: index, chapters: snapshot, limit: limit)
        guard !queue.isEmpty else { prefetchTask = nil; return }
        let readingBook = book
        // 阅读时在 MainActor 外依次预读后续章节，避免同时轰击书源或阻塞正文手势。
        prefetchTask = Task.detached(priority: .utility) {
            for i in queue {
                guard !Task.isCancelled else { return }
                let next = ChapterNavigation.contentIndex(from: i + 1, direction: 1, chapters: snapshot)
                    .map { snapshot[$0].url }
                do {
                    _ = try await ChapterContentLoader.content(source: source, book: readingBook,
                        chapter: snapshot[i], nextChapterURL: next, priority: .utility)
                } catch {
                    // 不把预读失败展示成当前章错误，也不越过登录/网络失败继续请求后续章节。
                    return
                }
            }
        }
    }
}
