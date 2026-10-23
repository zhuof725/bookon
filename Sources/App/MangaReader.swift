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
        // 图片同样是「书源的请求」：原版下载图片时带书源 header、并按 imageDecode 解密。
        MangaImageLoader.shared.configure(source: source)
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
            requestScroll(toItemID: "c\(currentChapter)-p\(clamped)", chapter: currentChapter,
                          page: clamped, animated: false)
            onProgress?(currentChapter, chapterTitle, clamped)
            onChapterRead?(currentChapter)
        }
        ensureNeighbors()
    }

    func stop() {
        for task in tasks.values { task.cancel() }
        tasks.removeAll()
        MangaImageLoader.shared.configure(source: nil)
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
        CrashReporter.note("漫画目录跳转 第\(chapter + 1)章 \(chapters[chapter].title)")
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
        CrashReporter.note("漫画目录更新 共\(newChapters.count)章 定位第\(relocated + 1)章")
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
                // 负数表示落在本章最后一页（从章首往回翻时用）。
                let clamped = page < 0 ? max(count - 1, 0) : min(max(page, 0), max(count - 1, 0))
                currentPage = clamped
                requestScroll(toItemID: "c\(chapter)-p\(clamped)", chapter: chapter,
                              page: clamped, animated: false)
                onProgress?(chapter, chapterTitle, clamped)
                onChapterRead?(chapter)
            }
            ensureNeighbors()
        }
    }

    /// 上一章 / 下一章。已加载的相邻章直接跳过去（原版 moveToNextChapter 的队列命中路径）。
    /// atLastPage：翻页模式从章首/章末越界进入时，向前一章要落在最后一页。
    func goToAdjacentChapter(_ delta: Int, atLastPage: Bool = false) {
        let target = currentChapter + delta
        guard chapters.indices.contains(target) else { return }
        if loaded.contains(target) {
            let count = pages[target]?.count ?? 0
            let landing = atLastPage ? max(count - 1, 0) : 0
            currentChapter = target
            currentPage = landing
            currentPageCount = count
            chapterTitle = chapters[target].title
            expectation = (target, Date().addingTimeInterval(3))
            rebuild()
            requestScroll(toItemID: "c\(target)-p\(landing)", chapter: target,
                          page: landing, animated: false)
            onProgress?(target, chapterTitle, landing)
            onChapterRead?(target)
            ensureNeighbors()
        } else {
            jump(to: target, page: atLastPage ? -1 : 0)
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
        requestScroll(toItemID: "c\(currentChapter)-p\(clamped)", chapter: currentChapter,
                      page: clamped, animated: false)
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
                requestScroll(toItemID: "c\(chapter)-p\(clamped)", chapter: chapter,
                              page: clamped, animated: false)
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
            CrashReporter.note("漫画章节地址未展开 第\(index + 1)章 \(chapters[index].url)")
            return
        }
        CrashReporter.note("漫画加载 第\(index + 1)章 \(chapters[index].title) \(chapters[index].url)")
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
                CrashReporter.note("漫画本章没有图片 第\(index + 1)章 正文 \(raw.count) 字")
            } else {
                pages[index] = urls
                loaded.insert(index)
                failed.remove(index)
                if index == currentChapter { errorMessage = nil }
                CrashReporter.note("漫画加载完成 第\(index + 1)章 图片 \(urls.count) 张")
            }
        } catch is CancellationError {
            // 主动停止/换章导致的中断不算失败。
        } catch {
            failed.insert(index)
            attempts[index, default: 0] += 1
            if index == currentChapter { errorMessage = error.localizedDescription }
            CrashReporter.note("漫画加载失败 第\(index + 1)章: \(error.localizedDescription)")
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
            // 不再插入「阅读 X / 已读完 X」分章标记：条漫要像参考图那样章节之间无缝相接，
            // 分章标记会撑出两屏白带。章节名仍由顶部面板 / 切章提示展示。
            for (page, url) in urls.enumerated() {
                out.append(MangaFlatItem(id: "c\(chapter)-p\(page)", chapter: chapter,
                                         kind: .page(chapter: chapter, index: page,
                                                     count: urls.count, url: url)))
            }
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

    private func requestScroll(toItemID id: String, chapter: Int, page: Int, animated: Bool) {
        scrollRequest = MangaScrollRequest(id: UUID(), itemID: id, animated: animated,
                                           chapter: chapter, page: page)
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
    let onClearChapter: () -> Void
    let onRefreshTOC: (@MainActor () async -> String?)?

    @ThemePalette private var palette
    @AppStorage(MangaReadingMode.storageKey) private var modeRaw = MangaReadingMode.fallback.rawValue
    @State private var barsVisible = true
    @State private var scrub: Double?
    @State private var notice: String?
    @State private var noticeToken = UUID()
    /// 自动修复旧目录只做一次，避免「本章没有图片」时反复刷新。
    @State private var autoRefreshedTOC = false
    /// 换章时短暂浮出的章节名。不改布局，条漫在章节之间保持无缝相接。
    @State private var chapterBanner: String?
    @State private var bannerToken = UUID()
    @State private var lastBannerChapter: Int?

    private var mode: MangaReadingMode { MangaReadingMode(rawValue: modeRaw) ?? .fallback }

    var body: some View {
        ZStack {
            background.ignoresSafeArea()
            readerSurface
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
            if let chapterBanner {
                VStack {
                    Text(chapterBanner)
                        .appFont(.system(size: 13, weight: .medium))
                        .foregroundStyle(foreground)
                        .lineLimit(1)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .appGlass(in: Capsule(), tint: background, tintOpacity: 0.30)
                        .overlay { Capsule().strokeBorder(foreground.opacity(0.25), lineWidth: 0.5) }
                        .padding(.top, 64)
                    Spacer(minLength: 0)
                }
                .allowsHitTesting(false)
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
        .onChange(of: manga.currentChapter) { chapter in
            guard let previous = lastBannerChapter else {
                lastBannerChapter = chapter
                return
            }
            lastBannerChapter = chapter
            guard chapter != previous else { return }
            showChapterBanner()
        }
        .onChange(of: modeRaw) { _ in
            // 切换阅读方式时把当前位置带到新容器（分页容器按页码，条漫按 itemID）。
            manga.requestScroll(toPage: manga.currentPage, reportProgress: false)
        }
    }

    @ViewBuilder
    private var readerSurface: some View {
        if mode.isPaged {
            MangaPagedView(pages: pagedPages,
                           chapter: manga.currentChapter,
                           mode: mode,
                           request: manga.scrollRequest,
                           background: UIColor(background),
                           foreground: UIColor(foreground),
                           chromeVisible: barsVisible,
                           onVisible: { chapter, page, count in
                               manga.visible(chapter: chapter, page: page, count: count)
                           },
                           onNextChapter: { manga.goToAdjacentChapter(1) },
                           onPrevChapter: { manga.goToAdjacentChapter(-1, atLastPage: true) },
                           onToggleChrome: { toggleBars() })
        } else {
            MangaScrollView(items: manga.items,
                            request: manga.scrollRequest,
                            background: UIColor(background),
                            foreground: UIColor(foreground),
                            chromeVisible: barsVisible,
                            onVisible: { chapter, page, count in
                                manga.visible(chapter: chapter, page: page, count: count)
                            },
                            onNearEnd: { manga.nearEnd() },
                            onNearStart: { manga.nearStart() },
                            onRetryNeighbor: { chapter in manga.retryNeighbor(chapter) },
                            onToggleChrome: { toggleBars() })
        }
    }

    /// 分页模式只取当前章的图片，按阅读顺序排列。
    private var pagedPages: [String] {
        manga.items.compactMap { item -> String? in
            guard item.chapter == manga.currentChapter,
                  case .page(_, _, _, let url) = item.kind else { return nil }
            return url
        }
    }

    private func toggleBars() {
        withAnimation(.easeInOut(duration: 0.15)) { barsVisible.toggle() }
    }

    private func showChapterBanner() {
        guard !manga.chapterTitle.isEmpty else { return }
        withAnimation(.easeOut(duration: 0.15)) { chapterBanner = manga.chapterTitle }
        let token = UUID()
        bannerToken = token
        Task {
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            guard bannerToken == token else { return }
            withAnimation(.easeIn(duration: 0.25)) { chapterBanner = nil }
        }
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
                .overlay { Circle().strokeBorder(foreground.opacity(0.25), lineWidth: 0.5) }
                .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(foreground)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    private var moreMenu: some View {
        Menu {
            Menu {
                ForEach(MangaReadingMode.allCases) { option in
                    Button {
                        modeRaw = option.rawValue
                    } label: {
                        if option == mode {
                            Label(option.title, systemImage: "checkmark")
                        } else {
                            Label(option.title, systemImage: option.symbol)
                        }
                    }
                }
            } label: {
                Label("阅读方式（\(mode.title)）", systemImage: "book")
            }
            Divider()
            Button { manga.goToAdjacentChapter(-1) } label: { Label("上一章", systemImage: "chevron.up") }
                .disabled(manga.currentChapter <= 0)
            Button { manga.goToAdjacentChapter(1) } label: { Label("下一章", systemImage: "chevron.down") }
                .disabled(manga.currentChapter >= manga.chapterCount - 1)
            Divider()
            Button { Task { await refreshTOC() } } label: { Label("刷新目录", systemImage: "arrow.clockwise") }
            Button(role: .destructive) { onClearChapter() } label: { Label("清除本话缓存并重载", systemImage: "trash") }
            Divider()
            Button { onDetails() } label: { Label("书籍操作", systemImage: "book") }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 42, height: 42)
                .appGlass(in: Circle(), tint: background)
                .overlay { Circle().strokeBorder(foreground.opacity(0.25), lineWidth: 0.5) }
                .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
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
        VStack(spacing: 1) {
            MangaPageSlider(fraction: pageProgress,
                            tint: foreground,
                            onScrub: { value in applyScrub(value, commit: false) },
                            onCommit: { value in applyScrub(value, commit: true) })
                .frame(height: 22)
            ZStack {
                Text(pageLabel)
                    .appFont(.system(size: 13, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(foreground.opacity(0.85))
                    .accessibilityIdentifier("reader.manga.footer")
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Text(remainingText)
                        .appFont(.system(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(foreground.opacity(0.55))
                }
            }
            .frame(height: 18)
        }
        .padding(.horizontal, 12)
        .padding(.top, 7)
        .padding(.bottom, 6)
        .frame(height: 58)
        // 面板是玻璃质感，而且跟着画布颜色走：画布黑就是深色玻璃 + 白字，
        // 画布白就是浅色玻璃 + 黑字。淡染取画布色、亮边/文字取前景色。
        .appGlass(in: Capsule(), tint: background, tintOpacity: 0.30)
        .overlay { Capsule().strokeBorder(foreground.opacity(0.35), lineWidth: 0.5) }
        .shadow(color: .black.opacity(0.22), radius: 12, y: 3)
        .padding(.horizontal, 20)
        .padding(.bottom, 6)
    }

    private func applyScrub(_ value: Double, commit: Bool) {
        let count = pageCount
        guard count > 0 else { return }
        let page = Int((value * Double(max(count - 1, 0))).rounded())
        if commit {
            scrub = nil
            manga.requestScroll(toPage: page)
        } else {
            scrub = value
            manga.requestScroll(toPage: page, reportProgress: false)
        }
    }

    // MARK: 覆盖层与动作

    @ViewBuilder
    private var statusOverlay: some View {
        VStack(spacing: 14) {
            if manga.loadingChapter {
                ProgressView().allowsHitTesting(false)
                Text("正在加载图片列表…").appFont(.footnote).foregroundStyle(foreground.opacity(0.7))
                    .allowsHitTesting(false)
            } else if let message = manga.errorMessage {
                Text(message).appFont(.footnote).foregroundStyle(foreground.opacity(0.8))
                    .multilineTextAlignment(.center).padding(.horizontal, 24)
                    .allowsHitTesting(false)
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
                    .allowsHitTesting(false)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(background.opacity(0.9))
        .background {
            // 遮罩上的空白处点一下就开/收顶部面板（按钮照常点，不受影响）。
            Color.clear.contentShape(Rectangle()).onTapGesture { toggleBars() }
        }
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

// MARK: - 底栏滑块（参考图样式）

/// 细轨道 + 药丸滑块的页进度条。
/// 系统 Slider 在 iOS 26 上会把整条轨道填成主题色，压在漫画上是一条粗条，
/// 参考图（浏览器里的阅读页）是细轨道 + 药丸滑块，所以这里自绘。
/// 颜色跟随画布前景：黑画布是白滑块/白字，白画布是黑滑块/黑字。
private struct MangaPageSlider: View {
    let fraction: Double
    let tint: Color
    let onScrub: (Double) -> Void
    let onCommit: (Double) -> Void

    private let thumb = CGSize(width: 30, height: 16)
    private let trackHeight: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let usable = max(width - thumb.width, 1)
            let progress = min(max(fraction, 0), 1)
            let travel = usable * progress
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(tint.opacity(0.22))
                    .frame(width: usable, height: trackHeight)
                    .offset(x: thumb.width / 2)
                Capsule()
                    .fill(tint.opacity(0.55))
                    .frame(width: max(travel, trackHeight), height: trackHeight)
                    .offset(x: thumb.width / 2)
                RoundedRectangle(cornerRadius: thumb.height / 2, style: .continuous)
                    .fill(tint)
                    .frame(width: thumb.width, height: thumb.height)
                    .shadow(color: .black.opacity(0.22), radius: 3, y: 1)
                    .offset(x: travel)
            }
            .frame(width: width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in onScrub(fraction(for: value.location.x, usable: usable)) }
                    .onEnded { value in onCommit(fraction(for: value.location.x, usable: usable)) }
            )
        }
        .accessibilityElement()
        .accessibilityLabel("页进度")
        .accessibilityValue("\(Int((min(max(fraction, 0), 1)) * 100))%")
        .accessibilityIdentifier("reader.manga.slider")
    }

    private func fraction(for x: CGFloat, usable: CGFloat) -> Double {
        let value = (x - thumb.width / 2) / usable
        return min(max(Double(value), 0), 1)
    }
}
