import SwiftUI

/// 自定义发现配置：选书源分类、给每条挑模板、调数量、排序。
struct CustomDiscoverSettingsView: View {
    @ThemePalette private var palette
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var model: DiscoverBoardStore

    @State private var draft = CustomDiscoverConfig()
    @State private var showPicker = false
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            List {
                carouselSection
                entriesSection
            }
            .scrollContentBackground(.hidden)
            .foregroundStyle(palette.primary)
            .background { AppThemeCanvas().ignoresSafeArea() }
            .navigationTitle("自定义发现")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { save() }
                        .fontWeight(.semibold)
                }
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        showPicker = true
                    } label: {
                        Label("添加板块", systemImage: "plus.circle.fill")
                    }
                }
            }
            .sheet(isPresented: $showPicker) {
                CustomDiscoverPicker { picked in
                    for entry in picked { draft.upsert(entry) }
                    showPicker = false
                }
                .environmentObject(store)
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                draft = model.config
            }
        }
    }

    // MARK: 轮播

    private var carouselSection: some View {
        Section {
            NavigationLink {
                CarouselSourcePicker(config: $draft)
                    .environmentObject(store)
            } label: {
                HStack {
                    Label("顶部轮播", systemImage: "rectangle.stack")
                    Spacer()
                    Text(carouselSummary).foregroundStyle(palette.secondary)
                }
            }
        } header: {
            Text("轮播")
        } footer: {
            Text("不选时自动用板块里出现过的书源。封面取该书源第一个板块的前三本。")
        }
    }

    private var carouselSummary: String {
        draft.carouselSourceUrls.isEmpty ? "自动" : "\(draft.carouselSourceUrls.count) 个"
    }

    // MARK: 板块

    private var entriesSection: some View {
        Section {
            if draft.entries.isEmpty {
                Text("还没有板块。点下面的「添加板块」，从书源发现分类里挑。")
                    .appFont(.footnote)
                    .foregroundStyle(palette.secondary)
            } else {
                ForEach(Array(draft.entries.enumerated()), id: \.element.id) { pair in
                    NavigationLink {
                        EntryEditor(entry: binding(for: pair.offset))
                    } label: {
                        row(pair.element)
                    }
                }
                .onMove { source, destination in
                    draft.move(fromOffsets: source, toOffset: destination)
                }
                .onDelete { offsets in
                    // 先按当前状态收集 id，再删；边删边取索引会错位
                    let ids = offsets.compactMap { index in
                        draft.entries.indices.contains(index) ? draft.entries[index].id : nil
                    }
                    for id in ids {
                        draft.remove(id: id)
                    }
                }
            }
        } header: {
            HStack {
                Text("板块")
                Spacer()
                if !draft.entries.isEmpty {
                    EditButton().font(.footnote)
                }
            }
        } footer: {
            if !draft.entries.isEmpty {
                Text("拖动右侧把手排序，左滑删除。顺序即页面从上到下的顺序。")
            }
        }
    }

    private func binding(for index: Int) -> Binding<CustomDiscoverEntry> {
        Binding(
            get: {
                draft.entries.indices.contains(index)
                    ? draft.entries[index]
                    : CustomDiscoverEntry(sourceUrl: "", sourceName: "", kindTitle: "", kindUrl: "")
            },
            set: { newValue in
                guard draft.entries.indices.contains(index) else { return }
                draft.entries[index] = newValue
            }
        )
    }

    private func row(_ entry: CustomDiscoverEntry) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon(entry.template))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.boardTitle).appFont(.headline).lineLimit(1)
                Text("\(entry.template.title) · 显示 \(entry.count) 条 · \(entry.sourceName)")
                    .appFont(.caption)
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private func icon(_ kind: DiscoverTemplateKind) -> String {
        switch kind {
        case .badgeGrid: return "square.grid.2x2"
        case .covers: return "rectangle.split.3x1"
        case .rankRow: return "list.number"
        case .waterfall: return "rectangle.grid.2x2"
        case .curve: return "rectangle.on.rectangle.angled"
        case .fan: return "fan.fill"
        case .deck: return "square.stack.3d.down.right"
        case .history: return "clock.arrow.circlepath"
        }
    }

    private func save() {
        model.save(draft)
        dismiss()
    }
}

// MARK: - 单条板块编辑

/// 选模板、调数量、看预览。
struct EntryEditor: View {
    @ThemePalette private var palette
    @Binding var entry: CustomDiscoverEntry
    @State private var showPreview = false

    var body: some View {
        List {
            Section {
                Text(entry.boardTitle).appFont(.headline)
                Text("\(entry.sourceName) · \(entry.kindUrl)")
                    .appFont(.caption2)
                    .foregroundStyle(palette.secondary)
                    .lineLimit(2)
            } header: {
                Text("来源")
            }

            Section {
                ForEach(DiscoverTemplate.all) { template in
                    Button {
                        entry.applyTemplate(template.kind)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: icon(template.kind))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(palette.accent)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(template.title).appFont(.body)
                                Text(template.detail)
                                    .appFont(.caption2)
                                    .foregroundStyle(palette.secondary)
                                    .lineLimit(2)
                            }
                            Spacer(minLength: 4)
                            if entry.template == template.kind {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(palette.accent)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("模板")
            }

            Section {
                Stepper(value: bindingCount, in: 1...20) {
                    HStack {
                        Text("显示数量")
                        Spacer()
                        Text("\(entry.count)").foregroundStyle(palette.secondary)
                    }
                }
                Button("预览这个模板") { showPreview = true }
            } footer: {
                Text("数量范围 1–20。「全部」页不受此限，会一直加载。")
            }
        }
        .scrollContentBackground(.hidden)
        .foregroundStyle(palette.primary)
        .background { AppThemeCanvas().ignoresSafeArea() }
        .navigationTitle(entry.boardTitle)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPreview) {
            NavigationStack {
                DiscoverTemplatePreview(kind: entry.template)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("完成") { showPreview = false }
                        }
                    }
                    .navigationTitle("预览")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    private var bindingCount: Binding<Int> {
        Binding(
            get: { entry.count },
            set: { entry.count = DiscoverTemplate.template(for: entry.template).clampedCount($0) }
        )
    }

    private func icon(_ kind: DiscoverTemplateKind) -> String {
        switch kind {
        case .badgeGrid: return "square.grid.2x2"
        case .covers: return "rectangle.split.3x1"
        case .rankRow: return "list.number"
        case .waterfall: return "rectangle.grid.2x2"
        case .curve: return "rectangle.on.rectangle.angled"
        case .fan: return "fan.fill"
        case .deck: return "square.stack.3d.down.right"
        case .history: return "clock.arrow.circlepath"
        }
    }
}

// MARK: - 轮播书源选择

struct CarouselSourcePicker: View {
    @ThemePalette private var palette
    @Binding var config: CustomDiscoverConfig
    @EnvironmentObject private var store: AppStore

    private var candidates: [BookSource] {
        // 板块里出现过的书源（按出现顺序去重）
        var seen = Set<String>()
        var out: [BookSource] = []
        for entry in config.entries where seen.insert(entry.sourceUrl).inserted {
            if let source = store.source(for: entry.sourceUrl) { out.append(source) }
        }
        return out
    }

    var body: some View {
        List {
            Section {
                Button {
                    config.carouselSourceUrls = []
                } label: {
                    HStack {
                        Text("自动（按板块顺序）")
                        Spacer()
                        if config.carouselSourceUrls.isEmpty {
                            Image(systemName: "checkmark").foregroundStyle(palette.accent)
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            Section {
                ForEach(candidates) { source in
                    Button {
                        toggle(source.bookSourceUrl)
                    } label: {
                        HStack {
                            Text(source.bookSourceName).lineLimit(1)
                            Spacer()
                            if let order = config.carouselSourceUrls.firstIndex(of: source.bookSourceUrl) {
                                Text("\(order + 1)")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 20, height: 20)
                                    .background(palette.accent, in: Circle())
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("参与轮播的书源")
            } footer: {
                Text("点一下加入，再点取消。数字是轮播顺序。")
            }

            // 排序单独一段：只操作已选中的书源，索引才对得上
            if !config.carouselSourceUrls.isEmpty {
                Section {
                    ForEach(Array(config.carouselSourceUrls.enumerated()), id: \.element) { pair in
                        HStack(spacing: 10) {
                            Text("\(pair.offset + 1)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 20, height: 20)
                                .background(palette.accent, in: Circle())
                            Text(name(for: pair.element)).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                    }
                    .onMove { source, destination in
                        config.carouselSourceUrls.move(fromOffsets: source, toOffset: destination)
                    }
                } header: {
                    HStack {
                        Text("轮播顺序")
                        Spacer()
                        EditButton().font(.footnote)
                    }
                } footer: {
                    Text("拖动右侧把手调整顺序。")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .foregroundStyle(palette.primary)
        .background { AppThemeCanvas().ignoresSafeArea() }
        .navigationTitle("顶部轮播")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// 用地址取书源名，书源找不到时退回地址本身。
    private func name(for url: String) -> String {
        store.source(for: url)?.bookSourceName ?? url
    }

    private func toggle(_ url: String) {
        if let index = config.carouselSourceUrls.firstIndex(of: url) {
            config.carouselSourceUrls.remove(at: index)
        } else {
            config.carouselSourceUrls.append(url)
        }
    }
}
