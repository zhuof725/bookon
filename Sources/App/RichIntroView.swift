import SwiftUI
import UIKit
import WebKit

/// `<useweb>` / `<usehtml>` 简介：书源直接给 HTML（含内联 CSS、SVG 图标），
/// 原版用 WebView 渲染，这里同样交给 WKWebView。
///
/// - 高度随内容自适应（外层 ScrollView 负责滚动，WebView 自身不滚动）
/// - 文字颜色跟随当前主题（书源样式用的是 `inherit` / `currentColor` / 半透明灰）
/// - 链接不在简介里跳转，交给系统浏览器
struct RichIntroWebView: UIViewRepresentable {
    let html: String
    let textColor: Color
    let secondaryColor: Color
    @Binding var height: CGFloat

    @Environment(\.colorScheme) private var scheme

    func makeCoordinator() -> Coordinator { Coordinator(height: $height) }

    func makeUIView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: Coordinator.heightHandler)
        let config = WKWebViewConfiguration()
        config.userContentController = controller
        config.suppressesIncrementalRendering = false
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.isScrollEnabled = false
        web.scrollView.backgroundColor = .clear
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.setContentHuggingPriority(.required, for: .vertical)
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        let document = Self.document(html: html,
                                     textColor: Self.css(textColor, scheme: scheme),
                                     secondaryColor: Self.css(secondaryColor, scheme: scheme))
        // 主题/内容不变时不重新加载，否则每次继电器刷新都会闪一下。
        guard context.coordinator.loaded != document else { return }
        context.coordinator.loaded = document
        web.loadHTMLString(document, baseURL: nil)
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        static let heightHandler = "introHeight"
        var loaded: String?
        private let heightBinding: Binding<CGFloat>

        init(height: Binding<CGFloat>) { heightBinding = height }

        func userContentController(_ controller: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard let number = message.body as? NSNumber else { return }
            apply(CGFloat(number.doubleValue))
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.evaluateJavaScript(RichIntroWebView.heightScript) { [weak self] value, _ in
                guard let number = value as? NSNumber else { return }
                self?.apply(CGFloat(number.doubleValue))
            }
        }

        /// 简介里的链接交给系统浏览器，避免 WebView 变成第二层导航。
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard action.navigationType == .linkActivated, let url = action.request.url,
                  !url.absoluteString.hasPrefix("about:") else {
                decisionHandler(.allow)
                return
            }
            decisionHandler(.cancel)
            UIApplication.shared.open(url)
        }

        private func apply(_ value: CGFloat) {
            let clamped = max(1, value.rounded(.up))
            guard abs(clamped - heightBinding.wrappedValue) > 0.5 else { return }
            DispatchQueue.main.async { [heightBinding] in heightBinding.wrappedValue = clamped }
        }
    }

    static let heightScript = """
    (function(){var b=document.body,e=document.documentElement;\
    return Math.ceil(Math.max(b?b.scrollHeight:0,e.scrollHeight,e.offsetHeight));})()
    """

    static func document(html: String, textColor: String, secondaryColor: String) -> String {
        """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
        <style>
        html,body{margin:0;padding:0;background:transparent;overflow-x:hidden;}
        body{color:\(textColor);font:-apple-system-body;font-family:-apple-system,"PingFang SC",sans-serif;
             -webkit-text-size-adjust:100%;word-break:break-word;}
        p{margin:0;}
        a{color:\(secondaryColor);}
        img,svg{max-width:100%;}
        section,div,span{max-width:100%;}
        </style></head>
        <body>\(html)
        <script>
        function __introHeight(){
          var b=document.body,e=document.documentElement;
          var h=Math.max(b?b.scrollHeight:0,e.scrollHeight,e.offsetHeight);
          try{window.webkit.messageHandlers.\(Coordinator.heightHandler).postMessage(h);}catch(err){}
        }
        window.addEventListener('load',__introHeight);
        window.addEventListener('resize',__introHeight);
        [0,80,260,600,1200].forEach(function(ms){setTimeout(__introHeight,ms);});
        __introHeight();
        </script></body></html>
        """
    }

    /// SwiftUI 颜色按当前外观解析成 CSS 颜色（主题文字色可能是自定义色）。
    static func css(_ color: Color, scheme: ColorScheme) -> String {
        let style: UIUserInterfaceStyle = scheme == .dark ? .dark : .light
        let resolved = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        if resolved.getRed(&r, green: &g, blue: &b, alpha: &a) {
            return String(format: "rgba(%d,%d,%d,%.3f)",
                          Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()), a)
        }
        return style == .dark ? "#FFFFFF" : "#000000"
    }
}
