//
//  RuleEngineError.swift
//  LegadoBookSource
//
//  规则引擎的可抛出错误。用来取代原先会让 App 崩溃的写法
//  （fatalError / 强制解包 / 越界访问），对齐 Kotlin 里会向上传播的异常语义。
//
//  Kotlin 里这些是「未捕获会崩」的异常：
//   - RuleAnalyzer 括号不平衡：`throw Error(... + "后未平衡")`
//   - RuleAnalyzer 越界：`queue[pos]` 抛 StringIndexOutOfBoundsException
//   - AnalyzeByRegex 正则编译失败：`Pattern.compile` 抛 PatternSyntaxException
//   - AnalyzeByRegex.getElement 捕获组未参与：`group(i)!!` 抛 NPE
//  这里统一收敛为 RuleEngineError，供调用方 try/catch，不再让进程崩溃。
//

import Foundation

public enum RuleEngineError: Error, Equatable, LocalizedError {
    /// 括号 / 平衡组不平衡。message 对齐 Kotlin：`queue.substring(0, start) + "后未平衡"`。
    case unbalanced(String)
    /// 下标越界（substring 起点>终点或超出范围、trim 越界等）。
    case indexOutOfBounds(String)
    /// 正则编译失败（对齐 Kotlin Pattern.compile 抛错）。
    case regexCompileFailed(pattern: String)
    /// 正则捕获组未参与匹配（对齐 Kotlin getElement 里 group(i)!! 抛 NPE）。
    case regexGroupNotParticipated(groupIndex: Int, pattern: String)
    /// 传入的 JSON 字符串无法解析（对齐 Jayway JsonPath.parse 解析失败抛异常）。
    case invalidJSON(String)

    public var errorDescription: String? {
        switch self {
        case .unbalanced(let s): return s + "后未平衡"
        case .indexOutOfBounds(let s): return "下标越界: \(s)"
        case .regexCompileFailed(let p): return "正则编译失败: \(p)"
        case .regexGroupNotParticipated(let i, let p): return "捕获组 \(i) 未参与匹配: \(p)"
        case .invalidJSON(let s): return "无法解析的 JSON: \(s)"
        }
    }
}
