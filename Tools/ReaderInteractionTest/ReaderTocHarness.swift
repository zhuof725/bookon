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
        // 滑条窗口设置持久化在 UserDefaults，测试间重置避免污染。
        ChapterPrecacheManager.resetStoredWindow()
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
        if ProcessInfo.processInfo.arguments.contains("--reader-bubble") {
            UserDefaults.standard.removeObject(forKey: "reader.bubble.styles.v1")
            BubbleStyleRuntime.set(nil)
        }
    }

    private static var bubbleChecks: (square: Bool, svgReject: Bool) {
        let square = BubbleStyle(name: "验收", mode: "template", template: "square", format: "N{n}", followText: false, colorHex: "#FF0000", scale: 1.2, aspect: 1.4)
        let image = BubbleStyleRenderer.image(style: square, count: 120, fontSize: 23, color: .label)
        let svgReject = BubbleSVG.validate("<svg viewBox=\"0 0 1 1\"><script/></svg>") != nil
            && BubbleSVG.validate("<svg viewBox=\"0 0 8 6\"><rect width=\"8\" height=\"6\" fill=\"#112233\"/></svg>") == nil
        return (image.size.width > image.size.height && image.size.width > 43, svgReject)
    }

    @State private var quickShown = false
    @State private var bubbleShown = false
    @State private var quickResult: String?

    var body: some View {
        VStack(spacing: 16) {
            if ProcessInfo.processInfo.arguments.contains("--reader-quick") {
                Button("打开快捷菜单") { quickShown = true }.accessibilityIdentifier("reader.quick.open")
            }
            if ProcessInfo.processInfo.arguments.contains("--reader-bubble") {
                Button("打开气泡设置") { bubbleShown = true }.accessibilityIdentifier("reader.bubble.open")
            }
            // 全局章数设置卡片较高，只在滑条用例中显示，避免把目录行挤出可见区。
            if ProcessInfo.processInfo.arguments.contains("--reader-toc-setting") {
                PrecacheWindowSettingView(manager: manager)
                    .padding(.horizontal, 16)
            }
            PrecacheCardView(manager: manager)
                .padding(.horizontal, 16)
                .padding(.top, 8)
            ReaderTocSheet(chapters: Self.fixtureChapters, currentIndex: 2,
                           manager: manager,
                           onSelect: { probe.recordSelection($0) },
                           onRefresh: {
                               try? await Task.sleep(nanoseconds: 300_000_000)
                               probe.recordRefresh()
                               return "目录已刷新：新增 2 章，共 32 章"
                           })
        }
        .sheet(isPresented: $quickShown) {
            NavigationStack {
                ReaderQuickPanel(book: Book(bookUrl: "fixture", name: "我正经学生，每天只吃九种魔药", author: "离线作者", origin: "fixture"),
                    sourceName: "测试书源", position: "4/386", message: quickResult,
                    enabled: ["refresh", "toc", "clear", "login", "source", "rules", "browser"],
                    action: { quickResult = "action=" + $0 })
                    .navigationTitle("书籍操作")
                    .toolbar { Button("完成") { quickShown = false } }
            }
            .presentationDetents([.height(440), .large])
        }
        .sheet(isPresented: $bubbleShown) {
            NavigationStack {
                BubbleStyleSettingsView()
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { bubbleShown = false } } }
            }
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 2) {
                Text("loads=\(probe.loads)").accessibilityIdentifier("reader.toc.harness.loads")
                Text(probe.selection).accessibilityIdentifier("reader.toc.harness.selection")
                Text("refreshes=\(probe.refreshes)").accessibilityIdentifier("reader.toc.harness.refreshes")
                Text("square=\(Self.bubbleChecks.square)").accessibilityIdentifier("reader.bubble.square")
                Text("svgReject=\(Self.bubbleChecks.svgReject)").accessibilityIdentifier("reader.bubble.svgReject")
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
        // 停止用例传 --reader-toc-slow，放慢加载以便在运行中点中「停止」。
        let slow = ProcessInfo.processInfo.arguments.contains("--reader-toc-slow")
        try await Task.sleep(nanoseconds: slow ? 1_500_000_000 : 300_000_000)
        if let failAt, index == failAt, !failedOnce {
            failedOnce = true
            throw ReaderTocProbeError.denied
        }
        loads += 1
    }

    func recordSelection(_ index: Int) { selection = "selected=\(index)" }

    @Published private(set) var refreshes = 0
    func recordRefresh() { refreshes += 1 }

    enum ReaderTocProbeError: LocalizedError {
        case denied
        var errorDescription: String? { "书源暂时拒绝访问" }
    }
}
