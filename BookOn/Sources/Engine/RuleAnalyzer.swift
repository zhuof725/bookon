import Foundation

/// 通用规则切分：按分隔符拆分，但跳过 [] () 以及引号内的分隔符（移植自 Legado RuleAnalyzer）。
struct RuleAnalyzer {
    private let chars: [Character]
    private(set) var elementsType = ""

    init(_ s: String) { chars = Array(s) }

    /// 去掉开头的 @ 和空白
    static func trimLeading(_ s: String) -> String {
        var i = s.startIndex
        while i < s.endIndex, s[i] == "@" || s[i].asciiValue.map({ $0 < 33 }) == true { i = s.index(after: i) }
        return String(s[i...])
    }

    /// 以多个候选分隔符中**第一个出现**的那个为准切分（与 Legado 相同：一条规则只会用一种组合符）。
    mutating func splitRule(_ seps: [String]) -> [String] {
        var parts: [String] = []
        var cur = ""
        var i = 0
        let n = chars.count
        var depthSq = 0, depthPa = 0
        var inS = false, inD = false
        var chosen: String? = nil

        while i < n {
            let c = chars[i]
            if c == "\\" && i + 1 < n { cur.append(c); cur.append(chars[i + 1]); i += 2; continue }
            if c == "'" && !inD { inS.toggle() }
            else if c == "\"" && !inS { inD.toggle() }
            if !inS && !inD {
                if c == "[" { depthSq += 1 } else if c == "]" { depthSq = max(0, depthSq - 1) }
                else if c == "(" { depthPa += 1 } else if c == ")" { depthPa = max(0, depthPa - 1) }
                if depthSq == 0 && depthPa == 0 {
                    let candidates = chosen.map { [$0] } ?? seps
                    if let sep = candidates.first(where: { matches($0, at: i) }) {
                        chosen = sep
                        parts.append(cur)
                        cur = ""
                        i += sep.count
                        continue
                    }
                }
            }
            cur.append(c)
            i += 1
        }
        parts.append(cur)
        elementsType = chosen ?? ""
        return parts
    }

    private func matches(_ sep: String, at i: Int) -> Bool {
        let s = Array(sep)
        guard i + s.count <= chars.count else { return false }
        for k in 0..<s.count where chars[i + k] != s[k] { return false }
        return true
    }

    /// 替换 {{ }} 内嵌规则：对每一段内嵌内容调用 handler，返回拼接后的字符串
    static func innerRule(_ s: String, open: String = "{{", close: String = "}}", _ handler: (String) -> String) -> String {
        var out = ""
        var rest = Substring(s)
        while let r = rest.range(of: open) {
            out += rest[..<r.lowerBound]
            let afterOpen = rest[r.upperBound...]
            guard let e = afterOpen.range(of: close) else { out += rest[r.lowerBound...]; return out }
            out += handler(String(afterOpen[..<e.lowerBound]))
            rest = afterOpen[e.upperBound...]
        }
        out += rest
        return out
    }
}
