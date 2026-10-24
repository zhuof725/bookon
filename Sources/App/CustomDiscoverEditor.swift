import SwiftUI

/// 单条板块编辑：选模板、调外观、看预览。
struct EntryEditor: View {
    @ThemePalette private var palette
    @Binding var entry: CustomDiscoverEntry
    @EnvironmentObject private var store: AppStore

    /// 预览用的书：优先用已加载的真实数据，没有就用占位数据
    @State private var previewBooks: [Book] = []
    @State private var previewLoading = false
    @State private var previewFailed = false

    var body: some View {
        List {
            previewSection
            sourceSection
            templateSection
            appearanceSection
        }
        .scrollContentBackground(.hidden)
        .foregroundStyle(palette.primary)
        .background { AppThemeCanvas().ignoresSafeArea() }
        .navigationTitle(entry.boardTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadPreview() }
    }

    // MARK: 预览

    private var previewSection: some View {
        Section {
            VStack(spacing: 0) {
                DiscoverTemplateView(
                    kind: entry.template,
                    title: entry.boardTitle,
                    moreTitle: "",
                    books: previewBooks.isEmpty ? Self.placeholderBooks : previewBooks,
                    count: min(entry.count, 6),
                    scale: entry.scale,
                    corner: entry.corner,
                    showNumber: entry.showNumber,
                    onMore: nil
                )
                .allowsHitTesting(false)
                .padding(.top, 6)
            }
            .frame(maxWidth: .infinity)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            if previewLoading {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.small)
                    Text("正在取真实数据…").appFont(.caption).foregroundStyle(palette.secondary)
                }
            } else if previewFailed {
                HStack(spacing: 7) {
                    Text("真实数据拉取失败，上面是占位预览")
                        .appFont(.caption).foregroundStyle(palette.secondary)
                    Button("重试") { Task { await loadPreview(force: true) } }
                        .appFont(.caption.weight(.semibold))
                }
            } else if !previewBooks.isEmpty {
                Text("预览取的是这个分类的真实书籍")
                    .appFont(.caption2).foregroundStyle(palette.secondary)
            }
        } header: {
            Text("预览")
        }
    }

    // MARK: 来源

    private var sourceSection: some View {
        Section {
            Text(entry.boardTitle).appFont(.headline)
            Text(entry.sourceName)
                .appFont(.caption)
                .foregroundStyle(palette.secondary)
        } header: {
            Text("来源")
        }
    }

    // MARK: 模板

    private var templateSection: some View {
        Section {
            NavigationLink {
                DiscoverTemplateLibrary(current: entry.template) { kind in
                    entry.applyTemplate(kind)
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: DiscoverTemplateIcon.symbol(entry.template))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(palette.accent)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.template.title).appFont(.body)
                        Text(entry.template.detail)
                            .appFont(.caption2)
                            .foregroundStyle(palette.secondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 4)
                    Text("展示库")
                        .appFont(.caption.weight(.semibold))
                        .foregroundStyle(palette.accent)
                }
            }
            .accessibilityIdentifier("entry.template.library")
        } header: {
            Text("模板")
        } footer: {
            Text("展示库里每个模板按真实尺寸铺开，点一个就换过来。")
        }
    }

    // MARK: 外观

    private var appearanceSection: some View {
        Section {
            Stepper(value: bindingCount, in: 1...20) {
                row("显示数量", value: "\(entry.count)")
            }

            // 卡片大小
            VStack(alignment: .leading, spacing: 6) {
                row("卡片大小", value: String(format: "%.2fx", entry.scale))
                Slider(value: bindingScale, in: 0.7...1.5, step: 0.05)
            }

            // 圆角
            VStack(alignment: .leading, spacing: 6) {
                row("圆角", value: "\(Int(entry.corner))")
                Slider(value: bindingCorner, in: 0...20, step: 1)
            }

            Toggle("显示序号", isOn: $entry.showNumber)
        } header: {
            Text("外观")
        } footer: {
            Text("数量范围 1–20，「全部」页不受此限。卡片大小会影响大封面的列数：小→3 列，中大→2 列，最大→1 列。")
        }
    }

    private func row(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(palette.secondary)
        }
    }

    private var bindingCount: Binding<Int> {
        Binding(
            get: { entry.count },
            set: { entry.count = DiscoverTemplate.template(for: entry.template).clampedCount($0) }
        )
    }

    private var bindingScale: Binding<Double> {
        Binding(get: { entry.scale }, set: { entry.scale = $0 })
    }

    private var bindingCorner: Binding<Double> {
        Binding(get: { entry.corner }, set: { entry.corner = $0 })
    }

    // MARK: 预览数据

    /// 拉这个板块的真实前几本；失败就保持占位数据。
    private func loadPreview(force: Bool = false) async {
        guard entry.kindUrl.contains("://") || entry.kindUrl.hasPrefix("/") else { return }
        guard let source = store.source(for: entry.sourceUrl) else { return }
        if !force, !previewBooks.isEmpty { return }
        previewLoading = true
        previewFailed = false
        defer { previewLoading = false }
        if !force,
           let cached = DiscoverBlockCache.cached(source: entry.sourceUrl, url: entry.kindUrl),
           !cached.isEmpty {
            previewBooks = Array(cached.prefix(6))
            return
        }
        do {
            let list = try await SourceDiagnostics.explore(source: source, url: entry.kindUrl)
            previewBooks = Array(list.prefix(12))
            if previewBooks.isEmpty { previewFailed = true }
        } catch {
            previewFailed = true
        }
    }

    /// 拉不到真实数据时的占位书：让用户先看到版式。
    static let placeholderBooks: [Book] = {
        let names = ["示例书名一", "示例书名二", "示例书名三",
                     "示例书名四", "示例书名五", "示例书名六"]
        return names.enumerated().map { index, name in
            var book = Book(bookUrl: "placeholder://\(index)", name: name, origin: "placeholder")
            book.author = "示例作者"
            return book
        }
    }()
}
