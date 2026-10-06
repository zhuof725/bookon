//
//  JSEngine.swift
//  LegadoBookSource
//
//  对应 Kotlin AnalyzeRule.evalJS：用 Rhino(com.script.rhino) 执行 JS。
//  本移植用 JavaScriptCore（iOS/macOS 原生），绑定对象键名与 Kotlin 完全一致：
//    java、cookie、cache、source、book、result、baseUrl、chapter、title、src、
//    nextChapterUrl、rssArticle、fromBookInfo。
//
//  `java` 对象：只暴露 AnalyzeRule 自身实现的方法（put/get/getString/getStringList/
//  getElement/getElements/setContent/ajax/log/getSource/getTag）。JsExtensions 的其余
//  方法（见 JsExtensionsCatalog）用 Proxy 拦截，调用即抛明确 JS 错误并记 diagnostics。
//
//  ⚠️ Rhino vs JavaScriptCore 差异（详见 README 差异表）：
//   - Java 互操作（Packages.xxx / importClass / importPackage / org.jsoup.Jsoup.parse /
//     java.lang.String）在 JSC 不存在。真实书源（台湾小说网、爱丽丝书屋）用了这类互操作，
//     本引擎检测到即抛明确错误 + 记 diagnostics，不假装支持。
//   - 数字→字符串：JS 内部 String(x)/拼接 与 Kotlin raw.toString() 是两条不同路径。
//     Rhino 返回 Java Double 时 Double.toString 整数带 .0；inline {{}} 仅对
//     Double%1==0 用 Locale.ROOT "%.0f"。以真实 Rhino 1.8.1 golden 定案，详见 README。
//   - ES 版本：legado 的 Rhino 设置 VERSION_ES6 + setInterpretedMode(true)；JSC 支持现代 ES。
//     未覆盖的现代语法仍不能声称与 Rhino 完全一致。
//
//  —— 全局规范：绝不崩溃。JS 求值异常 -> throw RuleEngineError.jsError + 记 diagnostics。
//

import Foundation

#if canImport(JavaScriptCore)
import JavaScriptCore

/// JavaScriptCore 实现的 JS 求值器。线程安全性：与 Kotlin 一致，调用方自行保证单线程使用。
final class JSEngine {

    private let diagnostics: RuleEngineDiagnostics?
    /// scriptCache 容量 16（对齐 Kotlin getOrPutLimit(16)）。缓存「源码字符串」。
    private var scriptCache: [String] = []
    private let scriptCacheLimit = 16

    init(diagnostics: RuleEngineDiagnostics? = nil) {
        self.diagnostics = diagnostics
    }

    /// Java 互操作检测：出现这些片段即判定为 Rhino-only，JSC 无法运行。
    /// 注意 "Packages." 会先剔除合法的 `Packages.org.jsoup`（Step 5 jsoup 替身放行）。
    private static let javaInteropMarkers = [
        "Packages.", "importClass", "importPackage",
        "java.lang", "java.util", "java.net", "java.math", "JavaImporter"
    ]

    /// Step 5：org.jsoup.Jsoup 替身放行。true 表示只用了 jsoup 两种写法（可放行）。
    static func isJsoupOnlyInterop(_ js: String) -> Bool {
        return js.contains("org.jsoup.Jsoup") && detectJavaInterop(js) == nil
    }

    /// 预检测 Java 互操作。返回命中的标记（若有）；仅 `org.jsoup` 写法不算（Step 5 放行）。
    static func detectJavaInterop(_ js: String) -> String? {
        // 先把合法的 Packages.org.jsoup 归一成 org.jsoup，其余 Packages. 用法仍视为互操作。
        let scrubbed = js.replacingOccurrences(of: "Packages.org.jsoup", with: "org.jsoup")
        for m in javaInteropMarkers where scrubbed.contains(m) {
            return m
        }
        return nil
    }

    /// 绑定上下文。对应 Kotlin buildScriptBindings 的键集合。
    struct Bindings {
        var java: JSJavaBridge
        var cookie: CookieStoreProtocol
        var cache: CacheManagerProtocol
        var sourceKey: String?
        var bookName: String?
        /// 书籍字段（键值均为字符串），用于把 `book` 绑成 **JS 对象**（对齐 Kotlin
        /// `bindings["book"] = book`，BaseBook 对象可访问 `book.bookUrl`）。
        /// 为空时退化为按 `bookName` 绑一个字符串，保持既有行为。
        var bookFields: [String: String] = [:]
        /// 章节字段（同上，用于 `chapter` 绑定）。
        var chapterFields: [String: String] = [:]
        var result: RuleValue
        var baseUrl: String?
        var chapterTitle: String?
        var src: String?
        var nextChapterUrl: String?
        var fromBookInfo: Bool
        /// 第 6 步：AnalyzeUrl.evalJS 需要的额外绑定（page/key/speakText/speakSpeed/infoMap 等）。
        /// 默认空——不影响既有调用方的绑定集合。
        var extraBindings: [String: Any] = [:]
    }

    /// 执行 JS，返回结果（已转 RuleValue）。对应 Kotlin evalJS。
    func eval(_ jsStr: String, bindings: Bindings) throws -> RuleValue {
        // Step 5：org.jsoup.Jsoup / Packages.org.jsoup.Jsoup 放行（安装 SwiftSoup 替身）；
        // 其它 Java 互操作仍是 Rhino-only，抛明确错误。
        if !JSEngine.isJsoupOnlyInterop(jsStr) {
            if let marker = JSEngine.detectJavaInterop(jsStr) {
                let msg = "JS 含 Java 互操作『\(marker)』，JavaScriptCore 不支持（Rhino-only，见 README 差异表）"
                diagnostics?.record(source: "JSEngine.eval", rule: String(jsStr.prefix(120)), message: msg)
                throw RuleEngineError.jsError(msg)
            }
        }

        guard let context = JSContext() else {
            throw RuleEngineError.jsError("无法创建 JSContext")
        }
        var thrown: Error?
        context.exceptionHandler = { _, exception in
            thrown = RuleEngineError.jsError(exception?.toString() ?? "unknown JS exception")
        }

        bind(context: context, bindings: bindings)

        // Step 5：JS 用到 jsoup 时安装替身（在绑定后、执行前，保证作用域可见）。
        if JSEngine.isJsoupOnlyInterop(jsStr) {
            JsoupJSBridge(diagnostics: diagnostics).install(into: context)
        }

        // 缓存记录（容量 16，对齐 Kotlin）。JSC 无「编译后脚本」对象，故缓存源码字符串即可。
        rememberScript(jsStr)

        let value = context.evaluateScript(jsStr)
        if let err = thrown {
            diagnostics?.record(source: "JSEngine.eval", rule: String(jsStr.prefix(120)),
                                error: err)
            throw err
        }
        guard let value = value else { return .null }
        return JSEngine.toRuleValue(value)
    }

    private func rememberScript(_ js: String) {
        if scriptCache.contains(js) { return }
        if scriptCache.count >= scriptCacheLimit { return } // 对齐 getOrPutLimit：满了不再放入
        scriptCache.append(js)
    }

    // MARK: - 绑定

    private func bind(context: JSContext, bindings: Bindings) {
        // java 对象：用 Proxy 包裹，自有方法直通，JsExtensions 未实现方法抛错。
        let bridge = bindings.java
        bridge.install(into: context, diagnostics: diagnostics)

        // cookie
        let cookieStore = bindings.cookie
        let cookieObj = JSValue(newObjectIn: context)
        let getCookie: @convention(block) (String) -> String = { url in cookieStore.getCookie(url) }
        let setCookie: @convention(block) (String, String?) -> Void = { url, c in cookieStore.setCookie(url, c) }
        let removeCookie: @convention(block) (String) -> Void = { url in cookieStore.removeCookie(url) }
        cookieObj?.setObject(getCookie, forKeyedSubscript: "getCookie" as NSString)
        cookieObj?.setObject(setCookie, forKeyedSubscript: "setCookie" as NSString)
        cookieObj?.setObject(removeCookie, forKeyedSubscript: "removeCookie" as NSString)
        context.setObject(cookieObj, forKeyedSubscript: "cookie" as NSString)

        // cache
        let cacheMgr = bindings.cache
        let cacheObj = JSValue(newObjectIn: context)
        let cacheGet: @convention(block) (String) -> String? = { k in cacheMgr.get(k) }
        let cachePut: @convention(block) (String, String) -> Void = { k, v in cacheMgr.put(k, v) }
        let cacheDel: @convention(block) (String) -> Void = { k in cacheMgr.delete(k) }
        cacheObj?.setObject(cacheGet, forKeyedSubscript: "get" as NSString)
        cacheObj?.setObject(cachePut, forKeyedSubscript: "put" as NSString)
        cacheObj?.setObject(cacheDel, forKeyedSubscript: "delete" as NSString)
        context.setObject(cacheObj, forKeyedSubscript: "cache" as NSString)

        // 标量绑定
        context.setObject(bindings.sourceKey, forKeyedSubscript: "source" as NSString)
        // ── `book` 必须是**对象**，不是书名字符串 ──
        //
        // Kotlin: `bindings["book"] = book`（BaseBook 对象），真实书源会写
        // `book.bookUrl` / `book.tocUrl`（如「淘小说书城」的 `ruleToc.chapterUrl`：
        // `String(book.bookUrl).match(/sourceId=([^&]+)/)`）。
        // 若绑成字符串，`book.bookUrl` 得 `undefined` → `.match()` 返回 null → `m[1]`
        // 抛 TypeError → 规则结果为「未获取到url」→ 所有章节 URL 相同，被按 url 去重
        // 压成 1 章（CI run 37463875191 实测日志：`⇒目录0未获取到url,使用baseUrl替代`）。
        context.setObject(
            JSEngine.fieldsToJSObject(bindings.bookFields, fallbackName: bindings.bookName, context: context),
            forKeyedSubscript: "book" as NSString
        )
        context.setObject(JSEngine.ruleValueToJSNative(bindings.result, context: context),
                          forKeyedSubscript: "result" as NSString)
        context.setObject(bindings.baseUrl, forKeyedSubscript: "baseUrl" as NSString)
        // `chapter` 同理：Kotlin 绑的是 BookChapter 对象（可访问 `chapter.title` 等）。
        context.setObject(
            JSEngine.fieldsToJSObject(bindings.chapterFields, fallbackName: bindings.chapterTitle, context: context),
            forKeyedSubscript: "chapter" as NSString
        )
        context.setObject(bindings.chapterTitle, forKeyedSubscript: "title" as NSString)
        context.setObject(bindings.src, forKeyedSubscript: "src" as NSString)
        context.setObject(bindings.nextChapterUrl, forKeyedSubscript: "nextChapterUrl" as NSString)
        context.setObject(NSNull(), forKeyedSubscript: "rssArticle" as NSString)
        context.setObject(bindings.fromBookInfo, forKeyedSubscript: "fromBookInfo" as NSString)

        // 第 6 步：AnalyzeUrl 的额外绑定（Kotlin AnalyzeUrl.evalJS 绑的是 page/key/speakText/
        // speakSpeed/book/source/infoMap，值为 null 时也要显式绑定，否则 JS 取变量会 ReferenceError）。
        for (key, value) in bindings.extraBindings {
            context.setObject(value, forKeyedSubscript: key as NSString)
        }
    }

    // MARK: - 值转换

    /// RuleValue -> JS 原生值（供 `result`/`src` 绑定用）。
    static func ruleValueToJSNative(_ v: RuleValue, context: JSContext) -> Any {
        switch v {
        case .string(let s): return s
        case .stringList(let l): return l
        case .number(let d): return d
        case .bool(let b): return b
        case .null: return NSNull()
        // ── JSON 必须**结构化**传给 JS，不能字符串化 ──
        //
        // Kotlin legado 里 `chapterList = "$.data.chapters[*]"` 经 Jayway 读出的是
        // **LinkedTreeMap/对象数组**，`@js:` 规则可以直接写 `result.chapterId` 取值。
        // 本移植早期把 `.json` 归到 default 分支传 `stringValue`（JSON 文本），导致
        // JS 里 `result.chapterId` 恒为 `undefined` —— 真实书源「淘小说书城」的
        // `ruleToc.chapterUrl` 正是用 `result.chapterId` 拼每章地址，于是所有章节
        // 拿到同一个 URL，被 `BookChapterList` 的按 url 去重逻辑压成 1 章
        // （本地探针复现：chapters.count = 1）。
        case .json(let j): return jsonValueToJSNative(j, context: context)
        case .jsonObject(let m), .jsObject(let m):
            let obj = JSValue(newObjectIn: context)
            for (k, val) in m { obj?.setObject(ruleValueToJSNative(val, context: context), forKeyedSubscript: k as NSString) }
            return obj ?? NSNull()
        default:
            // 元素等复杂类型：传其字符串化（对齐 Kotlin 把 content.toString() 交给 JS）
            return v.stringValue
        }
    }

    /// 把「字段字典」转成 JS 对象；字典为空时退化为 `fallbackName` 字符串
    /// （保证既有调用方在没提供字段时行为不变：`book` 仍是书名）。
    ///
    /// 对象上额外挂 `name`（= fallbackName 或字段里的 name），让 `book.name` 也可用。
    static func fieldsToJSObject(_ fields: [String: String], fallbackName: String?, context: JSContext) -> Any {
        guard !fields.isEmpty else { return fallbackName as Any }
        let obj = JSValue(newObjectIn: context)
        for (k, v) in fields { obj?.setObject(v, forKeyedSubscript: k as NSString) }
        if obj?.objectForKeyedSubscript("name") == nil, let n = fallbackName {
            obj?.setObject(n, forKeyedSubscript: "name" as NSString)
        }
        return obj ?? (fallbackName as Any)
    }

    /// `JSONValue` → JS 原生值（object/array/标量逐层递归）。
    ///
    /// 数字分支与 `JSONValue.stringValue` 的文本形式保持一致：
    /// 整数用 Int64（避免 `1` 变成 `1.0`）、bigInteger 原样按文本传（JS 数字会丢精度，
    /// 但这是 Jayway BigInteger 场景的已知差异，见差异表），double 传 Double。
    static func jsonValueToJSNative(_ v: JSONValue, context: JSContext) -> Any {
        switch v {
        case .object(let o):
            let obj = JSValue(newObjectIn: context)
            for (k, val) in o.orderedPairs {
                obj?.setObject(jsonValueToJSNative(val, context: context), forKeyedSubscript: k as NSString)
            }
            return obj ?? NSNull()
        case .array(let a):
            return a.map { jsonValueToJSNative($0, context: context) }
        case .string(let s): return s
        case .int(let i): return i
        case .bigInteger(let s): return s
        case .double(let d): return d
        case .bool(let b): return b
        case .null: return NSNull()
        }
    }

    /// JS 值 -> RuleValue（转换表见 README）：
    ///  string->.string, number->.number, bool->.bool, array->.stringList(元素字符串化),
    ///  object->.jsObject, null/undefined->.null
    static func toRuleValue(_ value: JSValue) -> RuleValue {
        if value.isNull || value.isUndefined { return .null }
        if value.isBoolean {
            // isBoolean 在数字上下文也可能为真，优先判断 primitive
            return .bool(value.toBool())
        }
        if value.isString { return .string(value.toString() ?? "") }
        if value.isNumber {
            return .number(value.toDouble())
        }
        if value.isArray {
            let len = Int(value.forProperty("length")?.toInt32() ?? 0)
            var arr: [String] = []
            for i in 0..<len {
                if let el = value.atIndex(i) {
                    arr.append(el.isNull || el.isUndefined ? "" : (el.toString() ?? ""))
                }
            }
            return .stringList(arr)
        }
        if value.isObject {
            // 普通对象 -> jsObject 键值 map（值做浅转换）
            if let dict = value.toDictionary() as? [String: Any] {
                var m: [String: RuleValue] = [:]
                for (k, vv) in dict {
                    m[k] = JSEngine.anyToRuleValue(vv)
                }
                return .jsObject(m)
            }
            return .string(value.toString() ?? "")
        }
        return .string(value.toString() ?? "")
    }

    private static func anyToRuleValue(_ any: Any) -> RuleValue {
        switch any {
        case let s as String: return .string(s)
        case let b as Bool: return .bool(b)
        case let n as NSNumber:
            let t = String(cString: n.objCType)
            if t == "c" { return .bool(n.boolValue) }
            return .number(n.doubleValue)
        case let a as [Any]: return .stringList(a.map { String(describing: $0) })
        case is NSNull: return .null
        default: return .string(String(describing: any))
        }
    }
}

#endif
