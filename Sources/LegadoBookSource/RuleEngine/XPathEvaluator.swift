//
//  XPathEvaluator.swift
//  LegadoBookSource
//
//  XPath 求值抽象。AnalyzeByXPath 只依赖本协议，便于以后替换底层引擎。
//
//  Kotlin 用 JsoupXpath（在 Jsoup DOM 上执行 XPath）。Swift 无等价库；
//  选型见 README：本移植在 SwiftSoup DOM 上自实现 XPath 子集（SwiftSoupXPathEvaluator）。
//  理由：libxml2/Kanna 的 HTML 容错与 Jsoup 不同，会导致选择结果与 Kotlin 不一致；
//  自实现子集能与 SwiftSoup 的 DOM 保持一致，并可控地对齐 JsoupXpath 的 asString/toString 语义。
//

import Foundation
import SwiftSoup

/// XPath 结果节点。对应 JsoupXpath 的 JXNode（可为元素 / 属性 / 文本）。
public final class XPathNode {
    public enum Kind {
        case element(Element)
        case attribute(name: String, value: String)
        case text(String)
    }
    public let kind: Kind

    public init(element: Element) { self.kind = .element(element) }
    public init(attribute name: String, value: String) { self.kind = .attribute(name: name, value: value) }
    public init(text: String) { self.kind = .text(text) }

    /// 是否为元素节点（对应 JXNode.isElement）。
    public var isElement: Bool { if case .element = kind { return true }; return false }

    /// 取底层 Element（非元素返回 nil）。
    public func asElement() -> Element? {
        if case .element(let e) = kind { return e }
        return nil
    }

    /// 对应真实 JsoupXpath 源码 JXNode.asString()（已去 JsoupXpath 源码核对，见 README）：
    ///   若 value 是元素：若其标签是内部专用的 "JX_TEXT"（即 text()/allText() 等函数结果，
    ///   本移植用 `.text` case 表达这一形态）返回 ownText()；否则（普通元素，如 `//div` 直接
    ///   命中的节点）返回 `element.toString()` == outerHtml（含元素自身标签）。
    ///  - 元素 -> outerHtml（不是纯文本！这是容易搞错的一点，已用 golden 对照修正）
    ///  - 属性 -> 属性值
    ///  - 文本（对应 JX_TEXT 伪元素）-> 文本内容
    public func asString() -> String {
        switch kind {
        case .element(let e): return SwiftSoupHtmlFix.fix((try? e.outerHtml()) ?? "")
        case .attribute(_, let v): return v
        case .text(let t): return t
        }
    }

    /// 对应 JXNode.toString()（JsoupXpath 源码：`toString() { return asString() }`，
    /// 与 asString() 完全相同，getString 用 TextUtils.join 拼接的即为此）。
    public func toStringValue() -> String {
        asString()
    }

    /// 供上层把 XPath 结果再喂给别的解析器时使用（AnalyzeByJSoup.parse 会调用）。
    func stringForParse() -> String { toStringValue() }
}

/// XPath 求值器抽象。
public protocol XPathEvaluator {
    /// 用一组根元素创建求值上下文。
    init(roots: [Element])
    /// 执行一个 XPath 表达式，返回结果节点列表。
    /// - Throws: RuleEngineError.invalidXPath（语法无效 / 不支持）。
    func evaluate(_ xpath: String) throws -> [XPathNode]
}
