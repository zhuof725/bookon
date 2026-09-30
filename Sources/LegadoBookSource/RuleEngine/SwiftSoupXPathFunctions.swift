//
//  SwiftSoupXPathFunctions.swift
//  LegadoBookSource
//
//  XPath 字符串/数值函数支持：顶层函数调用（如 `string(//div/@id)`）与谓词内函数比较
//  （如 `[count(li)=3]`、`[substring(text(),1,5)='Hello']`）。以及联合运算符 `|` 的顶层切分。
//
//  覆盖：string()、count()、concat()、substring()、substring-before()、substring-after()、
//  string-length()、not()。参数里出现的相对路径（如 `li`、`@attr`、`text()`、`.`）通过对
//  "以当前候选元素为根的临时 SwiftSoupXPathEvaluator" 递归求值来解析，复用同一套
//  step/谓词解析逻辑，不另起一套简化实现，保证语义一致。
//

import Foundation
import SwiftSoup

extension SwiftSoupXPathEvaluator {

    // MARK: - 顶层 `|` 切分

    /// 按顶层 `|`（不在引号/`[]`/`()`内）切分表达式。恒返回至少 1 个元素。
    static func topLevelUnionParts(_ expr: String) -> [String] {
        var parts: [String] = []
        var cur = ""
        var inS = false, inD = false, depth = 0
        for c in expr {
            if c == "'" && !inD { inS.toggle(); cur.append(c) }
            else if c == "\"" && !inS { inD.toggle(); cur.append(c) }
            else if !inS && !inD {
                if c == "[" || c == "(" { depth += 1; cur.append(c) }
                else if c == "]" || c == ")" { depth -= 1; cur.append(c) }
                else if c == "|" && depth == 0 {
                    parts.append(cur.trimmingCharacters(in: .whitespaces))
                    cur = ""
                } else {
                    cur.append(c)
                }
            } else {
                cur.append(c)
            }
        }
        parts.append(cur.trimmingCharacters(in: .whitespaces))
        return parts
    }

    // MARK: - 顶层函数调用识别与求值

    /// 已知的顶层字符串/数值函数名。
    private static let topLevelFuncNames = ["string", "count", "concat", "substring-before", "substring-after", "substring", "string-length"]

    /// 若整个表达式是一次顶层函数调用（如 `string(//div/@id)`），求值并返回结果节点；否则返回 nil。
    static func tryEvalTopLevelFunction(_ expr: String, roots: [Element], evaluator: SwiftSoupXPathEvaluator) throws -> Node? {
        guard let (fn, argsStr) = matchFunctionCall(expr) else { return nil }
        guard topLevelFuncNames.contains(fn) else { return nil }
        let args = splitArgsTopLevelComma(argsStr)

        switch fn {
        case "string":
            guard args.count == 1 else { throw RuleEngineError.invalidXPath("string() 需 1 个参数 in \(expr)") }
            let s = try resolveToFirstString(args[0], roots: roots)
            return .text(s)
        case "count":
            guard args.count == 1 else { throw RuleEngineError.invalidXPath("count() 需 1 个参数 in \(expr)") }
            let nodes = try resolveToNodes(args[0], roots: roots)
            return .text(String(nodes.count))
        case "concat":
            guard args.count >= 2 else { throw RuleEngineError.invalidXPath("concat() 至少需 2 个参数 in \(expr)") }
            var out = ""
            for a in args { out += try resolveToFirstString(a, roots: roots) }
            return .text(out)
        case "substring":
            guard args.count == 2 || args.count == 3 else { throw RuleEngineError.invalidXPath("substring() 需 2 或 3 个参数 in \(expr)") }
            let s = try resolveToFirstString(args[0], roots: roots)
            let result = try applySubstring(s, args: Array(args.dropFirst()), whole: expr)
            return .text(result)
        case "substring-before":
            guard args.count == 2 else { throw RuleEngineError.invalidXPath("substring-before() 需 2 个参数 in \(expr)") }
            let s = try resolveToFirstString(args[0], roots: roots)
            let sep = try resolveLiteralOrString(args[1], roots: roots)
            return .text(substringBefore(s, sep))
        case "substring-after":
            guard args.count == 2 else { throw RuleEngineError.invalidXPath("substring-after() 需 2 个参数 in \(expr)") }
            let s = try resolveToFirstString(args[0], roots: roots)
            let sep = try resolveLiteralOrString(args[1], roots: roots)
            return .text(substringAfter(s, sep))
        case "string-length":
            guard args.count == 1 else { throw RuleEngineError.invalidXPath("string-length() 需 1 个参数 in \(expr)") }
            let s = try resolveToFirstString(args[0], roots: roots)
            return .text(String(s.count))
        default:
            return nil
        }
    }

    // MARK: - 谓词内函数比较：count(...)/string(...)/concat(...)/substring*(...)/string-length(...) 与字面量比较

    /// 尝试把谓词内部文本解析为「函数调用 OP 字面量」形式；不是则返回 nil。
    static func tryParsePredicateFunctionCompare(_ inner: String, whole: String) throws -> Predicate? {
        guard let eqRange = findTopLevelCompareOperator(inner) else { return nil }
        let (opRange, op) = eqRange
        let lhs = String(inner[inner.startIndex..<opRange.lowerBound]).trimmingCharacters(in: .whitespaces)
        let rhsRaw = String(inner[opRange.upperBound...]).trimmingCharacters(in: .whitespaces)

        guard let (fn, argsStr) = matchFunctionCall(lhs) else { return nil }
        let funcNames = ["count", "string", "concat", "substring-before", "substring-after", "substring", "string-length"]
        guard funcNames.contains(fn) else { return nil }
        let args = splitArgsTopLevelComma(argsStr)
        let rhsValue = stripQuotesPublic(rhsRaw)

        let call: PredicateFuncCall
        switch fn {
        case "count":
            guard args.count == 1 else { throw RuleEngineError.invalidXPath("count() 需 1 个参数 in \(whole)") }
            call = .count(path: args[0])
        case "string":
            guard args.count == 1 else { throw RuleEngineError.invalidXPath("string() 需 1 个参数 in \(whole)") }
            call = .string(arg: args[0])
        case "concat":
            guard args.count >= 2 else { throw RuleEngineError.invalidXPath("concat() 至少需 2 个参数 in \(whole)") }
            call = .concat(args: args)
        case "substring":
            guard args.count == 2 || args.count == 3 else { throw RuleEngineError.invalidXPath("substring() 需 2 或 3 个参数 in \(whole)") }
            call = .substring(arg: args[0], rest: Array(args.dropFirst()))
        case "substring-before":
            guard args.count == 2 else { throw RuleEngineError.invalidXPath("substring-before() 需 2 个参数 in \(whole)") }
            call = .substringBefore(arg: args[0], sep: args[1])
        case "substring-after":
            guard args.count == 2 else { throw RuleEngineError.invalidXPath("substring-after() 需 2 个参数 in \(whole)") }
            call = .substringAfter(arg: args[0], sep: args[1])
        case "string-length":
            guard args.count == 1 else { throw RuleEngineError.invalidXPath("string-length() 需 1 个参数 in \(whole)") }
            call = .stringLength(arg: args[0])
        default:
            return nil
        }
        return Predicate(kind: .funcCompare(call, op, rhsValue))
    }

    /// 找顶层（不在引号/括号内）的比较运算符 `=` 或 `!=`，返回其 range 与 Predicate.CompareOp。
    private static func findTopLevelCompareOperator(_ s: String) -> (Range<String.Index>, Predicate.CompareOp)? {
        var inS = false, inD = false, depth = 0
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            if c == "'" && !inD { inS.toggle() }
            else if c == "\"" && !inS { inD.toggle() }
            else if !inS && !inD {
                if c == "(" { depth += 1 }
                else if c == ")" { depth -= 1 }
                else if depth == 0 {
                    if c == "!" {
                        let next = s.index(after: i)
                        if next < s.endIndex && s[next] == "=" {
                            return (i..<s.index(i, offsetBy: 2), .ne)
                        }
                    } else if c == "=" {
                        return (i..<s.index(after: i), .eq)
                    }
                }
            }
            i = s.index(after: i)
        }
        return nil
    }

    // MARK: - 参数解析辅助

    /// 若 s 形如 `name(args)` 返回 (name, args字符串)；否则 nil。
    static func matchFunctionCall(_ s: String) -> (String, String)? {
        guard let open = s.firstIndex(of: "("), s.hasSuffix(")") else { return nil }
        let name = String(s[s.startIndex..<open]).trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, name.allSatisfy({ $0.isLetter || $0 == "-" }) else { return nil }
        let argsStr = String(s[s.index(after: open)..<s.index(before: s.endIndex)])
        return (name, argsStr)
    }

    static func splitArgsTopLevelComma(_ s: String) -> [String] {
        var parts: [String] = []; var cur = ""; var inS = false; var inD = false; var depth = 0
        for c in s {
            if c == "'" && !inD { inS.toggle(); cur.append(c) }
            else if c == "\"" && !inS { inD.toggle(); cur.append(c) }
            else if c == "," && !inS && !inD && depth == 0 { parts.append(cur.trimmingCharacters(in: .whitespaces)); cur = "" }
            else {
                if !inS && !inD { if c == "(" { depth += 1 }; if c == ")" { depth -= 1 } }
                cur.append(c)
            }
        }
        let last = cur.trimmingCharacters(in: .whitespaces)
        if !last.isEmpty || !parts.isEmpty { parts.append(last) }
        return parts
    }

    static func stripQuotesPublic(_ s: String) -> String {
        if (s.hasPrefix("'") && s.hasSuffix("'") && s.count >= 2) ||
           (s.hasPrefix("\"") && s.hasSuffix("\"") && s.count >= 2) {
            return String(s.dropFirst().dropLast())
        }
        return s
    }

    // MARK: - 参数求值（相对于给定根，可以是整个文档根，也可以是谓词里的单个候选元素）

    /// 把一个函数参数解析为节点集合：字面量('..'/"..")本身没有节点集合语义，这里仅用于路径参数。
    static func resolveToNodes(_ arg: String, roots: [Element]) throws -> [Node] {
        let a = arg.trimmingCharacters(in: .whitespaces)
        if isLiteral(a) { return [] }  // 字面量不是节点集合
        let sub = SwiftSoupXPathEvaluator(roots: roots)
        return try sub.evaluatePath(a)
    }

    /// 取参数的「字符串值」：字面量去引号；路径参数取第一个匹配节点的 stringValue（无匹配为 ""）。
    static func resolveToFirstString(_ arg: String, roots: [Element]) throws -> String {
        let a = arg.trimmingCharacters(in: .whitespaces)
        if isLiteral(a) { return stripQuotesPublic(a) }
        let nodes = try resolveToNodes(a, roots: roots)
        return nodes.first?.stringValue() ?? ""
    }

    /// substring-before/after 的第二参数：可以是字面量，也可以是路径（取第一个字符串值）。
    static func resolveLiteralOrString(_ arg: String, roots: [Element]) throws -> String {
        try resolveToFirstString(arg, roots: roots)
    }

    static func isLiteral(_ s: String) -> Bool {
        (s.hasPrefix("'") && s.hasSuffix("'")) || (s.hasPrefix("\"") && s.hasSuffix("\""))
    }

    // MARK: - substring 系列的字符串运算（XPath 1.0 语义：1-based 起点）

    static func applySubstring(_ s: String, args: [String], whole: String) throws -> String {
        let chars = Array(s)
        guard let startD = Double(args[0].trimmingCharacters(in: .whitespaces)) else {
            throw RuleEngineError.invalidXPath("substring() 起点必须是数字 in \(whole)")
        }
        // XPath: 1-based，起点四舍五入。
        let start = Int(startD.rounded()) - 1
        var length = chars.count - max(start, 0)
        if args.count == 2 {
            guard let lenD = Double(args[1].trimmingCharacters(in: .whitespaces)) else {
                throw RuleEngineError.invalidXPath("substring() 长度必须是数字 in \(whole)")
            }
            length = Int(lenD.rounded())
        }
        let s0 = max(start, 0)
        let s1 = min(chars.count, max(start, 0) + max(length - max(0, -start), 0))
        guard s0 < s1, s0 >= 0, s1 <= chars.count else { return "" }
        return String(chars[s0..<s1])
    }

    static func substringBefore(_ s: String, _ sep: String) -> String {
        guard !sep.isEmpty, let r = s.range(of: sep) else { return "" }
        return String(s[s.startIndex..<r.lowerBound])
    }

    static func substringAfter(_ s: String, _ sep: String) -> String {
        guard !sep.isEmpty, let r = s.range(of: sep) else { return "" }
        return String(s[r.upperBound...])
    }
}

/// 谓词内函数调用（用于与字面量比较，如 `[count(li)=3]`）。
enum PredicateFuncCall {
    case count(path: String)
    case string(arg: String)
    case concat(args: [String])
    case substring(arg: String, rest: [String])
    case substringBefore(arg: String, sep: String)
    case substringAfter(arg: String, sep: String)
    case stringLength(arg: String)

    /// 相对于单个候选元素（作为临时根）求值，返回字符串结果供比较。
    func evaluate(context: Element) throws -> String {
        let roots = [context]
        switch self {
        case .count(let path):
            let nodes = try SwiftSoupXPathEvaluator.resolveToNodes(path, roots: roots)
            return String(nodes.count)
        case .string(let arg):
            return try SwiftSoupXPathEvaluator.resolveToFirstString(arg, roots: roots)
        case .concat(let args):
            var out = ""
            for a in args { out += try SwiftSoupXPathEvaluator.resolveToFirstString(a, roots: roots) }
            return out
        case .substring(let arg, let rest):
            let s = try SwiftSoupXPathEvaluator.resolveToFirstString(arg, roots: roots)
            return try SwiftSoupXPathEvaluator.applySubstring(s, args: rest, whole: "substring(...) in predicate")
        case .substringBefore(let arg, let sep):
            let s = try SwiftSoupXPathEvaluator.resolveToFirstString(arg, roots: roots)
            let sepV = try SwiftSoupXPathEvaluator.resolveLiteralOrString(sep, roots: roots)
            return SwiftSoupXPathEvaluator.substringBefore(s, sepV)
        case .substringAfter(let arg, let sep):
            let s = try SwiftSoupXPathEvaluator.resolveToFirstString(arg, roots: roots)
            let sepV = try SwiftSoupXPathEvaluator.resolveLiteralOrString(sep, roots: roots)
            return SwiftSoupXPathEvaluator.substringAfter(s, sepV)
        case .stringLength(let arg):
            let s = try SwiftSoupXPathEvaluator.resolveToFirstString(arg, roots: roots)
            return String(s.count)
        }
    }
}
