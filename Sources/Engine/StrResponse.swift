import Foundation
import JavaScriptCore

/// Native response storage, retaining the existing body/url/code properties.
/// Kotlin StrResponse and Jsoup Connection.Response are distinct contracts.
/// JavaScript wrappers live in JSEngine; a primitive code/url property cannot
/// simultaneously be a same-named callable method without breaking strict equality.
@objc protocol StrResponseExports: JSExport {
    var url: String { get }
    var body: String { get }
    var code: Int { get }
    var length: Int { get }
    func toString() -> String
    func valueOf() -> String
    func isSuccessful() -> Bool
    func headers() -> [String: String]
    func header(_ name: String) -> String
    func cookie(_ name: String) -> String
    /// OkHttp body().bytes()：JS 侧 body().bytes() 入口（loginCheckJs 需要）
    func bodyAsBytes() -> [Int]
}

@objc final class StrResponse: NSObject, StrResponseExports {
    let url: String
    let body: String
    let code: Int
    let length: Int
    /// 响应原始字节：二进制响应有，文本响应由 body encode。
    private let rawData: Data?
    private let responseHeaders: [String: String]

    /// Zero explicitly means unknown/non-HTTP status, never HTTP success.
    init(url: String, body: String, code: Int = 0, headers: [String: String] = [:], rawData: Data? = nil) {
        self.url = url
        self.body = body
        self.code = code
        self.length = rawData?.count ?? body.count
        self.rawData = rawData
        self.responseHeaders = headers
        super.init()
    }

    convenience init(_ response: HTTPResponseData) {
        self.init(url: response.url, body: response.body,
                  code: response.code, headers: response.headers, rawData: response.rawData)
    }

    /// 响应字节（原始为准，文本响应则用 utf8）。OkHttp body().bytes() 的直接对应。
    var bodyBytes: Data { rawData ?? Data(body.utf8) }

    @objc func bodyAsBytes() -> [Int] { SourceCrypto.toSigned(bodyBytes) }

    @objc func toString() -> String { body }
    @objc func valueOf() -> String { body }
    @objc func isSuccessful() -> Bool { (200...299).contains(code) }
    @objc func headers() -> [String: String] { responseHeaders }

    @objc func header(_ name: String) -> String {
        responseHeaders.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value ?? ""
    }

    @objc func cookie(_ name: String) -> String {
        let raw = header("Set-Cookie")
        for item in raw.split(separator: ";") {
            let pair = item.split(separator: "=", maxSplits: 1).map(String.init)
            if pair.count == 2 && pair[0].trimmingCharacters(in: .whitespaces) == name {
                return pair[1].trimmingCharacters(in: .whitespaces)
            }
        }
        return ""
    }
}
