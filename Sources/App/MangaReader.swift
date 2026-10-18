import SwiftUI
import UIKit

// MARK: - 会话（章节图片窗口，对应原版 ReadManga）

/// 漫画阅读会话：维护「上一章 / 当前章 / 下一章」的图片列表，
/// 对应原版 ReadManga 的 prev/cur/next 三章窗口与 loadContent(arrayListOf)。
/// 阅读器 UI 只读它的 @Published 快照，滚动容器负责把可见页回报回来。
@MainActor
final class MangaSession: ObservableObject {
    @Published private(set) var items: [MangaFlatItem] = []
    @Published private(set) var currentChapter = 0
    @Published private(set) var currentPage = 0
    @Published private(set) var currentPageCount = 0
    @Published private(set) var chapterTitle = ""
    @Published private(set) var chapterCount = 0
    @Published private(set) var loadingChapter = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var scrollRequest: MangaScrollRequest?

    private(set) var configured = false
    private var book: Book?
    private var source: BookSource?
    private var chapters: [BookChapter] = []
    private var pages: [Int: [String]] = [:]
    private var loaded: Set<Int> = []
    private var loading: Set<Int> = []
    private var failed: Set<Int> = []
    private var attempts: [Int: Int] = [:]
    private var tasks: [Int: Task<Void, Never>] = [:]
    /// 每章当前加载轮次；取消重载后旧轮次的收尾不会覆盖新状态。
    private var loadTokens: [Int: UUID] = [:]
    private var onProgress: ((Int, String, Int) -> Void)?
    private var onChapterRead: ((Int) -> Void)?
    private var started = false
    /// 程序化跳转后的短暂期望章：忽略旧章的滚动回报，避免进度来回跳。
    private var expectation: (chapter: Int, expires: Date)?

    func configure(book: Book, source: BookSource, chapters: [BookChapter],
                   start: Int, page: Int,
                   onProgress: @escaping (_ chapter: Int, _ title: String, _ page: Int) -> Void,
                   onChapterRead: @escaping (_ chapter: Int) -> Void) {
        guard !configured else { return }
        configured = true
        self.book = book
        self.source = source
        self.chapters = chapters
        self.chapterCount = chapters.count
        self.onProgress = onProgress
        self.onChapterRead = onChapterRead
        currentChapter = min(max(start, 0), max(chapters.count - 1, 0))
        currentPage = max(page, 0)
        chapterTitle = chapters.indices.contains(currentChapter) ? chapters[currentChapter].title : ""
    }

    /// 打开漫画：先加载当前章，然后按原版取「当前章 ± 1」。
    func start() async {
        guard configured, !started, chapters.indices.contains(currentChapter) else { return }
        started = true
        expectation = (currentChapter, Date().addingTimeInterval(3))
        if let task = beginLoad(currentChapter, isCurrent: true) { await task.value }
        if loaded.contains(currentChapter) {
            let count = pages[currentChapter]?.count ?? 0
            currentPageCount = count
            let clamped = min(max(currentPage, 0), max(count - 1, 0))
            currentPage = clamped
            requestScroll(toItemID: "c\(currentChapter)-p\(clamped)", animated: false)
            onProgress?(currentChapter, chapterTitle, clamped)
            onChapterRead?(currentChapter)
        }
        ensureNeighbors()
    }

    func stop() {
        for task in tasks.values { task.cancel() }
        tasks.removeAll()
    }

    // MARK: 可见页回报（滚动容器 → 会话）

    func visible(chapter: Int, page: Int, count: Int) {
        guard chapters.indices.contains(chapter) else { return }
        if let expectation {
            if expectation.expires < Date() {
                self.expectation = nil
            } else if chapter != expectation.chapter {
                return
            } else {
                self.expectation = nil
            }
        }
        let total = pages[chapter]?.count ?? count
        var changed = false
        if chapter != currentChapter {
            currentChapter = chapter
            currentPage = page
            currentPageCount = total
            chapterTitle = chapters[chapter].title
            rebuild()
            ensureNeighbors()
            onChapterRead?(chapter)
            changed = true
        } else if page != currentPage {
            currentPage = page
            currentPageCount = total
            changed = true
        } else if total != currentPageCount {
            currentPageCount = total
            changed = true
        }
        guard changed else { return }
        onProgress?(chapter, chapterTitle, page)
    }

    /// 接近列表底部 / 顶部时提前加载相邻章（对应原版 loadOrUpContent）。
    func nearEnd() {
        let next = currentChapter + 1
        guard chapters.indices.contains(next), !loaded.contains(next), !loading.contains(next) else { return }
        if failed.contains(next), (attempts[next] ?? 0) >= 1 { return }
        beginLoad(next, isCurrent: false)
    }

    func nearStart() {
        let prev = currentChapter - 1
        guard chapters.indices.contains(prev), !loaded.contains(prev), !loading.contains(prev) else { return }
        if failed.contains(prev), (attempts[prev] ?? 0) >= 1 { return }
        beginLoad(prev, isCurrent: false)
    }

    // MARK: 跳转

    /// 目录跳转：清空已加载窗口，重新从目标章加载（原版 moveTo 系列也会重置三章窗口）。
    func jump(to chapter: Int, page: Int = 0) {
        guard configured, chapters.indices.contains(chapter) else { return }
        resetWindow(to: chapter, title: chapters[chapter].title, page: page)
        loadWindow(positioningPage: page)
    }

    /// 目录刷新后替换章节列表：按标题重定位当前章（修复后的章节地址会变化），
    /// 清空窗口重新加载并保留本章页位置。
    func replaceChapters(_ newChapters: [BookChapter]) {
        guard configured, !newChapters.isEmpty else { return }
        let title = chapterTitle
        let oldIndex = currentChapter
        let page = currentPage
        let relocated = MangaBook.relocatedIndex(in: newChapters, title: title, fallback: oldIndex)
            ?? min(oldIndex, newChapters.count - 1)
        chapters = newChapters
        chapterCount = newChapters.count
        resetWindow(to: relocated, title: newChapters[relocated].title, page: page)
        loadWindow(positioningPage: page)
    }

    private func resetWindow(to chapter: Int, title: String, page: Int) {
        stop()
        pages.removeAll()
        loaded.removeAll()
        loading.removeAll()
        failed.removeAll()
        attempts.removeAll()
        currentChapter = chapter
        currentPage = max(page, 0)
        currentPageCount = 0
        chapterTitle = title
        errorMessage = nil
        expectation = (chapter, Date().addingTimeInterval(3))
        rebuild()
    }

    /// 加载当前章，成功后定位到指定页并补齐相邻章。
    private func loadWindow(positioningPage page: Int) {
        let chapter = currentChapter
        Task { [weak self] in
            guard let self else { return }
            if let task = beginLoad(chapter, isCurrent: true) { await task.value }
            if loaded.contains(chapter) {
                let count = pages[chapter]?.count ?? 0
                currentPageCount = count
                let clamped = min(max(page, 0), max(count - 1, 0))
                currentPage = clamped
                requestScroll(toItemID: "c\(chapter)-p\(clamped)", animated: false)
                onProgress?(chapter, chapterTitle, clamped)
                onChapterRead?(chapter)
            }
            ensureNeighbors()
        }
    }

    /// 上一章 / 下一章按钮。已加载的相邻章直接滚动过去（原版 moveToNextChapter 的队列命中路径）。
    func goToAdjacentChapter(_ delta: Int) {
        let target = currentChapter + delta
        guard chapters.indices.contains(target) else { return }
        if loaded.contains(target) {
            let count = pages[target]?.count ?? 0
            currentChapter = target
            currentPage = 0
            currentPageCount = count
            chapterTitle = chapters[target].title
            expectation = (target, Date().addingTimeInterval(3))
            rebuild()
            requestScroll(toItemID: "c\(target)-p0", animated: false)
            onProgress?(target, chapterTitle, 0)
            onChapterRead?(target)
            ensureNeighbors()
        } else {
            jump(to: target)
        }
    }

    /// 章内指定页（进度条拖动）。silent 时不写进度（拖动中的中间帧）。
    func requestScroll(toPage page: Int, reportProgress: Bool = true) {
        guard loaded.contains(currentChapter) else { return }
        let count = pages[currentChapter]?.count ?? 0
        guard count > 0 else { return }
        let clamped = min(max(page, 0), count - 1)
        currentPage = clamped
        currentPageCount = count
        requestScroll(toItemID: "c\(currentChapter)-p\(clamped)", animated: false)
        if reportProgress { onProgress?(currentChapter, chapterTitle, clamped) }
    }

    /// 重试当前章（错误覆盖层 / 清除缓存后重载）。
    func reloadCurrent() {
        let chapter = currentChapter
        guard chapters.indices.contains(chapter) else { return }
        pages[chapter] = nil
        loaded.remove(chapter)
        loading.remove(chapter)
        failed.remove(chapter)
        attempts[chapter] = 0
        errorMessage = nil
        rebuild()
        Task { [weak self] in
            guard let self else { return }
            if let task = beginLoad(chapter, isCurrent: true) { await task.value }
            if loaded.contains(chapter) {
                let count = pages[chapter]?.count ?? 0
                currentPageCount = count
                let clamped = min(max(currentPage, 0), max(count - 1, 0))
                currentPage = clamped
                requestScroll(toItemID: "c\(chapter)-p\(clamped)", animated: false)
            }
            ensureNeighbors()
        }
    }

    /// 哨兵点按重试相邻章。
    func retryNeighbor(_ chapter: Int) {
        attempts[chapter] = 0
        failed.remove(chapter)
        rebuild()
        beginLoad(chapter, isCurrent: false)
    }

    // MARK: 加载

    @discardableResult
    private func beginLoad(_ index: Int, isCurrent: Bool) -> Task<Void, Never>? {
        guard let book, let source, chapters.indices.contains(index),
              !loaded.contains(index), !loading.contains(index), tasks[index] == nil else { return nil }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.loadChapter(index, isCurrent: isCurrent, book: book, source: source)
        }
        tasks[index] = task
        return task
    }

    private func loadChapter(_ index: Int, isCurrent: Bool, book: Book, source: BookSource) async {
        let token = UUID()
        loadTokens[index] = token
        loading.insert(index)
        if index == currentChapter { loadingChapter = true; errorMessage = nil }
        defer {
            // 只有同一轮加载才清理状态；jump 取消后的迟到清理不能覆盖新一轮。
            if loadTokens[index] == token {
                loadTokens[index] = nil
                loading.remove(index)
                tasks[index] = nil
                if index == currentChapter { loadingChapter = false }
                rebuild()
            }
        }
        // 旧目录缓存的章节地址可能残留未展开的变量（@get/{{ }}）：直接给出可操作的提示。
        if MangaBook.isUnresolvedChapterURL(chapters[index].url) {
            failed.insert(index)
            attempts[index, default: 0] += 1
            if index == currentChapter { errorMessage = "目录已过期（章节地址未展开），请点「刷新目录」" }
            return
        }
        do {
            let nextURL = chapters.indices.contains(index + 1) ? chapters[index + 1].url : nil
            let raw = try await ChapterContentLoader.content(source: source, book: book,
                                                             chapter: chapters[index],
                                                             nextChapterURL: nextURL)
            try Task.checkCancellation()
            let urls = MangaBook.imageURLs(in: raw, baseURL: chapters[index].url)
            if urls.isEmpty {
                failed.insert(index)
                attempts[index, default: 0] += 1
                if index == currentChapter { errorMessage = "本章没有图片" }
            } else {
                pages[index] = urls
                loaded.insert(index)
                failed.remove(index)
                if index == currentChapter { errorMessage = nil }
            }
        } catch is CancellationError {
            // 主动停止/换章导致的中断不算失败。
        } catch {
            failed.insert(index)
            attempts[index, default: 0] += 1
            if index == currentChapter { errorMessage = error.localizedDescription }
        }
    }

    private func ensureNeighbors() {
        let next = currentChapter + 1
        let prev = currentChapter - 1
        if chapters.indices.contains(next), !failed.contains(next) || (attempts[next] ?? 0) < 1 {
            beginLoad(next, isCurrent: false)
        }
        if chapters.indices.contains(prev), !failed.contains(prev) || (attempts[prev] ?? 0) < 1 {
            beginLoad(prev, isCurrent: false)
        }
    }

    // MARK: 列表构建

    private func rebuild() {
        guard loaded.contains(currentChapter) else {
            // 当前章还没加载出来时列表为空，由覆盖层显示加载/失败状态。
            if !items.isEmpty { items = [] }
            return
        }
        var out: [MangaFlatItem] = []
        let previous = currentChapter - 1
        if previous >= 0, !loaded.contains(previous), failed.contains(previous) {
            out.append(MangaFlatItem(id: "sentinel-prev", chapter: previous, kind: .retryPrev))
        }
        for chapter in loaded.sorted() {
            guard let urls = pages[chapter], !urls.isEmpty else { continue }
            let title = chapters[chapter].title
            out.append(MangaFlatItem(id: "c\(chapter)-start", chapter: chapter,
                                     kind: .chapterStart(title: title)))
            for (page, url) in urls.enumerated() {
                out.append(MangaFlatItem(id: "c\(chapter)-p\(page)", chapter: chapter,
                                         kind: .page(chapter: chapter, index: page,
                                                     count: urls.count, url: url)))
            }
            out.append(MangaFlatItem(id: "c\(chapter)-end", chapter: chapter,
                                     kind: .chapterEnd(title: title)))
        }
        let next = currentChapter + 1
        if chapters.indices.contains(next) {
            if !loaded.contains(next) {
                let needsManualRetry = failed.contains(next) && (attempts[next] ?? 0) >= 1
                out.append(MangaFlatItem(id: "sentinel-next", chapter: next,
                                         kind: needsManualRetry ? .retryNext : .loadingNext))
            }
        } else {
            out.append(MangaFlatItem(id: "no-more", chapter: currentChapter, kind: .noMore))
        }
        if items != out { items = out }
    }

    private func requestScroll(toItemID id: String, animated: Bool) {
        scrollRequest = MangaScrollRequest(id: UUID(), itemID: id, animated: animated)
    }
}

// MARK: - 阅读界面

/// 漫画阅读器（对应原版 ReadMangaActivity）：
/// 竖向连续滚动图片流，中央点按呼出菜单，左下 / 右下点按翻一屏，底栏上一章 / 进度 / 下一章。
struct MangaReaderView: View {
    @ObservedObject var manga: MangaSession
    let book: Book
    let background: Color
    let foreground: Color
    let sourceLabel: String
    let onBack: () -> Void
    let onTOC: () -> Void
    let onDetails: () -> Void
    let onSettings: () -> Void
    let onClearChapter: () -> Void
    let onRefreshTOC: (@MainActor () async -> String?)?

    @ThemePalette private var palette
    @State private var barsVisible = true
    @State private var scrub: Double?
    @State private var notice: String?
    @State private var noticeToken = UUID()
    /// 自动修复旧目录只做一次，避免「本章没有图片」时反复刷新。
    @State private var autoRefreshedTOC = false

    var body: some View {
        ZStack {
            background.ignoresSafeArea()
            MangaScrollView(items: manga.items,
                            request: manga.scrollRequest,
                            background: UIColor(background),
                            foreground: UIColor(foreground),
                            onVisible: { chapter, page, count in
                                manga.visible(chapter: chapter, page: page, count: count)
                            },
                            onNearEnd: { manga.nearEnd() },
                            onNearStart: { manga.nearStart() },
                            onRetryNeighbor: { chapter in manga.retryNeighbor(chapter) },
                            onCenterTap: { toggleBars() })
                .ignoresSafeArea()
            if manga.items.isEmpty { statusOverlay }
            if barsVisible {
                VStack(spacing: 0) {
                    topBar
                    Spacer(minLength: 0)
                    bottomBar
                }
                .transition(.opacity)
            }
            if let notice {
                VStack {
                    Spacer()
                    Text(notice)
                        .appFont(.caption)
                        .foregroundStyle(background)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Capsule().fill(foreground.opacity(0.82)))
                        .padding(.bottom, 140)
                        .accessibilityIdentifier("reader.manga.notice")
                }
            }
        }
        .foregroundStyle(foreground)
        .task { await manga.start() }
        .onChange(of: manga.errorMessage) { message in
            // 第一次出现「本章没有图片」时，多半是旧目录缓存导致章节地址失效：
            // 自动刷新一次目录（会先跑详情页补齐变量）再重载当前章。
            guard message == "本章没有图片", !autoRefreshedTOC else { return }
            autoRefreshedTOC = true
            Task { await refreshTOC() }
        }
    }

    private func toggleBars() {
        withAnimation(.easeInOut(duration: 0.15)) { barsVisible.toggle() }
    }

    // MARK: 顶部浮动面板（参考图：左圆钮 + 居中章节名 + 右侧更多，无底色）

    private var topBar: some View {
        ZStack {
            Text(manga.chapterTitle.isEmpty ? book.name : manga.chapterTitle)
                .appFont(.system(size: 15, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(foreground)
                .shadow(color: .black.opacity(0.35), radius: 4, y: 1)
                .padding(.horizontal, 104)
                .allowsHitTesting(false)
                .accessibilityIdentifier("reader.manga.title")

            HStack(spacing: 10) {
                circleButton("xmark", label: "关闭", id: "reader.manga.back", action: onBack)
                circleButton("list.bullet", label: "目录", id: "reader.manga.toc", action: onTOC)
                Spacer(minLength: 0)
                moreMenu
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    private func circleButton(_ system: String, label: String, id: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 42, height: 42)
                .appGlass(in: Circle(), tint: background)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(foreground)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    private var moreMenu: some View {
        Menu {
            Button { manga.goToAdjacentChapter(-1) } label: { Label("上一章", systemImage: "chevron.up") }
                .disabled(manga.currentChapter <= 0)
            Button { manga.goToAdjacentChapter(1) } label: { Label("下一章", systemImage: "chevron.down") }
                .disabled(manga.currentChapter >= manga.chapterCount - 1)
            Divider()
            Button { Task { await refreshTOC() } } label: { Label("刷新目录", systemImage: "arrow.clockwise") }
            Button(role: .destructive) { onClearChapter() } label: { Label("清除本话缓存并重载", systemImage: "trash") }
            Divider()
            Button { onDetails() } label: { Label("书籍操作", systemImage: "book") }
            Button { onSettings() } label: { Label("阅读设置", systemImage: "textformat.size") }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 42, height: 42)
                .appGlass(in: Circle(), tint: background)
                .contentShape(Circle())
        }
        .foregroundStyle(foreground)
        .accessibilityLabel("更多")
        .accessibilityIdentifier("reader.manga.menu")
    }

    // MARK: 底部胶囊（页进度，参考图：滑块 + 页码 + 剩余页数）

    private var pageCount: Int { max(manga.currentPageCount, 0) }

    private var pageProgress: Double {
        if let scrub { return scrub }
        let count = max(manga.currentPageCount, 1)
        guard count > 1 else { return 0 }
        return min(max(Double(manga.currentPage) / Double(count - 1), 0), 1)
    }

    private var pageLabel: String { "\(manga.currentPage + 1) / \(max(pageCount, 1))" }

    private var remainingText: String {
        "剩余 \(max(pageCount - manga.currentPage - 1, 0)) 页"
    }

    private var bottomBar: some View {
        Slider(value: Binding(get: { pageProgress }, set: { value in
            scrub = value
            let count = pageCount
            guard count > 0 else { return }
            let page = Int((value * Double(max(count - 1, 0))).rounded())
            manga.requestScroll(toPage: page, reportProgress: false)
        }), in: 0...1) { editing in
            if !editing {
                if let value = scrub {
                    scrub = nil
                    let count = pageCount
                    if count > 0 {
                        let page = Int((value * Double(max(count - 1, 0))).rounded())
                        manga.requestScroll(toPage: page)
                    }
                }
            }
        }
        .tint(palette.accent)
        .accessibilityIdentifier("reader.manga.slider")
        .overlay {
            Text(pageLabel)
                .appFont(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(foreground.opacity(0.85))
                .allowsHitTesting(false)
                .accessibilityIdentifier("reader.manga.footer")
        }
        .overlay(alignment: .trailing) {
            Text(remainingText)
                .appFont(.system(size: 12))
                .monospacedDigit()
                .foregroundStyle(foreground.opacity(0.6))
                .padding(.trailing, 14)
                .allowsHitTesting(false)
        }
        .padding(.horizontal, 18)
        .frame(height: 44)
        .appGlass(in: Capsule(), tint: background)
        .padding(.horizontal, 20)
        .padding(.bottom, 6)
    }

    // MARK: 覆盖层与动作

    @ViewBuilder
    private var statusOverlay: some View {
        VStack(spacing: 14) {
            if manga.loadingChapter {
                ProgressView()
                Text("正在加载图片列表…").appFont(.footnote).foregroundStyle(foreground.opacity(0.7))
            } else if let message = manga.errorMessage {
                Text(message).appFont(.footnote).foregroundStyle(foreground.opacity(0.8))
                    .multilineTextAlignment(.center).padding(.horizontal, 24)
                HStack(spacing: 12) {
                    Button("重试") { manga.reloadCurrent() }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("reader.manga.retry")
                    Button("刷新目录") { Task { await refreshTOC() } }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("reader.manga.refreshTOC")
                }
            } else {
                Text("正在准备…").appFont(.footnote).foregroundStyle(foreground.opacity(0.7))
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(background.opacity(0.9))
        .allowsHitTesting(true)
    }

    private func refreshTOC() async {
        guard let onRefreshTOC else { return }
        let message = await onRefreshTOC()
        showNotice(message ?? "目录已刷新")
    }

    private func showNotice(_ text: String) {
        notice = text
        let token = UUID()
        noticeToken = token
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if noticeToken == token { notice = nil }
        }
    }
}
