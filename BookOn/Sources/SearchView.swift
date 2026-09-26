import SwiftUI

@MainActor
final class SearchModel: ObservableObject {
    @Published var results: [SearchBook] = []
    @Published var searching = false
    @Published var finished = 0
    @Published var total = 0
    @Published var errors: [String] = []
    private var task: Task<Void, Never>?

    func search(_ key: String) {
        cancel()
        let sources = SourceStore.shared.enabledSources.filter { !$0.searchUrl.isEmpty }
        results = []; errors = []; finished = 0; total = sources.count
        guard !key.isEmpty, !sources.isEmpty else { return }
        searching = true
        task = Task {
            let batches = stride(from: 0, to: sources.count, by: 8).map { Array(sources[$0..<min($0 + 8, sources.count)]) }
            for batch in batches {
                if Task.isCancelled { break }
                await withTaskGroup(of: (BookSource, Result<[SearchBook], Error>).self) { group in
                    for s in batch {
                        group.addTask { (s, await Result.capture { try await WebBook.search(s, key: key) }) }
                    }
                    for await (s, r) in group {
                        switch r {
                        case .success(let list):
                            let filtered = list.filter { $0.name.localizedCaseInsensitiveContains(key) || $0.author.localizedCaseInsensitiveContains(key) }
                            merge(filtered.isEmpty ? list : filtered)
                        case .failure(let e):
                            errors.append("\(s.bookSourceName): \(e.localizedDescription)")
                        }
                        finished += 1
                    }
                }
            }
            searching = false
        }
    }

    private func merge(_ list: [SearchBook]) {
        for b in list where !results.contains(where: { $0.id == b.id }) {
            results.append(b)
        }
    }

    func cancel() { task?.cancel(); task = nil; searching = false }
}

extension Result where Failure == Error {
    static func capture(_ body: () async throws -> Success) async -> Result<Success, Error> {
        do { return .success(try await body()) } catch { return .failure(error) }
    }
}

struct SearchView: View {
    @StateObject private var model = SearchModel()
    @ObservedObject private var store = SourceStore.shared
    @State private var key = ""
    @State private var selected: SearchBook?
    @FocusState private var focused: Bool

    /// 按 书名+作者 聚合
    private var grouped: [(key: String, books: [SearchBook])] {
        var order: [String] = []; var map: [String: [SearchBook]] = [:]
        for b in model.results {
            let k = b.name + "|" + b.author
            if map[k] == nil { order.append(k) }
            map[k, default: []].append(b)
        }
        return order.map { ($0, map[$0]!) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("书名 / 作者", text: $key)
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.search)
                    .focused($focused)
                    .onSubmit { model.search(key) }
                if model.searching { Button("停止") { model.cancel() } }
                else { Button("搜索") { model.search(key) }.disabled(key.isEmpty) }
            }.padding()

            if store.enabledSources.isEmpty {
                VStack(spacing: 8) {
                    Text("没有可用书源").font(.headline)
                    NavigationLink("去导入书源") { SourceListView() }
                }.frame(maxHeight: .infinity)
            } else if model.results.isEmpty && !model.searching && model.total > 0 {
                VStack(spacing: 8) {
                    Text("没有搜到").font(.headline)
                    if !model.errors.isEmpty {
                        Text("\(model.errors.count) 个书源出错").font(.footnote).foregroundColor(.secondary)
                    }
                }.frame(maxHeight: .infinity)
            } else {
                List {
                    if model.searching || model.total > 0 {
                        HStack {
                            if model.searching { ProgressView().scaleEffect(0.8) }
                            Text("\(model.finished)/\(model.total) 书源 · \(model.results.count) 结果").font(.caption).foregroundColor(.secondary)
                        }.listRowSeparator(.hidden)
                    }
                    ForEach(grouped, id: \.key) { g in
                        Button { selected = g.books[0] } label: {
                            SearchRow(book: g.books[0], sourceCount: g.books.count)
                        }.buttonStyle(.plain)
                    }
                }.listStyle(.plain)
            }
        }
        .navigationTitle("搜索")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if model.results.isEmpty { focused = true } }
        .sheet(item: $selected) { b in
            NavigationView { BookDetailView(book: b, alternatives: grouped.first { $0.books.contains(b) }?.books ?? [b]) }
        }
    }
}

struct SearchRow: View {
    let book: SearchBook
    let sourceCount: Int
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CoverView(url: book.coverUrl, title: book.name).frame(width: 56, height: 76)
            VStack(alignment: .leading, spacing: 4) {
                Text(book.name).font(.body).bold().lineLimit(1)
                Text(book.author.isEmpty ? "未知作者" : book.author).font(.caption).foregroundColor(.secondary)
                if !book.kind.isEmpty { Text(book.kind).font(.caption2).foregroundColor(.accentColor).lineLimit(1) }
                if !book.lastChapter.isEmpty { Text("最新：\(book.lastChapter)").font(.caption).foregroundColor(.secondary).lineLimit(1) }
                Text("\(sourceCount) 个书源").font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
        }.padding(.vertical, 4)
    }
}

struct CoverView: View {
    let url: String
    let title: String
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(LinearGradient(colors: [Color(red: 0.1, green: 0.6, blue: 0.65), Color(red: 0.1, green: 0.3, blue: 0.6)], startPoint: .top, endPoint: .bottom))
            Text(String(title.prefix(2))).font(.headline).foregroundColor(.white)
            if let u = URL(string: url), !url.isEmpty {
                AsyncImage(url: u) { img in img.resizable().aspectRatio(contentMode: .fill) } placeholder: { Color.clear }
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
    }
}
