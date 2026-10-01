//
//  HtmlUnescape.swift
//  LegadoBookSource
//
//  对应 Kotlin AnalyzeRule.getString 里用的 commons-text 1.13.1
//  StringEscapeUtils.unescapeHtml4(String)。Swift 自实现。
//
//  覆盖：
//   - HTML4 命名实体表（252 条，源自 CPython html.entities.name2codepoint，即 HTML4 命名实体集，
//     与 commons-text 的 EntityArrays.HTML40 并集一致；基础 + ISO-8859-1 + 符号/希腊字母）。
//   - 十进制数字实体 `&#123;`、十六进制 `&#xAB;` / `&#XAB;`。
//   - commons-text 的「无分号实体不解析」语义：commons-text 的 LookupTranslator 依赖
//     EntityArrays 里的键都带分号（如 "&amp;"），因此**无分号实体不会被还原**（如 "&amp" 原样保留）。
//     数字实体 NumericEntityUnescaper 默认同样**要求分号**（semiColonRequired），无分号时原样保留。
//
//  ⚠️ 与 commons-text 的最终对齐由 C 部分 golden（至少 40 例）验证；本步骤写合成单测自测。
//  已知可能差异见 README「与 Kotlin 已知差异」表（如超出 Unicode 范围的数字实体处理）。
//

import Foundation

enum HtmlUnescape {

    /// 对应 commons-text StringEscapeUtils.unescapeHtml4。
    static func unescapeHtml4(_ input: String) -> String {
        if input.firstIndex(of: "&") == nil { return input }
        let chars = Array(input)
        var out = String()
        out.reserveCapacity(input.count)
        var i = 0
        let n = chars.count
        while i < n {
            let c = chars[i]
            if c != "&" {
                out.append(c)
                i += 1
                continue
            }
            // 尝试匹配实体，从 & 之后开始找 ';'
            // commons-text 的 LookupTranslator：实体键带分号；NumericEntityUnescaper 要求分号。
            // 我们先定位分号（最多向后看一定长度）。
            var semi = -1
            var j = i + 1
            let maxLook = min(n, i + 1 + 32) // 实体名有限长度
            while j < maxLook {
                if chars[j] == ";" { semi = j; break }
                // 实体名只含字母数字和 #x；遇到其它字符即放弃
                let ch = chars[j]
                if !(ch.isLetter || ch.isNumber || ch == "#") { break }
                j += 1
            }
            if semi == -1 {
                out.append(c)
                i += 1
                continue
            }
            let body = String(chars[(i + 1)..<semi]) // 不含 & 和 ;
            if body.hasPrefix("#") {
                // 数字实体
                if let scalar = decodeNumeric(body) {
                    out.append(scalar)
                    i = semi + 1
                    continue
                } else {
                    out.append(c)
                    i += 1
                    continue
                }
            } else if let v = HtmlEntities.table[body] {
                out.append(v)
                i = semi + 1
                continue
            } else {
                // 未知命名实体：原样保留 &（commons-text 不还原未知实体）
                out.append(c)
                i += 1
                continue
            }
        }
        return out
    }

    /// 解析 "#123" / "#xAB" / "#XAB" -> 字符串（可能是 surrogate pair）。无效返回 nil。
    private static func decodeNumeric(_ body: String) -> String? {
        var hex = false
        var numStr = String(body.dropFirst()) // 去掉 '#'
        if numStr.hasPrefix("x") || numStr.hasPrefix("X") {
            hex = true
            numStr = String(numStr.dropFirst())
        }
        if numStr.isEmpty { return nil }
        guard let code = UInt32(numStr, radix: hex ? 16 : 10) else { return nil }
        guard let scalar = Unicode.Scalar(code) else { return nil }
        return String(Character(scalar))
    }
}
