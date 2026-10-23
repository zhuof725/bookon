import SwiftUI

// MARK: - 页面管理

/// 首页页面管理：列出所有页面，可以新增、删除、排序、改名，点一页进去编辑。
///
/// 删除与编辑都走**长按菜单**：列表上左滑不再负责删除（容易误触），
/// 只在长按弹出的小菜单里给「编辑页面 / 外观 / 删除」。
struct PageManagerView: View {
    @ThemePalette private var palette
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var model: DiscoverBoardStore

    /// 点某个页面 → 进它的编辑页。
    var onOpenPage: (String) -> Void = { _ in }
    /// 长按「编辑页面」→ 直接进内容编辑（空页面也进）。
    var onEditPage: (String) -> Void = { _ in }

    @State private var editingPage: CustomDiscoverPage?
    @State private var showDiscoverSettings = false
    /// 待确认删除的页面（长按菜单触发，删除前再问一次）。
    @State private var pendingDelete: CustomDiscoverPage?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(pages) { page in
                        pageRow(page, isCurrent: page.id == model.pages.currentID)
                            .contextMenu {
                                Button {
                                    model.selectPage(page.id)
                                    onEditPage(page.id)
                                    dismiss()
                                } label: {
                                    Label("编辑页面", systemImage: "square.and.pencil")
                                }
                                Button {
                                    editingPage = page
                                } label: {
                                    Label("页面外观", systemImage: "paintpalette")
                                }
                                Button {
                                    model.movePageToFront(page.id)
                                } label: {
                                    Label("设为首页", systemImage: "arrow.up.to.line")
                                }
                                .disabled(page.id == model.pages.currentID || pages.first?.id == page.id)
                                Divider()
                                Button(role: .destructive) {
                                    pendingDelete = page
                                } label: {
                                    Label("删除页面", systemImage: "trash")
                                }
                                .disabled(pages.count <= 1)
                            }
                    }
                    .onMove { model.movePages(fromOffsets: $0, toOffset: $1) }
                } header: {
                    Text("全部页面")
                } footer: {
                    Text("长按一行可以编辑或删除；右侧拖动排序。点一行进入该页面。")
                }

                Section {
                    Button {
                        model.addPage()
                        // 新页面默认空，直接进编辑页配内容
                        if let newPage = model.pages.pages.last {
                            onOpenPage(newPage.id)
                        }
                        dismiss()
                    } label: {
                        Label("自定义页面", systemImage: "plus.circle")
                    }
                    .accessibilityIdentifier("pageManager.addCustom")
                } header: {
                    Text("添加页面")
                } footer: {
                    Text("空白页面，自由添加组件（板块）。")
                }

                Section {
                    Button {
                        showDiscoverSettings = true
                    } label: {
                        Label("发现设置", systemImage: "slider.horizontal.3")
                    }
                } header: {
                    Text("其他")
                }
            }
            .scrollContentBackground(.hidden)
            .foregroundStyle(palette.primary)
            .background { AppThemeCanvas().ignoresSafeArea() }
            .navigationTitle("页面管理")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .fontWeight(.semibold)
                }
                if pages.count > 1 {
                    ToolbarItem(placement: .topBarLeading) {
                        EditButton()
                    }
                }
            }
            .sheet(item: $editingPage) { page in
                PageAppearanceEditor(page: page) { updated in
                    model.renamePage(updated)
                }
            }
            .sheet(isPresented: $showDiscoverSettings) {
                DiscoverSettingsView()
                    .environmentObject(store)
            }
            .confirmationDialog("删除「\(pendingDelete?.name ?? "")」？",
                                isPresented: Binding(
                                    get: { pendingDelete != nil },
                                    set: { if !$0 { pendingDelete = nil } }
                                ),
                                titleVisibility: .visible) {
                Button("删除页面", role: .destructive) {
                    if let page = pendingDelete { model.removePage(page.id) }
                    pendingDelete = nil
                }
                Button("取消", role: .cancel) { pendingDelete = nil }
            } message: {
                Text("页面里的板块会一起删掉，无法撤销。")
            }
            .accessibilityIdentifier("pageManager")
        }
    }

    private var pages: [CustomDiscoverPage] { model.pages.pages }

    private func pageRow(_ page: CustomDiscoverPage, isCurrent: Bool) -> some View {
        Button {
            model.selectPage(page.id)
            onOpenPage(page.id)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Text(page.icon)
                    .font(.system(size: 22))
                    .frame(width: 34, height: 34)
                    .background(palette.primary.opacity(0.06),
                                in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(page.name)
                        .appFont(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.primary)
                        .lineLimit(1)
                    Text(page.componentCount == 0
                         ? "还没有组件"
                         : "\(page.componentCount) 个组件")
                        .appFont(.system(size: 11.5))
                        .foregroundStyle(palette.secondary)
                }
                Spacer(minLength: 4)
                if isCurrent {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(palette.accent)
                }
            }
            .padding(.vertical, 3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("pageManager.page.\(page.id)")
        .accessibilityHint("长按可编辑或删除")
    }
}

// MARK: - 页面外观（图标 / 名称）

/// 改一个页面的图标和名称。对应参考图三最上面「页面外观」那两块。
struct PageAppearanceEditor: View {
    @ThemePalette private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var draft: CustomDiscoverPage
    var onSave: (CustomDiscoverPage) -> Void

    init(page: CustomDiscoverPage, onSave: @escaping (CustomDiscoverPage) -> Void) {
        _draft = State(initialValue: page)
        self.onSave = onSave
    }

    /// 常用图标，够表达页面用途即可，不追求全量 emoji 面板。
    private let icons = ["📄", "🏠", "📚", "🔥", "⭐️", "🎯", "🌙", "☀️",
                         "🧭", "🎬", "🎧", "🪐", "🍀", "🐱", "🗂", "✨"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("页面名称", text: $draft.name)
                        .appFont(.system(size: 15))
                        .accessibilityIdentifier("pageAppearance.name")
                } header: {
                    Text("名称")
                }

                Section {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10),
                                             count: 8), spacing: 10) {
                        ForEach(icons, id: \.self) { icon in
                            Button {
                                draft.icon = icon
                            } label: {
                                Text(icon)
                                    .font(.system(size: 22))
                                    .frame(width: 34, height: 34)
                                    .background {
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(draft.icon == icon
                                                  ? palette.accent.opacity(0.16)
                                                  : palette.primary.opacity(0.04))
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("图标")
                } footer: {
                    Text("图标会显示在首页左上角的页面切换按钮上。")
                }
            }
            .scrollContentBackground(.hidden)
            .foregroundStyle(palette.primary)
            .background { AppThemeCanvas().ignoresSafeArea() }
            .navigationTitle("页面外观")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        var next = draft
                        let trimmed = next.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        next.name = trimmed.isEmpty ? "空白页面" : trimmed
                        onSave(next)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
