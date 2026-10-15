import Foundation

/// 离线回归：书源登录状态判定与持久化。输入均为合成数据，断言不含真实凭据。
enum SourceLoginStatusRegression {
    static func run(_ check: (Bool, String) -> Void) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("login-status-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("login.json")
        let key = "https://state.test#1"
        let store = SourceLoginStore(backing: PersistentLoginBackingStore(fileURL: file),
                                     cookieReplacer: { _, _ in }, cookieRemover: { _ in })
        let suite = UserDefaults(suiteName: "login-status-\(UUID().uuidString)")!
        defer { suite.removePersistentDomain(forName: suite.description) }

        check(SourceLoginStatus.state(key: key, login: store, defaults: suite) == .none,
              "登录状态：没有凭据时为未登录")
        check(SourceLoginStatus.label(.none) == "未登录", "登录状态：未登录文案")
        check(SourceLoginStatus.detail(.saved).contains("重新打开应用后仍然有效"),
              "登录状态：说明只陈述本机事实")

        // 空值与空对象都不算已登录，避免把「保存过空白表单」显示成已登录。
        _ = store.putLoginInfo(key, "{}")
        check(SourceLoginStatus.state(key: key, login: store, defaults: suite) == .none,
              "登录状态：空对象不算已登录")
        _ = store.putLoginInfo(key, "{\"user\":\"   \"}")
        check(SourceLoginStatus.state(key: key, login: store, defaults: suite) == .none,
              "登录状态：只有空白值不算已登录")

        _ = store.putLoginInfo(key, "{\"user\":\"u\"}")
        check(SourceLoginStatus.state(key: key, login: store, defaults: suite) == .saved,
              "登录状态：保存凭据后为已登录")
        check(SourceLoginStatus.label(.saved) == "已登录", "登录状态：已登录文案")

        SourceLoginStatus.markVerified(key, defaults: suite)
        check(SourceLoginStatus.state(key: key, login: store, defaults: suite) == .verified,
              "登录状态：登录脚本成功后可标记已验证")

        // 重启：新实例读同一文件，状态仍为已登录。
        let reopened = SourceLoginStore(backing: PersistentLoginBackingStore(fileURL: file),
                                        cookieReplacer: { _, _ in }, cookieRemover: { _ in })
        check(SourceLoginStatus.state(key: key, login: reopened, defaults: suite) == .verified,
              "登录状态：重启后凭据与已验证标记都保留")
        check(SourceLoginStatus.state(key: "https://other.test", login: reopened, defaults: suite) == .none,
              "登录状态：不同书源状态互不影响")

        // 仅有 loginHeader 也算已登录（浏览器登录路径）。
        let headerKey = "https://header.test"
        try? reopened.putLoginHeader(headerKey, "{\"Cookie\":\"a=b\"}")
        check(SourceLoginStatus.state(key: headerKey, login: reopened, defaults: suite) == .saved,
              "登录状态：仅保存登录头也算已登录")
        try? reopened.putLoginHeader("https://emptyheader.test", "{\"X\":\"\"}")
        check(SourceLoginStatus.state(key: "https://emptyheader.test", login: reopened, defaults: suite) == .none,
              "登录状态：空登录头不算已登录")

        // 清除凭据后必须回到未登录，不能留下过期的已验证标记。
        reopened.removeLoginInfo(key)
        SourceLoginStatus.clearVerified(key, defaults: suite)
        check(SourceLoginStatus.state(key: key, login: reopened, defaults: suite) == .none,
              "登录状态：清除凭据后回到未登录并清除标记")
    }
}
