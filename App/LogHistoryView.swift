//
//  LogHistoryView.swift
//  书源调试
//
//  第 7 步 C 段返工：日志历史页（第 4 个标签页）。
//   - 列出 Documents/logs 下的日志文件，按时间倒序（新的在前）；
//   - 每个文件可打开（查看内容）/ 复制 / 分享 / 删除；
//   - 列表、读取、删除的接口全部在 BookonDebugKit.DebugLogStore（已含测试）。
//
//  读/删失败都会弹错误提示，不静默。
//

import SwiftUI
import BookonDebugKit

struct LogHistoryView: View {
    let logStore: DebugLogStore

    @State private var logs: [URL] = []
    @State private var openedLog: OpenedLog?
    @State private var errorAlert: String?

    var body: some View {
        NavigationStack {
            List {
                if logs.isEmpty {
                    ContentUnavailableView(
                        "尚无日志",
                        systemImage: "doc.text",
                        description: Text("调试结束后日志会保存到 Documents/logs。")
                    )
                } else {
                    ForEach(logs, id: \.self) { url in
                        row(url)
                    }
                }
            }
            .navigationTitle("日志历史")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        reload()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("刷新日志列表")
                }
            }
            .onAppear { reload() }
            .sheet(item: $openedLog) { opened in
                LogDetailView(log: opened) { url in
                    do {
                        try logStore.deleteLog(at: url)
                        openedLog = nil
                        reload()
                    } catch {
                        errorAlert = "删除失败：\(error.localizedDescription)"
                    }
                }
            }
            .alert("错误", isPresented: Binding(
                get: { errorAlert != nil },
                set: { if !$0 { errorAlert = nil } }
            ), presenting: errorAlert) { _ in
                Button("好", role: .cancel) { errorAlert = nil }
            } message: { message in
                Text(message)
            }
        }
    }

    @ViewBuilder
    private func row(_ url: URL) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(logStore.displayName(for: url))
                    .font(.subheadline)
                Text(url.lastPathComponent)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            // 分享
            ShareLink(item: url) {
                Image(systemName: "square.and.arrow.up")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("分享 \(url.lastPathComponent)")
            // 删除
            Button(role: .destructive) {
                delete(url)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("删除 \(url.lastPathComponent)")
        }
        .contentShape(Rectangle())
        .onTapGesture { open(url) }
    }

    private func reload() {
        logs = logStore.listLogsNewestFirst()
    }

    private func open(_ url: URL) {
        do {
            let content = try logStore.readLog(at: url)
            openedLog = OpenedLog(url: url, content: content)
        } catch {
            errorAlert = "读取失败：\(error.localizedDescription)"
        }
    }

    private func delete(_ url: URL) {
        do {
            try logStore.deleteLog(at: url)
            reload()
        } catch {
            errorAlert = "删除失败：\(error.localizedDescription)"
        }
    }
}

/// 已打开的日志（Identifiable 以便 sheet(item:)）。
struct OpenedLog: Identifiable {
    let url: URL
    let content: String
    var id: String { url.absoluteString }
}

/// 日志详情：等宽字体 + 可选中 + 复制 + 分享 + 删除。
struct LogDetailView: View {
    let log: OpenedLog
    var onDelete: (URL) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(log.content)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .navigationTitle(log.url.lastPathComponent)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        UIPasteboard.general.string = log.content
                        copied = true
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    }
                    .accessibilityLabel("复制日志内容")
                    ShareLink(item: log.content) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("分享日志内容")
                    Button(role: .destructive) {
                        onDelete(log.url)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel("删除该日志")
                }
            }
        }
    }
}
