import SwiftUI

/// 添加板块：**一页搞定**。
///
/// 从上到下：模板列表（左图右文，带封面预览）→ 书源 → 分类 → 添加按钮。
/// 点加号 push 进这一页，不弹窗、不套娃，选完直接添加。
struct AddBoardPage: View {
    @ThemePalette private var palette
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore

    /// 添加成功回调（由编辑页写入草稿）
    var onAdd: ([CustomDiscoverEntry]) -> Void

    @State private var template: DiscoverTemplateKind = .deck
    @State private var sourceUrl: String = ""
    @State private var kinds: [SourceDiagnostics.ExploreKind] = []
    @State private var kindsLoading = false
    @State private var kindsError: String?
    @State private var picked: Set<String> = []
    /// 切换书源/分类时给一点淡入，避免内容「啪」地跳出来
    @State private var contentVisible = false

    private var sources: [BookSource] { DiscoverCatalog.explorableSources(store.sources) }

    private var selectedSource: BookSource? {
        sources.first { $0.bookSourceUrl == sourceUrl }
    }

    private var selectableKinds: [SourceDiagnostics.ExploreKind] {
        kinds.filter { kind in
            guard (kind.type ?? "").isEmpty else { return false }
            guard let url = kind.url, !url.isEmpty else { return false }
            return !DiscoverCatalog.isDecorativeControlTitle(kind.title)
        }
    }

    private var canAdd: Bool {
        template.dataSource == .readingProgress || !picked.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                templateSection
                if template.dataSource == .bookList {
                    sourceSection
                    kindSection
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 120)
        }
        .background { AppThemeCanvas().ignoresSafeArea() }
        .foregroundStyle(palette.primary)
        .navigationTitle("添加板块")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            addBar
        }
        .task { await preloadFirstSource() }
    }

    // MARK: 模板（左图右文）

    private var templateSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("选择模板")

            VStack(spacing: 10) {
                ForEach(DiscoverTemplate.all) { item in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { template = item.kind }
                    } label: {
                        HStack(spacing: 12) {
                            // 左：缩略预览
                            DiscoverTemplateThumbnail(kind: item.kind)
                                .frame(width: 104, height: 78)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .strokeBorder(
                                            template == item.kind ? palette.accent : .clear,
                                            lineWidth: 1.5
                                        )
                                }

                            // 右：名称与说明
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title)
                                    .appFont(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(palette.primary)
                                Text(item.detail)
                                    .appFont(.system(size: 11.5))
                                    .foregroundStyle(palette.secondary)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)

                            if template == item.kind {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 17))
                                    .foregroundStyle(palette.accent)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .padding(9)
                        .background {
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(template == item.kind
                                      ? palette.accent.opacity(0.07)
                                      : palette.primary.opacity(0.028))
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("add.template.\(item.kind.rawValue)")
                }
            }
        }
    }

    // MARK: 书源

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("选择书源")

            if sources.isEmpty {
                Text("没有可用的书源。需要书源启用、启用发现、并填写了发现地址。")
                    .appFont(.system(size: 12))
                    .foregroundStyle(palette.secondary)
            } else {
                Menu {
                    ForEach(sources) { source in
                        Button {
                            switchSource(source)
                        } label: {
                            if sourceUrl == source.bookSourceUrl {
                                Label(source.bookSourceName, systemImage: "checkmark")
                            } else {
                                Text(source.bookSourceName)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "square.stack.3d.up")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(palette.accent)
                        Text(selectedSource?.bookSourceName ?? "点这里选书源")
                            .appFont(.system(size: 15, weight: selectedSource == nil ? .regular : .semibold))
                            .foregroundStyle(selectedSource == nil ? palette.secondary : palette.primary)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.secondary)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 48)
                    .background {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(palette.primary.opacity(0.045))
                    }
                }
                .accessibilityIdentifier("add.sourceMenu")
            }
        }
    }

    // MARK: 分类

    private var kindSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                sectionTitle("选择分类")
                if kindsLoading {
                    ProgressView().controlSize(.mini)
                        .transition(.opacity)
                }
                Spacer(minLength: 0)
                if !picked.isEmpty {
                    Text("已选 \(picked.count)")
                        .appFont(.system(size: 11.5))
                        .foregroundStyle(palette.accent)
                }
            }

            if sourceUrl.isEmpty {
                hintRow("先选一个书源")
            } else if let kindsError {
                VStack(alignment: .leading, spacing: 8) {
                    Text(kindsError)
                        .appFont(.system(size: 12))
                        .foregroundStyle(palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("重试") { Task { await loadKinds(force: true) } }
                        .appFont(.system(size: 12, weight: .semibold))
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(palette.primary.opacity(0.035))
                }
            } else if selectableKinds.isEmpty && !kindsLoading {
                hintRow("这个书源没有可用的发现分类")
            } else {
                // 骨架 + 真实列表：加载中用骨架占位，避免空白跳变
                VStack(spacing: 8) {
                    if kindsLoading && selectableKinds.isEmpty {
                        ForEach(0..<4, id: \.self) { _ in kindSkeleton }
                    } else {
                        ForEach(selectableKinds, id: \.self) { item in
                            kindRow(item)
                        }
                    }
                }
                .opacity(contentVisible ? 1 : 0)
                .animation(.easeOut(duration: 0.22), value: contentVisible)
            }
        }
    }

    private func kindRow(_ item: SourceDiagnostics.ExploreKind) -> some View {
        let url = item.url ?? ""
        let on = picked.contains(url)
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                if on { picked.remove(url) } else { picked.insert(url) }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(on ? palette.accent : palette.secondary.opacity(0.35))
                    .transition(.scale.combined(with: .opacity))
                Text(item.title)
                    .appFont(.system(size: 14))
                    .foregroundStyle(palette.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(on ? palette.accent.opacity(0.08) : palette.primary.opacity(0.028))
            }
        }
        .buttonStyle(.plain)
    }

    /// 加载占位：灰条呼吸，比纯转圈更能提示「这里有内容要出现」。
    private var kindSkeleton: some View {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(palette.primary.opacity(0.05))
            .frame(height: 44)
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(palette.primary.opacity(0.07))
                    .frame(width: 72, height: 11)
                    .padding(.leading, 40)
            }
            .redacted(reason: .placeholder)
    }

    private func hintRow(_ text: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "info.circle")
                .font(.system(size: 12))
            Text(text).appFont(.system(size: 12))
        }
        .foregroundStyle(palette.secondary)
        .padding(.horizontal, 14)
        .frame(height: 44)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(palette.primary.opacity(0.028))
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .appFont(.system(size: 13, weight: .semibold))
            .foregroundStyle(palette.secondary)
    }

    // MARK: 底部添加

    private var addBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(palette.primary.opacity(0.06))
                .frame(height: 0.5)
            Button {
                add()
            } label: {
                Text(addTitle)
                    .appFont(.system(size: 16, weight: .semibold))
                    .foregroundStyle(canAdd ? palette.onAccent : palette.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(canAdd ? palette.accent : palette.primary.opacity(0.07))
                    }
            }
            .buttonStyle(.plain)
            .disabled(!canAdd)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .animation(.easeInOut(duration: 0.18), value: canAdd)
        }
        .background(.ultraThinMaterial)
    }

    private var addTitle: String {
        if template.dataSource == .readingProgress { return "添加「继续阅读」" }
        let n = picked.count
        return n > 0 ? "添加 \(n) 个板块" : "添加"
    }

    // MARK: 动作

    private func switchSource(_ source: BookSource) {
        guard sourceUrl != source.bookSourceUrl else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            sourceUrl = source.bookSourceUrl
            kinds = []
            picked = []
            kindsError = nil
            contentVisible = false
        }
        Task { await loadKinds(force: true) }
    }

    private func preloadFirstSource() async {
        guard sourceUrl.isEmpty, let first = sources.first else { return }
        sourceUrl = first.bookSourceUrl
        await loadKinds()
    }

    private func loadKinds(force: Bool = false) async {
        guard let source = selectedSource else { return }
        if !force, !kinds.isEmpty {
            contentVisible = true
            return
        }
        if let cached = DiscoverKindsCache.cached(source: source.bookSourceUrl), !cached.isEmpty {
            kinds = cached
            kindsLoading = false
            contentVisible = true
            return
        }
        withAnimation(.easeInOut(duration: 0.15)) { kindsLoading = true }
        kindsError = nil
        defer { kindsLoading = false }

        let result = await Task.detached(priority: .userInitiated) {
            SourceDiagnostics.exploreKinds(source: source)
        }.value

        // 只接受当前书源的结果：快速切源时旧请求可能晚到
        guard sourceUrl == source.bookSourceUrl else { return }
        kinds = result
        if let err = DiscoverCatalog.kindError(result) {
            kindsError = err
        } else if !result.isEmpty {
            DiscoverKindsCache.store(source: source.bookSourceUrl, kinds: result)
        }
        withAnimation(.easeOut(duration: 0.22)) { contentVisible = true }
    }

    private func add() {
        if template.dataSource == .readingProgress {
            onAdd([CustomDiscoverEntry(
                sourceUrl: "",
                sourceName: "书架",
                kindTitle: "继续阅读",
                kindUrl: "history://shelf",
                template: .history,
                count: DiscoverTemplate.template(for: .history).defaultCount
            )])
            dismiss()
            return
        }
        guard let source = selectedSource else { return }
        let entries = selectableKinds
            .filter { picked.contains($0.url ?? "") }
            .map { item in
                CustomDiscoverEntry(
                    sourceUrl: source.bookSourceUrl,
                    sourceName: source.bookSourceName,
                    kindTitle: item.title,
                    kindUrl: item.url ?? "",
                    template: template,
                    count: DiscoverTemplate.template(for: template).defaultCount
                )
            }
        guard !entries.isEmpty else { return }
        onAdd(entries)
        dismiss()
    }
}
