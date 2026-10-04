//
//  RuleEngineDiagnostics.swift
//  LegadoBookSource
//
//  规则引擎的非致命诊断收集器。
//
//  对应 Kotlin 里被 try-catch 吞掉异常的地方（如 AnalyzeByJSonPath 里 ctx.read 失败
//  时 e.printOnDebug() 然后返回空值）。本移植保持"返回空值"的行为不变，同时提供一个
//  可选的收集器把错误记录下来，默认关闭（nil），不影响任何返回值。
//

import Foundation

/// 一条规则引擎运行期的诊断（非致命，已被吞掉，仅用于排查）。
public struct RuleEngineDiagnostic: Equatable {
    /// 发生位置（如 "AnalyzeByJSonPath.getString"）。
    public let source: String
    /// 出错的规则文本。
    public let rule: String
    /// 错误可读描述。
    public let message: String

    public init(source: String, rule: String, message: String) {
        self.source = source
        self.rule = rule
        self.message = message
    }
}

/// 诊断收集器（引用类型，可在多次解析调用间累积）。默认不创建即不收集。
public final class RuleEngineDiagnostics {
    public private(set) var diagnostics: [RuleEngineDiagnostic] = []

    public init() {}

    public func record(source: String, rule: String, error: Error) {
        diagnostics.append(
            RuleEngineDiagnostic(source: source, rule: rule, message: (error as NSError).localizedDescription)
        )
    }

    public func record(source: String, rule: String, message: String) {
        diagnostics.append(RuleEngineDiagnostic(source: source, rule: rule, message: message))
    }

    public func drain() -> [RuleEngineDiagnostic] {
        let d = diagnostics
        diagnostics = []
        return d
    }
}
