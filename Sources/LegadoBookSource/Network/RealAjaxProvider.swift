//
//  RealAjaxProvider.swift
//  LegadoBookSource
//
//  第 6 步 6B：AjaxProvider 的真实实现（对应 Kotlin AnalyzeRule.ajax / JsExtensions.ajax）。
//
//  Kotlin 对应位置：
//   - AnalyzeRule.kt `override fun ajax(url: String?): String?` → JsExtensions.ajax(url, callTimeout)
//     （help/JsExtensions.kt:100-122）
//   - AnalyzeUrl.getStrResponse（model/analyzeRule/AnalyzeUrl.kt:540）：
//       AnalyzeUrl(urlStr, source = getSource(), callTimeout = callTimeout) ->
//       concurrentRateLimiter.withLimit { executeStrRequest } -> StrResponse.body
//   - 失败分支 `getOrElse { it.stackTraceStr }`：返回**错误字符串**而不是抛异常。
//
//  语义：
//   - 走 AnalyzeUrl（含 concurrentRateLimiter 限速）+ 注入的 HTTPClient（默认 URLSessionHTTPClient）；
//   - 成功：返回解码后的 body（含 isXml / bodyJs 后处理，与 executeStrRequest 一致）；
//   - 失败：返回 "ajax(<url>) error\n<错误描述>"（对齐 Kotlin getOrElse { stackTraceStr }；
//     差异：Kotlin 返回 Java 堆栈文本，这里返回 Swift 错误描述）；
//   - type != null（url option type，如 data: URI）时返回字节的十六进制串（对齐 getStrResponseAwait）。
//
//  与 Kotlin 的差异（README 6B 小节登记）：
//   1. 同步桥：Kotlin 用 runBlocking(coroutineContext)；本移植用信号量把 async 工作桥回同步
//      （会阻塞调用线程，与 Kotlin 取舍相同）；
//   2. 书源：Kotlin 用 getSource() 的头/并发率；本移植可注入 source（默认 nil，不携带），
//      AnalyzeRule 默认构造的 RealAjaxProvider() 不带书源；
//   3. WebView 分支不实现（URLSessionHTTPClient 的既有约定）。
//

import Foundation

/// `AjaxProvider` 的真实实现（第 6 步 6B）。
public final class RealAjaxProvider: AjaxProvider {

    private let client: HTTPClient
    private let environment: AnalyzeUrlEnvironment
    private let source: (any SourceVariableStore)?
    private let diagnostics: RuleEngineDiagnostics?

    /// - Parameters:
    ///   - client: 网络客户端（默认 URLSessionHTTPClient；测试可注入 ScriptedHTTPClient）。
    ///   - environment: AnalyzeUrl 的环境（cookie/cache/diagnostics）。
    ///   - source: 书源变量存取（对应 Kotlin getSource()；默认 nil）。
    ///   - diagnostics: 非致命诊断收集器（默认 nil）。
    public init(client: HTTPClient? = nil,
                environment: AnalyzeUrlEnvironment = AnalyzeUrlEnvironment(),
                source: (any SourceVariableStore)? = nil,
                diagnostics: RuleEngineDiagnostics? = nil) {
        self.client = client ?? JsNetSupport.makeDefaultClient()
        self.environment = environment
        self.source = source
        self.diagnostics = diagnostics
    }

    /// 对应 Kotlin `ajax(url: String?): String?`：
    /// 失败时返回错误字符串（绝不抛异常、绝不崩溃），与 `getOrElse { stackTraceStr }` 一致。
    public func ajax(_ url: String) -> String? {
        let urlStr = url
        do {
            return try JsNetSupport.runBlocking { [self] in
                try await ajaxAsync(urlStr, callTimeout: nil)
            }
        } catch {
            diagnostics?.record(source: "RealAjaxProvider.ajax",
                                rule: urlStr, message: "ajax 失败：\(error)")
            // 对应 Kotlin `ajax(url) error\n${it.localizedMessage}` 风格 + stackTraceStr 兜底。
            return "ajax(\(urlStr)) error\n\(error)"
        }
    }

    /// ajax 的异步形态（future: 供 Swift 并发调用方直接使用；语义同 ajax(_:)）。
    public func ajaxAsync(_ url: String, callTimeout: Int64?) async throws -> String {
        let analyzeUrl = AnalyzeUrl(url,
                                    source: source,
                                    callTimeout: callTimeout,
                                    environment: environment)
        let payload = try await JsNetSupport.strPayload(for: analyzeUrl,
                                                        client: client,
                                                        environment: environment,
                                                        skipRateLimit: false)
        return payload.body
    }
}
