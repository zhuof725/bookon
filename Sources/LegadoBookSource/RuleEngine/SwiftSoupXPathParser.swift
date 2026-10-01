//
//  SwiftSoupXPathParser.swift
//  LegadoBookSource
//
//  XPath 子集的解析（切 step）与求值（轴/节点测试/谓词）。配合 SwiftSoupXPathEvaluator。
//

import Foundation
import SwiftSoup

extension SwiftSoupXPathEvaluator {

    // 一个定位步（step）。
    struct Step {
        enum Axis {
            case child, descendantOrSelf, selfAxis, parent
            case followingSibling, precedingSibling, descendant, ancestor
            case following, preceding, attribute
        }
        enum NodeTest {
            case name(String)     // 标签名
            case wildcard         // *
            case text             // text()
            case node             // node()
            /// 恒不匹配：形如 "xxx()" 但不是已知函数（如 ownText()），见 golden 对照记录。
            case none
        }
        var axis: Axis
        var nodeTest: NodeTest
        var predicates: [Predicate]
        /// 末尾扩展：@attr 或 函数（text/allText/html/outerHtml）。
        /// ⚠️ 不含 ownText()：经 golden（真实 JsoupXpath 2.5.3）验证它不是真实存在的
        /// NodeTest（JsoupXpath 官方文档 NodeTest 列表只有 allText()/html()/outerHtml()/
        /// num()/text()/node()，没有 ownText()），已移除，见 README 已知差异表。
        var terminal: Terminal?

        enum Terminal {
            case attribute(String)     // @attr（返回属性节点）
            case funcText              // text()（返回文本节点，元素直接子文本）
            case funcAllText           // allText()
            case funcHtml              // html() = innerHtml
            case funcOuterHtml         // outerHtml()
        }
    }

    // MARK: - 求值一个 step
    func applyStep(_ step: Step, to node: Node, into out: inout [Node]) throws {
        // 轴：先算出候选元素集合。
        var candidates: [Element] = []
        switch step.axis {
        case .selfAxis:
            if case .element(let e) = node { candidates = [e] }
        case .child:
            if case .element(let e) = node { candidates = e.children().array() }
        case .descendantOrSelf:
            if case .element(let e) = node {
                candidates = [e] + allDescendants(e)
            }
        case .descendant:
            if case .element(let e) = node { candidates = allDescendants(e) }
        case .parent:
            if case .element(let e) = node, let p = e.parent() { candidates = [p] }
        case .ancestor:
            if case .element(let e) = node { candidates = ancestors(e) }
        case .followingSibling:
            if case .element(let e) = node { candidates = followingSiblings(e) }
        case .precedingSibling:
            if case .element(let e) = node { candidates = precedingSiblings(e) }
        case .following:
            if case .element(let e) = node { candidates = following(e) }
        case .preceding:
            if case .element(let e) = node { candidates = preceding(e) }
        case .attribute:
            // @attr 作为 step（少见）；交由 nodeTest.name 决定属性名
            if case .element(let e) = node, case .name(let attr) = step.nodeTest {
                let v = (try? e.attr(attr)) ?? ""
                out.append(.attribute(name: attr, value: v, owner: e))
            }
            return
        }

        // 节点测试过滤（对元素）。text()/node() 特殊处理。
        switch step.nodeTest {
        case .name(let tag):
            candidates = candidates.filter { $0.tagName().lowercased() == tag.lowercased() }
        case .wildcard:
            break  // 保留所有元素
        case .text:
            // text() 作为 step：返回各候选元素的直接子文本节点（合并）。这里在 terminal 中更常见；
            // 若作为独立 step，则产出文本节点。
            var texts: [Node] = []
            for e in candidates {
                for tn in e.textNodes() {
                    let t = SwiftSoupTextNormalizeFix.normalize(tn.text())
                    if !t.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { texts.append(.text(t)) }
                }
            }
            // 谓词对文本节点仅支持位置；简单处理
            out.append(contentsOf: applyPositionPredicatesToText(texts, step.predicates))
            return
        case .node:
            break
        case .none:
            return  // 恒不匹配：直接不产出任何结果。
        }

        // 谓词过滤（对元素集合）。
        let filtered = try applyPredicates(candidates, step.predicates)

        // 末尾扩展。
        if let terminal = step.terminal {
            for e in filtered {
                switch terminal {
                case .attribute(let attr):
                    let v = (try? e.attr(attr)) ?? ""
                    out.append(.attribute(name: attr, value: v, owner: e))
                case .funcText:
                    for tn in e.textNodes() {
                        let t = SwiftSoupTextNormalizeFix.normalize(tn.text())
                        if !t.isEmpty { out.append(.text(t)) }
                    }
                case .funcAllText:
                    out.append(.text(SwiftSoupTextNormalizeFix.normalize((try? e.text()) ?? "")))
                case .funcHtml:
                    out.append(.text(JsoupCompatSerializer.innerHtml(e)))
                case .funcOuterHtml:
                    out.append(.text(JsoupCompatSerializer.outerHtml(e)))
                }
            }
        } else {
            for e in filtered { out.append(.element(e)) }
        }
    }

    // MARK: - 谓词

    func applyPredicates(_ elements: [Element], _ predicates: [Predicate]) throws -> [Element] {
        var cur = elements
        for pred in predicates {
            cur = try pred.filter(cur)
        }
        return cur
    }

    func applyPositionPredicatesToText(_ texts: [Node], _ predicates: [Predicate]) -> [Node] {
        var cur = texts
        for pred in predicates {
            if case .position(let p) = pred.kind {
                let count = cur.count
                cur = cur.enumerated().compactMap { (i, n) in
                    p.matches(position: i + 1, last: count) ? n : nil
                }
            }
        }
        return cur
    }

    // MARK: - 轴辅助
    func allDescendants(_ e: Element) -> [Element] {
        var out: [Element] = []
        for c in e.children().array() {
            out.append(c)
            out.append(contentsOf: allDescendants(c))
        }
        return out
    }
    func ancestors(_ e: Element) -> [Element] {
        var out: [Element] = []
        var p = e.parent()
        while let cur = p { out.append(cur); p = cur.parent() }
        return out
    }
    func followingSiblings(_ e: Element) -> [Element] {
        guard let p = e.parent() else { return [] }
        let sibs = p.children().array()
        guard let idx = sibs.firstIndex(where: { $0 === e }) else { return [] }
        return Array(sibs[(idx+1)...])
    }
    func precedingSiblings(_ e: Element) -> [Element] {
        guard let p = e.parent() else { return [] }
        let sibs = p.children().array()
        guard let idx = sibs.firstIndex(where: { $0 === e }) else { return [] }
        return Array(sibs[0..<idx])
    }
    func following(_ e: Element) -> [Element] {
        // 文档顺序中该元素之后、非后代的所有元素。用根做全序遍历。
        guard let root = topRoot(e) else { return [] }
        let all = [root] + allDescendants(root)
        guard let idx = all.firstIndex(where: { $0 === e }) else { return [] }
        let desc = Set(allDescendants(e).map { ObjectIdentifier($0) })
        return all[(idx+1)...].filter { !desc.contains(ObjectIdentifier($0)) }
    }
    func preceding(_ e: Element) -> [Element] {
        guard let root = topRoot(e) else { return [] }
        let all = [root] + allDescendants(root)
        guard let idx = all.firstIndex(where: { $0 === e }) else { return [] }
        let anc = Set(ancestors(e).map { ObjectIdentifier($0) })
        return all[0..<idx].filter { !anc.contains(ObjectIdentifier($0)) }
    }
    func topRoot(_ e: Element) -> Element? {
        var cur: Element = e
        while let p = cur.parent() { cur = p }
        return cur
    }
}
