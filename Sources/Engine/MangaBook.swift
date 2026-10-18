import Foundation

/// 漫画书源支持（bookSourceType == 2，图片源）。
/// 与原版 legado 一致：正文规则输出的是一串 `<img>` 标签（武芊漫画这类源用 JS 把
/// `$.data[*].image` 的图片地址逐行包成标签），阅读器从中取出图片地址，按章节
/// 组成可连续滚动的图片列表。
enum MangaBook {
    /// 是否漫画/图片书源。原版在书架打开书籍时按 bookSourceType == 2 进入漫画阅读器。
    static func isManga(source: BookSource?) -> Bool {
        source?.bookSourceType == 2
    }

    /// 从正文规则输出中提取图片地址，对应原版 `BookHelp.flowImages`：
    /// - `AppPattern.imgPattern` 的宽松匹配（以双引号为主，兼容单引号/无引号）；
    /// - 相对地址相对章节地址转绝对（`NetworkUtils.getAbsoluteURL`）；
    /// - `javascript:` 丢弃，`data:` 原样保留；
    /// - 连续重复的地址只保留一个（对应原版 `distinctUntilChanged`）。
    static func imageURLs(in content: String, baseURL: String) -> [String] {
        guard !content.isEmpty else { return [] }
        let pattern = "<img\\b[^>]*?\\bsrc\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s\"'>]+))"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let ns = content as NSString
        var out: [String] = []
        for match in regex.matches(in: content, range: NSRange(location: 0, length: ns.length)) {
            var raw: String?
            for group in 1...3 where match.range(at: group).location != NSNotFound {
                raw = ns.substring(with: match.range(at: group))
                break
            }
            guard var src = raw?.trimmingCharacters(in: .whitespacesAndNewlines) else { continue }
            src = src.replacingOccurrences(of: "&amp;", with: "&")
            guard !src.isEmpty else { continue }
            let lower = src.lowercased()
            if lower.hasPrefix("javascript") { continue }
            if !lower.hasPrefix("data:") {
                src = AnalyzeUrl.absolute(src, base: baseURL)
            }
            guard !src.isEmpty else { continue }
            // 原版只去掉相邻的重复项；同章里隔位重复的图片仍然保留。
            if out.last == src { continue }
            out.append(src)
        }
        return out
    }

    /// 目录里的「阅读 X / 已读完 X」分章标记文案（与原文案一致）。
    static func chapterStartTitle(_ title: String) -> String { "阅读 \(title)" }
    static func chapterEndTitle(_ title: String) -> String { "已读完 \(title)" }
}
