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
