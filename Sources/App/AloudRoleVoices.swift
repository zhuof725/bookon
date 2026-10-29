import AVFoundation
import Foundation

/// 每个角色可以选一个声线：系统音色（`sys:<identifier>`）或在线引擎（`tts:<id>`）。
/// 空字符串表示「跟随当前引擎」，等价于原来的单音色朗读。
struct AloudRoleVoiceConfig: Codable, Equatable {
    var enabled: Bool = false
    var narrator: String = ""
    var dialogue: String = ""
    var male: String = ""
    var female: String = ""
    /// 角色名 → 声线；值可以是 token，也可以是 `@male` / `@female`。
    var characters: [String: String] = [:]
    /// 朗读时自动收集到的角色名，按出现顺序保存。
    var knownNames: [String] = []

    static let maleAlias = "@male"
    static let femaleAlias = "@female"
}

/// 多角色声线配置（本地 UserDefaults，JSON）。
final class AloudRoleVoiceStore: ObservableObject {
    nonisolated(unsafe) static let shared = AloudRoleVoiceStore()
    static let storageKey = "reader.aloud.roles.v1"
    private static let maxKnownNames = 60

    @Published var config: AloudRoleVoiceConfig {
        didSet { save() }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let value = try? JSONDecoder().decode(AloudRoleVoiceConfig.self, from: data) {
            config = value
        } else {
            config = AloudRoleVoiceConfig()
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(config) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    /// 记录本章识别出的角色名；只追加，不删除用户已有的声线设置。
    func note(names: [String]) {
        var merged = config.knownNames
        for name in names where name.count >= 2 && !merged.contains(name) {
            merged.append(name)
        }
        guard merged != config.knownNames else { return }
        if merged.count > Self.maxKnownNames {
            merged = Array(merged.suffix(Self.maxKnownNames))
        }
        config.knownNames = merged
    }

    func resetCharacters() {
        config.knownNames.removeAll()
        config.characters.removeAll()
    }

    /// 第一次打开多角色时挑一个与当前音色不同的中文声部当「对话」，
    /// 否则开关打开也听不出区别。设备只有一个声部时保持跟随当前引擎。
    func autofillDialogueVoice() {
        guard config.dialogue.isEmpty else { return }
        let voices = AloudVoiceConfig.chineseVoices()
        guard voices.count > 1 else { return }
        let current = AloudVoiceConfig.selectedIdentifier
        let pick = voices.first { $0.id != current } ?? voices[1]
        config.dialogue = "sys:" + pick.id
    }
}

/// 解析后的实际声线：系统语音或在线引擎。
enum AloudVoiceChoice {
    case system(AVSpeechSynthesisVoice?)
    case engine(HTTPTTS)
}

enum AloudRoleVoiceResolver {
    /// 返回 nil 表示没有为这个角色单独配置，沿用当前朗读引擎。
    static func choice(for speaker: AloudSpeaker,
                       config: AloudRoleVoiceConfig) -> AloudVoiceChoice? {
        guard config.enabled else { return nil }
        let token: String
        switch speaker {
        case .narrator:
            token = config.narrator
        case let .dialogue(gender):
            token = dialogueToken(gender: gender, config: config)
        case let .character(name, gender):
            token = characterToken(name: name, gender: gender, config: config)
        }
        return resolve(token: token, config: config)
    }

    static func resolve(token: String, config: AloudRoleVoiceConfig) -> AloudVoiceChoice? {
        guard !token.isEmpty else { return nil }
        if token.hasPrefix("sys:") {
            let identifier = String(token.dropFirst(4))
            return .system(identifier.isEmpty ? nil : AVSpeechSynthesisVoice(identifier: identifier))
        }
        if token.hasPrefix("tts:"), let id = Int64(String(token.dropFirst(4))),
           let engine = HTTPTTSStore.shared.engine(id: id) {
            return .engine(engine)
        }
        // 兼容旧数据：裸的 AVSpeech 声部 identifier。
        return .system(AVSpeechSynthesisVoice(identifier: token))
    }

    private static func dialogueToken(gender: AloudGender?, config: AloudRoleVoiceConfig) -> String {
        switch gender {
        case .male: return firstNonEmpty(config.male, config.dialogue)
        case .female: return firstNonEmpty(config.female, config.dialogue)
        case nil: return config.dialogue
        }
    }

    private static func characterToken(name: String, gender: AloudGender?,
                                       config: AloudRoleVoiceConfig) -> String {
        let value = config.characters[name] ?? ""
        switch value {
        case "":
            return dialogueToken(gender: gender, config: config)
        case AloudRoleVoiceConfig.maleAlias:
            return firstNonEmpty(config.male, config.dialogue)
        case AloudRoleVoiceConfig.femaleAlias:
            return firstNonEmpty(config.female, config.dialogue)
        default:
            return value
        }
    }

    private static func firstNonEmpty(_ first: String, _ second: String) -> String {
        first.isEmpty ? second : first
    }
}

/// 拆段：开启多角色后把段落按引号切成旁白/对话，并记录识别到的角色名。
enum AloudMultiVoice {
    static func expand(_ list: [AloudUnit]) -> [AloudUnit] {
        let config = AloudRoleVoiceStore.shared.config
        guard config.enabled else { return list }
        let known = Set(config.knownNames)
        var result: [AloudUnit] = []
        var discovered: [String] = []

        for unit in list {
            let segments = AloudRoleParser.segments(in: unit.text, baseOffset: unit.offset,
                                                    knownNames: known)
            guard !segments.isEmpty else {
                result.append(unit)
                continue
            }
            var paragraph: [AloudUnit] = []
            for segment in segments {
                if case let .character(name, _) = segment.speaker,
                   !discovered.contains(name) {
                    discovered.append(name)
                }
                paragraph.append(AloudUnit(offset: segment.offset, text: segment.text,
                                           speaker: segment.speaker))
            }
            // 只在同一自然段内合并，避免把整章拼成一条超长请求。
            result.append(contentsOf: merged(paragraph, config: config))
        }
        if !discovered.isEmpty {
            AloudRoleVoiceStore.shared.note(names: discovered)
        }
        return result.isEmpty ? list : result
    }

    /// 相邻两段最终用的是同一个声线时合并，避免在线引擎为每个短句都发一次请求
    /// （只开多角色、还没配不同音色时尤其明显）。不同声线保持拆段。
    private static func merged(_ units: [AloudUnit],
                               config: AloudRoleVoiceConfig) -> [AloudUnit] {
        var output: [AloudUnit] = []
        for unit in units {
            if let last = output.last,
               voiceIdentity(for: last.speaker, config: config)
                == voiceIdentity(for: unit.speaker, config: config) {
                output[output.count - 1] = AloudUnit(offset: last.offset,
                                                     text: last.text + unit.text,
                                                     speaker: last.speaker)
            } else {
                output.append(unit)
            }
        }
        return output
    }

    /// 声线身份：空字符串表示跟随当前会话引擎；相同身份才允许合并。
    private static func voiceIdentity(for speaker: AloudSpeaker,
                                      config: AloudRoleVoiceConfig) -> String {
        switch speaker {
        case .narrator:
            return config.narrator
        case let .dialogue(gender):
            return dialogueIdentity(gender: gender, config: config)
        case let .character(name, gender):
            let value = config.characters[name] ?? ""
            switch value {
            case "":
                return dialogueIdentity(gender: gender, config: config)
            case AloudRoleVoiceConfig.maleAlias:
                return firstFilled(config.male, config.dialogue)
            case AloudRoleVoiceConfig.femaleAlias:
                return firstFilled(config.female, config.dialogue)
            default:
                return value
            }
        }
    }

    private static func dialogueIdentity(gender: AloudGender?,
                                         config: AloudRoleVoiceConfig) -> String {
        switch gender {
        case .male: return firstFilled(config.male, config.dialogue)
        case .female: return firstFilled(config.female, config.dialogue)
        case nil: return config.dialogue
        }
    }

    private static func firstFilled(_ first: String, _ second: String) -> String {
        first.isEmpty ? second : first
    }
}

/// 设置页可选的声线条目。
struct AloudVoiceOption: Identifiable, Hashable {
    let id: String
    let title: String
    let detail: String
}

enum AloudVoiceOptions {
    static func all() -> [AloudVoiceOption] {
        var items: [AloudVoiceOption] = []
        items += AloudVoiceConfig.chineseVoices().map {
            AloudVoiceOption(id: "sys:\($0.id)", title: $0.name, detail: $0.languageLabel)
        }
        items += SpeakEngineModel.shared.list.map {
            AloudVoiceOption(id: "tts:\($0.id)", title: $0.displayName, detail: "在线引擎")
        }
        return items
    }

    static func label(for token: String) -> String {
        switch token {
        case "": return "跟随当前引擎"
        case AloudRoleVoiceConfig.maleAlias: return "男声"
        case AloudRoleVoiceConfig.femaleAlias: return "女声"
        default: break
        }
        if token.hasPrefix("sys:") {
            let identifier = String(token.dropFirst(4))
            return AloudVoiceConfig.chineseVoices().first { $0.id == identifier }?.name ?? "系统音色"
        }
        if token.hasPrefix("tts:"), let id = Int64(String(token.dropFirst(4))),
           let engine = HTTPTTSStore.shared.engine(id: id) {
            return engine.displayName
        }
        return token
    }
}
