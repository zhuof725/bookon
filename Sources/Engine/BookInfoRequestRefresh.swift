import Foundation

/// Recovery is only for a saved, already-expanded request. Never rewrite the
/// book's persistent identity or invent credentials/signing algorithms.
enum BookInfoRequestRefresh {
    static func hasSavedHeaders(_ raw: String) -> Bool {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.hasPrefix("https://") || value.hasPrefix("http://"),
              !isDynamic(value),
              let boundary = value.range(of: ",\\s*\\{", options: .regularExpression),
              let data = String(value[value.index(after: boundary.lowerBound)...]).data(using: .utf8),
              let options = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let headers = options["headers"] as? [String: Any], !headers.isEmpty else { return false }
        return headers.values.contains { value in
            guard let text = value as? String else { return false }
            return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    static func isDynamic(_ rule: String) -> Bool {
        let value = rule.lowercased()
        return value.contains("@js:") || value.contains("<js>") || value.contains("{{")
    }

    static func nameKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
    }

    static func isReadOnlyHTTP(_ request: AnalyzeUrl) -> Bool {
        guard request.method == "GET", request.body == nil, !request.webView,
              request.webJs?.isEmpty != false,
              let url = URLComponents(string: request.url),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              url.host?.isEmpty == false, url.user == nil, url.password == nil else { return false }
        return true
    }

    static func canRefresh(source: BookSource, book: Book, request: AnalyzeUrl) -> Bool {
        book.origin == source.bookSourceUrl && hasSavedHeaders(book.bookUrl)
            && isReadOnlyHTTP(request)
            && !nameKey(book.name).isEmpty && !nameKey(book.author).isEmpty
            && source.searchUrl?.isEmpty == false
            && source.ruleBookInfo?.name?.isEmpty == false
            && source.ruleBookInfo?.author?.isEmpty == false
            && isDynamic(source.ruleSearch?.bookUrl ?? "")
    }

    static func matches(_ candidate: Book, saved: Book, request: AnalyzeUrl, savedRequest: AnalyzeUrl) -> Bool {
        candidate.origin == saved.origin
            && nameKey(candidate.name) == nameKey(saved.name)
            && nameKey(candidate.author) == nameKey(saved.author)
            && isReadOnlyHTTP(request)
            // Query parameters may be book identifiers: do not drop, sort,
            // normalize or guess which ones are safe to ignore.
            && request.url == savedRequest.url
    }

    static func headersChanged(_ request: AnalyzeUrl, from saved: AnalyzeUrl) -> Bool {
        func normalized(_ headers: [String: String]) -> [String: String] {
            Dictionary(headers.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { _, new in new })
        }
        return normalized(request.headers) != normalized(saved.headers)
    }

    static func httpError(_ status: Int, stage: String = "详情", note: String? = nil) -> URLError {
        let advice: String
        if let note { advice = note }
        else if status == 401 || status == 403 { advice = "请求被书源拒绝，请检查书源更新或登录状态。" }
        else if status == 429 { advice = "请求过于频繁，请稍后再试。" }
        else if status >= 500 { advice = "书源服务器暂时异常，请稍后再试。" }
        else { advice = "请检查书源规则或稍后重试。" }
        return URLError(.badServerResponse, userInfo: [
            NSLocalizedDescriptionKey: "书源\(stage)返回 HTTP \(status)。\(advice)已保留原有书架信息。",
            "LegadoHTTPStatus": status
        ])
    }

    static func invalidDetails() -> URLError {
        URLError(.cannotParseResponse, userInfo: [
            NSLocalizedDescriptionKey: "重新获取的详情为空或与书架书籍不一致，已保留原有信息。"
        ])
    }
}
