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
    /// imageDecode：对正文里的每张图片/气泡单独求值一次原版 imageDecode 规则。
    /// 阅读器必须走这条钩子，否则番茄系段评的「已渲染」标记不会被清掉，点击气泡打不开。
    static func content(raw: String, isVolume: Bool, replacement: BodyReplaceEngine,
                        imageDecode: ((String) -> String)? = nil) -> (text: String, blocks: [ContentBlock]) {
        if isVolume { return (raw, []) }
        let parsed = ContentBlocks.parse(raw, imageDecode: imageDecode)
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
    @State private var commentTarget: BrowserTarget?
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
    @StateObject private var aloud = ReaderAloudController()
    /// 音频书源（如喜马拉雅）章节播放。
    @StateObject private var bookAudio = BookAudioPlayer()
    /// 音频章链接过期已自动刷新重试过（每次进入章节重置，防止失败循环）。
    @State private var audioFailureRetried = false
    @State private var showAloudPanel = false
    /// 朗读驱动的翻章不停止朗读；用户手动翻章到 loadChapter 处停止。
    @State private var aloudDrivenNav = false
    /// 朗读跟随的最近一次滚动位置（千分比节流用）。
    @State private var aloudScrollPermille = -1000
    /// 漫画书源（bookSourceType == 2）：走漫画阅读器而不是文字排版。
    @State private var mangaMode = false
    @StateObject private var manga = MangaSession()

    private func toggleBars() {
        if !showBars { persistContinuousProgress(); syncMenuProgress() }
        withAnimation(.easeInOut(duration: 0.18)) { showBars.toggle() }
    }

    /// 漫画阅读器自带顶部/底部面板；它在的时候不要再叠阅读器面板（漫画页上会出两套菜单）。
    private var mangaReaderMounted: Bool {
        mangaMode && !chapters.isEmpty && !loading
    }

    /// 有声书播放器同样是整页界面，自带返回/目录/倍速/设置；
    /// 阅读器的上下栏叠上去会盖住播放键（还会出现两条进度条）。
    /// 正文照常显示、音频在后台播（书源音色 →「正文照常显示」开关）。
    /// 长按喇叭键时临时打开一次听书界面（forceAudioPlayer）。
    @State private var forceAudioPlayer = false
    /// 后台音频的正文高亮（按音频进度估算，和朗读高亮互不干扰）。
    @State private var toneHighlight = AloudHighlightModel()
    @State private var lastToneHighlightOffset = -1

    private var activeHighlight: AloudHighlightModel? {
        sourceToneBackground ? toneHighlight : aloud.highlight
    }

    private var sourceToneBackground: Bool {
        SourceToneAudio.backgroundPlayback
            && SourceToneAudio.isActive(bookUrl: book.bookUrl)
            && !forceAudioPlayer
    }

    private var audioReaderMounted: Bool {
        bookAudio.chapterURL != nil && !sourceToneBackground
    }

    /// 任何「自带面板的全屏阅读界面」都不叠阅读器 chrome。
    private var readerChromeMounted: Bool {
        !mangaReaderMounted && !audioReaderMounted
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
            if mangaMode {
                mangaBody
            } else if bookAudio.chapterURL != nil, !sourceToneBackground {
                AudioChapterView(audio: bookAudio, book: book,
                                 chapterNumber: index + 1,
                                 chapterCount: chapters.count,
                                 nextChapterTitle: chapters.indices.contains(index + 1)
                                     ? chapters[index + 1].title : nil,
                                 source: store.source(for: book.origin),
                                 onReloadAudio: { reloadAudioChapter() },
                                 onStop: {
                                     if SourceToneAudio.isActive(bookUrl: book.bookUrl) {
                                         SourceToneAudio.deactivate(bookUrl: book.bookUrl)
                                         BookKindStore.save(.text, bookUrl: book.bookUrl)
                                     }
                                 },
                                 onLoadParagraphs: { await audioChapterParagraphs() },
                                 textFontSize: settings.fontSize,
                                 textLineSpacing: settings.lineSpacingPoints,
                                 onSwitchToTTS: { engine in switchAudioToTTS(engine) },
                                 onPrevious: audioPreviousChapter,
                                 onNext: audioNextChapter,
                                 onBack: {
                                     if forceAudioPlayer { forceAudioPlayer = false } else { dismiss() }
                                 },
                                 onTOC: { showToc = true })
                    .transition(.opacity)
            } else if settings.pageMode == 1 {
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
            if showBars && readerChromeMounted {
                ReaderTopChrome(title: book.name, source: readerSourceName,
                    coverURL: BookCoverLocation.url(for: book),
                    background: theme.bg, foreground: theme.fg,
                    onBack: { dismiss() }, onDetails: { showBookInfo = true })
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) {
            if showBars && readerChromeMounted {
                ReaderBottomChrome(chapter: readerChapterTitle, positionLabel: readerPositionLabel,
                    progress: $menuProgress, canScrub: canScrubReader,
                    canPrevious: !loading && readableIndex(from: index - 1, direction: -1) != nil,
                    canNext: !loading && readableIndex(from: index + 1, direction: 1) != nil,
                    isSpeaking: bookAudio.chapterURL != nil ? bookAudio.isPlaying : aloud.isRunning,
                    background: theme.bg, foreground: theme.fg,
                    onScrub: scrubReader, onPrevious: { go(index - 1) }, onNext: { go(index + 1) },
                    onTOC: { showToc = true },
                    onSpeech: {
                        if bookAudio.chapterURL != nil { bookAudio.toggle() } else { showAloudPanel = true }
                    },
                    onSearch: { showReaderSearch = true }, onSettings: { showSettings = true },
                    onSpeechLongPress: {
                        guard bookAudio.chapterURL != nil else { return }
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        withAnimation(.easeInOut(duration: 0.22)) { forceAudioPlayer = true }
                    })
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
        .fullScreenCover(isPresented: $showAloudPanel) {
            AloudPlayerView(aloud: aloud, book: book, chapters: chapters,
                            onRefreshToc: tocRefreshAction,
                            currentChapter: chapters.indices.contains(index) ? chapters[index] : nil,
                            onUseSourceTone: { source, tone in
                                await useSourceToneAudio(source: source, tone: tone)
                            },
                            onStopSourceAudio: {
                                guard SourceToneAudio.isActive(bookUrl: book.bookUrl) else { return }
                                bookAudio.stop()
                                SourceToneAudio.deactivate(bookUrl: book.bookUrl)
                                BookKindStore.save(.text, bookUrl: book.bookUrl)
                                forceAudioPlayer = false
                            })
                .modifier(AppThemeRoot())
        }
        .overlay(alignment: .bottom) {
            if let notice = aloud.notice, !showAloudPanel {
                Text(notice).appFont(.caption).foregroundStyle(theme.bg)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Capsule().fill(theme.fg.opacity(0.82)))
                    .padding(.bottom, 90)
                    .transition(.opacity)
                    .accessibilityIdentifier("reader.aloud.notice")
            }
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
                    enabled: quickEnabled, loggedIn: quickLoggedIn,
                    customButton: store.source(for: book.origin)?.customButton == true,
                    action: quickAction)
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
                           onSelect: { target in showToc = false; openChapter(target) },
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
                    Section("朗读") {
                        NavigationLink("朗读引擎管理") { SpeakEngineList(aloud: aloud) }
                    }
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
                // 只是提示，不该把下面的正文点击吃掉：换章加载时照样能唤出/收起面板。
                .allowsHitTesting(false)
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
        .sheet(item: $commentTarget) { target in
            if let u = URL(string: target.url) {
                CommentSheet(url: u, content: target.content)
            }
        }
        .onChange(of: scenePhase) { phase in
            if phase != .active { persistContinuousProgress(); store.flushProgress(); closeReadingSession() }
            else if !loading, chapters.indices.contains(index) { noteReadingChapter(index) }
        }
        .onChange(of: readingFonts.selectedPostScriptName) { _ in
            aloud.stop()
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
            aloud.stop()
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
        .onChange(of: index) { _ in
            aloud.highlight.clear()
            toneHighlight.clear()
            lastToneHighlightOffset = -1
            syncMenuProgress()
        }
        .onChange(of: aloud.isRunning) { running in
            if !running { aloud.highlight.clear() }
        }
        .onChange(of: bookAudio.currentTime) { _ in
            followSourceToneAudio()
        }
        .onChange(of: bookAudio.chapterURL) { url in
            if url == nil {
                toneHighlight.clear()
                lastToneHighlightOffset = -1
            }
        }
        .onChange(of: screenSize) { _ in repaginate() }
        .onChange(of: pageInsets) { _ in repaginate() }
        .onDisappear {
            // 退出前存下这一秒，下次进来接着听。
            if bookAudio.chapterURL != nil {
                AudioProgress.save(bookUrl: book.bookUrl, chapter: index,
                                   seconds: bookAudio.currentTime)
            }
            bookAudio.stop()
            manga.stop()
            aloud.detach()
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
        .task { attachAloudHost(); await start() }
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
        if store.source(for: book.origin)?.customButton == true { items.insert("custom") }
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
        case "custom":
            guard let source = store.source(for: book.origin) else { break }
            let chapter = chapters.indices.contains(index) ? chapters[index] : nil
            let result = SourceCallBack.fire(SourceCallBack.clickCustomButton, source: source,
                                             book: book, chapter: chapter)
            quickMessage = (result?.isEmpty == false) ? result : "已执行书源按钮"
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

    // MARK: 漫画

    @ViewBuilder
    private var mangaBody: some View {
        if chapters.isEmpty || loading {
            VStack(spacing: 10) {
                if loading { ProgressView().allowsHitTesting(false) }
                if let error {
                    Text(error).appFont(.footnote).foregroundStyle(theme.fg.opacity(0.75))
                        .multilineTextAlignment(.center).padding(.horizontal, 24)
                } else if loading {
                    Text("轻点屏幕可打开或收起菜单").appFont(.caption).foregroundStyle(theme.fg.opacity(0.55))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // 加载中也能随时唤出/收起面板：整块都可点。
            .contentShape(Rectangle())
            .onTapGesture { toggleBars() }
        } else {
            // 漫画阅读器固定黑色画布：翻页模式下页面四周是留白，黑色观感更好（用户要求）。
            MangaReaderView(manga: manga, book: book, background: .black, foreground: .white,
                            sourceLabel: readerSourceName,
                            onBack: { dismiss() },
                            onTOC: { showToc = true },
                            onDetails: { showBookInfo = true },
                            onClearChapter: { Task { await clearMangaChapterCache() } },
                            onRefreshTOC: {
                                let message = await refreshToc()
                                // 刷新后让漫画会话改用新目录（旧缓存的章节地址可能未展开变量）。
                                if let latest = store.cachedToc(book) {
                                    manga.replaceChapters(latest)
                                }
                                return message
                            })
        }
    }

    /// 目录点击：漫画走会话跳转（重置章节窗口），文字书照旧。
    private func openChapter(_ target: Int) {
        if mangaMode { manga.jump(to: target) } else { go(target) }
    }

    /// 漫画「清除本话缓存并重载」：删掉当前章正文缓存后重新加载图片列表。
    private func clearMangaChapterCache() async {
        guard !store.isLocal(book), let source = store.source(for: book.origin),
              chapters.indices.contains(index) else { return }
        ChapterPrecacheManager.shared.cancelPrecache()
        try? await ChapterContentCache.shared.removeChapter(for: ChapterContentKey(
            sourceURL: source.bookSourceUrl, bookURL: book.bookUrl, chapterURL: chapters[index].url))
        manga.reloadCurrent()
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
            let latest = try await freshChapters(source: source, book: book)
            guard !latest.isEmpty else { return "书源返回空目录，已保留原目录" }
            let oldCount = chapters.count
            let currentURL = chapters.indices.contains(index) ? chapters[index].url : nil
            let currentTitle = chapters.indices.contains(index) ? chapters[index].title : nil
            let currentIsAudio = chapters.indices.contains(index)
                && AudioChapter.isAudio(source: source, chapter: chapters[index])
            chapters = latest
            store.saveToc(book, latest)
            if currentIsAudio {
                // 音频直链每次抓取都会重新签名，URL 必然变化：按标题重新定位当前章。
                if let relocated = AudioChapter.relocatedIndex(in: latest, title: currentTitle, fallback: index) {
                    index = relocated
                }
            } else if let currentURL, let found = latest.firstIndex(where: { $0.url == currentURL }) {
                if found != index { index = found }
            } else if mangaMode,
                      let relocated = MangaBook.relocatedIndex(in: latest, title: currentTitle, fallback: index) {
                // 漫画目录修复后章节地址会变化：按标题重定位当前章。
                index = relocated
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

    private func selectSearchResult(_ offset: Int) {
        guard settings.pageMode == 1, !pages.isEmpty else { return }
        aloud.stop()
        pageIndex = Paginator.pageIndex(containing: offset, in: pages)
        showReaderSearch = false
        showBars = false
    }

    private func start() async {
        // Stable per-reader snapshot: current and prefetched chapters use identical rules.
        bodyReplacement = BodyReplaceEngine(rules: BodyReplaceRepository().rules())
        CrashReporter.note("打开阅读 \(book.name)")
        if store.isLocal(book) { await startLocal(); return }
        guard let s = store.source(for: book.origin) else { error = "找不到书源"; loading = false; return }
        // 先按书源声明/已缓存的结果定模式，没结论的等目录出来再看正文。
        mangaMode = MangaBook.isManga(source: s) || BookKindStore.saved(bookUrl: book.bookUrl) == .image
        index = requestedChapter ?? (store.books.first(where: { $0.bookUrl == book.bookUrl })?.durChapterIndex ?? book.durChapterIndex)
        if let c = store.cachedToc(book), !c.isEmpty {
            chapters = c
            // 旧版本缓存的目录可能留下未展开的 @get/{{ }}（如漫画 comic_id），
            // 这类章节地址请求正文会失败；重抓一次目录（详情页会重新写入 @put 变量）。
            if c.contains(where: { MangaBook.isUnresolvedChapterURL($0.url) }) {
                if let repaired = try? await freshChapters(source: s, book: book), !repaired.isEmpty {
                    chapters = repaired
                    store.saveToc(book, repaired)
                }
            }
        } else {
            do {
                chapters = try await freshChapters(source: s, book: book)
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
        // 书源没声明类型、也没有缓存：先看一眼首章正文，别把漫画当文字排版打开。
        // （详情页已经识别过的书这里命中缓存，不会重复抓。）
        let audioStarted = await resolveReadingMode(source: s, first: first)
        if mangaMode {
            // 漫画：正文是图片列表，不走进度条/分页，直接交给漫画阅读器。
            CrashReporter.note("进入漫画阅读 \(book.name) 共\(chapters.count)章 起始第\(first + 1)章")
            let savedPage = requestedChapter == nil ? store.scrollPosition(book) : 0
            mountManga(source: s, start: first, page: savedPage)
            loading = false
            return
        }
        if audioStarted { return }
        await loadInitialChapter()
    }

    /// 决定这本书用哪种阅读器：书源声明的类型 → 已识别的缓存 → 抓首章正文识别。
    /// 文本正文缓存是共享的，这里抓过的章阅读器不会重复抓。
    /// 返回 true 表示已经由有声书播放器接管，调用方不要再走正文加载。
    private func resolveReadingMode(source: BookSource, first: Int) async -> Bool {
        if mangaMode { return false }  // 启动时已经按书源类型/缓存定了漫画
        if let declared = BookKind.from(sourceType: source.bookSourceType) {
            if declared == .image { BookKindStore.save(.image, bookUrl: book.bookUrl); mangaMode = true }
            return false
        }
        if let cached = BookKindStore.saved(bookUrl: book.bookUrl) {
            mangaMode = cached == .image
            if mangaMode { return false }
            if cached == .audio {
                // 之前识别过是音频：直接按有声书打开，不用再抓一遍正文确认。
                index = first
                await beginAudioChapter(first, source: source)
                loading = false
                return true
            }
            return false
        }
        guard chapters.indices.contains(first) else { return false }
        // 章节链接本身就是音频直链：交给 loadContent 的音频分支，别把音频文件当正文下载。
        if AudioChapter.isDirectAudioURL(chapters[first].url) {
            BookKindStore.save(.audio, bookUrl: book.bookUrl)
            return false
        }
        // 书上/地址里自带的类型标记（聚合源把 tab=漫画 编在书地址里）。
        if let inferred = BookKind.infer(source: source, book: book,
                                         sourceVariables: SourceVariable.get(source.bookSourceUrl)) {
            BookKindStore.save(inferred, bookUrl: book.bookUrl)
            mangaMode = inferred == .image
            if mangaMode { return false }
            if inferred == .audio {
                index = first
                await beginAudioChapter(first, source: source)
                loading = false
                return true
            }
            return false
        }
        // 书源名/章节名能看出来（番茄漫画、七猫听书这类），不联网就能定模式。
        if let guess = BookKind.guess(source: source, chapters: chapters) {
            BookKindStore.save(guess, bookUrl: book.bookUrl)
            mangaMode = guess == .image
            if mangaMode { return false }
            if guess == .audio {
                index = first
                await beginAudioChapter(first, source: source)
                loading = false
                return true
            }
            return false
        }
        // 开篇常常是「片花/序章/公告」这类文字章，光看第一章会把漫画/音频书误判成文本；
        // 取前几章里第一个能识别的非文本结果。
        var kind: BookKind = .text
        var matched = first
        var matchedRaw: String?
        for offset in 0..<3 {
            guard let index = readableIndex(from: first + offset, direction: 1) else { break }
            guard chapters.indices.contains(index) else { break }
            // 直接问书源（不走章节缓存）：早前失败时缓存下来的「无法获取漫画内容」
            // 这类文本不该决定这本书的模式；规则依赖详情页 init 变量时自动补跑一次。
            guard let raw = try? await WebBook.rawContentWithBookInfoHealing(
                source: source, book: book, chapter: chapters[index]) else { continue }
            let scanned = BookKind.detect(inContent: raw)
            if scanned != .text {
                kind = scanned; matched = index; matchedRaw = raw
                break
            }
        }
        BookKindStore.save(kind, bookUrl: book.bookUrl)
        mangaMode = kind == .image
        if mangaMode {
            CrashReporter.note("正文识别为漫画，进入漫画阅读 \(book.name)")
            if matched != first {
                index = matched
                store.updateProgress(book, index: matched, title: chapters[matched].title)
            }
            return false
        }
        guard kind == .audio else { return false }
        CrashReporter.note("正文识别为音频，进入有声书播放 \(book.name)")
        index = matched
        ChapterPrecacheManager.shared.updateCurrentIndex(matched)
        store.updateProgress(book, index: matched, title: chapters[matched].title)
        noteReadingChapter(matched)
        await beginAudioChapter(matched, source: source, content: matchedRaw)
        loading = false
        return true
    }

    /// 重新抓取目录：目录规则用 `@get:{…}` 取详情页 `@put` 变量（漫画 comic_id）时，
    /// 先跑一次详情页把变量写进当前会话，否则章节地址会缺参数（漫画接口报「漫画标识不能为空」）。
    private func freshChapters(source: BookSource, book: Book) async throws -> [BookChapter] {
        var b = book
        if b.tocUrl == nil || WebBook.tocRuleUsesVariables(source) {
            b = try await WebBook.bookInfo(source: source, book: b)
        }
        return try await WebBook.chapters(source: source, book: b)
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
            VStack(spacing: 8) {
                if loading { ProgressView().allowsHitTesting(false) }
                else if let error { Text(error).foregroundStyle(.red).allowsHitTesting(false) }
                else { Text("轻点屏幕可打开或收起菜单").appFont(.caption).foregroundStyle(theme.fg.opacity(0.55)).allowsHitTesting(false) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // 加载中也能随时唤出/收起面板。
            .contentShape(Rectangle())
            .onTapGesture { toggleBars() }
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
                ForEach(Array(content.readingBlocks.enumerated()), id: \.offset) { blockIndex, block in
                    blockView(block, chapter: content.id, blockIndex: blockIndex)
                        .padding(.top, scrollParagraphLeadingGap(in: content.readingBlocks, at: blockIndex))
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
                let decode = imageDecodeHook(for: chapters[target])
                let chapter = await Task.detached(priority: .utility) {
                    let parsed = ReaderChapterParser.content(raw: raw, isVolume: isVolume, replacement: replacement,
                                                            imageDecode: decode)
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
        guard settings.pageMode == 0, !loading, !showToc, !showSettings, commentTarget == nil,
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
        if statsStart == nil {
            statsStart = Date()
            SourceCallBack.fire(SourceCallBack.startRead, source: store.source(for: book.origin),
                                book: book, chapter: chapters.indices.contains(chapter) ? chapters[chapter] : nil)
        }
        statsChapters.insert(chapter)
    }

    private func closeReadingSession() {
        guard let start = statsStart else { return }
        statsStart = nil
        let chapters = statsChapters
        statsChapters = []
        ReadingStatsStore.shared.record(book: book, start: start, end: Date(), chapters: chapters.sorted())
        let source = store.source(for: book.origin)
        let chapter = self.chapters.indices.contains(book.durChapterIndex) ? self.chapters[book.durChapterIndex] : nil
        SourceCallBack.fire(SourceCallBack.saveRead, source: source, book: book,
                            chapter: chapter, result: "\(book.durChapterIndex)")
        SourceCallBack.fire(SourceCallBack.endRead, source: source, book: book, chapter: chapter)
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
        guard !mangaMode else {
            preparedChapters.removeAll()
            return
        }
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
                        content = ReaderChapterParser.content(raw: raw, isVolume: chapters[target].isVolume,
                                                            replacement: bodyReplacement,
                                                            imageDecode: imageDecodeHook(for: chapters[target]))
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

    /// 当前正在读的章节（卷章返回 nil：卷章没有正文块）。
    private var currentChapterItem: BookChapter? {
        guard chapters.indices.contains(index) else { return nil }
        let chapter = chapters[index]
        return chapter.isVolume ? nil : chapter
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
                showsChapterTitle: chapter?.isVolume != true,
                aloudHighlight: activeHighlight, aloudChapter: target).ignoresSafeArea())
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
            VStack { if loading { ProgressView().allowsHitTesting(false) } else if let e = error { Text(e).foregroundStyle(.red).allowsHitTesting(false) } else { Text("") } }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // 加载中也能随时唤出/收起面板（和正文点一下一个行为）。
                .contentShape(Rectangle())
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
        guard !loading, pendingEdge == nil, !showToc, !showSettings, commentTarget == nil, !commentBusy else { return }
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
            guard !commentBusy else { return }
            guard let src = store.source(for: book.origin) else {
                DebugLog.readerAdd("≡段评点击失败：找不到书籍对应的书源（origin=\(book.origin)）")
                return
            }
            commentBusy = true
            let call = String(t.dropFirst(3))
            DebugLog.readerAdd("≡段评点击：\(String(call.prefix(80)))")
            Task {
                let target = await Task.detached { JSEngine.shared.resolveClickURL(source: src, click: call) }.value
                commentBusy = false
                if let u = target.url, URL(string: u) != nil {
                    commentTarget = BrowserTarget(url: u, title: "", content: target.content)
                } else {
                    // 书源脚本自己失败（接口挂了、Token 没了…）时要把原因摆出来，
                    // 否则点了没反应，用户完全不知道发生了什么。
                    let message = target.error ?? "≡段评点击后没有拿到评论页地址"
                    DebugLog.readerAdd(message)
                    bookmarkNotice = message
                    let notice = bookmarkNotice
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 4_000_000_000)
                        if bookmarkNotice == notice { bookmarkNotice = nil }
                    }
                }
            }
        } else if URL(string: t) != nil {
            commentTarget = BrowserTarget(url: t, title: "", content: nil)
        }
    }

    @ViewBuilder
    private func blockView(_ block: ContentBlock, chapter: Int? = nil, blockIndex: Int? = nil) -> some View {
        switch block {
        case .paragraph(let t, let count, let url):
            InlineCommentParagraph(text: t, count: count,
                                    fontSize: settings.fontSize,
                                    lineSpacing: settings.lineSpacingPoints,
                                    color: UIColor(theme.fg),
                                    fullJustify: settings.fullJustify,
                                    onTextTap: { toggleBars() },
                                    selection: textSelectionActions,
                                    highlightColor: ReaderAloudHighlightStyle.color(forBackground: UIColor(theme.bg)),
                                    aloudHighlight: chapter == nil ? nil : activeHighlight,
                                    aloudChapter: chapter,
                                    aloudBlock: blockIndex,
                                    onTap: { commentTapped(url) })
                .frame(maxWidth: .infinity, alignment: .leading)
        case .inlineBubble:
            EmptyView()
        case .image(let src, let click, _):
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
                    .background(Capsule().fill(Color(red: 1, green: 0.27, blue: 0.27)))
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
        if item.chapterIndex == index {
            // 就在当前章：滚动模式直接把位置拖回书签处，分页模式停在当前页。
            if settings.pageMode == 0, !loading {
                scrollProgress.position = item.position
                scrollRequest = ReaderScrollRequest(id: UUID(), chapter: index, permille: item.position)
            }
            return
        }
        loadChapter(item.chapterIndex, landing: settings.pageMode == 1 ? .start : .saved(item.position))
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

    // MARK: 音频书章节（喜马拉雅等音频源）

    /// 开始播放音频章节；播完自动进下一章，锁屏上下曲同样跳章。
    ///
    /// 播放地址与原版一致：书源有正文规则时跑规则取结果（音频源常常把真正的
    /// m4a 地址藏在接口 JSON 里，章节链接只是个页面），没有正文规则才直接用
    /// 章节链接。规则可能返回多段地址，播放器按顺序播完才算整章结束。
    private func beginAudioChapter(_ target: Int, source: BookSource, content: String? = nil) async {
        guard chapters.indices.contains(target) else { return }
        let chapter = chapters[target]
        bookAudio.onFinish = {
            // 这一章听完了：清掉进度，别再「续播」到结尾。
            AudioProgress.clear(bookUrl: book.bookUrl)
            audioNextChapter()
        }
        bookAudio.onRemoteNext = { audioNextChapter() }
        bookAudio.onRemotePrevious = { audioPreviousChapter() }
        bookAudio.onPlaybackFailed = { audioPlaybackFailed() }
        do {
            let urls = try await AudioChapter.playURLs(source: source, book: book, chapter: chapter,
                                                       content: content)
            try Task.checkCancellation()
            guard chapters.indices.contains(target), index == target else { return }
            guard !urls.isEmpty else {
                bookAudio.stop()
                error = "没取到音频地址：书源的正文规则没有返回可播放的链接"
                return
            }
            // 上次听到这里就接着播（原版 durChapterPos）。
            let resume = AudioProgress.resumeSeconds(bookUrl: book.bookUrl, chapter: target)
            bookAudio.onProgress = { seconds in
                AudioProgress.save(bookUrl: book.bookUrl, chapter: target, seconds: seconds)
            }
            bookAudio.play(urls: urls, title: chapter.title, album: book.name, startAt: resume)
        } catch is CancellationError {
            return
        } catch {
            guard chapters.indices.contains(target), index == target else { return }
            bookAudio.stop()
            self.error = "音频加载失败：\(error.localizedDescription)"
        }
    }

    /// 正文模式下的后台音频：这一章还没在播就按当前音色取一次地址并播放。
    private func startBackgroundAudio(_ target: Int, source: BookSource) {
        guard chapters.indices.contains(target) else { return }
        let chapter = chapters[target]
        if bookAudio.chapterURL != nil, bookAudio.chapterTitle == chapter.title { return }
        Task { @MainActor in
            await beginAudioChapter(target, source: source)
        }
    }

    /// 朗读面板里给这本书选了书源音色（番茄 tone_id）：先用该音色试着取一次音频，
    /// 成功就切到书源音频播放这本书（不动书源的全局模式）。
    private func useSourceToneAudio(source: BookSource, tone: SourceTone.Item) async -> Bool {
        guard chapters.indices.contains(index) else { return false }
        SourceToneAudio.activate(bookUrl: book.bookUrl, sourceUrl: source.bookSourceUrl,
                                 tone: tone.value, toneName: tone.name)
        guard let url = await SourceToneAudio.audioURL(source: source, book: book,
                                                       chapter: chapters[index]), !url.isEmpty else {
            SourceToneAudio.deactivate(bookUrl: book.bookUrl)
            return false
        }
        showAloudPanel = false
        aloud.stop()
        if !SourceToneAudio.backgroundPlayback {
            BookKindStore.save(.audio, bookUrl: book.bookUrl)
        }
        await beginAudioChapter(index, source: source)
        return true
    }

    /// 有声书播放器里切到朗读：停掉书源音频，用选中的引擎从当前页开始读。
    private func switchAudioToTTS(_ engine: HTTPTTS?) {
        SourceToneAudio.deactivate(bookUrl: book.bookUrl)
        BookKindStore.save(.text, bookUrl: book.bookUrl)
        bookAudio.stop()
        forceAudioPlayer = false
        aloud.selectEngine(engine)
        showAloudPanel = true
        aloud.openCurrent()
    }

    /// 有声书「正文」页的文字：用原章节地址跑正文规则（音频模式是播放时才改写的），
    /// 再走阅读器同一套解析（图片/段评/`<img data:...>` 都会被过滤成图片块丢掉）。
    private func audioChapterParagraphs() async -> [String] {
        guard chapters.indices.contains(index),
              let source = store.source(for: book.origin) else { return [] }
        guard let raw = try? await WebBook.rawContentWithBookInfoHealing(
            source: source, book: book, chapter: chapters[index]) else { return [] }
        let chapter = chapters[index]
        let content = ReaderChapterParser.content(raw: raw, isVolume: chapter.isVolume,
                                                 replacement: bodyReplacement,
                                                 imageDecode: imageDecodeHook(for: chapter))
        return content.blocks.compactMap { block in
            guard case .paragraph(let text, _, _) = block else { return nil }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    /// 有声书换了音色：书源按新音色重新给本章音频，从本章开头重新播。
    private func reloadAudioChapter() {
        guard bookAudio.chapterURL != nil,
              chapters.indices.contains(index),
              let source = store.source(for: book.origin) else { return }
        let target = index
        AudioProgress.clear(bookUrl: book.bookUrl)
        Task { @MainActor in
            bookAudio.stop()
            error = nil
            await beginAudioChapter(target, source: source)
        }
    }

    /// 喜马拉雅类音频直链带时间签名，书架缓存目录里的旧链接会 403。
    /// 播放失败时自动刷新目录换新链接，再按新链接重试当前章一次。
    private func audioPlaybackFailed() {
        guard bookAudio.chapterURL != nil, !audioFailureRetried else { return }
        audioFailureRetried = true
        Task { @MainActor in
            let refreshMessage = await refreshToc()
            guard bookAudio.chapterURL != nil, chapters.indices.contains(index) else { return }
            // 目录没刷新成功就别拿旧链接再试一遍。
            if let refreshMessage,
               refreshMessage.hasPrefix("找不到书源") || refreshMessage.hasPrefix("刷新失败")
                   || refreshMessage.hasPrefix("书源返回空目录") {
                return
            }
            guard let source = store.source(for: book.origin),
                  AudioChapter.isAudio(source: source, chapter: chapters[index]) else { return }
            ChapterPrecacheManager.shared.updateCurrentIndex(index)
            retryTarget = nil
            error = nil
            store.updateProgress(book, index: index, title: chapters[index].title)
            await beginAudioChapter(index, source: source)
        }
    }

    private func audioNextChapter() {
        guard bookAudio.chapterURL != nil,
              let next = readableIndex(from: index + 1, direction: 1) else {
            bookAudio.stop()
            return
        }
        loadChapter(next, landing: .start)
    }

    private func audioPreviousChapter() {
        guard bookAudio.chapterURL != nil,
              let previous = readableIndex(from: index - 1, direction: -1) else { return }
        loadChapter(previous, landing: .start)
    }

    // MARK: 听书朗读

    /// 注入朗读控制器需要的阅读器能力；闭包捕获 this 只读取当前 @State 值。
    /// onDisappear 会 detach 清理，闭包不会在离开阅读页后继续存活。
    private func attachAloudHost() {
        var host = ReaderAloudHost()
        host.currentChapter = { index }
        host.chapterCount = { chapters.count }
        host.chapterTitle = { i in chapters.indices.contains(i) ? chapters[i].title : "" }
        host.bookLabel = { book.name }
        host.currentOffset = { currentReadOffset() }
        host.units = { i in i == index ? aloudUnits(from: readerBlocks) : nil }
        host.readableChapter = { i, direction in readableIndex(from: i, direction: direction) }
        host.openChapter = { i in await openChapterForAloud(i) }
        host.follow = { chapter, offset in followAloud(chapter: chapter, offset: offset) }
        aloud.attach(host)
    }

    /// 朗读单元 = 已解析正文块里的文字段落；分卷页返回空列表。
    private func aloudUnits(from blocks: [ContentBlock]) -> [AloudUnit] {
        ReaderMenuText.paragraphs(blocks).map { AloudUnit(offset: $0.offset, text: $0.text) }
    }

    /// 朗读偏移统一基于段落文字总长（不含块间换行），富文本书源 text 为空时也能换算。
    private var aloudParagraphLength: Int {
        max(readerBlocks.reduce(0) { partial, block in
            if case .paragraph(let text, _, _) = block { return partial + text.count }
            return partial
        }, 1)
    }

    /// 当前阅读位置的章节内偏移：翻页模式用页首 offset，滚动模式按千分比折算。
    private func currentReadOffset() -> Int {
        if settings.pageMode == 1, pages.indices.contains(pageIndex) {
            return pages[pageIndex].startOffset
        }
        let permille = min(max(scrollProgress.position, 0), 1000)
        return aloudParagraphLength * permille / 1000
    }

    /// 朗读跨章入口：先把阅读器切到目标章，等加载完成再把控制权还给朗读。
    @MainActor
    private func openChapterForAloud(_ target: Int) async -> Bool {
        guard chapters.indices.contains(target) else { return false }
        if target == index, !loading { return true }
        // 刚打开书时还在加载：等当前加载结束，避免 loadChapter 的 !loading 守卫把请求丢空。
        var waited = 0
        while loading && waited < 300 {
            if Task.isCancelled { return false }
            try? await Task.sleep(nanoseconds: 200_000_000); waited += 1
        }
        if target == index && !loading { return true }
        guard !loading, chapters.indices.contains(target) else { return false }
        aloudDrivenNav = true
        loadChapter(target, landing: .start)
        aloudDrivenNav = false
        for _ in 0..<300 {
            if Task.isCancelled { return false }
            if index == target && !loading { return true }
            if !loading, retryTarget == target { return false }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        return index == target && !loading
    }

    /// 后台音频（书源音色）的正文高亮：按「已播比例 × 总字数」估算当前段落，
    /// 只有换段时才更新，避免每 0.5 秒重绘整章。番茄音频没有逐句时间戳，只能估。
    private func followSourceToneAudio() {
        guard sourceToneBackground, chapters.indices.contains(index), !loading else { return }
        guard bookAudio.duration > 0 else { return }
        let units = aloudUnits(from: readerBlocks)
        guard !units.isEmpty else { return }
        let total = units.reduce(0) { $0 + max($1.text.count, 1) }
        guard total > 0 else { return }
        let fraction = min(max(bookAudio.currentTime / bookAudio.duration, 0), 1)
        let target = Int(Double(total) * fraction)
        var acc = 0
        var offset = units[0].offset
        for unit in units {
            acc += max(unit.text.count, 1)
            if target <= acc { offset = unit.offset; break }
            offset = unit.offset
        }
        guard offset != lastToneHighlightOffset else { return }
        lastToneHighlightOffset = offset
        let highlight = settings.pageMode == 1
            ? AloudHighlightLocator.locateInPages(offset: offset, chapter: index,
                                                   pages: pages, blocks: readerBlocks)
            : AloudHighlightLocator.locate(offset: offset, chapter: index, blocks: readerBlocks)
        toneHighlight.update(highlight)
        if settings.pageMode == 1 {
            guard !pages.isEmpty else { return }
            let pageTarget = Paginator.pageIndex(containing: offset, in: pages)
            if pageTarget != pageIndex, pages.indices.contains(pageTarget) { pageIndex = pageTarget }
        }
    }

    /// 朗读进度播报：翻页模式直接跳到含本段的页；滚动模式滚动到本段（节流），
    /// 并保存阅读进度，退出后可以从朗读接着读。
    private func followAloud(chapter: Int, offset: Int) {
        guard aloud.isRunning, chapter == index, !loading else { return }
        let highlight = settings.pageMode == 1
            ? AloudHighlightLocator.locateInPages(offset: offset, chapter: chapter,
                                                   pages: pages, blocks: readerBlocks)
            : AloudHighlightLocator.locate(offset: offset, chapter: chapter, blocks: readerBlocks)
        aloud.highlight.update(highlight)
        if settings.pageMode == 1 {
            guard !pages.isEmpty, pages.indices.contains(0) else { return }
            let target = Paginator.pageIndex(containing: offset, in: pages)
            guard target != pageIndex else { return }
            pageIndex = target
            if pages.indices.contains(target) {
                let total = max((pages.last?.startOffset ?? 0) + 1, 1)
                store.updateScrollPosition(book, permille: (pages[target].startOffset * 1000) / total)
            }
        } else {
            let textCount = aloudParagraphLength
            let permille = min(max((offset * 1000) / textCount, 0), 1000)
            scrollProgress.chapter = chapter
            scrollProgress.position = permille
            store.updateScrollPosition(book, permille: permille)
            // 每段的字符偏移只移动一点，逐段滚动会打断顺滑阅读；
            // 当阅读位置偏出朗读位置一屏左右或段落在当前位置之上时才跳。
            guard !showBars else { return }
            let drifted = abs(permille - aloudScrollPermille) >= 40 || permille < aloudScrollPermille - 5
            guard drifted else { return }
            aloudScrollPermille = permille
            scrollRequest = ReaderScrollRequest(id: UUID(), chapter: chapter, permille: permille)
        }
    }

    /// 正文与书源类型不一致时切换到对应阅读器；切换成功返回 true（本次加载就此结束）。
    @MainActor
    private func adoptDetectedKind(_ raw: String, target: Int) -> Bool {
        let kind = BookKind.detect(inContent: raw)
        guard kind != .text else { return false }
        guard let source = store.source(for: book.origin) else { return false }
        switch kind {
        case .image where !mangaMode:
            // 只有「开篇章节」就是图片列表，才把整本书记成漫画；
            // 文字书里偶尔插图的章节只这一次按图片显示，不改书的模式。
            if target == firstReadableChapterIndex {
                BookKindStore.save(.image, bookUrl: book.bookUrl)
            }
            CrashReporter.note("正文识别为漫画，切换到漫画阅读 \(book.name) 第\(target + 1)章")
            mangaMode = true
            index = target
            store.updateProgress(book, index: target, title: chapters[target].title)
            mountManga(source: source, start: target, page: 0)
            loading = false
            return true
        case .audio:
            let urls = AudioChapter.playURLs(fromContent: raw)
            guard !urls.isEmpty else { return false }
            BookKindStore.save(.audio, bookUrl: book.bookUrl)
            index = target
            store.updateProgress(book, index: target, title: chapters[target].title)
            noteReadingChapter(target)
            // 地址已经解析出来，直接交给播放器（它内部会先停掉上一章）。
            bookAudio.onFinish = {
                AudioProgress.clear(bookUrl: book.bookUrl)
                audioNextChapter()
            }
            bookAudio.onRemoteNext = { audioNextChapter() }
            bookAudio.onRemotePrevious = { audioPreviousChapter() }
            bookAudio.onPlaybackFailed = { audioPlaybackFailed() }
            let resume = AudioProgress.resumeSeconds(bookUrl: book.bookUrl, chapter: target)
            bookAudio.onProgress = { seconds in
                AudioProgress.save(bookUrl: book.bookUrl, chapter: target, seconds: seconds)
            }
            bookAudio.play(urls: urls, title: chapters[target].title,
                           album: book.name, startAt: resume)
            loading = false
            return true
        default:
            return false
        }
    }

    /// 目录里第一个可读章节（用来判断「开篇是不是图片」，避免整本书被一章插图带偏）。
    private var firstReadableChapterIndex: Int {
        ChapterNavigation.contentIndex(from: 0, direction: 1, chapters: chapters) ?? 0
    }

    /// 把漫画阅读器挂到指定章节（书源类型是图片源、或正文识别为漫画时共用）。
    private func mountManga(source: BookSource, start: Int, page: Int) {
        manga.configure(book: book, source: source, chapters: chapters, start: start, page: page,
                        onProgress: { chapter, title, page in
                            if index != chapter { index = chapter }
                            ChapterPrecacheManager.shared.updateCurrentIndex(chapter)
                            store.updateMangaProgress(book, chapterIndex: chapter, title: title, page: page)
                        },
                        onChapterRead: { chapter in noteReadingChapter(chapter) })
    }

    private func loadChapter(_ target: Int, landing: ChapterLanding) {
        guard !loading, chapters.indices.contains(target) else { return }
        // 新的导航重新给一次「链接过期自动重试」的预算。
        audioFailureRetried = false
        // 朗读控制器自己请求 openChapter 时 aloudDrivenNav 为真，朗读继续；
        // 其他途径（手动翻章/书签/边缘到达）都会在这里停止朗读。
        if !aloudDrivenNav { aloud.stop() }
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
        let backgroundAudio = sourceToneBackground
        if !store.isLocal(book), let source = store.source(for: book.origin),
           !backgroundAudio,
           BookKindStore.saved(bookUrl: book.bookUrl) == .audio
               || SourceToneAudio.isActive(bookUrl: book.bookUrl)
               || AudioChapter.isAudio(source: source, chapter: chapter) {
            // 音频章节：链接就是音频直链，不走正文抓取与排版，直接播放。
            index = target
            ChapterPrecacheManager.shared.updateCurrentIndex(target)
            retryTarget = nil
            error = nil
            await beginAudioChapter(target, source: source)
            store.updateProgress(book, index: target, title: chapter.title)
            noteReadingChapter(target)
            store.updateScrollPosition(book, permille: 0)
            return
        }
        if !backgroundAudio { bookAudio.stop() }
        do {
            let raw = try await rawContent(at: target, priority: .userInitiated)
            try Task.checkCancellation()
            guard contentRequestID == requestID else { return }
            // 书源类型没写对（最常见：漫画源/音频源被标成文本）：按正文实际内容切换阅读模式。
            if adoptDetectedKind(raw, target: target) { return }
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
            if backgroundAudio, let source = store.source(for: book.origin) {
                startBackgroundAudio(target, source: source)
            }
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

    /// imageDecode 钩子：原版对正文里的每张图片/气泡单独求值一次 imageDecode 规则。
    /// 番茄系段评靠它清掉「已渲染」标记；少了这一步，点击气泡永远打不开。
    private func imageDecodeHook(for chapter: BookChapter?) -> ((String) -> String)? {
        guard let chapter, let source = store.source(for: book.origin) else { return nil }
        return WebBook.contentImageHook(source: source, book: book, chapter: chapter)
    }

    /// 前台与预排版使用同一解析流程，保留原始段评标记和续段字符偏移。
    private func show(raw: String, landing: ChapterLanding) {
        let content = ReaderChapterParser.content(raw: raw, isVolume: currentVolume != nil, replacement: bodyReplacement,
                                                 imageDecode: imageDecodeHook(for: currentChapterItem))
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
