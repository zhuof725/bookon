//
//  OrderedJSONParser.swift
//  LegadoBookSource
//
//  一个最小的保序 JSON 解析器，直接产出 JSONValue：
//   - 对象保留 JSON 文本里的键顺序（对齐 Jayway/json-smart 的 LinkedHashMap 有序语义）；
//   - 数字区分整数（Int64，19 位以内精确）与小数（Double），不经过统一的 Double 丢精度；
//   - 解析失败返回 nil（上层 JSONValue.parse 处理）。
//
//  仅覆盖标准 JSON 语法；不接受注释 / 尾随逗号等非标准写法（与 JSONSerialization 一致的严格度）。
//

import Foundation

struct OrderedJSONParser {
    private let s: [Character]
    private var i = 0

    init(_ text: String) {
        self.s = Array(text)
    }

    mutating func parse() -> JSONValue? {
        skipWhitespace()
        guard let v = parseValue() else { return nil }
        skipWhitespace()
        // 允许结尾多余空白；若还有非空白字符，视为非法。
        if i != s.count { return nil }
        return v
    }

    private mutating func parseValue() -> JSONValue? {
        skipWhitespace()
        guard i < s.count else { return nil }
        let c = s[i]
        switch c {
        case "{": return parseObject()
        case "[": return parseArray()
        case "\"": return parseString().map { .string($0) }
        case "t", "f": return parseBool()
        case "n": return parseNull()
        default:
            if c == "-" || (c >= "0" && c <= "9") { return parseNumber() }
            return nil
        }
    }

    private mutating func parseObject() -> JSONValue? {
        i += 1 // 跳过 {
        var obj = JSONValue.OrderedObject()
        skipWhitespace()
        if i < s.count && s[i] == "}" { i += 1; return .object(obj) }
        while i < s.count {
            skipWhitespace()
            guard i < s.count, s[i] == "\"", let key = parseString() else { return nil }
            skipWhitespace()
            guard i < s.count, s[i] == ":" else { return nil }
            i += 1 // 跳过 :
            guard let value = parseValue() else { return nil }
            obj[key] = value
            skipWhitespace()
            guard i < s.count else { return nil }
            if s[i] == "," { i += 1; continue }
            if s[i] == "}" { i += 1; return .object(obj) }
            return nil
        }
        return nil
    }

    private mutating func parseArray() -> JSONValue? {
        i += 1 // 跳过 [
        var arr: [JSONValue] = []
        skipWhitespace()
        if i < s.count && s[i] == "]" { i += 1; return .array(arr) }
        while i < s.count {
            guard let value = parseValue() else { return nil }
            arr.append(value)
            skipWhitespace()
            guard i < s.count else { return nil }
            if s[i] == "," { i += 1; continue }
            if s[i] == "]" { i += 1; return .array(arr) }
            return nil
        }
        return nil
    }

    private mutating func parseString() -> String? {
        guard i < s.count, s[i] == "\"" else { return nil }
        i += 1 // 跳过起始引号
        var out = ""
        while i < s.count {
            let c = s[i]; i += 1
            if c == "\"" { return out }
            if c == "\\" {
                guard i < s.count else { return nil }
                let e = s[i]; i += 1
                switch e {
                case "\"": out.append("\"")
                case "\\": out.append("\\")
                case "/": out.append("/")
                case "n": out.append("\n")
                case "t": out.append("\t")
                case "r": out.append("\r")
                case "b": out.append("\u{08}")
                case "f": out.append("\u{0C}")
                case "u":
                    guard i + 4 <= s.count else { return nil }
                    let hex = String(s[i..<i+4])
                    guard let code = UInt32(hex, radix: 16) else { return nil }
                    i += 4
                    // 处理 UTF-16 代理对
                    if code >= 0xD800 && code <= 0xDBFF {
                        // 高位代理，需再读一个 \uXXXX 低位
                        guard i + 6 <= s.count, s[i] == "\\", s[i+1] == "u" else { return nil }
                        let hex2 = String(s[i+2..<i+6])
                        guard let low = UInt32(hex2, radix: 16), low >= 0xDC00, low <= 0xDFFF else { return nil }
                        i += 6
                        let scalarValue = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
                        if let u = Unicode.Scalar(scalarValue) { out.unicodeScalars.append(u) }
                    } else if let u = Unicode.Scalar(code) {
                        out.unicodeScalars.append(u)
                    }
                default:
                    return nil
                }
            } else {
                out.append(c)
            }
        }
        return nil // 未闭合
    }

    private mutating func parseBool() -> JSONValue? {
        if matchLiteral("true") { return .bool(true) }
        if matchLiteral("false") { return .bool(false) }
        return nil
    }

    private mutating func parseNull() -> JSONValue? {
        if matchLiteral("null") { return .null }
        return nil
    }

    private mutating func matchLiteral(_ lit: String) -> Bool {
        let chars = Array(lit)
        guard i + chars.count <= s.count else { return false }
        for k in 0..<chars.count where s[i + k] != chars[k] { return false }
        i += chars.count
        return true
    }

    private mutating func parseNumber() -> JSONValue? {
        let startIdx = i
        var isDouble = false
        if i < s.count && s[i] == "-" { i += 1 }
        while i < s.count {
            let c = s[i]
            if c >= "0" && c <= "9" { i += 1 }
            else if c == "." || c == "e" || c == "E" || c == "+" || c == "-" {
                isDouble = true
                i += 1
            } else { break }
        }
        let numStr = String(s[startIdx..<i])
        if !isDouble {
            if let intVal = Int64(numStr) {
                return .int(intVal)         // 整数字面量 -> Int64（19 位以内精确）
            }
            // 超出 Int64 的纯整数：保留原始数字文本，不丢精度（对齐 json-smart BigInteger）。
            return .bigInteger(numStr)
        }
        if let d = Double(numStr) {
            return .double(d)               // 小数 / 科学计数法 -> Double
        }
        // 数字文本无法解析（异常格式）-> 解析失败。
        return nil
    }

    private mutating func skipWhitespace() {
        while i < s.count {
            let c = s[i]
            if c == " " || c == "\n" || c == "\t" || c == "\r" { i += 1 } else { break }
        }
    }
}
