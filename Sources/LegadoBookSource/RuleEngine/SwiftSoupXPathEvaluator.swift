//
//  SwiftSoupXPathEvaluator.swift
//  LegadoBookSource
//
//  在 SwiftSoup DOM 上自实现的 XPath 子集求值器（对齐 JsoupXpath 常见用法）。
//  ⚠️ 这是「子集」，不是完整 XPath。已支持/不支持语法见 README 对照表。
//
//  设计：
//   - 顶层先按 `|`（联合运算符，depth=0 时，不在 `[]`/`()`/引号内）切分，每一段独立求值后
//     按文档顺序合并去重（对齐 XPath `|` 语义：结果是节点集合的并集，按文档顺序、去重）。
//   - 每一段先判断是否为顶层函数调用（`string(...)`/`count(...)`/`concat(...)`/
//     `substring(...)`/`substring-before(...)`/`substring-after(...)`/`string-length(...)`），
//     是则对函数参数中的路径求值后应用字符串函数，返回单个文本结果；否则按普通路径解析。
//   - 路径按 `/` 切成 step（`//` 表示 descendant-or-self），逐 step 在当前节点集上求值；
//     step = 轴 + 节点测试(标签名/`*`/`text()`/`node()`) + 谓词序列 `[...][...]...`（可多个，
//     依次连续过滤，与 XPath 标准语义一致：谓词从左到右依次收窄，位置谓词作用于"当前谓词
//     执行前的候选集合"）；
//   - 末尾可为 `@attr`（取属性）或 JsoupXpath 扩展函数 `text()/allText()/html()/outerHtml()/ownText()`；
//   - 谓词支持：位置 `[n]`、`[last()]`、`[position()>n]`、`@attr`(存在)、`@attr='v'`、
//     `contains(...)`、`starts-with(...)`、`normalize-space(...)`、`text()='v'`、`not(...)`、
//     `and`/`or`（顶层单层拆分，不支持括号分组）。
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

        // 顶层按 `|` 切分（联合运算符）。
        let branches = SwiftSoupXPathEvaluator.topLevelUnionParts(expr)
        if branches.count == 1 {
            return try evaluateSingle(branches[0]).map { $0.toXPathNode() }
        }

        // 多个分支：分别求值，合并后按「文档顺序」排序（对齐 XPath `|` 标准语义：
        // 联合运算的结果按文档顺序排列，与哪个分支命中无关），元素/属性去重，文本保留全部。
        var merged: [Node] = []
        for branch in branches {
            let nodes = try evaluateSingle(branch)
            merged.append(contentsOf: nodes)
        }
        let deduped = dedup(merged)
        return sortByDocumentOrder(deduped).map { $0.toXPathNode() }
    }

    /// 按文档顺序排序（用于 `|` 联合运算符）。
    /// - 元素：按其在文档树里的前序遍历位置排序。
    /// - 属性：按其归属元素的文档位置排序（同一元素的多个属性保持合并时的相对顺序）。
    /// - 纯文本节点（如 `text()` 的结果）：没有独立的文档位置可归属，保持合并时的原始相对顺序
    ///   （已知限制，见 README「与 Kotlin 已知差异」）。
    private func sortByDocumentOrder(_ nodes: [Node]) -> [Node] {
        guard let anyRoot = roots.first, let top = topRoot(anyRoot) else { return nodes }
        var order: [ObjectIdentifier: Int] = [:]
        var idx = 0
        func visit(_ e: Element) {
            order[ObjectIdentifier(e)] = idx
            idx += 1
            for c in e.children().array() { visit(c) }
        }
        visit(top)

        // 用稳定排序：先按 (是否可定位, 文档位置) 排序，不能定位的（纯文本）保持原始相对顺序。
        let indexed = nodes.enumerated().map { (offset, node) -> (Int, Int, Node) in
            switch node {
            case .element(let e):
                return (0, order[ObjectIdentifier(e)] ?? Int.max, node)
            case .attribute(_, _, let owner):
                let ownerIdx = owner.flatMap { order[ObjectIdentifier($0)] } ?? Int.max
                return (0, ownerIdx, node)
            case .text:
                // 文本节点排最后一组，组内保持原始合并顺序（用 offset 保序）。
                return (1, offset, node)
            }
        }
        return indexed.sorted { a, b in
            if a.0 != b.0 { return a.0 < b.0 }
            return a.1 < b.1
        }.map { $0.2 }
    }

    /// 求值「不含顶层 `|`」的单个表达式：可能是函数调用，也可能是普通路径。
    private func evaluateSingle(_ expr: String) throws -> [Node] {
        if let funcResult = try SwiftSoupXPathEvaluator.tryEvalTopLevelFunction(expr, roots: roots, evaluator: self) {
            return [funcResult]
        }
        let steps = try XPathParser.parse(expr)
        var current: [Node] = roots.map { .element($0) }
        for step in steps {
            var next: [Node] = []
            for node in current {
                try applyStep(step, to: node, into: &next)
            }
            current = dedup(next)
        }
        return current
    }

    /// 对一段路径表达式求值，返回内部 Node 列表（供函数参数内部递归求值使用）。
    func evaluatePath(_ expr: String) throws -> [Node] {
        let steps = try XPathParser.parse(expr)
        var current: [Node] = roots.map { .element($0) }
        for step in steps {
            var next: [Node] = []
            for node in current {
                try applyStep(step, to: node, into: &next)
            }
            current = dedup(next)
        }
        return current
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

        /// 取字符串值（对齐 XPath string() 转换：元素取其文本，属性取值，文本节点取自身）。
        func stringValue() -> String {
            switch self {
            case .element(let e): return (try? e.text()) ?? ""
            case .attribute(_, let v, _): return v
            case .text(let t): return t
            }
        }
    }
}
