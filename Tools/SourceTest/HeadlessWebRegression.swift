import Foundation

/// 无头 WebView 兜底回归。
///
/// 依赖 `document` / `fetch` / `DOMParser` 的书源脚本在 JavaScriptCore 里必然 ReferenceError。
/// App 注入 WKWebView 实现后要能自动重跑；CI/harness 不注入时必须安静降级。
enum HeadlessWebRegression {
    final class MockRunner: HeadlessWebRunning {
        var calls = 0
        var lastJS = ""
        var lastHTML: String?
        func run(html: String?, url: String?, js: String, timeout: TimeInterval) -> String? {
            calls += 1
            lastJS = js
            lastHTML = html
            return "<span class=\"from-webview\">OK</span>"
        }
    }

    static func run(_ check: (Bool, String) -> Void) {
        check(HeadlessWeb.needsBrowser("ReferenceError: Can't find variable: document"),
              "识别依赖浏览器环境的脚本（document）")
        check(HeadlessWeb.needsBrowser("ReferenceError: Can't find variable: fetch"),
              "识别依赖浏览器环境的脚本（fetch）")
        check(!HeadlessWeb.needsBrowser("TypeError: undefined is not an object (evaluating 'a.b')"),
              "普通 TypeError 不触发 WebView 兜底")
        check(!HeadlessWeb.isAvailable, "未注入实现时自动降级（CI/harness）")

        let mock = MockRunner()
        HeadlessWeb.runner = mock
        check(HeadlessWeb.isAvailable, "注入后 WebView 兜底可用")

        // document 脚本：在后台线程求值（引擎的兜底要求不在主线程）
        var out: String?
        let semaphore = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            let ar = AnalyzeRule(content: "<html><body><p>hi</p></body></html>",
                                 baseUrl: "https://example.invalid/", context: RuleContext())
            out = ar.getString("<js>document.querySelector('p').textContent</js>")
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 10)
        check(mock.calls == 1, "document 脚本触发一次 WebView 兜底")
        check((out ?? "").contains("from-webview"), "兜底结果回传给规则（实际 \(out ?? "nil")）")
        check((mock.lastHTML ?? "").contains("<p>hi</p>"), "当前内容作为 DOM 传给 WebView")
        check(mock.lastJS.contains("querySelector"), "原脚本原样交给 WebView")

        // java.webView(html, url, js) 显式调用
        let mock2 = MockRunner()
        HeadlessWeb.runner = mock2
        var webOut: String?
        let semaphore2 = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            webOut = JSEngine.shared.evalString("java.webView('<html></html>', '', 'document.title')")
            semaphore2.signal()
        }
        _ = semaphore2.wait(timeout: .now() + 10)
        check(mock2.calls == 1, "java.webView 走无头 WebView")
        check(webOut?.contains("from-webview") == true, "java.webView 返回 WebView 结果")

        // 主线程上也要能兜底（App 的调试页/阅读流程都在主线程跑规则）
        let mock3 = MockRunner()
        HeadlessWeb.runner = mock3
        let mainOut = AnalyzeRule(content: "<html><body><p>main</p></body></html>",
                                  baseUrl: "https://example.invalid/", context: RuleContext())
            .getString("<js>document.querySelector('p').textContent</js>")
        check(mock3.calls == 1, "主线程上同样触发 WebView 兜底")
        check(mainOut.contains("from-webview"), "主线程兜底结果回传（实际 \(mainOut)）")

        HeadlessWeb.runner = nil
    }
}
