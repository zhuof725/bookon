import SwiftUI

/// 「探索」：自己拼的发现页。每张卡片 = 一个（或几个）书源发现分类 + 一种参考版式。
struct ExploreView: View {
    @ThemePalette private var palette
    @EnvironmentObject private var appStore: AppStore
    @ObservedObject private var ai = AIServiceStore.shared
    @StateObject private var store: ExploreStore
    @State private var sheet: ExploreSheet?
    /// AI 生成推荐语后自增，用来让卡片重新读取推荐语。
    @State private var metaTick = 0
    @State private var aiRefreshing = false
    @State private var aiToast: String?
    @State private var recommendError: String?

    private enum ExploreSheet: Identifiable {
        case add(session: String)
        case manage
        case metaImport
        case edit(ExploreBoard)
        case aiService

        var id: String {
            switch self {
            case .add(let session): return "add-" + session
            case .manage: return "manage"
            case .metaImport: return "meta"
            case .edit(let board): return "edit-" + board.id
            case .aiService: return "ai-service"
            }
        }
    }

    init() {
        _store = StateObject(wrappedValue: ExploreStore())
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                if store.boards.isEmpty {
                    emptyState
                } else {
                    ForEach(store.boards) { board in
                        ExploreBoardCard(store: store,
                                         board: board,
                                         onEdit: { sheet = .edit(board) },
                                         onDelete: { remove(board) },
                                         metaVersion: metaTick)
                    }
                    addCard
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .refreshable { await handlePullRefresh() }
        .task { await runAutoRefreshIfNeeded() }
        .overlay(alignment: .top) { aiStatusOverlay }

        .foregroundStyle(palette.primary)
        .background { AppThemeCanvas().ignoresSafeArea() }
        .navigationTitle("探索")
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) { menuButton }
        }
        .sheet(item: $sheet) { item in
            switch item {
            case .add(let session):
                ExploreBoardEditor(board: nil) { store.add($0) }
                    .id(session)
                    .environmentObject(appStore)
            case .aiService:
                NavigationStack { AIServiceView() }
            case .manage:
                ExploreManageSheet(store: store)
                    .environmentObject(appStore)
            case .metaImport:
                ExploreMetaImportSheet {
                    store.reloadMeta()
                }
            case .edit(let board):
                ExploreBoardEditor(board: board) { store.update($0.first ?? board) }
                    .environmentObject(appStore)
            }
        }
        .accessibilityIdentifier("explore.page")
    }

    /// 有板块时页尾常驻一个添加入口：不必每次都走右上角菜单。
    private var addCard: some View {
        Button {
            sheet = .add(session: UUID().uuidString)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                Text("添加板块").appFont(.system(size: 14, weight: .medium))
            }
            .foregroundStyle(palette.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background {
                RoundedRectangle(cornerRadius: AppLayout.radiusCard, style: .continuous)
                    .strokeBorder(palette.border.opacity(0.55),
                                  style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("explore.addCard")
    }

    private var menuButton: some View {
        Menu {
            Button {
                sheet = .add(session: UUID().uuidString)
            } label: {
                Label("添加板块", systemImage: "plus")
            }
            Button {
                sheet = .manage
            } label: {
                Label("管理板块", systemImage: "slider.horizontal.3")
            }
            Divider()
            Button {
                Task { await store.refreshAll() }
            } label: {
                Label("刷新全部", systemImage: "arrow.clockwise")
            }
            Button {
                sheet = .metaImport
            } label: {
                Label("导入标签 / 推荐语…", systemImage: "text.badge.plus")
            }
        } label: {
            HStack(spacing: 4) {
                Text("管理").appFont(.system(size: 14, weight: .medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(palette.primary)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background { Capsule().stroke(palette.border.opacity(0.6), lineWidth: 1) }
            .contentShape(Capsule())
        }
        .accessibilityIdentifier("explore.menu")
    }

    /// 没有板块时的空态：能自动生成就让 AI 直接来，不行才引导去配置。
    private var emptyState: some View {
        let configured = ai.activeConfig != nil
        let hasAny = !ai.configs.isEmpty
        return VStack(spacing: 14) {
            Image(systemName: configured ? "sparkles" : "sparkles.rectangle.stack")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(configured ? palette.accent : palette.secondary)
            Text(configured ? "正在按你的阅读记录找相似的书"
                 : (hasAny ? "AI 服务还没就绪" : "还没有推荐内容"))
                .appFont(.system(size: 19, weight: .semibold))
            Text(configured
                 ? "第一次会花几秒搜索并挑选。之后每 6 小时更新，下拉刷新可以立刻换一批。"
                 : (hasAny ? aiUnavailableReason
                    : "配一个 AI 服务，打开探索页就会按你的阅读记录推荐相似的小说。"))
                .appFont(.system(size: 13))
                .foregroundStyle(palette.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
            Button {
                if configured {
                    Task { await generatePicksNow() }
                } else {
                    sheet = .aiService
                }
            } label: {
                Text(configured ? "现在生成" : (hasAny ? "检查 AI 服务" : "配置 AI 服务"))
                    .appFont(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.onAccent)
                    .padding(.horizontal, 24)
                    .frame(height: 42)
                    .background { Capsule().fill(palette.accent) }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("explore.empty.primary")
            if let recommendError {
                Text(recommendError)
                    .appFont(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if configured {
                Button { sheet = .add(session: UUID().uuidString) } label: {
                    Text("或手动添加板块").appFont(.system(size: 13)).foregroundStyle(palette.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, AppLayout.gapXL)
        .padding(.vertical, AppLayout.gapXL)
    }

    /// 空态里点「现在生成」：立刻按当前书架推荐一次。
    @MainActor
    private func generatePicksNow() async {
        guard let config = ai.activeConfig,
              let provider = AICatalog.provider(for: config),
              let key = ai.apiKey(for: config.id) else { return }
        aiRefreshing = true
        defer { aiRefreshing = false }
        await recommendSimilar(provider: provider, config: config, apiKey: key, force: true)
    }

    /// 按阅读记录推荐相似小说，写进置顶的「为你推荐」板块。
    /// `force` = 用户主动要（下拉刷新 / 点按钮），失败要提示；自动流程静默。
    @MainActor
    @discardableResult
    private func recommendSimilar(provider: AIProvider, config: AIServiceConfig,
                                  apiKey: String, force: Bool) async -> Bool {
        // 排除书架已有的，以及当前板块里的（下拉刷新就是换一批）。
        var excluding = Set(appStore.books.map(\.bookUrl))
        if let board = store.boards.first(where: { $0.id == AIRecommendation.boardID }) {
            excluding.formUnion((board.pinnedBooks ?? []).map(\.bookUrl))
        }
        do {
            let outcome = try await AIRecommendation.recommend(
                shelf: appStore.books, sources: appStore.sources,
                excluding: excluding, provider: provider, config: config, apiKey: apiKey)
            let board = ExploreBoard(
                id: AIRecommendation.boardID,
                title: AIRecommendation.boardTitle,
                subtitle: outcome.subtitle,
                layout: .forYou,
                categories: [],
                count: AIRecommendation.targetCount,
                pinnedBooks: outcome.books)
            store.upsert(board, atFront: true)
            metaTick += 1
            recommendError = nil
            showToast("已更新「为你推荐」")
            return true
        } catch {
            // 失败不闪一下就消失：留在页面上，让用户能看清原因并重试。
            recommendError = error.localizedDescription
            return false
        }
    }

    /// 打开探索页时的 AI 自动流程：先挑书源分类做推荐板块，再补推荐语。
    /// 失败不打断用户，只推迟下一次。
    @MainActor
    private func runAutoRefreshIfNeeded() async {
        let service = AIServiceStore.shared
        guard let config = service.activeConfig,
              let provider = AICatalog.provider(for: config),
              let key = service.apiKey(for: config.id) else { return }
        let hasBoard = store.boards.contains { $0.id == AIRecommendation.boardID }
        // 还没有推荐板块时不等冷却：用户第一次进来就应该看到内容。
        let shouldPick = hasBoard ? AIExploreAutoRefresh.shouldPick : AIExploreAutoRefresh.picksEnabled
        guard shouldPick || AIExploreAutoRefresh.shouldRun else { return }

        aiRefreshing = true
        defer { aiRefreshing = false }

        // 1) 按阅读记录推荐相似小说，生成置顶的「为你推荐」板块。
        if shouldPick {
            let ok = await recommendSimilar(provider: provider, config: config, apiKey: key, force: false)
            // 失败不写冷却时间，下次进来会重试；成功才计时。
            if ok { AIExploreAutoRefresh.picksLastRun = Date() }
        }

        // 2) 给还没有推荐语的书补一批标签与推荐语。
        guard AIExploreAutoRefresh.shouldRun else { return }

        var seen = Set<String>()
        var targets: [Book] = []
        for board in store.boards {
            for category in board.visibleCategories {
                for book in store.books(for: category) ?? [] {
                    guard seen.insert(book.bookUrl).inserted else { continue }
                    let reason = ExploreMetaStore.reason(for: book.bookUrl) ?? ""
                    if reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        targets.append(book)
                    }
                }
            }
        }
        let batch = Array(targets.prefix(AIRecommender.maxBooks))
        // 页面还没加载出书（网络慢或首次进入）时不消费冷却时间，下次再来。
        guard !batch.isEmpty else { return }

        do {
            let count = try await AIRecommender.generate(books: batch, provider: provider,
                                                         config: config, apiKey: key)
            if count > 0 { metaTick += 1 }
        } catch {
            // 自动流程不弹窗；仍然记录时间，避免反复失败持续消耗额度。
        }
        AIExploreAutoRefresh.lastRun = Date()
    }

    /// 顶部短暂提示，让自动流程有可见反馈。
    @MainActor
    private func showToast(_ text: String) {
        withAnimation(.easeOut(duration: 0.2)) { aiToast = text }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            withAnimation(.easeIn(duration: 0.2)) { aiToast = nil }
        }
    }

    /// 说明为什么没有可用服务，精确到缺哪一项。
    private var aiUnavailableReason: String {
        if ai.configs.isEmpty { return "还没有配置 AI 服务，无法生成推荐。" }
        let ordered = ai.orderedConfigs
        if let broken = ordered.first(where: { !ai.hasKey(for: $0.id) }) {
            return "「\(broken.displayName)」没有读到 API Key。打开它重新填一次密钥并点保存。"
        }
        if let broken = ordered.first(where: { $0.trimmedModel.isEmpty }) {
            return "「\(broken.displayName)」还没有填模型名。"
        }
        if let disabled = ordered.first(where: { !$0.enabled }) {
            return "「\(disabled.displayName)」被停用了。"
        }
        return "AI 服务不可用，点「检查 AI 服务」查看配置。"
    }

    /// 下拉刷新：先换一批推荐，再补失败过的板块。
    /// 不在这里强制刷新全部分类 —— 一次几十个请求会把书源打挂，整页变「加载失败」。
    @MainActor
    private func handlePullRefresh() async {
        guard let config = ai.activeConfig,
              let provider = AICatalog.provider(for: config),
              let key = ai.apiKey(for: config.id) else {
            // 没有可用服务时必须说清楚，否则用户只觉得「刷了没反应」。
            recommendError = aiUnavailableReason
            await store.retryFailed()
            return
        }

        recommendError = nil
        aiRefreshing = true
        let before = recommendedURLs()
        let ok = await recommendSimilar(provider: provider, config: config, apiKey: key, force: true)
        aiRefreshing = false
        if ok {
            AIExploreAutoRefresh.picksLastRun = Date()
            let after = recommendedURLs()
            if !before.isEmpty, before == after {
                recommendError = "这次没搜到新的书。书源返回的结果有限，换几个书源或稍后再试。"
            }
        }

        // 板块书单在后台刷新，不阻塞下拉手势；失败的分类会保留旧数据。
        Task { await store.refreshAll() }
    }

    /// 当前推荐板块里已有的书，用来判断「换一批」是否真的换了。
    private func recommendedURLs() -> Set<String> {
        guard let board = store.boards.first(where: { $0.id == AIRecommendation.boardID }),
              let books = board.pinnedBooks else { return [] }
        return Set(books.map(\.bookUrl))
    }

    private var aiStatusOverlay: some View {
        Group {
            if aiRefreshing {
                refreshingPill
            } else if let recommendError {
                recommendErrorCard(recommendError)
            } else if let aiToast {
                toastPill(aiToast)
            }
        }
    }

    private var refreshingPill: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("AI 正在整理推荐…").appFont(.footnote)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Capsule().fill(.regularMaterial))
        .padding(.top, 6)
        .accessibilityIdentifier("explore.ai.auto.busy")
    }

    private func toastPill(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles").font(.system(size: 12, weight: .semibold))
            Text(text).appFont(.footnote)
        }
        .foregroundStyle(palette.primary)
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Capsule().fill(.regularMaterial))
        .padding(.top, 6)
        .transition(.opacity)
        .accessibilityIdentifier("explore.ai.toast")
    }

    private func recommendErrorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.orange)
                Text(message)
                    .appFont(.footnote)
                    .foregroundStyle(palette.primary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 14) {
                Button("重试") { retryRecommend() }
                Button("检查 AI 服务") { sheet = .aiService }
                Button("关闭") { recommendError = nil }
            }
            .appFont(.caption)
            .foregroundStyle(palette.accent)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: 360, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.regularMaterial)
        }
        .padding(.horizontal, AppLayout.pageInset)
        .padding(.top, 6)
        .accessibilityIdentifier("explore.recommend.error")
    }

    @MainActor
    private func retryRecommend() {
        let service = AIServiceStore.shared
        guard let config = service.activeConfig,
              let provider = AICatalog.provider(for: config),
              let key = service.apiKey(for: config.id) else {
            recommendError = "还没有可用的 AI 服务。"
            return
        }
        recommendError = nil
        aiRefreshing = true
        Task {
            let ok = await recommendSimilar(provider: provider, config: config, apiKey: key, force: true)
            if ok { AIExploreAutoRefresh.picksLastRun = Date() }
            aiRefreshing = false
        }
    }

    private func remove(_ board: ExploreBoard) {
        withAnimation(.easeInOut(duration: 0.2)) {
            store.remove(id: board.id)
        }
    }
}

// MARK: - 管理板块

struct ExploreManageSheet: View {
    @ThemePalette private var palette
    @AppStorage("explore.ai.autoRefresh.v1") private var autoRefresh = true
    @AppStorage("explore.ai.picks.v1") private var autoPicks = true
    @EnvironmentObject private var appStore: AppStore
    @ObservedObject var store: ExploreStore
    @Environment(\.dismiss) private var dismiss
    @State private var sheet: ManageSheet?
    @State private var pickingNow = false
    @State private var pickMessage: String?

    private enum ManageSheet: Identifiable {
        case add(session: String)
        case edit(ExploreBoard)

        var id: String {
            switch self {
            case .add(let session): return "add-" + session
            case .edit(let board): return "edit-" + board.id
            }
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if store.boards.isEmpty {
                    Text("还没有板块。点右上角 + 添加一个。")
                        .appFont(.footnote)
                        .foregroundStyle(palette.secondary)
                        .independentGlassRow()
                } else {
                    Section {
                        ForEach(store.boards) { board in
                            Button {
                                sheet = .edit(board)
                            } label: {
                                row(board)
                            }
                            .buttonStyle(.plain)
                            .independentGlassRow()
                        }
                        .onMove { store.move(from: $0, to: $1) }
                        .onDelete { store.remove(at: $0) }
                    } footer: {
                        Text("点一行编辑；右上角「编辑」可拖动排序或删除。")
                            .appFont(.caption)
                            .foregroundStyle(palette.secondary)
                    }
                }
                Section {
                    Toggle(isOn: $autoPicks) {
                        Text("按阅读记录自动推荐").appFont(.body)
                    }
                    .accessibilityIdentifier("explore.ai.autoPicks")
                    Text(AIExploreAutoRefresh.picksStatusText())
                        .appFont(.caption)
                        .foregroundStyle(palette.secondary)

                    Button { pickNow() } label: {
                        HStack(spacing: 8) {
                            if pickingNow { ProgressView().controlSize(.small) }
                            Text(pickingNow ? "正在推荐…" : "立即换一批")
                                .appFont(.body)
                        }
                    }
                    .disabled(pickingNow)
                    .accessibilityIdentifier("explore.ai.pickNow")
                    if let pickMessage {
                        Text(pickMessage)
                            .appFont(.caption)
                            .foregroundStyle(palette.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } header: {
                    Text("AI 推荐")
                } footer: {
                    Text("读你最近在读的书，提取分类与标签，去各书源搜相似的书，再让 AI 挑出最像的，生成置顶的「为你推荐」板块。下拉刷新可以随时换一批。")
                        .appFont(.caption)
                }

                Section {
                    Toggle(isOn: $autoRefresh) {
                        Text("自动生成推荐语").appFont(.body)
                    }
                    .accessibilityIdentifier("explore.ai.auto")
                    Text(AIExploreAutoRefresh.statusText())
                        .appFont(.caption)
                        .foregroundStyle(palette.secondary)
                } header: {
                    Text("AI 文案")
                } footer: {
                    Text("打开探索页时，给还没有推荐语的书补一批（每次最多 \(AIRecommender.maxBooks) 本）。需要先在「我的 → AI 提供商」配置服务。")
                        .appFont(.caption)
                }
            }
            .scrollContentBackground(.hidden)
            .background { AppThemeCanvas().ignoresSafeArea() }
            .navigationTitle("探索板块")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { sheet = .add(session: UUID().uuidString) } label: { Image(systemName: "plus") }
                        .accessibilityIdentifier("explore.manage.add")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .sheet(item: $sheet) { item in
                switch item {
                case .add(let session):
                    ExploreBoardEditor(board: nil) { store.add($0) }
                        .id(session)
                        .environmentObject(appStore)
                case .edit(let board):
                    ExploreBoardEditor(board: board) { store.update($0.first ?? board) }
                        .environmentObject(appStore)
                }
            }
        }
        .accessibilityIdentifier("explore.manage.page")
    }

    /// 手动换一批推荐，不等冷却。
    private func pickNow() {
        let ai = AIServiceStore.shared
        guard let config = ai.activeConfig,
              let provider = AICatalog.provider(for: config),
              let key = ai.apiKey(for: config.id) else {
            pickMessage = "先在「我的 → AI 提供商」配置并启用一个服务。"
            return
        }
        pickingNow = true
        pickMessage = nil
        var excluding = Set(appStore.books.map(\.bookUrl))
        if let board = store.boards.first(where: { $0.id == AIRecommendation.boardID }) {
            excluding.formUnion((board.pinnedBooks ?? []).map(\.bookUrl))
        }
        Task {
            do {
                let outcome = try await AIRecommendation.recommend(
                    shelf: appStore.books, sources: appStore.sources,
                    excluding: excluding, provider: provider, config: config, apiKey: key)
                let board = ExploreBoard(
                    id: AIRecommendation.boardID,
                    title: AIRecommendation.boardTitle,
                    subtitle: outcome.subtitle,
                    layout: .forYou,
                    categories: [],
                    count: AIRecommendation.targetCount,
                    pinnedBooks: outcome.books)
                store.upsert(board, atFront: true)
                AIExploreAutoRefresh.picksLastRun = Date()
                pickMessage = "已推荐 \(outcome.books.count) 本。"
            } catch {
                pickMessage = error.localizedDescription
            }
            pickingNow = false
        }
    }

    private func row(_ board: ExploreBoard) -> some View {
        HStack(spacing: 12) {
            Image(systemName: board.layout.symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(palette.secondary)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(board.displayTitle)
                    .appFont(.system(size: 16, weight: .medium))
                    .foregroundStyle(palette.primary)
                    .lineLimit(1)
                Text(detail(board))
                    .appFont(.system(size: 11.5))
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(palette.secondary)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 2)
    }

    private func detail(_ board: ExploreBoard) -> String {
        let sourceNames = board.visibleCategories.compactMap { category in
            appStore.source(for: category.sourceURL)?.bookSourceName
        }
        let sourceText = Array(Set(sourceNames)).sorted().joined(separator: "、")
        let count = board.visibleCategories.count
        return [board.layout.title, sourceText, "\(count) 个分类"].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

// MARK: - 导入标签 / 推荐语（AI 接入点）

/// 外部（AI）生成的标签与推荐语的粘贴入口。
/// 只写本机文件，不上传；格式见 `ExploreMetaStore`。
struct ExploreMetaImportSheet: View {
    @ThemePalette private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var message: String?
    @State private var failed = false
    var onImported: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextEditor(text: $text)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(minHeight: 220)
                        .accessibilityIdentifier("explore.meta.text")
                } header: {
                    Text("JSON")
                } footer: {
                    Text("格式：{\"书籍地址\": {\"tags\": [\"求生游戏\", \"悬疑流\"], \"reason\": \"这本「都市」佳作与你的匹配度高达 87%！\"}}\n也可以只写 {\"书籍地址\": [\"标签\", \"标签\"]}。")
                        .appFont(.caption)
                }
                if let message {
                    Section {
                        Text(message)
                            .appFont(.footnote)
                            .foregroundStyle(failed ? Color.red : palette.secondary)
                    }
                }
                Section {
                    Text("写入 Application Support/LegadoReading/explore-meta.json，卡片上的标签与「猜你喜欢」的推荐语会立即跟着变。")
                        .appFont(.caption)
                        .foregroundStyle(palette.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background { AppThemeCanvas().ignoresSafeArea() }
            .navigationTitle("导入标签 / 推荐语")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("导入") { importJSON() }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .accessibilityIdentifier("explore.meta.page")
    }

    private func importJSON() {
        do {
            let count = try ExploreMetaStore.merge(json: text)
            failed = false
            message = "已写入 \(count) 本书。"
            onImported()
        } catch {
            failed = true
            message = error.localizedDescription
        }
    }
}
