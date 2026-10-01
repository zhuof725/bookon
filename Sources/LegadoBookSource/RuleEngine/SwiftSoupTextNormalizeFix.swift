//
//  SwiftSoupTextNormalizeFix.swift
//  LegadoBookSource
//
//  Step4-A 收尾：原 `SwiftSoupVoidElementFix.swift` 里的 void 元素自闭合修正
//  （`SwiftSoupVoidElementFix`）和 `<br>` 后文本缩进修正（`SwiftSoupBrIndentFix`）已被
//  彻底删除——它们是对 `outerHtml()`/`html()` 字符串结果的“后处理补丁”，职责已完全被
//  `JsoupCompatSerializer`（从零按 jsoup 真实算法重新生成 HTML 字符串，不再调用
//  SwiftSoup 自带的 outerHtml()/html()）取代。`SwiftSoupHtmlFix` 组合入口也一并删除，
//  所有调用点已切换到 `JsoupCompatSerializer.outerHtml()` / `.innerHtml()` /
//  `.elementsOuterHtml()` / `.elementsInnerHtml()`。
//
//  本文件只保留 `SwiftSoupTextNormalizeFix`：它修正的是 SwiftSoup 2.9.6
//  `text()`/`ownText()`（“纯文本提取”API，不产出 HTML 标签结构）里的一个独立 bug——
//  空白规整（`StringUtil.isWhitespace`）遗漏了 jsoup 特意扩展的 `&nbsp;`（U+00A0）。
//
//  职责边界（与 JsoupCompatSerializer 不重叠）：
//  - `JsoupCompatSerializer`：负责“HTML 结构序列化”路径——`@html`/`@all`/`outerHtml()`/
//    `html()`（CSS 规则的 html/all、XPath 的 html()/outerHtml()/asString()）。这些路径
//    会重新遍历 DOM 树自行处理空白折叠（含 nbsp，复刻 jsoup `Entities.escape` 的
//    `isWhitespace`+转义逻辑），**不**依赖本文件。
//  - `SwiftSoupTextNormalizeFix`：负责“纯文本提取”路径——`text()`/`ownText()`/`allText()`/
//    XPath 的 `text()`/`funcText`/`funcAllText`。这些路径调用的是 SwiftSoup 原生
//    `Element.text()`/`TextNode.text()`/`Element.ownText()`，其内部空白折叠逻辑没有被
//    `JsoupCompatSerializer` 取代（它们走的是 SwiftSoup 自己的 `StringUtil.isWhitespace`，
//    不经过本项目的 DOM 遍历），因此仍需要本文件对结果做一次 nbsp 等价再规整。
//
//  已读 jsoup 源码 `StringUtil.isActuallyWhitespace` 确认，注释原文：
//  "160 is &nbsp;(non-breaking space). Not in the spec but expected."
//

import Foundation

/// 复刻 jsoup `StringUtil.appendNormalisedWhitespace(_, _, stripLeading:true)` 的算法
/// （把 nbsp 并入“可折叠空白”集合），对 SwiftSoup 产出的 text()/ownText() 结果做一次
/// 等价的再规整，使最终结果与真实 jsoup 完全一致。
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
