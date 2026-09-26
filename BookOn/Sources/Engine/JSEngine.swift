import Foundation
import JavaScriptCore
import CryptoKit
import CommonCrypto

/// JavaScriptCore 引擎，注入 Legado 风格的 `java.*` 扩展与 `source/book/chapter/result/baseUrl` 变量。
final class JSEngine {
    let ctx: JSContext
    weak var analyzer: RuleAnalyzerContext?
    private var jsLibLoaded = false

    init() {
        ctx = JSContext()!
        ctx.exceptionHandler = { _, ex in
            Logger.log("JS 错误: \(ex?.toString() ?? "?")")
        }
        installJava()
        // 兼容 Rhino 常见写法
        ctx.evaluateScript("""
        var String = String; var JSON = JSON;
        if (typeof java === 'undefined') { var java = {}; }
        var console = { log: function(){ java.log([].slice.call(arguments).join(' ')); } };
        var Packages = {};
        var importPackage = function(){};
        var org = { jsoup: {} };
        """)
    }

    // MARK: eval

    @discardableResult
    func eval(_ js: String, result: Any? = nil, baseUrl: String? = nil) -> JSValue? {
        if let r = result { ctx.setObject(jsWrap(r), forKeyedSubscript: "result" as NSString) }
        else { ctx.setObject(NSNull(), forKeyedSubscript: "result" as NSString) }
        if let b = baseUrl { ctx.setObject(b, forKeyedSubscript: "baseUrl" as NSString) }
        let v = ctx.evaluateScript(js)
        if let v = v, v.isUndefined { return nil }
        return v
    }

    func evalString(_ js: String, result: Any? = nil, baseUrl: String? = nil) -> String? {
        guard let v = eval(js, result: result, baseUrl: baseUrl), !v.isNull, !v.isUndefined else { return nil }
        return JSEngine.stringify(v)
    }

    static func stringify(_ v: JSValue) -> String {
        if v.isString { return v.toString() }
        if v.isNumber {
            let d = v.toDouble()
            if d == d.rounded(), abs(d) < 1e15 { return String(Int64(d)) }
            return v.toString()
        }
        if v.isBoolean { return v.toBool() ? "true" : "false" }
        if v.isArray || v.isObject {
            if let obj = v.toObject(),
               let data = try? JSONSerialization.data(withJSONObject: obj, options: [.fragmentsAllowed]),
               let s = String(data: data, encoding: .utf8) { return s }
        }
        return v.toString()
    }

    private func jsWrap(_ any: Any) -> Any {
        if let s = any as? String { return s }
        if let d = any as? [String: Any] { return d }
        if let a = any as? [Any] { return a }
        return "\(any)"
    }

    func set(_ key: String, _ value: Any?) {
        ctx.setObject(value ?? NSNull(), forKeyedSubscript: key as NSString)
    }

    func loadJsLib(_ lib: String) {
        guard !lib.isEmpty, !jsLibLoaded else { return }
        jsLibLoaded = true
        ctx.evaluateScript(lib)
    }

    // MARK: java.*

    private func installJava() {
        let java = JSValue(newObjectIn: ctx)!

        func add(_ name: String, _ block: Any) { java.setObject(block, forKeyedSubscript: name as NSString) }

        // 网络
        let ajax: @convention(block) (JSValue) -> String = { url in
            var u = url.toString() ?? ""
            if url.isArray, let arr = url.toArray() as? [String], let f = arr.first { u = f }
            return HttpClient.shared.fetchSync(urlRule: u, source: self.analyzer?.source, js: self)?.text ?? ""
        }
        add("ajax", ajax)
        let ajaxAll: @convention(block) ([String]) -> [[String: Any]] = { urls in
            urls.map { u in
                let r = HttpClient.shared.fetchSync(urlRule: u, source: self.analyzer?.source, js: self)
                return ["body": r?.text ?? "", "url": r?.finalUrl ?? u, "code": r?.status ?? 0]
            }
        }
        add("ajaxAll", ajaxAll)
        let connect: @convention(block) (String, JSValue) -> JSValue = { url, _ in
            let r = HttpClient.shared.fetchSync(urlRule: url, source: self.analyzer?.source, js: self)
            return self.responseObject(r, url)
        }
        add("connect", connect)
        let getFn: @convention(block) (String, JSValue) -> JSValue = { urlOrKey, headers in
            if headers.isUndefined {
                return JSValue(object: self.analyzer?.get(urlOrKey) ?? "", in: self.ctx)
            }
            let h = (headers.toDictionary() as? [String: Any])?.mapValues { "\($0)" } ?? [:]
            let r = HttpClient.shared.fetchSync(url: urlOrKey, method: "GET", headers: h, body: nil, source: self.analyzer?.source)
            return self.responseObject(r, urlOrKey)
        }
        add("get", getFn)
        let post: @convention(block) (String, String, JSValue) -> JSValue = { url, body, headers in
            let h = (headers.toDictionary() as? [String: Any])?.mapValues { "\($0)" } ?? [:]
            let r = HttpClient.shared.fetchSync(url: url, method: "POST", headers: h, body: body, source: self.analyzer?.source)
            return self.responseObject(r, url)
        }
        add("post", post)
        let head: @convention(block) (String, JSValue) -> JSValue = { url, headers in
            let h = (headers.toDictionary() as? [String: Any])?.mapValues { "\($0)" } ?? [:]
            let r = HttpClient.shared.fetchSync(url: url, method: "HEAD", headers: h, body: nil, source: self.analyzer?.source)
            return self.responseObject(r, url)
        }
        add("head", head)
        let webView: @convention(block) (JSValue, JSValue, JSValue) -> String = { html, url, _ in
            // 无 WebView 执行环境，退化为直接请求
            if !url.isNull && !url.isUndefined, let u = url.toString(), !u.isEmpty {
                return HttpClient.shared.fetchSync(urlRule: u, source: self.analyzer?.source, js: self)?.text ?? ""
            }
            return html.isNull ? "" : (html.toString() ?? "")
        }
        add("webView", webView)

        // 编码
        add("base64Encode", { (s: String) -> String in Data(s.utf8).base64EncodedString() } as @convention(block) (String) -> String)
        add("base64Decode", { (s: String) -> String in
            var str = s.trimmingCharacters(in: .whitespacesAndNewlines)
            while str.count % 4 != 0 { str += "=" }
            return Data(base64Encoded: str, options: .ignoreUnknownCharacters).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        } as @convention(block) (String) -> String)
        add("base64DecodeToByteArray", { (s: String) -> [UInt8] in
            Data(base64Encoded: s, options: .ignoreUnknownCharacters).map { [UInt8]($0) } ?? []
        } as @convention(block) (String) -> [UInt8])
        add("encodeURI", { (s: String, enc: JSValue) -> String in
            let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+?#/:;,@$!'()*"))
            if !enc.isUndefined, let e = enc.toString()?.lowercased(), e.contains("gb") {
                return Encodings.percentEncodeGBK(s)
            }
            return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
        } as @convention(block) (String, JSValue) -> String)
        add("utf8ToGbk", { (s: String) -> String in Encodings.percentEncodeGBK(s) } as @convention(block) (String) -> String)
        add("hexDecodeToString", { (s: String) -> String in
            String(data: Encodings.hexToData(s), encoding: .utf8) ?? ""
        } as @convention(block) (String) -> String)
        add("hexEncodeToString", { (s: String) -> String in
            Data(s.utf8).map { String(format: "%02x", $0) }.joined()
        } as @convention(block) (String) -> String)
        add("strToBytes", { (s: String, cs: JSValue) -> [UInt8] in
            [UInt8](Encodings.encode(s, charset: cs.isUndefined ? "utf-8" : cs.toString()))
        } as @convention(block) (String, JSValue) -> [UInt8])
        add("bytesToStr", { (b: [Int], cs: JSValue) -> String in
            let data = Data(b.map { UInt8(truncatingIfNeeded: $0) })
            return Encodings.decode(data, charset: cs.isUndefined ? "utf-8" : cs.toString())
        } as @convention(block) ([Int], JSValue) -> String)

        // 摘要/加解密
        add("md5Encode", { (s: String) -> String in Crypto.md5(s) } as @convention(block) (String) -> String)
        add("md5Encode16", { (s: String) -> String in String(Crypto.md5(s).dropFirst(8).prefix(16)) } as @convention(block) (String) -> String)
        add("digestHex", { (alg: String, s: String) -> String in Crypto.digestHex(alg, s) } as @convention(block) (String, String) -> String)
        add("digestBase64Str", { (alg: String, s: String) -> String in Crypto.digestBase64(alg, s) } as @convention(block) (String, String) -> String)
        add("HMacHex", { (alg: String, key: String, s: String) -> String in Crypto.hmacHex(alg, key: key, s) } as @convention(block) (String, String, String) -> String)
        add("HMacBase64", { (alg: String, key: String, s: String) -> String in Crypto.hmacBase64(alg, key: key, s) } as @convention(block) (String, String, String) -> String)
        add("aesDecodeToString", { (s: String, key: String, mode: String, iv: String) -> String in
            Crypto.aes(Data(base64Encoded: s, options: .ignoreUnknownCharacters) ?? Encodings.hexToData(s), key: key, iv: iv, mode: mode, encrypt: false).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        } as @convention(block) (String, String, String, String) -> String)
        add("aesBase64DecodeToString", { (s: String, key: String, mode: String, iv: String) -> String in
            Crypto.aes(Data(base64Encoded: s, options: .ignoreUnknownCharacters) ?? Data(), key: key, iv: iv, mode: mode, encrypt: false).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        } as @convention(block) (String, String, String, String) -> String)
        add("aesEncodeToBase64String", { (s: String, key: String, mode: String, iv: String) -> String in
            Crypto.aes(Data(s.utf8), key: key, iv: iv, mode: mode, encrypt: true)?.base64EncodedString() ?? ""
        } as @convention(block) (String, String, String, String) -> String)
        add("aesEncodeToString", { (s: String, key: String, mode: String, iv: String) -> String in
            Crypto.aes(Data(s.utf8), key: key, iv: iv, mode: mode, encrypt: true)?.base64EncodedString() ?? ""
        } as @convention(block) (String, String, String, String) -> String)
        add("createSymmetricCrypto", { (transformation: String, key: JSValue, iv: JSValue) -> JSValue in
            Crypto.symmetricObject(self.ctx, transformation, key, iv)
        } as @convention(block) (String, JSValue, JSValue) -> JSValue)

        // 字符串工具
        add("timeFormat", { (t: Double) -> String in
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"
            return f.string(from: Date(timeIntervalSince1970: t / 1000))
        } as @convention(block) (Double) -> String)
        add("randomUUID", { () -> String in UUID().uuidString.lowercased() } as @convention(block) () -> String)
        add("htmlFormat", { (s: String) -> String in HtmlFormatter.format(s) } as @convention(block) (String) -> String)
        add("t2s", { (s: String) -> String in s.applyingTransform(.init("Hant-Hans"), reverse: false) ?? s } as @convention(block) (String) -> String)
        add("s2t", { (s: String) -> String in s.applyingTransform(.init("Hans-Hant"), reverse: false) ?? s } as @convention(block) (String) -> String)
        add("toNumChapter", { (s: JSValue) -> String in s.isNull ? "" : ChineseNumber.convertChapter(s.toString()) } as @convention(block) (JSValue) -> String)
        add("toURL", { (s: String) -> JSValue in
            let o = JSValue(newObjectIn: self.ctx)!
            let u = URL(string: s)
            o.setObject(u?.host ?? "", forKeyedSubscript: "host" as NSString)
            o.setObject(u?.path ?? "", forKeyedSubscript: "path" as NSString)
            o.setObject(u?.query ?? "", forKeyedSubscript: "query" as NSString)
            o.setObject(u?.scheme ?? "", forKeyedSubscript: "protocol" as NSString)
            return o
        } as @convention(block) (String) -> JSValue)

        // 日志/提示
        add("log", { (s: JSValue) -> JSValue in Logger.log("JS: \(s.toString() ?? "")"); return s } as @convention(block) (JSValue) -> JSValue)
        add("logType", { (s: JSValue) -> Void in Logger.log("JS type: \(s.toString() ?? "")") } as @convention(block) (JSValue) -> Void)
        add("toast", { (s: JSValue) -> Void in Logger.log("toast: \(s.toString() ?? "")") } as @convention(block) (JSValue) -> Void)
        add("longToast", { (s: JSValue) -> Void in Logger.log("toast: \(s.toString() ?? "")") } as @convention(block) (JSValue) -> Void)

        // 变量存取（映射到 analyzer）
        add("put", { (k: String, v: JSValue) -> String in
            let s = JSEngine.stringify(v); self.analyzer?.put(k, s); return s
        } as @convention(block) (String, JSValue) -> String)
        add("getString", { (rule: String, content: JSValue) -> String in
            self.analyzer?.jsGetString(rule, content: content.isUndefined || content.isNull ? nil : content.toObject()) ?? ""
        } as @convention(block) (String, JSValue) -> String)
        add("getStringList", { (rule: String, content: JSValue) -> [String] in
            self.analyzer?.jsGetStringList(rule, content: content.isUndefined || content.isNull ? nil : content.toObject()) ?? []
        } as @convention(block) (String, JSValue) -> [String])
        add("getElements", { (rule: String) -> [String] in
            self.analyzer?.getElementsHtml(rule) ?? []
        } as @convention(block) (String) -> [String])
        add("getElement", { (rule: String) -> String in
            self.analyzer?.getElementsHtml(rule).first ?? ""
        } as @convention(block) (String) -> String)
        add("setContent", { (c: JSValue, base: JSValue) -> Void in
            self.analyzer?.jsSetContent(c.toObject(), baseUrl: base.isUndefined || base.isNull ? nil : base.toString())
        } as @convention(block) (JSValue, JSValue) -> Void)
        add("getCookie", { (tag: String, key: JSValue) -> String in
            CookieStore.shared.cookieString(for: tag, key: key.isUndefined || key.isNull ? nil : key.toString())
        } as @convention(block) (String, JSValue) -> String)
        add("getVerificationCode", { (_: String) -> String in "" } as @convention(block) (String) -> String)
        add("startBrowser", { (_: String, _: String) -> Void in } as @convention(block) (String, String) -> Void)
        add("getWebViewUA", { () -> String in HttpClient.defaultUA } as @convention(block) () -> String)
        add("androidId", { () -> String in "bookon-ios" } as @convention(block) () -> String)

        ctx.setObject(java, forKeyedSubscript: "java" as NSString)
        // cache 对象
        ctx.evaluateScript("""
        var cache = { _m:{}, put:function(k,v){ this._m[k]=String(v); return v; }, get:function(k){ return this._m[k]===undefined?null:this._m[k]; },
                      delete:function(k){ delete this._m[k]; }, getInt:function(k){ return parseInt(this._m[k]); }, getFromMemory:function(k){ return this.get(k);} };
        """)
    }

    private func responseObject(_ r: HttpResponse?, _ url: String) -> JSValue {
        let o = JSValue(newObjectIn: ctx)!
        let body = r?.text ?? ""
        let bodyBlock: @convention(block) () -> String = { body }
        let codeBlock: @convention(block) () -> Int = { r?.status ?? 0 }
        let urlBlock: @convention(block) () -> String = { r?.finalUrl ?? url }
        let headersBlock: @convention(block) () -> [String: String] = { r?.headers ?? [:] }
        let headerBlock: @convention(block) (String) -> String = { k in r?.headers.first { $0.key.lowercased() == k.lowercased() }?.value ?? "" }
        let bytesBlock: @convention(block) () -> [UInt8] = { r.map { [UInt8]($0.data) } ?? [] }
        o.setObject(bodyBlock, forKeyedSubscript: "body" as NSString)
        o.setObject(codeBlock, forKeyedSubscript: "code" as NSString)
        o.setObject(urlBlock, forKeyedSubscript: "url" as NSString)
        o.setObject(headersBlock, forKeyedSubscript: "headers" as NSString)
        o.setObject(headerBlock, forKeyedSubscript: "header" as NSString)
        o.setObject(bytesBlock, forKeyedSubscript: "bytes" as NSString)
        o.setObject(bodyBlock, forKeyedSubscript: "toString" as NSString)
        let raw = JSValue(newObjectIn: ctx)!
        raw.setObject(bodyBlock, forKeyedSubscript: "body" as NSString)
        raw.setObject(codeBlock, forKeyedSubscript: "code" as NSString)
        o.setObject(raw, forKeyedSubscript: "raw" as NSString)
        return o
    }
}

/// AnalyzeRule 提供给 JS 的回调接口
protocol RuleAnalyzerContext: AnyObject {
    var source: BookSource? { get }
    func put(_ key: String, _ value: String)
    func get(_ key: String) -> String
    func jsGetString(_ rule: String, content: Any?) -> String
    func jsGetStringList(_ rule: String, content: Any?) -> [String]
    func getElementsHtml(_ rule: String) -> [String]
    func jsSetContent(_ content: Any?, baseUrl: String?)
}

enum Logger {
    static var lines: [String] = []
    static func log(_ s: String) {
        #if DEBUG
        print(s)
        #endif
        DispatchQueue.main.async {
            lines.append("[\(Date().formatted(date: .omitted, time: .standard))] \(s)")
            if lines.count > 500 { lines.removeFirst(lines.count - 500) }
        }
    }
}
