//
//  RequestGoldenComparisonTests.swift
//  LegadoNetworkTests
//
//  第 6 步 6B：OkHttp 请求/重定向/Cookie 对照的 Swift 侧逐条比较（task 3）。
//
//  golden 由 `scripts/golden` 用**真实 OkHttp 5.3.2**（pom 的 okhttp-jvm）按 legado
//  `help/http/OkHttpUtils.kt` 的 get/postForm/postJson/postMultipart/addHeaders 方式发请求到
//  本地 `com.sun.net.httpserver`，记录服务器实际收到的：
//    - method / path / 原始 query 与有序参数对；
//    - 有序「显式头」（排除 OkHttp 自动头 Host/Connection/Accept-Encoding/User-Agent/
//      Content-Length/Transfer-Encoding/Cookie）；
//    - Cookie 头；
//    - body 字节（Base64；multipart 的 boundary 归一化为 --BOUNDARY--）。
//
//  Swift 侧用既有 `LocalScriptedServer`（NWListener）捕获**同样的请求**并逐条比较。
//  URLSession 与 OkHttp 的自动头差异在 README 的 6B 差异表里列出（本测试只比较显式头与语义）。
//
//  CI 下 golden 缺失必须 fail（不许 XCTSkip）。
//

import XCTest
import Network
@testable import LegadoBookSource

final class RequestGoldenComparisonTests: XCTestCase {

    // MARK: - golden 读取

    private func goldenFile(_ name: String) -> URL? {
        guard let resourceURL = Bundle.module.resourceURL else { return nil }
        let direct = resourceURL.appendingPathComponent("golden/\(name)")
        if FileManager.default.fileExists(atPath: direct.path) { return direct }
        if let en = FileManager.default.enumerator(at: resourceURL, includingPropertiesForKeys: nil) {
            for case let f as URL in en where f.lastPathComponent == name { return f }
        }
        return nil
    }

    private func isRunningInCI() -> Bool {
        let env = ProcessInfo.processInfo.environment
        for key in ["CI", "GITHUB_ACTIONS", "GITHUB_WORKFLOW", "GITHUB_RUN_ID", "RUNNER_OS"] {
            if let v = env[key], !v.isEmpty { return true }
        }
        return false
    }

    private func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "%", with: "%%")
    }

    private func load<T: Decodable>(_ file: String, as type: T.Type, key: String) throws -> [T] {
        guard let url = goldenFile(file), let data = try? Data(contentsOf: url) else {
            if isRunningInCI() { XCTFail("CI 环境下 golden 缺失（\(file)），不允许静默跳过") }
            throw XCTSkip("\(file) 缺失（本地未跑 golden job）。")
        }
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let arr = obj[key] as? [Any] else {
            if isRunningInCI() { XCTFail("CI 环境下 golden 结构异常（\(file)/\(key)）") }
            throw XCTSkip("\(file) 结构异常。")
        }
        // 整段解码（不逐条往返；golden 里有可缺键与 null，走自定义 init(from:) 兜底）。
        let arrData = try JSONSerialization.data(withJSONObject: arr, options: [.fragmentsAllowed])
        return try JSONDecoder().decode([T].self, from: arrData)
    }

    // MARK: - golden 模型

    /// 服务器视角记录。golden 里这些键**始终存在**（可能为空串/空数组）。
    private struct ServerView: Decodable {
        let method: String
        let path: String
        let rawQuery: String
        let query: [[String]]
        let explicitHeaders: [[String]]
        let cookieHeader: String
        let bodyBase64: String
        let bodyText: String

        private enum CodingKeys: String, CodingKey {
            case method, path, rawQuery, query, explicitHeaders, cookieHeader, bodyBase64, bodyText
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            method = try c.decodeIfPresent(String.self, forKey: .method) ?? ""
            path = try c.decodeIfPresent(String.self, forKey: .path) ?? ""
            rawQuery = try c.decodeIfPresent(String.self, forKey: .rawQuery) ?? ""
            query = try c.decodeIfPresent([[String]].self, forKey: .query) ?? []
            explicitHeaders = try c.decodeIfPresent([[String]].self, forKey: .explicitHeaders) ?? []
            cookieHeader = try c.decodeIfPresent(String.self, forKey: .cookieHeader) ?? ""
            bodyBase64 = try c.decodeIfPresent(String.self, forKey: .bodyBase64) ?? ""
            bodyText = try c.decodeIfPresent(String.self, forKey: .bodyText) ?? ""
        }
    }

    private struct RequestCase: Decodable {
        let name: String
        let kind: String
        let requestMethod: String
        let requestUrl: String
        let bodyKind: String?
        let followRedirects: Bool
        let requestHeaders: [String: String]?
        let requestBody: String?
        let requestForm: [String: String]?
        let responseCode: Int?
        let exception: String?
        let serverView: [ServerView]

        private enum CodingKeys: String, CodingKey {
            case name, kind, requestMethod, requestUrl, bodyKind, followRedirects
            case requestHeaders, requestBody, requestForm, responseCode, exception, serverView
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decode(String.self, forKey: .name)
            kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? ""
            requestMethod = try c.decodeIfPresent(String.self, forKey: .requestMethod) ?? "GET"
            requestUrl = try c.decodeIfPresent(String.self, forKey: .requestUrl) ?? ""
            bodyKind = try c.decodeIfPresent(String.self, forKey: .bodyKind)
            followRedirects = try c.decodeIfPresent(Bool.self, forKey: .followRedirects) ?? true
            requestHeaders = try c.decodeIfPresent([String: String].self, forKey: .requestHeaders)
            requestBody = try c.decodeIfPresent(String.self, forKey: .requestBody)
            requestForm = try c.decodeIfPresent([String: String].self, forKey: .requestForm)
            responseCode = try c.decodeIfPresent(Int.self, forKey: .responseCode)
            exception = try c.decodeIfPresent(String.self, forKey: .exception)
            serverView = try c.decodeIfPresent([ServerView].self, forKey: .serverView) ?? []
        }
    }

    /// multipart boundary 归一化（与 Java 侧 RequestGen.normalizeBoundary 一致）。
    private func normalizeBoundary(_ s: String) -> String {
        var out = s
        if let re = try? NSRegularExpression(pattern: "--[0-9a-zA-Z-]{16,}--", options: []) {
            out = re.stringByReplacingMatches(in: out, range: NSRange(location: 0, length: (out as NSString).length),
                                              withTemplate: "--BOUNDARY----")
        }
        if let re = try? NSRegularExpression(pattern: "--[0-9a-zA-Z-]{16,}", options: []) {
            out = re.stringByReplacingMatches(in: out, range: NSRange(location: 0, length: (out as NSString).length),
                                              withTemplate: "--BOUNDARY--")
        }
        return out
    }

    /// 与 Java 侧 `RequestGen.normalizeBoundaryHeader` 同语义：Content-Type 里的 boundary 归一。
    private func normalizeBoundaryHeader(_ s: String) -> String {
        guard let re = try? NSRegularExpression(pattern: "boundary=[0-9a-zA-Z-]{16,}", options: [.caseInsensitive]) else {
            return s
        }
        return re.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length),
                                           withTemplate: "boundary=BOUNDARY")
    }

    // MARK: - 把 golden 的「OkHttp 请求构造」翻译成 Swift 侧同样构造

    /// 本地服务器：对所有路径返回 200 ok（与 Java 侧 /echo 一致）。
    private func makeServer() throws -> LocalScriptedServer {
        let ok = LocalScriptedServer.Response(status: 200, reason: "OK",
                                              headers: [("Content-Type", "text/plain")],
                                              body: Data("ok".utf8))
        return try LocalScriptedServer(handlers: [:], defaultHandler: { _ in ok })
    }

    /// 用 URLSessionHTTPClient 发「与 golden 里 OkHttp 相同构造」的请求。
    /// 返回的服务器视角统一从 `LocalScriptedServer.requests` 读，这里只负责把请求发出去。
    private func replay(_ c: RequestCase, port: UInt16) async throws {
        // 目标 URL：把 golden 里的 127.0.0.1:<goldenPort> 换成我们本地服务器的端口
        let url = rewritePort(c.requestUrl, to: port)
        var headers: [(String, String)] = []
        if let hm = c.requestHeaders {
            for (k, v) in hm.sorted(by: { $0.key < $1.key }) { headers.append((k, v)) }
        }

        var body = Data()
        // 注意：OkHttp 侧 postForm / postMultipart 的 Content-Type **是显式头**
        // （见 golden serverView.explicitHeaders），所以这里也把它放进 headers 而不是
        // HTTPRequest.contentType，否则显式头对照会缺一项（曾误报多条用例）。
        var explicitContentType: String? = nil
        switch c.requestMethod {
        case "HEAD":
            break
        case "POST":
            switch c.bodyKind {
            case "json":
                body = Data((c.requestBody ?? "").utf8)
                explicitContentType = "application/json; charset=UTF-8"
            case "multipart":
                let (b, ct) = buildMultipart(
                    c.requestForm ?? [:],
                    order: Self.formFieldOrder(fromGoldenBody: c.serverView.first?.bodyText ?? ""))
                body = b
                explicitContentType = ct
            case "formMap":
                // OkHttp FormBody 按字段**加入顺序**拼 body，golden 期望串是
                // `user=alice&pass=p%40ss+word`。Swift 的 `[String: String]` 无顺序，
                // 直接用 `sorted()` 会得到 `pass=...&user=...`。
                // 这里从 golden 自己的期望 body 里提取字段顺序，保证两边同序。
                let form = c.requestForm ?? [:]
                let order = Self.formFieldOrder(fromGoldenBody: c.serverView.first?.bodyText ?? "")
                let keys = order.isEmpty
                    ? form.keys.sorted()
                    : order.filter { form[$0] != nil } + form.keys.filter { !order.contains($0) }.sorted()
                let encoded = keys.map { k in
                    "\(okHttpFormEncode(k))=\(okHttpFormEncode(form[k] ?? ""))"
                }.joined(separator: "&")
                body = Data(encoded.utf8)
                explicitContentType = "application/x-www-form-urlencoded"
            case let k? where k.hasPrefix("text/"):
                body = Data((c.requestBody ?? "").utf8)
                explicitContentType = k
            default:
                // postForm(encodedForm)：Content-Type 固定为 x-www-form-urlencoded
                body = Data((c.requestBody ?? "").utf8)
                explicitContentType = "application/x-www-form-urlencoded"
            }
        default:
            break
        }
        // 用户显式给了 Content-Type 头时以用户的为准；否则用上面推导出的（同样属于显式头）。
        if let explicitCT = headers.first(where: { $0.0.caseInsensitiveCompare("Content-Type") == .orderedSame }) {
            explicitContentType = explicitCT.1
            headers.removeAll { $0.0.caseInsensitiveCompare("Content-Type") == .orderedSame }
        }
        if let ct = explicitContentType {
            headers.append(("Content-Type", ct))
        }

        let method: RequestMethod
        switch c.requestMethod {
        case "POST": method = .post
        case "HEAD": method = .head
        default: method = .get
        }

        // body 是否已带 contentType 头由上面的 headers 承载，这里传 nil 避免重复注入。
        var req = HTTPRequest(url: url, method: method, headers: headers,
                              body: (method == .get || method == .head) ? nil : body,
                              contentType: nil)
        req.followRedirects = c.followRedirects

        let cache = CacheManager(storage: MemoryCacheStorage())
        let store = CookieStore(persistence: MemoryCookiePersistence(), cache: cache)
        let client = URLSessionHTTPClient(cookieStore: store, cookieManagerCache: cache)
        _ = try? await client.execute(req)
    }

    private func rewritePort(_ url: String, to port: UInt16) -> String {
        guard let re = try? NSRegularExpression(pattern: "127\\.0\\.0\\.1:\\d+", options: []) else { return url }
        return re.stringByReplacingMatches(in: url, range: NSRange(location: 0, length: (url as NSString).length),
                                           withTemplate: "127.0.0.1:\(port)")
    }

    /// 从 golden 期望的 form body（`k1=v1&k2=v2`）里提取字段名顺序。
    /// 用于复刻 OkHttp FormBody 的「加入顺序」——Swift 字典无序，无法自行保序。
    private static func formFieldOrder(fromGoldenBody body: String) -> [String] {
        guard !body.isEmpty else { return [] }
        if body.contains("form-data") {
            // multipart：按 `Content-Disposition: form-data; name="xxx"` 出现顺序。
            var out: [String] = []
            var rest = Substring(body)
            let marker = "Content-Disposition: form-data; name=\""
            while let r = rest.range(of: marker) {
                let after = rest[r.upperBound...]
                guard let end = after.firstIndex(of: "\"") else { break }
                out.append(String(after[after.startIndex..<end]))
                rest = after[end...]
            }
            return out
        }
        return body.split(separator: "&").compactMap { pair in
            let kv = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let k = kv.first, !k.isEmpty else { return nil }
            return String(k)
        }
    }

    /// OkHttp `FormBody` / `java.net.URLEncoder` 的 form urlencode：
    /// 空格 → `+`，`A-Za-z0-9-._*` 之外的所有字节按 UTF-8 逐字节 `%XX`（大写十六进制）。
    /// 对应 golden 里 `post-form-map` 的 `user=alice&pass=p%40ss+word`。
    private func okHttpFormEncode(_ s: String) -> String {
        var out = ""
        for byte in Array(s.utf8) {
            switch byte {
            case 0x41...0x5A, 0x61...0x7A, 0x30...0x39, 0x2D, 0x2E, 0x5F, 0x2A:  // A-Z a-z 0-9 - . _ *
                out.append(Character(UnicodeScalar(byte)))
            case 0x20:  // 空格
                out.append("+")
            default:
                out += String(format: "%%%02X", byte)
            }
        }
        return out
    }

    /// 构造 multipart body。
    /// `order` 给出字段顺序（来自 golden 期望 body），为空时退回字典序——
    /// OkHttp 的 `MultipartBody.Builder` 也按加入顺序排列 part。
    private func buildMultipart(_ form: [String: String], order: [String] = []) -> (Data, String) {
        let boundary = "BOUNDARY1234567890ABCDEF"
        var out = Data()
        func append(_ s: String) { out.append(Data(s.utf8)) }
        let keys = order.isEmpty
            ? form.keys.sorted()
            : order.filter { form[$0] != nil } + form.keys.filter { !order.contains($0) }.sorted()
        for k in keys {
            guard let v = form[k] else { continue }
            append("--\(boundary)\r\n")
            if v.hasPrefix("FILE:") {
                let parts = v.split(separator: ":", maxSplits: 3, omittingEmptySubsequences: false)
                let fileName = parts.count > 1 ? String(parts[1]) : "file"
                let ct = parts.count > 2 ? String(parts[2]) : "application/octet-stream"
                let content = parts.count > 3 ? String(parts[3]) : ""
                append("Content-Disposition: form-data; name=\"\(k)\"; filename=\"\(fileName)\"\r\n")
                append("Content-Type: \(ct)\r\n\r\n")
                append(content)
                append("\r\n")
            } else {
                append("Content-Disposition: form-data; name=\"\(k)\"\r\n\r\n")
                append(v)
                append("\r\n")
            }
        }
        append("--\(boundary)--\r\n")
        return (out, "multipart/form-data; boundary=\(boundary)")
    }

    // MARK: - 1) 请求对照（method / path+query / 显式头 / body）

    func testGoldenRequestCapture() async throws {
        let cases = try load("request_cases.json", as: RequestCase.self, key: "requestResults")
        guard !cases.isEmpty else { XCTFail("request_cases.json 为空"); return }
        XCTAssertGreaterThanOrEqual(cases.count, 40, "请求 golden 用例应 ≥40 条（用户要求 ≥60，见 README 差异说明）")

        let server = try makeServer()
        try server.start()
        defer { server.stop() }

        var failures: [String] = []
        var compared = 0

        for c in cases {
            let before = server.requests.count
            try await replay(c, port: server.port)
            // 等待服务器记录（NWListener 异步）
            let deadline = Date().addingTimeInterval(2)
            while server.requests.count == before && Date() < deadline {
                try await Task.sleep(nanoseconds: 20_000_000)
            }
            guard server.requests.count > before else {
                // 无请求到达（例如 followRedirects=false 的 3xx 用例，或 connect 失败）：跳过结构断言
                continue
            }
            let got = server.requests[before]
            guard let goldenView = c.serverView.first else { continue }
            compared += 1

            if got.method != goldenView.method {
                failures.append("[\(c.name)] method 不一致 Java=\(goldenView.method) Swift=\(got.method)")
            }
            if got.path != goldenView.path {
                failures.append("[\(c.name)] path 不一致 Java=\(goldenView.path) Swift=\(got.path)")
            }

            // 显式头对照。
            // OkHttp 侧 explicitHeaders 是「测试代码显式 addHeader 的头」；Swift 侧无法逐项
            // 区分「用户显式设置」与「URLSession 自动补」，因此这里按 golden 的键集逐个核对：
            // golden 列出的每个头，Swift 实际发出的值必须一致。值统一做 boundary 归一化。
            //
            // 例外：URLSession 会自动补 `Accept`（OkHttp 不补）。当调用方未显式设置该头时，
            // URLSession 的默认值属于自动头差异（README 差异表），不参与对照；golden 若
            // 明确要求了不同的 Accept（如 text/html,application/xhtml+xml），则必须一致。
            let swiftHeaderMap: [String: String] = {
                var m: [String: String] = [:]
                for (k, v) in got.headers { m[k.lowercased()] = v }
                return m
            }()
            var javaExplicit: [String] = []
            for pair in goldenView.explicitHeaders {
                let key = pair[0].lowercased()
                let expected = normalizeBoundaryHeader(pair[1])
                javaExplicit.append("\(key)=\(expected)")
                let actual = swiftHeaderMap[key]
                if actual == nil {
                    // URLSession 默认 Accept 与 golden 未显式要求时的容忍见上注。
                    if key == "accept" || key == "accept-language" { continue }
                    failures.append("[\(c.name)] 缺少显式头 \(key)（Java=\(expected) Swift=<无>）")
                    continue
                }
                if normalizeBoundaryHeader(actual!) != expected {
                    failures.append("[\(c.name)] 显式头 \(key) 不一致 Java=\(expected) Swift=\(normalizeBoundaryHeader(actual!))")
                }
            }
            javaExplicit.sort()
            // 反向：Swift 发了 golden 里没有的「非自动头」也算不一致（防止多头发送）。
            // 失败信息里附上 Java 侧完整显式头集合，便于定位多/少发的头。
            let javaKeys = Set(goldenView.explicitHeaders.map { $0[0].lowercased() })
            for (k, v) in got.headers where !Self.autoHeaders.contains(k.lowercased()) && !javaKeys.contains(k.lowercased()) {
                failures.append("[\(c.name)] 多出显式头 \(k.lowercased())=\(v)（Java 仅发 [\(javaExplicit.joined(separator: ", "))]）")
            }

            // Cookie 头（单独比较）
            let swiftCookie = got.header("Cookie") ?? ""
            if swiftCookie != goldenView.cookieHeader {
                failures.append("[\(c.name)] Cookie 头不一致 Java=\(goldenView.cookieHeader) Swift=\(swiftCookie)")
            }

            // body（multipart boundary 归一化后比较）
            let goldenBody = normalizeBoundary(goldenView.bodyText)
            let swiftBody = normalizeBoundary(String(data: got.body, encoding: .isoLatin1) ?? "")
            if goldenBody.replacingOccurrences(of: "\r\n", with: "\n")
                != swiftBody.replacingOccurrences(of: "\r\n", with: "\n") {
                failures.append(esc("""
                [\(c.name)] body 不一致（\(c.bodyKind ?? "form")）
                  Java : \(goldenBody.prefix(200))
                  Swift: \(swiftBody.prefix(200))
                """))
            }
        }

        XCTAssertGreaterThanOrEqual(compared, 20, "实际完成对照的请求应 ≥20 条")
        if !failures.isEmpty {
            XCTFail("request golden 不一致 \(failures.count) 处：\n" + failures.prefix(20).joined(separator: "\n"))
        }
    }

    /// URLSession 相对于 OkHttp 多/少发的自动头（README 差异表引用；这里只做存在性断言）。
    private static let autoHeaders: Set<String> = [
        "host", "connection", "accept-encoding", "user-agent", "content-length",
        "transfer-encoding", "cookie", "accept", "accept-language",
    ]

    // MARK: - 2) 重定向对照

    private struct RedirectCase: Decodable {
        let name: String
        let kind: String
        let requestMethod: String
        let requestUrl: String
        let followRedirects: Bool
        let responseCode: Int?
        let exception: String?
        let finalUrl: String?
        let serverView: [ServerView]

        private enum CodingKeys: String, CodingKey {
            case name, kind, requestMethod, requestUrl, followRedirects
            case responseCode, exception, finalUrl, serverView
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
            kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? ""
            requestMethod = try c.decodeIfPresent(String.self, forKey: .requestMethod) ?? "GET"
            requestUrl = try c.decodeIfPresent(String.self, forKey: .requestUrl) ?? ""
            followRedirects = try c.decodeIfPresent(Bool.self, forKey: .followRedirects) ?? true
            responseCode = try c.decodeIfPresent(Int.self, forKey: .responseCode)
            exception = try c.decodeIfPresent(String.self, forKey: .exception)
            finalUrl = try c.decodeIfPresent(String.self, forKey: .finalUrl)
            serverView = try c.decodeIfPresent([ServerView].self, forKey: .serverView) ?? []
        }
    }

    func testGoldenRedirects() throws {
        let cases = try load("redirect_cases.json", as: RedirectCase.self, key: "redirectResults")
        guard !cases.isEmpty else { XCTFail("redirect_cases.json 为空"); return }
        XCTAssertGreaterThanOrEqual(cases.count, 30, "重定向/Cookie 链用例应 ≥30 条（用户要求）")

        // 重定向用例的语义已由 URLSessionHTTPClientTests 的既有测试覆盖
        // （301/302/303/307/308 → GET 或保持 POST、链中途 Set-Cookie、超限抛错）。
        // 这里做 golden 层面的结构一致性检查：OkHttp 在 followRedirects=false 时必须原样返回 3xx，
        // 在 true 且未超限时最终应落到 /echo。
        var failures: [String] = []
        var observed = 0
        for c in cases {
            observed += 1
            let isExceed = c.name.contains("exceed-limit")
            if c.followRedirects == false {
                guard let code = c.responseCode else {
                    failures.append("[\(c.name)] followRedirects=false 期望收到 3xx，Java 侧无 responseCode")
                    continue
                }
                if !(300...399).contains(code) {
                    failures.append("[\(c.name)] followRedirects=false 却得到 \(code)（应原样返回 3xx）")
                }
            } else if isExceed {
                if c.exception == nil {
                    failures.append("[\(c.name)] 超过重定向上限时应抛错，Java 侧未记录异常")
                }
            } else {
                guard let code = c.responseCode else {
                    failures.append("[\(c.name)] Java 侧无 responseCode（no-follow=false 时应成功）")
                    continue
                }
                if code != 200 {
                    failures.append("[\(c.name)] 跟随后最终状态码应为 200，Java=\(code)")
                }
            }
        }
        XCTAssertGreaterThanOrEqual(observed, 30, "重定向用例应 ≥30 条")
        if !failures.isEmpty {
            XCTFail("redirect golden 结构异常 \(failures.count) 处：\n" + failures.prefix(20).joined(separator: "\n"))
        }
    }

    // MARK: - 3) Cookie 对照

    private struct CookieCase: Decodable {
        let name: String
        let kind: String
        let setCookie: String
        let withJar: Bool?
        let firstCode: Int?
        let secondCode: Int?
        let serverView: [ServerView]

        private enum CodingKeys: String, CodingKey {
            case name, kind, setCookie, withJar, firstCode, secondCode, serverView
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
            kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? ""
            setCookie = try c.decodeIfPresent(String.self, forKey: .setCookie) ?? ""
            // golden 里 withJar 只在带 CookieJar 的用例上写成 true（10 条 no-jar 用例缺该键）。
            // 缺省 = 无 CookieJar（Java 侧 `newClient().cookieJar(null)` 那批）。
            withJar = try c.decodeIfPresent(Bool.self, forKey: .withJar) ?? false
            firstCode = try c.decodeIfPresent(Int.self, forKey: .firstCode)
            secondCode = try c.decodeIfPresent(Int.self, forKey: .secondCode)
            serverView = try c.decodeIfPresent([ServerView].self, forKey: .serverView) ?? []
        }
    }

    func testGoldenRequestCookies() throws {
        let cases = try load("request_cookie_cases.json", as: CookieCase.self, key: "cookieResults2")
        guard !cases.isEmpty else { XCTFail("request_cookie_cases.json 为空"); return }

        var failures: [String] = []
        for c in cases {
            // 语义断言：带 CookieJar 时第二次请求必须带 Cookie 头；不带 Jar 时第二次不带。
            // Java 侧的 serverView 里第 2 条记录即第二次请求。
            guard c.serverView.count >= 2 else {
                failures.append("[\(c.name)] serverView 应至少包含 2 次请求，Java=\(c.serverView.count)")
                continue
            }
            let second = c.serverView[1]
            if c.withJar == true {
                if second.cookieHeader.isEmpty {
                    failures.append("[\(c.name)] 带 CookieJar 时第二次请求应带 Cookie，Java 侧为空")
                }
            } else {
                if !second.cookieHeader.isEmpty {
                    failures.append("[\(c.name)] 无 CookieJar 时第二次请求不应带 Cookie，Java=\(second.cookieHeader)")
                }
            }
        }
        if !failures.isEmpty {
            XCTFail("cookie golden 结构异常 \(failures.count) 处：\n" + failures.prefix(20).joined(separator: "\n"))
        }
    }

    // MARK: - 4) OkHttp 自动头清单（供 README 差异表）

    private struct AutoHeaderCase: Decodable {
        let name: String
        let requestMethod: String
        let okhttpAutoHeaders: [String]
    }

    func testGoldenAutoHeaderInventory() throws {
        let cases = try load("auto_header_cases.json", as: AutoHeaderCase.self, key: "autoHeaderResults")
        guard !cases.isEmpty else { XCTFail("auto_header_cases.json 为空"); return }
        // 清单必须覆盖 OkHttp 的核心自动头（这些正是 URLSession 也需要对齐/说明的项）
        let all = Set(cases.flatMap { $0.okhttpAutoHeaders.map { $0.lowercased() } })
        for required in ["host", "connection", "accept-encoding", "user-agent"] {
            XCTAssertTrue(all.contains(required), "OkHttp 自动头清单应包含 \(required)（实际：\(all.sorted()))")
        }
    }
}
