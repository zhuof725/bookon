import SwiftUI

/// 书源批量校验界面（对齐 Legado 原版「校验书源」）：
/// 搜索 → 发现 → 详情 → 目录 → 正文，逐源显示结果，
/// 失败的源写回 搜索失效/…/校验超时/网站失效 分组、`// Error` 注释与响应耗时。
struct SourceCheckView: View {
    let sources: [BookSource]
    let store: AppStore

    @Environment(\.dismiss) private var dismiss
    @ThemePalette private var palette

    @StateObject private var runner = SourceCheckRunner()

    @State private var keyword = "我的"
    @State private var timeoutText = "180"
    @State private var concurrency = 3
    @State private var checkDomain = false
    @State private var checkSearch = true
    @State private var checkDiscovery = true
    @State private var checkInfo = true
    @State private var checkCategory = true
    @State private var checkContent = true
    @State private var writeComment = true

    var body: some View {
        NavigationStack {
            List {
                Section {
                    settingsCard
                }
                .independentGlassRow()

                Section("校验结果") {
                    if runner.rows.isEmpty {
                        Text("点右上角「开始」后逐个书源执行搜索 → 详情 → 目录 → 正文，失败会写回书源分组。")
                            .appFont(.footnote).foregroundStyle(palette.secondary)
                    }
                    ForEach(runner.rows) { row in resultRow(row) }
                }
                .independentGlassRow()
            }
            .scrollContentBackground(.hidden)
            .background { AppThemeCanvas().ignoresSafeArea() }
            .navigationTitle("校验书源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if runner.running {
                        Button("停止") { runner.stop() }.accessibilityIdentifier("check.stop")
                    } else {
                        Button("完成") { dismiss() }.accessibilityIdentifier("check.done")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("开始") { start() }
                        .disabled(runner.running || sources.isEmpty)
                        .accessibilityIdentifier("check.start")
                }
            }
        }
        .onAppear { loadSettings() }
        // 运行中不允许下拉关闭；真的离开页面时停止并把已有结果写回。
        .interactiveDismissDisabled(runner.running)
        .onDisappear { runner.stop(); runner.flushNow() }
    }

    // MARK: 设置

    private var summaryText: String {
        var options = SourceCheck.Options()
        options.timeout = Double(timeoutText.trimmingCharacters(in: .whitespaces)) ?? 180
        options.checkDomain = checkDomain
        options.checkSearch = checkSearch
        options.checkDiscovery = checkDiscovery
        options.checkInfo = checkInfo
        options.checkCategory = checkCategory
        options.checkContent = checkContent
        return options.summary
    }

    private var infoEnabled: Bool { checkSearch || checkDiscovery }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("关键词").foregroundStyle(palette.primary)
                Spacer(minLength: 8)
                TextField("我的", text: $keyword)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(palette.secondary)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .disabled(runner.running)
                    .accessibilityIdentifier("check.keyword")
            }
            .appFont(.subheadline)

            Divider().opacity(0.4)

            HStack {
                Text("单个书源超时（秒）").foregroundStyle(palette.primary)
                Spacer(minLength: 8)
                TextField("180", text: $timeoutText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(palette.secondary)
                    .disabled(runner.running)
                    .accessibilityIdentifier("check.timeout")
            }
            .appFont(.subheadline)

            Divider().opacity(0.4)

            // 同时校验的书源数；上限 9 与原版 AppConst.MAX_THREAD 一致。
            Stepper(value: $concurrency, in: 1...9) {
                HStack {
                    Text("并发数").foregroundStyle(palette.primary)
                    Spacer(minLength: 8)
                    Text("\(concurrency)").foregroundStyle(palette.secondary)
                }
            }
            .appFont(.subheadline)
            .disabled(runner.running)
            .accessibilityIdentifier("check.concurrency")

            Divider().opacity(0.4)
            Toggle("校验源地址可达", isOn: $checkDomain).disabled(runner.running).accessibilityIdentifier("check.domain")
            Toggle("校验搜索", isOn: $checkSearch).disabled(runner.running).accessibilityIdentifier("check.search")
            Toggle("校验发现", isOn: $checkDiscovery).disabled(runner.running).accessibilityIdentifier("check.discovery")
            Toggle("校验详情", isOn: $checkInfo)
                .disabled(runner.running || !infoEnabled)
                .accessibilityIdentifier("check.info")
            Toggle("校验目录", isOn: $checkCategory)
                .disabled(runner.running || !infoEnabled || !checkInfo)
                .accessibilityIdentifier("check.category")
            Toggle("校验正文", isOn: $checkContent)
                .disabled(runner.running || !infoEnabled || !checkInfo || !checkCategory)
                .accessibilityIdentifier("check.content")
            Toggle("失败写入书源注释", isOn: $writeComment).disabled(runner.running).accessibilityIdentifier("check.comment")

            Text(summaryText)
                .appFont(.caption2).foregroundStyle(palette.secondary)

            if runner.running || runner.notice != nil {
                Divider().opacity(0.4)
                if runner.running {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("正在校验 (\(runner.completed)/\(runner.rows.count))" + (runner.currentName.map { "：\($0)" } ?? ""))
                            .appFont(.footnote).foregroundStyle(palette.secondary)
                            .lineLimit(1)
                    }
                    .accessibilityIdentifier("check.progress")
                } else if let notice = runner.notice {
                    Text(notice)
                        .appFont(.footnote).foregroundStyle(palette.secondary)
                        .accessibilityIdentifier("check.summary")
                }
            }
        }
        .appFont(.subheadline)
        .tint(palette.accent)
    }

    // MARK: 结果

    private func resultRow(_ row: SourceCheckRunner.Row) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon(row.state))
                .foregroundStyle(color(row.state))
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(row.name).foregroundStyle(palette.primary).lineLimit(1)
                if !row.message.isEmpty {
                    Text(row.message).appFont(.caption).foregroundStyle(palette.secondary).lineLimit(3)
                }
                if let g = row.group {
                    Text(g).appFont(.caption2).foregroundStyle(Color.orange)
                }
            }
            Spacer(minLength: 4)
            if let rt = row.respondTime, rt > 0 {
                Text("\(rt)ms").appFont(.caption2).foregroundStyle(palette.secondary)
            }
        }
        .appFont(.subheadline)
        .contentShape(Rectangle())
        .accessibilityIdentifier("check.row.\(row.id)")
    }

    private func icon(_ state: SourceCheckRunner.Row.State) -> String {
        switch state {
        case .pending: return "circle.dashed"
        case .running: return "clock"
        case .success: return "checkmark.circle.fill"
        case .failure: return "xmark.octagon.fill"
        case .cancelled: return "stop.circle"
        }
    }

    private func color(_ state: SourceCheckRunner.Row.State) -> Color {
        switch state {
        case .pending: return palette.secondary.opacity(0.6)
        case .running: return palette.accent
        case .success: return .green
        case .failure: return .red
        case .cancelled: return palette.secondary
        }
    }

    // MARK: 运行

    private func start() {
        guard !runner.running, !sources.isEmpty else { return }
        let seconds = Double(timeoutText.trimmingCharacters(in: .whitespaces)) ?? 0
        guard seconds > 0 else {
            runner.notice = "超时不能为空，且需大于0秒"
            return
        }
        var options = SourceCheck.Options()
        let word = keyword.trimmingCharacters(in: .whitespaces)
        options.keyword = word.isEmpty ? "我的" : word
        options.timeout = seconds
        options.concurrency = max(1, min(concurrency, 9, sources.count))
        options.checkDomain = checkDomain
        options.checkSearch = checkSearch
        options.checkDiscovery = checkDiscovery
        options.checkInfo = checkInfo
        options.checkCategory = checkCategory
        options.checkContent = checkContent
        options.writeComment = writeComment
        saveSettings()
        runner.start(sources: sources, options: options, store: store)
    }

    private func loadSettings() {
        let d = UserDefaults.standard
        if let k = d.string(forKey: "reader.source.check.keyword") { keyword = k }
        let t = d.integer(forKey: "reader.source.check.timeout")
        if t > 0 { timeoutText = String(t) }
        let c = d.integer(forKey: "reader.source.check.concurrency")
        if c > 0 { concurrency = min(c, 9) }
        checkDomain = d.object(forKey: "reader.source.check.domain") as? Bool ?? false
        checkSearch = d.object(forKey: "reader.source.check.search") as? Bool ?? true
        checkDiscovery = d.object(forKey: "reader.source.check.discovery") as? Bool ?? true
        checkInfo = d.object(forKey: "reader.source.check.info") as? Bool ?? true
        checkCategory = d.object(forKey: "reader.source.check.category") as? Bool ?? true
        checkContent = d.object(forKey: "reader.source.check.content") as? Bool ?? true
        writeComment = d.object(forKey: "reader.source.check.comment") as? Bool ?? true
    }

    private func saveSettings() {
        let d = UserDefaults.standard
        d.set(keyword, forKey: "reader.source.check.keyword")
        d.set(Int(Double(timeoutText) ?? 180), forKey: "reader.source.check.timeout")
        d.set(concurrency, forKey: "reader.source.check.concurrency")
        d.set(checkDomain, forKey: "reader.source.check.domain")
        d.set(checkSearch, forKey: "reader.source.check.search")
        d.set(checkDiscovery, forKey: "reader.source.check.discovery")
        d.set(checkInfo, forKey: "reader.source.check.info")
        d.set(checkCategory, forKey: "reader.source.check.category")
        d.set(checkContent, forKey: "reader.source.check.content")
        d.set(writeComment, forKey: "reader.source.check.comment")
    }
}

/// 校验运行状态与结果列表（全部在 MainActor 上更新；引擎跑在 detached 任务里，避免卡界面）。
@MainActor
final class SourceCheckRunner: ObservableObject {
    struct Row: Identifiable {
        let id: String
        let name: String
        var state: State = .pending
        var message = ""
        var group: String?
        var respondTime: Int?

        enum State { case pending, running, success, failure, cancelled }
    }

    @Published var rows: [Row] = []
    @Published var running = false
    @Published var completed = 0
    @Published var currentName: String?
    @Published var notice: String?

    private var task: Task<Void, Never>?
    /// 校验结果先攒起来，每 2 秒合并写回一次；结束/停止/关闭时立即写回。
    private var pending: [BookSource] = []
    private var flushTask: Task<Void, Never>?
    private weak var store: AppStore?

    func start(sources: [BookSource], options: SourceCheck.Options, store: AppStore) {
        guard !running, !sources.isEmpty else { return }
        rows = sources.map { Row(id: $0.bookSourceUrl, name: $0.bookSourceName) }
        running = true
        completed = 0
        currentName = nil
        notice = nil
        self.store = store
        pending.removeAll()
        let started = Date()
        task = Task.detached { [weak self] in
            _ = await SourceCheck.runAll(sources, options: options, onStart: { s in
                Task { @MainActor in self?.markRunning(s) }
            }, onResult: { r in
                Task { @MainActor in self?.apply(r, store: store) }
            })
            await MainActor.run { self?.finish(started: started) }
        }
    }

    func stop() { task?.cancel() }

    private func markRunning(_ source: BookSource) {
        currentName = source.bookSourceName
        if let i = rows.firstIndex(where: { $0.id == source.bookSourceUrl }), rows[i].state == .pending {
            rows[i].state = .running
        }
    }

    private func apply(_ r: SourceCheck.Result, store: AppStore) {
        if let i = rows.firstIndex(where: { $0.id == r.bookSourceUrl }) {
            rows[i].state = r.cancelled ? .cancelled : (r.success ? .success : .failure)
            rows[i].message = r.message
            rows[i].group = r.group
            rows[i].respondTime = r.respondTime
        }
        completed = rows.filter { $0.state == .success || $0.state == .failure || $0.state == .cancelled }.count
        if !r.cancelled {
            pending.append(r.updatedSource)
            if running { scheduleFlush() } else { flushNow() }
        }
    }

    private func scheduleFlush() {
        guard flushTask == nil else { return }
        flushTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            self?.flushTask = nil
            self?.flushNow()
        }
    }

    func flushNow() {
        flushTask?.cancel()
        flushTask = nil
        guard !pending.isEmpty else { return }
        let list = pending
        pending.removeAll()
        store?.applySourceChecks(list)
    }

    private func finish(started: Date) {
        running = false
        currentName = nil
        task = nil
        flushNow()
        let ok = rows.filter { $0.state == .success }.count
        let bad = rows.filter { $0.state == .failure }.count
        let left = rows.count - ok - bad
        let seconds = String(format: "%.1f", Date().timeIntervalSince(started))
        if left > 0 {
            notice = "已停止：成功 \(ok) / 失败 \(bad) / 共 \(rows.count)"
        } else {
            notice = "完成：成功 \(ok) / 失败 \(bad) / 共 \(rows.count)，耗时 \(seconds) 秒"
        }
    }
}
