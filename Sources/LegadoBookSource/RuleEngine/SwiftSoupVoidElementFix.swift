//
//  SwiftSoupVoidElementFix.swift
//  LegadoBookSource
//
//  修正 SwiftSoup 2.9.6 自身的一个真实 bug：`Element.outerHtmlHead` 对 HTML 语法下的
//  "空标签"（void element，如 <img>/<br>/<hr>）错误地也输出自闭合斜杠 `<img src="x" />`，
//  而真实 jsoup（已读源码确认，Element.java:1737-1744）在 HTML 语法下应输出 `<img src="x">`
//  （无斜杠），只有 XML 语法才输出 `<img src="x" />`。SwiftSoup 把两个分支都写成了后者，
//  是库本身的移植缺陷，不是本项目可以通过配置 OutputSettings 绕开的（已验证：
//  OutputSettings.syntax 本就默认是 .html，问题出在 SwiftSoup 的 if/else 分支本身写错，
//  与 syntax 设置无关）。
//
//  本文件对 outerHtml()/html() 的输出结果做一次受控的字符串级修正：只处理「真正是 void
//  标签、且紧跟自闭合斜杠」的情形，不触碰文本内容、属性值、非 void 标签，避免误伤。
//

import Foundation

/// 修正 SwiftSoup 2.9.6 自身另一个真实 bug：空白规整（`text()`/`ownText()` 用的
/// `StringUtil.isWhitespace`）只认标准空白字符（空格/Tab/换行/换页/回车），**遗漏了
/// jsoup 自己特意扩展的 `&nbsp;`（U+00A0，不在 HTML 规范里，但 jsoup 明确按"预期行为"
/// 处理为可折叠空白——已读 jsoup 源码 `StringUtil.isActuallyWhitespace` 确认，
/// 注释原文："160 is &nbsp;(non-breaking space). Not in the spec but expected."）。
/// 结果是 SwiftSoup 对含 `&nbsp;` 的文本，开头/结尾的不换行空格不会被裁剪、
/// 连续空白也不会把 nbsp 与普通空格一起折叠成一个空格，与真实 jsoup 不一致。
///
/// 本函数复刻 jsoup `StringUtil.appendNormalisedWhitespace(_, _, stripLeading:true)`
/// 的算法（把 nbsp 并入"可折叠空白"集合），对 SwiftSoup 产出的 text()/ownText() 结果
/// 做一次等价的再规整，使最终结果与真实 jsoup 完全一致。
enum SwiftSoupTextNormalizeFix {
    /// 与 jsoup `StringUtil.isActuallyWhitespace` 等价的字符判定：普通空白 + U+00A0(nbsp)。
    private static func isActuallyWhitespace(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x20, 0x09, 0x0A, 0x0C, 0x0D, 0xA0: return true  // ' ', \t, \n, \f, \r, nbsp
        default: return false
        }
    }

    /// 复刻 jsoup `appendNormalisedWhitespace(sb, string, stripLeading: true)`：
    /// 连续空白（含 nbsp）折叠为单个普通空格；若折叠发生在"尚未出现非空白字符"之前，
    /// 直接跳过（即裁剪前导空白，含前导 nbsp）。不做尾部单独裁剪——与 jsoup 一致，
    /// 尾部如果是空白会被折叠成一个尾随空格（这是 jsoup 的真实行为，不是裁掉）。
    static func normalize(_ s: String) -> String {
        guard !s.isEmpty else { return s }
        // 快路径：不含 nbsp 时，SwiftSoup 自身的普通空白折叠已经正确，无需重算。
        guard s.unicodeScalars.contains(where: { $0.value == 0xA0 }) else { return s }

        var out = String.UnicodeScalarView()
        var lastWasWhite = false
        var reachedNonWhite = false
        for scalar in s.unicodeScalars {
            if isActuallyWhitespace(scalar) {
                if !reachedNonWhite || lastWasWhite { continue }
                out.append(" ")
                lastWasWhite = true
            } else {
                out.append(scalar)
                lastWasWhite = false
                reachedNonWhite = true
            }
        }
        return String(out)
    }
}

/// 修正 SwiftSoup 2.9.6 另一个真实 bug：pretty-print 输出里，紧跟在 `<br>` 后面的文本节点
/// 应该换行缩进（已读 jsoup 源码 `TextNode.outerHtmlHead` 确认：`(siblingIndex > 0 &&
/// isNode(prev, "br"))` 是一条专门的特殊规则，注释原文 "special case wrap on inline <br> -
/// doesn't make sense as a block tag"），但 SwiftSoup 的 `TextNode.outerHtmlHead` 移植
/// 遗漏了这整条分支（以及 jsoup 同一方法里的 trimLeading/trimTrailing/couldSkip 逻辑），
/// 导致 `<br>` 后的文本紧跟在同一行，不会像真实 jsoup 那样换行并带上与上下文一致的缩进。
///
/// 本函数对 SwiftSoup 产出的 pretty-print HTML 字符串做一次结构保守的后处理：
/// 找到每个 `<br>`（后面紧跟的不是 `<` 开头的标签、也不是换行，即其后直接跟着文本）的位置，
/// 在其后插入 "\n" + 与当前行相同的缩进（取当前行开头的空白前缀，与 jsoup
/// "同一深度" 的缩进结果一致）。只处理这一种结构，不触碰其它格式。
enum SwiftSoupBrIndentFix {
    static func fix(_ html: String) -> String {
        guard html.contains("<br>") else { return html }

        let lines = html.components(separatedBy: "\n")
        var outLines: [String] = []
        for line in lines {
            outLines.append(contentsOf: fixLine(line))
        }
        return outLines.joined(separator: "\n")
    }

    /// 处理单行：该行里每出现一次 "<br>" 后面紧跟非 '<' 字符（即后面是文本，不是下一个标签
    /// 或行尾），就在该处断行，新行带上与本行相同的前导空白缩进。
    private static func fixLine(_ line: String) -> [String] {
        guard line.contains("<br>") else { return [line] }

        // jsoup 对 "<br>" 后文本节点用的缩进深度，是该文本节点自身的树深度——即它所在
        // 父元素（如 <p>）的"内容深度"，比父元素标签本身的缩进深度多一层（默认
        // indentAmount=1，即多一个空格）。本行（含 "<br>" 的这一行）开头的空白就是父元素
        // 标签自己的缩进，所以这里要在其基础上再加一层（一个空格）。
        let lineIndent = String(line.prefix(while: { $0 == " " || $0 == "\t" }))
        let indent = lineIndent + " "

        var lines: [String] = []
        var current = ""
        var remainder = Substring(line)

        while let range = remainder.range(of: "<br>") {
            let afterBr = range.upperBound
            // 把 "...<br>" 这一段追加到当前行。
            current += String(remainder[remainder.startIndex..<afterBr])
            remainder = remainder[afterBr...]

            // 如果 "<br>" 后面紧跟的是另一个标签（'<'）或已经是行尾，不需要插入换行。
            if remainder.isEmpty || remainder.first == "<" {
                continue
            }
            // "<br>" 后面是文本：在此处断行，开始新的一行（带缩进）。
            lines.append(current)
            current = indent
        }
        current += String(remainder)
        lines.append(current)
        return lines
    }
}

enum SwiftSoupVoidElementFix {

    /// jsoup Tag.swift 里 emptyTags 的权威清单（原样抄自 SwiftSoup 2.9.6 源码，
    /// 见 reference 里的说明；必须与 SwiftSoup 当前版本保持一致）。
    static let voidTagNames: Set<String> = [
        "meta", "link", "base", "frame", "img", "br", "wbr", "embed", "hr", "input",
        "keygen", "col", "command", "device", "area", "basefont", "bgsound",
        "menuitem", "param", "source", "track"
    ]

    /// 把 `<tagname ... />` 形式（tagname 是 void 标签，自闭合斜杠前可有任意属性文本）
    /// 修正为 `<tagname ...>`（对齐真实 jsoup 的 HTML 语法输出）。
    ///
    /// 用正则精确匹配「标签开头 + 直到行内第一个 `/>`」的结构，只在确认标签名属于
    /// void 标签清单时才替换，避免误伤属性值或文本内容里恰好出现的 `/>` 字符序列
    /// （HTML 属性值理论上可能含有 `/>` 这种罕见但合法的内容，这里用“标签名必须紧跟
    /// `<` 之后”这一结构性约束来降低误判概率；真实书源 HTML 里出现这种边界情况的
    /// 概率极低，若未来发现反例可在此处继续加固)。
    static func fix(_ html: String) -> String {
        guard html.contains("/>") else { return html }

        var result = ""
        result.reserveCapacity(html.count)
        var idx = html.startIndex

        while idx < html.endIndex {
            if html[idx] == "<" {
                // 尝试匹配 "<tagname" （标签名：字母开头，后续字母数字）。
                var j = html.index(after: idx)
                var tagName = ""
                while j < html.endIndex, html[j].isLetter || (!tagName.isEmpty && html[j].isNumber) {
                    tagName.append(html[j])
                    j = html.index(after: j)
                }
                if !tagName.isEmpty, voidTagNames.contains(tagName.lowercased()) {
                    // 从 j 开始找到这个标签对应的 "/>" 或 ">"（取先出现的那个，且不能跨越
                    // 字符串/属性引号里的内容——用简单的引号状态机规避属性值里出现 '>' 的情况）。
                    var k = j
                    var inSingle = false, inDouble = false
                    var closeTagEnd: String.Index? = nil
                    var slashPos: String.Index? = nil
                    while k < html.endIndex {
                        let c = html[k]
                        if c == "'" && !inDouble { inSingle.toggle() }
                        else if c == "\"" && !inSingle { inDouble.toggle() }
                        else if !inSingle && !inDouble {
                            if c == "/" {
                                let next = html.index(after: k)
                                if next < html.endIndex && html[next] == ">" {
                                    slashPos = k
                                    closeTagEnd = html.index(after: next)
                                    break
                                }
                            } else if c == ">" {
                                closeTagEnd = html.index(after: k)
                                break
                            }
                        }
                        k = html.index(after: k)
                    }
                    if let end = closeTagEnd {
                        if let slash = slashPos {
                            // 把 ".../>" 换成 "...>"（去掉斜杠，去掉斜杠前可能的一个空格，
                            // 对齐 jsoup 的 "<img src=\"x\">" 无额外空格的输出格式）。
                            var attrPart = String(html[j..<slash])
                            if attrPart.hasSuffix(" ") { attrPart.removeLast() }
                            result += "<" + tagName + attrPart + ">"
                        } else {
                            result += String(html[idx..<end])
                        }
                        idx = end
                        continue
                    }
                }
                // 不是 void 标签开头，或没找到标签结束：原样输出这个 '<' 并继续逐字符扫描。
                result.append(html[idx])
                idx = html.index(after: idx)
            } else {
                result.append(html[idx])
                idx = html.index(after: idx)
            }
        }
        return result
    }
}


/// 组合入口：依次应用 void 元素自闭合修正 + br 后文本缩进修正。
/// 所有对外输出 outerHtml()/html() 的地方都应使用这个函数，而不是分别调用。
enum SwiftSoupHtmlFix {
    static func fix(_ html: String) -> String {
        SwiftSoupBrIndentFix.fix(SwiftSoupVoidElementFix.fix(html))
    }
}
