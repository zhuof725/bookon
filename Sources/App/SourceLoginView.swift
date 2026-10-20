import SwiftUI
import WebKit

/// 书源登录：有 loginUi 时按表单登录；只有网页登录地址时用 WebView 登录并回流 Cookie。
struct SourceLoginView: View {
    @ThemePalette private var palette
    let source: BookSource
    @Environment(\.dismiss) private var dismiss
    @State private var fields: [LoginField] = []
    @State private var values: [String: String] = [:]
    @State private var message = ""
    @State private var busy = false
    @State private var browser: BrowserTarget?
    @State private var loaded = false
    /// 书源脚本 java.toast 的弹出回传卡片内容。
    @State private var toastCard: String?

    private var script: String? { SourceLoginForm.loginScript(source.loginUrl) }
    private var pageURL: String? { SourceLoginForm.loginPageURL(source) }
    private var hasLoginFunction: Bool { (script ?? "").contains("login") }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !fields.isEmpty {
                        ForEach(Array(SourceLoginForm.layoutRows(fields).enumerated()), id: \.offset) { _, row in
                            HStack(spacing: 12) {
                                ForEach(row) { f in loginCell(f) }
                            }
                        }
                    }
                    if fields.isEmpty && pageURL == nil {
                        Text("这个书源没有可用的登录配置（没有 loginUi，loginUrl 也不是网址）。")
                            .appFont(.footnote).foregroundStyle(palette.secondary)
                    }
                    if let url = pageURL {
                        loginAction("打开登录页面", id: "login.openPage") { open(url, title: "网页登录") }
                        Text(url).appFont(.caption).foregroundStyle(palette.secondary).lineLimit(2)
                    }
                    if !message.isEmpty {
                        Text(message).appFont(.footnote).foregroundStyle(palette.secondary)
                            .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("login.outcome")
                    }
                }
                .padding(16)
            }
            .foregroundStyle(palette.primary)
            .background { AppThemeCanvas().ignoresSafeArea() }
            .navigationTitle("登录 - " + source.bookSourceName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确认") { save(runLogin: false); dismiss() }
                        .accessibilityIdentifier("login.confirm")
                }
            }
            .overlay { if busy { ProgressView() } }
            .overlay(alignment: .bottom) {
                if let toastCard {
                    LoginToastCard(text: toastCard) { self.toastCard = nil }
                        .padding(.horizontal, 24)
                        .frame(maxWidth: 360)
                        .padding(.bottom, 120)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                        .task(id: toastCard) {
                            try? await Task.sleep(nanoseconds: 1_000_000_000)
                            if !Task.isCancelled { self.toastCard = nil }
                        }
                }
            }
            .animation(.easeOut(duration: 0.2), value: toastCard)
            .sheet(item: $browser) { target in
                InAppBrowserSheet(target: target, host: URL(string: target.url)?.host,
                                  cookieJar: source.cookieJarEnabled) {
                    browser = nil
                    // 网页里登录完成后，提示用户回到表单再点一次登录以读取最新凭据。
                    if hasLoginFunction, message.isEmpty { message = "已回流网页登录 Cookie。" }
                }
            }
        }
        .task { if !loaded { loaded = true; await prepare() } }
        .onAppear {
            ToastCenter.setHandler { m in
                DispatchQueue.main.async {
                    message = m
                    // 同时弹出卡片：书源登录成功/失败都会用 java.toast 回传结果。
                    toastCard = m
                }
            }
            // 登录脚本里的 java.startBrowser/showBrowser/startBrowserAwait 一律在应用内浏览器打开，
            // 不再跳出到系统浏览器，关闭时按书源开关回流 Cookie。
            ToastCenter.setBrowserHandler { u, t in
                DispatchQueue.main.async { open(u, title: t) }
            }
        }
        .onDisappear { ToastCenter.setHandler(nil); ToastCenter.setBrowserHandler(nil) }
    }

    private func binding(_ name: String) -> Binding<String> {
        Binding(get: { values[name] ?? "" }, set: { values[name] = $0 })
    }

    /// 单个登录项：输入框是圆角浅底输入框，按钮是圆角玻璃底色 + 主题色文字。
    /// 布局比例交给 SourceLoginForm.layoutRows，这里只负责外观与回调。
    @ViewBuilder
    private func loginCell(_ f: LoginField) -> some View {
        if f.kind == .button {
            Button { press(f) } label: {
                Text(f.name)
                    .appFont(.subheadline)
                    .foregroundStyle(palette.accent)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 46)
            }
            .buttonStyle(.plain)
            .disabled(busy)
            .background { ThemeSurface(shape: RoundedRectangle(cornerRadius: 14, style: .continuous)) }
            .accessibilityIdentifier("login.item.\(f.name)")
        } else {
            Group {
                if f.kind == .password {
                    SecureField("", text: binding(f.name),
                                prompt: Text(f.name).foregroundColor(palette.secondary))
                } else {
                    TextField("", text: binding(f.name),
                              prompt: Text(f.name).foregroundColor(palette.secondary))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .appFont(.subheadline)
            .foregroundStyle(palette.primary)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background { ThemeSurface(shape: RoundedRectangle(cornerRadius: 14, style: .continuous)) }
            .accessibilityIdentifier("login.item.\(f.name)")
        }
    }

    /// 整行操作（打开登录页面）。
    private func loginAction(_ title: String, id: String, destructive: Bool = false,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .appFont(.subheadline)
                .foregroundStyle(destructive ? Color.red : palette.accent)
                .frame(maxWidth: .infinity, minHeight: 46)
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .background { ThemeSurface(shape: RoundedRectangle(cornerRadius: 14, style: .continuous)) }
        .accessibilityIdentifier(id)
    }

    private var sourceKey: String { source.bookSourceUrl }

    private func prepare() async {
        let src = source
        let text = await Task.detached { () -> String? in
            SourceLoginForm.resolveUiText(src.loginUi) { js in
                // loginUi 常常是 `@js: result = 某函数()`，函数定义在 loginUrl（登录函数库）里
                // （含遇見书源就是这样），所以求值时要同时带上 jsLib 与 loginUrl 脚本库。
                JSEngine.shared.evalString(js, jsLib: src.jsLib,
                                           loginLib: SourceLoginForm.loginScript(src.loginUrl),
                                           context: RuleContext(source: src))
            }
        }.value
        let parsed = SourceLoginForm.parseFields(text)
        fields = parsed
        if parsed.isEmpty, SourceLoginForm.isScriptUI(src.loginUi) {
            message = "登录界面脚本执行失败，请查看「书源调试」里的 JS 错误。"
        }
        // 读取已保存的登录信息；没有保存时不写入默认值，保存由用户点击触发。
        let saved = JSEngine.loginStore.getLoginInfo(sourceKey)
            .flatMap { SourceLoginJSON.parseStringMap($0, nested: .compactJSON) } ?? [:]
        values = SourceLoginForm.initialValues(fields: parsed, saved: saved)
    }

    private func save(runLogin: Bool) {
        JSEngine.loginStore.putLoginInfo(sourceKey, SourceLoginForm.encode(values))
        message = "已保存"
        if runLogin { runScript("login()") }
    }

    private func press(_ f: LoginField) {
        // 先保存当前输入，脚本里的 getLoginInfoMap() 才能读到最新值。
        JSEngine.loginStore.putLoginInfo(sourceKey, SourceLoginForm.encode(values))
        let action = f.action.trimmingCharacters(in: .whitespacesAndNewlines)
        if action.isEmpty { message = "按钮没有配置动作"; return }
        if SourceLoginForm.isURL(action) {
            open(action, title: f.name)
            return
        }
        runScript(action)
    }

    /// 只有需要跳转的登录网址才用内置浏览器打开，不跳出到系统浏览器。
    private func open(_ url: String, title: String) {
        guard let target = SourceLoginForm.browserURL(url) else {
            message = "这个网址无法在内置浏览器打开"
            return
        }
        browser = BrowserTarget(url: target, title: title)
    }

    private func runScript(_ call: String) {
        guard let lib = script else { message = "loginUrl 里没有可执行的脚本"; return }
        busy = true
        message = ""
        let src = source
        let vals = values
        Task {
            let result = await Task.detached { JSEngine.shared.runLoginScript(source: src, library: lib, call: call, formValues: vals) }.value
            busy = false
            switch result {
            case .failure(let e):
                // 脚本异常不会有 java.toast，必须由界面把原因回传出来。
                let text = "执行出错：\(e.message)"
                message = text
                toastCard = text
            case .success(let s):
                if call.lowercased().hasPrefix("login") {
                    SourceLoginStatus.markVerified(sourceKey, defaults: .standard)
                }
                if message.isEmpty {
                    let text = s.isEmpty ? "已执行" : s
                    message = text
                    toastCard = text
                }
            }
        }
    }
}

/// 登录页的弹出提示：书源 java.toast 的内容以深色胶囊卡片弹出，
/// 与书源在 Android 客户端里的提示一致，无标题、无关闭按钮，点按或超时后消失。
struct LoginToastCard: View {
    let text: String
    let onDismiss: () -> Void

    var body: some View {
        Text(text.trimmingCharacters(in: .whitespacesAndNewlines))
            .appFont(.footnote)
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .frame(maxWidth: 320)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black.opacity(0.78))
                    .shadow(color: .black.opacity(0.22), radius: 8, x: 0, y: 3)
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .onTapGesture(perform: onDismiss)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("login.toastCard")
    }
}

/// 内置浏览器目标：登录页与登录脚本请求的跳转网址。
struct BrowserTarget: Identifiable, Equatable {
    let id = UUID()
    let url: String
    let title: String
}

/// 内置浏览器：登录相关跳转都在应用内打开，关闭时按书源开关回流当前主机 Cookie。
struct InAppBrowserSheet: View {
    let target: BrowserTarget
    let host: String?
    let cookieJar: Bool
    let onClose: () -> Void
    @StateObject private var model = BrowserNavigationModel()

    var body: some View {
        NavigationStack {
            LoginWebView(url: target.url, model: model)
                .overlay { if model.isLoading { ProgressView().padding(10).modifier(SettingsGlassSurface()) } }
                .navigationTitle(target.title.isEmpty ? "登录" : target.title)
                .navigationBarTitleDisplayMode(.inline)
                .accessibilityIdentifier("login.browser.page")
                .alert(model.importMessage ?? "", isPresented: Binding(
                    get: { model.importMessage != nil && model.importMessage != "正在导入书源…" },
                    set: { if !$0 { model.importMessage = nil } })) {
                    Button("好", role: .cancel) {}
                }
                .toolbar {
                    ToolbarItemGroup(placement: .bottomBar) {
                        Button { model.back() } label: { Image(systemName: "chevron.backward") }
                            .disabled(!model.canGoBack)
                            .accessibilityLabel("后退").accessibilityIdentifier("login.browser.back")
                        Button { model.forward() } label: { Image(systemName: "chevron.forward") }
                            .disabled(!model.canGoForward)
                            .accessibilityLabel("前进").accessibilityIdentifier("login.browser.forward")
                        Spacer()
                        Button { model.reload() } label: { Image(systemName: "arrow.clockwise") }
                            .accessibilityLabel("刷新").accessibilityIdentifier("login.browser.reload")
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") {
                            Task {
                                await WebViewLoader.syncCookiesFromWebView(host: host, enabled: cookieJar)
                                onClose()
                            }
                        }
                        .accessibilityIdentifier("login.browser.done")
                    }
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { onClose() }.accessibilityIdentifier("login.browser.cancel")
                    }
                }
        }
    }
}

/// 内置浏览器的前进/后退/刷新状态；只持有 WebView 的弱引用。
final class BrowserNavigationModel: ObservableObject {
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var isLoading = false
    /// 网页里点「导入更新」等书源导入链接后的结果提示。
    @Published var importMessage: String?
    weak var webView: WKWebView?

    /// 拦截 yuedu:// / legado:// 书源导入链接，直接在应用内导入，不跳出浏览器。
    @MainActor
    func importSource(from src: String) {
        importMessage = "正在导入书源…"
        Task { @MainActor in
            do {
                let n = try await AppStore.shared.importSources(from: src)
                importMessage = "成功导入 \(n) 个书源"
            } catch {
                importMessage = "导入失败：\(error.localizedDescription)"
            }
        }
    }

    func attach(_ web: WKWebView) {
        guard webView !== web else { return }
        webView = web
        // 避免在 SwiftUI 视图更新期间发布状态变化。
        DispatchQueue.main.async { [weak self] in self?.refresh() }
    }
    func refresh() {
        canGoBack = webView?.canGoBack ?? false
        canGoForward = webView?.canGoForward ?? false
        isLoading = webView?.isLoading ?? false
    }
    func back() { webView?.goBack(); refresh() }
    func forward() { webView?.goForward(); refresh() }
    func reload() { webView?.reload(); refresh() }
}

struct LoginWebView: UIViewRepresentable {
    let url: String
    var model: BrowserNavigationModel?

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeUIView(context: Context) -> WKWebView {
        let web = WKWebView(frame: .zero)
        web.customUserAgent = WebViewSupport.userAgent
        web.navigationDelegate = context.coordinator
        context.coordinator.model?.attach(web)
        if let u = URL(string: url) {
            Task {
                await WebViewLoader.syncCookiesToWebView(for: u)
                web.load(URLRequest(url: u))
            }
        }
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.model = model
        model?.attach(uiView)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var model: BrowserNavigationModel?
        init(model: BrowserNavigationModel?) { self.model = model }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url, let src = SourceImportLink.sourceURL(url) {
                decisionHandler(.cancel)
                let model = self.model
                Task { @MainActor in model?.importSource(from: src) }
                return
            }
            decisionHandler(.allow)
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { model?.refresh() }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { model?.refresh() }
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { model?.refresh() }
    }
}
