import Foundation

/// 书源「源变量」：脚本里 `source.getVariable()` / `source.setVariable(v)` 读写的那一份字符串。
///
/// Legado 把它放在 CacheManager（键 `sourceVariable_<getKey()>`），不在书源 JSON 里；
/// 我们落到持久变量库，键名与 JSEngine prelude 里的
/// `java.storeGet('__var_' + this.bookSourceUrl)` 完全一致。
/// 编辑书源页面的「源变量」输入框也走这里，保存后脚本下一次求值立刻能读到。
enum SourceVariable {
    /// 存储键。改这里必须同步改 prelude 里的 `'__var_'` 前缀，
    /// `SourceVariableRegression` 会验证两边一致。
    static let keyPrefix = "__var_"

    static func key(_ sourceURL: String) -> String { keyPrefix + sourceURL }

    static func get(_ sourceURL: String) -> String {
        guard !sourceURL.isEmpty else { return "" }
        return JavaBridge.store.get(key(sourceURL)) ?? ""
    }

    static func set(_ value: String, for sourceURL: String) {
        guard !sourceURL.isEmpty else { return }
        let key = key(sourceURL)
        if value.isEmpty {
            JavaBridge.store.remove(key)
        } else {
            JavaBridge.store.set(key, value)
        }
    }

    /// 书源 URL 改名后把变量搬过去（编辑书源保存时用）。
    static func move(from oldURL: String, to newURL: String) {
        guard !oldURL.isEmpty, oldURL != newURL else { return }
        let value = get(oldURL)
        if !value.isEmpty { set(value, for: newURL) }
        JavaBridge.store.remove(key(oldURL))
    }
}
