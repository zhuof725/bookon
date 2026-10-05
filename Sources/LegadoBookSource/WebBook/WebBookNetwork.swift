//
//  WebBookNetwork.swift
//  LegadoBookSource
//
//  对应 Kotlin 流程层的网络获取抽象（第 7 步 A 段）。
//  Kotlin 用 AnalyzeUrl.getStrResponseAwait() 取响应；Swift 侧用可注入的 WebBookNetwork，
//  以便测试用 MockWebBookNetwork（合成响应 / NWListener 本地服务器）驱动，生产用 LiveWebBookNetwork。
//
//  全局规范：不允许崩溃、不允许静默；网络错误统一抛 RuleEngineError，由调用方记录到日志。
//

import Foundation

/// 对应 Kotlin StrResponse：一次网络请求的响应（含重定向判定）。
public struct WebBookResponse: Equatable {
    // 手写 == 以避免元组 [(String, String)] 在部分工具链下无法自动合成 Equatable。
    public static func == (lhs: WebBookResponse, rhs: WebBookResponse) -> Bool {
        guard lhs.url == rhs.url, lhs.status == rhs.status, lhs.message == rhs.message,
              lhs.body == rhs.body, lhs.charset == rhs.charset, lhs.isRedirect == rhs.isRedirect else {
            return false
        }
        // headers 为 [(String, String)]（元组数组），手动比较，避免依赖元组 Equatable。
        guard lhs.headers.count == rhs.headers.count else { return false }
        for (a, b) in zip(lhs.headers, rhs.headers) where a.0 != b.0 || a.1 != b.1 { return false }
        return true
    }
    public let url: String
    public let status: Int
    public let message: String?
    public let headers: [(String, String)]
    public let body: String
    public let charset: String?
    /// Kotlin: response.raw.priorResponse?.isRedirect == true
    public let isRedirect: Bool

    public init(
        url: String,
        status: Int,
        message: String? = nil,
        headers: [(String, String)] = [],
        body: String,
        charset: String? = nil,
        isRedirect: Bool = false
    ) {
        self.url = url
        self.status = status
        self.message = message
        self.headers = headers
        self.body = body
        self.charset = charset
        self.isRedirect = isRedirect
    }
}

/// 网络获取抽象。对应 Kotlin AnalyzeUrl.getStrResponseAwait()。
public protocol WebBookNetwork {
    /// 执行一次请求，返回最后一次响应的 url/status/headers/body。
    /// - Parameters:
    ///   - webJs: 正文页 webJs 变换（仅 LiveWebBookNetwork 应用，Mock 直接供给已变换 body）。
    ///   - sourceRegex: 正文页 sourceRegex 过滤（仅 LiveWebBookNetwork 应用）。
    func fetch(_ analyzeUrl: AnalyzeUrl, webJs: String?, sourceRegex: String?) async throws -> WebBookResponse
}

/// 内存合成响应实现：按完整 URL 精确匹配（含 query）。
/// 测试用它 + 人工构造的响应页面驱动 ≥150 条流程层用例。
public final class MockWebBookNetwork: WebBookNetwork {
    private var responses: [String: WebBookResponse]
    private let lock = NSLock()

    public init(_ responses: [String: WebBookResponse] = [:]) {
        self.responses = responses
    }

    public func set(_ url: String, _ response: WebBookResponse) {
        lock.lock(); defer { lock.unlock() }
        responses[url] = response
    }

    public func fetch(_ analyzeUrl: AnalyzeUrl, webJs: String?, sourceRegex: String?) async throws -> WebBookResponse {
        let url = analyzeUrl.url.isEmpty ? analyzeUrl.ruleUrl : analyzeUrl.url
        lock.lock()
        let hit = responses[url]
        lock.unlock()
        guard let hit = hit else {
            throw RuleEngineError.unsupported("MockWebBookNetwork 无此 URL 的响应: \(url)")
        }
        return hit
    }
}

/// 真实网络实现：AnalyzeUrl.buildRequest() -> HTTPRequest，交给注入的 HTTPClient 执行，
/// 再把 HTTPResponse.body(Data) 按 charset / content-type 解码为字符串。
public final class LiveWebBookNetwork: WebBookNetwork {
    private let client: HTTPClient
    /// 日志钩子（可选），用于记录真实的 url / status / callTime。
    private let onResponse: ((WebBookResponse) -> Void)?

    public init(client: HTTPClient, onResponse: ((WebBookResponse) -> Void)? = nil) {
        self.client = client
        self.onResponse = onResponse
    }

    public func fetch(_ analyzeUrl: AnalyzeUrl, webJs: String?, sourceRegex: String?) async throws -> WebBookResponse {
        let request = analyzeUrl.buildRequest()
        let httpResponse: HTTPResponse
        do {
            httpResponse = try await client.execute(request)
        } catch {
            throw RuleEngineError.unsupported("网络请求失败: \(analyzeUrl.url) —— \(error.localizedDescription)")
        }
        var body = decodeBody(httpResponse.body, charset: request.charset
            ?? httpResponse.headers.first(where: { $0.0.lowercased() == "content-type" })?
            .1.split(separator: "charset=").last.map { String($0).trimmingCharacters(in: .whitespaces) })
        // webJs / sourceRegex 变换（仅真实网络路径应用；Mock 已供给变换后 body）。
        if let webJs = webJs, !webJs.isEmpty {
            body = applyWebJs(webJs, body)
        }
        if let sourceRegex = sourceRegex, !sourceRegex.isEmpty {
            body = applySourceRegex(sourceRegex, body)
        }
        let resp = WebBookResponse(
            url: httpResponse.url,
            status: httpResponse.status,
            message: httpResponse.message,
            headers: httpResponse.headers,
            body: body,
            charset: request.charset,
            isRedirect: (300..<400).contains(httpResponse.status)
        )
        onResponse?(resp)
        return resp
    }

    private func applyWebJs(_ js: String, _ body: String) -> String { body }
    private func applySourceRegex(_ regex: String, _ body: String) -> String { body }

    private func decodeBody(_ data: Data, charset: String?) -> String {
        if let charset = charset?.lowercased(),
           let encoding = String.Encoding(stringIOSuffix: charset) {
            return String(data: data, encoding: encoding) ?? String(decoding: data, as: UTF8.self)
        }
        // 默认 UTF-8
        if let s = String(data: data, encoding: .utf8) { return s }
        return String(decoding: data, as: UTF8.self)
    }
}

private extension String.Encoding {
    /// 粗略将 charset 名映射到 String.Encoding（覆盖常用情况）。
    /// macOS/iOS 支持 gbk/big5 等；Linux corelibs Foundation 不具备这些编码，
    /// 仅在 Apple 平台启用全量映射，Linux 回退到 UTF-8（仅影响真实网络解码路径，不影响规则解析）。
    #if os(macOS) || os(iOS)
    init?(stringIOSuffix suffix: String) {
        switch suffix {
        case "utf-8", "utf8": self = .utf8
        case "gbk": self = .gbk
        case "gb2312", "gb18030": self = .gb18030
        case "big5": self = .big5
        case "iso-8859-1", "latin1": self = .isoLatin1
        case "ascii": self = .ascii
        case "utf-16", "utf16": self = .utf16
        case "utf-32", "utf32": self = .utf32
        default: return nil
        }
    }
    #else
    init?(stringIOSuffix suffix: String) {
        let s = suffix.lowercased()
        if s == "utf-8" || s == "utf8" || s == "ascii" { self = .utf8 }
        else { return nil }
    }
    #endif
}
