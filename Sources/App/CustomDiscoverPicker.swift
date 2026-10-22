import SwiftUI

/// 从书源的发现分类里挑板块：先选书源，再勾分类。
struct CustomDiscoverPicker: View {
    @ThemePalette private var palette
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    /// 确认后回传勾选结果
    var onConfirm: ([CustomDiscoverEntry]) -> Void

    @State private var selectedSource: BookSource?
    @State private var kinds: [SourceDiagnostics.ExploreKind] = []
    @State private var loading = false
    @State private var errorText: String?
    @State private var picked: Set<String> = []

    private var sources: [BookSource] {
        DiscoverCatalog.explorableSources(store.sources)
    }

    /// 只列能构成板块的分类：没有控件类型、有地址、不是装饰横幅。
    private var selectableKinds: [SourceDiagnostics.ExploreKind] {
        kinds.filter { kind in
            guard (kind.type ?? "").isEmpty else { return false }
            guard let url = kind.url, !url.isEmpty else { return false }
            return !DiscoverCatalog.isDecorativeControlTitle(kind.title)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let source = selectedSource {
                    kindList(source)
                } else {
                    sourceList
                }
            }
            .navigationTitle(selectedSource?.bookSourceName ?? "选择书源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { confirm() }
                        .fontWeight(.semibold)
                        .disabled(picked.isEmpty)
                }
                if selectedSource != nil {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            selectedSource = nil
                            kinds = []
                            picked = []
                        } label: {
                            Image(systemName: "chevron.left")
                        }
                    }
                }
            }
        }
        .background { AppThemeCanvas().ignoresSafeArea() }
    }

    // MARK: 一级：书源

    private var sourceList: some View {
        List {
            if sources.isEmpty {
                Text("没有可用的书源。需要书源启用、启用发现、并填写了发现地址。")
                    .appFont(.footnote)
                    .foregroundStyle(palette.secondary)
            } else {
                ForEach(sources) { source in
                    Button {
                        open(source)
                    } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(source.bookSourceName).appFont(.headline).lineLimit(1)
                                Text(DiscoverCatalog.cardSubtitle(source))
                                    .appFont(.caption)
                                    .foregroundStyle(palette.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(palette.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .foregroundStyle(palette.primary)
        .background { AppThemeCanvas().ignoresSafeArea() }
    }

    // MARK: 二级：分类

    private func kindList(_ source: BookSource) -> some View {
        List {
            if loading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在读取发现分类…").appFont(.footnote).foregroundStyle(palette.secondary)
                }
            } else if let errorText {
                VStack(alignment: .leading, spacing: 6) {
                    Text(errorText).appFont(.footnote).foregroundStyle(palette.secondary)
                    Button("重试") { Task { await load(source) } }
                        .appFont(.footnote.weight(.semibold))
                }
            } else if selectableKinds.isEmpty {
                Text("这个书源没有可用的发现分类。")
                    .appFont(.footnote)
                    .foregroundStyle(palette.secondary)
            } else {
                ForEach(selectableKinds, id: \.self) { kind in
                    Button {
                        let url = kind.url ?? ""
                        if picked.contains(url) { picked.remove(url) } else { picked.insert(url) }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: picked.contains(kind.url ?? "") ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 17))
                                .foregroundStyle(picked.contains(kind.url ?? "") ? palette.accent : palette.secondary.opacity(0.4))
                            Text(kind.title).appFont(.body).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 1)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .foregroundStyle(palette.primary)
        .background { AppThemeCanvas().ignoresSafeArea() }
        .task(id: source.bookSourceUrl) { await load(source) }
    }

    // MARK: 动作

    private func open(_ source: BookSource) {
        selectedSource = source
        picked = []
        Task { await load(source) }
    }

    private func load(_ source: BookSource) async {
        if !kinds.isEmpty { return }
        loading = true
        errorText = nil
        if let cached = DiscoverKindsCache.cached(source: source.bookSourceUrl) {
            kinds = cached
            loading = false
            return
        }
        let result = await Task.detached(priority: .userInitiated) {
            SourceDiagnostics.exploreKinds(source: source)
        }.value
        kinds = result
        loading = false
        if let err = DiscoverCatalog.kindError(result) {
            errorText = err
        } else if !result.isEmpty {
            DiscoverKindsCache.store(source: source.bookSourceUrl, kinds: result)
        }
    }

    private func confirm() {
        guard let source = selectedSource else { dismiss(); return }
        // 新加的板块默认用卡片堆叠 + 20 条，之后再在编辑页改
        let entries = selectableKinds
            .filter { picked.contains($0.url ?? "") }
            .map { kind in
                CustomDiscoverEntry(
                    sourceUrl: source.bookSourceUrl,
                    sourceName: source.bookSourceName,
                    kindTitle: kind.title,
                    kindUrl: kind.url ?? "",
                    template: .deck,
                    count: DiscoverTemplate.countCeiling
                )
            }
        onConfirm(entries)
    }
}
