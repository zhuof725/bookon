import SwiftUI

/// 听书播放器底栏「音色」面板：换朗读引擎 + 选系统音色 + 朗读设置。
///
/// - 系统语音：列出本机已安装的中文声部（普通话 / 台湾 / 粤语，含增强、高级音质）。
/// - 在线引擎：每个引擎就是一种音色（服务端合成），列出全部 HTTP TTS 引擎。
/// - 底栏的「设置」并到这里：朗读引擎管理、停止朗读。
struct AloudVoiceSheet: View {
    @ObservedObject var aloud: ReaderAloudController
    @ObservedObject var engines = SpeakEngineModel.shared
    /// 当前正在读的书：这本书所属的书源可以「用这个音色听这本书」。
    var currentBook: Book? = nil
    var currentChapter: BookChapter? = nil
    var onUseSourceTone: (@MainActor (BookSource, SourceTone.Item) async -> Bool)? = nil
    /// 切到系统语音/在线引擎时：停掉正在播的书源音频，改回朗读。
    var onStopSourceAudio: (() -> Void)? = nil
    @ObservedObject private var store = AppStore.shared
    @ObservedObject private var roleVoices = AloudRoleVoiceStore.shared
    @ObservedObject private var purify = AloudPurifyStore.shared
    @AppStorage(SourceToneAudio.backgroundKey) private var backgroundPlayback = false
    @ThemePalette private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var voices: [AloudVoiceConfig.Option] = []
    @State private var showEngineManager = false
    @State private var toneSources: [BookSource] = []
    @State private var toneSummaries: [String: String] = [:]

    private var selectedEngineID: String { AloudTTSConfig.selectedEngineID }

    private var roleSummary: String {
        guard roleVoices.config.enabled else { return "关闭：整章使用同一个声音" }
        let count = roleVoices.config.knownNames.count
        return count > 0 ? "已识别 \(count) 个角色，可按角色指定声线"
                         : "打开后按引号区分旁白与对话"
    }
    private var isSystem: Bool {
        selectedEngineID.isEmpty || selectedEngineID == "0" || AloudTTSConfig.selectedEngine == nil
    }

    /// 当前书的音色可用性探测（按这本书的章节，结果按书缓存）。
    private func sourceProbe(for source: BookSource) -> SourceToneList.Probe? {
        guard let book = currentBook, book.origin == source.bookSourceUrl,
              let chapter = currentChapter, SourceToneAudio.canProbe(source: source) else { return nil }
        let canProbe = SourceToneAudio.canProbe(source: source)
        return SourceToneList.Probe(
            cached: { tone in
                SourceToneAudio.cachedAvailability(bookUrl: book.bookUrl, tone: tone)
            },
            run: { group, tone in
                let ok: Bool
                if canProbe {
                    ok = await SourceToneAudio.probe(tone: tone.value, source: source, chapter: chapter)
                } else {
                    ok = await SourceToneAudio.probeViaRule(tone: tone, group: group,
                                                            source: source, book: book, chapter: chapter)
                }
                SourceToneAudio.storeAvailability(ok, bookUrl: book.bookUrl, tone: tone.value)
                return ok
            },
            reset: { SourceToneAudio.clearAvailability(bookUrl: book.bookUrl) },
            auto: canProbe)
    }

    /// 只有当前这本书所属的书源，才提供「用这个音色听这本书」。
    private func useSourceToneHandler(for source: BookSource) -> ((SourceTone.Item) async -> Bool)? {
        guard let book = currentBook, book.origin == source.bookSourceUrl,
              let handler = onUseSourceTone else { return nil }
        return { tone in await handler(source, tone) }
    }

    private func toneLabel(_ source: BookSource) -> String {
        toneSummaries[source.bookSourceUrl] ?? "默认音色"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    engineRow(title: "系统语音", detail: "本机声部", selected: isSystem,
                              id: "aloud.voice.system") {
                        aloud.selectEngine(nil)
                        onStopSourceAudio?()
                    }
                    ForEach(engines.list) { engine in
                        engineRow(title: engine.displayName, detail: "在线引擎",
                                  selected: selectedEngineID == "\(engine.id)",
                                  id: "aloud.voice.engine.\(engine.id)") {
                            aloud.selectEngine(engine)
                            onStopSourceAudio?()
                        }
                    }
                } header: {
                    Text("朗读引擎")
                }

                if isSystem {
                    Section {
                        if voices.isEmpty {
                            Text("这台设备没有可用的中文声部")
                                .appFont(.footnote).foregroundStyle(palette.secondary)
                        } else {
                            ForEach(voices) { voice in
                                voiceRow(voice)
                            }
                        }
                    } header: {
                        Text("系统音色")
                    } footer: {
                        Text("更多声部：设置 → 辅助功能 → 朗读内容 → 声音 → 中文。")
                    }
                }

                Section {
                    Toggle(isOn: Binding(
                        get: { roleVoices.config.enabled },
                        set: { value in
                            roleVoices.config.enabled = value
                            if value { roleVoices.autofillDialogueVoice() }
                            aloud.reloadRoleVoices()
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("多角色朗读").appFont(.body)
                            Text(roleSummary)
                                .appFont(.caption)
                                .foregroundStyle(palette.secondary)
                        }
                    }
                    .accessibilityIdentifier("aloud.voice.roles")

                    NavigationLink {
                        AloudRoleSettingsView(aloud: aloud)
                    } label: {
                        HStack(spacing: 12) {
                            Label("角色声线", systemImage: "person.2.wave.2")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(palette.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("aloud.voice.roleSettings")
                } header: {
                    Text("多角色朗读")
                }

                Section {
                    NavigationLink {
                        AloudPurifySettingsView()
                    } label: {
                        HStack(spacing: 12) {
                            Label("朗读净化", systemImage: "text.badge.minus")
                            Spacer()
                            Text(purify.enabled
                                 ? (purify.rules.isEmpty ? "内置清理" : "\(purify.rules.count) 条规则")
                                 : "已关闭")
                                .appFont(.caption)
                                .foregroundStyle(palette.secondary)
                        }
                    }
                    .accessibilityIdentifier("aloud.voice.purify")
                } header: {
                    Text("朗读净化")
                }

                Section {
                    if toneSources.isEmpty {
                        Text("没有书源提供音色表（目前只有番茄源这类带 _getTones 的源）。")
                            .appFont(.footnote).foregroundStyle(palette.secondary)
                    } else {
                        ForEach(toneSources) { source in
                            NavigationLink {
                                SourceToneList(source: source,
                                               onUseForBook: useSourceToneHandler(for: source),
                                               probe: sourceProbe(for: source),
                                               currentBook: currentBook)
                                    .navigationTitle(source.bookSourceName)
                                    .navigationBarTitleDisplayMode(.inline)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(source.bookSourceName).appFont(.body).lineLimit(1)
                                    Text(toneLabel(source))
                                        .appFont(.caption).foregroundStyle(palette.secondary).lineLimit(1)
                                }
                            }
                            .accessibilityIdentifier("aloud.voice.source.\(source.bookSourceUrl)")
                        }
                    }
                } header: {
                    Text("书源音色")
                }

                Section {
                    Toggle(isOn: $backgroundPlayback) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("正文照常显示").appFont(.body)
                            Text("后台播放，阅读页保留正文")
                                .appFont(.caption).foregroundStyle(palette.secondary)
                        }
                    }
                    .accessibilityIdentifier("aloud.voice.background")
                }

                Section {
                    AloudPreloadCard()
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

                Section {
                    Button { showEngineManager = true } label: {
                        HStack(spacing: 12) {
                            Label("朗读引擎管理", systemImage: "waveform.badge.mic")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption).foregroundStyle(palette.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("aloud.voice.engines")

                    Button(role: .destructive) {
                        aloud.stop()
                        dismiss()
                    } label: {
                        Label("停止朗读", systemImage: "stop.circle")
                    }
                    .accessibilityIdentifier("aloud.voice.stop")
                }
            }
            .scrollContentBackground(.hidden)
            .background { AppThemeCanvas().ignoresSafeArea() }
            .navigationTitle("音色")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .accessibilityIdentifier("aloud.voice.close")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            engines.reload()
            voices = AloudVoiceConfig.chineseVoices()
        }
        .task { await loadToneSources() }
        .sheet(isPresented: $showEngineManager) { SpeakEngineList(aloud: aloud) }
    }

    /// 找出所有带音色表的书源（要扫脚本，放到后台做）。
    private func loadToneSources() async {
        let sources = store.sources
        let origin = currentBook?.origin
        let result = await Task.detached { () -> ([BookSource], [String: String]) in
            // 只列这本书自己的书源（别的源音色对这本书没意义）。
            let matched = sources.filter { source in
                guard let origin, source.bookSourceUrl == origin else { return false }
                return SourceTone.hasTones(source: source)
            }
            var summaries: [String: String] = [:]
            for source in matched {
                summaries[source.bookSourceUrl] = SourceTone.summary(source: source)
            }
            return (matched, summaries)
        }.value
        toneSources = result.0
        toneSummaries = result.1
    }

    private func engineRow(title: String, detail: String, selected: Bool, id: String,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).appFont(.body)
                    Text(detail).appFont(.caption).foregroundStyle(palette.secondary)
                }
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: "checkmark").foregroundStyle(palette.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    private func voiceRow(_ voice: AloudVoiceConfig.Option) -> some View {
        let selected = AloudVoiceConfig.selectedIdentifier == voice.id
        return Button {
            AloudVoiceConfig.selectedIdentifier = voice.id
            aloud.applyVoiceChange()
        } label: {
            HStack(spacing: 8) {
                Text(voice.name).appFont(.body)
                Text(voice.languageLabel).appFont(.caption).foregroundStyle(palette.secondary)
                if let quality = voice.qualityLabel {
                    Text(quality)
                        .appFont(.caption2)
                        .foregroundStyle(palette.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(palette.accent.opacity(0.14)))
                }
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: "checkmark").foregroundStyle(palette.accent)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("aloud.voice.voice.\(voice.id)")
    }
}
