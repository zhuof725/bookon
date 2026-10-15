import SwiftUI

/// 离线目录页 fixture：真实 ReaderTocSheet 组件 + 合成章节与预缓存管理器。
/// 不访问网络与真实正文缓存；预缓存用固定延迟模拟，可配置单章失败一次。
struct ReaderTocHarnessView: View {
    private static let fixtureChapters: [BookChapter] = {
        var list: [BookChapter] = [BookChapter(url: "", title: "第一卷 学院生活", index: 0, isVolume: true)]
        for i in 1...30 {
            var chapter = BookChapter(url: "https://toc.invalid/chapter/\(i)", title: "第\(i)章 语言课\(i)", index: i)
            if i == 1 { chapter.updateTime = "2026-10-01" }
            if i == 5 { chapter.updateTime = "3分钟前" }
            if i == 9 { chapter.updateTime = "2026-09-30 12:00" }
            if i == 12 { chapter.isVip = true }
            list.append(chapter)
        }
        return list
    }()
    private static let preCached: Set<Int> = [5, 9, 12]

    @StateObject private var manager: ChapterPrecacheManager
    @StateObject private var probe: ReaderTocProbe

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let failAt = arguments.first(where: { $0.hasPrefix("--reader-toc-fail=") })
            .flatMap { Int($0.dropFirst("--reader-toc-fail=".count)) }
        let probe = ReaderTocProbe(failAt: failAt)
        _probe = StateObject(wrappedValue: probe)
        let manager = ChapterPrecacheManager()
        let services = ReaderTocServices(
            isCached: { chapter in Self.preCached.contains(chapter.index) },
            load: { chapter, _ in try await probe.load(chapter.index) })
        manager.register(chapters: Self.fixtureChapters, currentIndex: 2,
                         bookName: "测试书籍", services: services, canPrecache: true)
        _manager = StateObject(wrappedValue: manager)
    }

    var body: some View {
        VStack(spacing: 16) {
            PrecacheCardView(manager: manager)
                .padding(.horizontal, 16)
                .padding(.top, 8)
            ReaderTocSheet(chapters: Self.fixtureChapters, currentIndex: 2,
                           manager: manager,
                           onSelect: { probe.recordSelection($0) })
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 2) {
                Text("loads=\(probe.loads)").accessibilityIdentifier("reader.toc.harness.loads")
                Text(probe.selection).accessibilityIdentifier("reader.toc.harness.selection")
            }
            .appFont(.caption).padding(6).background(.thinMaterial).allowsHitTesting(false)
        }
    }
}

/// 合成预缓存服务：每章固定耗时；failAt 章节首次调用抛错，用于验证「失败即停、重试续跑」。
@MainActor
final class ReaderTocProbe: ObservableObject {
    @Published private(set) var loads = 0
    @Published private(set) var selection = "none"
    private let failAt: Int?
    private var failedOnce = false

    init(failAt: Int?) { self.failAt = failAt }

    func load(_ index: Int) async throws {
        try await Task.sleep(nanoseconds: 300_000_000)
        if let failAt, index == failAt, !failedOnce {
            failedOnce = true
            throw ReaderTocProbeError.denied
        }
        loads += 1
    }

    func recordSelection(_ index: Int) { selection = "selected=\(index)" }

    enum ReaderTocProbeError: LocalizedError {
        case denied
        var errorDescription: String? { "书源暂时拒绝访问" }
    }
}
