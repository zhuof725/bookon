import Foundation

/// 书源登录状态：即使书源没有表单（例如只在内置浏览器登录），也要在重启后仍能看出是否已登录。
/// 判定只看本机已保存的登录凭据，不联网、不猜测；没有凭据一律显示「未登录」。
enum SourceLoginStatus {
    enum State: Equatable {
        /// 没有保存任何登录凭据。
        case none
        /// 保存过登录信息或登录头（重启后仍在）。
        case saved
        /// 保存过凭据，且 login() 至少执行成功过一次。
        case verified
    }

    static let verifiedPrefix = "reader.source.login.verified."

    static func state(key: String, login: SourceLoginStore, defaults: UserDefaults) -> State {
        guard hasCredentials(key, login: login) else { return .none }
        return defaults.object(forKey: verifiedPrefix + key) != nil ? .verified : .saved
    }

    /// 列表与登录页统一显示：已保存凭据就是已登录，不把「登录脚本跑过」当成额外承诺。
    static func label(_ state: State) -> String {
        state == .none ? "未登录" : "已登录"
    }

    /// 状态说明：只陈述本机事实，不声称服务端仍然有效。
    static func detail(_ state: State) -> String {
        switch state {
        case .none: return "还没有保存登录信息。"
        case .saved: return "登录信息已保存在本机，重新打开应用后仍然有效；未执行过登录脚本。"
        case .verified: return "登录信息已保存在本机，重新打开应用后仍然有效；登录脚本已成功执行过。"
        }
    }

    /// 是否已保存登录凭据：登录信息里的任一非空值，或非空登录头。
    /// 返回 true 才说明重启后仍可复用，因此「记住登录」以凭据存在为准。
    static func hasCredentials(_ key: String, login: SourceLoginStore) -> Bool {
        if let header = login.getLoginHeader(key), !SourceLoginJSON.isBlank(header) { return true }
        guard let info = login.getLoginInfo(key), !SourceLoginJSON.isBlank(info),
              let map = SourceLoginJSON.parseStringMap(info, nested: .compactJSON) else { return false }
        return map.values.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// login() 执行成功时标记；凭据被清除时一并清除，避免留下过期的「已验证」。
    static func markVerified(_ key: String, defaults: UserDefaults, at date: Date = Date()) {
        defaults.set(date, forKey: verifiedPrefix + key)
    }

    static func clearVerified(_ key: String, defaults: UserDefaults) {
        defaults.removeObject(forKey: verifiedPrefix + key)
    }
}
