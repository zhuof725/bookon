//
//  DefaultJSONPathEvaluator.swift
//  LegadoBookSource
//
//  自实现的 JSONPath 求值器，覆盖书源常用语法子集，语义贴近 Jayway JsonPath。
//
//  ⚠️ 这是「子集」实现，不是完整 JSONPath。已支持 / 不支持 的语法见 README 对照表。
//  设计目标：正确处理真实书源里出现的语法（$、.、..、[*]、[n]、[a:b]、['a','b']、
//  简单过滤器 [?(@.x == 'y')]、.length()），不臆造未验证的高级特性。
//
//  「definite / indefinite」概念对齐 Jayway：
//   - 含 `..`（递归下降）/ `[*]` / 过滤器 / 多下标 / 切片 的路径是 indefinite，返回列表；
//   - 其余是 definite，返回单值；命中失败抛 pathNotFound。
//

import Foundation

public struct DefaultJSONPathEvaluator: JSONPathEvaluator {

    private let root: JSONValue

    public init(root: JSONValue) {
        self.root = root
    }

    public func read(_ path: String) throws -> JSONPathResult {
        let tokens = try PathParser.parse(path)
        let indefinite = tokens.contains { $0.isIndefinite }

        // 逐段求值，维护一个「当前节点集合」。
        var current: [JSONValue] = [root]
        for token in tokens {
            var next: [JSONValue] = []
            for node in current {
                token.apply(to: node, into: &next)
            }
            current = next
        }

        if indefinite {
            return .list(current)
        } else {
            // definite：无命中则 pathNotFound（对齐 Jayway）。
            guard let first = current.first else {
                throw JSONPathError.pathNotFound(path)
            }
            return .single(first)
        }
    }

    // MARK: - 路径段

    enum Token {
        case root                        // $
        case child(String)               // .name 或 ['name']
        case children([String])          // ['a','b']（多字段，indefinite）
        case index(Int)                  // [n]（支持负数，从末尾）
        case wildcard                    // [*] 或 .*
        case recursive(String?)          // ..name（name 为空表示 .. 后接 [*] 等）
        case slice(Int?, Int?)           // [start:end]
        case filter(FilterExpr)          // [?(@.x == 'y')]
        case lengthFunc                  // .length()

        var isIndefinite: Bool {
            switch self {
            case .children, .wildcard, .recursive, .slice, .filter: return true
            default: return false
            }
        }

        func apply(to node: JSONValue, into out: inout [JSONValue]) {
            switch self {
            case .root:
                out.append(node)

            case .child(let name):
                if case .object(let o) = node, let v = o[name] { out.append(v) }

            case .children(let names):
                if case .object(let o) = node {
                    for n in names { if let v = o[n] { out.append(v) } }
                }

            case .index(let i):
                if case .array(let a) = node {
                    let idx = i < 0 ? a.count + i : i
                    if idx >= 0 && idx < a.count { out.append(a[idx]) }
                }

            case .wildcard:
                switch node {
                case .array(let a): out.append(contentsOf: a)
                case .object(let o): out.append(contentsOf: o.values)
                default: break
                }

            case .recursive(let name):
                // 递归下降：收集当前节点及所有后代里匹配 name 的值；name 为 nil 表示收集所有节点（配合后续 [*] 等）
                Token.collectRecursive(node, name: name, into: &out)

            case .slice(let start, let end):
                if case .array(let a) = node {
                    let n = a.count
                    var s = start ?? 0
                    var e = end ?? n
                    if s < 0 { s = max(n + s, 0) }
                    if e < 0 { e = max(n + e, 0) }
                    s = min(max(s, 0), n)
                    e = min(max(e, 0), n)
                    if s < e { out.append(contentsOf: a[s..<e]) }
                }

            case .filter(let expr):
                if case .array(let a) = node {
                    for item in a where expr.matches(item) { out.append(item) }
                }

            case .lengthFunc:
                switch node {
                case .array(let a): out.append(.number(Double(a.count)))
                case .string(let s): out.append(.number(Double(s.count)))
                case .object(let o): out.append(.number(Double(o.count)))
                default: break
                }
            }
        }

        private static func collectRecursive(_ node: JSONValue, name: String?, into out: inout [JSONValue]) {
            // 若 name 为 nil：把当前节点也纳入（用于 `..[*]` 之类）；否则匹配子键。
            if let name = name {
                if case .object(let o) = node, let v = o[name] { out.append(v) }
            } else {
                out.append(node)
            }
            switch node {
            case .object(let o):
                for v in o.values { collectRecursive(v, name: name, into: &out) }
            case .array(let a):
                for v in a { collectRecursive(v, name: name, into: &out) }
            default:
                break
            }
        }
    }

    // MARK: - 简单过滤器表达式  [?(@.field OP value)]

    struct FilterExpr {
        enum Op { case eq, ne, gt, lt, ge, le, exists }
        let field: String     // @. 后的字段路径（点分）
        let op: Op
        let value: JSONValue? // 比较目标（exists 时为 nil）

        func matches(_ item: JSONValue) -> Bool {
            let target = FilterExpr.resolve(field, in: item)
            switch op {
            case .exists:
                return target != nil
            case .eq:
                return target == value
            case .ne:
                return target != value
            case .gt, .lt, .ge, .le:
                guard let t = target, let v = value,
                      case .number(let tn) = t, case .number(let vn) = v else { return false }
                switch op {
                case .gt: return tn > vn
                case .lt: return tn < vn
                case .ge: return tn >= vn
                case .le: return tn <= vn
                default: return false
                }
            }
        }

        static func resolve(_ dotted: String, in node: JSONValue) -> JSONValue? {
            var cur = node
            for part in dotted.split(separator: ".") {
                guard case .object(let o) = cur, let v = o[String(part)] else { return nil }
                cur = v
            }
            return cur
        }
    }
}
