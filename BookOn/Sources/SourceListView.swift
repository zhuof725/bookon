import SwiftUI

struct SourceListView: View {
    @ObservedObject private var store = SourceStore.shared
    @State private var showImport = false
    @State private var importText = ""
    @State private var importing = false
    @State private var message: String?
    @State private var showPicker = false
    @State private var search = ""

    private var filtered: [BookSource] {
        search.isEmpty ? store.sources : store.sources.filter { $0.bookSourceName.localizedCaseInsensitiveContains(search) || $0.bookSourceUrl.localizedCaseInsensitiveContains(search) || $0.bookSourceGroup.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        List {
            if store.sources.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "globe").font(.system(size: 48)).foregroundColor(.secondary)
                    Text("还没有书源").font(.headline)
                    Text("支持 Legado（阅读）格式的书源 JSON\n可从网址导入、粘贴 JSON，或从文件导入\n点击书源可进入调试").font(.footnote).foregroundColor(.secondary).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity).padding(.vertical, 40).listRowSeparator(.hidden)
            }
            ForEach(filtered) { s in
                NavigationLink { SourceDebugView(source: s) } label: { HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(s.bookSourceName).font(.body)
                        Text(s.bookSourceUrl).font(.caption).foregroundColor(.secondary).lineLimit(1)
                        if !s.bookSourceGroup.isEmpty { Text(s.bookSourceGroup).font(.caption2).foregroundColor(.accentColor) }
                    }
                    Spacer()
                    Toggle("", isOn: Binding(get: { s.enabled }, set: { _ in store.toggle(s) })).labelsHidden()
                } }
            }
            .onDelete { idx in idx.map { filtered[$0] }.forEach(store.delete) }
        }
        .listStyle(.plain)
        .searchable(text: $search, prompt: "搜索书源")
        .navigationTitle("书源（\(store.sources.count)）")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button { showImport = true } label: { Label("网址 / 粘贴导入", systemImage: "link") }
                    Button { showPicker = true } label: { Label("从文件导入", systemImage: "doc") }
                    if !store.sources.isEmpty {
                        Button(role: .destructive) { store.deleteAll() } label: { Label("清空全部", systemImage: "trash") }
                    }
                } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showImport) { importSheet }
        .sheet(isPresented: $showPicker) {
            DocumentPicker(types: ["json", "txt"]) { urls in
                var a = 0, u = 0
                for url in urls {
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    if let d = try? Data(contentsOf: url) {
                        let r = store.importJSON(TxtParser.decode(d)); a += r.added; u += r.updated
                    }
                }
                message = "新增 \(a) 个，更新 \(u) 个"
            }.ignoresSafeArea()
        }
        .alert("导入结果", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("好", role: .cancel) {}
        } message: { Text(message ?? "") }
    }

    private var importSheet: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 12) {
                Text("粘贴书源网址（http 开头）或书源 JSON 内容").font(.footnote).foregroundColor(.secondary)
                TextEditor(text: $importText)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(minHeight: 200)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3)))
                if let clip = UIPasteboard.general.string, !clip.isEmpty, importText.isEmpty {
                    Button { importText = clip } label: { Label("使用剪贴板内容", systemImage: "doc.on.clipboard") }
                }
                Spacer()
            }
            .padding()
            .navigationTitle("导入书源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { showImport = false } }
                ToolbarItem(placement: .confirmationAction) {
                    if importing { ProgressView() } else { Button("导入") { doImport() }.disabled(importText.trimmingCharacters(in: .whitespaces).isEmpty) }
                }
            }
        }
    }

    private func doImport() {
        let t = importText.trimmingCharacters(in: .whitespacesAndNewlines)
        importing = true
        Task {
            var result: (added: Int, updated: Int)
            var err: String?
            if t.lowercased().hasPrefix("http") {
                do { result = try await store.importFromURL(t) } catch { result = (0, 0); err = error.localizedDescription }
            } else {
                result = store.importJSON(t)
                if result.added + result.updated == 0 { err = "未识别到有效书源，请检查 JSON 格式" }
            }
            await MainActor.run {
                importing = false
                showImport = false
                importText = ""
                message = err ?? "新增 \(result.added) 个，更新 \(result.updated) 个"
            }
        }
    }
}
