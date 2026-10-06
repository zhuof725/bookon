//
//  DebugView.swift
//  书源调试
//
//  第 7 步 C 段返工：调试页。
//   - 书源由「书源」列表点行传入（`source`），页内**不再**选择书源；
//   - 输入框下方有示例提示（关键字 / 详情页网址 / ::发现页 / ++目录页 / --正文页）；
//   - 开始 / 取消；
//   - 顶部**横向滚动标签条**（ScrollView(.horizontal) + Buttons，非 Picker、非 TabView），
//     选中标签用 accent 色背景 + 粗体，未选中用 secondary 色；ScrollViewReader 把选中标签滚入视野；
//     点击区 ≥44pt；每标签有 accessibilityLabel 与 .isSelected traits；
//     某阶段已有响应时标签显示小圆点，日志有错误（status -1）时显示红点；
//   - 内容区用 switch（非 TabView，避免手势冲突）；
//   - 页签：日志 / 搜索源码 / 详情源码 / 目录源码 / 正文源码 / 结果；
//   - 每个页签有「复制」按钮（UIPasteboard）；
//   - 日志页签：等宽字体、textSelection(.enabled)、自动滚到底（ScrollViewReader）、
//     错误行红字、每行带时间前缀；
//   - 导出改为 ShareLink（分享完整导出文本）+ 显示「已保存到：路径」；保存失败**弹错误**，
//     不再 `try?` 吞掉。
//
//  业务逻辑（标签枚举 / 上限截断 / 圆点判定 / 结果 JSON / 共享 Cookie 缓存）全部在
//  BookonDebugKit；本文件只做装配。
//

import SwiftUI
import BookonDebugKit
import LegadoBookSource

struct DebugView: View {
    @Bindable var repository: BookSourceRepository
    @Bindable var settings: DebugSettings
    let environment: SharedEnvironment
    let logStore: DebugLogStore
    /// 由书源列表传入的书源；从「调试」标签直接进入时为 nil（提示去书源页选择）。
    let source: BookSource?

    @State private var session = DebugSession()
    @State private var key = ""
    @State private var selectedTab: DebugTab = .logs
    @State private var copiedMessage: String?
    @State private var exportAlert: String?
    @State private var savedLogPath: String?
    @State private var shareText = ""

    var body: some View {
        Group {
            if let source {
                content(for: source)
            } else {
                ContentUnavailableView(
                    "请先选择书源",
                    systemImage: "books.vertical",
                    description: Text("在「书源」标签点任意书源，即可进入它的调试页。")
                )
            }
        }
    }

    // MARK: - 主体（有书源时）

    @ViewBuilder
    private func content(for source: BookSource) -> some View {
        VStack(spacing: 0) {
            inputSection(for: source)
            Divider()
            DebugTabBar(tabs: DebugTab.allCases,
                        selected: $selectedTab,
                        state: session.tabBarState)
            Divider()
            tabContent(for: source)
        }
        .navigationTitle(source.bookSourceName)
        .navigationBarTitleDisplayMode(.inline)
        .alert("提示", isPresented: Binding(
            get: { copiedMessage != nil },
            set: { if !$0 { copiedMessage = nil } }
        ), presenting: copiedMessage) { _ in
            Button("好", role: .cancel) { copiedMessage = nil }
        } message: { message in
            Text(message)
        }
        .alert("导出失败", isPresented: Binding(
            get: { exportAlert != nil },
            set: { if !$0 { exportAlert = nil } }
        ), presenting: exportAlert) { _ in
            Button("好", role: .cancel) { exportAlert = nil }
        } message: { message in
            Text(message)
        }
    }

    // MARK: - 输入区

    @ViewBuilder
    private func inputSection(for source: BookSource) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("调试关键字", text: $key)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityLabel("调试关键字输入框")

            // 输入框下方示例提示。
            VStack(alignment: .leading, spacing: 2) {
                Text("示例：")
                    .font(.caption2).foregroundStyle(.secondary)
                ForEach(DebugKeyExample.all, id: \.hint) { example in
                    HStack(spacing: 4) {
                        Text(example.hint)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text("· \(example.sample)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            HStack {
                Button(session.isRunning ? "调试中…" : "开始调试") {
                    startDebug(source)
                }
                .buttonStyle(.borderedProminent)
                .disabled(session.isRunning)

                if session.isRunning {
                    Button("取消", role: .destructive) { session.cancel() }
                }

                Spacer()

                LabeledContent("", value: statusText)
                    .labelsHidden()
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(String(format: "%.2fs", session.elapsed))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack {
                if let stage = session.currentStage {
                    Text("阶段：\(stage.rawValue)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let savedLogPath {
                    Text("已保存到：\(savedLogPath)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .accessibilityLabel("日志已保存到 \(savedLogPath)")
                }
                ShareLink(item: shareText.isEmpty ? exportPreviewText(source) : shareText) {
                    Label("导出日志", systemImage: "square.and.arrow.up")
                }
                .font(.caption)
                .accessibilityLabel("导出日志")
            }
        }
        .padding()
    }

    // MARK: - 页签内容（switch，非 TabView）

    @ViewBuilder
    private func tabContent(for source: BookSource) -> some View {
        switch selectedTab {
        case .logs:
            logsTab
        case .result:
            resultTab
        case .searchSource, .infoSource, .tocSource, .contentSource:
            sourceTab(selectedTab)
        }
    }

    // MARK: 日志页签

    private var logsTab: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(session.records.enumerated()), id: \.offset) { index, record in
                            Text(record.message)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(record.state == DebugLogState.error ? Color.red : Color.primary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(index)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
                // 自动滚到底。
                .onChange(of: session.records.count) { _, newValue in
                    guard newValue > 0 else { return }
                    withAnimation(.linear(duration: 0.1)) {
                        proxy.scrollTo(newValue - 1, anchor: .bottom)
                    }
                }
            }
            .overlay {
                if session.records.isEmpty {
                    ContentUnavailableView("尚无日志", systemImage: "text.alignleft",
                                           description: Text(DebugTab.logs.placeholder))
                }
            }
            copyBar(text: logCopyText)
        }
    }

    // MARK: 结果页签

    private var resultTab: some View {
        VStack(spacing: 0) {
            ScrollView {
                Text(resultDisplayText)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .overlay {
                if session.parsedResult.isEmpty {
                    ContentUnavailableView("尚无解析结果", systemImage: "list.bullet.rectangle",
                                           description: Text(DebugTab.result.placeholder))
                }
            }
            copyBar(text: session.exportParsedResultJSON())
        }
    }

    // MARK: 源码页签

    @ViewBuilder
    private func sourceTab(_ tab: DebugTab) -> some View {
        // 源展示上限（settings.sourceDisplayLimit，按 Character 截断）。
        let limit = settings.sourceDisplayLimit
        VStack(spacing: 0) {
            if let cap = session.capturedResponse(for: tab) {
                // 5MB 硬上限：超出保留前 5MB 并提示。
                let hard = DebugTextLimit.applyHardByteLimit(cap.body)
                let truncation = DebugTextLimit.truncate(hard.kept, limit: limit)
                VStack(alignment: .leading, spacing: 0) {
                    if hard.exceeded {
                        banner(hard.notice, color: .orange)
                    }
                    if truncation.truncated {
                        banner(truncation.notice, color: .secondary)
                    }
                    header(cap)
                    Divider()
                    ScrollView([.horizontal, .vertical]) {
                        Text(truncation.text)
                            .font(.system(.caption2, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                }
                copyBar(text: cap.body)   // 复制完整响应，不受上限影响
            } else {
                ContentUnavailableView("尚无响应", systemImage: "doc.questionmark",
                                       description: Text(tab.placeholder))
                Spacer(minLength: 0)
            }
        }
    }

    private func header(_ cap: CapturedResponse) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("URL：\(cap.url)").font(.caption2).textSelection(.enabled)
            Text("状态码：\(cap.statusCode)").font(.caption2)
                .foregroundStyle(cap.statusCode == 200 ? Color.secondary : Color.red)
            Text("Headers：\(headerText(cap))")
                .font(.caption2).foregroundStyle(.secondary)
                .lineLimit(2).textSelection(.enabled)
            Text("Body：\(cap.body.count) 字符")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private func banner(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
    }

    private func copyBar(text: String) -> some View {
        HStack {
            Spacer()
            Button {
                copy(text)
            } label: {
                Label("复制", systemImage: "doc.on.doc")
            }
            .font(.caption)
            .disabled(text.isEmpty)
            .accessibilityLabel("复制\(selectedTab.title)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    // MARK: - 动作

    private var statusText: String {
        switch session.state {
        case .idle: return "空闲"
        case .running: return "运行中"
        case .finished: return "完成"
        case .cancelled: return "已取消"
        }
    }

    private func startDebug(_ source: BookSource) {
        settings.apply(to: session.logger)
        // 用**共享** CookieStore / CacheManager 构造客户端：Cookie 与缓存跨次调试保留。
        let client = URLSessionHTTPClient(
            cookieStore: environment.cookieStore,
            cookieManagerCache: environment.cacheManager
        )
        let network = LiveWebBookNetwork(client: client)
        let options = WebBookOptions(logger: session.logger, network: network)
        savedLogPath = nil
        shareText = ""
        selectedTab = .logs   // 开始调试后默认回到日志页签
        session.start(bookSource: source, key: key, options: options)
        saveLogOnFinish(source)
    }

    /// 调试结束后把完整日志落盘（保存失败弹错误，绝不 `try?` 吞）。
    private func saveLogOnFinish(_ source: BookSource) {
        Task {
            // 等待本次调试结束（轮询 session.state，避免引入额外回调）。
            while session.state == .running {
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
            let content = exportText(source)
            do {
                let url = try logStore.saveLog(sourceName: source.bookSourceName, content: content)
                savedLogPath = url.path
                shareText = content
            } catch {
                exportAlert = "日志保存失败：\(error.localizedDescription)"
                shareText = content   // 仍可分享，但明确告知未落盘
            }
        }
    }

    private func copy(_ text: String) {
        UIPasteboard.general.string = text
        copiedMessage = "已复制 \(text.count) 字符到剪贴板"
    }

    // MARK: - 文案组装（导出/复制）

    /// 导出文本：头 + 日志正文 + 各阶段源码（受 exportSourceLimit 限制，0 不附带）。
    private func exportText(_ source: BookSource) -> String {
        let build = AppBuildInfo.fromMainBundle()
        let header = DebugLogExportHeader(
            appVersion: build.version,
            gitCommit: build.commit,
            ciRun: build.ciRun,
            sourceName: source.bookSourceName,
            key: key
        )
        let limit = settings.exportSourceLimit
        var sections: [String] = []
        for tab in DebugTab.allCases where tab.isSourceTab {
            guard let cap = session.capturedResponse(for: tab) else { continue }
            if limit == 0 {
                sections.append("--- \(tab.title)：未附带源码 ---")
            } else if let section = DebugTextLimit.exportSection(for: cap.body, name: tab.title, limit: limit) {
                sections.append(section)
            }
        }
        let body = session.records.map { $0.message }.joined(separator: "\n")
        let sourceSnippet = sections.isEmpty ? nil : sections.joined(separator: "\n\n")
        return logStore.exportContent(
            header: header,
            body: body,
            sourceSnippet: sourceSnippet,
            sourceSnippetLimit: 0   // 已在 exportSection 内按 Character 截断过
        )
    }

    /// 结果页签的可读文本：书籍列表 / 详情 / 目录 / 正文。
    private var resultDisplayText: String {
        let result = session.parsedResult
        var lines: [String] = []
        if !result.books.isEmpty {
            lines.append("== 搜索到的书籍（\(result.books.count)） ==")
            for (i, book) in result.books.enumerated() {
                lines.append("[\(i)] \(book.name) / \(book.author) — \(book.bookUrl)")
            }
            lines.append("")
        }
        if let book = result.book {
            lines.append("== 详情 ==")
            lines.append("书名：\(book.name)")
            lines.append("作者：\(book.author)")
            lines.append("分类：\(book.kind ?? "")")
            lines.append("最新章：\(book.latestChapterTitle ?? "")")
            lines.append("目录页：\(book.tocUrl)")
            lines.append("")
        }
        if !result.chapters.isEmpty {
            lines.append("== 目录（\(result.chapters.count) 章） ==")
            for (i, chapter) in result.chapters.prefix(50).enumerated() {
                lines.append("[\(i)] \(chapter.title) — \(chapter.url)")
            }
            if result.chapters.count > 50 { lines.append("…（仅显示前 50 章）") }
            lines.append("")
        }
        if let content = result.content {
            lines.append("== 正文（前 \(min(content.count, 2000)) / \(content.count) 字符） ==")
            lines.append(String(content.prefix(2000)))
        }
        // 无结构化结果时退回 JSON，保证「结果」页签始终有可复制内容。
        if lines.isEmpty { return session.exportParsedResultJSON() }
        return lines.joined(separator: "\n")
    }

    private var logCopyText: String {
        session.records.map { $0.message }.joined(separator: "\n")
    }

    /// ShareLink 在尚未导出时的预览文本。
    private func exportPreviewText(_ source: BookSource) -> String {
        exportText(source)
    }

    private func headerText(_ cap: CapturedResponse) -> String {
        if cap.headers.isEmpty { return "（无）" }
        return cap.headers.sorted { $0.key < $1.key }
            .prefix(5)
            .map { "\($0.key): \($0.value)" }
            .joined(separator: " | ")
    }
}

// MARK: - 横向滚动标签条

/// 顶部横向滚动标签条（ScrollView(.horizontal) + Buttons）。
/// 故意不用 Picker(.segmented)、不用 TabView(.page)：前者无法显示小圆点，
/// 后者与源码页的横向滚动/长按选择手势冲突。
struct DebugTabBar: View {
    let tabs: [DebugTab]
    @Binding var selected: DebugTab
    let state: DebugTabBarState

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(tabs) { tab in
                        button(for: tab)
                            .id(tab)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .onChange(of: selected) { _, newValue in
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }

    private func button(for tab: DebugTab) -> some View {
        let isSelected = tab == selected
        return Button {
            selected = tab
        } label: {
            HStack(spacing: 4) {
                Text(tab.title)
                    .font(isSelected ? .subheadline.bold() : .subheadline)
                    .foregroundStyle(isSelected ? Color.white : Color.secondary)
                // 小圆点（有响应）/ 红点（日志有错误）。
                if state.showsErrorDot(for: tab) {
                    Circle().fill(Color.red).frame(width: 6, height: 6)
                } else if state.showsDot(for: tab) {
                    Circle().fill(isSelected ? Color.white : Color.accentColor)
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)   // 点击区 ≥44pt
            .background(isSelected ? Color.accentColor : Color.clear)
            .clipShape(Capsule())
            .overlay {
                if !isSelected {
                    Capsule().stroke(Color.secondary.opacity(0.4), lineWidth: 1)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
