import Foundation

/// Rhino（原版 Legado 的 JS 引擎）与 JavaScriptCore 的语法差异归一化。
///
/// 原版用 Rhino，很多书源的脚本依赖 Rhino 才有的宽松行为，直接丢给 JavaScriptCore 会报
/// SyntaxError（校验日志里真实出现过）：
/// 1. `let result = ...` / `const result = ...`
///    Rhino 把 result 当作「可变的规则全局变量」，JSC 里 `let` 是块级词法声明：
///    - 声明之前读 result 会命中 TDZ 报 ReferenceError；
///    - 声明之后的赋值只改块级变量，引擎回读不到。
///    → 统一改写成 `var result`（无 TDZ，语义与 Rhino 一致）。
/// 2. 箭头函数的**解构唯一参数**：`[title, Id] => {...}`
///    Rhino 接受，JSC 要求写成 `([title, Id]) => {...}`，
///    否则报 “Unexpected token '=>'. Expected ')' to end an argument list.”
///    → 给解构参数补上括号。
/// 3. 函数体顶层用 let/const 重新声明形参：Rhino 接受，JSC 是早期 SyntaxError。
///    → 把这种声明改写成 var。
///
/// 改写只针对「可执行代码」：字符串、模板字符串与注释里的同形文本不会被碰到
/// （先做一次词法遮罩，再在遮罩上匹配，最后按位置回写原文）。
enum RuleScriptCompat {

    /// 归一化后的脚本。无法安全改写时原样返回。
    static func normalize(_ script: String) -> String {
        guard !script.isEmpty else { return script }
        let masked = maskLiterals(script)
        var edits: [(range: NSRange, text: String)] = []

        // 1) let/const result -> var result
        if let re = try? NSRegularExpression(pattern: "\\b(let|const)(\\s+)result\\b") {
            for m in re.matches(in: masked, range: NSRange(location: 0, length: masked.utf16.count)) {
                guard let r = Range(m.range(at: 1), in: masked) else { continue }
                edits.append((NSRange(location: m.range.location, length: m.range.length),
                              "var" + (masked as NSString).substring(with: r)))
            }
        }

        // 2) 解构箭头参数补括号：([ ... ]) =>  →  (([ ... ]) => )
        edits.append(contentsOf: destructuredArrowParamEdits(masked))

        // 3) 函数体顶层重新声明形参 -> var
        edits.append(contentsOf: shadowedParameterEdits(masked))

        if edits.isEmpty { return script }
        // 从后往前应用，避免位移互相影响
        let sorted = edits.sorted { $0.range.location > $1.range.location }
        var result = script
        for edit in sorted {
            let mutable = NSMutableString(string: result)
            mutable.replaceCharacters(in: edit.range, with: edit.text)
            result = mutable as String
        }
        return result
    }

    // MARK: - 词法遮罩

    /// 把字符串字面量、模板字符串与注释的内容替换成等长空格（保留换行），
    /// 这样后续匹配只会落在真正的代码上。
    private static func maskLiterals(_ script: String) -> String {
        let chars = Array(script)
        var out = chars
        let n = chars.count
        func blank(_ range: ClosedRange<Int>) {
            var k = range
            while k <= range.upperBound {
                if k < n, out[k] != "\n" { out[k] = " " }
                k += 1
            }
        }
        var i = 0
        while i < n {
            let c = chars[i]
            if c == "/", i + 1 < n, chars[i + 1] == "/" {
                var j = i
                while j < n, chars[j] != "\n" { j += 1 }
                blank(i...max(i, j - 1))
                i = j
                continue
            }
            if c == "/", i + 1 < n, chars[i + 1] == "*" {
                var j = i + 2
                while j + 1 < n, !(chars[j] == "*" && chars[j + 1] == "/") { j += 1 }
                let end = min(n - 1, j + 1)
                blank(i...end)
                i = end + 1
                continue
            }
            if c == "\"" || c == "'" || c == "`" {
                var j = i + 1
                while j < n {
                    if chars[j] == "\\" { j += 2; continue }
                    if chars[j] == c { break }
                    j += 1
                }
                blank(i...min(n - 1, j))
                i = min(n - 1, j) + 1
                continue
            }
            i += 1
        }
        return String(out)
    }

    // MARK: - 解构箭头参数

    private static func destructuredArrowParamEdits(_ masked: String) -> [(range: NSRange, text: String)] {
        var edits: [(range: NSRange, text: String)] = []
        let ns = masked as NSString
        let n = ns.length
        var i = 0
        while i < n {
            if ns.character(at: i) == 0x5B { // [
                var p = i - 1
                while p >= 0 {
                    let c = ns.character(at: p)
                    if c == 0x20 || c == 0x0A || c == 0x09 || c == 0x0D { p -= 1; continue }
                    break
                }
                let prevOK = p >= 0 && (ns.character(at: p) == 0x28 || ns.character(at: p) == 0x2C)
                if prevOK, let close = matchingBracket(masked, open: 0x5B, close: 0x5D, at: i) {
                    var q = close + 1
                    while q < n {
                        let c = ns.character(at: q)
                        if c == 0x20 || c == 0x0A || c == 0x09 || c == 0x0D { q += 1; continue }
                        break
                    }
                    if q + 1 < n, ns.character(at: q) == 0x3D, ns.character(at: q + 1) == 0x3E {
                        edits.append((NSRange(location: i, length: 0), "("))
                        edits.append((NSRange(location: close + 1, length: 0), ")"))
                    }
                }
            }
            i += 1
        }
        return edits
    }

    // MARK: - 形参被重新声明

    private static func shadowedParameterEdits(_ masked: String) -> [(range: NSRange, text: String)] {
        var edits: [(range: NSRange, text: String)] = []
        let ns = masked as NSString
        let n = ns.length
        var i = 0
        while i < n {
            if ns.character(at: i) == 0x66 { // f
                let wordEnd = min(n, i + 8)
                let word = ns.substring(with: NSRange(location: i, length: wordEnd - i))
                if word.hasPrefix("function"),
                   let paramOpen = index(of: 0x28, in: masked, from: i + 8),
                   let paramClose = matchingBracket(masked, open: 0x28, close: 0x29, at: paramOpen),
                   let bodyOpen = index(of: 0x7B, in: masked, from: paramClose + 1),
                   let bodyClose = matchingBracket(masked, open: 0x7B, close: 0x7D, at: bodyOpen) {
                    let paramText = ns.substring(with: NSRange(location: paramOpen + 1, length: max(0, paramClose - paramOpen - 1)))
                    let params = Set(paramText
                        .split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" || $0 == "," })
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { $0.range(of: "^[A-Za-z_$][A-Za-z0-9_$]*$", options: .regularExpression) != nil })
                    if !params.isEmpty,
                       let re = try? NSRegularExpression(pattern: "\\b(let|const)(\\s+)([A-Za-z_$][A-Za-z0-9_$]*)") {
                        let bodyRange = NSRange(location: bodyOpen + 1, length: max(0, bodyClose - bodyOpen - 1))
                        for m in re.matches(in: masked, range: bodyRange) {
                            guard let nameRange = Range(m.range(at: 3), in: masked) else { continue }
                            let name = String(masked[nameRange])
                            guard params.contains(name) else { continue }
                            let space = (masked as NSString).substring(with: m.range(at: 2))
                            edits.append((NSRange(location: m.range.location, length: m.range.length),
                                          "var" + space + name))
                        }
                    }
                    i = bodyClose
                }
            }
            i += 1
        }
        return edits
    }

    // MARK: - 小工具

    private static func index(of code: UInt16, in text: String, from: Int) -> Int? {
        let ns = text as NSString
        var i = from
        while i < ns.length {
            if ns.character(at: i) == code { return i }
            i += 1
        }
        return nil
    }

    /// 从 open 处开始找配对的括号（基于遮罩后的文本，字符串/注释已排除）。
    private static func matchingBracket(_ text: String, open: UInt16, close: UInt16, at: Int) -> Int? {
        let ns = text as NSString
        var depth = 0
        var i = at
        while i < ns.length {
            let c = ns.character(at: i)
            if c == open { depth += 1 }
            if c == close {
                depth -= 1
                if depth == 0 { return i }
            }
            i += 1
        }
        return nil
    }
}
