import SwiftUI

/// 网络设置页：并发、封面并发、搜索结果缓存、换源时加载目录。
struct NetworkSettingsView: View {
    @ThemePalette private var palette

    @State private var concurrency = NetworkSettings.concurrency
    @State private var coverConcurrency = NetworkSettings.coverConcurrency
    @State private var cacheDays = NetworkSettings.searchCacheDays
    @State private var loadToc = NetworkSettings.loadTocOnSourceSwitch
    @State private var cacheBytes = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                card("并发数", detail: "搜索、缓存、下载、校验等网络请求的并发数，建议 16 个。") {
                    stepperRow(value: concurrency, range: NetworkSettings.concurrencyRange,
                               id: "network.concurrency") { value in
                        concurrency = value
                        NetworkSettings.concurrency = value
                    }
                }

                card("封面并发数", detail: "同时下载的封面上限，数字越低滚动越不容易发热，但封面出现得慢一些。") {
                    Picker("封面并发数", selection: Binding(
                        get: { coverConcurrency },
                        set: { value in
                            coverConcurrency = value
                            NetworkSettings.coverConcurrency = value
                            NetworkSettings.applyCoverLimit()
                        })) {
                        ForEach(NetworkSettings.coverOptions, id: \.self) { value in
                            Text(value == 0 ? "不限制" : "\(value) 个").tag(value)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(palette.accent)
                    .accessibilityIdentifier("network.cover")
                }

                card("搜索结果缓存天数", detail: "搜索时启用缓存，避免重复搜索；0 表示不缓存。") {
                    stepperRow(value: cacheDays, range: NetworkSettings.cacheDaysRange,
                               id: "network.searchCacheDays") { value in
                        cacheDays = value
                        NetworkSettings.searchCacheDays = value
                        refreshCacheBytes()
                    }
                    Text("当前占用 \(ByteCountFormatter.string(fromByteCount: Int64(cacheBytes), countStyle: .file))")
                        .appFont(.caption).foregroundStyle(palette.secondary)
                    Button {
                        SearchResultCache.clear()
                        refreshCacheBytes()
                    } label: {
                        Label("清空搜索缓存", systemImage: "trash")
                            .appFont(.subheadline)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(palette.accent)
                    .accessibilityIdentifier("network.clearSearchCache")
                }

                card("换源时加载目录", detail: "换源搜索时同时获取每个来源的目录，点选后立刻能看到章节；搜索期间的网络请求会增加一倍。") {
                    Toggle(isOn: Binding(get: { loadToc }, set: { value in
                        loadToc = value
                        NetworkSettings.loadTocOnSourceSwitch = value
                    })) {
                        Text("换源时加载目录").appFont(.body)
                    }
                    .tint(palette.accent)
                    .accessibilityIdentifier("network.loadToc")
                }
            }
            .padding(16)
        }
        .background { AppThemeCanvas().ignoresSafeArea() }
        .navigationTitle("网络设置")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            NetworkSettings.applyCoverLimit()
            refreshCacheBytes()
        }
    }

    private func refreshCacheBytes() {
        cacheBytes = SearchResultCache.diskBytes
    }

    @ViewBuilder
    private func card<Content: View>(_ title: String, detail: String,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).appFont(.headline)
            content()
            Text(detail).appFont(.footnote).foregroundStyle(palette.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(SettingsGlassSurface())
    }

    private func stepperRow(value: Int, range: ClosedRange<Int>, id: String,
                            onChange: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 12) {
            Text("\(value)")
                .appFont(.title3)
                .monospacedDigit()
                .frame(minWidth: 44, alignment: .leading)
            Spacer(minLength: 8)
            HStack(spacing: 0) {
                stepButton(symbol: "minus", enabled: value > range.lowerBound) {
                    onChange(max(range.lowerBound, value - 1))
                }
                Divider().frame(height: 22)
                stepButton(symbol: "plus", enabled: value < range.upperBound) {
                    onChange(min(range.upperBound, value + 1))
                }
            }
            .background {
                Capsule().fill(palette.primary.opacity(0.08))
            }
        }
        .accessibilityIdentifier(id)
    }

    private func stepButton(symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 46, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
    }
}
