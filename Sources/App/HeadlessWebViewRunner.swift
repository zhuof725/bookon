import Foundation
import WebKit

/// 无头 WKWebView：给依赖 `document` / `fetch` / `DOMParser` 的书源脚本兜底执行。
///
/// 引擎（Sources/Engine/HeadlessWeb.swift）只认协议，不直接依赖 WebKit：
/// - App 启动时 `install()` 注入；
/// - CI / 测试 harness 不注入 → 相关能力自动降级。
final class HeadlessWebViewRunner: NSObject, HeadlessWebRunning {
    static let shared = HeadlessWebViewRunner()

    static func install() {
        HeadlessWeb.runner = shared
    }

    /// 引擎在后台线程调用；这里阻塞等主线程的 WebView 结果（带硬超时，绝不永久阻塞）。
    func run(html: String?, url: String?, js: String, timeout: TimeInterval) -> String? {
        guard !Thread.isMainThread else { return nil }
        let semaphore = DispatchSemaphore(value: 0)
        var output: String?
        DispatchQueue.main.async {
            HeadlessWebSession(html: html, url: url, js: js, timeout: timeout) { value in
                output = value
                semaphore.signal()
            }
        }
        _ = semaphore.wait(timeout: .now() + timeout + 2)
        return output
    }
}

/// 一次性的 WebView 会话：每次调用新建，避免页面状态串到下一次规则。
private final class HeadlessWebSession: NSObject, WKNavigationDelegate {
    private var webView: WKWebView?
    private let js: String
    private let completion: (String?) -> Void
    private var finished = false

    /// 自己在飞行期间保活（WKWebView 的代理是弱引用）。
    private static var retained: [HeadlessWebSession] = []

    init(html: String?, url: String?, js: String, timeout: TimeInterval,
         completion: @escaping (String?) -> Void) {
        self.js = js
        self.completion = completion
        super.init()
        HeadlessWebSession.retained.append(self)

        let config = WKWebViewConfiguration()
        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 375, height: 667), configuration: config)
        wv.navigationDelegate = self
        webView = wv

        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            self?.finish(nil)
        }

        if let html, !html.isEmpty {
            wv.loadHTMLString(html, baseURL: url.flatMap { URL(string: $0) })
        } else if let url, let u = URL(string: url), ["http", "https"].contains(u.scheme?.lowercased() ?? "") {
            wv.load(URLRequest(url: u))
        } else {
            finish(nil)
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // 页面自身的脚本可能还在跑（SPA/懒加载）：等一拍再求值。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.evaluate()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(nil)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(nil)
    }

    // MARK: - 执行

    private func evaluate() {
        guard let webView, !finished else { return }
        webView.evaluateJavaScript(js) { [weak self] value, error in
            guard let self, !self.finished else { return }
            if let s = value as? String {
                self.finish(s)
            } else if let n = value as? NSNumber {
                self.finish(n.stringValue)
            } else if let list = value as? [Any] {
                self.finish(list.map { "\($0)" }.joined(separator: "\n"))
            } else if let dict = value as? [String: Any],
                      let data = try? JSONSerialization.data(withJSONObject: dict),
                      let text = String(data: data, encoding: .utf8) {
                self.finish(text)
            } else {
                // 脚本没有返回值且无错误：当作空结果（不是失败）
                self.finish(error == nil ? "" : nil)
            }
        }
    }

    private func finish(_ value: String?) {
        guard !finished else { return }
        finished = true
        completion(value)
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView = nil
        HeadlessWebSession.retained.removeAll { $0 === self }
    }
}
