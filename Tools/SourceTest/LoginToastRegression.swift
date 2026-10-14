import Foundation

/// 登录 toast 回传通道：确认书源脚本的 java.toast 内容真的到达界面回调。
/// 只使用合成脚本与合成书源，不联网、不读取真实账号。
enum LoginToastRegression {
    static func run(_ check: (Bool, String) -> Void) {
        var received: [String] = []
        ToastCenter.setHandler { received.append($0) }
        defer { ToastCenter.setHandler(nil) }

        // 与书山聚合 login() 相同的多行卡片形态。
        let card = """
        \n───────────────
        🌟 欢迎回来，尊贵的会员 🌟
        ───────────────
        昵称：测试昵称
        邮箱：233****@qq.com
        状态：会员用户
        ───────────────
        🟢 设备1 | 1.2.*.*
        ───────────────
        """
        var source = BookSource(bookSourceUrl: "toast-fixture.invalid", bookSourceName: "Toast 样例")
        source.loginUrl = """
        function login(flag) {
            java.toast('\(card.replacingOccurrences(of: "'", with: "\\'").replacingOccurrences(of: "\n", with: "\\n"))');
            return 'done';
        }
        """
        let result = JSEngine.shared.runLoginScript(source: source,
            library: source.loginUrl, call: "login()", formValues: ["邮箱": "a@b.c"])
        switch result {
        case .failure(let e):
            check(false, "合成登录脚本可执行（\(e.message)）")
        case .success(let value):
            check(value == "done", "登录脚本返回值可读")
        }
        check(received.count == 1, "toast 只回传一次（实际 \(received.count) 次）")
        let text = received.first ?? ""
        check(text.contains("欢迎回来，尊贵的会员"), "回传内容包含欢迎语")
        check(text.contains("昵称：测试昵称") && text.contains("邮箱：233****@qq.com"), "回传内容包含账号信息")
        check(text.contains("设备1"), "回传内容包含设备列表")
        check(text.components(separatedBy: "\n").count >= 8, "多行卡片不被截断")
        check(!text.contains("\\n"), "换行没有被转义成字面量")

        // 脚本异常时也必须回传，而不是静默失败。
        var broken = source
        broken.loginUrl = "function login(flag) { throw new Error('boom'); }"
        _ = JSEngine.shared.runLoginScript(source: broken, library: broken.loginUrl, call: "login()")
        check(!received.isEmpty, "脚本异常时仍有回传")
    }
}
