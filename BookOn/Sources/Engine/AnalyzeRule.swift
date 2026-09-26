import Foundation
import SwiftSoup
import JavaScriptCore

/// 移植 Legado AnalyzeRule：规则分段（@js: / <js> / @XPath: / @Json: / @CSS: / ##正则替换 / {{}} / @get:）并逐段求值。
final class AnalyzeRule: RuleAnalyzerContext {
    let source: BookSource?
    let js: JSEngine
    private(set) var content: Any?
    private(set) var baseUrl: String
    var redirectUrl: String
    private var variables: [String: String] = [:]
    var bookVariables: (get: (String) -> String?, put: (String, String) -> Void)?

    /// 开启后每一步规则求值都会写入诊断日志
    var verbose = false
    private var jsoupCache: HtmlAnalyzer?
    private var jsoupSrc: AnyObject?
    private var jsonCache: Any?

    init(source: BookSource?, content: Any? = nil, baseUrl: String? = nil, js: JSEngine? = nil) {
        self.source = source
        self.js = js ?? JSEngine()
        self.baseUrl = baseUrl ?? source?.bookSourceUrl ?? ""
        self.redirectUrl = self.baseUrl
        self.content = content
        self.js.analyzer = self
        self.js.set("source", source.map { ["bookSourceUrl": $0.bookSourceUrl, "bookSourceName": $0.bookSourceName, "key": $0.bookSourceUrl] } ?? [:])
        self.js.ctx.evaluateScript("""
        if (source) {
          source.getKey = function(){ return this.bookSourceUrl };
          source.getTag = function(){ return this.bookSourceName };
          source.getLoginHeader = function(){ return java.get('__loginHeader') || null };
          source.putLoginHeader = function(h){ java.put('__loginHeader', h) };
          source.getLoginHeaderMap = function(){ var h = this.getLoginHeader(); return h ? JSON.parse(h) : null };
          source.getVariable = function(){ return java.get('__sourceVariable') };
          source.setVariable = function(v){ java.put('__sourceVariable', v) };
          source.getLoginInfo = function(){ return java.get('__loginInfo') };
          source.getLoginInfoMap = function(){ var h = this.getLoginInfo(); return h ? JSON.parse(h) : null };
        }
        """)
        self.js.set("baseUrl", self.baseUrl)
        if let lib = source?.jsLib, !lib.isEmpty { self.js.loadJsLib(lib) }
    }

    @discardableResult
    func setContent(_ c: Any?, baseUrl: String? = nil) -> AnalyzeRule {
        content = c; jsoupCache = nil; jsonCache = nil
        if let b = baseUrl { self.baseUrl = b; redirectUrl = b; js.set("baseUrl", b) }
        return self
    }
    func jsSetContent(_ content: Any?, baseUrl: String?) { setContent(content, baseUrl: baseUrl) }

    func setRedirect(_ url: String) { redirectUrl = url; if let b = URL(string: url) { baseUrl = b.absoluteString } }

    // MARK: variables
    func put(_ key: String, _ value: String) { variables[key] = value; bookVariables?.put(key, value) }
    func get(_ key: String) -> String {
        if let v = variables[key] { return v }
        return bookVariables?.get(key) ?? ""
    }

    // MARK: modes
    enum Mode { case xpath, json, `default`, js, regex }

    final class SourceRule {
        var mode: Mode
        var rule: String
        var replaceRegex = ""
        var replacement = ""
        var replaceFirst = false
        var putMap: [String: String] = [:]
        private var params: [String] = []
        private var types: [Int] = []   // -2 get, -1 js, 0 literal, >0 regex group

        init(_ ruleStr: String, mode: Mode = .default, isJSON: Bool) {
            self.mode = mode
            var r = ruleStr
            if mode == .js || mode == .regex { rule = r }
            else if r.lowercased().hasPrefix("@css:") { self.mode = .default; rule = r }
            else if r.hasPrefix("@@") { self.mode = .default; rule = String(r.dropFirst(2)) }
            else if r.lowercased().hasPrefix("@xpath:") { self.mode = .xpath; rule = String(r.dropFirst(7)) }
            else if r.lowercased().hasPrefix("@json:") { self.mode = .json; rule = String(r.dropFirst(6)) }
            else if isJSON || r.hasPrefix("$.") || r.hasPrefix("$[") { self.mode = .json; rule = r }
            else if r.hasPrefix("/") { self.mode = .xpath; rule = r }
            else { rule = r }
            r = rule
            rule = SourceRule.splitPut(r, &putMap)
            // {{ }} & @get:{}
            let ns = rule as NSString
            let evalRe = try! NSRegularExpression(pattern: "@get:\\{[^}]+?\\}|\\{\\{[\\w\\W]*?\\}\\}|\\$\\d{1,2}")
            let matches = evalRe.matches(in: rule, range: NSRange(location: 0, length: ns.length))
            var start = 0
            if let first = matches.first(where: { !ns.substring(with: $0.range).hasPrefix("$") }) {
                let head = ns.substring(to: first.range.location)
                if self.mode != .js && self.mode != .regex && (first.range.location == 0 || !head.contains("##")) { self.mode = .regex }
            }
            for m in matches {
                if m.range.location > start { splitRegex(ns.substring(with: NSRange(location: start, length: m.range.location - start))) }
                let t = ns.substring(with: m.range)
                if t.lowercased().hasPrefix("@get:") { types.append(-2); params.append(String(t.dropFirst(6).dropLast())) }
                else if t.hasPrefix("{{") { types.append(-1); params.append(String(t.dropFirst(2).dropLast(2))) }
                else { splitRegex(t) }
                start = m.range.location + m.range.length
            }
            if ns.length > start { splitRegex(ns.substring(from: start)) }
        }

        private func splitRegex(_ s: String) {
            let firstPart = s.components(separatedBy: "##")[0]
            let re = try! NSRegularExpression(pattern: "\\$\\d{1,2}")
            let ns = firstPart as NSString
            let ms = re.matches(in: firstPart, range: NSRange(location: 0, length: ns.length))
            if !ms.isEmpty {
                if mode != .js && mode != .regex { mode = .regex }
                var start = 0
                for m in ms {
                    if m.range.location > start { types.append(0); params.append(ns.substring(with: NSRange(location: start, length: m.range.location - start))) }
                    let t = ns.substring(with: m.range)
                    types.append(Int(t.dropFirst()) ?? 0); params.append(t)
                    start = m.range.location + m.range.length
                }
                let rest = (s as NSString).substring(from: start)
                if !rest.isEmpty { types.append(0); params.append(rest) }
            } else if !s.isEmpty { types.append(0); params.append(s) }
        }

        var paramSize: Int { params.count }

        func makeUp(_ result: Any?, analyzer: AnalyzeRule) {
            if !params.isEmpty {
                var out = ""
                for (i, p) in params.enumerated() {
                    switch types[i] {
                    case let g where g > 0:
                        if let list = result as? [String], list.count > g { out += list[g] } else { out += p }
                    case -1:
                        if SourceRule.isRule(p) { out += analyzer.getString(p) }
                        else if let v = analyzer.js.eval(p, result: result, baseUrl: analyzer.baseUrl), !v.isNull, !v.isUndefined { out += JSEngine.stringify(v) }
                    case -2: out += analyzer.get(p)
                    default: out += p
                    }
                }
                rule = out
            }
            let parts = rule.components(separatedBy: "##")
            rule = parts[0].trimmingCharacters(in: .whitespaces)
            if parts.count > 1 { replaceRegex = parts[1] }
            if parts.count > 2 { replacement = parts[2] }
            if parts.count > 3 { replaceFirst = true }
        }

        static func isRule(_ s: String) -> Bool { s.hasPrefix("@") || s.hasPrefix("$.") || s.hasPrefix("$[") || s.hasPrefix("//") }

        /// @put:{key:rule}
        private static func splitPut(_ rule: String, _ map: inout [String: String]) -> String {
            guard rule.contains("@put:") else { return rule }
            var out = rule
            while let r = out.range(of: "@put:", options: .caseInsensitive) {
                let after = out[r.upperBound...]
                guard after.hasPrefix("{") else { break }
                var depth = 0; var end = after.startIndex
                for i in after.indices { if after[i] == "{" { depth += 1 } else if after[i] == "}" { depth -= 1; if depth == 0 { end = i; break } } }
                let body = String(after[after.index(after: after.startIndex)..<end])
                // body like key:rule  或  "key":"rule"
                if let d = ("{" + body + "}").data(using: .utf8), let o = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] {
                    for (k, v) in o { map[k] = J.str(v) ?? "" }
                } else if let c = body.firstIndex(of: ":") {
                    map[String(body[..<c]).trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))] = String(body[body.index(after: c)...]).trimmingCharacters(in: CharacterSet(charactersIn: " \"'"))
                }
                out.removeSubrange(r.lowerBound...end)
            }
            return out
        }
    }

    private var isJSON: Bool {
        if let s = content as? String { let t = s.trimmingCharacters(in: .whitespacesAndNewlines); return t.hasPrefix("{") || t.hasPrefix("[") }
        return content is [String: Any] || content is [Any]
    }

    func splitSourceRule(_ ruleStr: String?, allInOne: Bool = false) -> [SourceRule] {
        guard let ruleStr = ruleStr, !ruleStr.isEmpty else { return [] }
        var list: [SourceRule] = []
        var mode: Mode = .default
        var start = 0
        var s = ruleStr
        if allInOne && s.hasPrefix(":") { mode = .regex; s.removeFirst() }
        let ns = s as NSString
        let re = try! NSRegularExpression(pattern: "<js>([\\w\\W]*?)</js>|@js:([\\w\\W]*)", options: .caseInsensitive)
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            if m.range.location > start {
                let t = ns.substring(with: NSRange(location: start, length: m.range.location - start)).trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { list.append(SourceRule(t, mode: mode, isJSON: isJSON)) }
            }
            let code = m.range(at: 1).location != NSNotFound ? ns.substring(with: m.range(at: 1)) : ns.substring(with: m.range(at: 2))
            list.append(SourceRule(code, mode: .js, isJSON: isJSON))
            start = m.range.location + m.range.length
        }
        if ns.length > start {
            let t = ns.substring(from: start).trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { list.append(SourceRule(t, mode: mode, isJSON: isJSON)) }
        }
        return list
    }

    // MARK: getString

    func getString(_ rule: String?, content: Any? = nil, isUrl: Bool = false, unescape: Bool = true) -> String {
        guard let rule = rule, !rule.isEmpty else { return isUrl ? (baseUrl) : "" }
        return getString(splitSourceRule(rule), content: content, isUrl: isUrl, unescape: unescape)
    }
    func jsGetString(_ rule: String, content: Any?) -> String { getString(rule, content: content, isUrl: false) }

    func getString(_ rules: [SourceRule], content mContent: Any? = nil, isUrl: Bool = false, unescape: Bool = true) -> String {
        var result: Any? = nil
        let c = mContent ?? content
        if let c = c, !rules.isEmpty {
            result = c
            if let dict = c as? [String: Any], rules.count == 1, !(rules[0].rule.hasPrefix("$")), !rules[0].rule.hasPrefix("@"), rules[0].mode != .js {
                // 键值直接访问
                let sr = rules[0]; putRules(sr.putMap); sr.makeUp(result, analyzer: self)
                result = sr.paramSize > 1 ? sr.rule : dict[sr.rule].map(JSONPath.stringify)
                if let r = result as? String { result = replaceRegex(r, sr) }
            } else {
                for sr in rules {
                    putRules(sr.putMap)
                    sr.makeUp(result, analyzer: self)
                    guard let r = result else { continue }
                    let rule = sr.rule
                    if !rule.isEmpty || sr.replaceRegex.isEmpty {
                        switch sr.mode {
                        case .js: result = jsResult(js.eval(rule, result: r, baseUrl: baseUrl))
                        case .json: result = JSONPath.getString(rule, in: JSONPath.parse(r) ?? r)
                        case .xpath: result = XPathLite.getString(rule, in: element(r))
                        case .default: result = isUrl ? htmlAnalyzer(r).getString0(rule) : htmlAnalyzer(r).getString(rule)
                        case .regex: result = rule
                        }
                    }
                    if let r2 = result, !sr.replaceRegex.isEmpty { result = replaceRegex(anyToString(r2), sr) }
                    if verbose { DiagLog.shared.info("规则", "\(sr.mode) 「\(DiagLog.preview(rule, 80))」→ \(DiagLog.preview(result.map(anyToString) ?? "null", 120))") }
                }
            }
        }
        var str = result.map(anyToString) ?? ""
        if unescape, str.contains("&") { str = (try? Entities.unescape(str)) ?? str }
        if isUrl {
            return str.trimmingCharacters(in: .whitespaces).isEmpty ? baseUrl : NetworkUtils.absoluteURL(redirectUrl, str)
        }
        return str
    }

    // MARK: getStringList

    func getStringList(_ rule: String?, content: Any? = nil, isUrl: Bool = false) -> [String]? {
        guard let rule = rule, !rule.isEmpty else { return nil }
        return getStringList(splitSourceRule(rule), content: content, isUrl: isUrl)
    }
    func jsGetStringList(_ rule: String, content: Any?) -> [String] { getStringList(rule, content: content, isUrl: false) ?? [] }

    func getStringList(_ rules: [SourceRule], content mContent: Any? = nil, isUrl: Bool = false) -> [String]? {
        var result: Any? = nil
        let c = mContent ?? content
        if let c = c, !rules.isEmpty {
            result = c
            for sr in rules {
                putRules(sr.putMap)
                sr.makeUp(result, analyzer: self)
                guard let r = result else { continue }
                let rule = sr.rule
                if !rule.isEmpty {
                    switch sr.mode {
                    case .js: result = jsResult(js.eval(rule, result: r, baseUrl: baseUrl))
                    case .json: result = JSONPath.getStringList(rule, in: JSONPath.parse(r) ?? r)
                    case .xpath: result = XPathLite.getStringList(rule, in: element(r))
                    case .default: result = htmlAnalyzer(r).getStringList(rule)
                    case .regex: result = rule
                    }
                }
                if !sr.replaceRegex.isEmpty {
                    if let list = result as? [String] { result = list.map { replaceRegex($0, sr) } }
                    else if let r2 = result { result = replaceRegex(anyToString(r2), sr) }
                }
            }
        }
        guard let r = result else { return nil }
        var list: [String]
        if let s = r as? String { list = s.components(separatedBy: "\n") }
        else if let l = r as? [String] { list = l }
        else if let l = r as? [Any] { list = l.map(anyToString) }
        else { list = [anyToString(r)] }
        if isUrl {
            var out: [String] = []
            for u in list { let a = NetworkUtils.absoluteURL(redirectUrl, u); if !a.isEmpty, !out.contains(a) { out.append(a) } }
            return out
        }
        return list
    }

    // MARK: getElements（列表规则）

    func getElements(_ ruleStr: String) -> [Any] {
        var result: Any? = content
        let rules = splitSourceRule(ruleStr, allInOne: true)
        for sr in rules {
            putRules(sr.putMap)
            sr.makeUp(result, analyzer: self)
            guard let r = result, !sr.rule.isEmpty else { continue }
            switch sr.mode {
            case .js: result = jsResult(js.eval(sr.rule, result: r, baseUrl: baseUrl))
            case .json: result = JSONPath.getList(sr.rule, in: JSONPath.parse(r) ?? r)
            case .xpath: result = XPathLite.getElements(sr.rule, in: element(r))
            case .default: result = htmlAnalyzer(r).getElements(sr.rule)
            case .regex: result = regexElements(anyToString(r), sr.rule)
            }
            if !sr.replaceRegex.isEmpty, let list = result as? [String] { result = list.map { replaceRegex($0, sr) } }
        }
        var out: [Any] = []
        if let l = result as? [Any] { out = l }
        else if let l = result as? [Element] { out = l }
        else if let s = result as? String, !s.isEmpty { out = s.components(separatedBy: "\n") }
        DiagLog.shared.info("列表", "「\(DiagLog.preview(ruleStr, 80))」→ \(out.count) 项")
        if out.isEmpty { DiagLog.shared.warn("列表", "内容预览: \(DiagLog.preview(content.map(anyToString) ?? "nil", 200))") }
        return out
    }

    func getElementsHtml(_ rule: String) -> [String] {
        getElements(rule).map { ($0 as? Element).flatMap { try? $0.outerHtml() } ?? anyToString($0) }
    }

    // MARK: helpers

    private func regexElements(_ text: String, _ pattern: String) -> [[String]] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        let ns = text as NSString
        return re.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { m in
            (0..<m.numberOfRanges).map { m.range(at: $0).location == NSNotFound ? "" : ns.substring(with: m.range(at: $0)) }
        }
    }

    private func putRules(_ map: [String: String]) {
        for (k, r) in map { put(k, getString(r)) }
    }

    private func replaceRegex(_ result: String, _ sr: SourceRule) -> String {
        guard !sr.replaceRegex.isEmpty else { return result }
        let replacement = sr.replacement.replacingOccurrences(of: "$", with: "$$").replacingOccurrences(of: "$$", with: "$") // keep $1 semantic
        guard let re = try? NSRegularExpression(pattern: sr.replaceRegex, options: []) else {
            return result.replacingOccurrences(of: sr.replaceRegex, with: sr.replacement)
        }
        let ns = result as NSString
        if sr.replaceFirst {
            guard let m = re.firstMatch(in: result, range: NSRange(location: 0, length: ns.length)) else { return "" }
            let matched = ns.substring(with: m.range)
            return re.stringByReplacingMatches(in: matched, range: NSRange(location: 0, length: (matched as NSString).length), withTemplate: replacement)
        }
        return re.stringByReplacingMatches(in: result, range: NSRange(location: 0, length: ns.length), withTemplate: replacement)
    }

    private func htmlAnalyzer(_ o: Any) -> HtmlAnalyzer {
        if let cached = jsoupCache, let src = jsoupSrc, src === (o as AnyObject) { return cached }
        let a = HtmlAnalyzer(o)
        jsoupCache = a; jsoupSrc = o as AnyObject
        return a
    }
    private func element(_ o: Any) -> Element {
        if let e = o as? Element { return e }
        return (try? SwiftSoup.parse(anyToString(o))) ?? Document("")
    }

    func anyToString(_ v: Any) -> String {
        if let s = v as? String { return s }
        if let e = v as? Element { return (try? e.outerHtml()) ?? "" }
        if let l = v as? [Element] { return l.compactMap { try? $0.outerHtml() }.joined(separator: "\n") }
        if let l = v as? [String] { return l.joined(separator: "\n") }
        if let j = v as? JSValue { return JSEngine.stringify(j) }
        return JSONPath.stringify(v)
    }
    private func jsResult(_ v: JSValue?) -> Any? {
        guard let v = v, !v.isNull, !v.isUndefined else { return nil }
        return jsToAny(v)
    }
    private func jsToAny(_ v: JSValue) -> Any {
        if v.isString { return v.toString() as String }
        if v.isArray { return (v.toArray() ?? []).map { ($0 as? String) ?? JSONPath.stringify($0) } }
        if v.isObject { return v.toObject() ?? "" }
        return JSEngine.stringify(v)
    }
}

// MARK: - HtmlFormatter（移植）

enum HtmlFormatter {
    private static func re(_ p: String) -> NSRegularExpression { try! NSRegularExpression(pattern: p, options: [.caseInsensitive]) }
    private static let nbsp = re("(&nbsp;)+")
    private static let esp = re("(&ensp;|&emsp;)")
    private static let noPrint = re("(&thinsp;|&zwnj;|&zwj;|\u{2009}|\u{200C}|\u{200D})")
    private static let wrap = re("</?(?:div|p|br|hr|h\\d|article|dd|dl)[^>]*>")
    private static let comment = re("<!--[^>]*-->")
    private static let notImg = re("</?(?!img)[a-zA-Z]+(?=[ >])[^<>]*>")
    private static let other = re("</?[a-zA-Z]+(?=[ >])[^<>]*>")
    private static let indent1 = re("\\s*\\n+\\s*")
    private static let indent2 = re("^[\\n\\s]+")
    private static let last = re("[\\n\\s]+$")
    private static let img = re("<img[^>]*\\s(?:data-(?:src|original)|src)\\s*=\\s*['\"]([^'\">]+)['\"][^>]*>")

    private static func rep(_ s: String, _ r: NSRegularExpression, _ t: String) -> String {
        r.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: t)
    }

    static func format(_ html: String?, keepImg: Bool = false) -> String {
        guard var s = html else { return "" }
        s = rep(s, nbsp, " "); s = rep(s, esp, " "); s = rep(s, noPrint, "")
        s = rep(s, wrap, "\n"); s = rep(s, comment, "")
        s = rep(s, keepImg ? notImg : other, "")
        s = rep(s, indent1, "\n　　"); s = rep(s, indent2, "　　"); s = rep(s, last, "")
        return s
    }

    static func formatKeepImg(_ html: String?, baseUrl: String?) -> String {
        let s = format(html, keepImg: true)
        let ns = s as NSString
        var out = ""; var pos = 0
        for m in img.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: pos, length: m.range.location - pos))
            let src = ns.substring(with: m.range(at: 1))
            out += "<img src=\"\(NetworkUtils.absoluteURL(baseUrl, src))\">"
            pos = m.range.location + m.range.length
        }
        out += ns.substring(from: pos)
        return out
    }
}
