import SwiftUI
import UIKit
import WebKit

/// `<useweb>` / `<usehtml>` 简介：书源直接给 HTML（含内联 CSS、SVG 图标），
/// 原版用 WebView 渲染，这里同样交给 WKWebView。
///
/// - 高度随内容自适应（外层 ScrollView 负责滚动，WebView 自身不滚动）
/// - 文字颜色跟随当前主题（书源样式用的是 `inherit` / `currentColor` / 半透明灰）
/// - 链接不在简介里跳转，交给系统浏览器
extension Notification.Name {
    /// 书源详情面板改了源变量里的音色（tone/abook）。
    static let sourceToneChanged = Notification.Name("BookOn.sourceToneChanged")
}

struct RichIntroWebView: UIViewRepresentable {
    let html: String
    let textColor: Color
    let secondaryColor: Color
    let source: BookSource?
    @Binding var height: CGFloat

    @Environment(\.colorScheme) private var scheme

    func makeCoordinator() -> Coordinator { Coordinator(height: $height, source: source) }

    func makeUIView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: Coordinator.heightHandler)
        controller.add(context.coordinator, name: Coordinator.bridgeHandler)
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
        // 面板脚本要读写书源变量：每次加载前装一份带最新值的桥。
        context.coordinator.installBridge(on: web.configuration.userContentController)
        web.loadHTMLString(document, baseURL: nil)
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        static let heightHandler = "introHeight"
        static let bridgeHandler = "introBridge"
        var loaded: String?
        private let heightBinding: Binding<CGFloat>
        private let sourceURL: String
        private let sourceName: String

        init(height: Binding<CGFloat>, source: BookSource?) {
            heightBinding = height
            sourceURL = source?.bookSourceUrl ?? ""
            sourceName = source?.bookSourceName ?? ""
        }

        func userContentController(_ controller: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            if message.name == Self.heightHandler {
                guard let number = message.body as? NSNumber else { return }
                apply(CGFloat(number.doubleValue))
                return
            }
            guard message.name == Self.bridgeHandler,
                  let body = message.body as? [String: Any],
                  let op = body["op"] as? String else { return }
            switch op {
            case "var":
                if let value = body["value"] as? String {
                    let previous = SourceVariable.get(sourceURL)
                    SourceVariable.set(value, for: sourceURL)
                    if Self.toneSelectionChanged(previous, value), !sourceURL.isEmpty {
                        NotificationCenter.default.post(name: .sourceToneChanged, object: sourceURL)
                    }
                }
            case "put":
                if let key = body["key"] as? String, let value = body["value"] as? String {
                    SourceVariableStore.shared.set("v_\(sourceURL)_\(key)", value)
                }
            case "cache":
                if let key = body["key"] as? String, let value = body["value"] as? String {
                    SourceVariableStore.shared.set(key, value)
                }
            case "cacheDelete":
                if let key = body["key"] as? String { SourceVariableStore.shared.remove(key) }
            case "toast":
                if let text = body["text"] as? String { DebugLog.add("◇书源面板：\(text)") }
            default:
                break
            }
        }

        /// 面板 JS 桥：书源详情页的「音色 / 书库 / 清缓存」按钮都靠 source/cache 读写。
        /// 之前只有 WebView 渲染，没有这些全局对象，面板只能把选择写进自己的内存
        /// （提示「已保存在本机缓存，重启后如失效请重选一次」）。
        func installBridge(on controller: WKUserContentController) {
            controller.removeAllUserScripts()
            let variable = sourceURL.isEmpty ? "" : SourceVariable.get(sourceURL)
            var kv: [String: String] = [:]
            if !sourceURL.isEmpty,
               let value = SourceVariableStore.shared.get("v_\(sourceURL)_v2sv"), !value.isEmpty {
                kv["v_v2sv"] = value
            }
            if let value = SourceVariableStore.shared.get("v2sel"), !value.isEmpty {
                kv["v2sel"] = value
            }
            controller.addUserScript(WKUserScript(
                source: Self.bridgeScript(sourceURL: sourceURL, sourceName: sourceName,
                                          variable: variable, kv: kv),
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true))
        }

        private static func bridgeScript(sourceURL: String, sourceName: String,
                                         variable: String, kv: [String: String]) -> String {
            let kvJSON = (try? JSONSerialization.data(withJSONObject: kv))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
            return """
            (function(){
              var V = \(jsString(variable));
              var KV = \(kvJSON);
              function post(op, payload){
                try{
                  var m = {op: op};
                  if(payload){ for(var k in payload){ m[k] = payload[k]; } }
                  window.webkit.messageHandlers.\(bridgeHandler).postMessage(m);
                }catch(e){}
              }
              window.source = {
                bookSourceUrl: \(jsString(sourceURL)),
                bookSourceName: \(jsString(sourceName)),
                getKey: function(){ return this.bookSourceUrl; },
                getVariable: function(){ return V || ''; },
                setVariable: function(v){ V = String(v == null ? '' : v); post('var', {value: V}); },
                putVariable: function(v){ this.setVariable(v); },
                get: function(k){ k = String(k); return KV['v_' + k] == null ? '' : String(KV['v_' + k]); },
                put: function(k, v){ k = String(k); v = String(v == null ? '' : v); KV['v_' + k] = v; post('put', {key: k, value: v}); }
              };
              window.cache = {
                getFromMemory: function(k){ k = String(k); return KV[k] == null ? '' : String(KV[k]); },
                putMemory: function(k, v){ k = String(k); v = String(v == null ? '' : v); KV[k] = v; post('cache', {key: k, value: v}); },
                deleteMemory: function(k){ k = String(k); delete KV[k]; post('cacheDelete', {key: k}); },
                get: function(k){ return this.getFromMemory(k); },
                put: function(k, v){ this.putMemory(k, v); },
                delete: function(k){ this.deleteMemory(k); }
              };
              window.cookie = { getKey: function(){ return ''; } };
              window.java = window.java || {};
              window.java.toast = function(s){ post('toast', {text: String(s == null ? '' : s)}); return ''; };
              window.java.log = function(s){ post('toast', {text: String(s == null ? '' : s)}); return ''; };
              window.java.put = window.java.put || function(){ return ''; };
              window.java.get = window.java.get || function(){ return ''; };
            })();
            """
        }

        /// 面板写的变量里 tone/abook 变了才算换了音色。
        private static func toneSelectionChanged(_ old: String, _ new: String) -> Bool {
            func selection(_ raw: String) -> String {
                guard let data = raw.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    return ""
                }
                let tone = object["tone"].map { String(describing: $0) } ?? ""
                let abook = object["abook"].map { String(describing: $0) } ?? ""
                return tone + "|" + abook
            }
            return selection(old) != selection(new)
        }

        private static func jsString(_ value: String) -> String {
            guard let data = try? JSONSerialization.data(withJSONObject: [value]),
                  let text = String(data: data, encoding: .utf8),
                  text.hasPrefix("["), text.hasSuffix("]") else { return "\"\"" }
            return String(text.dropFirst().dropLast())
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
