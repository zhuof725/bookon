import Foundation
import SwiftSoup

/// 站点搜索表单兜底。
///
/// 有些站点的搜索**只接受 POST**（页面表单 `<form method="post">`），
/// 书源却把搜索写成 GET：GET 会返回 /200 但列表为空。原版 Legado 同样搜不到，
/// 但用户体验上"换个 App 就能搜"，所以这里在**搜索无结果时**自动读一次搜索页的表单，
/// 用它的 action + 隐藏字段 + 关键词重新 POST 一次，再交给原来的 ruleSearch 解析。
///
/// 只做一次，不改书源、不改配置。
enum SearchFormFallback {
    /// 返回 POST 的响应（body + 最终地址）；站点没有可用 POST 表单时返回 nil。
    static func postSearch(source: BookSource, key: String, page: Int,
                           pageBody: String, pageURL: String) async -> HTTPResponseData? {
        guard let doc = try? SwiftSoup.parse(pageBody, pageURL) else { return nil }
        guard let forms = try? doc.select("form"), !forms.isEmpty else { return nil }

        // 优先「method=post 且有文本输入框」的表单。
        var chosen: Element?
        var keywordField: String?
        var keywordType: String?
        for form in forms {
            let method = ((try? form.attr("method")) ?? "").lowercased()
            guard method == "post" else { continue }
            guard let inputs = try? form.select("input"), !inputs.isEmpty else { continue }
            for input in inputs {
                let type = ((try? input.attr("type")) ?? "text").lowercased()
                guard ["text", "search", ""].contains(type) else { continue }
                let name = ((try? input.attr("name")) ?? "").trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { continue }
                chosen = form
                keywordField = name
                keywordType = type
                break
            }
            if chosen != nil { break }
        }
        guard let form = chosen, let field = keywordField else { return nil }
        _ = keywordType

        // 表单 charset（accept-charset）优先，其次书源 searchUrl 里的 charset，最后 utf-8。
        let formCharset = ((try? form.attr("accept-charset")) ?? "")
            .trimmingCharacters(in: .whitespaces).lowercased()

        var pairs: [String] = []
        if let inputs = try? form.select("input") {
            for input in inputs {
                let name = ((try? input.attr("name")) ?? "").trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty, name != field else { continue }
                let type = ((try? input.attr("type")) ?? "text").lowercased()
                guard ["hidden", "text", "search", "submit"].contains(type) || type.isEmpty else { continue }
                let value = (try? input.attr("value")) ?? ""
                pairs.append("\(name)=\(value)")
            }
        }
        pairs.append("\(field)=\(key)")
        let body = pairs.joined(separator: "&")

        var action = ((try? form.attr("action")) ?? "").trimmingCharacters(in: .whitespaces)
        if action.isEmpty { action = pageURL }
        let target = AnalyzeUrl.absolute(action, base: pageURL)

        var charset = formCharset
        if charset.isEmpty { charset = searchCharset(source: source) }
        if charset.isEmpty { charset = "utf-8" }

        var request = AnalyzeUrl(rawUrl: target, key: key, page: page,
                                 baseUrl: source.bookSourceUrl, sourceHeader: source.header,
                                 context: RuleContext(source: source), jsLib: source.jsLib)
        request.method = "POST"
        request.body = body
        request.charset = charset
        DebugLog.add("≡搜索无结果，改用站点表单 POST（\(field)）重试")
        return try? await WebBook.fetch(request)
    }

    /// 从书源 searchUrl 的请求选项里取 charset。
    private static func searchCharset(source: BookSource) -> String {
        guard let raw = source.searchUrl,
              let r = raw.range(of: ",\\s*\\{", options: .regularExpression) else { return "" }
        let json = String(raw[r.lowerBound...])
        guard let object = AnalyzeUrl.looseJSON(json),
              let charset = object["charset"] as? String else { return "" }
        return charset.lowercased()
    }
}
