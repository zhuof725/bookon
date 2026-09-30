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
//         若某捕获组未参与匹配（group 为 null），Kotlin 抛 NPE（会崩）。
//         Swift 无法用可选签名表达"抛"，为忠实复刻该"致命"语义，遇到未参与的捕获组时
//         触发 fatalError（等价 Kotlin 未捕获的 NPE 会终止流程）。若提供了诊断收集器，
//         先记录再触发。⚠️ 这是按 Kotlin 原行为复刻，非本移植新增行为。
//       · 非最后规则：把所有 match 的整体串接后，递归下一个规则。
//   - getElements：
//       · find() 失败 -> 返回空数组。
//       · 最后规则：每个 match 收集 group(0..groupCount)，未参与的组取 ""（Kotlin `?: ""`）。
//       · 非最后规则：串接所有 match 后递归。
//

import Foundation

public enum AnalyzeByRegex {

    /// 对应 Kotlin: fun getElement(res, regs, index=0): List<String>?
    public static func getElement(
        _ res: String,
        _ regs: [String],
        index: Int = 0,
        diagnostics: RuleEngineDiagnostics? = nil
    ) -> [String]? {
        var vIndex = index
        let pattern = regs[vIndex]
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            // Kotlin: Pattern.compile 抛 PatternSyntaxException（未捕获会崩）。
            // 此处按"致命"处理并记录诊断，保持与 Kotlin 一致的失败传播。
            diagnostics?.record(source: "AnalyzeByRegex.getElement", rule: pattern, message: "正则编译失败")
            fatalError("正则编译失败: \(pattern)")
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
            for groupIndex in 0...first.numberOfRanges - 1 {
                let r = first.range(at: groupIndex)
                if r.location == NSNotFound {
                    // Kotlin `resM.group(i)!!` 未参与匹配的组会抛 NPE。
                    diagnostics?.record(source: "AnalyzeByRegex.getElement", rule: pattern,
                                        message: "捕获组 \(groupIndex) 未参与匹配（Kotlin 会抛 NPE）")
                    fatalError("捕获组 \(groupIndex) 未参与匹配")
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
            return getElement(result, regs, index: vIndex, diagnostics: diagnostics)
        }
    }

    /// 对应 Kotlin: fun getElements(res, regs, index=0): List<List<String>>
    public static func getElements(
        _ res: String,
        _ regs: [String],
        index: Int = 0,
        diagnostics: RuleEngineDiagnostics? = nil
    ) -> [[String]] {
        var vIndex = index
        let pattern = regs[vIndex]
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            diagnostics?.record(source: "AnalyzeByRegex.getElements", rule: pattern, message: "正则编译失败")
            fatalError("正则编译失败: \(pattern)")
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
                for groupIndex in 0...m.numberOfRanges - 1 {
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
            return getElements(result, regs, index: vIndex, diagnostics: diagnostics)
        }
    }
}
