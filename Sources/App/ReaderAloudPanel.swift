import SwiftUI
import AVFoundation

/// 听书朗读面板：对齐原版 `dialog_read_aloud.xml` 的控件组 —
/// 上一章/上一句/播放暂停/停止/下一句/下一章，语速 −/+，定时，朗读引擎，朗读设置。
struct ReaderAloudPanel: View {
    @ObservedObject var aloud: ReaderAloudController
    @Environment(\.dismiss) private var dismiss
    @State private var showEngines = false
    @State private var showTimerMenu = false
    private let timerPresets = [0, 5, 10, 15, 30, 45, 60, 90, 180]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    statusHeader
                    controlRow
                    speedRow
                    engineLink
                    AloudPreloadCard()
                }
                .padding(16)
            }
            .foregroundStyle(.primary)
            .background { AppThemeCanvas().ignoresSafeArea() }
            .navigationTitle("听书")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .accessibilityIdentifier("reader.aloud.close")
                }
            }
        }
        .presentationDetents([.height(560), .large])
        .presentationDragIndicator(.visible)
        // 打开面板未启动即自动开始；中途重新打开不打断正在读的。
        .onAppear { if !aloud.isRunning { aloud.openCurrent() } }
        // 面板始终显示最新选中的引擎名
        .onAppear { aloud.refreshEngineLabel() }
        .sheet(isPresented: $showEngines, onDismiss: { aloud.refreshEngineLabel() }) {
            SpeakEngineList(aloud: aloud)
        }
    }

    private var statusHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(aloud.chapterTitle.isEmpty ? "未开始朗读" : aloud.chapterTitle)
                    .appFont(.headline).lineLimit(1)
                Spacer()
                Text(aloud.engineName).appFont(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("reader.aloud.engineName")
            }
            Text(aloud.unitText.isEmpty ? "「听书」从当前位置开始朗读，章末自动进入下一章。" : aloud.unitText)
                .appFont(.subheadline).foregroundStyle(.secondary)
                .lineLimit(3).frame(minHeight: 44, alignment: .leading)
                .accessibilityIdentifier("reader.aloud.unit")
            HStack(spacing: 12) {
                Text(stateText).appFont(.caption).foregroundStyle(.secondary)
                if aloud.unitTotal > 0 {
                    Text("第 \(aloud.unitIndex + 1)/\(aloud.unitTotal) 段").appFont(.caption).foregroundStyle(.secondary)
                }
                if aloud.timerLeft > 0 {
                    Text("定时还剩 \(aloud.timerLeft) 分钟").appFont(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("reader.aloud.timerLeft")
                }
                Spacer()
            }
        }
        .padding(16)
        .modifier(SettingsGlassSurface())
        .accessibilityElement(children: .contain)
    }

    private var stateText: String {
        if !aloud.isRunning { return "未开始" }
        if aloud.isBuffering { return "正在下载音频…" }
        return aloud.isPlaying ? "正在朗读" : "已暂停"
    }

    private struct Control: Identifiable {
        let label: String
        let symbol: String
        let id: String
        let size: CGFloat
        let active: Bool
        let action: () -> Void
    }

    private var controlRow: some View {
        let buttons: [Control] = [
            Control(label: "上一章", symbol: "backward.end.alt.fill", id: "reader.aloud.prevChapter", size: 18, active: aloud.isRunning) { aloud.manualChapter(direction: -1) },
            Control(label: "上一句", symbol: "backward.end.fill", id: "reader.aloud.prev", size: 18, active: aloud.isRunning) { aloud.previousUnit() },
            Control(label: aloud.isPlaying ? "暂停" : "播放", symbol: aloud.isPlaying ? "pause.fill" : "play.fill", id: "reader.aloud.play", size: 24, active: true) { aloud.togglePlay() },
            Control(label: "停止", symbol: "stop.fill", id: "reader.aloud.stop", size: 20, active: aloud.isRunning) { aloud.stop() },
            Control(label: "下一句", symbol: "forward.end.fill", id: "reader.aloud.next", size: 18, active: aloud.isRunning) { aloud.nextUnit() },
            Control(label: "下一章", symbol: "forward.end.alt.fill", id: "reader.aloud.nextChapter", size: 18, active: aloud.isRunning) { aloud.manualChapter(direction: 1) },
        ]
        return HStack(spacing: 0) {
            ForEach(buttons) { item in
                Button(action: item.action) {
                    VStack(spacing: 6) {
                        Image(systemName: item.symbol)
                            .font(.system(size: item.size))
                            .frame(minWidth: 28, minHeight: 28)
                        Text(item.label).appFont(.caption2)
                    }.frame(maxWidth: .infinity, minHeight: 58).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!item.active)
                .accessibilityLabel(item.label)
                .accessibilityIdentifier(item.id)
            }
        }
        .modifier(SettingsGlassSurface())
    }

    private var speedRow: some View {
        HStack(spacing: 14) {
            Text("语速").appFont(.subheadline)
            Button { aloud.changeSpeed(-1) } label: {
                Image(systemName: "minus").frame(width: 34, height: 34).contentShape(Rectangle())
            }
            .accessibilityLabel("语速减")
            .accessibilityIdentifier("reader.aloud.speedMinus")
            Text(String(format: "%.1f", AloudTTSConfig.rateDisplay(for: aloud.speed)))
                .font(.system(.body, design: .rounded, weight: .semibold))
                .frame(minWidth: 54)
                .accessibilityIdentifier("reader.aloud.speedValue")
            Button { aloud.changeSpeed(1) } label: {
                Image(systemName: "plus").frame(width: 34, height: 34).contentShape(Rectangle())
            }
            .accessibilityLabel("语速加")
            .accessibilityIdentifier("reader.aloud.speedPlus")
            Spacer()
            Menu {
                ForEach(timerPresets, id: \.self) { minutes in
                    if minutes == 0 {
                        Button("关闭定时") { aloud.setTimer(minutes: 0) }
                            .accessibilityIdentifier("reader.aloud.timer.0")
                    } else {
                        Button("\(minutes) 分钟") { aloud.setTimer(minutes: minutes) }
                            .accessibilityIdentifier("reader.aloud.timer.\(minutes)")
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "timer")
                    Text(aloud.timerLeft > 0 ? "\(aloud.timerLeft) 分钟" : "定时")
                    Image(systemName: "chevron.up.chevron.down").font(.caption2)
                }.appFont(.subheadline)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("定时")
            .accessibilityIdentifier("reader.aloud.timer")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16).padding(.vertical, 12)
        .modifier(SettingsGlassSurface())
    }

    private var engineLink: some View {
        Button { showEngines = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "waveform.badge.mic")
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text("朗读引擎").appFont(.subheadline)
                    Text(aloud.engineName).appFont(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").appFont(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(SettingsGlassSurface())
        .accessibilityIdentifier("reader.aloud.engines")
    }
}

/// 预加载段落设置：数字框 + −/+ 圆形按钮 + 滑杆，调整后立即持久化。
/// 语音引擎为系统语音时无预加载，仍保留可调（切到在线引擎即生效）。
struct AloudPreloadCard: View {
    @AppStorage(AloudTTSConfig.preloadKey) private var storedCount = AloudTTSConfig.defaultPreloadCount
    private let range = AloudTTSConfig.preloadRange
    private var count: Int { AloudTTSConfig.clampedPreloadCount(storedCount) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("预加载").appFont(.headline)
                .padding(.leading, 4)
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 8) {
                    Text("预加载段落").appFont(.body)
                    Spacer(minLength: 8)
                    Text("\(count)")
                        .font(.system(.title2, design: .default, weight: .regular))
                        .monospacedDigit()
                        .frame(minWidth: 56, minHeight: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                        .accessibilityIdentifier("reader.aloud.preloadValue")
                    Text("段").appFont(.body).foregroundStyle(.secondary)
                }
                HStack(spacing: 14) {
                    stepButton(symbol: "minus", label: "减少预加载段落", enabled: count > range.lowerBound) {
                        setCount(count - 1)
                    }
                    .accessibilityIdentifier("reader.aloud.preloadMinus")
                    Slider(value: Binding(get: { Double(count) },
                                          set: { setCount(Int($0.rounded())) }),
                           in: Double(range.lowerBound)...Double(range.upperBound), step: 1)
                        .tint(.accentColor)
                        .accessibilityIdentifier("reader.aloud.preloadSlider")
                        .accessibilityLabel("预加载段落")
                    stepButton(symbol: "plus", label: "增加预加载段落", enabled: count < range.upperBound) {
                        setCount(count + 1)
                    }
                    .accessibilityIdentifier("reader.aloud.preloadPlus")
                }
                Text("范围: \(range.lowerBound)-\(range.upperBound)，预加载更多段落可减少卡顿")
                    .appFont(.footnote).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16).padding(.vertical, 16)
            .modifier(SettingsGlassSurface())
        }
        .onAppear { setCount(storedCount) }
        .onChange(of: storedCount) { setCount($0) }
    }

    private func stepButton(symbol: String, label: String, enabled: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(enabled ? Color.white : Color.white.opacity(0.7))
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.accentColor.opacity(enabled ? 1 : 0.45)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    private func setCount(_ value: Int) {
        let clamped = AloudTTSConfig.clampedPreloadCount(value)
        guard storedCount != clamped else { return }
        storedCount = clamped
    }
}

/// 朗读引擎管理：对齐原版 SpeakEngineDialog — 列表选择、长按登录、
/// 添加/编辑/删除/导入/导出/清空缓存。选择立即生效并持久化。
struct SpeakEngineList: View {
    @ObservedObject var aloud: ReaderAloudController
    @ObservedObject var engines = SpeakEngineModel.shared
    @Environment(\.dismiss) private var dismiss
    @State private var editing: HTTPTTS?
    @State private var showNewEditor = false
    @State private var importInput = ""
    @State private var importTitle = ""
    @State private var showImportText = false
    @State private var showImportFile = false
    @State private var deleting: HTTPTTS?
    @State private var loginEngine: HTTPTTS?
    @State private var message: String?
    @StateObject private var auditioner = AloudEngineAudition()
    private var selectedID: String { AloudTTSConfig.selectedEngineID }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { choose(nil) } label: {
                        HStack(spacing: 12) {
                            Text("系统语音").appFont(.body)
                            Spacer()
                            if auditioner.isSystem {
                                Image(systemName: auditioner.isPlaying ? "waveform" : "hourglass")
                                    .foregroundStyle(.tint)
                            }
                            Text("系统").appFont(.caption).foregroundStyle(.secondary)
                            if selectedID.isEmpty {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }.contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("tts.system")
                    .contextMenu {
                        Button { auditioner.toggleSystem(reader: aloud) } label: {
                            Label(auditioner.isSystem ? "取消试听" : "试听", systemImage: auditioner.isSystem ? "stop.circle" : "play.circle")
                        }
                        .accessibilityIdentifier("tts.audition.system")
                    }
                } header: { Text("语音引擎") }

                Section {
                    if engines.list.isEmpty {
                        Text("还没有在线引擎\n菜单里可以「导入默认」或直接新建。")
                            .appFont(.footnote).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                            .accessibilityIdentifier("tts.empty")
                    } else {
                        ForEach(engines.list) { engine in
                            engineRow(engine)
                        }
                    }
                } header: { Text("HTTP 引擎") }

                if let message {
                    Section { Text(message).appFont(.footnote).foregroundStyle(.secondary) }
                }
            }
            .foregroundStyle(.primary)
            .navigationTitle("朗读引擎")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("完成") { auditioner.cancel(); dismiss() }.accessibilityIdentifier("tts.close")
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("新建引擎") { showNewEditor = true }
                        Button("文本导入") { importTitle = "输入引擎 JSON"; importInput = ""; showImportText = true }
                        Button("本地文件导入") { showImportFile = true }
                        Button("URL 导入") { importTitle = "输入引擎链接"; importInput = ""; showImportText = true }
                        Button("剪贴板导入") { importClipboard() }
                        Divider()
                        Button("导入默认") {
                            let n = HTTPTTSStore.shared.importDefaults(); engines.reload()
                            show("导入了 \(n) 个默认引擎")
                        }
                        Button("导出全部引擎") { exportAll() }
                        .disabled(engines.list.isEmpty)
                        Divider()
                        Button("清空音频缓存") {
                            AloudAudioCache.shared.clear()
                            show("朗读音频缓存已清空")
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .accessibilityLabel("添加或导入")
                    }
                    .accessibilityIdentifier("tts.import")
                }
            }
            .sheet(isPresented: $showImportText) {
                NavigationStack {
                    VStack {
                        TextEditor(text: $importInput)
                            .font(.system(.caption, design: .monospaced))
                            .padding(12)
                            .modifier(SettingsGlassSurface())
                            .padding(16)
                    }
                    .background { AppThemeCanvas().ignoresSafeArea() }
                    .navigationTitle(importTitle)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("取消") { showImportText = false } }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("导入") {
                                showImportText = false
                                doImport(importInput)
                            }.disabled(importInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
            }
            .sheet(isPresented: $showImportFile) {
                DocumentPicker(allowsMultiple: false) { urls in
                    showImportFile = false
                    guard let first = urls.first, let text = DocumentPicker.readText(first) else {
                        show("没有读到有效内容"); return
                    }
                    doImport(text)
                } onCancel: { showImportFile = false }
            }
            .sheet(item: $editing) { engine in
                HttpTTSEditView(engine: engine) { saved in
                    if let saved { HTTPTTSStore.shared.save(saved); engines.reload() }
                    editing = nil
                }
            }
            .sheet(isPresented: $showNewEditor) {
                HttpTTSEditView(engine: nil) { saved in
                    if var saved {
                        saved.id = Int64(Date().timeIntervalSince1970 * 1000)
                        HTTPTTSStore.shared.save(saved); engines.reload()
                    }
                    showNewEditor = false
                }
            }
            .sheet(item: $loginEngine) { engine in
                NavigationStack {
                    SourceLoginView(source: engine.bookSourceShim)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar { ToolbarItem(placement: .cancellationAction) {
                            Button("关闭") { loginEngine = nil }
                        } }
                }
            }
            .alert("删除朗读引擎？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button("取消", role: .cancel) {}
                Button("删除", role: .destructive) {
                    if let engine = deleting {
                        if AloudTTSConfig.selectedEngineID == "\(engine.id)" { aloud.selectEngine(nil) }
                        _ = HTTPTTSStore.shared.delete(id: engine.id)
                        engines.reload()
                    }
                }
            } message: { Text(deleting?.displayName ?? "") }
        }
        .onAppear { engines.reload() }
        .onDisappear { auditioner.cancel() }
        .onChange(of: aloud.isPlaying) { if $0 { auditioner.cancel() } }
        .onChange(of: aloud.isRunning) { if !$0 { auditioner.cancel() } }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.interruptionNotification)) { notice in
            if let type = notice.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
               type == AVAudioSession.InterruptionType.began.rawValue {
                auditioner.cancel()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { notice in
            if let reason = notice.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
               reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue {
                auditioner.cancel()
            }
        }
        .alert("试听失败", isPresented: Binding(get: { auditioner.errorMessage != nil },
                                           set: { if !$0 { auditioner.dismissError() } })) {
            Button("好", role: .cancel) { auditioner.dismissError() }
        } message: {
            Text(auditioner.errorMessage ?? "")
        }
    }

    private func engineRow(_ engine: HTTPTTS) -> some View {
        Button { choose(engine) } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(engine.displayName).appFont(.body).lineLimit(1)
                    Text(engine.url).appFont(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        .accessibilityIdentifier("tts.url.\(engine.id)")
                }
                Spacer(minLength: 0)
                if auditioner.engineID == engine.id {
                    if auditioner.isPlaying {
                        Image(systemName: "waveform").foregroundStyle(.tint)
                            .accessibilityLabel("正在试听")
                    } else {
                        ProgressView().controlSize(.small)
                            .accessibilityLabel("正在下载试听音频")
                    }
                }
                if selectedID == "\(engine.id)" {
                    Image(systemName: "checkmark").foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tts.row.\(engine.id)")
        .accessibilityHint("长按显示更多操作")
        .contextMenu { engineMenu(engine) }
    }

    /// 长按菜单：试听 + 原有操作。右侧三点入口已取消。
    @ViewBuilder
    private func engineMenu(_ engine: HTTPTTS) -> some View {
        Button { audition(engine) } label: {
            Label(auditioner.engineID == engine.id ? "取消试听" : "试听",
                  systemImage: auditioner.engineID == engine.id ? "stop.circle" : "play.circle")
        }
        .accessibilityIdentifier("tts.audition.\(engine.id)")
        Button("设为当前引擎") { choose(engine) }
        if engine.hasLogin {
            Button("登录") { auditioner.cancel(); loginEngine = engine }
        }
        Button("编辑") { auditioner.cancel(); editing = engine }
        Button("复制配置") {
            if let s = getSingleJSONText(engine), !s.isEmpty {
                UIPasteboard.general.string = s
                show("已复制引擎配置")
            }
        }
        Button("删除", role: .destructive) { auditioner.cancel(); deleting = engine }
    }

    /// 使用真实引擎和登录配置试听固定短句，正文保持暂停。
    private func audition(_ engine: HTTPTTS) {
        auditioner.toggle(engine: engine, reader: aloud)
    }

    private func getSingleJSONText(_ engine: HTTPTTS) -> String? {
        let store = HTTPTTSStore.shared
        return store.exportJSON(ids: [engine.id]).isEmpty ? nil : store.exportJSON(ids: [engine.id])
    }

    private func choose(_ engine: HTTPTTS?) {
        auditioner.cancel()
        aloud.selectEngine(engine)
        if let e = engine {
            if e.hasLogin, !hasLoginInfo(e) { loginEngine = e }
            show("当前引擎：\(e.displayName)")
        } else {
            show("已切换为系统语音")
        }
    }

    private func hasLoginInfo(_ engine: HTTPTTS) -> Bool {
        let info = JSEngine.loginStore.getLoginInfo(engine.key) ?? ""
        if info.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
        // 纯空白字符串数组也视为未登录
        return SourceLoginJSON.isBlank(info) == false
    }

    private func doImport(_ input: String) {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if text.hasPrefix("http://") || text.hasPrefix("https://"), !text.contains("{") {
            Task {
                if let (body, _) = try? await AnalyzeUrl(rawUrl: text).fetch(),
                   (body.contains("{")) {
                    let n = HTTPTTSStore.shared.importJSON(body)
                    engines.reload()
                    show(n > 0 ? "导入了 \(n) 个引擎" : "链接内容不是有效的引擎配置")
                } else {
                    show("下载失败或内容无效")
                }
            }
            return
        }
        let n = HTTPTTSStore.shared.importJSON(text)
        engines.reload()
        show(n > 0 ? "导入了 \(n) 个引擎" : "不是有效的引擎 JSON")
    }

    private func importClipboard() {
        let text = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { show("剪贴板为空"); return }
        doImport(text)
    }

    private func exportAll() {
        let json = HTTPTTSStore.shared.exportJSON()
        UIPasteboard.general.string = json
        show("已复制全部 \(engines.list.count) 个引擎的配置")
    }

    private func show(_ text: String) {
        message = text
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if message == text { message = nil }
        }
    }
}

/// 引擎列表数据：HTTPTTSStore 不是 ObservableObject，这里做薄包装。
final class SpeakEngineModel: ObservableObject {
    static let shared = SpeakEngineModel()
    @Published var list: [HTTPTTS] = []
    func reload() { list = HTTPTTSStore.shared.engines }
}
