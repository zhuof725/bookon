//
//  SourceListView.swift
//  书源调试
//
//  第 7 步 C 段返工：书源列表。
//   - 点行进入该**书源专属的调试页**（NavigationStack + navigationDestination），
//     不再在调试页里选书源；
//   - 导入面板提供 4 个入口：粘贴文本 / fileImporter 选择文件 / URL 下载 / 读剪贴板；
//   - 导入后弹出结果弹窗（成功条数 + 失败原因列表 + 警告）。
//
//  业务逻辑（解析 / 计数 / 失败原因格式化）全在 BookSourceRepository 与
//  BookonDebugKit.ImportOutcomePresenter，本文件只装配界面。
//

import SwiftUI
import UniformTypeIdentifiers
import BookonDebugKit
import LegadoBookSource

struct SourceListView: View {
    @Bindable var repository: BookSourceRepository
    @Bindable var settings: DebugSettings
    let environment: SharedEnvironment
    let logStore: DebugLogStore

    @State private var showingImport = false
    @State private var importResult: ImportResultSummary?
    @State private var importError: String?

    var body: some View {
        NavigationStack {
            List {
                ForEach(repository.filteredSources, id: \.bookSourceUrl) { source in
                    NavigationLink {
                        // 调试页接收当前书源（由列表传入），页内不再选择书源。
                        DebugView(
                            repository: repository,
                            settings: settings,
                            environment: environment,
                            logStore: logStore,
                            source: source
                        )
                    } label: {
                        row(source)
                    }
                    .swipeActions {
                        Button(source.enabled ? "禁用" : "启用") {
                            repository.toggleEnabled(sourceUrl: source.bookSourceUrl)
                        }
                        .tint(source.enabled ? .orange : .green)
                    }
                }
            }
            .navigationTitle("书源")
            .searchable(text: $repository.searchText, prompt: "搜索书源")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingImport = true
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .accessibilityLabel("导入书源")
                }
            }
            .sheet(isPresented: $showingImport) {
                ImportSheet(repository: repository) { result in
                    importResult = result
                } onError: { message in
                    importError = message
                }
            }
            // 导入结果弹窗：成功数 + 失败原因列表 + 警告。
            .alert("导入完成", isPresented: Binding(
                get: { importResult != nil },
                set: { if !$0 { importResult = nil } }
            ), presenting: importResult) { _ in
                Button("好", role: .cancel) { importResult = nil }
            } message: { result in
                Text(result.detailText)
            }
            .alert("导入失败", isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            ), presenting: importError) { _ in
                Button("好", role: .cancel) { importError = nil }
            } message: { message in
                Text(message)
            }
        }
    }

    private func row(_ source: BookSource) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(source.bookSourceName)
                .font(.headline)
            Text(source.bookSourceUrl)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .opacity(source.enabled ? 1.0 : 0.4)
    }
}

/// 导入面板：4 个入口（粘贴文本 / 选文件 / URL 下载 / 读剪贴板）。
struct ImportSheet: View {
    @Bindable var repository: BookSourceRepository
    /// 成功回调（带结果摘要，供列表页弹窗）。
    var onSuccess: (ImportResultSummary) -> Void
    /// 失败回调（网络/解析等硬错误，供列表页弹窗）。
    var onError: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var remoteURL = ""
    @State private var showingFileImporter = false
    @State private var busy = false

    var body: some View {
        NavigationStack {
            Form {
                Section("方式一：粘贴 JSON 文本") {
                    TextEditor(text: $text)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 120)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Button("导入文本") { importText(text) }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Section("方式二：选择文件") {
                    Button {
                        showingFileImporter = true
                    } label: {
                        Label("选择 JSON 文件", systemImage: "folder")
                    }
                }

                Section("方式三：从 URL 下载") {
                    TextField("https://…/sources.json", text: $remoteURL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    Button("下载并导入") { downloadAndImport() }
                        .disabled(remoteURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                Section("方式四：读取剪贴板") {
                    Button {
                        importText(UIPasteboard.general.string ?? "")
                    } label: {
                        Label("从剪贴板导入", systemImage: "doc.on.clipboard")
                    }
                }

                if busy {
                    HStack { ProgressView(); Text("处理中…").foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("导入书源")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [.json, .plainText],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    readFile(url)
                case .failure(let error):
                    dismissWith(error: error.localizedDescription)
                }
            }
        }
    }

    // MARK: - 四个入口

    private func importText(_ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            dismissWith(error: "内容为空，未解析到书源")
            return
        }
        do {
            let outcome = try repository.importSourcesDetailed(jsonText: trimmed)
            finish(outcome)
        } catch {
            dismissWith(error: error.localizedDescription)
        }
    }

    private func readFile(_ url: URL) {
        // 沙箱外文件需要安全作用域访问。
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }
        do {
            let outcome = try repository.importSourcesDetailed(fileURL: url)
            finish(outcome)
        } catch {
            dismissWith(error: "读取文件失败：\(error.localizedDescription)")
        }
    }

    private func downloadAndImport() {
        let trimmed = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme?.hasPrefix("http") == true else {
            dismissWith(error: "URL 不合法：\(trimmed)")
            return
        }
        busy = true
        Task {
            do {
                let outcome = try await repository.importSourcesDetailed(url: url)
                busy = false
                finish(outcome)
            } catch {
                busy = false
                dismissWith(error: "下载失败：\(error.localizedDescription)")
            }
        }
    }

    // MARK: - 结果处理

    private func finish(_ outcome: ImportOutcome) {
        if outcome.importedCount == 0 {
            dismissWith(error: outcome.failureText.isEmpty
                        ? "未解析到书源"
                        : "未导入任何书源：\n" + outcome.failureText)
            return
        }
        onSuccess(ImportResultSummary(outcome: outcome))
        dismiss()
    }

    private func dismissWith(error: String) {
        onError(error)
        dismiss()
    }
}
