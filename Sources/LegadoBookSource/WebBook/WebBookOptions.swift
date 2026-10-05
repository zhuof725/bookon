//
//  WebBookOptions.swift
//  LegadoBookSource
//
//  流程层共享的调用上下文（第 7 步 A 段）。
//  把「可注入日志」「可注入网络」「诊断」三件套打包，供 WebBook 各流程函数透传。
//

import Foundation

public struct WebBookOptions {
    /// 调试日志（对应 Kotlin Debug 单例，Swift 改为注入实例）。
    public var logger: DebugLogger
    /// 网络获取（对应 Kotlin AnalyzeUrl.getStrResponseAwait，Swift 用可注入协议）。
    public var network: any WebBookNetwork
    /// 规则引擎诊断（对应 AnalyzeRule 的 diagnostics 入参）。
    public var diagnostics: RuleEngineDiagnostics?

    public init(
        logger: DebugLogger = DebugLogger(),
        network: any WebBookNetwork,
        diagnostics: RuleEngineDiagnostics? = nil
    ) {
        self.logger = logger
        self.network = network
        self.diagnostics = diagnostics
    }
}
