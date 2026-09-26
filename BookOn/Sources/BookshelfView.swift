import SwiftUI

struct BookshelfView: View {
    @ObservedObject private var library = Library.shared
    @State private var showPicker = false
    @State private var importMessage: String?
    @State private var openBook: Book?

    var body: some View {
        NavigationView {
            Group {
                if library.books.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(library.books) { book in
                            Button { openBook = book } label: { BookRow(book: book) }
                                .buttonStyle(.plain)
                        }
                        .onDelete { idx in idx.map { library.books[$0] }.forEach(library.delete) }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("书架")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showPicker = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showPicker) {
                DocumentPicker { urls in importFiles(urls) }
                    .ignoresSafeArea()
            }
            .fullScreenCover(item: $openBook) { book in
                ReaderView(book: book)
            }
            .alert("导入结果", isPresented: Binding(get: { importMessage != nil },
                                                 set: { if !$0 { importMessage = nil } })) {
                Button("好", role: .cancel) {}
            } message: { Text(importMessage ?? "") }
        }
        .navigationViewStyle(.stack)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "book.closed").font(.system(size: 64)).foregroundColor(.secondary)
            Text("书架空空如也").font(.headline)
            Text("点击右上角 + 导入本地 TXT").font(.subheadline).foregroundColor(.secondary)
            Button { showPicker = true } label: {
                Label("导入 TXT", systemImage: "doc.badge.plus")
                    .padding(.horizontal, 20).padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private func importFiles(_ urls: [URL]) {
        var ok = 0, fails: [String] = []
        for url in urls {
            do { _ = try library.importTxt(from: url); ok += 1 }
            catch { fails.append("\(url.lastPathComponent)：\(error.localizedDescription)") }
        }
        if !fails.isEmpty {
            importMessage = "成功 \(ok) 本\n失败：\n" + fails.joined(separator: "\n")
        }
    }
}

struct BookRow: View {
    let book: Book
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .fill(LinearGradient(colors: [Color(red: 0.1, green: 0.6, blue: 0.65), Color(red: 0.1, green: 0.3, blue: 0.6)],
                                         startPoint: .top, endPoint: .bottom))
                Text(String(book.title.prefix(2)))
                    .font(.headline).foregroundColor(.white)
            }
            .frame(width: 48, height: 64)
            VStack(alignment: .leading, spacing: 4) {
                Text(book.title).font(.body).lineLimit(1)
                Text(book.author.isEmpty ? "TXT · 共 \(book.chapterCount) 章" : "\(book.author) · 共 \(book.chapterCount) 章")
                    .font(.caption).foregroundColor(.secondary)
                Text(book.progressText).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundColor(Color(.tertiaryLabel))
        }
        .padding(.vertical, 4)
    }
}
