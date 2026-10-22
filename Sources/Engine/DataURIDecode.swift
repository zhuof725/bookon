import Foundation

/// 正文 data: URI 的解码。与平台无关（不依赖 UIKit），便于离线回归；
/// UI 层用它在内存里还原图片，图片块与导出共用同一套规则。
enum DataURIDecode {
    /// 支持的形态：`data:image/png;base64,xxxx` 与 `data:image/svg+xml,<urlencoded>`。
    /// SVG（段评气泡）不是可导出的位图，返回 nil。
    /// base64 的 payload 只取第一个「,」之前的部分：书源常在地址后面接 `,{...}` 选项，
    /// 混进 base64 里会解不出来。
    static func data(_ src: String) -> Data? {
        guard src.hasPrefix("data:"), let comma = src.firstIndex(of: ",") else { return nil }
        let meta = src[..<comma].lowercased()
        var payload = String(src[src.index(after: comma)...])
        guard !meta.contains("svg") else { return nil }
        if meta.contains(";base64") {
            if let cut = payload.firstIndex(of: ",") { payload = String(payload[..<cut]) }
            var p = payload.replacingOccurrences(of: "\\s", with: "", options: .regularExpression)
            while p.count % 4 != 0 { p += "=" }
            return Data(base64Encoded: p)
        }
        return payload.removingPercentEncoding?.data(using: .utf8)
    }
}
