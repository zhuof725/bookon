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
    /// 有板块时点 + ：先去「添加模板」挑一个模板，挑完再进「选择分类」。
    @State private var showTemplatePicker = false
    @State private var showCarouselPicker = false
    @State private var loaded = false
    /// 空配置时先让用户从展示库挑一个模板；选完才进「添加栏目」。
    @State private var pickedTemplate: DiscoverTemplateKind?

    var body: some View {
        NavigationStack {
            ZStack {
                AppThemeCanvas().ignoresSafeArea()

                ScrollView {
                    if draft.entries.isEmpty {
                        // 空配置：第一屏就是模板展示库，点一个模板直接开始配置
                        DiscoverTemplateLibrary(current: pickedTemplate ?? .largeCard,
                                                dismissOnPick: false) { kind in
                            pickedTemplate = kind
                            showAddPage = true
                        }
                        .environmentObject(store)
                    } else {
                        previewList
                    }
                }

                // 底部圆形加号：空配置时整屏就是模板库，不需要再加号
                if !draft.entries.isEmpty {
                    VStack {
                        Spacer()
                        Button {
                            // 手点加号：先去「添加模板」挑模板
                            pickedTemplate = nil
                            showTemplatePicker = true
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
            }
            .navigationTitle(draft.entries.isEmpty ? "添加模板" : "首页预览")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 14) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(palette.primary)
                    }
                    .accessibilityIdentifier("editor.close")
                    Menu {
                        Button {
                            showCarouselPicker = true
                        } label: {
                            Label("轮播数据与模板", systemImage: "rectangle.stack")
                        }
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                draft.carouselHidden.toggle()
                            }
                        } label: {
                            Label(draft.carouselHidden ? "打开顶部轮播" : "关闭顶部轮播",
                                  systemImage: draft.carouselHidden ? "eye" : "eye.slash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .accessibilityIdentifier("editor.menu")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { save() }
                        .fontWeight(.semibold)
                }
            }
            .navigationDestination(isPresented: $showTemplatePicker) {
                DiscoverTemplateLibrary(current: .largeCard, dismissOnPick: false) { kind in
                    pickedTemplate = kind
                    showTemplatePicker = false
                    showAddPage = true
                }
                .environmentObject(store)
            }
            .navigationDestination(isPresented: $showAddPage) {
                // 从模板库点进来时模板已经定了，这一页只管选书源和分类。
                AddBoardPage(initialTemplate: pickedTemplate) { entries in
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

    // MARK: 已有板块（全面屏真实排版预览）

    /// 不再是「都市人生 · 大型阅读卡片 · 20 条」这种条目列表，
    /// 而是把每个板块按它自己的模板原样画出来——看到的就等于首页的样子。
    /// 每个板块右上角一个减号，点开是它的详细设置。
    private var previewList: some View {
        LazyVStack(spacing: 26) {
            ForEach(Array(draft.entries.enumerated()), id: \.element.id) { pair in
                previewBlock(pair.element, index: pair.offset)
            }
            Text("点底部 + 继续添加模板")
                .appFont(.system(size: 12))
                .foregroundStyle(palette.secondary)
                .padding(.top, 4)
        }
        .padding(.top, 14)
        .padding(.bottom, 120)
    }

    private func previewBlock(_ entry: CustomDiscoverEntry, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // 板块头：标题 + 设置入口
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(entry.boardTitle)
                    .appFont(.system(size: 19, weight: .bold))
                    .foregroundStyle(palette.primary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                NavigationLink {
                    EntryEditor(entry: binding(for: index))
                        .environmentObject(store)
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.secondary)
                        .frame(width: 26, height: 26)
                        .background(palette.primary.opacity(0.06), in: Circle())
                }
                .buttonStyle(.plain)
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        draft.remove(id: entry.id)
                    }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(palette.secondary.opacity(0.45))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            // 真身：和首页同一套渲染
            Group {
            if entry.template.dataSource == .readingProgress {
                DiscoverTemplateView(
                    kind: .history,
                    title: "",
                    moreTitle: "",
                    history: model.historyItems,
                    count: entry.count,
                    onSelectHistory: { _ in }
                )
                .allowsHitTesting(false)
            } else if let section = model.sectionFor(entry), section.failed {
                inlineFailed(section)
            } else if let section = model.sectionFor(entry), !section.books.isEmpty {
                DiscoverTemplateView(
                    kind: entry.template,
                    title: "",
                    moreTitle: "",
                    books: section.books,
                    cards: section.cards,
                    count: entry.count,
                    scale: entry.scale,
                    corner: entry.corner,
                    showNumber: entry.showNumber,
                    onSelectBook: { _ in }
                )
                .allowsHitTesting(false)
            } else {
                inlineLoading
                    .task(id: entry.id) { await model.loadLive(entry) }
            }
            }
        }
        .accessibilityIdentifier("editor.preview.\(entry.id)")
    }

    private var inlineLoading: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("加载中…")
                .appFont(.system(size: 12))
                .foregroundStyle(palette.secondary)
        }
        .padding(.horizontal, 20)
        .frame(height: 80)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func inlineFailed(_ section: DiscoverSectionModel) -> some View {
        HStack(spacing: 8) {
            Text(section.errorText ?? "加载失败")
                .appFont(.system(size: 12))
                .foregroundStyle(palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("重试") {
                Task { await model.load(section, force: true) }
            }
            .appFont(.system(size: 12, weight: .semibold))
        }
        .padding(.horizontal, 20)
        .frame(height: 80)
        .frame(maxWidth: .infinity, alignment: .leading)
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
