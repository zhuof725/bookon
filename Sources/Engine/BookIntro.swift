import Foundation

/// 书籍简介的呈现形态，与原版 `BookInfo` / `BookInfoActivity` 对齐：
///
/// - `<useweb>…</useweb>`：整段 HTML 交给 WebView 渲染（**支持 CSS**），原版注释「支持使用浏览器渲染」
/// - `<usehtml>…</usehtml>`：轻量 HTML（原版用 TextView.setHtml，我们同样交给 WebView）
/// - `<md>…</md>`：Markdown
/// - 其他：按 `HtmlFormatter.formatIntro` 归一成纯文本
///
/// 详情解析时带标记的简介必须**原样保留**，否则 `displayIntro` 会把 `<div style=…>`、
/// `<svg>` 一起抹平（番茄系聚合源的「作品简介/作品数据」卡片就是这样丢掉的）。
enum BookIntro {
    enum Kind: Equatable {
        case text
        case html
        case markdown
        case web

        /// 需要 WebView 渲染（HTML/CSS）的形态。
        var isRich: Bool { self == .web || self == .html }
    }

    let kind: Kind
    /// 去掉包裹标签后的正文（`text` 时即纯文本）
    let body: String
    /// 原始简介（保留包裹标签）
    let raw: String

    /// 详情解析用：带标记的原样保留，其余归一成纯文本。空串返回 nil。
    static func normalized(_ value: String?) -> String? {
        guard let trimmed = trimmedValue(value) else { return nil }
        // 三种包裹标记（useweb/usehtml/md）都原样保留，交给展示层决定怎么渲染。
        if marker(in: trimmed) != nil { return trimmed }
        let flat = flatten(trimmed)
        return flat.isEmpty ? nil : flat
    }

    /// 展示用解析：区分纯文本 / HTML / Markdown / WebView。
    static func parse(_ value: String?) -> BookIntro? {
        guard let trimmed = trimmedValue(value) else { return nil }
        guard let (tag, kind) = marker(in: trimmed) else {
            return BookIntro(kind: .text, body: trimmed, raw: trimmed)
        }
        return BookIntro(kind: kind, body: unwrap(trimmed, opening: tag), raw: trimmed)
    }

    /// 列表 / 摘要处使用的纯文本（把 HTML 抹平）。
    var plainText: String {
        kind == .text ? body : flatten(body)
    }

    /// 富文本渲染用的正文。
    /// `<usehtml>` 里的按钮写成 `点我@onclick:java.toast("…")`（原版点按钮执行脚本），
    /// 我们把动作源码去掉，至少不会把 JS 当文字显示出来。
    var renderBody: String {
        guard kind == .html else { return body }
        return body.replacingOccurrences(of: "@onclick:[^<]*", with: "",
                                         options: [.regularExpression, .caseInsensitive])
    }

    /// 与原版 `HtmlFormatter.formatIntro` 同口径的纯文本归一：
    /// `<br>`/`</p>` 变换行、其余标签去掉、常用实体还原、压缩空行。
    static func flatten(_ value: String) -> String {
        var text = value
            .replacingOccurrences(of: "<br\\s*/?>|</p>", with: "\n",
                                  options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        for (entity, decoded) in [("&nbsp;", " "), ("&ensp;", " "), ("&emsp;", " "), ("&shy;", ""),
                                  ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
                                  ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'")] {
            text = text.replacingOccurrences(of: entity, with: decoded)
        }
        return text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private static func trimmedValue(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// 原版按 `intro.trimStart()` 判定这三种包裹标记。
    private static func marker(in value: String) -> (tag: String, kind: Kind)? {
        let lower = value.lowercased()
        for (tag, kind) in [("<useweb>", Kind.web), ("<usehtml>", Kind.html), ("<md>", Kind.markdown)]
        where lower.hasPrefix(tag) {
            return (tag, kind)
        }
        return nil
    }

    private static func unwrap(_ value: String, opening: String) -> String {
        var body = String(value.dropFirst(opening.count))
        let closing = "</" + opening.dropFirst()
        if body.lowercased().hasSuffix(closing) {
            body = String(body.dropLast(closing.count))
        }
        return body.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
