import Foundation

struct HttpResponse {
    let data: Data
    let status: Int
    let headers: [String: String]
    let finalUrl: String
    let charsetHint: String?
    var text: String {
        if let cs = charsetHint, !cs.isEmpty { return Encodings.decode(data, charset: cs) }
        // Content-Type charset
        if let ct = headers.first(where: { $0.key.lowercased() == "content-type" })?.value,
           let r = ct.range(of: "charset=", options: .caseInsensitive) {
            let cs = ct[r.upperBound...].split(separator: ";").first.map(String.init)?.trimmingCharacters(in: CharacterSet(charactersIn: " \"'")) ?? ""
            if !cs.isEmpty { return Encodings.decode(data, charset: cs) }
        }
        if let s = String(data: data, encoding: .utf8) {
            // meta charset override for gbk pages that mislabel
            return s
        }
        // sniff meta
        let head = String(decoding: data.prefix(2048), as: UTF8.self).lowercased()
        if let r = head.range(of: "charset=") {
            let cs = head[r.upperBound...].prefix(while: { $0.isLetter || $0.isNumber || $0 == "-" })
            return Encodings.decode(data, charset: String(cs))
        }
        return Encodings.decode(data, charset: "gbk")
    }
}

/// 解析 Legado 的 URL 规则：`url,{options}`、`{{js}}`、`<js>..</js>`、`@js:`、分页 `<1,2,3>`、`{{key}}` `{{page}}`
struct AnalyzeUrl {
    var url: String
    var method = "GET"
    var headers: [String: String] = [:]
    var body: String?
    var charset: String?
    var type: String?
    var retry = 0
    var webView = false
    var baseUrl: String

    init(_ ruleUrl: String, key: String? = nil, page: Int? = nil, baseUrl: String, source: BookSource?, js: JSEngine?, extra: [String: Any] = [:]) {
        self.baseUrl = baseUrl
        var rule = ruleUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        if let k = key { js?.set("key", k) }
        if let p = page { js?.set("page", p) }
        js?.set("baseUrl", baseUrl)
        for (k, v) in extra { js?.set(k, v) }

        // 1) <js>…</js> / @js:
        rule = AnalyzeUrl.evalJsBlocks(rule, js: js)
        // 2) {{ }}
        if rule.contains("{{") {
            rule = RuleAnalyzer.innerRule(rule) { inner in
                let t = inner.trimmingCharacters(in: .whitespaces)
                if t == "key" { return key ?? "" }
                if t == "page" { return page.map(String.init) ?? "" }
                return js?.evalString(inner) ?? ""
            }
        }
        // 3) <1,2,3> 分页
        if let p = page, let re = try? NSRegularExpression(pattern: "<(.*?)>") {
            let ns = rule as NSString
            for m in re.matches(in: rule, range: NSRange(location: 0, length: ns.length)).reversed() {
                let pages = ns.substring(with: m.range(at: 1)).components(separatedBy: ",")
                let rep = (p <= pages.count ? pages[p - 1] : pages.last ?? "").trimmingCharacters(in: .whitespaces)
                rule = (rule as NSString).replacingCharacters(in: m.range, with: rep)
            }
        }
        // 4) 拆 options
        var urlPart = rule
        if let r = rule.range(of: #"\s*,\s*(?=\{)"#, options: .regularExpression) {
            urlPart = String(rule[..<r.lowerBound])
            let optStr = String(rule[r.upperBound...])
            if let d = optStr.data(using: .utf8), let o = (try? JSONSerialization.jsonObject(with: d, options: [.fragmentsAllowed])) as? [String: Any] {
                if let m = J.str(o["method"]) { method = m.uppercased() }
                if let h = o["headers"] as? [String: Any] { for (k, v) in h { headers[k] = J.str(v) ?? "" } }
                else if let hs = o["headers"] as? String, let hd = hs.data(using: .utf8), let h = (try? JSONSerialization.jsonObject(with: hd)) as? [String: Any] { for (k, v) in h { headers[k] = J.str(v) ?? "" } }
                if let b = o["body"] { body = (b as? String) ?? J.str(b) }
                charset = J.str(o["charset"])
                type = J.str(o["type"])
                retry = J.int(o["retry"]) ?? 0
                if let w = o["webView"] { webView = (J.bool(w) ?? false) || (J.str(w).map { !$0.isEmpty } ?? false) }
                if let jsStr = J.str(o["js"]), let js = js {
                    urlPart = js.evalString(jsStr, result: urlPart) ?? urlPart
                }
            }
        }
        url = NetworkUtils.absoluteURL(baseUrl, urlPart.trimmingCharacters(in: .whitespaces))
        // Encode query for GET
        if method == "GET", let q = url.firstIndex(of: "?") {
            let path = String(url[..<q]); let query = String(url[url.index(after: q)...])
            url = path + "?" + AnalyzeUrl.encodeQuery(query, charset: charset)
        } else if method == "POST", let b = body, !b.hasPrefix("{"), !b.hasPrefix("["), !b.hasPrefix("<"),
                  headers.first(where: { $0.key.lowercased() == "content-type" }) == nil {
            body = AnalyzeUrl.encodeQuery(b, charset: charset)
            headers["Content-Type"] = "application/x-www-form-urlencoded"
        }
    }

    static func evalJsBlocks(_ rule: String, js: JSEngine?) -> String {
        guard let re = try? NSRegularExpression(pattern: "<js>([\\w\\W]*?)</js>|@js:([\\w\\W]*)", options: .caseInsensitive) else { return rule }
        let ns = rule as NSString
        let matches = re.matches(in: rule, range: NSRange(location: 0, length: ns.length))
        if matches.isEmpty { return rule }
        var result = rule
        var start = 0
        for m in matches {
            if m.range.location > start {
                let seg = ns.substring(with: NSRange(location: start, length: m.range.location - start)).trimmingCharacters(in: .whitespaces)
                if !seg.isEmpty { result = seg.replacingOccurrences(of: "@result", with: result) }
            }
            let code = m.range(at: 1).location != NSNotFound ? ns.substring(with: m.range(at: 1)) : ns.substring(with: m.range(at: 2))
            result = js?.evalString(code, result: result) ?? ""
            start = m.range.location + m.range.length
        }
        if ns.length > start {
            let seg = ns.substring(from: start).trimmingCharacters(in: .whitespaces)
            if !seg.isEmpty { result = seg.replacingOccurrences(of: "@result", with: result) }
        }
        return result
    }

    static func encodeQuery(_ q: String, charset: String?) -> String {
        // already encoded?
        if q.range(of: "%[0-9A-Fa-f]{2}", options: .regularExpression) != nil, !q.contains(" ") { return q }
        return q.components(separatedBy: "&").map { pair -> String in
            guard let eq = pair.firstIndex(of: "=") else { return enc(pair, charset) }
            return enc(String(pair[..<eq]), charset) + "=" + enc(String(pair[pair.index(after: eq)...]), charset)
        }.joined(separator: "&")
    }
    private static func enc(_ s: String, _ charset: String?) -> String {
        if let c = charset?.lowercased(), c.contains("gb") { return Encodings.percentEncodeGBK(s) }
        if charset == "escape" { return s }
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.~*")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }
}

enum NetworkUtils {
    static func absoluteURL(_ base: String?, _ rel: String) -> String {
        let r = rel.trimmingCharacters(in: .whitespacesAndNewlines)
        if r.isEmpty { return base ?? "" }
        if r.hasPrefix("http://") || r.hasPrefix("https://") || r.hasPrefix("data:") || r.hasPrefix("file:") { return r }
        guard let b = base, let bu = URL(string: cleaned(b)) else { return r }
        if r.hasPrefix("//") { return (bu.scheme ?? "https") + ":" + r }
        return URL(string: encodeIfNeeded(r), relativeTo: bu)?.absoluteString ?? r
    }
    static func baseUrl(_ url: String) -> String {
        guard let u = URL(string: cleaned(url)), let host = u.host else { return url }
        var s = (u.scheme ?? "https") + "://" + host
        if let p = u.port { s += ":\(p)" }
        return s
    }
    private static func cleaned(_ u: String) -> String {
        if let r = u.range(of: #",\s*\{"#, options: .regularExpression) { return String(u[..<r.lowerBound]) }
        return u
    }
    private static func encodeIfNeeded(_ s: String) -> String {
        if URL(string: s) != nil { return s }
        var allowed = CharacterSet.urlQueryAllowed
        allowed.insert(charactersIn: "#[]")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }
}

final class CookieStore {
    static let shared = CookieStore()
    private let storage = HTTPCookieStorage.shared
    func cookieString(for urlOrTag: String, key: String?) -> String {
        guard let u = URL(string: urlOrTag), let cookies = storage.cookies(for: u) else { return "" }
        if let k = key { return cookies.first { $0.name == k }?.value ?? "" }
        return cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }
}

final class HttpClient {
    static let shared = HttpClient()
    static let defaultUA = "Mozilla/5.0 (Linux; Android 13; Pixel 6) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36"

    private let session: URLSession
    private init() {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 20
        cfg.timeoutIntervalForResource = 60
        cfg.httpCookieAcceptPolicy = .always
        cfg.httpShouldSetCookies = true
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: cfg)
    }

    func fetch(_ a: AnalyzeUrl, source: BookSource?, js: JSEngine?) async throws -> HttpResponse {
        guard let u = URL(string: a.url) else { throw NSError(domain: "BookOn", code: 1, userInfo: [NSLocalizedDescriptionKey: "无效地址: \(a.url)"]) }
        var req = URLRequest(url: u)
        req.httpMethod = a.method
        var h = source?.headerMap(js: js) ?? [:]
        for (k, v) in a.headers { h[k] = v }
        if h.first(where: { $0.key.lowercased() == "user-agent" }) == nil { h["User-Agent"] = HttpClient.defaultUA }
        for (k, v) in h { req.setValue(v, forHTTPHeaderField: k) }
        if a.method == "POST", let b = a.body {
            req.httpBody = Encodings.encode(b, charset: a.charset)
            if req.value(forHTTPHeaderField: "Content-Type") == nil {
                req.setValue(b.hasPrefix("{") || b.hasPrefix("[") ? "application/json" : "application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            }
        }
        var lastErr: Error?
        for _ in 0...max(0, a.retry) {
            do {
                let (data, resp) = try await session.data(for: req)
                let http = resp as? HTTPURLResponse
                var headers: [String: String] = [:]
                http?.allHeaderFields.forEach { headers["\($0.key)"] = "\($0.value)" }
                return HttpResponse(data: data, status: http?.statusCode ?? 0, headers: headers,
                                    finalUrl: http?.url?.absoluteString ?? a.url, charsetHint: a.charset)
            } catch { lastErr = error }
        }
        throw lastErr ?? URLError(.unknown)
    }

    // 同步版本供 JS 调用（JS 在后台线程运行）
    func fetchSync(urlRule: String, source: BookSource?, js: JSEngine?) -> HttpResponse? {
        let a = AnalyzeUrl(urlRule, baseUrl: source?.bookSourceUrl ?? "", source: source, js: nil)
        return fetchSync(a, source: source)
    }
    func fetchSync(url: String, method: String, headers: [String: String], body: String?, source: BookSource?) -> HttpResponse? {
        var a = AnalyzeUrl(url, baseUrl: source?.bookSourceUrl ?? "", source: source, js: nil)
        a.method = method; a.headers = headers; a.body = body
        return fetchSync(a, source: source)
    }
    private func fetchSync(_ a: AnalyzeUrl, source: BookSource?) -> HttpResponse? {
        let sem = DispatchSemaphore(value: 0)
        var result: HttpResponse?
        Task.detached { [self] in
            result = try? await self.fetch(a, source: source, js: nil)
            sem.signal()
        }
        _ = sem.wait(timeout: .now() + 30)
        return result
    }
}
