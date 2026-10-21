import Foundation

/// 书源事件回调（原版 SourceCallBack）。只有 `eventListener == true` 且
/// `ruleContent.callBackJs` 非空时才执行；事件名与 Legado 一致。
enum SourceCallBack {
    static let addBookShelf = "addBookShelf"
    static let delBookShelf = "delBookShelf"
    static let saveRead = "saveRead"
    static let startRead = "startRead"
    static let endRead = "endRead"
    static let clickCustomButton = "clickCustomButton"

    @discardableResult
    static func fire(_ event: String, source: BookSource?, book: Book?,
                     chapter: BookChapter? = nil, result: String? = nil) -> String? {
        guard let source, source.eventListener ?? false,
              let js = source.ruleContent?.callBackJs?.trimmingCharacters(in: .whitespacesAndNewlines),
              !js.isEmpty else { return nil }
        let context = RuleContext(source: source, book: book, chapter: chapter)
        var vars: [String: Any] = ["event": event]
        if let result { vars["result"] = result }
        let value = JSEngine.shared.eval(js, result: result ?? "",
                                         baseUrl: book?.bookUrl ?? source.bookSourceUrl,
                                         vars: vars, jsLib: source.jsLib, context: context)
        if let error = JSEngine.lastError {
            DebugLog.add("◇callBackJs(\(event)) 失败：\(error)")
        }
        if let text = value as? String { return text }
        if let value { return "\(value)" }
        return nil
    }
}
