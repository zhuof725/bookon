//
//  JSONPathParser.swift
//  LegadoBookSource
//
//  把 JSONPath 表达式解析成 DefaultJSONPathEvaluator.Token 序列。
//  仅覆盖 README 对照表中「已支持」的语法。遇到不支持的语法抛 unsupportedSyntax。
//

import Foundation

enum PathParser {

    static func parse(_ path: String) throws -> [DefaultJSONPathEvaluator.Token] {
        var tokens: [DefaultJSONPathEvaluator.Token] = []
        let s = Array(path)
        var i = 0
        let n = s.count

        // 允许以 $ 开头；也容忍不带 $ 的相对路径（Jayway 要求 $ 或 @，这里对 $ 与省略都兼容）
        if i < n && s[i] == "$" {
            tokens.append(.root)
            i += 1
        } else {
            tokens.append(.root)
        }

        while i < n {
            let c = s[i]
            if c == "." {
                // 可能是 ".." （递归）或 ".name" 或 ".*" 或 ".length()" 或 ".[*]"（点后跟方括号）
                if i + 1 < n && s[i + 1] == "." {
                    // 递归下降 ..
                    i += 2
                    // .. 后面可能直接跟 name，或跟 [ ... ]
                    if i < n && (s[i] == "[") {
                        // ..[*] / ..[n] 等：先放一个 recursive(nil) 收集所有节点，再由后续 [ ] 段处理
                        tokens.append(.recursive(nil))
                        // 交给下面的 '[' 分支处理
                        continue
                    } else {
                        let name = readName(s, &i)
                        if name.isEmpty {
                            throw JSONPathError.unsupportedSyntax("..(空名) in \(path)")
                        }
                        if name == "*" {
                            tokens.append(.recursive(nil))
                        } else {
                            tokens.append(.recursive(name))
                        }
                    }
                } else {
                    // 单个 .
                    i += 1
                    if i < n && s[i] == "[" {
                        // ".[" 形式（如 $.a.[*]），点被忽略，交给 '[' 分支
                        continue
                    }
                    if i < n && s[i] == "*" {
                        tokens.append(.wildcard)
                        i += 1
                        continue
                    }
                    let name = readName(s, &i)
                    if name.isEmpty {
                        throw JSONPathError.unsupportedSyntax(".(空名) in \(path)")
                    }
                    // .length() 函数
                    if name == "length" && i + 1 < n && s[i] == "(" && s[i + 1] == ")" {
                        tokens.append(.lengthFunc)
                        i += 2
                    } else {
                        tokens.append(.child(name))
                    }
                }
            } else if c == "[" {
                // 方括号段：[*] [n] [a:b] ['a'] ['a','b'] [?(...)]
                guard let close = matchBracket(s, i) else {
                    throw JSONPathError.invalidPath("方括号不平衡 in \(path)")
                }
                let inner = String(s[(i + 1)..<close]).trimmingCharacters(in: .whitespaces)
                tokens.append(try parseBracket(inner, path: path))
                i = close + 1
            } else if c == "*" {
                tokens.append(.wildcard)
                i += 1
            } else if isNameStart(c) {
                // 裸字段名开头（如无 $ 前缀的 "data.books"，或 $ 后紧跟名字 "$data"）。
                // Jayway/legado 允许不带前导点的首段属性名，这里对齐兼容。
                let name = readName(s, &i)
                if name == "length" && i + 1 < n && s[i] == "(" && s[i + 1] == ")" {
                    tokens.append(.lengthFunc)
                    i += 2
                } else {
                    tokens.append(.child(name))
                }
            } else {
                // 其它字符：出现未知结构时不猜，抛不支持。
                throw JSONPathError.unsupportedSyntax("无法解析的字符 '\(c)' in \(path)")
            }
        }

        return tokens
    }

    /// 是否是「字段名」的合法起始字符（字母 / 下划线 / 数字 / 中文等非结构字符）。
    private static func isNameStart(_ c: Character) -> Bool {
        return c != "." && c != "[" && c != "]" && c != "*" && c != "$" && c != "(" && c != ")"
    }

    /// 读取一个字段名（直到 . [ 或结尾）。
    private static func readName(_ s: [Character], _ i: inout Int) -> String {
        var name = ""
        while i < s.count {
            let c = s[i]
            // 在 . [ ( 处停止：`(` 用于识别函数调用（如 length()），否则会把 "length()" 整体当成字段名。
            if c == "." || c == "[" || c == "(" { break }
            name.append(c)
            i += 1
        }
        return name
    }

    /// 找到与位置 i 处 '[' 匹配的 ']'（考虑引号内的 ]）。
    private static func matchBracket(_ s: [Character], _ open: Int) -> Int? {
        var depth = 0
        var i = open
        var inSingle = false
        var inDouble = false
        while i < s.count {
            let c = s[i]
            if c == "'" && !inDouble { inSingle.toggle() }
            else if c == "\"" && !inSingle { inDouble.toggle() }
            else if !inSingle && !inDouble {
                if c == "[" { depth += 1 }
                else if c == "]" { depth -= 1; if depth == 0 { return i } }
            }
            i += 1
        }
        return nil
    }

    /// 解析方括号内部内容。
    private static func parseBracket(_ inner: String, path: String) throws -> DefaultJSONPathEvaluator.Token {
        if inner == "*" {
            return .wildcard
        }
        // 过滤器 ?(...)
        if inner.hasPrefix("?(") && inner.hasSuffix(")") {
            let expr = String(inner.dropFirst(2).dropLast())
            return .filter(try parseFilter(expr, path: path))
        }
        // 引号字段：'a' 或 'a','b' 或 "a"
        if inner.hasPrefix("'") || inner.hasPrefix("\"") {
            let names = try parseQuotedNames(inner, path: path)
            if names.count == 1 { return .child(names[0]) }
            return .children(names)
        }
        // 切片 a:b
        if inner.contains(":") {
            let parts = inner.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            let startStr = parts.first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
            let endStr = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespaces) : ""
            let start = startStr.isEmpty ? nil : Int(startStr)
            let end = endStr.isEmpty ? nil : Int(endStr)
            if (start == nil && !startStr.isEmpty) || (end == nil && !endStr.isEmpty) {
                throw JSONPathError.unsupportedSyntax("切片 [\(inner)] in \(path)")
            }
            return .slice(start, end)
        }
        // 纯数字下标（含负数）
        if let idx = Int(inner) {
            return .index(idx)
        }
        // 无引号的裸字段名（Jayway 也容忍 [name]）
        if !inner.isEmpty && inner.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }) {
            return .child(inner)
        }
        throw JSONPathError.unsupportedSyntax("方括号内容 [\(inner)] in \(path)")
    }

    /// 解析 ['a','b'] / ["a"] 内的字段名列表。
    private static func parseQuotedNames(_ inner: String, path: String) throws -> [String] {
        var names: [String] = []
        let s = Array(inner)
        var i = 0
        while i < s.count {
            // 跳过分隔符与空白
            while i < s.count && (s[i] == "," || s[i] == " ") { i += 1 }
            if i >= s.count { break }
            let quote = s[i]
            guard quote == "'" || quote == "\"" else {
                throw JSONPathError.unsupportedSyntax("多字段引号 [\(inner)] in \(path)")
            }
            i += 1
            var name = ""
            while i < s.count && s[i] != quote {
                // 简单转义
                if s[i] == "\\" && i + 1 < s.count { i += 1 }
                name.append(s[i])
                i += 1
            }
            guard i < s.count else { throw JSONPathError.invalidPath("引号未闭合 in \(path)") }
            i += 1 // 跳过结束引号
            names.append(name)
        }
        if names.isEmpty { throw JSONPathError.unsupportedSyntax("空多字段 [\(inner)] in \(path)") }
        return names
    }

    /// 解析简单过滤器：@.field OP value 或 @.field（exists）。
    private static func parseFilter(_ expr: String, path: String) throws -> DefaultJSONPathEvaluator.FilterExpr {
        let e = expr.trimmingCharacters(in: .whitespaces)
        guard e.hasPrefix("@.") || e.hasPrefix("@[") else {
            throw JSONPathError.unsupportedSyntax("过滤器 [?(\(expr))] in \(path)")
        }
        // 依次尝试各比较运算符（顺序影响 == / != / >= / <= 的识别）
        let ops: [(String, DefaultJSONPathEvaluator.FilterExpr.Op)] = [
            ("==", .eq), ("!=", .ne), (">=", .ge), ("<=", .le), (">", .gt), ("<", .lt)
        ]
        for (sym, op) in ops {
            if let r = e.range(of: sym) {
                let lhs = String(e[e.startIndex..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
                let rhs = String(e[r.upperBound...]).trimmingCharacters(in: .whitespaces)
                let field = try filterField(lhs, path: path)
                let value = parseFilterValue(rhs)
                return DefaultJSONPathEvaluator.FilterExpr(field: field, op: op, value: value)
            }
        }
        // 无运算符 → 存在性判断
        let field = try filterField(e, path: path)
        return DefaultJSONPathEvaluator.FilterExpr(field: field, op: .exists, value: nil)
    }

    private static func filterField(_ lhs: String, path: String) throws -> String {
        // @.a.b -> a.b
        if lhs.hasPrefix("@.") { return String(lhs.dropFirst(2)) }
        throw JSONPathError.unsupportedSyntax("过滤器字段 \(lhs) in \(path)")
    }

    private static func parseFilterValue(_ rhs: String) -> JSONValue {
        var v = rhs
        if (v.hasPrefix("'") && v.hasSuffix("'")) || (v.hasPrefix("\"") && v.hasSuffix("\"")) {
            v = String(v.dropFirst().dropLast())
            return .string(v)
        }
        if v == "true" { return .bool(true) }
        if v == "false" { return .bool(false) }
        if v == "null" { return .null }
        // 整数字面量优先按 int，其余按 double（对齐数字精度拆分）。
        if !v.contains(".") && !v.lowercased().contains("e"), let i = Int64(v) { return .int(i) }
        if let d = Double(v) { return .double(d) }
        return .string(v)
    }
}
