import SwiftUI

/// 首页（自定义发现）配置：分类标题 + 板块列表。
struct CustomDiscoverSettingsView: View {
    @ThemePalette private var palette
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var model: DiscoverBoardStore

    @State private var draft: CustomDiscoverConfig
    @State private var showPicker = false
    @State private var newCategory = ""
    @State private var loaded = false

    init(initial: CustomDiscoverConfig? = nil) {
        _draft = State(initialValue: initial ?? CustomDiscoverConfig())
    }

    var body: some View {
        NavigationStack {
            List {
                categorySection
                entriesSection
            }
            .scrollContentBackground(.hidden)
            .foregroundStyle(palette.primary)
            .background { AppThemeCanvas().ignoresSafeArea() }
            .navigationTitle("自定义首页")
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
                TemplatePickerSheet { picked in
                    for entry in picked { draft.upsert(entry) }
                    showPicker = false
                }
                .environmentObject(store)
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                // 从编辑页带进来的草稿优先，避免把用户刚加的板块冲掉
                if draft.entries.isEmpty { draft = model.config }
            }
        }
    }

    // MARK: 顶部分类

    private var categorySection: some View {
        Section {
            // 已有分类：可改名、可删
            ForEach(Array(draft.categories.enumerated()), id: \.offset) { pair in
                HStack(spacing: 10) {
                    Image(systemName: "tag")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.accent)
                        .frame(width: 20)
                    TextField("分类标题", text: bindingCategory(pair.offset))
                        .textInputAutocapitalization(.never)
                }
            }
            .onDelete { offsets in
                let ids = offsets.compactMap { draft.categories.indices.contains($0) ? $0 : nil }
                for index in ids.sorted(by: >) {
                    draft.categories.remove(at: index)
                }
            }

            HStack(spacing: 8) {
                TextField("新增分类标题", text: $newCategory)
                Button {
                    addCategory()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(newCategory.trimmingCharacters(in: .whitespaces).isEmpty
                                         ? palette.secondary.opacity(0.4) : palette.accent)
                }
                .buttonStyle(.plain)
                .disabled(newCategory.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            HStack {
                Text("顶部分类")
                Spacer()
                if !draft.categories.isEmpty { EditButton().font(.footnote) }
            }
        } footer: {
            Text(effectiveHint)
        }
    }

    /// 不填分类时，顶部按板块里出现过的书源名自动生成，并自动加一个「全部」。
    private var effectiveHint: String {
        if draft.categories.isEmpty {
            let auto = draft.effectiveCategories
            if auto.isEmpty {
                return "留空则按板块所属书源自动生成分类，并自动加「全部」。"
            }
            return "当前自动生成：全部、\(auto.joined(separator: "、"))"
        }
        return "分类按书源名筛选板块：点「起点」就只看起点的板块。再加一个「全部」可看全量。"
    }

    private func bindingCategory(_ index: Int) -> Binding<String> {
        Binding(
            get: { draft.categories.indices.contains(index) ? draft.categories[index] : "" },
            set: { value in
                guard draft.categories.indices.contains(index) else { return }
                draft.categories[index] = value
            }
        )
    }

    private func addCategory() {
        let value = newCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        if !draft.categories.contains(value) { draft.categories.append(value) }
        newCategory = ""
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
                            .environmentObject(store)
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
                    for id in ids { draft.remove(id: id) }
                }
            }
        } header: {
            HStack {
                Text("板块")
                Spacer()
                if !draft.entries.isEmpty { EditButton().font(.footnote) }
            }
        } footer: {
            if !draft.entries.isEmpty {
                Text("拖动排序，左滑删除。顺序即首页从上到下的顺序。点进去可以换模板、调外观并预览。")
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
            Image(systemName: DiscoverTemplateIcon.symbol(entry.template))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(palette.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.boardTitle).appFont(.headline).lineLimit(1)
                Text("\(entry.template.title) · \(entry.count) 条 · \(entry.sourceName)")
                    .appFont(.caption)
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    private func save() {
        // 落盘前把空分类名清掉，避免出现一个点不动的空白标签
        draft.categories = draft.categories
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        model.save(draft)
        dismiss()
    }
}
