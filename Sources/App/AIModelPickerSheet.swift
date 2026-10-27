import SwiftUI

/// 模型选择器：搜索 + 列表，来自服务商 `/models` 接口或本地缓存。
struct AIModelPickerSheet: View {
    @ThemePalette private var palette
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var store: AIServiceStore
    let serviceID: String
    let current: String
    let providerName: String
    var onPick: (String) -> Void
    var onRefresh: (() async -> Void)? = nil

    @State private var query = ""
    @State private var refreshing = false

    private var models: [AIModelSummary] { store.cachedModels(for: serviceID) }

    private var filtered: [AIModelSummary] {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !keyword.isEmpty else { return models }
        return models.filter {
            $0.id.lowercased().contains(keyword) || $0.displayName.lowercased().contains(keyword)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if filtered.isEmpty {
                    Text(models.isEmpty ? "还没有拿到模型列表，点右上角刷新。" : "没有匹配的模型。")
                        .appFont(.footnote).foregroundStyle(palette.secondary)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(filtered) { model in
                        Button { onPick(model.id); dismiss() } label: {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(model.displayName)
                                        .appFont(.body)
                                        .foregroundStyle(palette.primary)
                                        .lineLimit(1)
                                    if model.displayName != model.id {
                                        Text(model.id)
                                            .appFont(.system(size: 11, design: .monospaced))
                                            .foregroundStyle(palette.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer(minLength: 4)
                                if model.id == current {
                                    Image(systemName: "checkmark").foregroundStyle(palette.accent)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background { AppThemeCanvas().ignoresSafeArea() }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索模型")
            .navigationTitle(providerName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        guard let onRefresh else { return }
                        refreshing = true
                        Task {
                            await onRefresh()
                            refreshing = false
                        }
                    } label: {
                        if refreshing {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(refreshing || onRefresh == nil)
                    .accessibilityLabel("刷新模型列表")
                    .accessibilityIdentifier("ai.models.refresh")
                }
            }
        }
        .accessibilityIdentifier("ai.models.page")
    }
}
