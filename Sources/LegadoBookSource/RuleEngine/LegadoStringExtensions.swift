//
//  LegadoStringExtensions.swift
//  LegadoBookSource
//
//  对应 Kotlin: utils/StringExtensions.kt 中被 AnalyzeRule 使用的子集：
//   - isJson / isJsonObject / isJsonArray（trim 后 {…}/[…] 判定）
//   - isAbsUrl（http://、https:// 前缀，大小写不敏感）
//   - isDataUrl（^data:.*?;base64,(.*) 正则）
//   - splitNotBlank（按分隔符切分，trim + 去空）
//
//  行为与 Kotlin 对齐（见各函数注释）。本文件只做 AnalyzeRule 依赖的字符串工具，
//  其余 StringExtensions 方法不在本步骤范围。
//

import Foundation

enum LegadoStringUtils {

    /// 对应 Kotlin: String?.isJson() —— trim 后 {…} 或 […] 返回 true。
    static func isJson(_ s: String?) -> Bool {
        guard let s = s else { return false }
        let str = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if str.hasPrefix("{") && str.hasSuffix("}") { return true }
        if str.hasPrefix("[") && str.hasSuffix("]") { return true }
        return false
    }

    static func isJsonObject(_ s: String?) -> Bool {
        guard let s = s else { return false }
        let str = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return str.hasPrefix("{") && str.hasSuffix("}")
    }

    static func isJsonArray(_ s: String?) -> Bool {
        guard let s = s else { return false }
        let str = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return str.hasPrefix("[") && str.hasSuffix("]")
    }

    /// 对应 Kotlin: String?.isAbsUrl() —— http:// 或 https:// 前缀（大小写不敏感）。
    static func isAbsUrl(_ s: String?) -> Bool {
        guard let s = s else { return false }
        let lower = s.lowercased()
        return lower.hasPrefix("http://") || lower.hasPrefix("https://")
    }

    /// 对应 Kotlin AppPattern.dataUriRegex: `^data:.*?;base64,(.*)`，用 matches（整串匹配）。
    static func isDataUrl(_ s: String?) -> Bool {
        guard let s = s else { return false }
        // Kotlin Regex.matches 要求整串匹配；用 anchored + 末尾 $。
        // ^data:.*?;base64,(.*)  —— .* 不跨行，Swift NSRegularExpression 默认 . 不匹配换行，和 Kotlin 一致。
        guard let re = try? NSRegularExpression(pattern: "^data:.*?;base64,(.*)$") else { return false }
        let ns = s as NSString
        return re.firstMatch(in: s, range: NSRange(location: 0, length: ns.length))?.range.length == ns.length
    }

    /// 对应 Kotlin: String.splitNotBlank(vararg delimiter, limit=0)
    ///   this.split(*delimiter, limit).map { trim }.filterNot { isBlank }
    /// Kotlin split 不含分隔符本身；limit=0 表示不限制。
    static func splitNotBlank(_ s: String, _ delimiters: [String], limit: Int = 0) -> [String] {
        let parts = kotlinSplit(s, delimiters, limit: limit)
        return parts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// 近似 Kotlin String.split(vararg delimiters, limit): 按多个字面量分隔符切分。
    /// limit>0 时最多切出 limit 段（最后一段保留剩余，含分隔符），limit<=0 不限制。
    private static func kotlinSplit(_ s: String, _ delimiters: [String], limit: Int) -> [String] {
        let dels = delimiters.filter { !$0.isEmpty }
        if dels.isEmpty { return [s] }
        var result: [String] = []
        var current = ""
        var i = s.startIndex
        while i < s.endIndex {
            if limit > 0 && result.count == limit - 1 {
                current += String(s[i...])
                break
            }
            var matched = false
            for d in dels {
                if let r = s.range(of: d, range: i..<s.endIndex), r.lowerBound == i {
                    result.append(current)
                    current = ""
                    i = r.upperBound
                    matched = true
                    break
                }
            }
            if !matched {
                current.append(s[i])
                i = s.index(after: i)
            }
        }
        result.append(current)
        return result
    }
}
