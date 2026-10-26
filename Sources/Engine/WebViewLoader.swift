import Foundation

/// 教程「URL必知必会」中的 {"webView":true} 与 ruleContent.webJs：
/// 用 WKWebView 加载网页、执行 JS 后取源码；遇到 Cloudflare 等人机验证时，
/// 先在后台等待自动通过，不行再弹出网页让用户手动验证，并把 Cookie 同步给 URLSession。
enum WebViewSupport {
    /// 判断 Cookie 的 domain 是否属于目标主机（含父域，如 .a.com 属于 www.a.com）。不依赖 UIKit，便于离线测试。
    static func cookieDomain(_ domain: String, matches host: String) -> Bool {
        let d = domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let h = host.lowercased()
        return !d.isEmpty && (h == d || h.hasSuffix("." + d))
    }

    /// 与 WebView 保持一致的 UA，cf_clearance 等 Cookie 与 UA 绑定
    static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    /// 判断返回内容是否是人机验证页
    static func isChallenge(_ html: String) -> Bool {
        let head = String(html.prefix(6000))
        let marks = ["<title>Just a moment", "challenges.cloudflare.com", "cf-browser-verification",
                     "__gatekeeper_challenge", "_cf_chl_opt", "<title>Redirecting...", "Attention Required! | Cloudflare",
                     "TCaptcha.js", "__captcha", "WafCaptcha", "captcha.qq.com"]
        return marks.contains { head.contains($0) }
    }

    /// 站点首个请求只下发会话/WAF Cookie、正文却是「找不到内容」时，带着 Cookie 重发一次即可。
    /// 三八小说（waf_sc + server_name_session）就是这种形态：第一次 POST 返回错误页，
    /// 第二次带 Cookie 才跳到真实搜索结果。只在小体积错误页上触发，正常页面不受影响。
    static func isSessionCookieErrorPage(_ html: String, status: Int) -> Bool {
        guard (200..<300).contains(status), html.count < 8000 else { return false }
        let marks = ["错误提示", "找不到您要搜索的内容", "访问验证", "安全验证", "请稍候",
                     "您的访问出错了", "访问过于频繁", "请开启JavaScript", "Just a moment"]
        return marks.contains { html.contains($0) }
    }
}

#if canImport(UIKit) && canImport(WebKit)
import UIKit
import WebKit

@MainActor
final class WebViewLoader: NSObject, WKNavigationDelegate {
    /// 由 UI 层设置：需要用户手动验证时调用，返回验证后的网页源码
    static var interactiveHandler: ((WKWebView) async -> String?)?

    private let webView: WKWebView
    private var loadedOnce = false

    private override init() {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: cfg)
        super.init()
        webView.customUserAgent = WebViewSupport.userAgent
        webView.navigationDelegate = self
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in self.loadedOnce = true }
    }

    /// 加载网页并返回 (源码, 最终URL)。js 为空时返回 document.documentElement.outerHTML
    static func load(url: String, method: String = "GET", body: String? = nil,
                     headers: [String: String] = [:], js: String? = nil,
                     timeout: Double = 25, allowInteractive: Bool = true, cookieJar: Bool = true) async throws -> (String, String) {
        guard let u = URL(string: url) else { throw URLError(.badURL) }
        let loader = WebViewLoader()
        if let agent = headers.first(where: { $0.key.lowercased() == "user-agent" })?.value {
            loader.webView.customUserAgent = agent
        }
        if cookieJar { await syncCookiesToWebView(for: u) }
        var req = URLRequest(url: u, timeoutInterval: timeout)
        req.httpMethod = method
        for (k, v) in headers where k.lowercased() != "user-agent" { req.setValue(v, forHTTPHeaderField: k) }
        if let b = body {
            req.httpBody = b.data(using: .utf8)
            if req.value(forHTTPHeaderField: "Content-Type") == nil {
                req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            }
        }
        if let win = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.windows.first }).first {
            loader.webView.alpha = 0.01
            loader.webView.isUserInteractionEnabled = false
            win.insertSubview(loader.webView, at: 0)
        }
        defer { loader.webView.stopLoading(); loader.webView.removeFromSuperview() }
        loader.webView.load(req)

        let deadline = Date().addingTimeInterval(timeout)
        var html = ""
        while Date() < deadline {
            try await Task.sleep(nanoseconds: 800_000_000)
            if !loader.loadedOnce { continue }
            html = await loader.source(js: nil)
            if !WebViewSupport.isChallenge(html), !html.isEmpty { break }
        }
        var finalUrl = loader.webView.url?.absoluteString ?? url
        if WebViewSupport.isChallenge(html), allowInteractive, let handler = interactiveHandler {
            if let h = await handler(loader.webView) { html = h }
            finalUrl = loader.webView.url?.absoluteString ?? url
        }
        await syncCookiesFromWebView(host: u.host, enabled: cookieJar)
        if !WebViewSupport.isChallenge(html) { WebViewLoader.markCleared(host: u.host) }
        if let js = js, !js.isEmpty, !WebViewSupport.isChallenge(html) {
            let r = await loader.source(js: js)
            if !r.isEmpty { html = r }
        } else if !WebViewSupport.isChallenge(html) {
            // WKWebView 展示 JSON 时返回的 outerHTML 包含 <pre>，使用纯文本还原 API 响应。
            let plain = await loader.source(js: "document.body ? document.body.innerText : ''")
            if let data = plain.data(using: .utf8), (try? JSONSerialization.jsonObject(with: data)) != nil {
                html = plain
            }
        }
        return (html, finalUrl)
    }

    private func source(js: String?) async -> String {
        let script = (js?.isEmpty == false) ? js! : "document.documentElement.outerHTML"
        return await withCheckedContinuation { c in
            webView.evaluateJavaScript(script) { v, _ in
                if let s = v as? String { c.resume(returning: s) }
                else if let v = v { c.resume(returning: "\(v)") }
                else { c.resume(returning: "") }
            }
        }
    }

    // MARK: 已通过验证的主机（短窗口内不再反复弹 Cloudflare 验证）

nonisolated private static let clearedLock = NSLock()
private nonisolated(unsafe) static var clearedHosts: [String: Date] = [:]
/// 通过时间上限：2 小时（cf_clearance 通常有效约 30–60 分钟，宽松给），
/// 期间同主机请求只带 Cookie 重试，不再起 WebView。
nonisolated private static let clearedWindow: TimeInterval = 2 * 3600

nonisolated static func markCleared(host: String?) {
    guard let host, !host.isEmpty else { return }
    clearedLock.lock(); clearedHosts[host] = Date(); clearedLock.unlock()
}

nonisolated static func recentlyCleared(host: String?) -> Bool {
    guard let host, !host.isEmpty else { return false }
    clearedLock.lock(); defer { clearedLock.unlock() }
    guard let when = clearedHosts[host] else { return false }
    return Date().timeIntervalSince(when) < clearedWindow
}

// MARK: Cookie 同步

    /// 把 WebView 里的 Cookie 回流到共享存储。
    /// - host 非空时只回流与该主机相关的 Cookie，避免把无关站点的 Cookie 带进来。
    /// - enabled=false（书源关闭 Cookie 保存）时不回流。
    static func syncCookiesFromWebView(host: String? = nil, enabled: Bool = true) async {
        guard enabled else { return }
        let store = WKWebsiteDataStore.default().httpCookieStore
        let cookies: [HTTPCookie] = await withCheckedContinuation { c in store.getAllCookies { c.resume(returning: $0) } }
        for ck in cookies {
            if let h = host, !WebViewSupport.cookieDomain(ck.domain, matches: h) { continue }
            HTTPCookieStorage.shared.setCookie(ck)
        }
    }

    static func syncCookiesToWebView(for url: URL) async {
        let store = WKWebsiteDataStore.default().httpCookieStore
        for ck in HTTPCookieStorage.shared.cookies(for: url) ?? [] {
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in store.setCookie(ck) { c.resume() } }
        }
    }
}
#endif
