import Foundation

/// 有声书的「音色」：不是本机 TTS 声部，而是书源自己带的朗读音色。
///
/// 以番茄源为例：jsLib 里定义了 `_getTones()`（真人 / 甜美少女 / 清亮青叔… 几十个），
/// 选中的音色存在源变量的 `tone`（`tone_id=1`）和 `tone_cn` 里，切换由 loginUrl 的
/// `setVoice(n)` 完成（同时写源变量与源自己的配置缓存）。章节音频地址就是按 `tone`
/// 拼出来的，所以换音色后要重新取一次本章音频。
///
/// 书源没有这套约定时 `tones()` 返回空数组，界面降级为「打开书源设置」。
enum SourceTone {
    struct Item: Identifiable, Hashable {
        let index: Int
        let name: String
        let value: String
        var id: Int { index }
    }

    /// 当前音色（源变量里的 tone / tone_cn）。
    static func current(source: BookSource) -> (name: String, value: String) {
        let dict = configDictionary(source: source)
        let value = string(dict["tone"])
        let name = string(dict["tone_cn"])
        return (name, value)
    }

    /// 书源脚本提供的音色表；没有 `_getTones()` 时为空。
    static func tones(source: BookSource) -> [Item] {
        let script = "JSON.stringify((typeof _getTones === 'function') ? _getTones() : [])"
        guard let json = JSEngine.shared.evalString(script, jsLib: source.jsLib,
                                                    context: RuleContext(source: source)),
              let data = json.data(using: .utf8),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[Any]] else {
            return []
        }
        return rows.enumerated().compactMap { index, row in
            guard row.count >= 2 else { return nil }
            let name = string(row[0])
            guard !name.isEmpty else { return nil }
            return Item(index: index, name: name, value: string(row[1]))
        }
    }

    /// 应用第 `index` 个音色：先跑书源自己的 `setVoice(index)`（它知道要写到哪几处），
    /// 脚本不可用时退回直接改源变量的 tone / tone_cn。
    @discardableResult
    static func apply(_ item: Item, source: BookSource) -> Bool {
        let script = "(function(){try{setVoice(\(item.index));return 'ok';}catch(e){return 'err:'+e;}})()"
        let output = JSEngine.shared.evalString(script, jsLib: source.jsLib,
                                                loginLib: SourceLoginForm.loginScript(source.loginUrl),
                                                context: RuleContext(source: source)) ?? ""
        if output == "ok" {
            let now = current(source: source)
            if now.value == item.value || (!item.value.isEmpty && now.value == item.value) { return true }
        }
        // setVoice 不存在/失败：直接写源变量，至少让下一次取章节用上新音色。
        writeConfig(source: source, tone: item.value,
                    toneName: item.value.isEmpty ? "" : item.name + "(\(item.value))")
        return current(source: source).value == item.value
    }

    // MARK: 源变量读写

    private static func configDictionary(source: BookSource) -> [String: Any] {
        guard let data = SourceVariable.get(source.bookSourceUrl).data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return obj
    }

    private static func writeConfig(source: BookSource, tone: String, toneName: String) {
        var dict = configDictionary(source: source)
        dict["tone"] = tone
        dict["tone_cn"] = toneName
        guard JSONSerialization.isValidJSONObject(dict),
              let data = try? JSONSerialization.data(withJSONObject: dict),
              let text = String(data: data, encoding: .utf8) else { return }
        SourceVariable.set(text, for: source.bookSourceUrl)
    }

    private static func string(_ value: Any?) -> String {
        switch value {
        case let s as String: return s
        case let n as NSNumber: return n.stringValue
        case .none, is NSNull: return ""
        default: return String(describing: value ?? "")
        }
    }
}
