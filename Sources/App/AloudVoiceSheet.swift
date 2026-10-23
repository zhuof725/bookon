import SwiftUI

/// 听书播放器底栏「音色」面板：换朗读引擎 + 选系统音色 + 朗读设置。
///
/// - 系统语音：列出本机已安装的中文声部（普通话 / 台湾 / 粤语，含增强、高级音质）。
/// - 在线引擎：每个引擎就是一种音色（服务端合成），列出全部 HTTP TTS 引擎。
/// - 底栏的「设置」并到这里：朗读引擎管理、停止朗读。
struct AloudVoiceSheet: View {
    @ObservedObject var aloud: ReaderAloudController
    @ObservedObject var engines = SpeakEngineModel.shared
    @ThemePalette private var palette
    @Environment(\.dismiss) private var dismiss
    @State private var voices: [AloudVoiceConfig.Option] = []
    @State private var showEngineManager = false

    private var selectedEngineID: String { AloudTTSConfig.selectedEngineID }
    private var isSystem: Bool {
        selectedEngineID.isEmpty || selectedEngineID == "0" || AloudTTSConfig.selectedEngine == nil
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    engineRow(title: "系统语音", detail: "本机声部", selected: isSystem,
                              id: "aloud.voice.system") { aloud.selectEngine(nil) }
                    ForEach(engines.list) { engine in
                        engineRow(title: engine.displayName, detail: "在线引擎",
                                  selected: selectedEngineID == "\(engine.id)",
                                  id: "aloud.voice.engine.\(engine.id)") {
                            aloud.selectEngine(engine)
                        }
                    }
                } header: {
                    Text("朗读引擎")
                } footer: {
                    Text("每个在线引擎就是一种音色；需要更多音色可以在「朗读引擎管理」里导入。")
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
                        Text("更多音色：系统设置 → 辅助功能 → 朗读内容 → 声音 → 中文，下载后回到这里选择。")
                    }
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
        .onAppear { voices = AloudVoiceConfig.chineseVoices() }
        .sheet(isPresented: $showEngineManager) { SpeakEngineList(aloud: aloud) }
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
