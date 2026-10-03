//
//  JsNumberFormat.swift
//  LegadoBookSource
//
//  Step 5 收尾：JS number → 字符串，按 **ECMAScript Number::toString** 语义输出。
//
//  为什么需要它：
//  - legado 里 JS 调 `java.md5Encode(1e21)` 时，Rhino 的 NativeJavaMethod 对 String 参数走
//    NativeJavaObject.coerceTypeImpl（JSTYPE_NUMBER && type == STRING）→ ScriptRuntime.toString(value)
//    → Rhino 1.8.1 的 `org.mozilla.javascript.dtoa.DoubleFormatter.toString(double)`，源码注释原文：
//    "Convert a double to String as defined in the "Number::toString" operation in ECMAScript."
//  - 本移植 `java` 桥接从 JSContext 取出的是 NSNumber（只有 Double 值），所以 Swift 侧必须自己
//    复刻 ECMAScript Number::toString，才能与 Rhino 传进 Java String 参数的字符串逐字一致。
//  - 旧实现（`String(Int64(d))` 一类的「整数无 .0」手写规则）已删除：它只对常规整数/小数成立，
//    对 1e21（应为 "1e+21"）、1e-7（"1e-7"）、NaN/Infinity（"NaN"/"Infinity"）、-0（"0"）全错。
//
//  验证：golden `cases/js_number_args.json` 由真实 Rhino 1.8.1 跑出「字面量 → Rhino 实际传入
//  Java String 参数的字符串」，Swift 测试逐条比较（见 RhinoNumberArgGoldenTests）。
//
//  算法（ECMA-262 6.1.6.1.20 Number::toString）：
//    令 s、k、n 为满足 10^(k-1) ≤ s < 10^k、s × 10^(n-k) = x 的最小位数整数（s 为最短往返十进制数字），
//      - k ≤ n ≤ 21           → s 的 k 位数字 + (n−k) 个 '0'
//      - 0 < n ≤ 21           → s 的前 n 位 + '.' + 其余位
//      - −6 < n ≤ 0           → "0." + (−n) 个 '0' + s
//      - 其它                  → 指数形式：首位 [+ '.' + 其余位] + 'e' + ('+' | '-') + |n−1|
//
import Foundation

enum JsNumberFormat {

    /// 复刻 ECMAScript Number::toString（进制 10）。
    static func toString(_ value: Double) -> String {
        if value.isNaN { return "NaN" }
        if value == 0 { return "0" }                    // +0 与 −0 都是 "0"
        if value < 0 { return "-" + toString(-value) }  // 含 −Infinity
        if value.isInfinite { return "Infinity" }
        // 此处 value > 0 且有限
        let (digits, n) = shortestDigits(value)
        let k = digits.count
        if k <= n && n <= 21 {
            return digits + String(repeating: "0", count: n - k)
        }
        if 0 < n && n <= 21 {
            let split = digits.index(digits.startIndex, offsetBy: n)
            return String(digits[..<split]) + "." + String(digits[split...])
        }
        if -6 < n && n <= 0 {
            return "0." + String(repeating: "0", count: -n) + digits
        }
        let exponent = n - 1
        let mantissa = k == 1
            ? digits
            : String(digits.prefix(1)) + "." + String(digits.dropFirst())
        return mantissa + "e" + (exponent >= 0 ? "+" : "-") + String(abs(exponent))
    }

    /// 取「最短往返十进制数字」的位串 s（无前导/尾随零）与十进制位数 n
    /// （满足 value = 0.<digits> × 10^n，即小数点前的位数）。
    ///
    /// Swift 的 `String(Double)` 与 ECMAScript 一样输出「能唯一往返的最短数字」，
    /// 差别只在排版（如 Swift 输出 "1e-07"/"123.0"，JS 输出 "1e-7"/"123"），
    /// 所以这里只向它借数字串，排版全部由上面的规则重算。
    private static func shortestDigits(_ value: Double) -> (digits: String, n: Int) {
        var text = String(value)
        var exponent10 = 0
        if let eIndex = text.firstIndex(where: { $0 == "e" || $0 == "E" }) {
            let mantissa = String(text[..<eIndex])
            let expPart = String(text[text.index(after: eIndex)...])
            exponent10 = Int(expPart) ?? 0
            text = mantissa
        }
        var intPart = text
        var fracPart = ""
        if let dot = text.firstIndex(of: ".") {
            intPart = String(text[..<dot])
            fracPart = String(text[text.index(after: dot)...])
        }
        var digits = intPart + fracPart
        var pointPosition = intPart.count
        while digits.count > 1 && digits.first == "0" {
            digits.removeFirst()
            pointPosition -= 1
        }
        while digits.count > 1 && digits.last == "0" {
            digits.removeLast()
        }
        if digits.isEmpty { return ("0", 1) }
        return (digits, pointPosition + exponent10)
    }
}
