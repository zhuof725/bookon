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
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        content.background {
            ZStack {
                if reduceTransparency { shape.fill(AppPalette.surface) }
                else {
                    shape.fill(.ultraThinMaterial)
                    shape.fill(AppPalette.surface.opacity(scheme == .dark ? 0.15 : 0.65))
                }
                shape.strokeBorder(Color.primary.opacity(0.13), lineWidth: 0.5)
            }.allowsHitTesting(false)
        }
    }
}

/// Independent from AppStore: the production screen and offline UI fixture share
/// exactly the same card/menu code. Only callbacks may mutate the user's library.
struct BookshelfScreen: View {
    let books: [Book]
    let localOrigin: String
    let onOpen: (Book) -> Void
    let onSearch: () -> Void
    let onImport: () -> Void
    let onRemove: ([Book]) -> Void
    @AppStorage("shelf.layout.v1") private var layoutValue = ShelfLayout.grid.rawValue
    @AppStorage("shelf.sort.v1") private var sortValue = ShelfSort.recent.rawValue
    @State private var filter: ShelfFilter = .all
    @State private var selecting = false
    @State private var selection: Set<String> = []
    @State private var menu: String?
    @State private var confirmRemoval = false
    @Environment(\.dynamicTypeSize) private var typeSize

    private var layout: ShelfLayout { ShelfLayout(rawValue: layoutValue) ?? .grid }
    private var sort: ShelfSort { ShelfSort(rawValue: sortValue) ?? .recent }
    private var visibleBooks: [Book] { ShelfBooks.visible(books, filter: filter, sort: sort, localOrigin: localOrigin) }
    private var selectedBooks: [Book] { books.filter { selection.contains($0.id) } }

    var body: some View {
        GeometryReader { geometry in
            let columns = typeSize.isAccessibilitySize ? 2 : max(3, Int((geometry.size.width - 48) / 124))
            VStack(spacing: 14) {
                header
                if selecting { selectionBar }
                ScrollView {
                    if visibleBooks.isEmpty {
                        VStack(spacing: 14) {
                            Image(systemName: "books.vertical").font(.system(size: 36)).foregroundStyle(.secondary)
                            Text(books.isEmpty ? "书架是空的" : "这个分类暂无书籍").font(.headline)
                            Text(books.isEmpty ? "点击左上角搜索，或在右上角菜单导入 TXT / EPUB。" : "试试切换到「全部」。")
                                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }.padding(36).padding(.top, 70).frame(maxWidth: .infinity)
                        .accessibilityIdentifier("shelf.empty")
                    } else if layout == .grid {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 18), count: columns), alignment: .leading, spacing: 22) {
                            ForEach(visibleBooks) { book in bookButton(book, grid: true) }
                        }.padding(.horizontal, 24).padding(.top, 2).padding(.bottom, 24)
                    } else {
                        LazyVStack(spacing: 14) {
                            ForEach(visibleBooks) { book in bookButton(book, grid: false) }
                        }.padding(.horizontal, 24).padding(.bottom, 24)
                    }
                }
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
        .background(AppPalette.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .confirmationDialog("移除选中的 \(selectedBooks.count) 本书？本地书籍文件也会删除。", isPresented: $confirmRemoval, titleVisibility: .visible) {
            Button("移除书籍", role: .destructive) {
                onRemove(selectedBooks); selection.removeAll(); selecting = false
            }
            Button("取消", role: .cancel) {}
        }
        .onChange(of: books.map(\.id)) { ids in selection.formIntersection(Set(ids)) }
    }

    private var header: some View {
        HStack {
            Button(action: onSearch) { Image(systemName: "magnifyingglass").font(.system(size: 21, weight: .medium)).frame(width: 44, height: 44) }
                .modifier(ShelfGlass(shape: Circle())).accessibilityLabel("搜索书籍").accessibilityIdentifier("shelf.search")
            Spacer()
            Button { menu = menu == "filter" ? nil : "filter" } label: {
                HStack(spacing: 7) { Text(filter.rawValue).font(.system(size: 16, weight: .semibold)); Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary) }
                    .padding(.horizontal, 17).frame(height: 42)
            }.modifier(ShelfGlass(shape: Capsule())).accessibilityLabel("分类：" + filter.rawValue).accessibilityIdentifier("shelf.filter")
            Spacer()
            Button { menu = menu == "main" ? nil : "main" } label: { Image(systemName: "ellipsis").font(.system(size: 22, weight: .bold)).frame(width: 44, height: 44) }
                .modifier(ShelfGlass(shape: Circle())).accessibilityLabel("更多").accessibilityIdentifier("shelf.more")
        }.buttonStyle(.plain).foregroundStyle(.primary).padding(.horizontal, 16).padding(.top, 6)
    }

    private var selectionBar: some View {
        HStack {
            Button(selection.count == visibleBooks.count && !visibleBooks.isEmpty ? "取消全选" : "全选") {
                if selection.count == visibleBooks.count { selection.removeAll() }
                else { selection = Set(visibleBooks.map(\.id)) }
            }.accessibilityIdentifier("shelf.selectAll")
            Spacer()
            Button("移除（\(selectedBooks.count)）", role: .destructive) { confirmRemoval = true }
                .disabled(selectedBooks.isEmpty).accessibilityIdentifier("shelf.removeSelected")
            Button("完成") { selecting = false; selection.removeAll() }.padding(.leading, 10).accessibilityIdentifier("shelf.finishSelection")
        }.font(.subheadline).padding(.horizontal, 24)
    }

    private func bookButton(_ book: Book, grid: Bool) -> some View {
        Button {
            if selecting {
                if selection.contains(book.id) { selection.remove(book.id) } else { selection.insert(book.id) }
            } else { onOpen(book) }
        } label: {
            ShelfBookCard(book: book, grid: grid, selecting: selecting, selected: selection.contains(book.id))
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
        .foregroundStyle(.primary).buttonStyle(.plain)
        .background {
            RoundedRectangle(cornerRadius: 32, style: .continuous).fill(.regularMaterial)
                .overlay { RoundedRectangle(cornerRadius: 32, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5) }
                .shadow(color: .black.opacity(0.13), radius: 16, x: 0, y: 12)
        }
        .overlay(alignment: .topTrailing) {
            if page != "filter" {
                ShelfMenuPointer().fill(.regularMaterial).frame(width: 25, height: 14).offset(x: -15, y: -13)
                    .allowsHitTesting(false)
            }
        }
    }

    private func menuRow(_ title: String, icon: String? = nil, detail: String? = nil, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 11) {
                if let icon { Image(systemName: icon).font(.system(size: 19, weight: .medium)).foregroundStyle(AppPalette.accent).frame(width: 22) }
                Text(title).font(.system(size: 16))
                Spacer(minLength: 5)
                if let detail { Text(detail).font(.system(size: 14)).foregroundStyle(.secondary).lineLimit(1); Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary) }
            }.padding(.horizontal, 10).frame(minHeight: 44).contentShape(Rectangle())
        }.accessibilityIdentifier(id)
    }
    private func choiceRow(_ title: String, selected: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack { Text(title); Spacer(); if selected { Image(systemName: "checkmark").foregroundStyle(AppPalette.accent) } }
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
    let book: Book
    let grid: Bool
    let selecting: Bool
    let selected: Bool
    var body: some View {
        Group {
            if grid {
                VStack(spacing: 8) {
                    cover.aspectRatio(0.70, contentMode: .fit)
                    VStack(spacing: 3) {
                        Text(book.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        Text(ShelfBooks.subtitle(book)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }.frame(maxWidth: .infinity).padding(.horizontal, 7).padding(.vertical, 6)
                        .modifier(ShelfGlass(shape: RoundedRectangle(cornerRadius: 13, style: .continuous)))
                }
            } else {
                HStack(spacing: 14) {
                    cover.frame(width: 62, height: 88)
                    VStack(alignment: .leading, spacing: 7) {
                        Text(book.name).font(.headline).lineLimit(2)
                        Text(ShelfBooks.subtitle(book)).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }.padding(10).modifier(ShelfGlass(shape: RoundedRectangle(cornerRadius: 18)))
            }
        }.foregroundStyle(.primary)
    }
    private var cover: some View {
        ShelfCoverImage(url: book.coverUrl.flatMap(URL.init(string:)))
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .shadow(color: .black.opacity(0.16), radius: 8, x: 0, y: 5)
            .overlay(alignment: .topTrailing) {
                if selecting {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22)).foregroundStyle(selected ? AppPalette.accent : Color.white)
                        .background(Circle().fill(Color.black.opacity(0.35))).padding(7)
                }
            }
    }
}

struct ShelfCoverImage: View {
    let url: URL?
    @State private var localImage: UIImage?
    var body: some View {
        GeometryReader { geometry in
            Group {
                if let url, url.isFileURL {
                    if let localImage { Image(uiImage: localImage).resizable().scaledToFill() } else { placeholder }
                } else if let url, ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image { image.resizable().scaledToFill() } else { placeholder }
                    }
                } else { placeholder }
            }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }
        .task(id: url) {
            localImage = nil
            guard let url, url.isFileURL else { return }
            let data = await Task.detached(priority: .utility) { try? Data(contentsOf: url) }.value
            guard !Task.isCancelled, let data, let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 600] as CFDictionary) else { return }
            localImage = UIImage(cgImage: cgImage)
        }
        .accessibilityHidden(true)
    }
    private var placeholder: some View {
        ZStack {
            LinearGradient(colors: [AppPalette.placeholderTop, AppPalette.placeholderBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: "book.closed").font(.system(size: 26, weight: .light)).foregroundStyle(.white.opacity(0.55))
        }
    }
}
