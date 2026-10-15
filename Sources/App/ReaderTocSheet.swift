import SwiftUI

/// 目录页用到的缓存查询与预缓存动作。生产端由阅读器注入真实的正文缓存与加载器，
/// 离线 UI 测试注入合成实现；本文件不直接依赖网络栈或 WebBook。
struct ReaderTocServices {
    var isCached: (BookChapter) async -> Bool
    var load: (_ chapter: BookChapter, _ nextChapterURL: String?) async throws -> Void
    static let unavailable = ReaderTocServices(
        isCached: { _ in false },
        load: { _, _ in throw ReaderTocError.unavailable })
    enum ReaderTocError: LocalizedError {
        case unavailable
        var errorDescription: String? { "当前书籍不支持预缓存" }
    }
}

/// 预缓存状态与进度。单例，在「我的」页面显示进度条，在目录页提供已缓存标识。
/// 阅读器打开时注册当前书籍的目录与服务；预缓存走与阅读同一条链路（ChapterContentLoader）。
/// 进度状态在「我的」页面可见，不放在目录页，避免目录页因频繁刷新进度而卡顿。
@MainActor
final class ChapterPrecacheManager: ObservableObject {
    static let shared = ChapterPrecacheManager()

    enum PrecachePhase: Equatable {
        case running, finished, stopped, failed(String)
    }
    struct PrecacheProgress: Equatable {
        var done = 0
        var total = 0
        var phase: PrecachePhase = .running
    }

    static let windowRange = 1...50
    static let windowKey = "precache.window.v1"

    /// 预缓存窗口章数。默认 10；用户在「我的」预缓存卡片用滑条调整，持久化到 UserDefaults。
    @Published var window: Int = {
        let stored = UserDefaults.standard.integer(forKey: ChapterPrecacheManager.windowKey)
        return ChapterPrecacheManager.windowRange.contains(stored) ? stored : 10
    }()

    /// 清除持久化的窗口设置（离线测试用，避免用例间互相污染）。
    static func resetStoredWindow() {
        UserDefaults.standard.removeObject(forKey: windowKey)
    }

    func setWindow(_ value: Int) {
        let clamped = min(max(value, Self.windowRange.lowerBound), Self.windowRange.upperBound)
        guard clamped != window else { return }
        window = clamped
        UserDefaults.standard.set(clamped, forKey: Self.windowKey)
    }

    @Published private(set) var cached: Set<String> = []
    @Published private(set) var progress: PrecacheProgress?
    @Published private(set) var bookName: String?
    @Published private(set) var canPrecache = false

    private var precacheTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var chapters: [BookChapter] = []
    private var currentIndex = 0
    private var services: ReaderTocServices?
    private var hasRefreshed = false

    var isPrecaching: Bool { progress?.phase == .running }

    /// 阅读器加载完目录后注册：设置当前书籍、章节列表、索引与缓存服务。
    /// 新书籍会取消旧的预缓存并重置标识。注册只发生一次（除非换书）。
    func register(chapters: [BookChapter], currentIndex: Int, bookName: String,
                  services: ReaderTocServices?, canPrecache: Bool) {
        if self.bookName == bookName, !chapters.isEmpty, self.chapters.count == chapters.count {
            self.currentIndex = currentIndex
            return
        }
        cancelPrecache()
        stopAndClear()
        self.chapters = chapters
        self.currentIndex = currentIndex
        self.bookName = bookName
        self.services = services
        self.canPrecache = canPrecache
        self.cached = []
        self.hasRefreshed = false
    }

    /// 更新当前阅读位置（翻页时调用），供预缓存窗口锚定起点。
    func updateCurrentIndex(_ index: Int) {
        currentIndex = index
    }

    /// 目录页打开时刷新已缓存标识；只刷新一次，后台异步执行不阻塞 UI。
    func refreshCacheStatusIfNeeded() {
        guard !hasRefreshed, let services, !chapters.isEmpty else { return }
        hasRefreshed = true
        let items = chapters.filter { !$0.isVolume && !$0.url.isEmpty }
        refreshTask?.cancel()
        refreshTask = Task.detached { [weak self] in
            var found: Set<String> = []
            for chapter in items {
                if Task.isCancelled { return }
                if await services.isCached(chapter) { found.insert(chapter.id) }
            }
            await MainActor.run { self?.cached = found }
        }
    }

    /// 预缓存当前章之后的窗口章节；卷标题不占窗口，越界截断。
    func startPrecache() {
        guard !isPrecaching, let services else { return }
        let queue = ChapterNavigation.prefetchIndices(after: currentIndex, chapters: chapters, limit: window)
        guard !queue.isEmpty else { return }
        let snapshot = chapters
        let total = queue.count
        progress = PrecacheProgress(done: 0, total: total, phase: .running)
        precacheTask?.cancel()
        precacheTask = Task { [weak self] in
            var done = 0
            for index in queue {
                guard let self, !Task.isCancelled else { return }
                guard snapshot.indices.contains(index) else { continue }
                let chapter = snapshot[index]
                if self.cached.contains(chapter.id) {
                    done += 1
                    self.progress = PrecacheProgress(done: done, total: total, phase: .running)
                    continue
                }
                let next = ChapterNavigation.contentIndex(from: index + 1, direction: 1, chapters: snapshot)
                    .map { snapshot[$0].url }
                do {
                    try await services.load(chapter, next)
                } catch is CancellationError {
                    return
                } catch {
                    self.progress = PrecacheProgress(done: done, total: total, phase: .failed(error.localizedDescription))
                    self.precacheTask = nil
                    return
                }
                guard !Task.isCancelled else { return }
                done += 1
                self.cached.insert(chapter.id)
                self.progress = PrecacheProgress(done: done, total: total, phase: .running)
            }
            guard let self else { return }
            self.progress = PrecacheProgress(done: done, total: total, phase: .finished)
            self.precacheTask = nil
        }
    }

    func cancelPrecache() {
        guard isPrecaching else { return }
        precacheTask?.cancel()
        precacheTask = nil
        if let current = progress {
            progress = PrecacheProgress(done: current.done, total: current.total, phase: .stopped)
        }
    }

    func stopAndClear() {
        precacheTask?.cancel()
        precacheTask = nil
        refreshTask?.cancel()
        refreshTask = nil
        progress = nil
    }
}

/// 阅读器目录页：章节标题 + 书源更新时间 + 已缓存标识。
/// 预缓存进度条不在目录页显示（在「我的」页面），避免目录卡顿。
struct ReaderTocSheet: View {
    @ThemePalette private var palette
    let chapters: [BookChapter]
    let currentIndex: Int
    @ObservedObject var manager: ChapterPrecacheManager
    let onSelect: (Int) -> Void

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List(chapters) { chapter in
                    row(chapter)
                        .independentGlassRow()
                        .id(chapter.index)
                }
                .scrollContentBackground(.hidden)
                .background { AppThemeCanvas().ignoresSafeArea() }
                .onAppear { proxy.scrollTo(currentIndex, anchor: .center) }
            }
            .navigationTitle("目录（\(chapters.count)）")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { manager.refreshCacheStatusIfNeeded() }
    }

    @ViewBuilder
    private func row(_ chapter: BookChapter) -> some View {
        let isCached = manager.cached.contains(chapter.id)
        Button { onSelect(chapter.index) } label: {
            if chapter.isVolume {
                Text(chapter.title).appFont(.headline)
                    .foregroundStyle(chapter.index == currentIndex ? palette.accent : palette.secondary)
            } else {
                HStack(spacing: 8) {
                    Text(chapter.title)
                        .foregroundStyle(chapter.index == currentIndex ? palette.accent : palette.primary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if let time = chapter.updateTime, !time.isEmpty {
                        Text(time).appFont(.caption).foregroundStyle(palette.secondary).lineLimit(1)
                    }
                    if chapter.isVip {
                        Image(systemName: "lock.fill").font(.caption).foregroundStyle(palette.secondary)
                    }
                    if isCached {
                        Image(systemName: "arrow.down.circle.fill").font(.caption)
                            .foregroundStyle(palette.secondary)
                    }
                }
            }
        }
        .accessibilityIdentifier("reader.toc.row.\(chapter.index)")
        .accessibilityValue(chapter.isVolume ? "" : (isCached ? "已缓存" : "未缓存"))
    }
}

/// 「我的」页面全局设置：所有书源书籍阅读时自动预加载的章数（本地书籍不预加载）。
/// 始终显示，不依赖是否打开过书籍；手动预缓存也使用同一章数。
struct PrecacheWindowSettingView: View {
    @ThemePalette private var palette
    @ObservedObject var manager: ChapterPrecacheManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("章节预缓存").appFont(.headline)
                Spacer(minLength: 8)
                Text("\(manager.window) 章").appFont(.title3).foregroundStyle(palette.secondary)
                    .accessibilityIdentifier("precache.windowValue")
            }
            Slider(
                value: Binding(
                    get: { Double(manager.window) },
                    set: { manager.setWindow(Int($0.rounded())) }
                ),
                in: Double(ChapterPrecacheManager.windowRange.lowerBound)...Double(ChapterPrecacheManager.windowRange.upperBound),
                step: 1
            )
            .disabled(manager.isPrecaching)
            .accessibilityIdentifier("precache.windowSlider")
            Text("阅读书源书籍时自动预加载后续章节，对所有书源生效。")
                .appFont(.footnote).foregroundStyle(palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(SettingsGlassSurface())
    }
}

/// 「我的」页面预缓存卡片：显示当前阅读书籍的预缓存状态与进度条。
/// 由阅读器注册书籍信息后激活；离开阅读器后进度仍可见，直到完成或清除。
struct PrecacheCardView: View {
    @ThemePalette private var palette
    @ObservedObject var manager: ChapterPrecacheManager

    var body: some View {
        if manager.bookName != nil {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.down.circle").foregroundStyle(palette.accent)
                    Text(manager.bookName ?? "").appFont(.headline).lineLimit(1)
                }
                if let progress = manager.progress {
                    HStack(spacing: 10) {
                        Text(statusText(progress)).appFont(.subheadline).lineLimit(2)
                            .accessibilityIdentifier("precache.status")
                        Spacer(minLength: 8)
                        if progress.phase == .running {
                            Button("停止") { manager.cancelPrecache() }
                                .accessibilityIdentifier("precache.stop")
                        } else {
                            Button { manager.stopAndClear() } label: {
                                Image(systemName: "xmark.circle.fill").font(.system(size: 18))
                                    .foregroundStyle(palette.secondary)
                            }
                            .accessibilityLabel("关闭预缓存状态")
                            .accessibilityIdentifier("precache.dismiss")
                        }
                    }
                    ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                        .accessibilityIdentifier("precache.bar")
                    if case .failed = progress.phase {
                        Button("重试") { manager.startPrecache() }
                            .accessibilityIdentifier("precache.retry")
                    }
                } else if manager.canPrecache {
                    Button {
                        manager.startPrecache()
                    } label: {
                        Label("预缓存后续 \(manager.window) 章", systemImage: "arrow.down.circle")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .accessibilityIdentifier("precache.start")
                }
            }
            .padding(.horizontal, 18).padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(SettingsGlassSurface())
        }
    }

    private func statusText(_ progress: ChapterPrecacheManager.PrecacheProgress) -> String {
        switch progress.phase {
        case .running: return "正在预缓存 \(progress.done)/\(progress.total)"
        case .finished: return "预缓存完成：共 \(progress.total) 章"
        case .stopped: return "已停止：已缓存 \(progress.done)/\(progress.total)"
        case .failed(let message): return "预缓存中断：\(message)"
        }
    }
}
