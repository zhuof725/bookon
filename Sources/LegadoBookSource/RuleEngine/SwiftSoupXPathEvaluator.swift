//
//  SwiftSoupXPathEvaluator.swift
//  LegadoBookSource
//
//  在 SwiftSoup DOM 上自实现的 XPath 子集求值器（对齐 JsoupXpath 常见用法）。
//  ⚠️ 这是「子集」，不是完整 XPath。已支持/不支持语法见 README 对照表。
//
//  设计：
//   - 把表达式按 `/` 切成 step（`//` 表示 descendant-or-self），逐 step 在当前节点集上求值；
//   - step = 轴 + 节点测试(标签名/`*`/`text()`/`node()`) + 谓词序列 `[...]`；
//   - 末尾可为 `@attr`（取属性）或 JsoupXpath 扩展函数 `text()/allText()/html()/outerHtml()/ownText()`；
//   - 谓词支持：位置 `[n]`、`[last()]`、`[position()>n]`、`@attr`(存在)、`@attr='v'`、
//     `contains(...)`、`starts-with(...)`、`normalize-space(...)`、`text()='v'`、`and`/`or`。
//   - 轴支持：child(默认)、descendant-or-self(`//`)、self(`.`)、parent(`..`)、
//     `following-sibling::`、`preceding-sibling::`、`parent::`、`attribute::`(`@`)、
//     `descendant::`、`ancestor::`、`following::`、`preceding::`。
//

import Foundation
import SwiftSoup

public struct SwiftSoupXPathEvaluator: XPathEvaluator {

    private let roots: [Element]

    public init(roots: [Element]) {
        self.roots = roots
    }

    public func evaluate(_ xpath: String) throws -> [XPathNode] {
        let expr = xpath.trimmingCharacters(in: .whitespacesAndNewlines)
        if expr.isEmpty { return [] }
        let steps = try XPathParser.parse(expr)
        // 起始上下文：根元素集合。绝对路径(以 / 或 // 开头)从文档根开始；相对路径也从当前根开始。
        var current: [Node] = roots.map { .element($0) }
        for step in steps {
            var next: [Node] = []
            for node in current {
                try applyStep(step, to: node, into: &next)
            }
            current = dedup(next)
        }
        return current.map { $0.toXPathNode() }
    }

    // 去重（元素按对象标识；属性/文本按值+归属，简单按描述）。
    private func dedup(_ nodes: [Node]) -> [Node] {
        var out: [Node] = []
        var seenEls = Set<ObjectIdentifier>()
        var seenOther = Set<String>()
        for n in nodes {
            switch n {
            case .element(let e):
                if seenEls.insert(ObjectIdentifier(e)).inserted { out.append(n) }
            case .attribute(let name, let value, let owner):
                // 用 owner 的身份区分不同元素的同名同值属性，避免误去重。
                let ownerKey = owner.map { String(ObjectIdentifier($0).hashValue) } ?? "nil"
                let key = "a:\(ownerKey):\(name)=\(value)"
                if seenOther.insert(key).inserted { out.append(n) }
            case .text(let t):
                // 文本节点不强制去重（不同元素可能有相同文本），但同一遍内保序即可。
                out.append(.text(t))
            }
        }
        return out
    }

    // 内部节点模型（元素 / 属性 / 文本）。
    enum Node {
        case element(Element)
        case attribute(name: String, value: String, owner: Element?)
        case text(String)

        func toXPathNode() -> XPathNode {
            switch self {
            case .element(let e): return XPathNode(element: e)
            case .attribute(let n, let v, _): return XPathNode(attribute: n, value: v)
            case .text(let t): return XPathNode(text: t)
            }
        }
    }
}
