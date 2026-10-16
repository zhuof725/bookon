import SwiftUI
import UIKit

/// 书源调试：布局与 Legado 原版 BookSourceDebugActivity 一致。
/// 顶部一个输入框；聚焦时显示帮助（搜索/发现/详情/目录/正文示例，点击直接填入或运行）；
/// 右上菜单可查看搜索/详情/目录/正文源码、刷新发现、复制日志、帮助。
struct SourceDebugView: View {
    @ThemePalette private var palette
    let source: BookSource
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var report = ""
    @State private var running = false
    @State private var showHelp = true
    @State private var runTask: Task<Void, Never>?
    @State private var exploreKinds: [SourceDiagnostics.ExploreKind] = []
    @State private var exploreText = "系统::http://xxx"
    @State private var sourceText: SourceText?
    @State private var showHelpDoc = false
    @FocusState private var focused: Bool

    private struct SourceText: Identifiable {
        let id = UUID()
        let title: String
        let text: String
    }

    private var myKey: String {
        let k = source.ruleSearch?.checkKeyWord?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return k.isEmpty ? "我的" : k
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(palette.secondary)
                    TextField("搜索书名、作者", text: $query)
                        .textFieldStyle(.plain)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .focused($focused)
                        .onSubmit { start(query.isEmpty ? myKey : query) }
                        .accessibilityIdentifier("debug.query")
                    if running { ProgressView() }
                    Button { start(query.isEmpty ? myKey : query) } label: { Image(systemName: "arrow.right.circle.fill") }
                        .disabled(running)
                        .accessibilityIdentifier("debug.run")
                }
                .padding(12).modifier(SettingsGlassSurface())

                if showHelp {
                    helpPanel
                } else {
                    ScrollView {
                        Text(report.isEmpty ? "等待日志…" : report)
                            .appFont(.system(size: 12, design: .monospaced))
                            .foregroundStyle(palette.primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .accessibilityIdentifier("debug.log")
                    }
                    .modifier(SettingsGlassSurface())
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .background { AppThemeCanvas().ignoresSafeArea() }
            .navigationTitle(source.bookSourceName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { stop(); dismiss() }
                }
                ToolbarItem(placement: .primaryAction) { menu }
            }
            .onChange(of: focused) { f in if f { showHelp = true } }
            .task {
                loadExplore()
                focused = true
                while !Task.isCancelled {
                    if running { report = DebugLog.snapshot() }
                    do { try await Task.sleep(nanoseconds: 300_000_000) } catch { break }
                }
            }
            .onDisappear { stop() }
            .sheet(item: $sourceText) { item in
                NavigationStack {
                    ScrollView {
                        Text(item.text)
                            .appFont(.system(size: 12, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                    .navigationTitle(item.title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("复制") { UIPasteboard.general.string = item.text } }
                        ToolbarItem(placement: .confirmationAction) { Button("完成") { sourceText = nil } }
                    }
                }
            }
            .alert("书源调试", isPresented: $showHelpDoc) {
                Button("好", role: .cancel) {}
            } message: {
                Text("调试搜索：输入关键字，如 系统\n调试发现：输入 标题::发现URL\n调试详情页：输入详情页URL\n调试目录页：输入 ++目录页URL\n调试正文页：输入 --正文页URL")
            }
        }
    }

    private var menu: some View {
        Menu {
            Button("搜索源码") { showSource(10, "搜索源码") }
            Button("详情源码") { showSource(20, "详情源码") }
            Button("目录源码") { showSource(30, "目录源码") }
            Button("正文源码") { showSource(40, "正文源码") }
            Button("刷新发现") { report = ""; showHelp = true; loadExplore() }
            Button("复制日志") { UIPasteboard.general.string = report }
            Button("帮助") { showHelpDoc = true }
        } label: { Image(systemName: "ellipsis.circle") }
            .accessibilityIdentifier("debug.menu")
    }

    private var helpPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                helpTitle("调试搜索>>输入关键字，如：")
                HStack(spacing: 10) {
                    chip(myKey) { run(myKey) }
                    chip("系统") { run("系统") }
                }
                helpTitle("调试发现>>输入发现URL，如：")
                Group {
                    if exploreKinds.count > 1 {
                        Menu {
                            ForEach(Array(exploreKinds.enumerated()), id: \.offset) { _, k in
                                Button(k.title) { exploreText = "\(k.title)::\(k.url ?? "")"; run(exploreText) }
                            }
                        } label: { chipLabel(exploreText) } primaryAction: {
                            if !exploreText.hasPrefix("ERROR:") { run(exploreText) }
                        }
                    } else {
                        chip(exploreText) { if !exploreText.hasPrefix("ERROR:") { run(exploreText) } }
                    }
                }
                if exploreKinds.count > 1 {
                    Text("长按可选择其它发现").appFont(.caption2).foregroundStyle(palette.secondary)
                }
                helpTitle("调试详情页>>输入详情页URL，如：")
                chip("https://m.qidian.com/book/1015609210") {
                    if !query.isEmpty { run(query) } else { query = "https://"; focused = true }
                }
                helpTitle("调试目录页>>输入目录页URL，如：")
                chip("++https://www.zhaishuyuan.com/read/30394") { prefix("++") }
                helpTitle("调试正文页>>输入正文页URL，如：")
                chip("--https://www.zhaishuyuan.com/chapter/30394/20940996") { prefix("--") }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
        .modifier(SettingsGlassSurface())
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .accessibilityIdentifier("debug.help")
    }

    private func helpTitle(_ t: String) -> some View {
        Text(t).appFont(.footnote).foregroundStyle(palette.secondary)
    }

    private func chipLabel(_ t: String) -> some View {
        Text(t).appFont(.footnote).foregroundStyle(palette.accent).lineLimit(1)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background { Capsule().stroke(palette.accent.opacity(0.6)) }
    }

    private func chip(_ t: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { chipLabel(t) }.buttonStyle(.plain)
    }

    /// 与原版 prefixAutoComplete 一致：输入为空或过短只补前缀；已有地址则补前缀并直接运行。
    private func prefix(_ p: String) {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.count <= 2 { query = p; focused = true; return }
        run(q.hasPrefix(p) ? q : p + q)
    }

    private func run(_ key: String) { query = key; start(key) }

    private func showSource(_ stage: Int, _ title: String) {
        let text = DebugLog.source(stage: stage) ?? ""
        sourceText = SourceText(title: title, text: text.isEmpty ? "（暂无，先运行一次调试）" : text)
    }

    private func loadExplore() {
        let src = source
        Task {
            let kinds = await Task.detached { SourceDiagnostics.exploreKinds(source: src).filter { !($0.url ?? "").isEmpty || $0.title.hasPrefix("ERROR:") } }.value
            exploreKinds = kinds
            if let first = kinds.first {
                exploreText = "\(first.title)::\(first.url ?? "")"
                if first.title.hasPrefix("ERROR:") {
                    report = "获取发现出错\n\(first.url ?? first.title)"
                    showHelp = false
                    focused = false
                }
            }
        }
    }

    private func stop() { runTask?.cancel(); runTask = nil; DebugLog.end() }

    private func start(_ key: String) {
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !k.isEmpty else { return }
        runTask?.cancel()
        focused = false
        showHelp = false
        running = true
        DebugLog.begin()
        report = ""
        runTask = Task {
            await SourceDiagnostics.run(source: source, key: k)
            report = DebugLog.snapshot()
            running = false
            DebugLog.end()
        }
    }
}
