//
//  RegexTemplate.swift
//  LegadoBookSource
//
//  把 Java/Kotlin 正则替换模板转换为 NSRegularExpression(ICU) 模板。
//
//  差异要点：
//   - Java/Kotlin: 组引用 $0..$9（以及 ${name}），字面 $ 用 \$，字面 \ 用 \\。
//   - ICU(NSRegularExpression): 组引用 $0..$9（${name} 不支持，用 $n），字面 $ 用 \$，
//     字面 \ 需在模板里写 \\。NSRegularExpression 还会把模板里的 \ 当转义引入。
//  本转换：
//   - Java "\$" (字面$) -> ICU "\$"
//   - Java "\\" (字面\) -> ICU "\\\\"（两个反斜杠在 ICU 模板里表示一个字面反斜杠）
//   - "$1".."$9"、"$0" 组引用原样保留
//   - 其它反斜杠转义（\n 等）在 Kotlin replacement 里本就是字面，这里保留为字面。
//
//  ⚠️ Java 正则 vs ICU 已知差异（匹配侧，非模板侧）写进 README：占有量词 ++/*+/?+、
//  \h/\v、\Z、命名组 (?<name>) 语法、内嵌标志 (?i) 作用域等。最终由 C 部分 golden 验证。
//

import Foundation

enum RegexTemplate {

    /// 从正则 pattern 里提取「命名捕获组 -> 组序号」映射。
    /// 组序号 = 捕获组左括号出现顺序（从 1 开始），命名组 `(?<name>`/`(?'name'` 与普通捕获组共享编号。
    /// 非捕获组 `(?:...)`、断言 `(?=`/`(?!`/`(?<=`/`(?<!`、内嵌标志 `(?i)` 等不计数。
    /// 转义的 `\(` 不计数。字符类 `[...]` 内的 `(` 不计数。
    static func namedGroupIndices(in pattern: String) -> [String: Int] {
        var result: [String: Int] = [:]
        let chars = Array(pattern)
        var i = 0
        var groupIndex = 0
        var inClass = false
        while i < chars.count {
            let c = chars[i]
            if c == "\\" {
                i += 2  // 跳过转义字符
                continue
            }
            if inClass {
                if c == "]" { inClass = false }
                i += 1
                continue
            }
            if c == "[" {
                inClass = true
                i += 1
                continue
            }
            if c == "(" {
                if i + 1 < chars.count && chars[i + 1] == "?" {
                    // (?... ：可能是命名组 (?<name>) / (?'name') / (?P<name>)，或非捕获/断言/标志
                    var j = i + 2
                    // (?<...  但要排除断言 (?<= (?<!
                    if j < chars.count && chars[j] == "<" && j + 1 < chars.count
                        && chars[j + 1] != "=" && chars[j + 1] != "!" {
                        // 命名组 (?<name>
                        groupIndex += 1
                        var name = ""
                        var k = j + 1
                        while k < chars.count && chars[k] != ">" { name.append(chars[k]); k += 1 }
                        if !name.isEmpty { result[name] = groupIndex }
                    } else if j < chars.count && chars[j] == "'" {
                        // 命名组 (?'name'
                        groupIndex += 1
                        var name = ""
                        var k = j + 1
                        while k < chars.count && chars[k] != "'" { name.append(chars[k]); k += 1 }
                        if !name.isEmpty { result[name] = groupIndex }
                    } else if j + 1 < chars.count && chars[j] == "P" && chars[j + 1] == "<" {
                        // 命名组 (?P<name>
                        groupIndex += 1
                        var name = ""
                        var k = j + 2
                        while k < chars.count && chars[k] != ">" { name.append(chars[k]); k += 1 }
                        if !name.isEmpty { result[name] = groupIndex }
                    }
                    // 其它 (?...) 不计数
                } else {
                    // 普通捕获组
                    groupIndex += 1
                }
            }
            i += 1
        }
        return result
    }

    /// Java/Kotlin replacement -> ICU 模板（含命名组引用 ${name} / $<name> -> $index 转换）。
    /// 需要 pattern 才能解析命名组序号；无 pattern 时命名组引用无法转换（保留原样，由上层登记差异）。
    static func javaToICU(_ replacement: String, pattern: String? = nil) -> String {
        let named = pattern.map { namedGroupIndices(in: $0) } ?? [:]
        return convert(replacement, named: named)
    }

    /// 内部转换实现。named 为命名组名 -> 序号映射。
    private static func convert(_ replacement: String, named: [String: Int]) -> String {
        var out = ""
        let chars = Array(replacement)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "\\" {
                if i + 1 < chars.count {
                    let next = chars[i + 1]
                    if next == "$" {
                        out += "\\$"      // 字面 $
                        i += 2
                        continue
                    } else if next == "\\" {
                        out += "\\\\"     // 字面 \
                        i += 2
                        continue
                    } else {
                        // 其它 \x：Kotlin 中 \x 多为字面；ICU 把未知转义当字面处理，保留字面字符
                        out.append(next)
                        i += 2
                        continue
                    }
                } else {
                    // 末尾单个 \：当字面
                    out += "\\\\"
                    i += 1
                    continue
                }
            } else if c == "$" {
                // $ 后跟数字 -> 组引用，保留；
                // ${name} / $<name> -> 命名组：查 named 映射转成 $index（ICU 不支持命名引用）。
                if i + 1 < chars.count, chars[i + 1].isNumber {
                    out.append(c)
                    i += 1
                    continue
                } else if i + 1 < chars.count, chars[i + 1] == "{" || chars[i + 1] == "<" {
                    let close: Character = chars[i + 1] == "{" ? "}" : ">"
                    var k = i + 2
                    var name = ""
                    while k < chars.count && chars[k] != close { name.append(chars[k]); k += 1 }
                    if k < chars.count, let idx = named[name] {
                        // 命中命名组 -> $idx
                        out += "$\(idx)"
                        i = k + 1
                        continue
                    } else {
                        // 无法解析的命名引用：保留字面 $（转义），其余字符按原样续处理。
                        out += "\\$"
                        i += 1
                        continue
                    }
                } else {
                    out += "\\$"
                    i += 1
                    continue
                }
            } else {
                out.append(c)
                i += 1
            }
        }
        return out
    }
}
