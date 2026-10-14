import Foundation

/// 登录 toast 回传通道：确认书源脚本的 java.toast 内容真的到达界面回调。
/// 只使用合成脚本与合成书源，不联网、不读取真实账号。
enum LoginToastRegression {
    /// BookSource 只有 Decodable 初始化，测试里按 JSON 构造，与导入路径一致。
    private static func source(loginURL: String) throws -> BookSource {
        let object: [String: Any] = ["bookSourceUrl": "toast-fixture.invalid",
                                     "bookSourceName": "Toast 样例",
                                     "loginUrl": loginURL]
        let data = try JSONSerialization.data(withJSONObject: object)
        return try JSONDecoder().decode(BookSource.self, from: data)
    }

    static func run(_ check: (Bool, String) -> Void) throws {
        var received: [String] = []
        ToastCenter.setHandler { received.append($0) }
        defer { ToastCenter.setHandler(nil) }

        // 与书山聚合 login() 相同的多行卡片形态。
        let card = [
            "",
            "───────────────",
            "🌟 欢迎回来，尊贵的会员 🌟",
            "───────────────",
            "昵称：测试昵称",
            "邮箱：233****@qq.com",
            "状态：会员用户",
            "───────────────",
            "🟢 设备1 | 1.2.*.*",
            "───────────────"
        ].joined(separator: "\n")

        let library = """
        function login(flag) {
            java.toast(\(jsonString(card)));
            return 'done';
        }
        """
        let good = try source(loginURL: library)
        switch JSEngine.shared.runLoginScript(source: good, library: good.loginUrl,
                                              call: "login()", formValues: ["邮箱": "a@b.c"]) {
        case .failure(let error):
            check(false, "合成登录脚本可执行（\(error.message)）")
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

        // 脚本异常时不会凭空产生 toast，但必须把失败原因返回给界面用于回传。
        received.removeAll()
        let broken = try source(loginURL: "function login(flag) { throw new Error('boom'); }")
        let outcome = JSEngine.shared.runLoginScript(source: broken, library: broken.loginUrl, call: "login()")
        switch outcome {
        case .failure(let error):
            check(error.message.contains("boom"), "脚本异常原因可回传给界面")
        case .success:
            check(false, "抛错的登录脚本不应报告成功")
        }
    }

    /// 把任意文本安全地嵌入 JS 字符串字面量。
    private static func jsonString(_ value: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: [value])
        let array = data.flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\"]"
        return String(array.dropFirst().dropLast())
    }
}
