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
            /// 番茄 v2 真人录播：源变量 abook/abookBid/abookName，tone 置 0。
            case realPerson(bookID: String)
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
        // 番茄 v2：音色表不在脚本里，要按当前书调 toneinfo 接口（见 dynamicTones）。
        if script.contains("toneinfo"), script.contains("fanqieSignHeaders") { return true }
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
        let abookName = string(config["abookName"])
        let abook = string(config["abook"])
        if !abook.isEmpty {
            parts.append(abookName.isEmpty ? "真人录播 \(abook)" : "真人 · \(abookName)")
        }
        let tone = string(config["tone"])
        if !tone.isEmpty, abook.isEmpty || tone != "0" {
            let name = string(config["tone_cn"])
            parts.append(name.isEmpty ? tone : name)
        }
        return parts.isEmpty ? "默认音色" : parts.joined(separator: " · ")
    }

    /// 音色分组：先看函数式，再看声明式，最后按当前书动态取（番茄 v2）。
    static func groups(source: BookSource, book: Book? = nil) -> [Group] {
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
            groups.append(Group(id: key, title: title(forKey: key), kind: .declared(key: key),
                                tones: array.tones, currentValue: string(config[key])))
        }
        if groups.isEmpty, let book, let dynamic = dynamicTones(source: source, book: book) {
            groups.append(contentsOf: dynamic)
        }
        return groups
    }

    /// 当前分组已选的音色值。
    static func currentValue(group: Group, source: BookSource) -> String {
        let config = configDictionary(source: source)
        switch group.kind {
        case .legacy: return string(config["tone"])
        case .declared(let key): return string(config[key])
        case .realPerson: return string(config["abook"])
        }
    }

    /// 静默写入音色（探测用，不提示、不刷新）。
    static func setValue(_ value: String, group: Group, source: BookSource) {
        switch group.kind {
        case .legacy:
            writeConfig(source: source) { dict in
                dict["tone"] = value
                dict["tone_cn"] = value
                // 之前被书源判过「不支持」的标记要清掉，否则一直回落到默认音色。
                dict["toneBad"] = ""
                // 真人录播的 abook 优先级更高，切回合成音色时必须清掉。
                dict["abook"] = ""
                dict["abookName"] = ""
                dict["abookBid"] = ""
            }
        case .declared(let key):
            let prefersArray = scriptText(source).contains("JSON.stringify([")
            writeConfig(source: source, prefersArray: prefersArray) { dict in
                dict[key] = value
            }
        case .realPerson(let bookID):
            writeConfig(source: source) { dict in
                dict["abook"] = value
                dict["abookName"] = value
                dict["abookBid"] = bookID
                dict["tone"] = "0"
                dict["toneBad"] = ""
            }
        }
    }

    /// 应用一个音色（函数式优先跑书源自己的 setVoice）。
    @discardableResult
    static func apply(_ item: Item, in group: Group, source: BookSource) -> Bool {
        switch group.kind {
        case .legacy:
            return applyLegacy(item, source: source)
        case .realPerson(let bookID):
            writeConfig(source: source) { dict in
                dict["abook"] = item.value
                dict["abookName"] = item.name
                dict["abookBid"] = bookID
                dict["tone"] = "0"
                dict["tone_cn"] = item.name
                dict["toneBad"] = ""
            }
            return string(configDictionary(source: source)["abook"]) == item.value
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
            // 之前失败留下的 toneBad 会让书源直接回落默认音色，换音色时必须清掉。
            dict["toneBad"] = ""
            // 真人录播的 abook 优先级更高，切回合成音色时必须清掉。
            dict["abook"] = ""
            dict["abookName"] = ""
            dict["abookBid"] = ""
        }
        return string(configDictionary(source: source)["tone"]) == item.value
    }

    // MARK: 动态音色（番茄 v2）

    /// 番茄 v2 的脚本里没有音色数组，音色来自 `bookapi/audio/toneinfo`：
    /// - `tts_tones`：合成音色（tone_id）
    /// - `audio_tones`：真人录播（abook_id）
    /// 注意：abook_id 是 19 位数字，**不能**在 JS 里 JSON.parse 后再 String()——
    /// JavaScript 的 Number 只有 53 位精度，会变成 …000 的假 id（书源面板也踩过这个坑）。
    /// 这里让 JS 只负责取回原始 JSON 文本，Swift 用 Int64/字符串解码，保证位数不变。
    private static func dynamicTones(source: BookSource, book: Book) -> [Group]? {
        let script = scriptText(source)
        guard script.contains("toneinfo"), script.contains("fanqieSignHeaders") else { return nil }
        guard let bid = bookID(from: book.bookUrl) else { return nil }
        let js = """
        (function(){
          try{
            var u = FQ_BASE + "/bookapi/audio/toneinfo/?" + FQ_P + "&book_id=" + String(__fqBookId);
            var h = fanqieSignHeaders(String(u), null);
            h["Cookie"] = "install_id=" + FQ_IID;
            var hm = new Packages.java.util.HashMap();
            for(var k in h){ hm.put(String(k), String(h[k])); }
            return String(java.get(String(u), hm).body());
          }catch(e){ return ""; }
        })()
        """
        guard let body = JSEngine.shared.evalString(js, vars: ["__fqBookId": bid],
                                                    jsLib: source.jsLib,
                                                    context: RuleContext(source: source, book: book)),
              !body.isEmpty, let data = body.data(using: .utf8),
              let info = try? JSONDecoder().decode(ToneInfoPayload.self, from: data) else { return nil }
        let config = configDictionary(source: source)
        var groups: [Group] = []
        let tts = (info.data?.tts_tones ?? []).enumerated().compactMap { index, tone -> Item? in
            guard let id = tone.id?.value, !id.isEmpty else { return nil }
            let name = tone.title ?? tone.name ?? "音色\(id)"
            return Item(index: index, name: name, value: id)
        }
        if !tts.isEmpty {
            groups.append(Group(id: "dynamic", title: "音色", kind: .legacy,
                                tones: tts, currentValue: string(config["tone"])))
        }
        let audio = (info.data?.audio_tones ?? []).enumerated().compactMap { index, tone -> Item? in
            guard let id = tone.abook_id?.value, !id.isEmpty else { return nil }
            let name = tone.title ?? tone.name ?? "真人\(id)"
            return Item(index: index, name: name, value: id)
        }
        if !audio.isEmpty {
            groups.append(Group(id: "dynamic-real", title: "真人录播",
                                kind: .realPerson(bookID: bid),
                                tones: audio, currentValue: string(config["abook"])))
        }
        return groups
    }

    enum ToneProbeResult {
        /// 这个音色没有音频，书源会回落默认音色。
        case unavailable
        /// 书源对不同音色返回了同一个音频：这本书只有一版录音，换音色不会变声。
        case sameAsDefault
        /// 有独立音频，可以切换。
        case playable
    }

    /// 用当前章节问一次 playinfo，比较「所选音色」和「默认音色」的音频。
    /// 注意签名地址每次都会变（host/token），只能比较去掉查询参数后的路径。
    static func probeTone(source: BookSource, book: Book?, chapterURL: String?, tone: String) async -> ToneProbeResult? {
        let script = scriptText(source)
        guard script.contains("playinfo"), script.contains("fanqieSignHeaders") else { return nil }
        // 真人录播书有文字版时，音色走 TTS 通道（音色差异一定存在），不再用录播音频比较。
        if (Int(tone) ?? 0) > 0, let book, FanqieTTS.isSupported(source: source),
           await FanqieTTS.relatedBookID(source: source, book: book) != nil {
            return .playable
        }
        guard let chapterURL, let item = itemID(from: chapterURL), !tone.isEmpty else { return nil }
        let js = """
        (function(){
          function play(t){
            try{
              var u = "https://reading.snssdk.com/reading/reader/audio/playinfo/?tone_id=" + String(t)
                    + "&item_ids=" + String(__item) + "&pv_player=-1&aid=3040&device_platform=android";
              var h = fanqieSignHeaders(u, null);
              var hm = new Packages.java.util.HashMap();
              for (var k in h) { hm.put(String(k), String(h[k])); }
              var body = String(java.get(u, hm).body());
              var d = {};
              try { d = JSON.parse(body); } catch(e) { return ""; }
              if (d.data && d.data[0] && d.data[0].main_url) { return String(d.data[0].main_url); }
              return "";
            }catch(e){ return ""; }
          }
          return JSON.stringify({tone: play(__tone), def: play(0)});
        })()
        """
        let out = await Task.detached { () -> String? in
            JSEngine.shared.evalString(js, vars: ["__tone": tone, "__item": item],
                                       jsLib: source.jsLib,
                                       context: RuleContext(source: source, book: book))
        }.value
        guard let out, let data = out.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let toneURL = (object["tone"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let defaultURL = (object["def"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        func mediaPath(_ raw: String) -> String {
            guard let url = URL(string: raw) else { return raw }
            return url.path
        }
        let sameMedia = !toneURL.isEmpty && mediaPath(toneURL) == mediaPath(defaultURL)
        DebugLog.readerAdd("◇音色探测 tone=\(tone) item=\(item) → \(toneURL.isEmpty ? "无音频" : (sameMedia ? "与默认音色相同" : URL(string: toneURL)?.host ?? "有独立音频"))")
        if toneURL.isEmpty { return .unavailable }
        if sameMedia { return .sameAsDefault }
        return .playable
    }

    private static func itemID(from url: String) -> String? {
        guard let range = url.range(of: "item_id=([0-9]+)", options: .regularExpression) else { return nil }
        let digits = String(url[range]).replacingOccurrences(of: "[^0-9]", with: "",
                                                             options: .regularExpression)
        return digits.isEmpty ? nil : digits
    }

    /// 从书籍地址里抠 book_id（番茄的 bookUrl 只是 id 载体）。
    private static func bookID(from url: String) -> String? {
        if let range = url.range(of: "(?:book_id|bookId)=([0-9]+)", options: .regularExpression) {
            let digits = String(url[range]).replacingOccurrences(of: "[^0-9]", with: "",
                                                                 options: .regularExpression)
            return digits.isEmpty ? nil : digits
        }
        let digits = url.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
        return digits.isEmpty ? nil : digits
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
        let url = source.bookSourceUrl
        var candidates: [String] = [SourceVariable.get(url)]
        if let value = SourceVariableStore.shared.get("v_\(url)_v2sv") { candidates.append(value) }
        if let value = SourceVariableStore.shared.get("v2sel") { candidates.append(value) }
        var best: [String: Any] = [:]
        var bestTS = -Double.greatestFiniteMagnitude
        for raw in candidates {
            guard let data = raw.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) else { continue }
            let dict: [String: Any]
            if let single = object as? [String: Any] {
                dict = single
            } else if let list = object as? [[String: Any]], let first = list.first {
                dict = first
            } else {
                continue
            }
            let ts = (dict["_ts"] as? NSNumber)?.doubleValue ?? 0
            if ts >= bestTS { bestTS = ts; best = dict }
        }
        return best
    }

    /// 当前生效的音色配置（和规则一样按 _ts 取最新那份）。
    static func currentSelection(source: BookSource) -> (tone: String, abook: String) {
        let config = configDictionary(source: source)
        return (string(config["tone"]), string(config["abook"]))
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
        // 书源规则（番茄 v2）会在三份存储里挑 _ts 最大的那份：
        // source.getVariable() / source.get('v2sv') / cache.getFromMemory('v2sel')。
        // 面板按钮三份都写并带时间戳；只写第一份会被旧变量盖住，表现就是「切了没变」。
        dict["_ts"] = Int(Date().timeIntervalSince1970 * 1000)
        let useArray = isArray || (raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && prefersArray)
        let output: Any = useArray ? [dict] : dict
        guard JSONSerialization.isValidJSONObject(output),
              let data = try? JSONSerialization.data(withJSONObject: output),
              let text = String(data: data, encoding: .utf8) else { return }
        SourceVariable.set(text, for: source.bookSourceUrl)
        SourceVariableStore.shared.set("v_\(source.bookSourceUrl)_v2sv", text)
        SourceVariableStore.shared.set("v2sel", text)
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


/// toneinfo 返回体。只取需要的字段；ID 用柔性类型解码，19 位数字不会被浮点化。
private struct ToneInfoPayload: Decodable {
    struct Payload: Decodable {
        var tts_tones: [TTS]?
        var audio_tones: [Audio]?
    }
    struct TTS: Decodable {
        var id: ToneID?
        var title: String?
        var name: String?
    }
    struct Audio: Decodable {
        var abook_id: ToneID?
        var title: String?
        var name: String?
    }
    var data: Payload?
}

private struct ToneID: Decodable {
    var value: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Int64.self) {
            value = String(number)
        } else if let text = try? container.decode(String.self) {
            value = text
        } else {
            throw DecodingError.typeMismatch(ToneID.self,
                .init(codingPath: container.codingPath, debugDescription: "音色 id 不是数字或字符串"))
        }
    }
}
