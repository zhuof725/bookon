import SwiftUI

/// 多角色朗读的角色声线设置：
/// 旁白 / 对话 / 男声 / 女声，以及朗读时自动收集到的具体角色。
struct AloudRoleSettingsView: View {
    @ObservedObject private var store = AloudRoleVoiceStore.shared
    @ObservedObject private var engines = SpeakEngineModel.shared
    @ThemePalette private var palette
    @State private var voices: [AloudVoiceConfig.Option] = []
    /// 用于从本页进入在线引擎管理；独立预览时可以为 nil。
    var aloud: ReaderAloudController?

    init(aloud: ReaderAloudController? = nil) {
        self.aloud = aloud
    }

    var body: some View {
        List {
            Section {
                Toggle("开启多角色朗读", isOn: $store.config.enabled)
                    .accessibilityIdentifier("aloud.role.enabled")
            } footer: {
                Text("按“”「」把正文拆成旁白与对话；能认出「林晚晴说道」这类提示时，切换成该角色的声线。")
            }

            Section {
                voiceRow("旁白", token: $store.config.narrator, id: "aloud.role.narrator")
                voiceRow("对话", token: $store.config.dialogue, id: "aloud.role.dialogue")
                voiceRow("男声", token: $store.config.male,
                         aliases: [(AloudRoleVoiceConfig.maleAlias, "跟随对话声线")],
                         id: "aloud.role.male")
                voiceRow("女声", token: $store.config.female,
                         aliases: [(AloudRoleVoiceConfig.femaleAlias, "跟随对话声线")],
                         id: "aloud.role.female")
            } header: {
                Text("基础声线")
            } footer: {
                Text("「跟随当前引擎」= 沿用音色面板里选的朗读引擎；每一行都可以改选在线引擎或系统音色。")
            }

            if let aloud {
                Section {
                    NavigationLink {
                        SpeakEngineList(aloud: aloud)
                    } label: {
                        Label("在线朗读引擎管理", systemImage: "waveform.badge.mic")
                    }
                    .accessibilityIdentifier("aloud.role.engines")
                } header: {
                    Text("在线引擎")
                } footer: {
                    Text("还没有在线引擎？在这里导入或新建，每个引擎就是一个音色。当前主引擎：\(AloudTTSConfig.engineLabel)。")
                }
            }

            Section {
                if store.config.knownNames.isEmpty {
                    Text("朗读几章后，这里会自动列出对话里出现的角色名。")
                        .appFont(.footnote)
                        .foregroundStyle(palette.secondary)
                } else {
                    ForEach(store.config.knownNames, id: \.self) { name in
                        characterRow(name)
                    }
                    Button("清空角色列表", role: .destructive) {
                        store.resetCharacters()
                    }
                }
            } header: {
                Text("角色声线")
            } footer: {
                Text("自动 = 按「他/她」提示选男声或女声；识别错了可以直接给角色指定一个音色。")
            }
        }
        .scrollContentBackground(.hidden)
        .background { AppThemeCanvas().ignoresSafeArea() }
        .navigationTitle("角色声线")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            engines.reload()
            voices = AloudVoiceConfig.chineseVoices()
        }
    }

    // MARK: - 行

    private func voiceRow(_ title: String, token: Binding<String>,
                          aliases: [(String, String)] = [], id: String) -> some View {
        voiceMenu(title: title, token: token, aliases: aliases)
            .accessibilityIdentifier(id)
    }

    private func characterRow(_ name: String) -> some View {
        let binding = Binding<String>(
            get: { store.config.characters[name] ?? "" },
            set: { value in
                if value.isEmpty { store.config.characters.removeValue(forKey: name) }
                else { store.config.characters[name] = value }
            })
        return voiceMenu(title: name, token: binding,
                         aliases: [(AloudRoleVoiceConfig.maleAlias, "男声"),
                                   (AloudRoleVoiceConfig.femaleAlias, "女声")])
            .accessibilityIdentifier("aloud.role.character.\(name)")
    }

    private struct AliasOption: Identifiable {
        let id: String
        let title: String
    }

    private func voiceMenu(title: String, token: Binding<String>,
                           aliases: [(String, String)]) -> some View {
        Menu {
            Button { token.wrappedValue = "" } label: { Text("跟随当前引擎") }
            if !aliases.isEmpty {
                Divider()
                ForEach(aliases.map { AliasOption(id: $0.0, title: $0.1) }) { item in
                    Button { token.wrappedValue = item.id } label: { Text(item.title) }
                }
            }
            if !engines.list.isEmpty {
                Section("在线引擎") {
                    ForEach(engines.list) { engine in
                        Button {
                            token.wrappedValue = "tts:\(engine.id)"
                        } label: {
                            Text(engine.displayName)
                        }
                    }
                }
            }
            if !voices.isEmpty {
                Section("系统音色") {
                    ForEach(voices) { voice in
                        Button {
                            token.wrappedValue = "sys:" + voice.id
                        } label: {
                            Text("\(voice.name)（\(voice.languageLabel)）")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 12) {
                Text(title).appFont(.body)
                Spacer(minLength: 8)
                Text(AloudVoiceOptions.label(for: token.wrappedValue))
                    .appFont(.subheadline)
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.secondary.opacity(0.6))
            }
            .contentShape(Rectangle())
        }
    }
}
