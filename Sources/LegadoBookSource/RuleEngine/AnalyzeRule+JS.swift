//
//  AnalyzeRule+JS.swift
//  LegadoBookSource
//
//  AnalyzeRule 的 evalJS（JavaScriptCore）、ajax、webJSResult、log、reGetBook/refreshTocUrl 桩。
//  对应 Kotlin AnalyzeRule.kt 的 evalJS / ajax / getWebJsResult / reGetBook / refreshTocUrl。
//

import Foundation

extension AnalyzeRule {

    /// 对应 Kotlin: fun evalJS(jsStr, result=null): Any?
    /// 用 JavaScriptCore 执行；绑定键名与 Kotlin 一致。JsExtensions 未实现方法由 Proxy 抛错。
    @discardableResult
    public func evalJS(_ jsStr: String, result: RuleValue = .null) throws -> RuleValue {
        #if canImport(JavaScriptCore)
        let engine = JSEngine(diagnostics: diagnostics)
        let bridge = JSJavaBridge(diagnostics: diagnostics,
                                  uiProvider: jsUIProviderValue,
                                  networkProvider: jsNetworkProviderValue,
                                  webJSProvider: webJSProviderValue)
        // 注入 java 对象自有方法（回调本 AnalyzeRule）
        bridge.runtime.putFn = { [weak self] k, v in self?.put(k, v) ?? v }
        bridge.runtime.getFn = { [weak self] k in self?.get(k) ?? "" }
        bridge.runtime.getStringFn = { [weak self] r in
            guard let self = self else { return "" }
            return (try? self.getString(r)) ?? ""
        }
        bridge.runtime.getStringListFn = { [weak self] r in
            guard let self = self else { return [] }
            return ((try? self.getStringList(r)) ?? nil) ?? []
        }
        bridge.runtime.getElementFn = { [weak self] r in
            guard let self = self else { return "" }
            return ((try? self.getElement(r)) ?? nil)?.stringValue ?? ""
        }
        bridge.runtime.getElementsFn = { [weak self] r in
            guard let self = self else { return [] }
            return ((try? self.getElements(r)) ?? []).map { $0.stringValue }
        }
        bridge.runtime.ajaxFn = { [weak self] u in self?.ajax(u) ?? "" }
        bridge.runtime.logFn = { [weak self] s in self?.log(s) ?? s }
        bridge.runtime.getSourceKeyFn = { [weak self] in self?.sourceStore?.getKey() }
        bridge.runtime.getTagFn = { [weak self] in self?.getTag() }
        bridge.runtime.cookieStore = cookieStoreValue

        let bindings = JSEngine.Bindings(
            java: bridge,
            cookie: cookieStoreValue,
            cache: cacheManagerValue,
            sourceKey: sourceStore?.getKey(),
            bookName: bookStore?.name,
            bookFields: bookStore?.jsFields ?? [:],
            chapterFields: chapterStore?.jsFields ?? [:],
            result: result,
            baseUrl: baseUrlValue,
            chapterTitle: chapterStore?.title,
            src: contentValue?.stringValue,
            nextChapterUrl: nextChapterUrlValue,
            fromBookInfo: isFromBookInfoValue
        )
        return try engine.eval(jsStr, bindings: bindings)
        #else
        throw RuleEngineError.unsupported("JavaScriptCore 不可用（当前平台无法运行 JS）")
        #endif
    }

    /// 对应 Kotlin override fun getTag(): String? = source?.getTag() ?: ruleName
    public func getTag() -> String? {
        return sourceStore?.getTag() ?? ruleNameValue
    }

    /// 对应 Kotlin override fun getSource(): BaseSource? —— 返回注入的书源变量存取器。
    public func getSource() -> SourceVariableStore? {
        return sourceStore
    }

    /// 对应 Kotlin override fun ajax(url): String? —— 失败返回错误串（getOrElse { stackTraceStr }）。
    @discardableResult
    public func ajax(_ url: String) -> String? {
        return ajaxProviderValue.ajax(url)
    }

    /// 对应 Kotlin JsExtensions.log（默认把消息原样返回，并可记录）。
    @discardableResult
    public func log(_ msg: String) -> String {
        diagnostics?.record(source: "AnalyzeRule.log", rule: "", message: msg)
        return msg
    }

    /// 对应 Kotlin getWebJsResult（走 BackstageWebView）。默认 WebJSProvider 抛 unsupported。
    func webJSResult(_ jsStr: String, result: RuleValue) throws -> String {
        return try webJSProviderValue.eval(js: jsStr, result: result.stringValue, baseUrl: baseUrlValue)
    }

    // MARK: - 依赖 WebBook 的方法（本步骤留桩抛 unsupported）

    /// 对应 Kotlin: fun reGetBook() —— 真实实现依赖 WebBook，本步骤排除（第 6 步）。
    public func reGetBook() throws {
        if !isFromBookInfoValue {}
        throw RuleEngineError.unsupported("reGetBook 依赖 WebBook，未实现（第 6 步）")
    }

    /// 对应 Kotlin: fun refreshTocUrl() —— 同上，留桩。
    public func refreshTocUrl() throws {
        throw RuleEngineError.unsupported("refreshTocUrl 依赖 WebBook，未实现（第 6 步）")
    }
}
