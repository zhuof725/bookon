import SwiftUI

/// 选书源 → 在该书源里选分类。用于添加板块。
struct SourceAndCategoryPicker: View {
    @ThemePalette private var palette
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    let template: DiscoverTemplateKind
    var onConfirm: ([CustomDiscoverEntry]) -> Void

    @State private var selectedSource: BookSource?
    @State private var kinds: [SourceDiagnostics.ExploreKind] = []
    @State private var loading = false
    @State private var errorText: String?
    @State private var picked: Set<String> = []
    @State private var staged: [CustomDiscoverEntry] = []

    private var sources: [BookSource] { DiscoverCatalog.explorableSources(store.sources) }

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
                    Button(confirmTitle) { confirm() }
                        .fontWeight(.semibold)
                        .disabled(staged.isEmpty && picked.isEmpty)
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
            .background { AppThemeCanvas().ignoresSafeArea() }
        }
    }

    private var confirmTitle: String {
        let total = staged.count + picked.count
        return total > 0 ? "添加 \(total) 个" : "完成"
    }

    private var sourceList: some View {
        List {
            if !staged.isEmpty {
                Section {
                    ForEach(staged) { entry in
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(palette.accent)
                            Text(entry.boardTitle).lineLimit(1)
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets.sorted(by: >) where staged.indices.contains(index) {
                            staged.remove(at: index)
                        }
                    }
                } header: {
                    Text("已选 \(staged.count) 个")
                }
            }

            Section {
                if sources.isEmpty {
                    Text("没有可用的书源。需要书源启用、启用发现、并填写了发现地址。")
                        .appFont(.footnote).foregroundStyle(palette.secondary)
                } else {
                    ForEach(sources) { source in
                        Button { open(source) } label: {
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
            } header: {
                Text("选择书源")
            }
        }
        .scrollContentBackground(.hidden)
        .foregroundStyle(palette.primary)
    }

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
                    .appFont(.footnote).foregroundStyle(palette.secondary)
            } else {
                Section {
                    ForEach(selectableKinds, id: \.self) { item in
                        Button {
                            let url = item.url ?? ""
                            if picked.contains(url) { picked.remove(url) } else { picked.insert(url) }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: picked.contains(item.url ?? "") ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 17))
                                    .foregroundStyle(picked.contains(item.url ?? "") ? palette.accent
                                                     : palette.secondary.opacity(0.4))
                                Text(item.title).appFont(.body).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 1)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("选分类")
                } footer: {
                    Text("用「\(template.title)」渲染。可以切回上一级再挑别的书源，已选的会累积。")
                }

                if !picked.isEmpty {
                    Section {
                        Button("先记下这 \(picked.count) 个，再选别的书源") {
                            staged += makeEntries(source: source)
                            picked = []
                            selectedSource = nil
                            kinds = []
                        }
                        .appFont(.body.weight(.semibold))
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .foregroundStyle(palette.primary)
        .task(id: source.bookSourceUrl) { await load(source) }
    }

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

    private func makeEntries(source: BookSource) -> [CustomDiscoverEntry] {
        selectableKinds
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
    }

    private func confirm() {
        var all = staged
        if let source = selectedSource, !picked.isEmpty {
            all += makeEntries(source: source)
        }
        if !all.isEmpty { onConfirm(all) }
        dismiss()
    }
}
