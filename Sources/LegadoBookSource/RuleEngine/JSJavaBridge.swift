//
//  JSJavaBridge.swift
//  LegadoBookSource
//
//  JS 里 `java` 对象的桥接。对应 Kotlin evalJS 里 bindings["java"] = this
//  （AnalyzeRule 实现 JsExtensions : JsEncodeUtils 接口）。
//
//  Step 5：`java` 上已实现的方法（JsExtensionsCatalog.implemented）通过通用分发器
//  JsExtensionsRuntime 提供真实实现；未实现方法仍由 JS Proxy 拦截，调用即抛明确
//  JS 错误 + 记 diagnostics（不静默返回 undefined）。
//

import Foundation

#if canImport(JavaScriptCore)
import JavaScriptCore

/// `java` 对象的实现注入点：AnalyzeRule 注入自有方法闭包，其余由 runtime 分发。
final class JSJavaBridge {
    /// 通用分发器（Step 5）。AnalyzeRule 负责把自有方法闭包设置到它上面。
    let runtime: JsExtensionsRuntime

    init(diagnostics: RuleEngineDiagnostics?,
         uiProvider: JsUIProvider = UnsupportedJsUIProvider(),
         networkProvider: JsNetworkExtensionsProvider = UnsupportedJsNetworkExtensionsProvider(),
         webJSProvider: WebJSProvider = UnsupportedWebJSProvider()) {
        self.runtime = JsExtensionsRuntime(diagnostics: diagnostics,
                                           uiProvider: uiProvider,
                                           networkProvider: networkProvider,
                                           webJSProvider: webJSProvider)
    }

    /// 在 JSContext 安装 `java` 对象（含 Proxy 拦截未实现方法）。
    func install(into context: JSContext, diagnostics: RuleEngineDiagnostics?) {
        guard let base = JSValue(newObjectIn: context) else { return }

        // __call 原生分发入口：(name, argsArray) -> [String:Any]
        let runtime = self.runtime
        // 注意：@convention(block) 的参数必须是 ObjC 桥接类型；JSValue 可直接作为参数。
        let callBlock: @convention(block) (NSString, JSValue) -> [String: Any] = { name, argsValue in
            var arguments: [Any?] = []
            if let array = argsValue.toArray() {
                arguments = array.map { $0 is NSNull ? nil : $0 }
            }
            let result = runtime.call(name as String, arguments: arguments)
            var dict: [String: Any] = ["ok": result.ok]
            if let value = result.value {
                dict["value"] = value
            }
            if let error = result.error {
                dict["error"] = error
            }
            return dict
        }
        context.setObject(callBlock, forKeyedSubscript: "__callJava" as NSString)

        // 定义 java 基对象：为每个「已实现方法」安装包装函数。
        let implementedNames = JsExtensionsCatalog.implemented.sorted()
        context.setObject(implementedNames, forKeyedSubscript: "__javaImplemented" as NSString)

        let recordDiag: @convention(block) (String) -> Void = { name in
            diagnostics?.record(source: "JSJavaBridge.proxy", rule: "java.\(name)",
                                message: "java.\(name) 尚未实现（JsExtensions，第 5 步范围外）")
        }
        context.setObject(recordDiag, forKeyedSubscript: "__recordJavaDiag" as NSString)

        let proxyScript = """
        (function(){
          var names = __javaImplemented;
          var base = {};
          for (var i=0;i<names.length;i++){
            (function(name){
              base[name] = function(){
                var r = __callJava(name, Array.prototype.slice.call(arguments));
                if (!r.ok) { throw new Error(r.error || ('java.'+name+' 调用失败')); }
                return r.value;
              };
            })(names[i]);
          }
          var handler = {
            get: function(target, prop) {
              if (typeof prop === 'symbol') { return target[prop]; }
              if (prop in target) { return target[prop]; }
              // 未实现 JsExtensions 方法：返回抛错函数（不静默 undefined）
              return function() {
                if (typeof __recordJavaDiag === 'function') { __recordJavaDiag(prop); }
                throw new Error('java.' + prop + ' 尚未实现（JsExtensions，第 5 步范围外）');
              };
            }
          };
          return new Proxy(base, handler);
        })()
        """
        if let proxy = context.evaluateScript(proxyScript) {
            context.setObject(proxy, forKeyedSubscript: "java" as NSString)
        } else {
            context.setObject(base, forKeyedSubscript: "java" as NSString)
        }
    }
}

#endif