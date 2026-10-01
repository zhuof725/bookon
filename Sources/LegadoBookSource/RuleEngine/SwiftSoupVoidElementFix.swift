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
