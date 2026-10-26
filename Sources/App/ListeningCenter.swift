import SwiftUI
import Combine

/// 全局收听中心：听书（TTS 朗读）＋ 有声书（书源音频）共用一份播放状态。
///
/// 播放器原先是阅读器的 `@StateObject`，退出阅读页就停。现在由这里托管：
/// 阅读器在的时候由它提供段落/章节能力；离开阅读页后改用中心自己的章节加载
/// （在线源走 `ChapterContentLoader`，本地书读文件），播放不中断，
/// 底栏上方的迷你播放条据此显示。
@MainActor
final class ListeningCenter: ObservableObject {
    static let shared = ListeningCenter()

    enum Mode { case none, aloud, audio }

    let aloud = ReaderAloudController()
    let audio = BookAudioPlayer()

    /// 当前收听的书与目录：迷你条、收听面板、后台加载都从这里取。
    @Published private(set) var book: Book?
    @Published private(set) var source: BookSource?
    @Published private(set) var chapters: [BookChapter] = []
    @Published private(set) var chapterIndex = 0
    /// 阅读器是否在前台：它自带控制条，此时不显示迷你播放条。
    @Published private(set) var readerAttached = false
    /// 迷你条点开的收听面板。
    @Published var showSheet = false

    /// 后台播放时自己加载的段落（章节号 → 段落），只保留最近几章。
    private var detachedUnits: [Int: [AloudUnit]] = [:]
    private let cacheLimit = 6

    /// 播放器自己的状态变化（自然播完、锁屏暂停…）不经过中心，转发一下让迷你条跟着刷新。
    private var observers: Set<AnyCancellable> = []

    private init() {
        aloud.objectWillChange
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.objectWillChange.send() }
            }
            .store(in: &observers)
        audio.objectWillChange
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.objectWillChange.send() }
            }
            .store(in: &observers)
    }

    // MARK: 状态

    var mode: Mode {
        if aloud.isRunning { return .aloud }
        if audio.chapterURL != nil { return .audio }
        return .none
    }

    var isActive: Bool { mode != .none }
    /// 迷你播放条只在「有播放会话 + 阅读器不在前台」时出现。
    var showsBar: Bool { isActive && !readerAttached }

    var isPlaying: Bool {
        switch mode {
        case .aloud: return aloud.isPlaying
        case .audio: return audio.isPlaying
        case .none: return false
        }
    }

    var chapterTitle: String {
        switch mode {
        case .aloud: return aloud.chapterTitle
        case .audio: return audio.chapterTitle
        case .none: return ""
        }
    }

    /// 迷你条上的一行标题：`书名 - 章节名`。
    var displayTitle: String {
        guard let book else { return "" }
        let chapter = chapterTitle
        return chapter.isEmpty ? book.name : "\(book.name) - \(chapter)"
    }

    /// 收听面板的进度（0…1）；没有可用的时长信息时返回 nil（不画进度条）。
    var progress: Double? {
        switch mode {
        case .aloud:
            guard aloud.chapterDuration > 0 else { return nil }
            return min(max(aloud.chapterPlayed / aloud.chapterDuration, 0), 1)
        case .audio:
            guard audio.duration > 0 else { return nil }
            return min(max(audio.currentTime / audio.duration, 0), 1)
        case .none:
            return nil
        }
    }

    // MARK: 阅读器生命周期

    /// 阅读器出现：换书就停掉上一本，同一本书接着播。
    func readerAppeared(book: Book) {
        if let current = self.book, current.bookUrl != book.bookUrl { stopAll() }
        self.book = book
        self.source = AppStore.shared.source(for: book.origin)
        readerAttached = true
    }

    /// 阅读器离开：还在播就转成后台收听（换成中心自己的章节加载），否则彻底停掉。
    func readerDisappeared(book: Book, chapters: [BookChapter], index: Int) {
        readerAttached = false
        self.book = book
        self.source = AppStore.shared.source(for: book.origin)
        if !chapters.isEmpty { self.chapters = chapters }
        self.chapterIndex = index
        if aloud.isRunning {
            detachedUnits.removeAll()
            aloud.attach(detachedHost())
        } else {
            aloud.detach()
        }
        if audio.chapterURL != nil {
            bindAudioCallbacks()
        } else {
            audio.stop()
        }
        if !aloud.isRunning, audio.chapterURL == nil { clearContext() }
    }

    // MARK: 迷你条控制

    func toggle() {
        switch mode {
        case .aloud: aloud.togglePlay()
        case .audio: audio.toggle()
        case .none: break
        }
    }

    func skipChapter(_ direction: Int) {
        guard direction != 0 else { return }
        switch mode {
        case .aloud:
            aloud.manualChapter(direction: direction)
        case .audio:
            Task { @MainActor in await moveAudio(direction) }
        case .none:
            break
        }
    }

    /// 结束收听：停止播放并清掉迷你条。
    func stopAll() {
        aloud.stop()
        audio.stop()
        clearContext()
    }

    private func clearContext() {
        book = nil
        source = nil
        chapters = []
        chapterIndex = 0
        detachedUnits.removeAll()
        if showSheet { showSheet = false }
    }

    // MARK: 后台朗读（TTS）

    /// 阅读器不在时接管的宿主：段落/目录都由中心自己加载。
    /// 控制器是 @MainActor 的，这些闭包只在主线程被调用；闭包类型不带隔离，
    /// 所以用 `MainActor.assumeIsolated` 读中心的状态。
    private func detachedHost() -> ReaderAloudHost {
        var host = ReaderAloudHost()
        host.chapterCount = { [weak self] in
            MainActor.assumeIsolated { self?.chapters.count ?? 0 }
        }
        host.chapterTitle = { [weak self] index in
            MainActor.assumeIsolated {
                guard let self, self.chapters.indices.contains(index) else { return "" }
                return self.chapters[index].title
            }
        }
        host.bookLabel = { [weak self] in
            MainActor.assumeIsolated { self?.book?.name ?? "" }
        }
        host.coverURL = { [weak self] in
            MainActor.assumeIsolated { self?.book?.coverUrl }
        }
        host.bookOrigin = { [weak self] in
            MainActor.assumeIsolated { self?.book?.origin }
        }
        host.currentOffset = { 0 }
        host.units = { [weak self] index in
            MainActor.assumeIsolated { self?.detachedUnits[index] }
        }
        host.readableChapter = { [weak self] index, direction in
            MainActor.assumeIsolated { self?.readableChapter(from: index, direction: direction) }
        }
        host.openChapter = { [weak self] index in
            guard let self else { return false }
            return await self.loadForPlayback(index)
        }
        host.follow = { [weak self] chapter, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.markPlaying(chapter)
            }
        }
        return host
    }

    private func readableChapter(from target: Int, direction: Int) -> Int? {
        guard direction != 0, !chapters.isEmpty else { return nil }
        var i = target
        while chapters.indices.contains(i) {
            if !chapters[i].isVolume { return i }
            i += direction
        }
        return nil
    }

    /// 后台朗读换章：抓正文 → 切段落。成功返回 true，控制器会接着读下一章。
    private func loadForPlayback(_ index: Int) async -> Bool {
        guard let book, chapters.indices.contains(index) else { return false }
        if let cached = detachedUnits[index], !cached.isEmpty {
            chapterIndex = index
            return true
        }
        let chapter = chapters[index]
        var raw: String?
        if AppStore.shared.isLocal(book) {
            raw = AppStore.shared.localContent(book, index: index)
        } else if let source {
            let next = chapters.indices.contains(index + 1) ? chapters[index + 1].url : nil
            raw = try? await ChapterContentLoader.content(source: source, book: book, chapter: chapter,
                                                          nextChapterURL: next)
        }
        guard let raw, !raw.isEmpty else { return false }
        let units = ReaderMenuText.paragraphs(ContentBlocks.parse(raw))
            .map { AloudUnit(offset: $0.offset, text: $0.text) }
        guard !units.isEmpty else { return false }
        detachedUnits[index] = units
        trimUnitsCache(keeping: index)
        markPlaying(index)
        return true
    }

    private func trimUnitsCache(keeping index: Int) {
        guard detachedUnits.count > cacheLimit else { return }
        for key in detachedUnits.keys where abs(key - index) > 2 { detachedUnits.removeValue(forKey: key) }
    }

    private func markPlaying(_ index: Int) {
        guard chapters.indices.contains(index) else { return }
        chapterIndex = index
        if let book { AppStore.shared.updateProgress(book, index: index, title: chapters[index].title) }
    }

    // MARK: 后台有声书

    private func bindAudioCallbacks() {
        audio.onFinish = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if let url = self.book?.bookUrl { AudioProgress.clear(bookUrl: url) }
                await self.moveAudio(1)
            }
        }
        audio.onRemoteNext = { [weak self] in
            Task { @MainActor in await self?.moveAudio(1) }
        }
        audio.onRemotePrevious = { [weak self] in
            Task { @MainActor in await self?.moveAudio(-1) }
        }
        audio.onPlaybackFailed = { [weak self] in
            MainActor.assumeIsolated { _ = self?.audio.stop() }
        }
    }

    private func moveAudio(_ direction: Int) async {
        guard let next = readableChapter(from: chapterIndex + direction, direction: direction) else {
            audio.stop()
            return
        }
        await playAudio(next, resume: false)
    }

    /// 后台续播某一章（播完自动进章、锁屏上下曲、面板切章都走这里）。
    func playAudio(_ index: Int, resume: Bool = true) async {
        guard let book, chapters.indices.contains(index) else { return }
        let chapter = chapters[index]
        let source = self.source ?? AppStore.shared.source(for: book.origin)
        guard let source else { return }
        guard let urls = try? await AudioChapter.playURLs(source: source, book: book, chapter: chapter),
              !urls.isEmpty else {
            audio.stop()
            return
        }
        markPlaying(index)
        audio.onProgress = { seconds in
            AudioProgress.save(bookUrl: book.bookUrl, chapter: index, seconds: seconds)
        }
        let headers = AnalyzeUrl.headerFields(source.header, key: nil, page: 1,
                                              baseUrl: source.bookSourceUrl,
                                              context: RuleContext(source: source), jsLib: source.jsLib)
        audio.play(urls: urls, title: chapter.title, album: book.name,
                   startAt: resume ? AudioProgress.resumeSeconds(bookUrl: book.bookUrl, chapter: index) : 0,
                   coverUrl: book.coverUrl, origin: book.origin, headers: headers)
    }
}
