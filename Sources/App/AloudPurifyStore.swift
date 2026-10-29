import Combine
import Foundation

/// 朗读净化设置：开关 + 自定义替换规则 + 是否套用正文替换规则。
/// 只影响送进 TTS 的文字，不改阅读页正文。
final class AloudPurifyStore: ObservableObject {
    nonisolated(unsafe) static let shared = AloudPurifyStore()
    static let enabledKey = "reader.aloud.purify.enabled.v1"
    static let rulesKey = "reader.aloud.purify.rules.v1"
    static let useBodyRulesKey = "reader.aloud.purify.useBody.v1"

    @Published var enabled: Bool {
        didSet { defaults.set(enabled, forKey: Self.enabledKey) }
    }
    @Published var useBodyRules: Bool {
        didSet {
            defaults.set(useBodyRules, forKey: Self.useBodyRulesKey)
            bodyEngine = nil
        }
    }
    @Published var rules: [BodyReplaceRule] {
        didSet {
            saveRules()
            engine = nil
        }
    }

    private let defaults = UserDefaults.standard
    private var engine: BodyReplaceEngine?
    private var bodyEngine: BodyReplaceEngine?

    private init() {
        enabled = defaults.object(forKey: Self.enabledKey) as? Bool ?? true
        useBodyRules = defaults.object(forKey: Self.useBodyRulesKey) as? Bool ?? false
        if let data = defaults.data(forKey: Self.rulesKey),
           let decoded = try? JSONDecoder().decode([BodyReplaceRule].self, from: data) {
            rules = Array(decoded.prefix(50))
        } else {
            rules = []
        }
    }

    private func saveRules() {
        guard let data = try? JSONEncoder().encode(Array(rules.prefix(50))) else { return }
        defaults.set(data, forKey: Self.rulesKey)
    }

    /// 朗读前净化一段文字：先走内置清理，再按顺序套自定义规则/正文替换规则。
    func purify(_ text: String) -> String {
        guard enabled else { return text }
        var value = AloudPurifier.clean(text)
        if useBodyRules {
            if bodyEngine == nil {
                bodyEngine = BodyReplaceEngine(rules: BodyReplaceRepository().rules())
            }
            if let bodyEngine { value = bodyEngine.apply(value) }
        }
        if engine == nil { engine = BodyReplaceEngine(rules: rules) }
        if let engine { value = engine.apply(value) }
        return value
    }

    /// 正文替换规则可能在别处改过：进入新章节时让缓存失效。
    func reloadBodyRules() {
        bodyEngine = nil
    }

    static let recommendedRules: [BodyReplaceRule] = [
        BodyReplaceRule(id: "purify-url", name: "删除网址", pattern: #"(?:https?://|www\.)\S+"#,
                        replacement: "", isRegex: true, enabled: true),
        BodyReplaceRule(id: "purify-ending", name: "删除本章完/未完待续",
                        pattern: #"[（(【\[]?(?:本章未完|本章完|未完待续|全文完)[）)】\]]?"#,
                        replacement: "", isRegex: true, enabled: true),
        BodyReplaceRule(id: "purify-votes", name: "删除求票求收藏",
                        pattern: #"(?:求收藏|求推荐|求月票|求订阅|推荐票)[^。！？!?\n]{0,20}"#,
                        replacement: "", isRegex: true, enabled: true)
    ]
}

/// 所有送进 TTS 的文字都从这里过一遍，播放和预取用的是同一份文本（缓存键才对得上）。
enum AloudSpeechText {
    static func prepare(_ text: String) -> String? {
        AloudText.speakText(for: AloudPurifyStore.shared.purify(text))
    }
}
