//
//  AnalyzeByRegex.swift
//  LegadoBookSource
//
//  对应 Kotlin: model/analyzeRule/AnalyzeByRegex.kt（59 行）
//
//  正则解析。Kotlin 用 java.util.regex.Pattern/Matcher；Swift 用 NSRegularExpression。
//
//  语义对齐（务必与 Kotlin 一致，不擅自改行为）：
//   - getElement：
//       · 首个规则若 find() 失败 -> 返回 nil。
//       · 最后一个规则：收集 group(0..groupCount)，Kotlin 用 `resM.group(i)!!`——
//         若某捕获组未参与匹配（group 为 null），Kotlin 抛 NPE。
//         本移植改为抛 RuleEngineError.regexGroupNotParticipated（不再崩溃）。
//       · 非最后规则：把所有 match 的整体串接后，递归下一个规则。
//   - getElements：
//       · find() 失败 -> 返回空数组。
//       · 最后规则：每个 match 收集 group(0..groupCount)，未参与的组取 ""（Kotlin `?: ""`）。
//       · 非最后规则：串接所有 match 后递归。
//   - 正则编译失败：Kotlin Pattern.compile 抛 PatternSyntaxException；
//     本移植改为抛 RuleEngineError.regexCompileFailed（不再崩溃）。
//

import Foundation

public enum AnalyzeByRegex {

    /// 对应 Kotlin: fun getElement(res, regs, index=0): List<String>?
    /// - Throws: RuleEngineError.regexCompileFailed / .regexGroupNotParticipated
    public static func getElement(
        _ res: String,
        _ regs: [String],
        index: Int = 0,
        diagnostics: RuleEngineDiagnostics? = nil
    ) throws -> [String]? {
        var vIndex = index
        let pattern = regs[vIndex]
        let regex: NSRegularExpression
        do {
            regex = try NSRegularExpression(pattern: pattern)
        } catch {
            diagnostics?.record(source: "AnalyzeByRegex.getElement", rule: pattern, message: "正则编译失败")
            throw RuleEngineError.regexCompileFailed(pattern: pattern)
        }

        let nsRes = res as NSString
        let matches = regex.matches(in: res, range: NSRange(location: 0, length: nsRes.length))
        // 对应 Kotlin: if (!resM.find()) return null
        guard let first = matches.first else {
            return nil
        }

        // 判断索引的规则是最后一个规则
        if vIndex + 1 == regs.count {
            // 新建容器
            var info: [String] = []
            for groupIndex in 0...(first.numberOfRanges - 1) {
                let r = first.range(at: groupIndex)
                if r.location == NSNotFound {
                    // Kotlin `resM.group(i)!!` 未参与匹配的组会抛 NPE；此处改为抛 RuleEngineError。
                    diagnostics?.record(source: "AnalyzeByRegex.getElement", rule: pattern,
                                        message: "捕获组 \(groupIndex) 未参与匹配")
                    throw RuleEngineError.regexGroupNotParticipated(groupIndex: groupIndex, pattern: pattern)
                }
                info.append(nsRes.substring(with: r))
            }
            return info
        } else {
            // 把所有 match 的整体（group()）串接
            var result = ""
            for m in matches {
                result += nsRes.substring(with: m.range)
            }
            vIndex += 1
            return try getElement(result, regs, index: vIndex, diagnostics: diagnostics)
        }
    }

    /// 对应 Kotlin: fun getElements(res, regs, index=0): List<List<String>>
    /// - Throws: RuleEngineError.regexCompileFailed（getElements 里 Kotlin 不处理组缺失，取 ""，故不抛组错误）
    public static func getElements(
        _ res: String,
        _ regs: [String],
        index: Int = 0,
        diagnostics: RuleEngineDiagnostics? = nil
    ) throws -> [[String]] {
        var vIndex = index
        let pattern = regs[vIndex]
        let regex: NSRegularExpression
        do {
            regex = try NSRegularExpression(pattern: pattern)
        } catch {
            diagnostics?.record(source: "AnalyzeByRegex.getElements", rule: pattern, message: "正则编译失败")
            throw RuleEngineError.regexCompileFailed(pattern: pattern)
        }

        let nsRes = res as NSString
        let matches = regex.matches(in: res, range: NSRange(location: 0, length: nsRes.length))
        // 对应 Kotlin: if (!resM.find()) return arrayListOf()
        if matches.isEmpty {
            return []
        }

        // 判断索引的规则是最后一个规则
        if vIndex + 1 == regs.count {
            // 创建书息缓存数组
            var books: [[String]] = []
            // 提取列表
            for m in matches {
                // 新建容器
                var info: [String] = []
                for groupIndex in 0...(m.numberOfRanges - 1) {
                    let r = m.range(at: groupIndex)
                    // Kotlin: resM.group(groupIndex) ?: ""
                    if r.location == NSNotFound {
                        info.append("")
                    } else {
                        info.append(nsRes.substring(with: r))
                    }
                }
                books.append(info)
            }
            return books
        } else {
            var result = ""
            for m in matches {
                result += nsRes.substring(with: m.range)
            }
            vIndex += 1
            return try getElements(result, regs, index: vIndex, diagnostics: diagnostics)
        }
    }
}
