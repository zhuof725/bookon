import Foundation

/// 轻量 JSONPath（覆盖书源常用语法）：
/// $.a.b  $['a']  $.list[0]  $.list[-1]  $.list[*]  $.list[1:3]  $..name  $.list[?(@.type=='x')]
/// 以及 Legado 扩展：{$.a}{$.b} 拼接、a.b 无 $ 前缀。
enum JSONPath {

    static func parse(_ any: Any) -> Any? {
        if let s = any as? String {
            guard let d = s.data(using: .utf8) else { return nil }
            return try? JSONSerialization.jsonObject(with: d, options: [.fragmentsAllowed])
        }
        return any
    }

    // MARK: query

    static func query(_ path: String, in root: Any) -> [Any] {
        var p = path.trimmingCharacters(in: .whitespaces)
        if p.hasPrefix("$") { p.removeFirst() }
        let tokens = tokenize(p)
        var cur: [Any] = [root]
        for t in tokens {
            var next: [Any] = []
            for node in cur { next += apply(t, to: node) }
            cur = next
        }
        return cur
    }

    private enum Token {
        case key(String)
        case deep(String)          // ..key
        case wildcard
        case index(Int)
        case slice(Int?, Int?)
        case union([String])
        case filter(String)
    }

    private static func tokenize(_ s: String) -> [Token] {
        var tokens: [Token] = []
        let chars = Array(s)
        var i = 0
        func readKey() -> String {
            var k = ""
            while i < chars.count, chars[i] != ".", chars[i] != "[" { k.append(chars[i]); i += 1 }
            return k
        }
        while i < chars.count {
            let c = chars[i]
            if c == "." {
                i += 1
                if i < chars.count, chars[i] == "." {
                    i += 1
                    if i < chars.count, chars[i] == "[" { continue } // ..[ handled by bracket as wildcard-deep (approx)
                    let k = readKey()
                    tokens.append(k == "*" ? .wildcard : .deep(k))
                } else if i < chars.count, chars[i] != "[" {
                    let k = readKey()
                    if k == "*" { tokens.append(.wildcard) } else if !k.isEmpty { tokens.append(.key(k)) }
                }
            } else if c == "[" {
                var depth = 0; var body = ""; i += 1
                while i < chars.count {
                    if chars[i] == "[" { depth += 1 }
                    if chars[i] == "]" { if depth == 0 { break }; depth -= 1 }
                    body.append(chars[i]); i += 1
                }
                i += 1
                let b = body.trimmingCharacters(in: .whitespaces)
                if b == "*" { tokens.append(.wildcard) }
                else if b.hasPrefix("?") { tokens.append(.filter(String(b.dropFirst()).trimmingCharacters(in: CharacterSet(charactersIn: "() ")))) }
                else if b.hasPrefix("'") || b.hasPrefix("\"") {
                    let keys = b.components(separatedBy: ",").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " '\"")) }
                    tokens.append(keys.count == 1 ? .key(keys[0]) : .union(keys))
                } else if b.contains(":") {
                    let parts = b.components(separatedBy: ":")
                    tokens.append(.slice(Int(parts[0].trimmingCharacters(in: .whitespaces)), parts.count > 1 ? Int(parts[1].trimmingCharacters(in: .whitespaces)) : nil))
                } else if let n = Int(b) { tokens.append(.index(n)) }
                else if b.contains(",") { tokens.append(.union(b.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) })) }
                else if !b.isEmpty { tokens.append(.key(b)) }
            } else {
                let k = readKey()
                if !k.isEmpty { tokens.append(.key(k)) }
            }
        }
        return tokens
    }

    private static func apply(_ t: Token, to node: Any) -> [Any] {
        switch t {
        case .key(let k):
            if let d = node as? [String: Any], let v = d[k] { return [v] }
            if let a = node as? [Any], let n = Int(k), n >= 0, n < a.count { return [a[n]] }
            return []
        case .deep(let k):
            var out: [Any] = []
            walk(node) { n in if let d = n as? [String: Any], let v = d[k] { out.append(v) } }
            return out
        case .wildcard:
            if let d = node as? [String: Any] { return Array(d.values) }
            if let a = node as? [Any] { return a }
            return []
        case .index(let n):
            guard let a = node as? [Any] else { return [] }
            let i = n < 0 ? a.count + n : n
            return i >= 0 && i < a.count ? [a[i]] : []
        case .slice(let s, let e):
            guard let a = node as? [Any] else { return [] }
            var st = s ?? 0; if st < 0 { st += a.count }
            var en = e ?? a.count; if en < 0 { en += a.count }
            st = max(0, st); en = min(a.count, en)
            return st < en ? Array(a[st..<en]) : []
        case .union(let ks):
            if let d = node as? [String: Any] { return ks.compactMap { d[$0] } }
            if let a = node as? [Any] { return ks.compactMap { Int($0) }.compactMap { $0 < a.count ? a[$0] : nil } }
            return []
        case .filter(let expr):
            guard let a = node as? [Any] else { return [] }
            return a.filter { evalFilter(expr, $0) }
        }
    }

    private static func walk(_ node: Any, _ visit: (Any) -> Void) {
        visit(node)
        if let d = node as? [String: Any] { d.values.forEach { walk($0, visit) } }
        else if let a = node as? [Any] { a.forEach { walk($0, visit) } }
    }

    /// 支持 @.key op value，op ∈ == != > < >= <= =~；以及 @.key 存在判断；&& || 简单组合
    private static func evalFilter(_ expr: String, _ item: Any) -> Bool {
        if expr.contains("||") { return expr.components(separatedBy: "||").contains { evalFilter($0.trimmingCharacters(in: .whitespaces), item) } }
        if expr.contains("&&") { return expr.components(separatedBy: "&&").allSatisfy { evalFilter($0.trimmingCharacters(in: .whitespaces), item) } }
        let ops = ["==", "!=", ">=", "<=", ">", "<", "=~"]
        for op in ops {
            if let r = expr.range(of: op) {
                let lhs = expr[..<r.lowerBound].trimmingCharacters(in: .whitespaces)
                var rhs = expr[r.upperBound...].trimmingCharacters(in: .whitespaces)
                let lv = value(of: lhs, item)
                if op == "=~" {
                    guard let lv = lv else { return false }
                    if rhs.hasPrefix("/"), let end = rhs.lastIndex(of: "/") { rhs = String(rhs[rhs.index(after: rhs.startIndex)..<end]) }
                    return lv.range(of: rhs, options: .regularExpression) != nil
                }
                rhs = rhs.trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
                switch op {
                case "==": return lv == rhs
                case "!=": return lv != rhs
                default:
                    guard let a = lv.flatMap(Double.init), let b = Double(rhs) else { return false }
                    switch op { case ">": return a > b; case "<": return a < b; case ">=": return a >= b; default: return a <= b }
                }
            }
        }
        // existence
        return value(of: expr, item) != nil
    }

    private static func value(of ref: String, _ item: Any) -> String? {
        var r = ref.trimmingCharacters(in: .whitespaces)
        guard r.hasPrefix("@") else { return r.trimmingCharacters(in: CharacterSet(charactersIn: "'\"")) }
        r.removeFirst()
        let res = query("$" + r, in: item)
        guard let v = res.first else { return nil }
        return stringify(v)
    }

    // MARK: to string

    static func stringify(_ v: Any) -> String {
        switch v {
        case let s as String: return s
        case is NSNull: return ""
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return n.boolValue ? "true" : "false" }
            let d = n.doubleValue
            if d == d.rounded(), abs(d) < 1e15 { return String(Int64(d)) }
            return n.stringValue
        default:
            if let data = try? JSONSerialization.data(withJSONObject: v, options: [.fragmentsAllowed]),
               let s = String(data: data, encoding: .utf8) { return s }
            return "\(v)"
        }
    }

    // MARK: Legado-style API

    /// getString：支持 {$.a}{$.b} 拼接、&& || 组合
    static func getString(_ rule: String, in root: Any) -> String? {
        if rule.isEmpty { return nil }
        var ra = RuleAnalyzer(rule)
        let rules = ra.splitRule(["&&", "||"])
        var texts: [String] = []
        for r in rules {
            let t: String?
            if r.contains("{$.") || r.contains("{$[") {
                t = RuleAnalyzer.innerRule(r, open: "{", close: "}") { inner in getString(inner, in: root) ?? "" }
            } else {
                let res = query(r, in: root)
                if res.isEmpty { t = nil }
                else if res.count == 1 { t = stringify(res[0]) }
                else { t = res.map(stringify).joined(separator: "\n") }
            }
            if let t = t, !t.isEmpty {
                texts.append(t)
                if ra.elementsType == "||" { break }
            }
        }
        return texts.isEmpty ? nil : texts.joined(separator: "\n")
    }

    static func getStringList(_ rule: String, in root: Any) -> [String] {
        if rule.isEmpty { return [] }
        var ra = RuleAnalyzer(rule)
        let rules = ra.splitRule(["&&", "||", "%%"])
        var results: [[String]] = []
        for r in rules {
            var list: [String]
            if r.contains("{$.") || r.contains("{$[") {
                list = [RuleAnalyzer.innerRule(r, open: "{", close: "}") { inner in getString(inner, in: root) ?? "" }]
            } else {
                let res = query(r, in: root)
                list = res.flatMap { v -> [String] in
                    if let arr = v as? [Any] { return arr.map(stringify) }
                    return [stringify(v)]
                }
            }
            if !list.isEmpty {
                results.append(list)
                if ra.elementsType == "||" { break }
            }
        }
        if ra.elementsType == "%%" {
            var out: [String] = []
            for i in 0..<(results.first?.count ?? 0) { for l in results where i < l.count { out.append(l[i]) } }
            return out
        }
        return results.flatMap { $0 }
    }

    static func getList(_ rule: String, in root: Any) -> [Any] {
        if rule.isEmpty { return [] }
        var ra = RuleAnalyzer(rule)
        let rules = ra.splitRule(["&&", "||", "%%"])
        var results: [[Any]] = []
        for r in rules {
            let res = query(r, in: root)
            let list = res.flatMap { ($0 as? [Any]) ?? [$0] }
            if !list.isEmpty {
                results.append(list)
                if ra.elementsType == "||" { break }
            }
        }
        if ra.elementsType == "%%" {
            var out: [Any] = []
            for i in 0..<(results.first?.count ?? 0) { for l in results where i < l.count { out.append(l[i]) } }
            return out
        }
        return results.flatMap { $0 }
    }
}
