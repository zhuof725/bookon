import Foundation

/// `data:` 伪协议的元信息后缀回归。
///
/// 番茄系书源的 bookUrl 形如
///   `data:;base64,NzMyMDk1NTE0MzIwODMwNzc3NA==,{"type":"novel"}`
/// 其中 `,{"type":"novel"}` 不是请求选项，而是脚本要从 baseUrl 里读的元信息：
///   `JSON.parse(baseUrl.slice(baseUrl.indexOf('{')))`
/// 之前被当成请求选项吃掉 → `indexOf('{')` = -1 → `JSON.parse('=')` 报
/// “Unexpected token '='”，详情/目录整条链失效。
enum DataURLRegression {
    static func run(_ check: (Bool, String) -> Void) async throws {
        let bookUrl = "data:;base64,NzMyMDk1NTE0MzIwODMwNzc3NA==,{\"type\":\"novel\"}"
        let au = AnalyzeUrl(rawUrl: bookUrl, baseUrl: "https://fq.vv9v.cn")
        check(au.url.hasSuffix("{\"type\":\"novel\"}"), "data: URL 保留 {\"type\":\"novel\"} 元信息（实际 \(au.url)）")

        do {
            let (body, finalURL) = try await au.fetch()
            check(body == "37333230393535313433323038333037373734",
                  "data: 响应体是 hex（java.hexDecodeToString 可还原 id，实际 \(body.prefix(40))）")
            check(finalURL.hasSuffix("{\"type\":\"novel\"}"), "响应 URL 同样带元信息（脚本据此取 type）")
        } catch {
            check(false, "data: 请求失败：\(error)")
        }

        // 普通 http 的 `,{...}` 仍然必须是请求选项，不能被当成 URL 的一部分
        let http = AnalyzeUrl(rawUrl: "https://example.invalid/api?q=1,{\"method\":\"POST\",\"body\":\"a=1\"}")
        check(http.method == "POST", "http 的 ,{...} 仍按请求选项解析（method=POST）")
        check(!http.url.contains("{"), "http 选项不出现在 URL 里（实际 \(http.url)）")
    }
}
