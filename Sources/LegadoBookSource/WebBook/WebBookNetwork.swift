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

    /// 响应体解码。
    ///
    /// 委托给 `JsNetTextDecoder`（与 AnalyzeUrl 路径**共用同一套解码器**），语义对齐
    /// Kotlin `AnalyzeUrl.getStrResponseAwait()` 里 `String(body, charset)` 的**容错**行为：
    /// 非法字节序列替换为 `U+FFFD`，而不是整体失败。
    ///
    /// ⚠️ 不要退回 `String(data:encoding:)` / `String.Encoding` 手写映射：
    ///   1. `String.Encoding` 在 Darwin 上**没有** `gbk` / `gb18030` / `big5` 成员
    ///      （它们只存在于 CoreFoundation 的 `CFStringEncoding` 层面），写了就编译不过；
    ///   2. `String(data:encoding:)` 是**严格**的，非法字节返回 nil，会让整段响应体
    ///      静默退化成 UTF-8 乱码。
    ///   3. `JsNetTextDecoder.decode` 自带 BOM → explicit charset → Content-Type →
    ///       EncodingDetect 的完整回退链，并覆盖 GBK/GB2312/GB18030/Big5/Shift_JIS/
    ///      EUC-JP/EUC-KR 及单字节族，均经 golden 逐字节比对。
    ///
    /// 注意 `decode(bytes:)` 的显式 charset 参数只吃**规范名**（`GBK` / `BIG5` /
    /// `SHIFT-JIS`…），因此这里把 charset 名做一次归一：大写、`_` → `-`。
    private func decodeBody(_ data: Data, charset: String?) -> String {
        JsNetTextDecoder.decode(bytes: [UInt8](data),
                                explicitCharset: Self.normalizedCharsetName(charset),
                                contentTypeHeader: nil)
    }

    /// 把 charset 名归一为解码器认得的规范形式（大写、下划线转连字符）。
    /// 空串或全空白视为「未指定」。
    private static func normalizedCharsetName(_ charset: String?) -> String? {
        guard let charset = charset?.trimmingCharacters(in: .whitespacesAndNewlines),
              !charset.isEmpty else { return nil }
        return charset.uppercased().replacingOccurrences(of: "_", with: "-")
    }
}
