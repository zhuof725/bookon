import Foundation

/// Rhino（原版 Legado 的 JS 引擎）与 JavaScriptCore 的语法差异归一化。
///
/// 原版用 Rhino，很多书源的脚本依赖 Rhino 才有的宽松行为，直接丢给 JavaScriptCore 会报
/// SyntaxError（校验日志里真实出现过）：
/// 1. `let result = ...` / `const result = ...`
///    Rhino 把 result 当作「可变的规则全局变量」，JSC 里 `let` 是块级词法声明：
///    - 声明之前读 result 会命中 TDZ 报 ReferenceError；
///    - 声明之后的赋值只改块级变量，引擎回读不到。
///    → 统一改写成 `var result`。
/// 2. 箭头函数的**解构唯一参数**：`[title, Id] => {...}`
///    Rhino 接受，JSC 要求写成 `([title, Id]) => {...}`，
///    否则报 “Unexpected token '=>'. Expected ')' to end an argument list.”
///    → 给解构参数补上括号。
/// 3. 函数体顶层用 let/const 重新声明形参：Rhino 接受，JSC 是早期 SyntaxError。
///    → 把这种声明改写成 var。
///
/// 改写只针对「可执行代码」：字符串、模板字符串与注释里的同形文本不会被碰到
/// （先把它们遮成空格，再在遮罩上匹配，最后按位置回写原文）。
enum RuleScriptCompat {

    static func normalize(_ script: String) -> String {
        guard !script.isEmpty else { return script }
        let masked = maskLiterals(script)
        let ns = masked as NSString
        var edits: [(range: NSRange, text: String)] = []

        // 1) let/const result -> var result
        if let re = try? NSRegularExpression(pattern: "\\b(let|const)(\\s+)result\\b") {
            for m in re.matches(in: masked, range: NSRange(location: 0, length: ns.length)) {
                let kw = m.range(at: 1)
                // 关键字之后的部分（空白 + result）原样保留
                let tailRange = NSRange(location: kw.upperBound, length: m.range.upperBound - kw.upperBound)
                let tail = ns.substring(with: tailRange)
                edits.append((m.range, "var" + tail))
            }
        }

        // 2) 解构箭头参数补括号
        edits.append(contentsOf: destructuredArrowParamEdits(masked))

        // 3) 形参被 let/const 重新声明 -> var
        edits.append(contentsOf: shadowedParameterEdits(masked))

        guard !edits.isEmpty else { return script }
        let sorted = edits.sorted { $0.range.location > $1.range.location }
        let mutable = NSMutableString(string: script)
        for edit in sorted {
            guard NSMaxRange(edit.range) <= mutable.length else { continue }
            mutable.replaceCharacters(in: edit.range, with: edit.text)
        }
        return mutable as String
    }

    // MARK: - 词法遮罩

    /// 字符串/模板字符串/注释替换为空格（换行保留）。
    private static func maskLiterals(_ script: String) -> String {
        let ns = script as NSString
        let n = ns.length
        var buf = [unichar](repeating: 0, count: n)
        for i in 0..<n { buf[i] = ns.character(at: i) }
        func blank(_ from: Int, _ to: Int) {
            guard from <= to else { return }
            var k = max(0, from)
            let end = min(to, n - 1)
            while k <= end {
                if buf[k] != 10 { buf[k] = 32 }
                k += 1
            }
        }
        var i = 0
        while i < n {
            let c = buf[i]
            if c == 47, i + 1 < n, buf[i + 1] == 47 {          // //
                var j = i
                while j < n, buf[j] != 10 { j += 1 }
                blank(i, j - 1)
                i = j
                continue
            }
            if c == 47, i + 1 < n, buf[i + 1] == 42 {          // /*
                var j = i + 2
                while j + 1 < n, !(buf[j] == 42 && buf[j + 1] == 47) { j += 1 }
                blank(i, min(n - 1, j + 1))
                i = min(n - 1, j + 1) + 1
                continue
            }
            if c == 34 || c == 39 || c == 96 {                 // " ' `
                var j = i + 1
                while j < n {
                    if buf[j] == 92 { j += 2; continue }       // 反斜杠转义
                    if buf[j] == c { break }
                    j += 1
                }
                blank(i, min(n - 1, j))
                i = min(n - 1, j) + 1
                continue
            }
            i += 1
        }
        return String(decoding: buf, as: UTF16.self)
    }

    // MARK: - 解构箭头参数

    private static func destructuredArrowParamEdits(_ masked: String) -> [(range: NSRange, text: String)] {
        let ns = masked as NSString
        let n = ns.length
        var edits: [(range: NSRange, text: String)] = []
        var i = 0
        while i < n {
            if ns.character(at: i) == 91 {                     // [
                var p = i - 1
                while p >= 0, isSpace(ns.character(at: p)) { p -= 1 }
                let prevOK = p >= 0 && (ns.character(at: p) == 40 || ns.character(at: p) == 44) // ( or ,
                if prevOK, let close = matching(masked, open: 91, close: 93, at: i) {
                    var q = close + 1
                    while q < n, isSpace(ns.character(at: q)) { q += 1 }
                    if q + 1 < n, ns.character(at: q) == 61, ns.character(at: q + 1) == 62 {   // =>
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
        let ns = masked as NSString
        let n = ns.length
        var edits: [(range: NSRange, text: String)] = []
        var i = 0
        while i < n {
            if ns.character(at: i) == 102, i + 8 <= n, ns.substring(with: NSRange(location: i, length: 8)) == "function",
               let paramOpen = firstIndex(of: 40, in: masked, from: i + 8),
               let paramClose = matching(masked, open: 40, close: 41, at: paramOpen),
               let bodyOpen = firstIndex(of: 123, in: masked, from: paramClose + 1),
               let bodyClose = matching(masked, open: 123, close: 125, at: bodyOpen) {
                let paramText = ns.substring(with: NSRange(location: paramOpen + 1, length: max(0, paramClose - paramOpen - 1)))
                let params = Set(paramText
                    .split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" || $0 == "\r" || $0 == "," })
                    .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { isIdentifier($0) })
                if !params.isEmpty,
                   let re = try? NSRegularExpression(pattern: "\\b(let|const)(\\s+)([A-Za-z_$][A-Za-z0-9_$]*)") {
                    let bodyRange = NSRange(location: bodyOpen + 1, length: max(0, bodyClose - bodyOpen - 1))
                    if bodyRange.length > 0 {
                        for m in re.matches(in: masked, range: bodyRange) {
                            let nameRange = m.range(at: 3)
                            let name = ns.substring(with: nameRange)
                            guard params.contains(name) else { continue }
                            let space = ns.substring(with: m.range(at: 2))
                            edits.append((NSRange(location: m.range.location, length: m.range.length), "var" + space + name))
                        }
                    }
                }
                i = bodyClose
            }
            i += 1
        }
        return edits
    }

    // MARK: - 小工具

    private static func isSpace(_ c: unichar) -> Bool { c == 32 || c == 10 || c == 9 || c == 13 }

    private static func isIdentifier(_ s: String) -> Bool {
        s.range(of: "^[A-Za-z_$][A-Za-z0-9_$]*$", options: .regularExpression) != nil
    }

    private static func firstIndex(of code: unichar, in text: String, from: Int) -> Int? {
        let ns = text as NSString
        var i = max(0, from)
        while i < ns.length {
            if ns.character(at: i) == code { return i }
            i += 1
        }
        return nil
    }

    private static func matching(_ text: String, open: unichar, close: unichar, at: Int) -> Int? {
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
