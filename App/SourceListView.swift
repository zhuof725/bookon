//
//  SourceListView.swift
//  书源调试
//
//  第 7 步 C 段：书源列表（导入 / 启用开关 / 搜索）。
//  业务逻辑委托 BookSourceRepository。
//

import SwiftUI
import BookonDebugKit
import LegadoBookSource

struct SourceListView: View {
    @Bindable var repository: BookSourceRepository
    @State private var showingImport = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(repository.filteredSources, id: \.bookSourceUrl) { source in
                    VStack(alignment: .leading) {
                        Text(source.bookSourceName)
                            .font(.headline)
                        Text(source.bookSourceUrl)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .swipeActions {
                        Button(source.enabled ? "禁用" : "启用") {
                            repository.toggleEnabled(sourceUrl: source.bookSourceUrl)
                        }
                        .tint(source.enabled ? .orange : .green)
                    }
                    .opacity(source.enabled ? 1.0 : 0.4)
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
                }
            }
            .sheet(isPresented: $showingImport) {
                ImportSheet(repository: repository)
            }
        }
    }
}

/// 导入面板：粘贴 JSON 文本。
struct ImportSheet: View {
    @Bindable var repository: BookSourceRepository
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack {
                TextEditor(text: $text)
                    .font(.system(.body, design: .monospaced))
                    .border(.gray)
                    .padding()

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
            .navigationTitle("导入书源")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("导入") {
                        do {
                            let count = try repository.importSources(jsonText: text)
                            if count == 0 { errorMessage = "未解析到书源" }
                            else { dismiss() }
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
            }
        }
    }
}
