import AVFoundation

/// 系统语音（TTS）的音色选择：iPhone 上已安装的中文声部 + 记住用户选择。
///
/// iOS 自带的中文声部不止一个（婷婷/美嘉/善怡…），装了「增强/高级」音色后同一语言
/// 会出现多个条目；系统设置 → 辅助功能 → 朗读内容 → 声音 → 中文 里可以下载更多。
enum AloudVoiceConfig {
    private static let key = "reader.aloud.voice.v1"

    /// 选中的声部 identifier；空 = 跟随系统默认（zh-CN）。
    static var selectedIdentifier: String {
        get { UserDefaults.standard.string(forKey: key) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    static var selectedVoice: AVSpeechSynthesisVoice? {
        let id = selectedIdentifier
        guard !id.isEmpty else { return nil }
        return AVSpeechSynthesisVoice(identifier: id)
    }

    /// 朗读用声部：用户选的音色优先，否则中文（zh-CN）。
    static var speechVoice: AVSpeechSynthesisVoice? {
        selectedVoice ?? AVSpeechSynthesisVoice(language: "zh-CN")
    }

    struct Option: Identifiable, Hashable {
        let id: String
        let name: String
        let language: String
        let quality: Int

        var qualityLabel: String? {
            switch quality {
            case 3: return "高级"
            case 2: return "增强"
            default: return nil
            }
        }

        var languageLabel: String {
            switch language {
            case "zh-CN": return "普通话"
            case "zh-TW": return "台湾"
            case "zh-HK": return "粤语"
            default: return language
            }
        }
    }

    /// 系统里已安装的中文声部：普通话 → 台湾 → 粤语，同语言音质高的在前。
    static func chineseVoices() -> [Option] {
        let order: [String: Int] = ["zh-CN": 0, "zh-TW": 1, "zh-HK": 2]
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.lowercased().hasPrefix("zh") }
            .map { Option(id: $0.identifier, name: $0.name, language: $0.language,
                          quality: $0.quality.rawValue) }
            .sorted { a, b in
                let la = order[a.language] ?? 9, lb = order[b.language] ?? 9
                if la != lb { return la < lb }
                if a.quality != b.quality { return a.quality > b.quality }
                return a.name < b.name
            }
    }
}
