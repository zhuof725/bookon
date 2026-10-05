//
//  StringUtils.swift
//  LegadoBookSource
//
//  对应 Kotlin: utils/StringUtils.kt 中**被流程层调用**的子集（第 7 步 A 段）：
//   - wordCountFormat(words: Int): String
//   - wordCountFormat(wc: String?): String      ← BookList.getSearchItem / BookInfo 调用
//   - isNumeric(str) / isContainNumber(company)
//   - chineseNumToInt(chNum) / stringToInt(str)
//   - fullToHalf(input) / halfToFull(input)     ← stringToInt 依赖
//   - trim(s) / repeat(str, n)
//
//  ⚠️ wordCountFormat 的 Java DecimalFormat("#.#") 与 Kotlin `words * 1.0f / 10000f.toDouble()`
//  的精度语义在 README「手工移植说明」里登记；Swift 侧对齐 Java 的 DecimalFormat（HALF_EVEN 舍入、
//  最多 1 位小数、无小数则不输出小数点）。
//

import Foundation

/// 对应 Kotlin: object StringUtils（仅流程层用到的子集）
public enum LegadoStringUtils2 {

    // MARK: - 中文数字表（对应 Kotlin chnMap）

    /// 对应 Kotlin: private val chnMap: HashMap<Char, Int>
    static let chnMap: [Character: Int] = {
        var map: [Character: Int] = [:]
        let cn1 = Array("零一二三四五六七八九十")
        for i in 0...10 { map[cn1[i]] = i }
        let cn2 = Array("〇壹贰叁肆伍陆柒捌玖拾")
        for i in 0...10 { map[cn2[i]] = i }
        map["两"] = 2
        map["百"] = 100
        map["佰"] = 100
        map["千"] = 1000
        map["仟"] = 1000
        map["万"] = 10000
        map["亿"] = 100_000_000
        return map
    }()

    // MARK: - wordCountFormat

    /// 对应 Kotlin: fun wordCountFormat(words: Int): String
    ///
    /// ```kotlin
    /// var wordsS = ""
    /// if (words > 0) {
    ///     if (words > 10000) {
    ///         val df = wordCountFormatter              // DecimalFormat("#.#")
    ///         wordsS = df.format(words * 1.0f / 10000f.toDouble()) + "万字"
    ///     } else {
    ///         wordsS = words.toString() + "字"
    ///     }
    /// }
    /// return wordsS
    /// ```
    public static func wordCountFormat(_ words: Int) -> String {
        if words > 0 {
            if words > 10000 {
                // Kotlin: words * 1.0f / 10000f.toDouble()
                let fWords: Float = Float(words)
                let scaled: Float = fWords * 1.0
                let value: Double = Double(scaled) / Double(Float(10000))
                return decimalFormatSharp1(value) + "万字"
            } else {
                return String(words) + "字"
            }
        }
        return ""
    }

    /// 对应 Kotlin: fun wordCountFormat(wc: String?): String
    public static func wordCountFormat(_ wc: String?) -> String {
        guard let wc = wc else { return "" }
        if isNumeric(wc) {
            // Kotlin: wc.toInt()  —— 溢出/非 Int 在 Swift 侧以 DecimalFormat 路径的 try? 兜底为空串
            guard let words = Int(wc) else { return "" }
            if words > 0 {
                if words > 10000 {
                    // Kotlin: words * 1.0f / 10000f.toDouble()
                    let fWords: Float = Float(words)
                    let scaled: Float = fWords * 1.0
                    let value: Double = Double(scaled) / Double(Float(10000))
                    return decimalFormatSharp1(value) + "万字"
                } else {
                    return String(words) + "字"
                }
            }
            return ""
        } else {
            return wc
        }
    }

    /// 对齐 Java `new DecimalFormat("#.#")`：默认 HALF_EVEN 舍入，最多 1 位小数，整数不输出小数点。
    /// Java 默认 Locale 的 DecimalFormat 使用 '.' 作为小数点（zh_CN/en_US 均如此）。
    static func decimalFormatSharp1(_ value: Double) -> String {
        // Java 的 DecimalFormat 对非有限值不适用；此处按常规数值路径处理。
        if value.isNaN || value.isInfinite { return "" }
        // 先用 Java 的 HALF_EVEN 语义保留 1 位，再按 "#.#" 去掉多余的 ".0"。
        let rounded = javaHalfEvenRound(value, digits: 1)
        let absRounded = abs(rounded)
        let whole = absRounded.rounded(.towardZero)
        let frac = absRounded - whole
        let sign = rounded < 0 && absRounded != 0 ? "-" : ""
        if frac < 1e-9 {
            return sign + String(Int(whole))
        }
        // 1 位小数：乘 10 取整（已 HALF_EVEN 到 1 位，必为整十）
        let tenths = Int((absRounded * 10).rounded())
        return sign + "\(tenths / 10).\(tenths % 10)"
    }

    /// 以 Java BigDecimal HALF_EVEN 语义把 value 保留 digits 位小数。
    static func javaHalfEvenRound(_ value: Double, digits: Int) -> Double {
        let factor = pow(10.0, Double(digits))
        let scaled = value * factor
        let floorVal = scaled.rounded(.down)
        let diff = scaled - floorVal
        var result: Double
        if abs(diff - 0.5) < 1e-9 {
            // 恰好 .5：向偶数取整
            result = (Int(floorVal) % 2 == 0) ? floorVal : floorVal + 1
        } else {
            result = scaled.rounded()   // 远离 .5 时为普通四舍五入
        }
        return result / factor
    }

    // MARK: - 数值判定

    /// 对应 Kotlin: Pattern.compile("[0-9]+") + m.find()
    public static func isContainNumber(_ company: String) -> Bool {
        return RegexCacheLike.firstMatch("[0-9]+", company) != nil
    }

    /// 对应 Kotlin: Pattern.compile("-?[0-9]+") + m.matches()
    public static func isNumeric(_ str: String) -> Bool {
        return RegexCacheLike.fullMatch("-?[0-9]+", str)
    }

    // MARK: - 中文数字

    /// 对应 Kotlin: fun chineseNumToInt(chNum: String): Int
    public static func chineseNumToInt(_ chNum: String) -> Int {
        var result = 0
        var tmp = 0
        var billion = 0
        var cn = Array(chNum)

        // "一零二五" 形式
        if cn.count > 1 && RegexCacheLike.fullMatch("^[〇零一二三四五六七八九壹贰叁肆伍陆柒捌玖]$", chNum) {
            // Kotlin: 逐字 48 + ChnMap[cn[i]]!!，再 Integer.parseInt
            var digits = ""
            for ch in cn {
                guard let v = chnMap[ch] else { return -1 }
                digits.append(Character(UnicodeScalar(48 + v)!))
            }
            return Int(digits) ?? -1
        }

        // "一千零二十五", "一千二" 形式
        for i in 0..<cn.count {
            guard let tmpNum = chnMap[cn[i]] else { return -1 }
            if tmpNum == 100_000_000 {
                result += tmp
                result *= tmpNum
                billion = billion * 100_000_000 + result
                result = 0
                tmp = 0
            } else if tmpNum == 10000 {
                result += tmp
                result *= tmpNum
                tmp = 0
            } else if tmpNum >= 10 {
                if tmp == 0 { tmp = 1 }
                result += tmpNum * tmp
                tmp = 0
            } else {
                if i >= 2 && i == cn.count - 1 && (chnMap[cn[i - 1]] ?? 0) > 10 {
                    tmp = tmpNum * (chnMap[cn[i - 1]] ?? 0) / 10
                } else {
                    tmp = tmp * 10 + tmpNum
                }
            }
        }
        result += tmp + billion
        return result
    }

    /// 对应 Kotlin: fun stringToInt(str: String?): Int
    /// Kotlin 用 runCatching { Integer.parseInt } getOrElse { chineseNumToInt }，异常不抛出。
    public static func stringToInt(_ str: String?) -> Int {
        guard let str = str else { return -1 }
        let num = replaceAllRegex(fullToHalf(str), "\\s+", "")
        if let v = Int(num) { return v }
        return chineseNumToInt(num)
    }

    // MARK: - 全角/半角

    /// 对应 Kotlin: fun halfToFull(input: String): String
    public static func halfToFull(_ input: String) -> String {
        var out = ""
        for scalar in input.unicodeScalars {
            let code = Int(scalar.value)
            if code == 32 {
                out.unicodeScalars.append(UnicodeScalar(12288)!)
                continue
            }
            if code >= 33 && code <= 126 {
                out.unicodeScalars.append(UnicodeScalar(UInt32(code + 65248))!)
            } else {
                out.unicodeScalars.append(scalar)
            }
        }
        return out
    }

    /// 对应 Kotlin: fun fullToHalf(input: String): String
    public static func fullToHalf(_ input: String) -> String {
        var out = ""
        for scalar in input.unicodeScalars {
            let code = Int(scalar.value)
            if code == 12288 {
                out.unicodeScalars.append(UnicodeScalar(32)!)
                continue
            }
            if code >= 65281 && code <= 65374 {
                out.unicodeScalars.append(UnicodeScalar(UInt32(code - 65248))!)
            } else {
                out.unicodeScalars.append(scalar)
            }
        }
        return out
    }

    // MARK: - trim / repeat

    /// 对应 Kotlin: fun trim(s: String): String
    /// 移除首尾空字符（利用 ASCII 值判断，包括全角空格 U+3000）。
    public static func trim(_ s: String) -> String {
        if s.isEmpty { return "" }
        var chars = Array(s)
        let len = chars.count
        var start = 0
        var end = len - 1
        while start < end && (chars[start].unicodeScalars.first!.value <= 0x20 || chars[start] == "　") {
            start += 1
        }
        while start < end && (chars[end].unicodeScalars.first!.value <= 0x20 || chars[end] == "　") {
            end -= 1
        }
        end += 1
        if start > 0 || end < len {
            return String(chars[start..<end])
        }
        return s
    }

    /// 对应 Kotlin: fun repeat(str: String, n: Int): String
    public static func repeatStr(_ str: String, _ n: Int) -> String {
        var sb = ""
        if n > 0 {
            for _ in 0..<n { sb += str }
        }
        return sb
    }

    // MARK: - 内部

    /// 全局正则替换（字面量模板，编译失败返回原串）。
    static func replaceAllRegex(_ s: String, _ pattern: String, _ replacement: String) -> String {
        let cache = NSRegularExpressionCache(pattern: pattern)
        let ns = s as NSString
        return cache.stringByReplacingMatches(
            in: s, range: NSRange(location: 0, length: ns.length),
            withTemplate: NSRegularExpression.escapedTemplate(for: replacement))
    }
}

/// 极简正则判定缓存（find / matches 语义）。编译失败一律返回「不匹配」，绝不崩溃。
enum RegexCacheLike {
    private static var cache: [String: NSRegularExpression] = [:]
    private static let lock = NSLock()

    private static func get(_ pattern: String) -> NSRegularExpression? {
        lock.lock()
        defer { lock.unlock() }
        if let r = cache[pattern] { return r }
        guard let r = try? NSRegularExpression(pattern: pattern) else { return nil }
        cache[pattern] = r
        return r
    }

    /// 对应 java Matcher.find()：任意位置匹配。
    static func firstMatch(_ pattern: String, _ s: String) -> String? {
        guard let r = get(pattern) else { return nil }
        let ns = s as NSString
        guard let m = r.firstMatch(in: s, options: [], range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        return ns.substring(with: m.range)
    }

    /// 对应 java Matcher.matches()：整串匹配。
    static func fullMatch(_ pattern: String, _ s: String) -> Bool {
        guard let r = get(pattern) else { return false }
        let ns = s as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let m = r.firstMatch(in: s, options: [], range: range) else { return false }
        return m.range.location == 0 && m.range.length == ns.length
    }
}
