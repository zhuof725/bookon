import SwiftUI

struct LibraryStatisticsView: View {
    @EnvironmentObject var store: AppStore
    private var started: Int { store.books.filter(ShelfBooks.isStarted).count }
    var body: some View {
        List {
            Section("书库概览") {
                LabeledContent("书架书籍", value: "\(store.books.count) 本")
                LabeledContent("已开始阅读", value: "\(started) 本")
                LabeledContent("未读", value: "\(store.books.count - started) 本")
                LabeledContent("本地书籍", value: "\(store.books.filter { store.isLocal($0) }.count) 本")
            }
            Section("最近阅读") {
                let recent = store.books.filter(ShelfBooks.isStarted).sorted { $0.lastReadAt > $1.lastReadAt }
                if recent.isEmpty { Text("暂无阅读记录").foregroundStyle(.secondary) }
                ForEach(Array(recent.prefix(10))) { book in
                    NavigationLink { ReaderView(book: book) } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(book.name)
                            Text(book.durChapterTitle ?? "阅读中").font(.caption).foregroundStyle(.secondary)
                            Text(book.lastReadAt, style: .date).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section { Text("统计来自书架与已保存的阅读进度；尚未记录阅读时长。").font(.footnote).foregroundStyle(.secondary) }
        }
        .scrollContentBackground(.hidden)
        .background(AppPalette.background.ignoresSafeArea())
        .navigationTitle("统计")
        .toolbar(.visible, for: .navigationBar)
    }
}

struct LibraryProfileView: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        List {
            Section("书库管理") {
                NavigationLink { SourcesView() } label: { Label("书源管理", systemImage: "square.stack.3d.up") }
                    .accessibilityIdentifier("library.sources")
                NavigationLink { SearchView() } label: { Label("搜索书籍", systemImage: "magnifyingglass") }
            }
            Section("本机数据") {
                LabeledContent("已导入书源", value: "\(store.sources.count) 个")
                LabeledContent("书架书籍", value: "\(store.books.count) 本")
            }
            Section { Text("阅读进度、导入书源与本地书籍保存在本机。").foregroundStyle(.secondary).font(.footnote) }
        }
        .scrollContentBackground(.hidden)
        .background(AppPalette.background.ignoresSafeArea())
        .navigationTitle("我的")
        .toolbar(.visible, for: .navigationBar)
    }
}
