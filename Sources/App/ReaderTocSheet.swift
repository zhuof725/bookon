import SwiftUI

/// 目录页用到的缓存查询与预缓存动作。生产端由阅读器注入真实的正文缓存与加载器，
/// 离线 UI 测试注入合成实现；本文件不直接依赖网络栈或 WebBook。
struct ReaderTocServices {
    /// 该章正文是否已在本地缓存（内存或磁盘）。
    var isCached: (BookChapter) async -> Bool
    /// 预缓存一章正文；已缓存时应当立即成功返回。nextChapterURL 用于书源的续页规则。
    var load: (_ chapter: BookChapter, _ nextChapterURL: String?) async throws -> Void

    static let unavailable = ReaderTocServices(
        isCached: { _ in false },
        load: { _, _ in throw ReaderTocError.unavailable })

    enum ReaderTocError: LocalizedError {
        case unavailable
        var errorDescription: String? { "当前书籍不支持预缓存" }
    }
}

/// 目录的「已缓存」标识与预缓存进度。进度条覆盖当前章之后的固定窗口，
/// 已缓存的章节直接计入完成数、不重复请求书源；失败即停并保留进度，可重试。
@MainActor
final class ReaderTocModel: ObservableObject {
    enum PrecachePhase: Equatable {
        case running
        case finished
        case stopped
        case failed(String)
    }
    struct PrecacheProgress: Equatable {
        var done = 0
        var total = 0
        var phase: PrecachePhase = .running
    }

    /// 一次预缓存的窗口大小：当前章之后要保证已缓存的章节数。
    static let window = 20

    @Published private(set) var cached: Set<String> = []
    @Published private(set) var progress: PrecacheProgress?
    private var precacheTask: Task<Void, Never>?

    var isPrecaching: Bool { progress?.phase == .running }

    /// 打开目录时刷新「已缓存」标识；只报告真实存在的缓存，不虚构。
    /// 分批发布，避免上千章目录每章触发一次刷新。
    func refreshCacheStatus(chapters: [BookChapter], services: ReaderTocServices) async {
        let items = chapters.filter { !$0.isVolume && !$0.url.isEmpty }
        var found: Set<String> = []
        var processed = 0
        for chapter in items {
            if Task.isCancelled { return }
            if await services.isCached(chapter) { found.insert(chapter.id) }
            processed += 1
            if processed % 32 == 0 { cached.formUnion(found) }
        }
        cached.formUnion(found)
    }

    /// 预缓存当前章之后的窗口章节；卷标题不占窗口，越界自动截断。
    func startPrecache(chapters: [BookChapter], currentIndex: Int, services: ReaderTocServices) {
        guard !isPrecaching else { return }
        let queue = ChapterNavigation.prefetchIndices(after: currentIndex, chapters: chapters, limit: Self.window)
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
                // 已经缓存的章节不重复请求书源，直接计入完成数。
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
                    self.progress = PrecacheProgress(done: done, total: total,
                                                     phase: .failed(error.localizedDescription))
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

    /// 用户主动停止：保留已完成进度，状态改为已停止。
    func cancelPrecache() {
        guard isPrecaching else { return }
        precacheTask?.cancel()
        precacheTask = nil
        if let current = progress {
            progress = PrecacheProgress(done: current.done, total: current.total, phase: .stopped)
        }
    }

    /// 关闭进度提示 / 离开阅读器：取消在途预缓存并清除进度条。
    func stopAndClear() {
        precacheTask?.cancel()
        precacheTask = nil
        progress = nil
    }
}

/// 阅读器目录页：章节标题 + 书源更新时间 + 已缓存标识 + 预缓存进度条。
/// 章节列表与 ReaderView 的 chapters 是同一份快照；点选只回调索引，不直接翻页。
struct ReaderTocSheet: View {
    @ThemePalette private var palette
    let chapters: [BookChapter]
    let currentIndex: Int
    @ObservedObject var model: ReaderTocModel
    let services: ReaderTocServices
    var canPrecache: Bool = true
    let onSelect: (Int) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let progress = model.progress {
                    precacheHeader(progress)
                }
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
            }
            .navigationTitle("目录（\(chapters.count)）")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if canPrecache {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            model.startPrecache(chapters: chapters, currentIndex: currentIndex, services: services)
                        } label: {
                            Label("预缓存", systemImage: "arrow.down.circle")
                        }
                        .disabled(model.isPrecaching)
                        .accessibilityIdentifier("reader.toc.precache")
                    }
                }
            }
        }
        .task { await model.refreshCacheStatus(chapters: chapters, services: services) }
    }

    @ViewBuilder
    private func row(_ chapter: BookChapter) -> some View {
        let isCached = model.cached.contains(chapter.id)
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

    private func precacheHeader(_ progress: ReaderTocModel.PrecacheProgress) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(statusText(progress))
                    .appFont(.subheadline)
                    .lineLimit(2)
                    .accessibilityIdentifier("reader.toc.precache.status")
                Spacer(minLength: 8)
                if progress.phase == .running {
                    Button("停止") { model.cancelPrecache() }
                        .accessibilityIdentifier("reader.toc.precache.stop")
                } else {
                    Button { model.stopAndClear() } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 18))
                            .foregroundStyle(palette.secondary)
                    }
                    .accessibilityLabel("关闭预缓存提示")
                    .accessibilityIdentifier("reader.toc.precache.dismiss")
                }
            }
            ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                .accessibilityIdentifier("reader.toc.precache.bar")
            if case .failed = progress.phase {
                Button("重试") {
                    model.startPrecache(chapters: chapters, currentIndex: currentIndex, services: services)
                }
                .accessibilityIdentifier("reader.toc.precache.retry")
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(SettingsGlassSurface())
        .padding(.horizontal, 16).padding(.top, 8)
    }

    private func statusText(_ progress: ReaderTocModel.PrecacheProgress) -> String {
        switch progress.phase {
        case .running: return "正在预缓存 \(progress.done)/\(progress.total)"
        case .finished: return "预缓存完成：共 \(progress.total) 章"
        case .stopped: return "已停止：已缓存 \(progress.done)/\(progress.total)"
        case .failed(let message): return "预缓存中断：\(message)"
        }
    }
}
