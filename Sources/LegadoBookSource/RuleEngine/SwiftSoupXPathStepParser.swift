//
//  SwiftSoupXPathStepParser.swift
//  LegadoBookSource
//
//  把 XPath 表达式解析成 SwiftSoupXPathEvaluator.Step 序列。
//  仅覆盖 README「已支持」表中的语法；遇到不支持的抛 RuleEngineError.invalidXPath。
//

import Foundation

extension SwiftSoupXPathEvaluator {

    enum XPathParser {

        /// 解析表达式为 step 列表。
        static func parse(_ expr: String) throws -> [Step] {
            let s = Array(expr)
            var i = 0
            let n = s.count
            var steps: [Step] = []

            // 处理前导 . 或 .. 或 / 或 //
            // 逐段切分：以 / 分隔，// 记为 descendant-or-self。
            // 起始若无 / 前缀，视为相对（child from context）。
            var pendingDescendant = false

            // 跳过前导空白
            func skipWS() { while i < n && (s[i] == " " || s[i] == "\t" || s[i] == "\n" || s[i] == "\r") { i += 1 } }

            skipWS()
            // 绝对路径起始
            if i < n && s[i] == "/" {
                if i + 1 < n && s[i+1] == "/" { pendingDescendant = true; i += 2 }
                else { i += 1 }  // 绝对根 child
            }

            while i < n {
                skipWS()
                if i >= n { break }
                // 读一个 step 文本（到下一个未被括号/引号包裹的 '/'）
                let (stepText, consumed) = readStepText(s, i)
                i = consumed
                let trimmed = stepText.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    let step = try parseStep(trimmed, descendant: pendingDescendant, whole: expr)
                    steps.append(step)
                }
                pendingDescendant = false
                // 处理分隔符
                skipWS()
                if i < n && s[i] == "/" {
                    if i + 1 < n && s[i+1] == "/" { pendingDescendant = true; i += 2 }
                    else { i += 1 }
                }
            }

            if steps.isEmpty {
                throw RuleEngineError.invalidXPath(expr)
            }
            return steps
        }

        /// 读一个 step 文本，直到未被 []/引号 包裹的 '/'。
        private static func readStepText(_ s: [Character], _ start: Int) -> (String, Int) {
            var i = start
            var depth = 0
            var inSingle = false
            var inDouble = false
            var out = ""
            while i < s.count {
                let c = s[i]
                if c == "'" && !inDouble { inSingle.toggle(); out.append(c); i += 1; continue }
                if c == "\"" && !inSingle { inDouble.toggle(); out.append(c); i += 1; continue }
                if !inSingle && !inDouble {
                    if c == "[" { depth += 1 }
                    else if c == "]" { depth -= 1 }
                    else if c == "/" && depth == 0 { break }
                }
                out.append(c)
                i += 1
            }
            return (out, i)
        }

        /// 解析单个 step。
        private static func parseStep(_ text: String, descendant: Bool, whole: String) throws -> Step {
            var t = text

            // 自身 / 父：. 与 ..
            if t == "." {
                return Step(axis: descendant ? .descendantOrSelf : .selfAxis,
                            nodeTest: .node, predicates: [], terminal: nil)
            }
            if t == ".." {
                return Step(axis: .parent, nodeTest: .node, predicates: [], terminal: nil)
            }

            var axis: Step.Axis = descendant ? .descendantOrSelf : .child

            // 轴前缀 axis::
            if let r = t.range(of: "::") {
                let axisName = String(t[t.startIndex..<r.lowerBound])
                t = String(t[r.upperBound...])
                switch axisName {
                case "child": axis = .child
                case "descendant": axis = .descendant
                case "descendant-or-self": axis = .descendantOrSelf
                case "self": axis = .selfAxis
                case "parent": axis = .parent
                case "ancestor": axis = .ancestor
                case "following-sibling": axis = .followingSibling
                case "preceding-sibling": axis = .precedingSibling
                case "following": axis = .following
                case "preceding": axis = .preceding
                case "attribute": axis = .attribute
                default: throw RuleEngineError.invalidXPath("不支持的轴 \(axisName)::  in \(whole)")
            }
            }

            // @attr 作为 step（属性节点）
            if t.hasPrefix("@") {
                let attr = String(t.dropFirst())
                if attr.isEmpty { throw RuleEngineError.invalidXPath("空 @ 属性 in \(whole)") }
                return Step(axis: .attribute, nodeTest: .name(attr), predicates: [], terminal: nil)
            }

            // 拆出谓词
            var predicates: [Predicate] = []
            if let br = t.firstIndex(of: "[") {
                let nodePart = String(t[t.startIndex..<br])
                let predPart = String(t[br...])
                predicates = try parsePredicates(predPart, whole: whole)
                t = nodePart
            }

            // 末尾函数 / node test
            var terminal: Step.Terminal? = nil
            var nodeTest: Step.NodeTest = .wildcard

            // 这些函数作用于「当前上下文节点自身」（对齐 XPath text()/JsoupXpath 扩展语义）：
            // 若这一步既没有显式轴前缀、也不是 // 引出的 descendant-or-self，
            // 须用 selfAxis 而非默认 child，否则会变成"取子元素的文本"而非"取自身的文本"。
            // 但 //text() 这种由 // 引出的情形要保留 descendantOrSelf（取所有后代的文本）。
            let lower = t.lowercased()
            let isPlainChildDefault = (axis == .child)  // 未被 axis:: 或 // 覆盖过的默认值
            if lower == "text()" {
                terminal = .funcText; nodeTest = .wildcard
                if isPlainChildDefault { axis = .selfAxis }
            } else if lower == "alltext()" {
                terminal = .funcAllText
                if isPlainChildDefault { axis = .selfAxis }
            } else if lower == "html()" {
                terminal = .funcHtml
                if isPlainChildDefault { axis = .selfAxis }
            } else if lower == "outerhtml()" {
                terminal = .funcOuterHtml
                if isPlainChildDefault { axis = .selfAxis }
            } else if lower == "owntext()" {
                terminal = .funcOwnText
                if isPlainChildDefault { axis = .selfAxis }
            } else if lower == "node()" {
                nodeTest = .node
            } else if t == "*" {
                nodeTest = .wildcard
            } else if t.hasPrefix("@") {
                terminal = .attribute(String(t.dropFirst()))
                nodeTest = .wildcard
            } else if t.isEmpty {
                nodeTest = .node
            } else if isValidNameTest(t) {
                nodeTest = .name(t)
            } else {
                throw RuleEngineError.invalidXPath("无法解析的节点测试 '\(t)' in \(whole)")
            }

            return Step(axis: axis, nodeTest: nodeTest, predicates: predicates, terminal: terminal)
        }

        private static func isValidNameTest(_ t: String) -> Bool {
            // 标签名：字母/数字/下划线/连字符/冒号（命名空间）
            return !t.isEmpty && t.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" || $0 == ":" }
        }

        // MARK: 谓词解析

        /// 解析一串谓词 "[...][...]"。
        static func parsePredicates(_ text: String, whole: String) throws -> [Predicate] {
            var preds: [Predicate] = []
            let s = Array(text)
            var i = 0
            while i < s.count {
                guard s[i] == "[" else {
                    if s[i] == " " { i += 1; continue }
                    throw RuleEngineError.invalidXPath("谓词格式错误 in \(whole)")
                }
                // 找到匹配的 ]
                var depth = 0; var j = i; var inS = false; var inD = false
                var found = -1
                while j < s.count {
                    let c = s[j]
                    if c == "'" && !inD { inS.toggle() }
                    else if c == "\"" && !inS { inD.toggle() }
                    else if !inS && !inD {
                        if c == "[" { depth += 1 }
                        else if c == "]" { depth -= 1; if depth == 0 { found = j; break } }
                    }
                    j += 1
                }
                if found < 0 { throw RuleEngineError.invalidXPath("谓词方括号不平衡 in \(whole)") }
                let inner = String(s[(i+1)..<found]).trimmingCharacters(in: .whitespaces)
                preds.append(try parseOnePredicate(inner, whole: whole))
                i = found + 1
            }
            return preds
        }

        static func parseOnePredicate(_ inner: String, whole: String) throws -> Predicate {
            // and / or（顶层，简单按小写关键字切；不处理括号嵌套的逻辑分组）
            if let parts = splitLogical(inner, keyword: " or ") {
                return Predicate(kind: .or(try parts.map { try parseOnePredicate($0, whole: whole) }))
            }
            if let parts = splitLogical(inner, keyword: " and ") {
                return Predicate(kind: .and(try parts.map { try parseOnePredicate($0, whole: whole) }))
            }

            let t = inner.trimmingCharacters(in: .whitespaces)

            // not(...)
            if t.hasPrefix("not(") && t.hasSuffix(")") {
                let innerExpr = String(t.dropFirst(4).dropLast())
                return Predicate(kind: .not(try parseOnePredicate(innerExpr, whole: whole)))
            }

            // 函数比较：count(...)=n / string(...)='x' / concat(...)='x' / substring*(...)='x' / string-length(...)=n
            // 必须在 contains/starts-with/normalize-space 等专用函数分支之前尝试，覆盖更广的函数名集合。
            if let funcPred = try SwiftSoupXPathEvaluator.tryParsePredicateFunctionCompare(t, whole: whole) {
                return funcPred
            }

            // 纯数字 [n]
            if let n = Int(t) {
                return Predicate(kind: .position(PositionSpec(usesLast: false, offset: n, op: .eq, literalIndex: n)))
            }
            // last() 及 last()-k
            if t == "last()" {
                return Predicate(kind: .position(PositionSpec(usesLast: true, offset: 0, op: .eq, literalIndex: nil)))
            }
            if t.hasPrefix("last()") {
                let rest = t.dropFirst("last()".count).replacingOccurrences(of: " ", with: "")
                if rest.hasPrefix("-"), let k = Int(rest.dropFirst()) {
                    return Predicate(kind: .position(PositionSpec(usesLast: true, offset: k, op: .eq, literalIndex: nil)))
                }
            }
            // position() OP n
            if t.hasPrefix("position()") {
                let rest = t.dropFirst("position()".count).trimmingCharacters(in: .whitespaces)
                for (sym, op): (String, PositionSpec.Op) in [(">=", .ge), ("<=", .le), (">", .gt), ("<", .lt), ("=", .eq)] {
                    if rest.hasPrefix(sym) {
                        let numStr = rest.dropFirst(sym.count).trimmingCharacters(in: .whitespaces)
                        if let num = Int(numStr) {
                            return Predicate(kind: .position(PositionSpec(usesLast: false, offset: num, op: op, literalIndex: nil)))
                        }
                    }
                }
                throw RuleEngineError.invalidXPath("position() 谓词无法解析 '\(t)' in \(whole)")
            }
            // 函数：contains / starts-with / normalize-space
            if t.hasPrefix("contains(") {
                let (target, value) = try parseFuncArgs(t, fn: "contains", whole: whole)
                return Predicate(kind: .function(.init(name: .contains, target: target, value: value)))
            }
            if t.hasPrefix("starts-with(") {
                let (target, value) = try parseFuncArgs(t, fn: "starts-with", whole: whole)
                return Predicate(kind: .function(.init(name: .startsWith, target: target, value: value)))
            }
            if t.hasPrefix("normalize-space(") {
                // 形如 normalize-space(@x)='v' 或 normalize-space(text())='v'
                guard let eq = t.range(of: "=") else {
                    throw RuleEngineError.invalidXPath("normalize-space 需比较 in \(whole)")
                }
                let fnPart = String(t[t.startIndex..<eq.lowerBound]).trimmingCharacters(in: .whitespaces)
                let valPart = String(t[eq.upperBound...]).trimmingCharacters(in: .whitespaces)
                let target = try parseTargetFromFuncCall(fnPart, fn: "normalize-space", whole: whole)
                let value = stripQuotes(valPart)
                return Predicate(kind: .function(.init(name: .normalizeSpaceEq, target: target, value: value)))
            }
            // @attr 存在 / 比较
            if t.hasPrefix("@") {
                // ⚠️ 必须先检查 "!="，再检查单独的 "="：否则 "@class!='odd'" 里的 "="（属于 "!="
                // 的一部分）会被 range(of:"=") 先匹配到，导致属性名被错误解析成 "class!"。
                if let ne = t.range(of: "!=") {
                    let name = String(t[t.index(t.startIndex, offsetBy: 1)..<ne.lowerBound]).trimmingCharacters(in: .whitespaces)
                    let val = stripQuotes(String(t[ne.upperBound...]).trimmingCharacters(in: .whitespaces))
                    return Predicate(kind: .attrCompare(name: name, op: .ne, value: val))
                }
                if let eq = t.range(of: "=") {
                    let name = String(t[t.index(t.startIndex, offsetBy: 1)..<eq.lowerBound]).trimmingCharacters(in: .whitespaces)
                    let val = stripQuotes(String(t[eq.upperBound...]).trimmingCharacters(in: .whitespaces))
                    return Predicate(kind: .attrCompare(name: name, op: .eq, value: val))
                }
                let name = String(t.dropFirst())
                return Predicate(kind: .attrExists(name))
            }
            // text() 比较
            if t.hasPrefix("text()") {
                let rest = t.dropFirst("text()".count).trimmingCharacters(in: .whitespaces)
                if rest.hasPrefix("=") {
                    let val = stripQuotes(rest.dropFirst().trimmingCharacters(in: .whitespaces))
                    return Predicate(kind: .textCompare(op: .eq, value: val))
                }
                if rest.hasPrefix("!=") {
                    let val = stripQuotes(rest.dropFirst(2).trimmingCharacters(in: .whitespaces))
                    return Predicate(kind: .textCompare(op: .ne, value: val))
                }
            }
            throw RuleEngineError.invalidXPath("不支持的谓词 '\(inner)' in \(whole)")
        }

        // 拆 and/or（大小写不敏感），忽略引号内的关键字。返回 nil 表示没有该关键字。
        private static func splitLogical(_ inner: String, keyword: String) -> [String]? {
            let lower = inner.lowercased()
            guard lower.contains(keyword) else { return nil }
            var parts: [String] = []
            let s = Array(inner)
            let low = Array(lower)
            let k = Array(keyword)
            var i = 0; var last = 0; var inS = false; var inD = false; var depth = 0
            while i <= s.count - k.count {
                let c = s[i]
                if c == "'" && !inD { inS.toggle() }
                else if c == "\"" && !inS { inD.toggle() }
                else if !inS && !inD {
                    if c == "(" || c == "[" { depth += 1 }
                    else if c == ")" || c == "]" { depth -= 1 }
                    else if depth == 0 {
                        var match = true
                        for m in 0..<k.count where low[i+m] != k[m] { match = false; break }
                        if match {
                            parts.append(String(s[last..<i]))
                            i += k.count; last = i; continue
                        }
                    }
                }
                i += 1
            }
            parts.append(String(s[last...]))
            return parts.count > 1 ? parts.map { $0.trimmingCharacters(in: .whitespaces) } : nil
        }

        // contains(@x,'v') / contains(text(),'v')
        private static func parseFuncArgs(_ t: String, fn: String, whole: String) throws -> (Predicate.FuncPred.Target, String) {
            guard t.hasSuffix(")"), let open = t.firstIndex(of: "(") else {
                throw RuleEngineError.invalidXPath("\(fn) 语法错误 in \(whole)")
            }
            let argsStr = String(t[t.index(after: open)..<t.index(before: t.endIndex)])
            let args = splitTopLevelComma(argsStr)
            guard args.count == 2 else { throw RuleEngineError.invalidXPath("\(fn) 需 2 个参数 in \(whole)") }
            let target = try parseTargetArg(args[0].trimmingCharacters(in: .whitespaces), whole: whole)
            let value = stripQuotes(args[1].trimmingCharacters(in: .whitespaces))
            return (target, value)
        }

        private static func parseTargetArg(_ a: String, whole: String) throws -> Predicate.FuncPred.Target {
            if a.hasPrefix("@") { return .attr(String(a.dropFirst())) }
            if a == "text()" { return .text }
            if a == "." { return .current }
            throw RuleEngineError.invalidXPath("不支持的函数目标 '\(a)' in \(whole)")
        }

        private static func parseTargetFromFuncCall(_ fnPart: String, fn: String, whole: String) throws -> Predicate.FuncPred.Target {
            guard fnPart.hasPrefix(fn + "("), fnPart.hasSuffix(")") else {
                throw RuleEngineError.invalidXPath("\(fn) 语法错误 in \(whole)")
            }
            let inner = String(fnPart.dropFirst(fn.count + 1).dropLast())
            return try parseTargetArg(inner.trimmingCharacters(in: .whitespaces), whole: whole)
        }

        private static func splitTopLevelComma(_ s: String) -> [String] {
            var parts: [String] = []; var cur = ""; var inS = false; var inD = false; var depth = 0
            for c in s {
                if c == "'" && !inD { inS.toggle(); cur.append(c) }
                else if c == "\"" && !inS { inD.toggle(); cur.append(c) }
                else if c == "," && !inS && !inD && depth == 0 { parts.append(cur); cur = "" }
                else {
                    if !inS && !inD { if c == "(" { depth += 1 }; if c == ")" { depth -= 1 } }
                    cur.append(c)
                }
            }
            parts.append(cur)
            return parts
        }

        private static func stripQuotes(_ s: String) -> String {
            if (s.hasPrefix("'") && s.hasSuffix("'") && s.count >= 2) ||
               (s.hasPrefix("\"") && s.hasSuffix("\"") && s.count >= 2) {
                return String(s.dropFirst().dropLast())
            }
            return s
        }
    }
}
