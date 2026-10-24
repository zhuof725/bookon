import SwiftUI

/// 书源内搜索的请求（首页板块的「搜索」控件用）。
struct SourceSearchRequest: Identifiable, Hashable {
    let id = UUID()
    let key: String
}

/// 书源内搜索的结果页（首页板块的「搜索」控件跳转过来）。
struct DiscoverSourceSearchView: View {
    @ThemePalette private var palette
    let source: BookSource
    let key: String

    @State private var books: [Book] = []
    @State private var loading = true
    @State private var errorText: String?

    var body: some View {
        List {
            if loading {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("正在搜索「\(key)」…").appFont(.footnote).foregroundStyle(palette.secondary)
                }
                .independentGlassRow()
            } else if let errorText {
                VStack(alignment: .leading, spacing: 8) {
                    Text(errorText).appFont(.footnote).foregroundStyle(palette.secondary)
                    Button("重试") { Task { await run() } }
                        .appFont(.footnote.weight(.semibold))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .independentGlassRow()
            } else if books.isEmpty {
                Text("没有搜到相关书籍").appFont(.footnote).foregroundStyle(palette.secondary)
                    .independentGlassRow()
            } else {
                ForEach(books) { book in
                    NavigationLink {
                        BookDetailView(book: book)
                    } label: {
                        BookRow(book: book, subtitle: "来源：\(source.bookSourceName)")
                    }
                    .independentGlassRow()
                }
            }
        }
        .scrollContentBackground(.hidden)
        .foregroundStyle(palette.primary)
        .background { AppThemeCanvas().ignoresSafeArea() }
        .navigationTitle(key)
        .navigationBarTitleDisplayMode(.inline)
        .task { await run() }
    }

    private func run() async {
        loading = true
        errorText = nil
        let src = source
        do {
            books = try await WebBook.search(source: src, key: key)
        } catch {
            errorText = "搜索失败：\(error)"
        }
        loading = false
    }
}
