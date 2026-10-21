import Foundation
import SwiftSoup

/// Legado-compatible rule analyzer: default JSoup syntax, @css:, @json:/$., @js:/<js>, ##regex, ||, &&, {{}}.
final class AnalyzeRule {
    let content: Any
    let baseUrl: String
    let jsLib: String?
    let context: RuleContext
    /// 原始响应文本。Legado 中顶层 JS 的 result 是原始字符串（如 data: URL 解出的十六进制），
    /// 不能是 SwiftSoup 重新序列化后的 <html> 文档。
    let rawContent: String?
    /// 规则中间阶段：字符串结果被解析成的文档节点 → 原字符串。
    private var stageRaw: (node: AnyObject, raw: String)?

    private func parseStage(_ str: String) -> Any {
        let parsed = AnalyzeRule.parse(str, baseUrl: baseUrl)
        if parsed is Element { stageRaw = (parsed as AnyObject, str) }
        return parsed
    }

    init(content: Any, baseUrl: String, jsLib: String? = nil, context: RuleContext = RuleContext()) {
        self.baseUrl = baseUrl
        self.jsLib = jsLib
        self.context = context
        if let s = content as? String {
            self.rawContent = s
            self.content = AnalyzeRule.parse(s, baseUrl: baseUrl)
        } else {
            self.rawContent = nil
            self.content = content
        }
    }

    /// 传给 JS 的 result：顶层文档用原始文本，其余节点按原逻辑转换
    private func jsInput(_ input: Any) -> Any {
        if let raw = rawContent, (input as AnyObject) === (content as AnyObject) { return raw }
        // 上一段 JS 返回的字符串被解析成 HTML 文档后，{{result}} / 后续 JS 仍应拿到原字符串
        // （原版混合规则 `$.id <js>base64</js> data:;base64,{{result}}` 依赖这一点）。
        if let stage = stageRaw, (input as AnyObject) === stage.node { return stage.raw }
        // 元素规则的结果在原版是 Rhino 的 Elements 集合：脚本里普遍写
        // `result.select('a').toArray()` / `result[0].outerHtml()` / `result.size()`。
        // 这里把元素数组原样交给 JS（每个元素是带 select/attr/text 的节点对象），
        // 集合方法由 prelude 给 Array.prototype 补上。
        if let list = input as? [Any], !list.isEmpty {
            let elements = list.compactMap { $0 as? Element }
            if elements.count == list.count {
                let items = elements.map { JSNodeBridge($0) as Any }
                // 同时给出拼好的 HTML 文本：脚本常写 result.match(...) / result.split(...)。
                let text = elements.map { (try? $0.outerHtml()) ?? "" }.joined(separator: "\n")
                return JSNodeListWithText(items: items, text: text)
            }
        }
        return AnalyzeRule.jsValue(input)
    }

    static func parse(_ s: String, baseUrl: String) -> Any {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("{") || t.hasPrefix("["), let d = t.data(using: .utf8),
           let o = try? JSONSerialization.jsonObject(with: d, options: [.fragmentsAllowed]) {
            return o
        }
        if let doc = try? SwiftSoup.parse(s, baseUrl) { return doc }
        return s
    }

    // MARK: - JS splitting

    private func splitJS(_ rule: String) -> [(Bool, String)] {
        // Match Kotlin AppPattern.JS_PATTERN; RuleScanner is not a JS lexer.
        guard let regex = RegexLog.compile("<js>([\\s\\S]*?)</js>|@js:([\\s\\S]*)",
                                          options: [.caseInsensitive]) else { return [(false, rule)] }
        let source = rule as NSString
        var parts: [(Bool, String)] = []
        var cursor = 0
        for match in regex.matches(in: rule, range: NSRange(location: 0, length: source.length)) {
            if match.range.location > cursor {
                let before = source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !before.isEmpty { parts.append((false, before)) }
            }
            let block = match.range(at: 1)
            let script = block.location != NSNotFound ? block : match.range(at: 2)
            var body = source.substring(with: script)
            // 规则尾部还有 `##正则##替换`（如 `a@text@js:xxx##(^|…)##$1<br>`）：
            // 原版把正则拆成独立的替换步骤，留在 JS 脚本里会直接语法错误
            // （JavaScriptCore 报 “Invalid character: '#'”）。
            if let marker = RuleScanner.firstTopLevel(body, ["##"]) {
                let tail = String(body[marker.lowerBound...])
                body = String(body[..<marker.lowerBound])
                parts.append((true, body))
                if !tail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    parts.append((false, tail))
                }
            } else {
                parts.append((true, body))
            }
            cursor = NSMaxRange(match.range)
        }
        if cursor < source.length {
            let tail = source.substring(from: cursor).trimmingCharacters(in: .whitespacesAndNewlines)
            if !tail.isEmpty { parts.append((false, tail)) }
        }
        return parts
    }

    private func resolvedHost() -> String {
        if let lib = jsLib, !lib.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           let host = JSEngine.shared.evalString("typeof host === 'undefined' ? '' : String(host)", jsLib: lib, context: context), !host.isEmpty {
            return host
        }
        return context.get("host")
    }

    private func runJS(_ js: String, _ input: Any, node: Any? = nil) -> Any {
        let expanded = expandEmbeddedTemplates(js, input: input)
        // ruleInput = java.getString/getElement 等的作用对象：混合规则里它是本条规则的内容节点
        // （原版 bindings["java"] = this），不是前面各段累计的 result。
        return JSEngine.shared.eval(expanded, result: jsInput(input), baseUrl: baseUrl, jsLib: jsLib, rule: self, ruleInput: node ?? input, context: context) ?? ""
    }

    /// 与 runJS 相同，但脚本抛错时返回 nil（错误信息在 JSEngine.lastError）。
    private func runJSOptional(_ js: String, _ input: Any, node: Any? = nil) -> Any? {
        let expanded = expandEmbeddedTemplates(js, input: input)
        return JSEngine.shared.eval(expanded, result: jsInput(input), baseUrl: baseUrl, jsLib: jsLib, rule: self, ruleInput: node ?? input, context: context)
    }

    /// Legado 会在执行 @js:/<js> 前先展开其中的 {{规则}}。
    /// 例如 `{{$.bid}}` 必须从当前 JSON 节点取值，而不能直接交给 JSCore 解析。
    private func expandEmbeddedTemplates(_ script: String, input: Any) -> String {
        RuleScanner.replaceGroups(script, marker: "{{") { inner in
            let expression = inner.trimmingCharacters(in: .whitespacesAndNewlines)
            if expression == "baseUrl" { return self.baseUrl }
            if expression == "host" { return self.resolvedHost() }
            if expression.lowercased().hasPrefix("@get:") {
                let key = String(expression.dropFirst(5))
                if key.hasPrefix("{"),
                   let group = RuleScanner.balancedRange(key, at: key.startIndex),
                   group.upperBound == key.endIndex {
                    return self.context.get(String(key.dropFirst().dropLast()))
                }
                return self.context.get(key)
            }
            if expression.hasPrefix("@") || expression.hasPrefix("$.") || expression.hasPrefix("$[") || expression.hasPrefix("//") {
                return self.stringValue(input, expression)
            }
            // Evaluate once directly; runJS would expand the same template again.
            return AnalyzeRule.asString(JSEngine.shared.eval(
                expression, result: AnalyzeRule.jsValue(input), baseUrl: self.baseUrl,
                jsLib: self.jsLib, rule: self, ruleInput: input, context: self.context
            ) ?? "")
        }
    }

    static func jsValue(_ v: Any) -> Any {
        if let e = v as? Element { return (try? e.outerHtml()) ?? "" }
        if let a = v as? [Any] { return a.map { jsValue($0) } }
        return v
    }

    // MARK: - Public API

    private var validatingCoverTemplate = false

    /// An absent ID in a literal image URL is not a new cover. Keep this policy
    /// scoped to covers: other fields and scripts may intentionally use blanks.
    func getCoverString(_ rule: String?, from obj: Any? = nil) -> String {
        let previous = validatingCoverTemplate
        validatingCoverTemplate = true
        defer { validatingCoverTemplate = previous }
        let result = getString(rule, from: obj)
        return Self.missingCoverValue(result) ? "" : result
    }

    private static func missingCoverValue(_ value: String) -> Bool {
        ["", "null", "undefined"].contains(value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    func getString(_ rule: String?, from obj: Any? = nil) -> String {
        guard var rule = rule, !rule.isEmpty else { return "" }
        rule = resolvePut(rule, from: obj)
        // 只含 @put 的规则（如漫画详情 name 规则只存 comic_id）不产出文本；
        // 不能把当前正文当成匹配结果返回。
        guard !rule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
        if let g = obj as? [String], AnalyzeRule.hasGroupRef(rule) {
            rule = AnalyzeRule.fillGroups(rule, g)
            if !rule.contains("<js>") && rule.range(of: "@js:", options: .caseInsensitive) == nil {
                return rule.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        var cur: Any = obj ?? content
        // 本条规则作用的内容节点：混合规则的 JS 段里 java.getString(...) 仍查这个节点，
        // 只有 result 才是前面各段累计的值（原版 bindings["java"] = 本 AnalyzeRule）。
        let node: Any = obj ?? content
        var seenJS = false
        var textBeforeJS: String? = nil
        for (isJs, s) in splitJS(rule) {
            if isJs {
                seenJS = true
                let value = runJSOptional(s, cur, node: node)
                if value == nil, JSEngine.lastError != nil {
                    // 脚本报错：文本部分通常就是真实地址（脚本只做一层包装，如 data: 协议），
                    // 退回文本部分，别把整条规则判成空。
                    if let t = textBeforeJS, !t.isEmpty { return t }
                    return ""
                }
                cur = value ?? ""
            } else {
                if let rg = regexOnlySegment(s), let str = cur as? String {
                    // 纯正则段：直接改累计结果，不能把它再解析成 HTML（否则会拿到空文档 outerHtml）
                    cur = AnalyzeRule.applyRegexReplacement(str, rg.regex, rg.repl, rg.firstOnly)
                } else {
                    if let str = cur as? String, cur as AnyObject !== content as AnyObject { cur = parseStage(str) }
                    cur = stringValue(cur, s)
                }
                if !seenJS, textBeforeJS == nil { textBeforeJS = AnalyzeRule.asString(cur) }
            }
        }
        return AnalyzeRule.asString(cur).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 对应原版 AnalyzeRule.getStringList（`kind` 等字段使用）：
    /// JSON 多值结果保持「字符串数组」，在后续 @js 阶段以 JS 数组传入
    /// （如 `$..theme_id @js: Array.from(result)[0]…` 依赖数组语义），
    /// 最终按数组项 / 行展开为字符串列表。
    func getStringList(_ rule: String?, from obj: Any? = nil) -> [String] {
        guard var rule = rule, !rule.isEmpty else { return [] }
        rule = resolvePut(rule, from: obj)
        guard !rule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        var cur: Any = obj ?? content
        let node: Any = obj ?? content
        let parts = splitJS(rule)
        for (index, part) in parts.enumerated() {
            let (isJs, s) = part
            if isJs {
                cur = runJS(s, cur, node: node)
                continue
            }
            if let rg = regexOnlySegment(s), let str = cur as? String {
                // 纯正则段（如 `##·##,`）：替换累计结果，不重新解析
                cur = AnalyzeRule.applyRegexReplacement(str, rg.regex, rg.repl, rg.firstOnly)
                continue
            }
            if let str = cur as? String, cur as AnyObject !== content as AnyObject {
                cur = parseStage(str)
            }
            let nextIsJS = index + 1 < parts.count && parts[index + 1].0
            if nextIsJS, let list = jsonStringValues(cur, s) {
                cur = list
            } else {
                cur = stringValue(cur, s)
            }
        }
        if let list = cur as? [Any] {
            return list.map { AnalyzeRule.asString($0).trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        return AnalyzeRule.asString(cur)
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// 纯 JSON 规则在当前节点上的求值结果列表；不是 JSON 规则时返回 nil（退回字符串语义）。
    private func jsonStringValues(_ obj: Any, _ rule: String) -> [Any]? {
        let trimmed = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        // 混合规则里带 {{模板}} 的文本段不是 JSON 路径：原版把这一段的字符串结果
        // 累计进 result 再交给后续 JS（result.replace(...)），
        // 不能因为「内容是 JSON」就把它当 JSON 查询返回数组（会打死 JS 段）。
        guard !trimmed.isEmpty, !trimmed.hasPrefix("@@"), !trimmed.contains("{{"),
              isJsonRule(trimmed, obj) else { return nil }
        return JsonPath.query(jsonRoot(obj), stripPrefix(trimmed))
    }
    /// 不能用 getString(_:from:)：那会先把正文当 HTML 解析、再用默认 prettyPrint 序列化，
    /// 段与段之间的换行会被并成空格（整章变一段）。这里对字符串求值，不做 HTML 解析。
    /// 只有完全不像替换规则的写法（既没有 ## 也没有 JS）才退回旧路径。
    func getReplacementString(_ rule: String?, from text: String) -> String {
        guard let rule, !rule.isEmpty else { return text }
        let trimmed = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        let isJS = lower.hasPrefix("@js:") || lower.hasPrefix("<js>")
        guard trimmed.hasPrefix("##") || isJS else { return getString(rule, from: text) }
        var cur: Any = text
        for (isJs, s) in splitJS(rule) {
            if isJs { cur = runJS(s, cur) } else { cur = stringValue(cur, s) }
        }
        return AnalyzeRule.asString(cur).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func getElements(_ rule: String?, from obj: Any? = nil) -> [Any] {
        guard let rawRule = rule, !rawRule.isEmpty else { return [] }
        let rule = resolvePut(rawRule, from: obj)
        var cur: Any = obj ?? content
        let node: Any = obj ?? content
        for (isJs, s) in splitJS(rule) {
            if isJs { cur = runJS(s, cur, node: node) }
            else {
                if let str = cur as? String { cur = parseStage(str) }
                if s.hasPrefix("##") {
                    // 规则尾部的正则替换步骤（配合 JS 段使用）
                    cur = AnalyzeRule.applyTrailingRegex(cur, s)
                } else {
                    cur = elementsValue(cur, s)
                }
            }
        }
        if let a = cur as? [Any] { return a }
        if let s = cur as? String {
            let p = AnalyzeRule.parse(s, baseUrl: baseUrl)
            if let a = p as? [Any] { return a }
            return [p]
        }
        return [cur]
    }

    private func resolvePut(_ raw: String, from obj: Any?) -> String {
        RuleScanner.replaceGroups(raw, marker: "@put:{", caseInsensitive: true) { body in
            let pairs = RuleScanner.split(body, by: [","])
            guard pairs.valid else { return "@put:{" + body + "}" }
            var rules: [(String, String)] = []
            for pair in pairs.parts {
                guard let colon = RuleScanner.firstTopLevel(pair, [":"]) else {
                    return "@put:{" + body + "}"
                }
                let rawKey = String(pair[..<colon.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                let rawValue = String(pair[colon.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                let key = RuleScanner.unquote(rawKey) ?? rawKey
                let valueRule = RuleScanner.unquote(rawValue) ?? rawValue
                guard !key.isEmpty else { return "@put:{" + body + "}" }
                rules.append((key, valueRule))
            }
            var values: [String: String] = [:]
            for (key, valueRule) in rules {
                values[key] = self.stringValue(obj ?? self.content, valueRule)
            }
            self.context.putAll(values)
            return ""
        }
    }

    // MARK: - String rules

    private func topLevelRegexMarker(in s: String) -> Range<String.Index>? {
        RuleScanner.firstTopLevel(s, ["##"])
    }

    /// 混合规则里「只有 ##正则」的段（如番茄 kind 规则结尾的 `##·##,`）。
    /// 原版语义：规则部分为空 + 有替换正则 → 不再求值，直接对前面累计的 result 做替换
    /// （`if (rule.isNotBlank() || sourceRule.replaceRegex.isEmpty())` 的短路）。
    private func regexOnlySegment(_ s: String)
        -> (regex: String, repl: String, firstOnly: Bool)? {
        guard let r = topLevelRegexMarker(in: s) else { return nil }
        let base = String(s[..<r.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard base.isEmpty else { return nil }
        let tail = String(s[r.upperBound...])
        var segs = tail.components(separatedBy: "##")
        guard let re = segs.first, !re.isEmpty else { return nil }
        segs.removeFirst()
        let repl = segs.first ?? ""
        return (re, repl, tail.hasSuffix("###"))
    }

    /// 规则尾部的 `##正则##替换`：原版是独立的替换步骤（可跟在 JS 段后面）。
    static func applyTrailingRegex(_ value: Any, _ raw: String) -> Any {
        guard let marker = RuleScanner.firstTopLevel(raw, ["##"]) else { return value }
        let tail = String(raw[marker.upperBound...])
        var segs = tail.components(separatedBy: "##")
        let regex = segs.removeFirst()
        let repl = segs.first ?? ""
        let firstOnly = tail.hasSuffix("###")
        let text = AnalyzeRule.asString(value)
        guard let nre = RegexLog.compile(regex) else { return text }
        let ns = text as NSString
        if firstOnly {
            if let m = nre.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) {
                return nre.replacementString(for: m, in: text, offset: 0, template: repl)
            }
            return ""
        }
        return nre.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: ns.length), withTemplate: repl)
    }

    /// ##正则##替换：与 stringValue 尾部同一套语义（支持 ### 只替换第一处）。
    private static func applyRegexReplacement(_ s: String, _ re: String,
                                              _ repl: String, _ firstOnly: Bool) -> String {
        guard let nre = RegexLog.compile(re) else { return s }
        let ns = s as NSString
        if firstOnly {
            if let m = nre.firstMatch(in: s, range: NSRange(location: 0, length: ns.length)) {
                return nre.replacementString(for: m, in: s, offset: 0, template: repl)
            }
            return ""
        }
        return nre.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: ns.length),
                                            withTemplate: repl)
    }

    private func stringValue(_ obj: Any, _ rawRule: String) -> String {
        // 模板内部的 ##（如 {{$.docId##.*_}}）由 template() 单独处理；
        // 整条 URL/正文规则仍要保留原始模板分支，避免把 URL 当成 CSS 规则。
        var rule = rawRule
        var regex: String? = nil, repl = "", firstOnly = false
        if let r = topLevelRegexMarker(in: rule) {
            let tail = String(rule[r.upperBound...])
            rule = String(rule[..<r.lowerBound])
            var segs = tail.components(separatedBy: "##")
            regex = segs.removeFirst()
            if !segs.isEmpty { repl = segs.removeFirst() }
            if tail.hasSuffix("###") { firstOnly = true }
        }
        var out: String
        let combination = RuleScanner.split(rule, by: ["&&", "||", "%%"])
        if rule.contains("{{") {
            out = template(obj, rule)
            // Kotlin 在同一趟里替换 @get:{…} 与 {{…}}，两种写法可以出现在同一条规则中
            // （漫画源 chapterUrl 末尾的 &comic_id=@get:{comic_id} 就是与 {{}} 混用）。
            if out.range(of: "@get:{", options: .caseInsensitive) != nil {
                out = RuleScanner.replaceGroups(out, marker: "@get:{", caseInsensitive: true) {
                    self.context.get($0)
                }
            }
        } else if rule.range(of: "@get:{", options: .caseInsensitive) != nil {
            // Kotlin treats @get substitutions as literal output, not a new selector.
            out = RuleScanner.replaceGroups(rule, marker: "@get:{", caseInsensitive: true) {
                self.context.get($0)
            }
        } else if !combination.valid {
            out = ""
        } else if combination.parts.count > 1 {
            let forceDefault = rule.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("@@")
            let parts = combination.parts.map { part -> String in
                let trimmed = part.trimmingCharacters(in: .whitespacesAndNewlines)
                return forceDefault && !trimmed.hasPrefix("@@") ? "@@" + trimmed : trimmed
            }
            switch combination.separator {
            case "||":
                out = ""
                for part in parts {
                    let value = stringValue(obj, part)
                    if !value.isEmpty { out = value; break }
                }
            case "%%":
                let lists: [[Any]] = parts.map { part in
                    self.stringValue(obj, part).split(separator: "\n").map { String($0) as Any }
                }
                out = AnalyzeRule.interleave(lists).map { AnalyzeRule.asString($0) }.joined(separator: "\n")
            default:
                out = parts.map { self.stringValue(obj, $0) }
                    .filter { !$0.isEmpty }.joined(separator: "\n")
            }
        } else if rule.contains("{$.") {
            out = replaceBraces(rule, pattern: "\\{(\\$\\.[^}]+)\\}") { self.singleString(obj, $0) }
        } else {
            if rule.isEmpty {
                if let e = obj as? Element { out = (try? e.outerHtml()) ?? "" } else { out = AnalyzeRule.asString(obj) }
            } else { out = singleString(obj, rule) }
        }
        if let re = regex, !re.isEmpty, let nre = RegexLog.compile(re) {
            let ns = out as NSString
            if firstOnly {
                if let m = nre.firstMatch(in: out, range: NSRange(location: 0, length: ns.length)) {
                    out = nre.replacementString(for: m, in: out, offset: 0, template: repl)
                } else { out = "" }
            } else {
                out = nre.stringByReplacingMatches(in: out, range: NSRange(location: 0, length: ns.length), withTemplate: repl)
            }
        }
        return out
    }

    private func template(_ obj: Any, _ rule: String) -> String {
        // Mask balanced expressions before locating the URL's query/options:
        // a '?' inside JavaScript/JSONPath is not a query delimiter. No rule
        // gets evaluated twice (java.put and other JS can have side effects).
        var required: [Bool] = []
        if validatingCoverTemplate {
            let marker = "__cover_" + UUID().uuidString + "_"
            var index = 0
            let skeleton = RuleScanner.replaceGroups(rule, marker: "{{") { _ in
                defer { index += 1 }
                return marker + String(index) + "__"
            }
            let query = skeleton.firstIndex(where: { $0 == "?" || $0 == "#" }) ?? skeleton.endIndex
            // A comma in the image path is legal; only ', { ... }' starts
            // Legado request options. Do not re-evaluate/execute that JSON here.
            let options = skeleton.range(of: ",\\s*\\{", options: .regularExpression)?.lowerBound ?? skeleton.endIndex
            let boundary = min(query, options)
            let address = String(skeleton[..<boundary])
            required = (0..<index).map { address.contains(marker + String($0) + "__") }
        }
        func evaluate(_ inner: String) -> String {
            let t = inner.trimmingCharacters(in: .whitespacesAndNewlines)
            if t == "baseUrl" { return self.baseUrl }
            if t == "host" { return self.resolvedHost() }
            if t.lowercased().hasPrefix("@get:") {
                let key = String(t.dropFirst(5))
                if key.hasPrefix("{"),
                   let group = RuleScanner.balancedRange(key, at: key.startIndex),
                   group.upperBound == key.endIndex {
                    return self.context.get(String(key.dropFirst().dropLast()))
                }
                return self.context.get(key)
            }
            if t.hasPrefix("@") || t.hasPrefix("$.") || t.hasPrefix("$[") || t.hasPrefix("//") {
                return self.stringValue(obj, t)
            }
            return AnalyzeRule.asString(self.runJS(t, obj))
        }
        var index = 0, missingAddress = false
        let result = RuleScanner.replaceGroups(rule, marker: "{{") { inner in
            let value = evaluate(inner)
            if required.indices.contains(index), required[index], Self.missingCoverValue(value) {
                missingAddress = true
            }
            index += 1
            return value
        }
        // A later JS stage can still supply an explicit fallback for this blank.
        return missingAddress ? "" : result
    }

    private func replaceBraces(_ s: String, pattern: String, _ f: (String) -> String) -> String {
        guard let re = RegexLog.compile(pattern) else { return s }
        var result = s
        let ns = s as NSString
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)).reversed() {
            let v = f(ns.substring(with: m.range(at: 1)))
            result = (result as NSString).replacingCharacters(in: m.range, with: v)
        }
        return result
    }

    private func singleString(_ obj: Any, _ r: String) -> String {
        var rule = r.trimmingCharacters(in: .whitespacesAndNewlines)
        let forceDefault = rule.hasPrefix("@@")
        if forceDefault { rule = String(rule.dropFirst(2)) }
        if rule.isEmpty { return "" }
        if !forceDefault, isJsonRule(rule, obj) {
            return JsonPath.query(jsonRoot(obj), stripPrefix(rule)).map { AnalyzeRule.asString($0) }.joined(separator: "\n")
        }
        if !forceDefault, XPathRule.isXPath(rule) { return XPathRule.string(obj, rule) }
        let isCss = rule.lowercased().hasPrefix("@css:")
        let body = isCss ? String(rule.dropFirst(5)) : rule
        let segments = RuleScanner.split(body, by: ["@"])
        guard segments.valid else { return "" }
        guard segments.parts.count > 1 else {
            // A bare default rule extracts an attribute; @css selects text.
            if let el = AnalyzeRule.element(obj) {
                if isCss { return elementsText((try? el.select(body).array()) ?? [], "text") }
                return elementsText([el], body)
            }
            return forceDefault ? "" : AnalyzeRule.asString(obj)
        }
        let sel = segments.parts.dropLast().joined(separator: "@")
        let attr = segments.parts.last ?? ""
        let els: [Element]
        if sel.isEmpty { els = AnalyzeRule.element(obj).map { [$0] } ?? [] }
        else if isCss { els = (try? AnalyzeRule.element(obj)?.select(sel).array()) ?? [] }
        else { els = defaultElements(obj, sel) }
        return elementsText(els, attr)
    }

    private func elementsText(_ els: [Element], _ attr: String) -> String {
        var seen = Set<String>()
        return els.compactMap { e -> String? in
            switch attr {
            case "text": return try? e.text()
            case "ownText": return e.ownText()
            case "textNodes": return e.textNodes().map { $0.text() }.joined(separator: "\n")
            case "html":
                _ = try? e.select("script,style").remove()
                return try? e.outerHtml()
            case "all": return try? e.outerHtml()
            default:
                guard let value = try? e.attr(attr),
                      !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      seen.insert(value).inserted else { return nil }
                return value
            }
        }.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    // MARK: - Element rules

    private func elementsValue(_ obj: Any, _ r: String) -> [Any] {
        var rule = r.trimmingCharacters(in: .whitespacesAndNewlines)
        let forceDefault = rule.hasPrefix("@@")
        if forceDefault { rule = String(rule.dropFirst(2)) }
        // AllInOne is a regex, not a list of selector combinations.
        if !forceDefault, rule.hasPrefix(":") {
            return AnalyzeRule.allInOne(obj, String(rule.dropFirst()))
        }
        let combination = RuleScanner.split(rule, by: ["&&", "||", "%%"])
        guard combination.valid else { return [] }
        if combination.parts.count > 1 {
            let parts = combination.parts.map { forceDefault ? "@@" + $0 : $0 }
            switch combination.separator {
            case "||":
                for part in parts {
                    let values = elementsValue(obj, part)
                    if !values.isEmpty { return values }
                }
                return []
            case "%%":
                return AnalyzeRule.interleave(parts.map { self.elementsValue(obj, $0) })
            default:
                return parts.flatMap { self.elementsValue(obj, $0) }
            }
        }
        var main = rule, reverse = false
        if main.hasPrefix("-") { reverse = true; main.removeFirst() }
        if main.hasPrefix("+") { main.removeFirst() }
        var res: [Any]
        if !forceDefault, main.hasPrefix(":") {
            res = AnalyzeRule.allInOne(obj, String(main.dropFirst()))
        } else if !forceDefault, isJsonRule(main, obj) {
            res = JsonPath.query(jsonRoot(obj), stripPrefix(main)).flatMap { ($0 as? [Any]) ?? [$0] }
        } else if !forceDefault, XPathRule.isXPath(main) {
            res = XPathRule.elements(obj, main)
        } else if main.lowercased().hasPrefix("@css:") {
            res = (try? AnalyzeRule.element(obj)?.select(String(main.dropFirst(5))).array()) ?? []
        } else {
            res = defaultElements(obj, main)
        }
        return reverse ? Array(res.reversed()) : res
    }

    /// `class.a b` 表示同时带 a、b 两个类名的元素（po18 目录规则 `class.lb fk@tag.li!-1`）。
    /// jsoup 的 getElementsByClass 只认单个类名，这里按空白拆分后取交集。
    static func classElements(_ el: Element, _ names: String) -> [Element] {
        let tokens = names.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard let first = tokens.first, !first.isEmpty else { return [] }
        var result = (try? el.getElementsByClass(first).array()) ?? []
        for token in tokens.dropFirst() where !result.isEmpty {
            let allowed = Set(((try? el.getElementsByClass(token).array()) ?? []).map { ObjectIdentifier($0) })
            result = result.filter { allowed.contains(ObjectIdentifier($0)) }
        }
        return result
    }

    private func defaultElements(_ obj: Any, _ rule: String) -> [Element] {
        let segments = RuleScanner.split(rule, by: ["@"])
        guard segments.valid, let root = AnalyzeRule.element(obj) else { return [] }
        var cur: [Element] = [root]
        for seg in segments.parts where !seg.isEmpty {
            cur = cur.flatMap { applySegment($0, seg) }
        }
        return cur
    }

    private func applySegment(_ el: Element, _ seg: String) -> [Element] {
        if let (base, spec) = AnalyzeRule.splitBracket(seg) {
            let l = (base.isEmpty || base == "children") ? el.children().array() : applySegment(el, base)
            return AnalyzeRule.pickIndexes(l, spec)
        }
        if seg.hasPrefix("."), seg.dropFirst().range(of: "^!?[-0-9:]+$", options: .regularExpression) != nil {
            return AnalyzeRule.pickIndexes(el.children().array(), String(seg.dropFirst()))
        }
        // 教程兼容：tag.dd!0:1:2 与 tag.dd.!0:1:2 都表示排除索引。
        var normalized = seg
        if let bang = normalized.firstIndex(of: "!") {
            let base = String(normalized[..<bang])
            if !base.hasSuffix(".") {
                normalized = base + "." + String(normalized[bang...])
            }
        }
        var parts = normalized.components(separatedBy: ".")
        let type = parts.removeFirst()
        var list: [Element]
        switch type {
        case "class": list = AnalyzeRule.classElements(el, parts.first ?? "")
        case "tag": list = (try? el.getElementsByTag(parts.first ?? "").array()) ?? []
        case "id":
            if let found = ((try? el.getElementById(parts.first ?? "")) ?? nil) { list = [found] } else { list = [] }
        case "text": list = (try? el.getElementsContainingOwnText(parts.first ?? "").array()) ?? []
        case "children": list = el.children().array()
        default:
            // Legado 默认语法：非 class/tag/id/text/children 的段按 CSS 选择器处理，
            // 允许尾部带索引，如 .search@li!0、li.2、div.-1、li!0:1
            var css = seg
            var idxSpec: String? = nil
            if let bang = seg.lastIndex(of: "!") {
                css = String(seg[..<bang])
                idxSpec = String(seg[bang...])
            } else if let m = seg.range(of: "\\.(-?\\d+(:-?\\d+)*)$", options: .regularExpression) {
                css = String(seg[..<m.lowerBound])
                idxSpec = String(seg[seg.index(after: m.lowerBound)...])
            }
            if css.hasSuffix(".") { css.removeLast() }
            if css.isEmpty { return [] }
            let found = (try? el.select(css).array()) ?? []
            guard let spec = idxSpec, !spec.isEmpty else { return found }
            // 旧语法 !0:1:2 / 0:1 表示多个独立索引
            return AnalyzeRule.pickIndexes(found, spec.replacingOccurrences(of: ":", with: ","))
        }
        if type != "children" && !parts.isEmpty { parts.removeFirst() }
        guard let idxStr = parts.first, !idxStr.isEmpty else { return list }
        if idxStr.hasPrefix("!") {
            let ex = Set(idxStr.dropFirst().split(separator: ":").compactMap { Int($0) }.map { $0 < 0 ? list.count + $0 : $0 })
            return list.enumerated().filter { !ex.contains($0.offset) }.map { $0.element }
        }
        let idxs = idxStr.split(separator: ":").compactMap { Int($0) }
        return idxs.compactMap { i in
            let j = i < 0 ? list.count + i : i
            return (j >= 0 && j < list.count) ? list[j] : nil
        }
    }

    // MARK: - Helpers

    /// 规则分析（对照原版 AnalyzeRule 的 splitSourceRule / modeQualified 思路）：
    /// 先看**规则写法**（@json:/@xpath:/@css:/$ 前缀），再看**当前节点类型**，
    /// 最后才落到 Jsoup 默认语法。这样 JSON 元素上的裸字段名（`bid`、`ChapterName`）
    /// 不会被当成 CSS 选择器（数字字段会因此变成空串）。
    private func isJsonRule(_ rule: String, _ obj: Any) -> Bool {
        let l = rule.lowercased()
        if l.hasPrefix("@json:") || rule.hasPrefix("$.") || rule.hasPrefix("$[") { return true }
        if l.hasPrefix("@css:") || l.hasPrefix("@xpath:") { return false }
        if obj is [String: Any] || obj is [Any] { return true }
        // 当前节点是 JSON 文本（JS 规则直接返回 JSON 串、后面没有 $[*] 时）：
        // 裸字段名按 JSON 字段取，不当 CSS 选择器。
        if let text = obj as? String {
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard t.hasPrefix("{") || t.hasPrefix("[") else { return false }
            let r = rule.trimmingCharacters(in: .whitespacesAndNewlines)
            if r.isEmpty || r.hasPrefix("@") || r.hasPrefix("/") { return false }
            return r.range(of: "^[A-Za-z_$][A-Za-z0-9_$]*$", options: .regularExpression) != nil
        }
        return false
    }

    private func stripPrefix(_ r: String) -> String {
        r.lowercased().hasPrefix("@json:") ? String(r.dropFirst(6)) : r
    }

    private func jsonRoot(_ obj: Any) -> Any {
        if let s = obj as? String { return AnalyzeRule.parse(s, baseUrl: baseUrl) }
        if let e = obj as? Element, let t = try? e.text() { return AnalyzeRule.parse(t, baseUrl: baseUrl) }
        return obj
    }

    static func element(_ obj: Any) -> Element? {
        if let e = obj as? Element { return e }
        if let s = obj as? String { return try? SwiftSoup.parse(s) }
        return nil
    }

    static func asString(_ v: Any) -> String {
        switch v {
        case let s as String: return s
        case let e as Element: return (try? e.text()) ?? ""
        case let n as NSNumber: return n.stringValue
        case let a as [Any]: return a.map { asString($0) }.joined(separator: "\n")
        case is NSNull: return ""
        default:
            if JSONSerialization.isValidJSONObject(v), let d = try? JSONSerialization.data(withJSONObject: v) {
                return String(data: d, encoding: .utf8) ?? ""
            }
            return "\(v)"
        }
    }
}
