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
//  第 6 步 6B：网络方法的返回值信封（\u{1}JSCONN\u{1} / \u{1}JSSTR\u{1} / \u{1}JSSTRS\u{1}
//  + JSON）在 JS 侧由 __javaUnwrap 还原为带方法的对象：
//   - get/post/head → jsoup Connection.Response 替身（body()/statusCode()/statusMessage()/
//     headers()/cookies()/header(name)/cookieKey(name)/url()/contentType()）；
//   - connect → StrResponse 替身（body()/code()/message()/headers()/raw()/toString()/
//     callTime()/url()）；ajaxAll → StrResponse 替身数组。
//  信封由 RealJsNetworkExtensionsProvider 构造，前缀常量为 P_CONN/P_STR/P_STRS（与 Swift 侧一致）。
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
          // 6B：网络方法的「信封字符串」（\\u0001 前缀 + JSON）→ 带方法的 JS 对象。
          // 对应 Kotlin 里 get/post/head 返回的 jsoup Connection.Response、
          // connect/ajaxAll 返回的 StrResponse；信封由 RealJsNetworkExtensionsProvider 构造。
          var P_CONN = '\\u0001JSCONN\\u0001';
          var P_STR = '\\u0001JSSTR\\u0001';
          var P_STRS = '\\u0001JSSTRS\\u0001';
          function __headerMap(pairs){
            var m = {};
            for (var i=0;i<pairs.length;i++){
              var k = pairs[i][0], v = pairs[i][1];
              if (Object.prototype.hasOwnProperty.call(m, k)) { m[k].push(v); } else { m[k] = [v]; }
            }
            var getter = function(name){
              var lower = String(name).toLowerCase();
              for (var k in m){
                if (Object.prototype.hasOwnProperty.call(m, k) && k.toLowerCase() === lower) { return m[k]; }
              }
              return null;
            };
            try { Object.defineProperty(m, 'get', { value: getter, enumerable: false, configurable: true }); }
            catch (e) { m.get = getter; }
            return m;
          }
          function __cookieMap(pairs){
            var m = {};
            for (var i=0;i<pairs.length;i++){ m[pairs[i][0]] = pairs[i][1]; }
            var getter = function(name){ return Object.prototype.hasOwnProperty.call(m, name) ? m[name] : null; };
            try { Object.defineProperty(m, 'get', { value: getter, enumerable: false, configurable: true }); }
            catch (e) { m.get = getter; }
            return m;
          }
          function __makeConnection(d){
            var hm = __headerMap(d.headers || []);
            var cm = __cookieMap(d.cookies || []);
            var conn = {
              statusCode: function(){ return d.status; },
              statusMessage: function(){ return d.message; },
              headers: function(){ return hm; },
              cookies: function(){ return cm; },
              header: function(name){
                var lower = String(name).toLowerCase();
                for (var k in hm){
                  if (Object.prototype.hasOwnProperty.call(hm, k) && k.toLowerCase() === lower) { return hm[k][0]; }
                }
                return null;
              },
              cookieKey: function(name){
                return Object.prototype.hasOwnProperty.call(cm, name) ? cm[name] : null;
              },
              url: function(){ return d.url; },
              contentType: function(){ return d.contentType; }
            };
            // 6B-6：jsoup Connection.Response 在 Kotlin 里是 Java 对象，`.body` 与 `.body()` 都可用
            // （Rhino 对 Java getter 既支持属性也支持方法调用）。这里用「同名 getter 返回可调用的
            // 函数字符串」模拟：读 `.body` 得到该字符串（与 body() 的返回值内容一致），
            // 调用 `.body()` 也得到同一内容 —— 两种写法都拿到响应体。
            __installDualChannel(conn, 'body', function(){ return d.body; });
            return conn;
          }
          function __makeStrResponse(d){
            var res = {
              code: function(){ return d.code; },
              message: function(){ return d.message; },
              headers: function(){ return __headerMap(d.headers || []); },
              raw: function(){ return d.raw; },
              toString: function(){ return d.raw; },
              callTime: function(){ return d.callTime; },
              url: function(){ return d.url; }
            };
            // 6B-6：Kotlin `StrResponse` 同时有 `var body: String?`（属性）与 `fun body()`（方法），
            // 书源里两种写法都存在。这里同时支持 `.body` 与 `.body()`（见 __installDualChannel）。
            __installDualChannel(res, 'body', function(){ return d.body; });
            return res;
          }
          // 双重通道安装器：让 `.name`（属性）与 `.name()`（方法）都返回同一个值。
          // Kotlin 侧 `StrResponse` 同时定义了 `var body: String?`（属性）与 `fun body()`（方法），
          // 书源里两种写法都存在；Rhino 对 Java getter 也同时支持属性与方法调用。
          //
          // JS 实现：属性 getter 返回一个 Proxy —— 它是可调用对象（`x()` 返回字符串），
          // 同时把 String 原型上的方法与属性转发出去（`x.length` / `x.indexOf(...)` /
          // `x.slice(...)` / `x.includes(...)` / 索引访问 / 解构都成立），
          // `toString`/`valueOf`/`toJSON` 也返回原字符串，因此拼接、比较（==）、
          // `String(x)`、`JSON.stringify` 均与字符串语义一致。
          // 唯一差异：`typeof x` 为 "function"、严格 `===` 字符串为 false（已记入差异表 6B-6）。
          function __dualValue(v){
            if (typeof v !== 'string') { return v; }
            var str = new String(v);
            var callable = function(){ return v; };
            return new Proxy(callable, {
              get: function(t, prop){
                if (prop === 'toString' || prop === 'valueOf' || prop === 'toJSON') {
                  return function(){ return v; };
                }
                if (prop === 'length') { return v.length; }
                if (prop in t) { return t[prop]; }
                var sv = str[prop];
                return (typeof sv === 'function') ? sv.bind(str) : sv;
              },
              apply: function(){ return v; },
              has: function(t, prop){ return prop in t || prop in str; }
            });
          }
          function __installDualChannel(obj, name, getter){
            Object.defineProperty(obj, name, {
              enumerable: true,
              configurable: true,
              get: function(){ return __dualValue(getter()); },
              set: function(){ /* Kotlin 侧 body 为 private set，外部不可写 */ }
            });
          }
          function __javaUnwrap(v){
            if (typeof v !== 'string') { return v; }
            if (v.indexOf(P_CONN) === 0) {
              try { return __makeConnection(JSON.parse(v.slice(P_CONN.length))); } catch (e) { return v; }
            }
            if (v.indexOf(P_STR) === 0) {
              try { return __makeStrResponse(JSON.parse(v.slice(P_STR.length))); } catch (e) { return v; }
            }
            if (v.indexOf(P_STRS) === 0) {
              try {
                var arr = JSON.parse(v.slice(P_STRS.length));
                var out = [];
                for (var i=0;i<arr.length;i++){ out.push(__makeStrResponse(arr[i])); }
                return out;
              } catch (e) { return v; }
            }
            return v;
          }
          var names = __javaImplemented;
          var base = {};
          for (var i=0;i<names.length;i++){
            (function(name){
              base[name] = function(){
                var r = __callJava(name, Array.prototype.slice.call(arguments));
                if (!r.ok) { throw new Error(r.error || ('java.'+name+' 调用失败')); }
                return __javaUnwrap(r.value);
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