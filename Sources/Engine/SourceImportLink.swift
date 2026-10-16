import Foundation

/// 书源一键导入链接：与 Legado/阅读一致，支持
/// `yuedu://booksource/importonline?src=URL`、`legado://booksource/importonline?src=URL`、
/// `legado://import/bookSource?src=URL`。只识别书源，订阅源/替换规则等不处理。
enum SourceImportLink {
    static func sourceURL(_ url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), ["yuedu", "legado"].contains(scheme),
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let route = ((comps.host ?? "") + comps.path).lowercased()
        guard route.contains("booksource") else { return nil }
        guard let src = comps.queryItems?.first(where: { $0.name == "src" })?.value?
            .trimmingCharacters(in: .whitespacesAndNewlines), !src.isEmpty else { return nil }
        return src
    }
}
