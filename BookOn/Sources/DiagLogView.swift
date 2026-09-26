import SwiftUI

struct DiagLogView: View {
    @ObservedObject private var log = DiagLog.shared
    @State private var filter = ""
    @State private var onlyProblems = false
    @State private var shareText: String?

    private var shown: [DiagLog.Entry] {
        log.entries.filter { e in
            (!onlyProblems || e.level == .error || e.level == .warn) &&
            (filter.isEmpty || e.message.localizedCaseInsensitiveContains(filter) || e.tag.localizedCaseInsensitiveContains(filter))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Toggle("只看问题", isOn: $onlyProblems).toggleStyle(.button).font(.footnote)
                Spacer()
                Text("\(shown.count) 条").font(.caption).foregroundColor(.secondary)
            }.padding(.horizontal).padding(.vertical, 6)
            ScrollViewReader { proxy in
                List(shown) { e in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(e.level.rawValue)
                            Text(e.tag).font(.caption).bold()
                            Text(e.time, format: .dateTime.hour().minute().second()).font(.caption2).foregroundColor(.secondary)
                        }
                        Text(e.message).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    }
                    .id(e.id)
                    .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                }
                .listStyle(.plain)
                .onChange(of: log.entries.count) { _ in
                    if let last = shown.last { withAnimation(nil) { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }
        }
        .searchable(text: $filter, prompt: "过滤")
        .navigationTitle("诊断日志")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button { UIPasteboard.general.string = log.exportText } label: { Label("复制全部", systemImage: "doc.on.doc") }
                    Button { shareText = log.exportText } label: { Label("分享 / 保存文件", systemImage: "square.and.arrow.up") }
                    Button(role: .destructive) { log.clear() } label: { Label("清空", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .sheet(item: Binding(get: { shareText.map { ShareItem(text: $0) } }, set: { _ in shareText = nil })) { item in
            ShareSheet(items: [item.fileURL ?? item.text])
        }
    }
}

struct ShareItem: Identifiable {
    let id = UUID()
    let text: String
    var fileURL: URL? {
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("bookon-log-\(f.string(from: Date())).txt")
        return (try? text.write(to: url, atomically: true, encoding: .utf8)) != nil ? url : nil
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// MARK: - 书源调试（类似 Legado 的书源调试：输入关键词，跑完搜索→详情→目录→正文）

struct SourceDebugView: View {
    let source: BookSource
    @State private var key = "我的"
    @State private var running = false
    @State private var report: [String] = []
    @State private var showLog = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("搜索关键词 或 书籍/目录/正文网址", text: $key).textFieldStyle(.roundedBorder)
                Button(running ? "运行中…" : "开始") { run() }.disabled(running || key.isEmpty)
            }.padding()
            List {
                ForEach(Array(report.enumerated()), id: \.offset) { _, line in
                    Text(line).font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
                }
            }.listStyle(.plain)
            Button { showLog = true } label: { Label("查看完整诊断日志", systemImage: "doc.text.magnifyingglass") }.padding()
        }
        .navigationTitle("调试：\(source.bookSourceName)")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showLog) { NavigationView { DiagLogView() } }
    }

    private func add(_ s: String) { DispatchQueue.main.async { report.append(s) } }

    private func run() {
        running = true; report = []
        DiagLog.shared.clear()
        let k = key.trimmingCharacters(in: .whitespaces)
        Task {
            defer { Task { @MainActor in running = false } }
            do {
                var book: SearchBook
                if k.lowercased().hasPrefix("http") {
                    add("▶ 直接作为书籍地址")
                    book = SearchBook(sourceUrl: source.bookSourceUrl, sourceName: source.bookSourceName, name: "", author: "", kind: "", intro: "", lastChapter: "", coverUrl: "", bookUrl: k, wordCount: "")
                } else {
                    add("▶ 搜索「\(k)」")
                    let t0 = Date()
                    let list = try await WebBook.search(source, key: k)
                    add("  ✅ \(list.count) 条结果，耗时 \(String(format: "%.1f", Date().timeIntervalSince(t0)))s")
                    for b in list.prefix(3) { add("  · \(b.name) | \(b.author) | \(b.lastChapter)\n    \(b.bookUrl)") }
                    guard let first = list.first else { add("  ❌ 无结果，流程终止"); return }
                    book = first
                }
                add("▶ 详情")
                let info = try await WebBook.bookInfo(source, book)
                add("  ✅ \(info.name) | \(info.author) | \(info.kind)\n  封面: \(info.coverUrl)\n  目录: \(info.tocUrl)\n  简介: \(DiagLog.preview(info.intro, 100))")
                add("▶ 目录")
                let toc = try await WebBook.chapterList(source, info)
                add("  ✅ \(toc.count) 章")
                for c in toc.prefix(3) { add("  · \(c.title)\n    \(c.url)") }
                if toc.count > 3, let last = toc.last { add("  … \(last.title)\n    \(last.url)") }
                guard let ch = toc.first else { return }
                add("▶ 正文：\(ch.title)")
                let text = try await WebBook.content(source, book: info, chapter: ch, nextChapterUrl: toc.count > 1 ? toc[1].url : nil)
                add("  ✅ \(text.count) 字\n\(DiagLog.preview(text, 400))")
                add("✔ 全部完成")
            } catch {
                add("❌ 失败：\(error.localizedDescription)")
            }
        }
    }
}
