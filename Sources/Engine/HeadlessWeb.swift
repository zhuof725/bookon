import Foundation

/// 无头 WebView 运行器：书源脚本里有一类写法依赖**浏览器环境**
/// （`document` / `window` / `DOMParser` / `fetch` / `XPathResult` / `atob`…），
/// JavaScriptCore 里没有这些全局对象，会直接 ReferenceError。
/// 原版 Legado 用内置浏览器 / `java.webView(...)` 跑这类脚本。
///
/// 这里只定义协议与注册点：
/// - App 启动时注入 `WKWebView` 实现（Sources/App/HeadlessWebViewRunner.swift）；
/// - CI / harness 不注入 → 自动降级为「不做 WebView 兜底」，不影响构建。
protocol HeadlessWebRunning: AnyObject {
    /// 装载 `html`（或 `url`）后执行 `js`，返回字符串结果；失败/超时返回 nil。
    /// 实现必须能从**后台线程**同步调用（内部自行切主线程 + 超时）。
    func run(html: String?, url: String?, js: String, timeout: TimeInterval) -> String?
}

enum HeadlessWeb {
    /// 由 App 启动时注入；弱引用，避免与单例互相持有。
    nonisolated(unsafe) static weak var runner: HeadlessWebRunning?

    static var isAvailable: Bool { runner != nil }

    /// 这些全局对象只有浏览器环境才有。
    private static let browserGlobals = [
        "document", "window", "domparser", "xmlhttprequest", "fetch",
        "location", "navigator", "localstorage", "sessionstorage",
        "xpathresult", "atob", "btoa", "queryselector", "getelementsbytagname",
        "createelement", "innerhtml"
    ]

    /// 只有「找不到浏览器全局对象」这一类错误才值得用 WebView 重跑；
    /// 普通的 TypeError（空值、字段不存在）重跑也没用，别浪费一次 WebView。
    static func needsBrowser(_ error: String) -> Bool {
        let e = error.lowercased()
        let isMissingGlobal = e.contains("referenceerror")
            || e.contains("can't find variable")
            || e.contains("is not defined")
        guard isMissingGlobal else { return false }
        return browserGlobals.contains { e.contains($0) }
    }
}
