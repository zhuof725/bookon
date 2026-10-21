import UIKit
import WebKit

/// 书源遇到人机验证（Cloudflare 等）时，弹出网页让用户手动通过验证。
/// 用户点「完成」后读取网页源码返回，并把 Cookie 同步给 URLSession。
@MainActor
enum VerifyPresenter {
    private static var busy = false

    static func install() {
        WebViewLoader.interactiveHandler = { webView in await present(webView) }
        // java.getVerificationCode(imageUrl)：JS 线程同步等待用户输入。
        SourceVerificationBridge.handler = { imageUrl in
            guard !Thread.isMainThread else {
                DebugLog.add("◇getVerificationCode 在主线程调用，无法阻塞等待输入")
                return ""
            }
            let semaphore = DispatchSemaphore(value: 0)
            var code = ""
            DispatchQueue.main.async {
                presentCodePrompt(imageUrl: imageUrl) { value in
                    code = value ?? ""
                    semaphore.signal()
                }
            }
            _ = semaphore.wait(timeout: .now() + 180)
            return code
        }
    }

    private static func presentCodePrompt(imageUrl: String, completion: @escaping (String?) -> Void) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let win = scenes.flatMap({ $0.windows }).first(where: { $0.isKeyWindow }) ?? scenes.first?.windows.first,
              let root = win.rootViewController else {
            completion(nil); return
        }
        var top = root
        while let p = top.presentedViewController { top = p }
        let vc = VerificationCodeViewController(imageUrl: imageUrl, completion: completion)
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .formSheet
        nav.navigationBar.tintColor = .label
        top.present(nav, animated: true)
    }

    static func present(_ webView: WKWebView) async -> String? {
        if busy { return nil }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let win = scenes.flatMap({ $0.windows }).first(where: { $0.isKeyWindow }) ?? scenes.first?.windows.first,
              let root = win.rootViewController else { return nil }
        var top = root
        while let p = top.presentedViewController { top = p }
        busy = true
        defer { busy = false }
        return await withCheckedContinuation { c in
            let vc = VerifyViewController(webView: webView) { html in c.resume(returning: html) }
            let nav = UINavigationController(rootViewController: vc)
            nav.navigationBar.tintColor = .label
            nav.modalPresentationStyle = .fullScreen
            top.present(nav, animated: true)
        }
    }
}

final class VerifyViewController: UIViewController {
    private let webView: WKWebView
    private let onFinish: (String?) -> Void
    private var finished = false

    init(webView: WKWebView, onFinish: @escaping (String?) -> Void) {
        self.webView = webView
        self.onFinish = onFinish
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "人机验证"
        view.backgroundColor = .systemBackground
        webView.frame = view.bounds
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        webView.removeFromSuperview()
        webView.alpha = 1
        webView.isUserInteractionEnabled = true
        view.addSubview(webView)
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "取消", style: .plain, target: self, action: #selector(cancelTapped))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "完成", style: .done, target: self, action: #selector(doneTapped))
        navigationItem.prompt = "按网页提示完成验证，看到正常页面后点「完成」"
        // 复用 loader 已加载的页面，不重新 load（否则会丢失 POST 和 Cookie 上下文）。
    }

    @objc private func cancelTapped() { finish(nil) }

    @objc private func doneTapped() {
        webView.evaluateJavaScript("document.documentElement.outerHTML") { [weak self] v, _ in
            let html = v as? String
            Task { @MainActor in
                await WebViewLoader.syncCookiesFromWebView(host: self?.webView.url?.host)
                self?.finish(html)
            }
        }
    }

    private func finish(_ html: String?) {
        guard !finished else { return }
        finished = true
        let cb = onFinish
        dismiss(animated: true) { cb(html) }
    }
}


/// 图片验证码输入框：书源 `java.getVerificationCode(url)` 在 JS 线程等待结果。
final class VerificationCodeViewController: UIViewController, UITextFieldDelegate {
    private let imageUrl: String
    private let completion: (String?) -> Void
    private let imageView = UIImageView()
    private let field = UITextField()
    private var finished = false

    init(imageUrl: String, completion: @escaping (String?) -> Void) {
        self.imageUrl = imageUrl
        self.completion = completion
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "验证码"
        view.backgroundColor = .systemBackground
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "取消", style: .plain,
                                                           target: self, action: #selector(cancelTapped))
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "确定", style: .done,
                                                           target: self, action: #selector(doneTapped))
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .secondarySystemBackground
        imageView.translatesAutoresizingMaskIntoConstraints = false
        field.borderStyle = .roundedRect
        field.placeholder = "请输入图片中的验证码"
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.returnKeyType = .done
        field.delegate = self
        field.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(imageView)
        view.addSubview(field)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            imageView.heightAnchor.constraint(equalToConstant: 140),
            field.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 20),
            field.leadingAnchor.constraint(equalTo: imageView.leadingAnchor),
            field.trailingAnchor.constraint(equalTo: imageView.trailingAnchor),
            field.heightAnchor.constraint(equalToConstant: 40)
        ])
        if let url = URL(string: imageUrl) {
            URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                guard let data, let image = UIImage(data: data) else { return }
                DispatchQueue.main.async { self?.imageView.image = image }
            }.resume()
        }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        doneTapped()
        return true
    }

    @objc private func cancelTapped() { finish(nil) }
    @objc private func doneTapped() { finish(field.text ?? "") }

    private func finish(_ value: String?) {
        guard !finished else { return }
        finished = true
        let cb = completion
        dismiss(animated: true) { cb(value) }
    }
}
