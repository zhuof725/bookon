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
    /// 保存凭据后重启仍可复用，这里显示当前登录状态（只读本机凭据，不联网探测）。
    @State private var loginState: SourceLoginStatus.State = .none
    /// 书源脚本 java.toast 的弹出回传卡片内容。
    @State private var toastCard: String?

    private var script: String? { SourceLoginForm.loginScript(source.loginUrl) }
    private var pageURL: String? { SourceLoginForm.loginPageURL(source) }
    private var hasLoginFunction: Bool { (script ?? "").contains("login") }

    var body: some View {
        NavigationStack {
            Form {
                Group {
                    Section("登录状态") {
                        HStack {
                            Text("当前状态").foregroundStyle(palette.secondary).appFont(.callout)
                            Spacer()
                            Text(SourceLoginStatus.label(loginState))
                                .foregroundStyle(loginState == .none ? palette.secondary : palette.accent)
                                .accessibilityIdentifier("login.status")
                        }
                        if loginState != .none {
                            Text(SourceLoginStatus.detail(loginState))
                                .appFont(.footnote).foregroundStyle(palette.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .independentGlassRow()
                    if !fields.isEmpty {
                        Section("登录信息") {
                            ForEach(fields.filter { $0.kind != .button }) { f in
                                if f.kind == .password {
                                    SecureField(f.name, text: binding(f.name)).foregroundStyle(palette.primary)
                                } else {
                                    HStack {
                                        Text(f.name).foregroundStyle(palette.secondary).appFont(.callout)
                                        TextField(f.name, text: binding(f.name))
                                            .foregroundStyle(palette.primary)
                                            .textInputAutocapitalization(.never)
                                            .autocorrectionDisabled()
                                    }
                                }
                            }
                        }
                        let buttons = fields.filter { $0.kind == .button }
                        if !buttons.isEmpty {
                            Section("操作") {
                                ForEach(buttons) { f in
                                    Button(f.name) { press(f) }.disabled(busy)
                                }
                            }
                        }
                        Section {
                            Button("保存") { save(runLogin: false) }.disabled(busy)
                            if hasLoginFunction {
                                Button("登录") { save(runLogin: true) }.disabled(busy)
                            }
                            Button("清除登录信息", role: .destructive) { clear() }.foregroundStyle(.red).disabled(busy)
                        }
                    }
                    if let url = pageURL {
                        Section("网页登录") {
                            Button("打开登录页面") { open(pageURL ?? source.bookSourceUrl, title: "网页登录") }
                            Text(url).appFont(.caption).foregroundStyle(palette.secondary).lineLimit(2)
                        }
                    }
                    if fields.isEmpty && pageURL == nil {
                        Text("这个书源没有可用的登录配置（没有 loginUi，loginUrl 也不是网址）。")
                            .appFont(.footnote).foregroundStyle(palette.secondary)
                    }
                    if !message.isEmpty {
                        Section("结果") { Text(message).appFont(.footnote).textSelection(.enabled) }
                    }
                }
                .independentGlassRow()
            }
            .foregroundStyle(palette.primary)
            .scrollContentBackground(.hidden)
            .background { AppThemeCanvas().ignoresSafeArea() }
            .navigationTitle(source.bookSourceName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
            .overlay { if busy { ProgressView() } }
            .overlay(alignment: .bottom) {
                if let toastCard {
                    LoginToastCard(text: toastCard) { self.toastCard = nil }
                        .padding(.horizontal, 16).padding(.bottom, 16)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .task(id: toastCard) {
                            try? await Task.sleep(nanoseconds: 15_000_000_000)
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
                    if hasLoginFunction, message.isEmpty { message = "已回流网页登录 Cookie；如需令牌，请再点「登录」。" }
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

    private var sourceKey: String { source.bookSourceUrl }

    private func prepare() async {
        let src = source
        let text = await Task.detached { () -> String? in
            SourceLoginForm.resolveUiText(src.loginUi) { js in
                JSEngine.shared.evalString(js, context: RuleContext(source: src))
            }
        }.value
        let parsed = SourceLoginForm.parseFields(text)
        fields = parsed
        // 读取已保存的登录信息；没有保存时不写入默认值，保存由用户点击触发。
        let saved = JSEngine.loginStore.getLoginInfo(sourceKey)
            .flatMap { SourceLoginJSON.parseStringMap($0, nested: .compactJSON) } ?? [:]
        values = SourceLoginForm.initialValues(fields: parsed, saved: saved)
        loginState = SourceLoginStatus.state(key: sourceKey, login: JSEngine.loginStore, defaults: .standard)
    }

    private func save(runLogin: Bool) {
        JSEngine.loginStore.putLoginInfo(sourceKey, SourceLoginForm.encode(values))
        loginState = SourceLoginStatus.state(key: sourceKey, login: JSEngine.loginStore, defaults: .standard)
        message = "已保存"
        if runLogin { runScript("login()") }
    }

    private func clear() {
        JSEngine.loginStore.removeLoginInfo(sourceKey)
        try? JSEngine.loginStore.removeLoginHeader(sourceKey)
        SourceLoginStatus.clearVerified(sourceKey, defaults: .standard)
        loginState = SourceLoginStatus.state(key: sourceKey, login: JSEngine.loginStore, defaults: .standard)
        for f in fields where f.kind != .button { values[f.name] = f.defaultValue }
        message = "已清除本书源保存的登录信息"
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
                    loginState = SourceLoginStatus.state(key: sourceKey, login: JSEngine.loginStore, defaults: .standard)
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

/// 登录页的弹出回传卡片：显示书源 java.toast 的完整内容，可点按关闭。
struct LoginToastCard: View {
    @ThemePalette private var palette
    let text: String
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("登录结果").appFont(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.primary)
                Spacer(minLength: 8)
                Button(action: onDismiss) {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.secondary).frame(width: 32, height: 32)
                }
                .buttonStyle(.plain).accessibilityLabel("关闭登录结果")
            }
            ScrollView {
                Text(text.trimmingCharacters(in: .whitespacesAndNewlines))
                    .appFont(.footnote).foregroundStyle(palette.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 260)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(SettingsGlassSurface())
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onTapGesture(perform: onDismiss)
        .accessibilityElement(children: .contain)
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
    weak var webView: WKWebView?

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
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { model?.refresh() }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { model?.refresh() }
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { model?.refresh() }
    }
}
