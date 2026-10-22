import SwiftUI

/// 首页的**编辑模式**：空白画布 + 中间加号，点加号挑模板。
///
/// 对应参考图一的形态：
///  - 中间一个幽灵图标 + 「空白配置」
///  - 下面一组入口：选择轮播数据 / 关闭轮播图 / 更多设置
///  - 底部一个圆形加号，点开挑模板
///  - 右上角「完成」保存退出
struct CustomDiscoverEditorPage: View {
    @ThemePalette private var palette
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var model: DiscoverBoardStore

    @State private var draft = CustomDiscoverConfig()
    @State private var showAddPage = false
    @State private var showCarouselPicker = false
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            ZStack {
                AppThemeCanvas().ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        if draft.entries.isEmpty {
                            emptyCanvas
                        } else {
                            boardList
                        }
                        Spacer(minLength: 40)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 30)
                }

                // 底部圆形加号
                VStack {
                    Spacer()
                    Button {
                        showAddPage = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 26, weight: .medium))
                            .foregroundStyle(palette.primary)
                            .frame(width: 64, height: 64)
                            .background {
                                Circle().fill(Color(uiColor: .systemBackground))
                                    .shadow(color: .black.opacity(0.10), radius: 12, x: 0, y: 4)
                            }
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 26)
                    .accessibilityIdentifier("editor.add")
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { save() }
                        .fontWeight(.semibold)
                }
            }
            .navigationDestination(isPresented: $showAddPage) {
                AddBoardPage { entries in
                    for entry in entries { draft.upsert(entry) }
                }
                .environmentObject(store)
            }
            .sheet(isPresented: $showCarouselPicker) {
                CarouselDataSourcePicker(config: $draft)
                    .environmentObject(store)
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                draft = model.config
            }
        }
    }

    // MARK: 空白画布

    private var emptyCanvas: some View {
        VStack(spacing: 0) {
            // 幽灵图标
            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .fill(palette.accent.opacity(0.16))
                    .frame(width: 78, height: 78)
                    .overlay {
                        Image(systemName: "theatermasks")
                            .font(.system(size: 32, weight: .regular))
                            .foregroundStyle(palette.accent)
                    }
                Image(systemName: "camera.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.secondary)
                    .padding(5)
                    .background(Color(uiColor: .systemBackground), in: Circle())
                    .offset(x: 2, y: 2)
            }
            .padding(.bottom, 14)

            Text("空白配置")
                .appFont(.system(size: 17, weight: .semibold))
                .foregroundStyle(palette.primary)
                .padding(.bottom, 34)

            entryRow("选择轮播数据", enabled: true) { showCarouselPicker = true }
            entryRow(draft.carouselHidden ? "打开轮播图" : "关闭轮播图", enabled: true) {
                withAnimation(.easeInOut(duration: 0.2)) { draft.carouselHidden.toggle() }
            }
        }
        .padding(.horizontal, 24)
    }

    private func entryRow(_ title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        entryRow(systemImage: nil, title, enabled: enabled, action: action)
    }

    private func entryRow(systemImage: String?, _ title: String, enabled: Bool,
                          action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .medium))
                }
                Text(title)
                    .appFont(.system(size: 16))
            }
            .foregroundStyle(enabled ? palette.primary : palette.secondary.opacity(0.55))
            .frame(maxWidth: .infinity)
            .frame(height: 50)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    // MARK: 已有板块

    private var boardList: some View {
        VStack(spacing: 14) {
            ForEach(Array(draft.entries.enumerated()), id: \.element.id) { pair in
                NavigationLink {
                    EntryEditor(entry: binding(for: pair.offset))
                        .environmentObject(store)
                } label: {
                HStack(spacing: 10) {
                    Image(systemName: DiscoverTemplateIcon.symbol(pair.element.template))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.accent)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pair.element.boardTitle)
                            .appFont(.system(size: 15, weight: .semibold))
                            .foregroundStyle(palette.primary)
                            .lineLimit(1)
                        Text("\(pair.element.template.title) · \(pair.element.count) 条 · \(pair.element.sourceName)")
                            .appFont(.system(size: 11))
                            .foregroundStyle(palette.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Button {
                        draft.remove(id: pair.element.id)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(palette.secondary.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .frame(height: 62)
                .background {
                    ThemeSurface(shape: RoundedRectangle(cornerRadius: 14, style: .continuous), isCard: true)
                }
                .padding(.horizontal, 20)
                }
                .buttonStyle(.plain)
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
            set: { value in
                guard draft.entries.indices.contains(index) else { return }
                draft.entries[index] = value
            }
        )
    }

    private func save() {
        draft.categories = draft.categories
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        model.save(draft)
        dismiss()
    }
}
