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
    /// Java/Kotlin replacement -> ICU 模板。
    static func javaToICU(_ replacement: String) -> String {
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
                // $ 后跟数字 -> 组引用，保留；否则 ICU 要求字面 $ 转义
                if i + 1 < chars.count, chars[i + 1].isNumber {
                    out.append(c)
                    i += 1
                    continue
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
