import Foundation

/// 书源自带的「音色」（有声书/听书的朗读音色）。
///
/// 目前书源里有两类写法，这里都认：
/// 1. **函数式**（番茄源）：jsLib 里 `_getTones()` 返回 `[[名字, tone_id=…], …]`，
///    当前值存在源变量的 `tone` / `tone_cn`，切换调 loginUrl 的 `setVoice(n)`。
/// 2. **声明式**（书山聚合这类聚合源）：脚本里 `xxxTones = [{id,name}, …]`，
///    当前值存在源变量配置的 `xxx_tts_tone` 键里，直接写配置即可。
///
/// 书源两样都没有时返回空，界面降级为「打开书源设置」。
enum SourceTone {
    struct Item: Identifiable, Hashable {
        let index: Int
        let name: String
        let value: String
        var id: String { "\(index)#\(value)" }
    }

    struct Group: Identifiable {
        enum Kind: Equatable {
            /// 番茄式：源变量 tone/tone_cn + setVoice(index)。
            case legacy
            /// 声明式：配置键 = 音色 id。
            case declared(key: String)
        }
        let id: String
        let title: String
        let kind: Kind
        let tones: [Item]
        let currentValue: String
    }

    // MARK: 探测

    /// 这个书源有没有音色表（只做字符串检查，读列表时才求值脚本）。
    static func hasTones(source: BookSource) -> Bool {
        let script = scriptText(source)
        if script.contains("_getTones") { return true }
        guard script.contains("_tts_tone"), script.contains("Tones =") || script.contains("Tones=") else {
            return false
        }
        return !declaredArrays(in: script).isEmpty
    }

    /// 轻量摘要（当前配置里已选的音色），不执行脚本。
    static func summary(source: BookSource) -> String {
        let config = configDictionary(source: source)
        var parts: [String] = []
        for key in declaredKeys(source: source) {
            let value = string(config[key])
            if !value.isEmpty { parts.append("\(title(forKey: key)) \(value)") }
        }
        let tone = string(config["tone"])
        if !tone.isEmpty {
            let name = string(config["tone_cn"])
            parts.append(name.isEmpty ? tone : name)
        }
        return parts.isEmpty ? "默认音色" : parts.joined(separator: " · ")
    }

    /// 音色分组：先看函数式，再看声明式。
    static func groups(source: BookSource) -> [Group] {
        let config = configDictionary(source: source)
        var groups: [Group] = []
        if let tones = legacyTones(source: source), !tones.isEmpty {
            groups.append(Group(id: "legacy", title: "音色", kind: .legacy,
                                tones: tones, currentValue: string(config["tone"])))
        }
        let script = scriptText(source)
        for array in declaredArrays(in: script) {
            let key = array.prefix.lowercased() + "_tts_tone"
            guard script.contains(key) else { continue }
            if groups.contains(where: { $0.id == key }) { continue }
            // 书源的音色表常常没有「真人」这一项（番茄的 tone_id=0），补一个默认项。
            var tones = array.tones
            if !tones.contains(where: { $0.value == "0" || $0.value == "tone_id=0" }) {
                tones.insert(Item(index: -1, name: "真人（默认）", value: "0"), at: 0)
            }
            groups.append(Group(id: key, title: title(forKey: key), kind: .declared(key: key),
                                tones: tones, currentValue: string(config[key])))
        }
        return groups
    }

    /// 应用一个音色（函数式优先跑书源自己的 setVoice）。
    @discardableResult
    static func apply(_ item: Item, in group: Group, source: BookSource) -> Bool {
        switch group.kind {
        case .legacy:
            return applyLegacy(item, source: source)
        case .declared(let key):
            // 书山聚合这类源的配置是 `[config]` 数组：变量为空时也要写成数组，
            // 否则 getConfig() 的 Array.isArray 检查会退回默认值、我们的键读不到。
            let prefersArray = scriptText(source).contains("JSON.stringify([")
            writeConfig(source: source, prefersArray: prefersArray) { dict in
                dict[key] = item.value
            }
            return string(configDictionary(source: source)[key]) == item.value
        }
    }

    // MARK: 函数式（番茄）

    private static func legacyTones(source: BookSource) -> [Item]? {
        let script = "JSON.stringify((typeof _getTones === 'function') ? _getTones() : [])"
        guard let json = JSEngine.shared.evalString(script, jsLib: source.jsLib,
                                                    context: RuleContext(source: source)),
              let data = json.data(using: .utf8),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[Any]] else {
            return nil
        }
        return rows.enumerated().compactMap { index, row in
            guard row.count >= 2 else { return nil }
            let name = string(row[0])
            guard !name.isEmpty else { return nil }
            return Item(index: index, name: name, value: string(row[1]))
        }
    }

    private static func applyLegacy(_ item: Item, source: BookSource) -> Bool {
        let script = "(function(){try{setVoice(\(item.index));return 'ok';}catch(e){return 'err:'+e;}})()"
        let output = JSEngine.shared.evalString(script, jsLib: source.jsLib,
                                                loginLib: SourceLoginForm.loginScript(source.loginUrl),
                                                context: RuleContext(source: source)) ?? ""
        if output == "ok", string(configDictionary(source: source)["tone"]) == item.value {
            return true
        }
        writeConfig(source: source) { dict in
            dict["tone"] = item.value
            dict["tone_cn"] = item.value.isEmpty ? "" : "\(item.name)(\(item.value))"
        }
        return string(configDictionary(source: source)["tone"]) == item.value
    }

    // MARK: 声明式数组解析

    private struct DeclaredArray {
        let prefix: String
        let tones: [Item]
    }

    /// 脚本里 `xxxTones = [{id, name}, …]` 的数组。
    private static func declaredArrays(in script: String) -> [DeclaredArray] {
        var result: [DeclaredArray] = []
        let pattern = "([A-Za-z_$][A-Za-z0-9_$]*)Tones\\s*=\\s*\\["
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = script as NSString
        for match in regex.matches(in: script, range: NSRange(location: 0, length: ns.length)) {
            guard match.numberOfRanges >= 2 else { continue }
            let name = ns.substring(with: match.range(at: 1))
            let bodyStart = match.range.location + match.range.length
            guard let body = bracketBody(in: ns, from: bodyStart) else { continue }
            let tones = parseToneItems(body)
            guard tones.count >= 2 else { continue }
            result.append(DeclaredArray(prefix: name, tones: tones))
        }
        return result
    }

    /// 从 `[` 后面开始找到配对的 `]`（跳过字符串里的括号）。
    private static func bracketBody(in text: NSString, from start: Int) -> String? {
        let doubleQuote: unichar = 34, singleQuote: unichar = 39
        let backslash: unichar = 92, open: unichar = 91, close: unichar = 93
        var depth = 1
        var i = start
        var inString: unichar = 0
        while i < text.length {
            let c = text.character(at: i)
            if inString != 0 {
                if c == inString, i == 0 || text.character(at: i - 1) != backslash {
                    inString = 0
                }
            } else if c == doubleQuote || c == singleQuote {
                inString = c
            } else if c == open {
                depth += 1
            } else if c == close {
                depth -= 1
                if depth == 0 {
                    return text.substring(with: NSRange(location: start, length: i - start))
                }
            }
            i += 1
        }
        return nil
    }

    private static func parseToneItems(_ body: String) -> [Item] {
        var items: [Item] = []
        let pattern = "\\{\\s*(?:id\\s*:\\s*[\"']?([^\"',}\\s]+)[\"']?\\s*,\\s*name\\s*:\\s*[\"']([^\"']*)[\"']"
            + "|name\\s*:\\s*[\"']([^\"']*)[\"']\\s*,\\s*id\\s*:\\s*[\"']?([^\"',}\\s]+)[\"']?)\\s*\\}"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = body as NSString
        for (index, match) in regex.matches(in: body, range: NSRange(location: 0, length: ns.length)).enumerated() {
            let (idRange, nameRange) = match.range(at: 1).location != NSNotFound
                ? (match.range(at: 1), match.range(at: 2))
                : (match.range(at: 4), match.range(at: 3))
            guard idRange.location != NSNotFound, nameRange.location != NSNotFound else { continue }
            let value = ns.substring(with: idRange).trimmingCharacters(in: .whitespacesAndNewlines)
            let name = ns.substring(with: nameRange).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, !name.isEmpty else { continue }
            items.append(Item(index: index, name: name, value: value))
        }
        return items
    }

    // MARK: 配置键

    private static func declaredKeys(source: BookSource) -> [String] {
        let script = scriptText(source)
        var keys: [String] = []
        for array in declaredArrays(in: script) {
            let key = array.prefix.lowercased() + "_tts_tone"
            if script.contains(key), !keys.contains(key) { keys.append(key) }
        }
        return keys
    }

    private static func title(forKey key: String) -> String {
        switch key.lowercased() {
        case "fanqie_tts_tone": return "番茄"
        case "shuqi_tts_tone": return "书旗"
        default:
            let prefix = key.replacingOccurrences(of: "_tts_tone", with: "")
            return prefix.isEmpty ? "音色" : prefix
        }
    }

    private static func scriptText(_ source: BookSource) -> String {
        [source.jsLib, source.loginUrl, source.loginUi]
            .compactMap { $0 }
            .joined(separator: "\n")
    }

    // MARK: 源变量读写（对象或 [对象] 两种形状都保留）

    private static func configDictionary(source: BookSource) -> [String: Any] {
        guard let data = SourceVariable.get(source.bookSourceUrl).data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return [:]
        }
        if let dict = object as? [String: Any] { return dict }
        if let list = object as? [[String: Any]], let first = list.first { return first }
        return [:]
    }

    private static func writeConfig(source: BookSource, prefersArray: Bool = false,
                                    update: (inout [String: Any]) -> Void) {
        let raw = SourceVariable.get(source.bookSourceUrl)
        var isArray = false
        var dict: [String: Any] = [:]
        if let data = raw.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) {
            if let list = object as? [[String: Any]] {
                isArray = true
                dict = list.first ?? [:]
            } else if let obj = object as? [String: Any] {
                dict = obj
            }
        }
        update(&dict)
        let useArray = isArray || (raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && prefersArray)
        let output: Any = useArray ? [dict] : dict
        guard JSONSerialization.isValidJSONObject(output),
              let data = try? JSONSerialization.data(withJSONObject: output),
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
