import SwiftUI

extension AppCacheCategory {
    var title: String {
        switch self {
        case .content: return "在线正文缓存"
        case .catalog: return "在线目录缓存"
        case .network: return "网络响应缓存"
        case .all: return "全部可管理缓存"
        }
    }
    var explanation: String {
        switch self {
        case .content: return "已下载和预读的在线章节。清理后再次阅读需要联网，不影响本地 TXT / EPUB。"
        case .catalog: return "书源书籍的目录副本。清理后进入书籍时重新获取，不影响本地书籍目录。"
        case .network: return "系统 URLCache 保存的网络响应，可能包含远程图片。不会清除 Cookie 或网页登录信息。"
        case .all: return "清理在线正文、在线目录和系统网络响应缓存。之后可能需要联网重新加载。"
        }
    }
    var symbol: String {
        switch self {
        case .content: return "doc.text"
        case .catalog: return "list.bullet.rectangle"
        case .network: return "network"
        case .all: return "trash"
        }
    }
}

@MainActor
final class CacheManagementModel: ObservableObject {
    @Published private(set) var snapshot = AppCacheSnapshot.empty
    @Published private(set) var busy = false
    @Published private(set) var hasScanned = false
    @Published private(set) var result: AppCacheClearResult?
    private let service: AppCacheService

    init(service: AppCacheService) { self.service = service }
    func refresh() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        snapshot = await service.snapshot()
        hasScanned = true
    }
    func clear(_ category: AppCacheCategory) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        let outcome = await service.clear(category)
        result = outcome
        snapshot = outcome.snapshot
        hasScanned = true
    }
}

@MainActor
struct CacheManagementView: View {
    @ThemePalette private var palette
    @StateObject private var model: CacheManagementModel
    @Environment(\.dismiss) private var dismiss
    @State private var pending: AppCacheCategory = .all
    @State private var showingConfirmation = false

    init(service: AppCacheService = .shared) {
        _model = StateObject(wrappedValue: CacheManagementModel(service: service))
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 21, weight: .medium))
                        .frame(width: 46, height: 46).modifier(ShelfGlass(shape: Circle()))
                }.accessibilityLabel("返回").accessibilityIdentifier("cache.back")
                Spacer()
                Text("缓存管理").appFont(.headline)
                Spacer()
                Button { Task { await model.refresh() } } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 19, weight: .medium))
                        .frame(width: 46, height: 46).modifier(ShelfGlass(shape: Circle()))
                }.disabled(model.busy).accessibilityLabel("刷新缓存占用").accessibilityIdentifier("cache.refresh")
            }.buttonStyle(.plain).padding(.horizontal, 18).padding(.top, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("可管理缓存 · 磁盘").appFont(.subheadline).foregroundStyle(palette.secondary)
                        Text(model.hasScanned ? bytes(model.snapshot.diskBytes) : "正在统计…")
                            .appFont(.system(size: 30, weight: .semibold))
                            .accessibilityIdentifier("cache.total")
                        Text("网络内存缓存：\(bytes(model.snapshot.networkMemoryBytes))")
                            .appFont(.footnote).foregroundStyle(palette.secondary)
                        if model.busy { ProgressView("正在处理…").appFont(.footnote).accessibilityIdentifier("cache.busy") }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
                        .appGlass(in: RoundedRectangle(cornerRadius: 22), tint: palette.surface)
                    ForEach([AppCacheCategory.content, .catalog, .network]) { category in
                        categoryCard(category)
                    }
                    Button { requestClear(.all) } label: {
                        Label("清理全部可管理缓存", systemImage: "trash")
                            .appFont(.body.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 50)
                            .appGlass(in: Capsule(), tint: palette.selection)
                    }.buttonStyle(.plain).disabled(model.busy || !model.hasScanned)
                        .accessibilityIdentifier("cache.clear.all")
                    if let outcome = model.result {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(outcome.failures.isEmpty ? "\(outcome.category.title)清理完成" : "部分缓存未能清理")
                                .appFont(.headline)
                            Text("已删除 \(outcome.removedFiles) 个缓存文件（\(bytes(outcome.removedBytes))），上方为重新统计的占用。")
                                .appFont(.footnote)
                            if outcome.category == .network || outcome.category == .all {
                                Text("已请求系统清理网络响应缓存；此项不计入文件删除数量。").appFont(.footnote)
                            }
                            ForEach(Array(outcome.failures.enumerated()), id: \.offset) { _, message in
                                Text(message).appFont(.footnote).foregroundStyle(.red)
                            }
                        }.accessibilityElement(children: .combine).accessibilityIdentifier("cache.result")
                    }
                    ForEach(Array(model.snapshot.warnings.enumerated()), id: \.offset) { _, message in
                        Text(message).appFont(.footnote).foregroundStyle(palette.secondary)
                    }
                    Text("不会删除本地书籍、EPUB 封面、导入字体、书源、登录信息、阅读进度、规则或搜索历史。")
                        .appFont(.footnote).foregroundStyle(palette.secondary)
                    Text("只统计本页列出的缓存，文件大小为逻辑字节数，网络占用由系统报告。不包含全部网页缓存或当前屏幕持有的图片与排版。阅读和网络请求会再次生成缓存。")
                        .appFont(.footnote).foregroundStyle(palette.secondary)
                }.padding(.horizontal, 18).padding(.bottom, 28)
            }
        }
        .background { AppThemeCanvas().ignoresSafeArea() }
        .foregroundStyle(palette.primary)
        .toolbar(.hidden, for: .navigationBar)
        .modifier(MonochromeAppStyle()).modifier(AppTypographyRoot())
        .task { await model.refresh() }
        .confirmationDialog("清理\(pending.title)？", isPresented: $showingConfirmation, titleVisibility: .visible) {
            Button("确认清理", role: .destructive) {
                let category = pending
                Task { await model.clear(category) }
            }.accessibilityIdentifier("cache.confirm")
            Button("取消", role: .cancel) {}
        } message: { Text(pending.explanation + "\n本地书籍及个人数据不会删除。") }
    }

    private func categoryCard(_ category: AppCacheCategory) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(category.title, systemImage: category.symbol).appFont(.headline)
                Spacer()
                Text(model.hasScanned ? bytes(diskBytes(category)) : "—").appFont(.subheadline)
                    .accessibilityIdentifier("cache.size." + category.rawValue)
            }
            Text(category.explanation).appFont(.footnote).foregroundStyle(palette.secondary)
            if category == .content {
                Text("\(model.snapshot.contentFiles) 个文件 · \(model.snapshot.contentMemoryEntries) 条内存正文")
                    .appFont(.caption).foregroundStyle(palette.secondary).accessibilityIdentifier("cache.count.content")
            } else if category == .catalog {
                Text("\(model.snapshot.catalogFiles) 个文件").appFont(.caption).foregroundStyle(palette.secondary)
                    .accessibilityIdentifier("cache.count.catalog")
            }
            Button("清理") { requestClear(category) }.appFont(.body)
                .frame(minHeight: 44).disabled(model.busy || !model.hasScanned)
                .accessibilityLabel("清理" + category.title).accessibilityIdentifier("cache.clear." + category.rawValue)
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .appGlass(in: RoundedRectangle(cornerRadius: 22), tint: palette.surface)
    }
    private func requestClear(_ category: AppCacheCategory) { pending = category; showingConfirmation = true }
    private func diskBytes(_ category: AppCacheCategory) -> Int64 {
        switch category {
        case .content: return model.snapshot.contentBytes
        case .catalog: return model.snapshot.catalogBytes
        case .network: return model.snapshot.networkDiskBytes
        case .all: return model.snapshot.diskBytes
        }
    }
    private func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(0, value), countStyle: .file)
    }
}
