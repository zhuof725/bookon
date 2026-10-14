import Foundation

/// 书源登录表单：把 loginUi（JSON 数组，可能是 <js>/@js: 脚本）解析成有序字段，
/// 并负责按 Legado 约定执行登录：保存表单 -> 运行 loginUrl 里的 login()；按钮 action 调用 loginUrl 里的函数。
struct LoginField: Equatable, Identifiable {
    enum Kind: Equatable { case text, password, button }
    var id: Int
    var name: String
    var kind: Kind
    var defaultValue: String
    /// 按钮的 action：JS 函数调用，例如 `checkSite()`；也可能是网址。
    var action: String
}

enum SourceLoginForm {
    /// loginUi 原文 -> 可解析的 JSON 数组文本。<js>…</js> 与 @js: 由调用方提供的求值闭包执行。
    static func resolveUiText(_ raw: String?, evaluate: (String) -> String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        if raw.lowercased().hasPrefix("<js>") {
            var body = String(raw.dropFirst(4))
            if let r = body.range(of: "</js>", options: [.backwards, .caseInsensitive]) { body = String(body[..<r.lowerBound]) }
            return evaluate(body)
        }
        if raw.lowercased().hasPrefix("@js:") { return evaluate(String(raw.dropFirst(4))) }
        return raw
    }

    /// 解析字段，保留顺序。非法内容返回空数组，不崩溃。
    static func parseFields(_ text: String?) -> [LoginField] {
        guard let text = text, !SourceLoginJSON.isBlank(text) else { return [] }
        var parser = SourceLoginJSON.Parser(text, lenient: true)
        guard let doc = parser.parseDocument(), case .array(let items) = doc else { return [] }
        var out: [LoginField] = []
        for item in items {
            guard case .object(let members) = item else { continue }
            func text(_ key: String) -> String {
                for m in members.reversed() where m.key == key {
                    switch m.value {
                    case .string(let s): return s
                    case .number(let n): return n
                    case .bool(let b): return b ? "true" : "false"
                    default: return ""
                    }
                }
                return ""
            }
            let name = text("name")
            if name.isEmpty { continue }
            let kind: LoginField.Kind
            switch text("type").lowercased() {
            case "button": kind = .button
            case "password": kind = .password
            default: kind = .text
            }
            out.append(LoginField(id: out.count, name: name, kind: kind,
                                  defaultValue: text("default"), action: text("action")))
        }
        return out
    }

    /// 已保存的值优先，其次是 default。按钮不参与取值。
    static func initialValues(fields: [LoginField], saved: [String: String]) -> [String: String] {
        var v: [String: String] = [:]
        for f in fields where f.kind != .button { v[f.name] = saved[f.name] ?? f.defaultValue }
        return v
    }

    /// 序列化为登录信息 JSON（键按字典序，保证稳定）。
    static func encode(_ values: [String: String]) -> String {
        guard let d = try? JSONSerialization.data(withJSONObject: values, options: [.sortedKeys]),
              let s = String(data: d, encoding: .utf8) else { return "{}" }
        return s
    }

    /// 按钮 action 是函数调用还是网址。
    static func isURL(_ action: String) -> Bool {
        let t = action.trimmingCharacters(in: .whitespaces).lowercased()
        return t.hasPrefix("http://") || t.hasPrefix("https://")
    }

    /// 只有真正需要跳转的 http(s) 网址才交给内置浏览器。
    /// 其他协议（javascript:/file:/mailto:）与缺少主机名、含空白或换行的输入一律拒绝。
    static func browserURL(_ raw: String) -> String? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, t.count <= 2048,
              !t.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }),
              !t.contains(" "), isURL(t),
              let url = URL(string: t), url.scheme != nil,
              let host = url.host, !host.isEmpty else { return nil }
        return t
    }

    /// 在内置浏览器打开后的回显文案（只写主机名，不回显完整网址）。
    static func browserOpenText(_ raw: String) -> String {
        guard let target = browserURL(raw), let host = URL(string: target)?.host else {
            return "网址无法在内置浏览器打开"
        }
        return "已在内置浏览器打开 \(host)"
    }

    /// 登录按钮点击后的结果回显：脚本异常才算失败，空返回算已执行。
    static func resultText(action: String, outcome: Result<String, LoginScriptError>) -> (success: Bool, detail: String) {
        switch outcome {
        case .failure(let error):
            return (false, error.message)
        case .success(let value):
            let detail = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return (true, detail.isEmpty ? "已执行" : detail)
        }
    }

    /// 取 loginUrl 里的 JS（Legado 里 loginUrl 可以是函数库，也可以是网址）。
    static func loginScript(_ loginUrl: String?) -> String? {
        guard let t = loginUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        if isURL(t) || t.hasPrefix("/") { return nil }
        if t.lowercased().hasPrefix("@js:") { return String(t.dropFirst(4)) }
        if t.lowercased().hasPrefix("<js>") {
            var b = String(t.dropFirst(4))
            if let r = b.range(of: "</js>", options: [.backwards, .caseInsensitive]) { b = String(b[..<r.lowerBound]) }
            return b
        }
        return t
    }

    /// 是否显示登录入口：有 loginUi，或 loginUrl 是脚本/网址。
    static func hasLogin(_ source: BookSource) -> Bool {
        if !(source.loginUi ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        return loginScript(source.loginUrl) != nil || loginPageURL(source) != nil
    }

    /// 没有脚本的 loginUrl 视为网页登录地址。
    static func loginPageURL(_ source: BookSource) -> String? {
        guard let t = source.loginUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        if isURL(t) { return t }
        if t.hasPrefix("/") { return AnalyzeUrl.absolute(t, base: source.bookSourceUrl) }
        return nil
    }
}
