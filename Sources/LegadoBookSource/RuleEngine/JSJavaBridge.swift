//
//  JSJavaBridge.swift
//  LegadoBookSource
//
//  JS 里 `java` 对象的桥接。对应 Kotlin evalJS 里 bindings["java"] = this（AnalyzeRule 实现
//  JsExtensions 接口）。本步骤只提供 AnalyzeRule 自身实现的方法；JsExtensions 的其余方法
//  用 JS Proxy 拦截，调用即抛明确错误 + 记 diagnostics（不静默返回 undefined）。
//
//  AnalyzeRule 自身在 `java` 上提供的方法：
//    put / get / getString / getStringList / getElement / getElements / setContent /
//    ajax / log / getSource / getTag
//  （以 AnalyzeRule.kt 为准：这些是 AnalyzeRule 标了 fun/override 且 JS 可调用的自有方法。）
//

import Foundation

#if canImport(JavaScriptCore)
import JavaScriptCore

/// `java` 对象的自有方法实现由 AnalyzeRule 以闭包注入。
final class JSJavaBridge {
    // 自有方法闭包（由 AnalyzeRule 注入）。参数/返回尽量贴近 Kotlin 签名。
    var putFn: (String, String) -> String = { _, v in v }
    var getFn: (String) -> String = { _ in "" }
    var getStringFn: (String) -> String = { _ in "" }
    var getStringListFn: (String) -> [String] = { _ in [] }
    var getElementFn: (String) -> String = { _ in "" }   // 返回字符串化结果（JS 侧通常再喂 getString）
    var getElementsFn: (String) -> [String] = { _ in [] }
    var ajaxFn: (String) -> String = { url in "ajax(\(url)) error\n未实现" }
    var logFn: (String) -> String = { s in s }
    var getSourceKeyFn: () -> String? = { nil }
    var getTagFn: () -> String? = { nil }

    init() {}

    /// 在 JSContext 安装 `java` 对象（含 Proxy 拦截未实现方法）。
    func install(into context: JSContext, diagnostics: RuleEngineDiagnostics?) {
        guard let base = JSValue(newObjectIn: context) else { return }

        // 自有方法
        let put: @convention(block) (String, String) -> String = { [weak self] k, v in
            self?.putFn(k, v) ?? v
        }
        let get: @convention(block) (String) -> String = { [weak self] k in self?.getFn(k) ?? "" }
        let getString: @convention(block) (String) -> String = { [weak self] r in self?.getStringFn(r) ?? "" }
        let getStringList: @convention(block) (String) -> [String] = { [weak self] r in self?.getStringListFn(r) ?? [] }
        let getElement: @convention(block) (String) -> String = { [weak self] r in self?.getElementFn(r) ?? "" }
        let getElements: @convention(block) (String) -> [String] = { [weak self] r in self?.getElementsFn(r) ?? [] }
        let ajax: @convention(block) (String) -> String = { [weak self] u in self?.ajaxFn(u) ?? "" }
        let log: @convention(block) (String) -> String = { [weak self] s in self?.logFn(s) ?? s }
        let getSource: @convention(block) () -> String? = { [weak self] in self?.getSourceKeyFn() }
        let getTag: @convention(block) () -> String? = { [weak self] in self?.getTagFn() }

        base.setObject(put, forKeyedSubscript: "put" as NSString)
        base.setObject(get, forKeyedSubscript: "get" as NSString)
        base.setObject(getString, forKeyedSubscript: "getString" as NSString)
        base.setObject(getStringList, forKeyedSubscript: "getStringList" as NSString)
        base.setObject(getElement, forKeyedSubscript: "getElement" as NSString)
        base.setObject(getElements, forKeyedSubscript: "getElements" as NSString)
        base.setObject(ajax, forKeyedSubscript: "ajax" as NSString)
        base.setObject(log, forKeyedSubscript: "log" as NSString)
        base.setObject(getSource, forKeyedSubscript: "getSource" as NSString)
        base.setObject(getTag, forKeyedSubscript: "getTag" as NSString)

        // 已实现方法名集合（供 Proxy get 判断）。
        let implemented: [String] = [
            "put", "get", "getString", "getStringList", "getElement", "getElements",
            "ajax", "log", "getSource", "getTag"
        ]
        context.setObject(implemented, forKeyedSubscript: "__javaImplemented" as NSString)
        context.setObject(base, forKeyedSubscript: "__javaBase" as NSString)

        // 诊断回调：Proxy 命中未实现方法时调用，记录 diagnostics。
        let recordDiag: @convention(block) (String) -> Void = { name in
            diagnostics?.record(source: "JSJavaBridge.proxy", rule: "java.\(name)",
                                message: "java.\(name) 尚未实现（JsExtensions，第 5 步）")
        }
        context.setObject(recordDiag, forKeyedSubscript: "__recordJavaDiag" as NSString)

        // 用 Proxy 包裹：已实现方法直通；未实现方法返回一个抛错的函数。
        let proxyScript = """
        (function(){
          var impl = {};
          for (var i=0;i<__javaImplemented.length;i++){ impl[__javaImplemented[i]]=true; }
          var handler = {
            get: function(target, prop) {
              if (typeof prop === 'symbol') { return target[prop]; }
              if (impl[prop]) { return target[prop]; }
              if (prop in target) { return target[prop]; }
              // 未实现 JsExtensions 方法：返回抛错函数
              return function() {
                if (typeof __recordJavaDiag === 'function') { __recordJavaDiag(prop); }
                throw new Error('java.' + prop + ' 尚未实现（JsExtensions，第 5 步）');
              };
            }
          };
          return new Proxy(__javaBase, handler);
        })()
        """
        if let proxy = context.evaluateScript(proxyScript) {
            context.setObject(proxy, forKeyedSubscript: "java" as NSString)
        } else {
            // Proxy 不可用时退回未包裹对象（极少见；JSC 支持 Proxy）。
            context.setObject(base, forKeyedSubscript: "java" as NSString)
        }
    }
}

#endif
