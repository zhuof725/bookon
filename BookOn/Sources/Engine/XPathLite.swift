import Foundation
import SwiftSoup

/// XPath 子集 → SwiftSoup 求值。覆盖书源里 95% 的写法：
/// //div[@class="x"]/a/@href   //div[@id='list']/dl/dd/a/text()   //div[contains(@class,"a")]//p
/// //ul/li[1]   //li[last()]   //li[position()>1]   //a[text()="下一页"]   ./p   .//a
/// 末尾支持 /text() /@attr /string() /html()，以及 | 联合。
enum XPathLite {

    static func query(_ xpath: String, in root: Element) -> [Node] {
        var results: [Node] = []
        for part in splitUnion(xpath) {
            results += evalSingle(part.trimmingCharacters(in: .whitespaces), root)
        }
        return results
    }

    static func getStringList(_ xpath: String, in root: Element) -> [String] {
        var out: [String] = []
        for n in query(xpath, in: root) {
            if let t = n as? TextNode { let s = t.text().trimmingCharacters(in: .whitespacesAndNewlines); if !s.isEmpty { out.append(s) } }
            else if let a = n as? AttrNode { if !a.value.isEmpty { out.append(a.value) } }
            else if let e = n as? Element { if let t = try? e.text(), !t.isEmpty { out.append(t) } }
        }
        return out
    }

    static func getString(_ xpath: String, in root: Element) -> String? {
        let l = getStringList(xpath, in: root)
        return l.isEmpty ? nil : l.joined(separator: "\n")
    }

    static func getElements(_ xpath: String, in root: Element) -> [Element] {
        query(xpath, in: root).compactMap { $0 as? Element }
    }

    /// 伪节点：属性值
    final class AttrNode: Node {
        let value: String
        init(_ v: String) { value = v; super.init("") }
        override func nodeName() -> String { "#attr" }
    }

    // MARK: - impl

    private static func splitUnion(_ s: String) -> [String] {
        var parts: [String] = []; var cur = ""; var depth = 0; var q: Character? = nil
        for c in s {
            if let qq = q { if c == qq { q = nil } ; cur.append(c); continue }
            if c == "'" || c == "\"" { q = c; cur.append(c); continue }
            if c == "[" { depth += 1 } else if c == "]" { depth -= 1 }
            if c == "|" && depth == 0 { parts.append(cur); cur = ""; continue }
            cur.append(c)
        }
        parts.append(cur)
        return parts
    }

    private struct Step { var descendant: Bool; var name: String; var predicates: [String] }

    private static func tokenize(_ xp: String) -> [Step] {
        var steps: [Step] = []
        let chars = Array(xp)
        var i = 0
        while i < chars.count {
            var descendant = false
            if chars[i] == "/" {
                i += 1
                if i < chars.count, chars[i] == "/" { descendant = true; i += 1 }
            } else if chars[i] == "." {
                // "." or "./" or ".//"
                i += 1; continue
            }
            var name = ""
            while i < chars.count, chars[i] != "/", chars[i] != "[" { name.append(chars[i]); i += 1 }
            var preds: [String] = []
            while i < chars.count, chars[i] == "[" {
                var depth = 0; var body = ""; i += 1
                var q: Character? = nil
                while i < chars.count {
                    let c = chars[i]
                    if let qq = q { if c == qq { q = nil }; body.append(c); i += 1; continue }
                    if c == "'" || c == "\"" { q = c }
                    if c == "[" { depth += 1 }
                    if c == "]" { if depth == 0 { break }; depth -= 1 }
                    body.append(c); i += 1
                }
                i += 1
                preds.append(body)
            }
            if !name.isEmpty || !preds.isEmpty { steps.append(Step(descendant: descendant, name: name, predicates: preds)) }
        }
        return steps
    }

    private static func evalSingle(_ xp: String, _ root: Element) -> [Node] {
        var steps = tokenize(xp)
        guard !steps.isEmpty else { return [] }
        // terminal
        var terminal: String? = nil
        if let last = steps.last, last.name.hasPrefix("@") || last.name.hasSuffix("()") {
            terminal = last.name
            steps.removeLast()
        }
        var current: [Element] = [root]
        for step in steps {
            var next: [Element] = []
            for e in current {
                var cands: [Element]
                if step.name == ".." { cands = e.parent().map { [$0] } ?? [] }
                else if step.descendant {
                    cands = (try? e.getAllElements()).map(Array.init) ?? []
                    cands.removeAll { $0 === e }
                    if step.name != "*" && !step.name.isEmpty { cands = cands.filter { $0.tagName().lowercased() == step.name.lowercased() } }
                } else {
                    cands = Array(e.children())
                    if step.name != "*" && !step.name.isEmpty { cands = cands.filter { $0.tagName().lowercased() == step.name.lowercased() } }
                }
                for p in step.predicates { cands = applyPredicate(p, cands, positional: !step.descendant) }
                next += cands
            }
            // dedupe preserving order
            var seen = Set<ObjectIdentifier>()
            current = next.filter { seen.insert(ObjectIdentifier($0)).inserted }
        }
        guard let t = terminal else { return current }
        var out: [Node] = []
        switch t {
        case "text()":
            for e in current { out += e.textNodes().map { $0 as Node } }
        case "string()", "normalize-space()":
            for e in current { out.append(TextNode((try? e.text()) ?? "", "")) }
        case "html()", "outerHtml()":
            for e in current { out.append(TextNode((try? e.outerHtml()) ?? "", "")) }
        case "node()":
            for e in current { out += e.getChildNodes() }
        default:
            if t.hasPrefix("@") {
                let attr = String(t.dropFirst())
                for e in current { if let v = try? e.attr(attr), !v.isEmpty { out.append(AttrNode(v)) } }
            }
        }
        return out
    }

    private static func applyPredicate(_ p: String, _ els: [Element], positional: Bool) -> [Element] {
        let pred = p.trimmingCharacters(in: .whitespaces)
        if let n = Int(pred) { return n >= 1 && n <= els.count ? [els[n - 1]] : [] }
        if pred == "last()" { return els.last.map { [$0] } ?? [] }
        if pred.hasPrefix("last()-"), let k = Int(pred.dropFirst(7)) { let i = els.count - 1 - k; return i >= 0 ? [els[i]] : [] }
        if pred.hasPrefix("position()") {
            let rest = pred.dropFirst(10).trimmingCharacters(in: .whitespaces)
            let ops = [">=", "<=", "!=", ">", "<", "="]
            for op in ops where rest.hasPrefix(op) {
                guard let v = Int(rest.dropFirst(op.count).trimmingCharacters(in: .whitespaces)) else { return els }
                return els.enumerated().filter { (i, _) in
                    let pos = i + 1
                    switch op { case ">": return pos > v; case "<": return pos < v; case ">=": return pos >= v; case "<=": return pos <= v; case "!=": return pos != v; default: return pos == v }
                }.map { $0.element }
            }
        }
        // or / and
        if let r = pred.range(of: " or ") {
            let a = applyPredicate(String(pred[..<r.lowerBound]), els, positional: positional)
            let b = applyPredicate(String(pred[r.upperBound...]), els, positional: positional)
            return els.filter { e in a.contains { $0 === e } || b.contains { $0 === e } }
        }
        if let r = pred.range(of: " and ") {
            let a = applyPredicate(String(pred[..<r.lowerBound]), els, positional: positional)
            return applyPredicate(String(pred[r.upperBound...]), a, positional: positional)
        }
        if pred.hasPrefix("not(") && pred.hasSuffix(")") {
            let inner = String(pred.dropFirst(4).dropLast())
            let ex = applyPredicate(inner, els, positional: positional)
            return els.filter { e in !ex.contains { $0 === e } }
        }
        return els.filter { test(pred, $0) }
    }

    private static func value(_ expr: String, _ e: Element) -> String? {
        let x = expr.trimmingCharacters(in: .whitespaces)
        if x.hasPrefix("@") { return (try? e.attr(String(x.dropFirst()))) }
        if x == "text()" || x == "." || x == "string(.)" || x == "normalize-space(.)" || x == "normalize-space(text())" { return (try? e.text()) }
        if x.hasPrefix("'") || x.hasPrefix("\"") { return String(x.dropFirst().dropLast()) }
        if x == "name()" { return e.tagName() }
        // nested path like a/@href or span/text()
        let nodes = evalSingle("./" + x, e)
        for n in nodes {
            if let t = n as? TextNode { return t.text() }
            if let a = n as? AttrNode { return a.value }
            if let el = n as? Element { return try? el.text() }
        }
        return nil
    }

    private static func test(_ pred: String, _ e: Element) -> Bool {
        let fnPattern = #"^(contains|starts-with|ends-with|matches)\((.+),(.+)\)$"#
        if let m = pred.range(of: fnPattern, options: .regularExpression) {
            let s = String(pred[m])
            guard let re = try? NSRegularExpression(pattern: fnPattern),
                  let match = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return false }
            let fn = String(s[Range(match.range(at: 1), in: s)!])
            let a = value(String(s[Range(match.range(at: 2), in: s)!]), e) ?? ""
            let b = value(String(s[Range(match.range(at: 3), in: s)!]), e) ?? ""
            switch fn {
            case "contains": return a.contains(b)
            case "starts-with": return a.hasPrefix(b)
            case "ends-with": return a.hasSuffix(b)
            default: return a.range(of: b, options: .regularExpression) != nil
            }
        }
        for op in ["!=", "="] {
            if let r = pred.range(of: op) {
                let l = value(String(pred[..<r.lowerBound]), e)
                let rv = value(String(pred[r.upperBound...]), e)
                let eq = (l ?? "").trimmingCharacters(in: .whitespaces) == (rv ?? "")
                return op == "=" ? eq : !eq
            }
        }
        // attribute / child existence
        if pred.hasPrefix("@") { return e.hasAttr(String(pred.dropFirst())) }
        return !evalSingle("./" + pred, e).isEmpty
    }
}
