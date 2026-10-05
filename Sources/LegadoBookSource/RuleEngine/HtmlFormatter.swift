//
//  HtmlFormatter.swift
//  LegadoBookSource
//
//  对应 Kotlin: utils/HtmlFormatter.kt（第 7 步 A 段）。
//
//  逐行移植 Kotlin 的正则与替换顺序，不做任何「优化」：
//    format(html, otherRegex = otherHtmlRegex)
//      1. nbspRegex  (&nbsp;)+                       -> " "
//      2. espRegex   (&ensp;|&emsp;)                 -> " "
//      3. noPrintRegex (&thinsp;|&zwnj;|&zwj;|\u2009|\u200C|\u200D) -> ""
//      4. wrapHtmlRegex </?(?:div|p|br|hr|h\d|article|dd|dl)[^>]*> -> "\n"
//      5. commentRegex <!--[^>]*-->                  -> ""
//      6. otherRegex（默认 otherHtmlRegex）          -> ""
//      7. indent1Regex \s*\n+\s*                     -> "\n　　"
//      8. indent2Regex ^[\n\s]+                      -> "　　"
//      9. lastRegex   [\n\s]+$                       -> ""
//    formatKeepImg(html, redirectUrl)
//      同 format，但用 notImgHtmlRegex（保留 <img>），再把命中的 <img> 重写为
//      `<img src="绝对地址[+param]">`，其余 img 形态被清除（对应 Kotlin 的熔断式交替正则）。
//
//  —— 全局规范：绝不崩溃；html 为 nil 返回 ""。
//

import Foundation

/// 对应 Kotlin: object HtmlFormatter
public enum HtmlFormatter {

    // MARK: - 正则（逐行对齐 Kotlin，均以 .toRegex() 语义 = NSRegularExpression，大小写敏感）

    /// Kotlin: "(&nbsp;)+".toRegex()
    public static let nbspRegex = "(&nbsp;)+"
    /// Kotlin: "(&ensp;|&emsp;)".toRegex()
    public static let espRegex = "(&ensp;|&emsp;)"
    /// Kotlin: "(&thinsp;|&zwnj;|&zwj;|\u2009|\u200C|\u200D)".toRegex()
    /// 注意 Kotlin 字面量里 \u2009 等是真正的字符（U+2009 细空格、U+200C ZWNJ、U+200D ZWJ）。
    public static let noPrintRegex = "(&thinsp;|&zwnj;|&zwj;|\u{2009}|\u{200C}|\u{200D})"
    /// Kotlin: "</?(?:div|p|br|hr|h\\d|article|dd|dl)[^>]*>".toRegex()
    public static let wrapHtmlRegex = "</?(?:div|p|br|hr|h\\d|article|dd|dl)[^>]*>"
    /// Kotlin: "<!--[^>]*-->".toRegex()
    public static let commentRegex = "<!--[^>]*-->"
    /// Kotlin: "</?(?!img)[a-zA-Z]+(?=[ >])[^<>]*>".toRegex()  —— formatKeepImg 用
    public static let notImgHtmlRegex = "</?(?!img)[a-zA-Z]+(?=[ >])[^<>]*>"
    /// Kotlin: "</?[a-zA-Z]+(?=[ >])[^<>]*>".toRegex()  —— format 默认
    public static let otherHtmlRegex = "</?[a-zA-Z]+(?=[ >])[^<>]*>"
    /// Kotlin: "\\s*\\n+\\s*".toRegex()
    ///
    /// ⚠️ `\s` 已显式展开为 Java 的 **ASCII 空白集** `[ \t\n\x0B\f\r]`，原因见
    /// `javaASCIISpace` 的文档：ICU（NSRegularExpression）的 `\s` **包含全角空格 U+3000**，
    /// 而 Java 的不包含，两者对 `　` 的处置不同，会导致缩进被重复叠加。
    public static let indent1Regex = "[\(javaASCIISpace)]*\\n+[\(javaASCIISpace)]*"
    /// Kotlin: "^[\\n\\s]+".toRegex()
    public static let indent2Regex = "^[\\n\(javaASCIISpace)]+"
    /// Kotlin: "[\\n\\s]+$".toRegex()
    public static let lastRegex = "[\\n\(javaASCIISpace)]+$"

    /// Java `\s` 的等价**字符类内容**（**不含**全角空格 U+3000、不含 U+00A0）。
    ///
    /// Java 的 `\s` 定义就是 `[ \t\n\x0B\f\r]` 这 6 个 ASCII 空白；而 ICU 正则
    /// （NSRegularExpression / Swift 的 `\s`）把 Unicode 空白也算进去，**首当其冲就是
    /// 全角空格 U+3000**。这个差异在本移植里会造成真实行为分歧：
    ///
    /// 以 `<div>内容</div>` 为例（两边的第 1–3 步完全一致，都得到 `"\n　　内容\n　　"`）：
    ///
    /// | 步骤 | Java（Kotlin 真实行为） | ICU（`\s` 未展开时） |
    /// |---|---|---|
    /// | 4. `^[\n\s]+` 匹配 | 只吃 `\n`（长度 1）→ `"　　　　内容\n　　"` | 吃 `\n　　`（长度 3）→ `"　　内容\n　　"` |
    /// | 5. `[\n\s]+$` | 匹配尾部 `\n　　` → 清掉 | 匹配不到（`\n` 后的 `　` 非 `\s`）→ 残留 |
    ///
    /// 即 ICU 会让第 3 步刚插入的缩进被第 4 步**再叠加一次**（应为 4 个全角空格 → 只剩 2 个）。
    /// 实测证据（Java 20）：`"　".matches("\\s") == false`，而 Swift/ICU 侧为 true。
    ///
    /// 参考：本缺陷由 CI `HtmlFormatter` golden 的 43 条用例一次性暴露。
    ///
    /// ⚠️ 这里必须嵌入**真实字符**而不是 `\u{0B}` 之类的转义：`\u{...}` 是 Swift 的字符串
    /// 插值语法，写进正则串会变成字面量 `u{0B}` 从而让 `NSRegularExpression` 直接报
    /// `NSCocoaErrorDomain 2048`（实测）。
    ///
    /// 注意：0x0B（垂直制表）是合法标量，但仓库硬规则禁止强解包，故这里用 `UnicodeScalar(_:)`
    /// 的 failable init + `??` 兜底（实际不会走到兜底分支，仅为了不出现 `!`）。
    private static let javaASCIISpace: String = {
        let verticalTab = UnicodeScalar(0x0B).map(String.init) ?? "\u{0B}"
        return " \t\n" + verticalTab + "\u{0C}\r"
    }()

    /// Kotlin 的 formatImagePattern（Pattern.CASE_INSENSITIVE）。
    /// 注意第 4 个分支前的 `|` 处于顶层的「熔断」语义：Kotlin 依赖交替匹配取第一个成功分支。
    /// Swift 的 NSRegularExpression 同样按交替顺序取第一个可匹配分支，语义一致。
    public static let formatImagePattern = "<img[^>]*\\ssrc\\s*=\\s*['\"]([^'\"{>]*\\{(?:[^{}]|\\{[^}>]+\\})+\\})['\"][^>]*>"
        + "|<img[^>]*\\sdata-(?:src|original|srcset)\\s*=\\s*['\"]([^'\">]+)['\"][^>]*>"
        + "|<img[^>]*\\ssrc\\s*=\\s*\"([^\">]+)\"[^>]*>"
        + "|<img[^>]*\\s(?:data-[^=>]*|src)=\\s*['\"]([^'\">]*)['\"][^>]*>"

    // MARK: - format

    /// 对应 Kotlin: fun format(html: String?, otherRegex: Regex = otherHtmlRegex): String
    public static func format(_ html: String?, otherRegex: String = otherHtmlRegex) -> String {
        guard let html = html else { return "" }
        var s = html
        s = replaceAll(s, nbspRegex, " ")
        s = replaceAll(s, espRegex, " ")
        s = replaceAll(s, noPrintRegex, "")
        s = replaceAll(s, wrapHtmlRegex, "\n")
        s = replaceAll(s, commentRegex, "")
        s = replaceAll(s, otherRegex, "")
        s = replaceAll(s, indent1Regex, "\n　　")
        s = replaceAll(s, indent2Regex, "　　")
        s = replaceAll(s, lastRegex, "")
        return s
    }

    /// 对应 Kotlin: fun formatKeepImg(html: String?, redirectUrl: URL? = null): String
    ///
    /// - Parameter redirectUrl: 用于把 img 的 src 解析成绝对地址的基准；nil 时 getAbsoluteURL 直接返回 trim 后的相对串。
    public static func formatKeepImg(_ html: String?, redirectUrl: String? = nil) -> String {
        guard let html = html else { return "" }
        let keepImgHtml = format(html, otherRegex: notImgHtmlRegex)

        // Kotlin 用 java.util.regex.Matcher 手工拼接：[appendPos, matcher.start()) + 新标签，最后补尾。
        var appendPos = 0
        var sb = ""
        let ns = keepImgHtml as NSString
        let matches = NSRegularExpressionCache(pattern: formatImagePattern, options: [.caseInsensitive]).matches(in: keepImgHtml)
        for m in matches {
            var param = ""
            // 依次尝试 group1..group4，取第一个「存在且非 nil」的分组（对齐 Kotlin 的 ?: 链）。
            let rawSrc = firstMatchedGroup(ns, m, [1, 2, 3, 4]).map { group -> String in
                if group.index == 1 {
                    // Kotlin: 对 group1 再做 paramPattern 检查，抽出参数到 param，src 取参数前部分。
                    if let urlMatcher = AnalyzeUrl.paramPattern.firstMatch(in: group.value) {
                        let gv = group.value as NSString
                        param = "," + gv.substring(from: urlMatcher.range.location + urlMatcher.range.length)
                        return gv.substring(to: urlMatcher.range.location)
                    }
                    return group.value
                }
                return group.value
            } ?? ""
            let abs = NetworkUtils.getAbsoluteURL(redirectUrl, rawSrc) + param
            sb += ns.substring(with: NSRange(location: appendPos, length: m.range.location - appendPos))
            sb += "<img src=\"\(abs)\">"
            appendPos = m.range.location + m.range.length
        }
        if appendPos < ns.length {
            sb += ns.substring(with: NSRange(location: appendPos, length: ns.length - appendPos))
        }
        return sb
    }

    // MARK: - 内部工具

    /// 取第一个「参与匹配且非 NSParticipantNotFound」的分组，同时记录其组号（用于区分 group1 的 param 处理）。
    private static func firstMatchedGroup(_ ns: NSString, _ m: NSTextCheckingResult, _ indexes: [Int]) -> (index: Int, value: String)? {
        for i in indexes {
            if i < m.numberOfRanges {
                let r = m.range(at: i)
                if r.location != NSNotFound {
                    return (i, ns.substring(with: r))
                }
            }
        }
        return nil
    }

    /// 语义等价 Kotlin `String.replace(regex, replacement)`：全局替换，replacement 原样（不做 $1 展开，
    /// 因为 Kotlin 的 String.replace(Regex, String) 的 replacement 是字面量，不解析分组引用）。
    static func replaceAll(_ s: String, _ pattern: String, _ replacement: String) -> String {
        let cache = NSRegularExpressionCache(pattern: pattern)
        let ns = s as NSString
        // literal = true：把 replacement 当字面量，避免 "$" 被当作分组引用（Kotlin 同样不展开）。
        return cache.stringByReplacingMatches(
            in: s,
            range: NSRange(location: 0, length: ns.length),
            withTemplate: NSRegularExpression.escapedTemplate(for: replacement)
        )
    }
}
