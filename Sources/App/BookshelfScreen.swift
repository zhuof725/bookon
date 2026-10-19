import SwiftUI
import UIKit
import ImageIO

enum ShelfFilter: String, CaseIterable { case all = "全部", reading = "在读", unread = "未读", local = "本地" }
enum ShelfSort: String, CaseIterable { case recent = "最后阅读", added = "加入时间", title = "书名" }
enum ShelfLayout: String, CaseIterable { case grid = "书架", list = "列表" }

enum ShelfBooks {
    static func isStarted(_ book: Book) -> Bool {
        book.durChapterIndex > 0 || book.durChapterPos > 0 || !(book.durChapterTitle ?? "").isEmpty
    }
    static func visible(_ books: [Book], filter: ShelfFilter, sort: ShelfSort, localOrigin: String) -> [Book] {
        books.filter { book in
            switch filter {
            case .all: return true
            case .reading: return isStarted(book)
            case .unread: return !isStarted(book)
            case .local: return book.origin == localOrigin
            }
        }.sorted { a, b in
            switch sort {
            case .recent: if a.lastReadAt != b.lastReadAt { return a.lastReadAt > b.lastReadAt }
            case .added: if a.addedAt != b.addedAt { return a.addedAt > b.addedAt }
            case .title:
                let order = a.name.localizedStandardCompare(b.name)
                if order != .orderedSame { return order == .orderedAscending }
            }
            return a.bookUrl < b.bookUrl
        }
    }
    static func subtitle(_ book: Book) -> String {
        let author = book.author.isEmpty ? (book.wordCount ?? book.originName) : book.author
        let progress = isStarted(book) ? (book.durChapterTitle ?? "阅读中") : "刚开始"
        return author.isEmpty ? progress : author + " · " + progress
    }
}

struct ShelfGlass<S: InsettableShape>: ViewModifier {
    let shape: S
    var isCard: Bool = false
    func body(content: Content) -> some View {
        content.background { ThemeSurface(shape: shape, isCard: isCard) }
    }
}

/// Independent from AppStore: the production screen and offline UI fixture share
/// exactly the same card/menu code. Only callbacks may mutate the user's library.
struct BookshelfScreen: View {
    @ThemePalette private var palette
    @Environment(\.appTheme) private var theme
    let books: [Book]
    let localOrigin: String
    let onOpen: (Book) -> Void
    let onImport: () -> Void
    let onRemove: ([Book]) -> Void
    var loadListChapters: (Book) -> [BookChapter]? = { _ in nil }
    /// 下拉刷新：返回要显示的结果文案（nil 表示不提示）。刷新期间系统自带下拉指示器。
    var onRefresh: () async -> String? = { nil }
    @AppStorage("shelf.layout.v1") private var layoutValue = ShelfLayout.grid.rawValue
    @AppStorage("shelf.sort.v1") private var sortValue = ShelfSort.recent.rawValue
    @State private var filter: ShelfFilter = .all
    @State private var selecting = false
    @State private var selection: Set<String> = []
    @State private var menu: String?
    @State private var confirmRemoval = false
    @State private var refreshStatus: String?
    @State private var statusTask: Task<Void, Never>?
    @State private var refreshing = false
    @Environment(\.dynamicTypeSize) private var typeSize

    private var layout: ShelfLayout { ShelfLayout(rawValue: layoutValue) ?? .grid }
    private var sort: ShelfSort { ShelfSort(rawValue: sortValue) ?? .recent }
    private var visibleBooks: [Book] { ShelfBooks.visible(books, filter: filter, sort: sort, localOrigin: localOrigin) }
    private var selectedBooks: [Book] { books.filter { selection.contains($0.id) } }

    var body: some View {
        GeometryReader { geometry in
            let metrics = theme.customization.map {
                ThemeShelfMetrics(width: geometry.size.width, customization: $0, accessibility: typeSize.isAccessibilitySize)
            }
            let columns = metrics?.columns ?? (typeSize.isAccessibilitySize ? 2 : max(3, Int((geometry.size.width - 48) / 124)))
            VStack(spacing: 14) {
                header
                if selecting { selectionBar }
                if let refreshStatus {
                    Text(refreshStatus)
                        .appFont(.system(size: 14))
                        .foregroundStyle(palette.secondary)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .modifier(ShelfGlass(shape: Capsule()))
                        .accessibilityIdentifier("shelf.refreshStatus")
                        .transition(.opacity)
                }
                ScrollView {
                    if visibleBooks.isEmpty {
                        VStack(spacing: 14) {
                            Image(systemName: "books.vertical").font(.system(size: 36)).foregroundStyle(palette.secondary)
                            Text(books.isEmpty ? "书架是空的" : "这个分类暂无书籍").appFont(.headline)
                            Text(books.isEmpty ? "点击左上角搜索，或在右上角菜单导入 TXT / EPUB。" : "试试切换到「全部」。")
                                .appFont(.subheadline).foregroundStyle(palette.secondary).multilineTextAlignment(.center)
                        }.padding(36).padding(.top, 70).frame(maxWidth: .infinity)
                        .accessibilityIdentifier("shelf.empty")
                    } else if layout == .grid {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: metrics == nil ? 10 : 0), spacing: 18), count: columns), alignment: .leading, spacing: 22) {
                            ForEach(visibleBooks) { book in bookButton(book, grid: true, coverWidth: metrics?.coverWidth) }
                        }.padding(.horizontal, 24).padding(.top, 2).padding(.bottom, 24)
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(visibleBooks) { book in
                                ShelfListBookButton(book: book, localOrigin: localOrigin,
                                    selecting: selecting, selected: selection.contains(book.id),
                                    loadChapters: loadListChapters, action: {
                                        if selecting {
                                            if selection.contains(book.id) { selection.remove(book.id) }
                                            else { selection.insert(book.id) }
                                        } else { onOpen(book) }
                                    }, open: { onOpen(book) }, select: {
                                        selecting = true; selection.insert(book.id)
                                    })
                            }
                        }.padding(.horizontal, 0).padding(.bottom, 24)
                    }
                }
                .refreshable { await performRefresh() }
            }
            .overlay(alignment: .topTrailing) {
                if let menu {
                    ZStack(alignment: .topTrailing) {
                        Color.clear.contentShape(Rectangle()).onTapGesture { self.menu = nil }
                            .accessibilityLabel("关闭菜单").accessibilityIdentifier("shelf.dismissMenu")
                        menuPanel(menu)
                            .frame(width: min(230, geometry.size.width - 32))
                            .padding(.top, 68).padding(.trailing, 10)
                    }
                }
            }
        }
        .foregroundStyle(palette.primary)
        .background { AppThemeCanvas().ignoresSafeArea() }
        .toolbar(.hidden, for: .navigationBar)
        .confirmationDialog("移除选中的 \(selectedBooks.count) 本书？本地书籍文件也会删除。", isPresented: $confirmRemoval, titleVisibility: .visible) {
            Button("移除书籍", role: .destructive) {
                onRemove(selectedBooks); selection.removeAll(); selecting = false
            }
            Button("取消", role: .cancel) {}
        }
        .onChange(of: books.map(\.id)) { ids in selection.formIntersection(Set(ids)) }
    }

    /// 下拉刷新：同一时间只跑一次；先显示「正在更新…」，完成后换成结果文案并自动消失。
    /// 这里不检查 Task.isCancelled：下拉控件的任务可能在收起时被取消，而结果提示仍应显示。
    @MainActor
    private func performRefresh() async {
        if refreshing { return }
        refreshing = true
        defer { refreshing = false }
        showRefreshStatus("正在更新…", autoHide: false)
        let message = await onRefresh()
        showRefreshStatus(message ?? "已更新", autoHide: true)
    }

    @MainActor
    private func showRefreshStatus(_ text: String, autoHide: Bool) {
        refreshStatus = text
        statusTask?.cancel()
        statusTask = nil
        guard autoHide else { return }
        statusTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            withAnimation(.easeOut(duration: 0.25)) { refreshStatus = nil }
        }
    }

    /// 分类胶囊水平居中显示；更多按钮固定在右侧。
    private var header: some View {
        ZStack {
            Button { menu = menu == "filter" ? nil : "filter" } label: {
                HStack(spacing: 7) { Text(filter.rawValue).appFont(.system(size: 16, weight: .semibold)); Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(palette.secondary) }
                    .padding(.horizontal, 17).frame(height: 42)
            }.modifier(ShelfGlass(shape: Capsule())).accessibilityLabel("分类：" + filter.rawValue).accessibilityIdentifier("shelf.filter")
            HStack {
                Spacer()
                Button { menu = menu == "main" ? nil : "main" } label: { Image(systemName: "ellipsis").font(.system(size: 22, weight: .bold)).frame(width: 44, height: 44) }
                    .modifier(ShelfGlass(shape: Circle())).accessibilityLabel("更多").accessibilityIdentifier("shelf.more")
            }
        }.buttonStyle(.plain).foregroundStyle(palette.primary).padding(.horizontal, 16).padding(.top, 6)
    }

    private var selectionBar: some View {
        HStack {
            Button(selection.count == visibleBooks.count && !visibleBooks.isEmpty ? "取消全选" : "全选") {
                if selection.count == visibleBooks.count { selection.removeAll() }
                else { selection = Set(visibleBooks.map(\.id)) }
            }.accessibilityIdentifier("shelf.selectAll")
            Spacer()
            Button("移除（\(selectedBooks.count)）", role: .destructive) { confirmRemoval = true }
                .foregroundStyle(.red)
                .disabled(selectedBooks.isEmpty).accessibilityIdentifier("shelf.removeSelected")
            Button("完成") { selecting = false; selection.removeAll() }.padding(.leading, 10).accessibilityIdentifier("shelf.finishSelection")
        }.appFont(.subheadline).padding(.horizontal, 24)
    }

    private func bookButton(_ book: Book, grid: Bool, coverWidth: CGFloat? = nil) -> some View {
        Button {
            if selecting {
                if selection.contains(book.id) { selection.remove(book.id) } else { selection.insert(book.id) }
            } else { onOpen(book) }
        } label: {
            ShelfBookCard(book: book, grid: grid, selecting: selecting, selected: selection.contains(book.id), coverWidth: coverWidth)
        }.buttonStyle(.plain)
        .accessibilityLabel(book.name + "，" + ShelfBooks.subtitle(book))
        .accessibilityValue(selecting ? (selection.contains(book.id) ? "已选择" : "未选择") : "打开阅读")
        .accessibilityIdentifier("shelf.book." + book.id)
        .contextMenu {
            Button { onOpen(book) } label: { Label("开始阅读", systemImage: "book") }
            Button { selecting = true; selection.insert(book.id) } label: { Label("选择书籍", systemImage: "checkmark.circle") }
        }
    }

    private func menuPanel(_ page: String) -> some View {
        VStack(spacing: 0) {
            if page == "main" {
                menuRow("选择书籍", icon: "checkmark.circle", id: "shelf.select") {
                    selecting = true; selection.removeAll(); menu = nil
                }
                menuRow("导入书籍", icon: "plus", id: "shelf.import") { menu = nil; onImport() }
                Divider().padding(.horizontal, 9).padding(.vertical, 6)
                menuRow("视图", detail: layout.rawValue, id: "shelf.view") { menu = "layout" }
                menuRow("排序", detail: sort.rawValue, id: "shelf.sort") { menu = "sort" }
            } else {
                if page != "filter" {
                    menuRow("返回", icon: "chevron.left", id: "shelf.menuBack") { menu = "main" }
                    Divider().padding(.horizontal, 9)
                }
                if page == "layout" {
                    ForEach(ShelfLayout.allCases, id: \.rawValue) { value in
                        choiceRow(value.rawValue, selected: value == layout, id: "shelf.layout." + (value == .grid ? "grid" : "list")) { layoutValue = value.rawValue; menu = nil }
                    }
                } else if page == "sort" {
                    ForEach(ShelfSort.allCases, id: \.rawValue) { value in
                        choiceRow(value.rawValue, selected: value == sort, id: "shelf.sort." + (value == .recent ? "recent" : value == .added ? "added" : "title")) { sortValue = value.rawValue; menu = nil }
                    }
                } else {
                    ForEach(ShelfFilter.allCases, id: \.rawValue) { value in
                        choiceRow(value.rawValue, selected: value == filter, id: "shelf.filter." + (value == .all ? "all" : value == .reading ? "reading" : value == .unread ? "unread" : "local")) { filter = value; selection.removeAll(); menu = nil }
                    }
                }
            }
        }
        .padding(9)
        .foregroundStyle(palette.primary).buttonStyle(.plain)
        .modifier(ShelfGlass(shape: RoundedRectangle(cornerRadius: 32, style: .continuous)))
    }

    private func menuRow(_ title: String, icon: String? = nil, detail: String? = nil, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 11) {
                if let icon { Image(systemName: icon).font(.system(size: 19, weight: .medium)).foregroundStyle(palette.accent).frame(width: 22) }
                Text(title).appFont(.system(size: 16))
                Spacer(minLength: 5)
                if let detail { Text(detail).appFont(.system(size: 14)).foregroundStyle(palette.secondary).lineLimit(1); Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(palette.secondary) }
            }.padding(.horizontal, 10).frame(minHeight: 44).contentShape(Rectangle())
        }.accessibilityIdentifier(id)
    }
    private func choiceRow(_ title: String, selected: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack { Text(title); Spacer(); if selected { Image(systemName: "checkmark").foregroundStyle(palette.accent) } }
                .padding(.horizontal, 12).frame(minHeight: 44).contentShape(Rectangle())
        }.accessibilityValue(selected ? "已选择" : "未选择").accessibilityIdentifier(id)
    }
}

private struct ShelfMenuPointer: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: 0, y: rect.maxY))
            p.addQuadCurve(to: CGPoint(x: rect.midX, y: 0), control: CGPoint(x: rect.midX * 0.7, y: rect.maxY * 0.3))
            p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY), control: CGPoint(x: rect.midX * 1.3, y: rect.maxY * 0.3))
            p.closeSubpath()
        }
    }
}

struct ShelfBookCard: View {
    @ThemePalette private var palette
    @Environment(\.appTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    let book: Book
    let grid: Bool
    let selecting: Bool
    let selected: Bool
    var coverWidth: CGFloat? = nil
    private var accessibleCustom: Bool { theme.customization != nil && typeSize.isAccessibilitySize }
    var body: some View {
        Group {
            if grid {
                VStack(spacing: 6) {
                    gridCover
                    VStack(spacing: 2) {
                        Text(book.name)
                            .appFont(accessibleCustom ? .headline : .system(size: 13, weight: .semibold))
                            .lineLimit(accessibleCustom ? nil : 2)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(ShelfListSummary.authorName(book))
                            .appFont(accessibleCustom ? .subheadline : .system(size: 11))
                            .foregroundStyle(palette.secondary)
                            .lineLimit(accessibleCustom ? nil : 1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }.fixedSize(horizontal: false, vertical: accessibleCustom)
                }
            } else {
                ShelfListRow(book: book, localOrigin: "local", summary: ShelfListSummary(book: book),
                             selecting: selecting, selected: selected)
            }
        }.foregroundStyle(palette.primary)
    }
    @ViewBuilder private var gridCover: some View {
        if let coverWidth { cover.frame(width: coverWidth, height: coverWidth / 0.70) }
        else { cover.aspectRatio(0.70, contentMode: .fit) }
    }
    private var cover: some View {
        ShelfCoverImage(url: BookCoverLocation.url(for: book))
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .shadow(color: .black.opacity(0.16), radius: 8, x: 0, y: 5)
            .overlay(alignment: .topTrailing) {
                if selecting {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22)).foregroundStyle(selected ? palette.accent : palette.primary)
                        .background(Circle().fill(palette.surface)).padding(7)
                }
            }
    }
}

struct ShelfCoverImage: View {
    let url: URL?
    var body: some View { BookCoverImage(url: url) }
}
