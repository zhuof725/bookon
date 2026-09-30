//
//  SwiftSoupXPathPredicate.swift
//  LegadoBookSource
//
//  XPath 子集的谓词模型与解析。配合 SwiftSoupXPathEvaluator / Parser。
//

import Foundation
import SwiftSoup

extension SwiftSoupXPathEvaluator {

    /// 位置谓词。
    struct PositionSpec {
        enum Op { case eq, gt, lt, ge, le }
        // last 表示是否基于 last()（如 [last()], [last()-1]）
        let usesLast: Bool
        let offset: Int          // last()-offset；或直接的数字（op=eq 时）
        let op: Op               // 仅当来自 position() 比较时使用
        let literalIndex: Int?   // [n] 直接数字

        func matches(position: Int, last: Int) -> Bool {
            if let n = literalIndex {
                return position == n
            }
            let target = usesLast ? (last - offset) : offset
            switch op {
            case .eq: return position == target
            case .gt: return position > target
            case .lt: return position < target
            case .ge: return position >= target
            case .le: return position <= target
            }
        }
    }

    /// 谓词。
    struct Predicate {
        enum Kind {
            case position(PositionSpec)                 // [n] / [last()] / [position()>n]
            case attrExists(String)                     // [@id]
            case attrCompare(name: String, op: CompareOp, value: String)  // [@id='x']
            case textCompare(op: CompareOp, value: String)                // [text()='x']
            case function(FuncPred)                     // contains(...)/starts-with(...)/normalize-space(...)
            case and([Predicate])
            case or([Predicate])
        }
        enum CompareOp { case eq, ne }
        struct FuncPred {
            enum Name { case contains, startsWith, normalizeSpaceEq }
            let name: Name
            // 作用目标：@attr / text() / .（当前元素文本）
            enum Target { case attr(String); case text; case current }
            let target: Target
            let value: String     // 比较/包含的值（normalizeSpaceEq 用作等值）
        }
        var kind: Kind

        /// 过滤元素集合。
        func filter(_ elements: [Element]) throws -> [Element] {
            switch kind {
            case .position(let spec):
                let count = elements.count
                var out: [Element] = []
                for (i, e) in elements.enumerated() {
                    if spec.matches(position: i + 1, last: count) { out.append(e) }
                }
                return out
            case .attrExists(let name):
                return elements.filter { (try? $0.hasAttr(name)) ?? false }
            case .attrCompare(let name, let op, let value):
                return elements.filter { e in
                    let v = (try? e.attr(name)) ?? ""
                    return op == .eq ? (v == value) : (v != value)
                }
            case .textCompare(let op, let value):
                return elements.filter { e in
                    let t = (try? e.text()) ?? ""
                    return op == .eq ? (t == value) : (t != value)
                }
            case .function(let f):
                return elements.filter { e in Predicate.evalFunc(f, on: e) }
            case .and(let preds):
                var cur = elements
                for p in preds { cur = (try? p.filter(cur)) ?? [] }
                return cur
            case .or(let preds):
                var seen = Set<ObjectIdentifier>()
                var out: [Element] = []
                for p in preds {
                    let sub = (try? p.filter(elements)) ?? []
                    for e in sub where seen.insert(ObjectIdentifier(e)).inserted { out.append(e) }
                }
                // 保持文档顺序：按原 elements 顺序输出
                return elements.filter { seen.contains(ObjectIdentifier($0)) }
            }
        }

        static func evalFunc(_ f: FuncPred, on e: Element) -> Bool {
            let subject: String
            switch f.target {
            case .attr(let a): subject = (try? e.attr(a)) ?? ""
            case .text, .current: subject = (try? e.text()) ?? ""
            }
            switch f.name {
            case .contains: return subject.contains(f.value)
            case .startsWith: return subject.hasPrefix(f.value)
            case .normalizeSpaceEq:
                let normalized = subject.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" })
                    .joined(separator: " ")
                return normalized == f.value
            }
        }
    }
}
