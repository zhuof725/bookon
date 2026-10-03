//
//  JsExtensionsRuntime.swift
//  LegadoBookSource
//
//  Step 5：java.xxx 的运行时分发。JS 侧通过 `__call(name, args)` 请求；
//  这里按 JsExtensionsCatalog.implemented 把调用路由到：
//    - AnalyzeRule 自有方法（桥接闭包，由 AnalyzeRule 注入）
//    - 纯算法 JsExtensionsCore
//    - JsUIProvider / JsNetworkExtensionsProvider / WebJSProvider（依赖注入）
//  unhandled（未实现）方法不应到达这里（JS Proxy 已拦截），防御性返回 ok:false。
//

import Foundation

/// 一次 `__call` 的返回：JS wrapper 根据 ok 决定返回 value 或 throw。
struct JsCallResult {
    let ok: Bool
    let value: Any?
    let error: String?
}

final class JsExtensionsRuntime {
    private let diagnostics: RuleEngineDiagnostics?
    private let uiProvider: JsUIProvider
    private let networkProvider: JsNetworkExtensionsProvider
    private let webJSProvider: WebJSProvider

    // AnalyzeRule 自有方法桥接（与 JSJavaBridge 现有闭包同源，由 AnalyzeRule 注入）
    var putFn: (String, String) -> String = { _, v in v }
    var getFn: (String) -> String = { _ in "" }
    var getStringFn: (String) -> String = { _ in "" }
    var getStringListFn: (String) -> [String] = { _ in [] }
    var getElementFn: (String) -> String = { _ in "" }
    var getElementsFn: (String) -> [String] = { _ in [] }
    var ajaxFn: (String) -> String = { url in "ajax(\(url)) error\n未实现" }
    var logFn: (String) -> String = { s in s }
    var getSourceKeyFn: () -> String? = { nil }
    var getTagFn: () -> String? = { nil }
    /// Kotlin JsExtensions.getCookie(tag,key?) 从 CookieStore 读取（JS 绑定里另有 cookie 对象）。
    var cookieStore: CookieStoreProtocol = InMemoryCookieStore()

    init(diagnostics: RuleEngineDiagnostics?,
         uiProvider: JsUIProvider = UnsupportedJsUIProvider(),
         networkProvider: JsNetworkExtensionsProvider = UnsupportedJsNetworkExtensionsProvider(),
         webJSProvider: WebJSProvider = UnsupportedWebJSProvider()) {
        self.diagnostics = diagnostics
        self.uiProvider = uiProvider
        self.networkProvider = networkProvider
        self.webJSProvider = webJSProvider
    }

    /// 供 JS `__call` 调用的统一入口。参数已由桥接层解析为 [Any?]（NSNumber/NSNull/String/NSArray/NSDictionary）。
    func call(_ name: String, arguments: [Any?]) -> JsCallResult {
        do {
            switch name {
            // MARK: AnalyzeRule 自有
            case "put":
                return ok(try putFn(stringArg(arguments, 0), stringArg(arguments, 1)))
            case "get":
                return ok(getFn(stringArg(arguments, 0)))
            case "getString":
                return ok(getStringFn(stringArg(arguments, 0)))
            case "getStringList":
                return ok(getStringListFn(stringArg(arguments, 0)))
            case "getElement":
                return ok(getElementFn(stringArg(arguments, 0)))
            case "getElements":
                return ok(getElementsFn(stringArg(arguments, 0)))
            case "ajax":
                return ok(ajaxFn(stringArg(arguments, 0)))
            case "log":
                return ok(logFn(stringArg(arguments, 0)))
            case "getSource":
                return ok(getSourceKeyFn())
            case "getTag":
                return ok(getTagFn())
            case "getCookie":
                // Kotlin getCookie(tag, key?)：以参数0为 key 从 CookieStore 读取（真实书源未用到，
                // 语义按 CookieStoreProtocol.getCookie(url) 提供）。
                return ok(cookieStore.getCookie(stringArg(arguments, 0)))

            // MARK: 纯算法
            case "md5Encode":
                return ok(JsExtensionsCore.md5Encode(stringArg(arguments, 0)))
            case "md5Encode16":
                return ok(JsExtensionsCore.md5Encode16(stringArg(arguments, 0)))
            case "t2s":
                return ok(JsExtensionsCore.t2s(stringArg(arguments, 0)))
            case "s2t":
                return ok(JsExtensionsCore.s2t(stringArg(arguments, 0)))
            case "timeFormat":
                return ok(JsExtensionsCore.timeFormat(int64Arg(arguments, 0)))
            case "timeFormatUTC":
                return ok(JsExtensionsCore.timeFormatUTC(int64Arg(arguments, 0),
                                                        format: stringArg(arguments, 1),
                                                        offsetMilliseconds: intArg(arguments, 2)))
            case "base64Encode":
                return ok(JsExtensionsCore.base64Encode(stringArg(arguments, 0)))
            case "base64Decode":
                return ok(try JsExtensionsCore.base64Decode(arguments.first as? String))
            case "base64DecodeToByteArray":
                return ok(JsExtensionsCore.base64DecodeToByteArray(arguments.first as? String) ?? [])
            case "hexDecodeToString":
                return ok(try JsExtensionsCore.hexDecodeToString(stringArg(arguments, 0)))
            case "hexEncodeToString":
                return ok(JsExtensionsCore.hexEncodeToString(stringArg(arguments, 0)))
            case "hexDecodeToByteArray":
                return ok(JsExtensionsCore.hexDecodeToByteArray(stringArg(arguments, 0)) ?? [])
            case "htmlFormat":
                return ok(JsExtensionsCore.htmlFormat(stringArg(arguments, 0)))
            case "encodeURI":
                return ok(JsExtensionsCore.encodeURI(stringArg(arguments, 0)))
            case "randomUUID":
                return ok(JsExtensionsCore.randomUUID())
            case "toNumChapter":
                return ok(JsExtensionsCore.toNumChapter(arguments.first as? String))
            case "strToBytes":
                return ok(try JsExtensionsCore.strToBytes(stringArg(arguments, 0),
                                                         charset: arguments.count > 1 ? stringArg(arguments, 1) : "UTF-8"))
            case "bytesToStr":
                return ok(try JsExtensionsCore.bytesToStr(bytesArg(arguments, 0),
                                                         charset: arguments.count > 1 ? stringArg(arguments, 1) : "UTF-8"))

            // MARK: UI / 系统（协议注入，默认 unsupported）
            case "toast", "longToast", "openUrl", "startBrowser", "startBrowserAwait", "getVerificationCode":
                return ok(try uiProvider.invoke(method: name, arguments: arguments.map { stringify($0) }))
            case "webView":
                // Kotlin webView(html,url,js,cacheFirst)。优先走 WebJSProvider（真实实现留第 6 步），
                // 不可用时回退 JsUIProvider（默认 unsupported）。
                let html = stringArg(arguments, 0), url = stringArg(arguments, 1), js = stringArg(arguments, 2)
                do {
                    return ok(try webJSProvider.eval(js: js, result: html, baseUrl: url))
                } catch {
                    diagnostics?.record(source: "JsExtensionsRuntime.webView", rule: name, message: "\(error)")
                    return ok(try uiProvider.invoke(method: name, arguments: [html, url, js]))
                }

            // MARK: 网络 / 文件（协议注入，默认 unsupported）
            case "get", "post", "head", "ajaxAll", "connect", "cacheFile", "downloadFile":
                return ok(try networkProvider.invoke(method: name, arguments: arguments.map { stringify($0) }))

            default:
                let message = "java.\(name) 尚未实现（JsExtensions 未处理，第 5 步范围外）"
                diagnostics?.record(source: "JsExtensionsRuntime.call", rule: name, message: message)
                return JsCallResult(ok: false, value: nil, error: message)
            }
        } catch let error as RuleEngineError {
            diagnostics?.record(source: "JsExtensionsRuntime.call", rule: name, error: error)
            return JsCallResult(ok: false, value: nil, error: error.errorDescription ?? "\(error)")
        } catch {
            diagnostics?.record(source: "JsExtensionsRuntime.call", rule: name, message: "\(error)")
            return JsCallResult(ok: false, value: nil, error: "\(error)")
        }
    }

    private func ok(_ value: Any?) -> JsCallResult { JsCallResult(ok: true, value: value, error: nil) }

    // MARK: - 同名方法（供 verify_functions 自动提取覆盖 + 直接调用/diagnostics 测试）
    // Kotlin 签名：fun toast(msg: Any?) / longToast / openUrl(url, mimeType?) /
    // startBrowser(url,title) / startBrowserAwait(url,title,refetch?) / getVerificationCode(imageUrl) /
    // webView(html,url,js,cacheFirst?) / get/post/head/connect/cacheFile/downloadFile/ajaxAll

    func toast(_ message: String) throws { _ = try uiProvider.invoke(method: "toast", arguments: [message]) }
    func longToast(_ message: String) throws { _ = try uiProvider.invoke(method: "longToast", arguments: [message]) }
    func openUrl(_ url: String) throws { _ = try uiProvider.invoke(method: "openUrl", arguments: [url]) }
    func startBrowser(_ url: String, title: String) throws { _ = try uiProvider.invoke(method: "startBrowser", arguments: [url, title]) }
    func startBrowserAwait(_ url: String, title: String) throws -> String? {
        try uiProvider.invoke(method: "startBrowserAwait", arguments: [url, title])
    }
    func getVerificationCode(_ imageUrl: String) throws -> String {
        try uiProvider.invoke(method: "getVerificationCode", arguments: [imageUrl]) ?? ""
    }
    func webView(_ html: String, url: String?, js: String) throws -> String? {
        try webJSProvider.eval(js: js, result: html, baseUrl: url)
    }
    func get(_ url: String) throws -> String? { try networkProvider.invoke(method: "get", arguments: [url]) }
    func post(_ url: String, body: String) throws -> String? { try networkProvider.invoke(method: "post", arguments: [url, body]) }
    func head(_ url: String) throws -> String? { try networkProvider.invoke(method: "head", arguments: [url]) }
    func ajaxAll(_ urls: [String]) throws -> String? { try networkProvider.invoke(method: "ajaxAll", arguments: urls) }
    func connect(_ url: String) throws -> String? { try networkProvider.invoke(method: "connect", arguments: [url]) }
    func cacheFile(_ url: String) throws -> String? { try networkProvider.invoke(method: "cacheFile", arguments: [url]) }
    func downloadFile(_ url: String) throws -> String? { try networkProvider.invoke(method: "downloadFile", arguments: [url]) }

    // MARK: - 纯算法同名包装（供 verify_functions 直接匹配同名 func）

    func md5Encode(_ input: String) -> String { JsExtensionsCore.md5Encode(input) }
    func md5Encode16(_ input: String) -> String { JsExtensionsCore.md5Encode16(input) }
    func t2s(_ input: String) -> String { JsExtensionsCore.t2s(input) }
    func s2t(_ input: String) -> String { JsExtensionsCore.s2t(input) }
    func timeFormat(_ milliseconds: Int64) -> String { JsExtensionsCore.timeFormat(milliseconds) }
    func timeFormatUTC(_ time: Int64, format: String, sh: Int) -> String? {
        JsExtensionsCore.timeFormatUTC(time, format: format, offsetMilliseconds: sh)
    }
    func base64Encode(_ input: String) -> String? { JsExtensionsCore.base64Encode(input) }
    func base64Decode(_ input: String?) -> String { (try? JsExtensionsCore.base64Decode(input)) ?? "" }
    func base64DecodeToByteArray(_ input: String?) -> [UInt8]? { JsExtensionsCore.base64DecodeToByteArray(input) }
    func hexDecodeToString(_ hex: String) -> String? { try? JsExtensionsCore.hexDecodeToString(hex) }
    func hexEncodeToString(_ utf8: String) -> String? { JsExtensionsCore.hexEncodeToString(utf8) }
    func hexDecodeToByteArray(_ hex: String) -> [UInt8]? { JsExtensionsCore.hexDecodeToByteArray(hex) }
    func htmlFormat(_ input: String) -> String { JsExtensionsCore.htmlFormat(input) }
    func encodeURI(_ input: String) -> String { JsExtensionsCore.encodeURI(input) }
    func randomUUID() -> String { JsExtensionsCore.randomUUID() }
    func toNumChapter(_ input: String?) -> String? { JsExtensionsCore.toNumChapter(input) }
    func strToBytes(_ input: String) -> [UInt8] { (try? JsExtensionsCore.strToBytes(input)) ?? [] }
    func bytesToStr(_ bytes: [UInt8]) -> String { (try? JsExtensionsCore.bytesToStr(bytes)) ?? "" }
    func getCookie(_ tag: String) -> String { cookieStore.getCookie(tag) }

    private func stringArg(_ args: [Any?], _ index: Int) -> String {
        guard index < args.count, let v = args[index] else { return "" }
        return stringify(v)
    }

    private func int64Arg(_ args: [Any?], _ index: Int) -> Int64 {
        guard index < args.count, let n = args[index] as? NSNumber else { return 0 }
        return n.int64Value
    }

    private func intArg(_ args: [Any?], _ index: Int) -> Int {
        guard index < args.count, let n = args[index] as? NSNumber else { return 0 }
        return n.intValue
    }

    private func bytesArg(_ args: [Any?], _ index: Int) -> [UInt8] {
        guard index < args.count else { return [] }
        if let data = args[index] as? Data { return Array(data) }
        if let array = args[index] as? [Any] {
            return array.compactMap { ($0 as? NSNumber)?.uint8Value }
        }
        return []
    }

    private func stringify(_ value: Any?) -> String {
        guard let value else { return "" }
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return "\(number)" }
        if let array = value as? [Any] { return array.map { stringify($0) }.joined(separator: ",") }
        if let dict = value as? [String: Any] { return "\(dict)" }
        if value is NSNull { return "" }
        return "\(value)"
    }
}
