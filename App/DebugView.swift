//
//  DebugView.swift
//  书源调试
//
//  第 7 步 C 段：调试页（选择书源 + 输入 key + 启动调试 + 日志展示 + 导出）。
//  业务逻辑委托 BookonDebugKit.DebugSession / DebugLogStore。
//

import SwiftUI
import BookonDebugKit
import LegadoBookSource

struct DebugView: View {
    @Bindable var repository: BookSourceRepository
    @Bindable var settings: DebugSettings

    @State private var session = DebugSession()
    @State private var key = ""
    @State private var logStore = DebugLogStore()
    @State private var selectedSourceUrl: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("书源") {
                    Picker("书源", selection: $selectedSourceUrl) {
                        Text("（未选择）").tag(String?.none)
                        ForEach(repository.filteredSources, id: \.bookSourceUrl) { source in
                            Text(source.bookSourceName).tag(Optional(source.bookSourceUrl))
                        }
                    }
                }

                Section("调试关键字") {
                    TextField("绝对地址 / ::发现 / ++目录 / --正文 / 搜索", text: $key)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Button(session.isRunning ? "调试中…" : "开始调试") {
                        startDebug()
                    }
                    .disabled(session.isRunning || selectedSourceUrl == nil)
                    if session.isRunning {
                        Button("取消") { session.cancel() }
                    }
                }

                Section("状态") {
                    LabeledContent("状态", value: statusText)
                    LabeledContent("耗时", value: String(format: "%.2f 秒", session.elapsed))
                    if let stage = session.currentStage {
                        LabeledContent("阶段", value: stage.rawValue)
                    }
                }

                Section("日志") {
                    ScrollView {
                        LazyVStack(alignment: .leading) {
                            ForEach(session.records.indices, id: \.self) { i in
                                Text(session.records[i].message)
                                    .font(.system(.caption, design: .monospaced))
                            }
                        }
                    }
                    .frame(minHeight: 200)
                    Button("导出日志") {
                        exportLog()
                    }
                }
            }
            .navigationTitle("调试")
        }
    }

    private var statusText: String {
        switch session.state {
        case .idle: return "空闲"
        case .running: return "运行中"
        case .finished: return "完成"
        case .cancelled: return "已取消"
        }
    }

    private func startDebug() {
        guard let url = selectedSourceUrl,
              let source = repository.sources.first(where: { $0.bookSourceUrl == url }) else { return }
        settings.apply(to: session.logger)
        let network = LiveWebBookNetwork(client: makeHTTPClient())
        let options = WebBookOptions(logger: session.logger, network: network)
        session.start(bookSource: source, key: key, options: options)
    }

    private func exportLog() {
        guard let source = repository.sources.first(where: { $0.bookSourceUrl == selectedSourceUrl }) else { return }
        let header = DebugLogExportHeader(sourceName: source.bookSourceName, key: key)
        let content = logStore.exportContent(
            header: header,
            body: session.records.map { $0.message }.joined(separator: "\n")
        )
        try? logStore.saveLog(sourceName: source.bookSourceName, content: content)
    }

    private func makeHTTPClient() -> URLSessionHTTPClient {
        URLSessionHTTPClient(cookieStore: CookieStore(), cookieManagerCache: CacheManager())
    }
}
