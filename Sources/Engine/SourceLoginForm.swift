import Foundation

/// 书源登录表单：把 loginUi（JSON 数组，可能是 <js>/@js: 脚本）解析成有序字段，
/// 并负责按 Legado 约定执行登录：保存表单 -> 运行 loginUrl 里的 login()；按钮 action 调用 loginUrl 里的函数。
struct LoginField: Equatable, Identifiable {
    /// text/password：输入框；button：可点按钮；select：下拉选择（chars 为选项）。
    enum Kind: Equatable { case text, password, button, select }
    var id: Int
    var name: String
    var kind: Kind
    var defaultValue: String
    /// 按钮/下拉的 action：JS 函数调用，例如 `checkSite()`；也可能是网址。
    var action: String
    /// select 的选项数组（loginUi 的 chars）。
    var options: [String] = []
    /// 显示名：viewName（去掉 JS 引号）优先，其次是 name。表单取值仍按 name。
    var title: String { displayName.isEmpty ? name : displayName }
    /// 内部存储：viewName 解出的显示名（空表示用 name）。
    var displayName: String = ""
    /// 书源 style.layout_flexBasisPercent：0.45 表示与下一个同类按钮并排，1 表示整行。
    var basisPercent: Double = 1
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
            case "select": kind = .select
            default: kind = .text
            }
            // loginUi 的 viewName 是 JS 表达式（如 `'✅ 塔读小说'`）：去掉引号后作为显示名。
            let display = RuleScanner.unquote(text("viewName")) ?? ""
            // select 的选项数组：chars: ["A","B"]；宽松 JSON 下也可能是字符串数组以外的形式。
            let options: [String] = {
                for m in members.reversed() where m.key == "chars" {
                    guard case .array(let items) = m.value else { return [] }
                    return items.map { item in
                        switch item {
                        case .string(let s): return s
                        case .number(let n): return n
                        case .bool(let b): return b ? "true" : "false"
                        default: return ""
                        }
                    }.filter { !$0.isEmpty }
                }
                return []
            }()
            // style.layout_flexBasisPercent：0.45 左右表示与相邻项并排；缺省或 1 为整行。
            var basis = 1.0
            for m in members.reversed() where m.key == "style" {
                if case .object(let styleMembers) = m.value {
                    for s in styleMembers.reversed() where s.key == "layout_flexBasisPercent" {
                        switch s.value {
                        case .number(let n): if let v = Double(n), v > 0, v < 1 { basis = v }
                        case .string(let t): if let v = Double(t), v > 0, v < 1 { basis = v }
                        default: break
                        }
                    }
                }
                break
            }
            out.append(LoginField(id: out.count, name: name, kind: kind,
                                  defaultValue: text("default"), action: text("action"),
                                  options: options, displayName: display,
                                  basisPercent: basis))
        }
        return out
    }

    /// 把有序的登录项排成行：并排（basis < 1）项两两成行；整行项独占一行。
    /// 只做布局，不改变顺序，不合并不同种类（输入框与按钮可以同排，与原版一致）。
    static func layoutRows(_ fields: [LoginField]) -> [[LoginField]] {
        var rows: [[LoginField]] = []
        var pending: LoginField?
        for field in fields {
            if field.basisPercent < 1, pending == nil {
                pending = field
                continue
            }
            if let first = pending {
                // 相邻两个并排项成一行；若第二个是整行项，先落单行再另起。
                if field.basisPercent < 1 {
                    rows.append([first, field])
                    pending = nil
                    continue
                }
                rows.append([first])
                pending = nil
            }
            if field.basisPercent < 1 {
                pending = field
            } else {
                rows.append([field])
            }
        }
        if let last = pending { rows.append([last]) }
        return rows
    }

    /// 已保存的值优先，其次是 default；再其次回落到第一个选项。按钮不参与取值。
    static func initialValues(fields: [LoginField], saved: [String: String]) -> [String: String] {
        var v: [String: String] = [:]
        for f in fields where f.kind != .button {
            let stored = saved[f.name] ?? f.defaultValue
            v[f.name] = !stored.isEmpty ? stored : (f.options.first ?? "")
        }
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

    /// 取 loginUrl 里的 JS（Legado 里 loginUrl 可以是函数库，也可以是网址）。
    /// 注意：很多书源的脚本库以 `//注释` 开头，不能把所有以 / 开头的输入都当网址。
    static func loginScript(_ loginUrl: String?) -> String? {
        guard let t = loginUrl?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        if isURL(t) || isWebPath(t) { return nil }
        if t.lowercased().hasPrefix("@js:") { return String(t.dropFirst(4)) }
        if t.lowercased().hasPrefix("<js>") {
            var b = String(t.dropFirst(4))
            if let r = b.range(of: "</js>", options: [.backwards, .caseInsensitive]) { b = String(b[..<r.lowerBound]) }
            return b
        }
        return t
    }

    /// 仅当以 / 开头且是单行、无空白、没有 JS 语法的短输入时，才视为网页登录路径。
    /// `/login` 是路径；`//注释...` 或多行脚本一定是 JS。
    static func isWebPath(_ t: String) -> Bool {
        guard t.hasPrefix("/"), !t.contains("\n"), !t.contains(" "),
              !t.contains("{"), !t.contains("}"), !t.contains(";"),
              !t.lowercased().contains("function") else { return false }
        return true
    }

    /// loginUi 是否本身就是脚本（<js> / @js:）。这类 loginUi 需要函数库才能求值，
    /// 求值失败时要给出提示，而不是显示「没有可用登录配置」。
    static func isScriptUI(_ raw: String?) -> Bool {
        guard let t = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return false }
        let lower = t.lowercased()
        return lower.hasPrefix("<js>") || lower.hasPrefix("@js:")
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
        if isWebPath(t) { return AnalyzeUrl.absolute(t, base: source.bookSourceUrl) }
        return nil
    }
}
