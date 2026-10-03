//
//  GsonJSON.swift
//  LegadoBookSource
//
//  第 6 步 6A：为 UrlOption 的解析做「Gson 兼容」的 JSON 值模型与解析器。
//
//  为什么不用 Foundation 的 JSONSerialization：
//   1. 需要保持对象的键顺序（Gson 用 LinkedTreeMap；`getBody()` 会重新序列化成 JSON 文本，
//      键顺序会进 golden 对照）；
//   2. 需要区分 Long / Double（legado 的 GSON 设了 ToNumberPolicy.LONG_OR_DOUBLE）；
//   3. 需要两种严格度：analyzeUrl 先用 GSONStrict（Strictness.STRICT）再用 GSON（宽松回退），
//      两次的成功/失败会影响最终结果（宽松成功时会记一条 log）。
//
//  ⚠️ 已知差异：Gson 的宽松模式细节很多（注释、单引号、未加引号的键值、NaN/Infinity、
//  多顶层值…），这里实现了书源实际会用到的子集并在 golden 里逐条对照；未覆盖的写成
//  README 差异表条目（附最小复现）。
//

import Foundation

/// Gson 的数字：LONG_OR_DOUBLE 策略（能放 Long 就 Long，否则 Double）。
public enum GsonNumber: Equatable {
    case long(Int64)
    case double(Double)

    public var doubleValue: Double {
        switch self {
        case .long(let v): return Double(v)
        case .double(let v): return v
        }
    }

    public var intValue: Int {
        switch self {
        case .long(let v): return Int(truncatingIfNeeded: v)
        case .double(let v):
            if v.isNaN || v.isInfinite { return 0 }
            if v > 2147483647.0 { return 2147483647 }
            if v < -2147483648.0 { return -2147483648 }
            return Int(v)
        }
    }

    public var longValue: Int64? {
        switch self {
        case .long(let v): return v
        case .double(let v):
            if v.isNaN || v.isInfinite { return nil }
            if v >= 9_223_372_036_854_775_808.0 || v < -9_223_372_036_854_775_808.0 { return nil }
            return Int64(v)
        }
    }

    /// Gson JsonPrimitive.getAsString()：数字按原始字面量文本输出。
    public var literal: String {
        switch self {
        case .long(let v): return String(v)
        case .double(let v): return GsonJSON.doubleLiteral(v)
        }
    }
}

/// Gson 的 JsonElement 子集。
indirect public enum GsonValue: Equatable {
    case object([(String, GsonValue)])
    case array([GsonValue])
    case string(String)
    case number(GsonNumber)
    case bool(Bool)
    case null

    public var isPrimitive: Bool {
        switch self {
        case .string, .number, .bool: return true
        default: return false
        }
    }

    public var isNumber: Bool {
        if case .number = self { return true }
        return false
    }

    public var isObject: Bool {
        if case .object = self { return true }
        return false
    }

    public var isArray: Bool {
        if case .array = self { return true }
        return false
    }

    /// Gson JsonElement.toString()：对象/数组输出紧凑 JSON 文本。
    public var jsonText: String {
        switch self {
        case .string(let s): return GsonJSON.quote(s)
        case .number(let n): return n.literal
        case .bool(let b): return b ? "true" : "false"
        case .null: return "null"
        case .array(let arr): return "[" + arr.map { $0.jsonText }.joined(separator: ",") + "]"
        case .object(let entries):
            return "{" + entries.map { GsonJSON.quote($0.0) + ":" + $0.1.jsonText }.joined(separator: ",") + "}"
        }
    }

    /// 对应 Kotlin `JsonPrimitive.asString`（仅对 primitive 有意义）。
    public var primitiveString: String? {
        switch self {
        case .string(let s): return s
        case .number(let n): return n.literal
        case .bool(let b): return b ? "true" : "false"
        default: return nil
        }
    }

    /// 对应 legado StringJsonDeserializer：primitive -> asString；null -> null；其它 -> 紧凑 JSON。
    public var stringFieldValue: String? {
        switch self {
        case .null: return nil
        case .string, .number, .bool: return primitiveString
        case .array, .object: return jsonText
        }
    }

    /// 手写 Equatable（对象分支是有序元组数组，Swift 不会自动合成）。
    public static func == (lhs: GsonValue, rhs: GsonValue) -> Bool {
        switch (lhs, rhs) {
        case (.null, .null): return true
        case (.bool(let a), .bool(let b)): return a == b
        case (.string(let a), .string(let b)): return a == b
        case (.number(let a), .number(let b)): return a == b
        case (.array(let a), .array(let b)):
            if a.count != b.count { return false }
            for (x, y) in zip(a, b) where x != y { return false }
            return true
        case (.object(let a), .object(let b)):
            if a.count != b.count { return false }
            for (x, y) in zip(a, b) where x.0 != y.0 || x.1 != y.1 { return false }
            return true
        default: return false
        }
    }

    /// 取对象成员（键重复时 Gson 的 LinkedTreeMap 是后者覆盖，这里以最后一次为准）。
    public func member(_ key: String) -> GsonValue? {
        guard case .object(let entries) = self else { return nil }
        var found: GsonValue?
        for (k, v) in entries where k == key { found = v }
        return found
    }
}

public enum GsonJSONError: Error, Equatable {
    case syntax(String)
    case unexpectedEnd
}

/// Gson 兼容的 JSON 解析器（严格/宽松两种模式）。
public enum GsonJSON {

    // MARK: - 入口

    /// 对应 `Gson.fromJson(...)` 的解析结果：失败返回 nil（Kotlin 侧是 Result.failure）。
    public static func parse(_ text: String, lenient: Bool) -> GsonValue? {
        var parser = Parser(text: text, lenient: lenient)
        do {
            let v = try parser.parseValue()
            parser.skipWhitespaceAndComments()
            if !parser.atEnd {
                // Gson 的 assertFullConsumption：有多余内容视为错误
                if lenient {
                    // 宽松模式下 Gson 允许顶层多值（取第一个），这里对齐「取第一个」
                    return v
                }
                return nil
            }
            return v
        } catch {
            return nil
        }
    }

    /// 对应 `GSON.fromJsonObject<T>(text)`：必须是 JSON 对象，否则失败。
    public static func parseObject(_ text: String, lenient: Bool) -> GsonValue? {
        guard let v = parse(text, lenient: lenient) else { return nil }
        guard v.isObject else { return nil }
        return v
    }

    // MARK: - 字面量输出（Gson 的 toJson 风格）

    /// Gson 序列化字符串：默认转义 " \ 和控制字符；legado 关掉了 html 转义（<>&= 原样）。
    static func quote(_ s: String) -> String {
        var out = "\""
        for scalar in s.unicodeScalars {
            switch scalar.value {
            case 0x22: out += "\\\""
            case 0x5C: out += "\\\\"
            case 0x08: out += "\\b"
            case 0x0C: out += "\\f"
            case 0x0A: out += "\\n"
            case 0x0D: out += "\\r"
            case 0x09: out += "\\t"
            case 0x00...0x1F: out += String(format: "\\u%04x", scalar.value)
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out + "\""
    }

    /// Gson 序列化 Double 的字面量：JsonWriter 用 Java 的 Double.toString
    /// （整数带 ".0"、大/小指数用 "1.0E21"/"1.0E-7" 形式），这里复用第 4 步的 JavaDoubleFormat。
    static func doubleLiteral(_ v: Double) -> String {
        if v.isNaN { return "NaN" }
        if v.isInfinite { return v > 0 ? "Infinity" : "-Infinity" }
        return JavaDoubleFormat.string(v)
    }

    // MARK: - 解析器

    private struct Parser {
        let units: [UInt16]
        var pos = 0
        var lenient: Bool
        var depth = 0

        init(text: String, lenient: Bool) {
            self.units = Array(text.utf16)
            self.lenient = lenient
        }

        var atEnd: Bool { pos >= units.count }

        mutating func skipWhitespaceAndComments() {
            while pos < units.count {
                let c = units[pos]
                if c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D {
                    pos += 1
                } else if lenient && c == 0x2F && pos + 1 < units.count && units[pos + 1] == 0x2F {
                    while pos < units.count && units[pos] != 0x0A { pos += 1 }
                } else if lenient && c == 0x2F && pos + 1 < units.count && units[pos + 1] == 0x2A {
                    pos += 2
                    while pos + 1 < units.count && !(units[pos] == 0x2A && units[pos + 1] == 0x2F) { pos += 1 }
                    if pos + 1 < units.count { pos += 2 }
                } else if !lenient && c == 0x2F {
                    // 严格模式不允许注释
                    return
                } else {
                    return
                }
            }
        }

        mutating func parseValue() throws -> GsonValue {
            skipWhitespaceAndComments()
            guard pos < units.count else { throw GsonJSONError.unexpectedEnd }
            let c = units[pos]
            switch c {
            case 0x7B: return try parseObjectBody()
            case 0x5B: return try parseArrayBody()
            case 0x22: return .string(try parseQuotedString(quote: 0x22))
            case 0x27 where lenient: return .string(try parseQuotedString(quote: 0x27))
            case 0x74, 0x66: return try parseKeyword()
            case 0x6E: return try parseKeyword()
            case 0x4E where lenient: return try parseKeyword() // NaN
            case 0x49 where lenient: return try parseKeyword() // Infinity
            default:
                // 数字字面量（严格模式也要接受）；宽松模式才把其余内容当未加引号的字符串
                let start = pos
                while pos < units.count {
                    let ch = units[pos]
                    if ch == 0x2C || ch == 0x5D || ch == 0x7D || ch == 0x3A || ch == 0x20
                        || ch == 0x09 || ch == 0x0A || ch == 0x0D { break }
                    pos += 1
                }
                guard pos > start else { throw GsonJSONError.syntax("unexpected value") }
                let raw = String(decoding: units[start..<pos], as: UTF16.self)
                if let num = GsonJSON.parseNumber(raw) { return .number(num) }
                pos = start
                if lenient { return try parseUnquoted() }
                throw GsonJSONError.syntax("unexpected value")
            }
        }

        mutating func parseKeyword() throws -> GsonValue {
            if matches("true") { pos += 4; return .bool(true) }
            if matches("false") { pos += 5; return .bool(false) }
            if matches("null") { pos += 4; return .null }
            if lenient {
                if matches("NaN") { pos += 3; return .number(.double(Double.nan)) }
                if matches("Infinity") { pos += 8; return .number(.double(Double.infinity)) }
                if matches("-Infinity") { pos += 9; return .number(.double(-Double.infinity)) }
            }
            throw GsonJSONError.syntax("bad keyword")
        }

        mutating func matches(_ s: String) -> Bool {
            let target = Array(s.utf16)
            guard pos + target.count <= units.count else { return false }
            for (i, t) in target.enumerated() where units[pos + i] != t { return false }
            return true
        }

        mutating func parseObjectBody() throws -> GsonValue {
            pos += 1 // {
            depth += 1
            defer { depth -= 1 }
            var entries: [(String, GsonValue)] = []
            skipWhitespaceAndComments()
            if pos < units.count && units[pos] == 0x7D { pos += 1; return .object(entries) }
            while true {
                skipWhitespaceAndComments()
                guard pos < units.count else { throw GsonJSONError.unexpectedEnd }
                let key: String
                if units[pos] == 0x22 {
                    key = try parseQuotedString(quote: 0x22)
                } else if lenient && units[pos] == 0x27 {
                    key = try parseQuotedString(quote: 0x27)
                } else if lenient {
                    key = try parseUnquotedString()
                } else {
                    throw GsonJSONError.syntax("unquoted key")
                }
                skipWhitespaceAndComments()
                guard pos < units.count && units[pos] == 0x3A else { throw GsonJSONError.syntax("missing colon") }
                pos += 1
                let value = try parseValue()
                // Gson 的 LinkedTreeMap：重复键后者覆盖（保持首次出现的位置）
                if let idx = entries.firstIndex(where: { $0.0 == key }) {
                    entries[idx].1 = value
                } else {
                    entries.append((key, value))
                }
                skipWhitespaceAndComments()
                guard pos < units.count else { throw GsonJSONError.unexpectedEnd }
                if units[pos] == 0x2C { pos += 1; continue }
                if units[pos] == 0x7D { pos += 1; break }
                throw GsonJSONError.syntax("bad object separator")
            }
            return .object(entries)
        }

        mutating func parseArrayBody() throws -> GsonValue {
            pos += 1 // [
            depth += 1
            defer { depth -= 1 }
            var arr: [GsonValue] = []
            skipWhitespaceAndComments()
            if pos < units.count && units[pos] == 0x5D { pos += 1; return .array(arr) }
            while true {
                arr.append(try parseValue())
                skipWhitespaceAndComments()
                guard pos < units.count else { throw GsonJSONError.unexpectedEnd }
                if units[pos] == 0x2C { pos += 1; continue }
                if units[pos] == 0x5D { pos += 1; break }
                throw GsonJSONError.syntax("bad array separator")
            }
            return .array(arr)
        }

        mutating func parseQuotedString(quote: UInt16) throws -> String {
            pos += 1
            var scalars = String.UnicodeScalarView()
            while pos < units.count {
                let c = units[pos]
                if c == quote { pos += 1; return String(scalars) }
                if c == 0x5C { // backslash
                    pos += 1
                    guard pos < units.count else { throw GsonJSONError.unexpectedEnd }
                    let e = units[pos]
                    pos += 1
                    switch e {
                    case 0x22: scalars.append("\"")
                    case 0x27: scalars.append("'")
                    case 0x5C: scalars.append("\\")
                    case 0x2F: scalars.append("/")
                    case 0x62: scalars.append("\u{08}")
                    case 0x66: scalars.append("\u{0C}")
                    case 0x6E: scalars.append("\n")
                    case 0x72: scalars.append("\r")
                    case 0x74: scalars.append("\t")
                    case 0x75:
                        var value: UInt32 = 0
                        for _ in 0..<4 {
                            guard pos < units.count, let d = GsonJSON.hexDigit(units[pos]) else {
                                throw GsonJSONError.syntax("bad \\u escape")
                            }
                            value = value << 4 | UInt32(d)
                            pos += 1
                        }
                        if let sc = UnicodeScalar(value) { scalars.append(sc) }
                    default:
                        throw GsonJSONError.syntax("bad escape")
                    }
                    continue
                }
                if let sc = UnicodeScalar(c) { scalars.append(sc) }
                pos += 1
            }
            throw GsonJSONError.unexpectedEnd
        }

        /// 宽松模式：未加引号的字符串/数字/关键字（Gson 里叫 unquoted value）。
        mutating func parseUnquoted() throws -> GsonValue {
            let start = pos
            while pos < units.count {
                let c = units[pos]
                if c == 0x2C || c == 0x5D || c == 0x7D || c == 0x3A || c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D {
                    break
                }
                pos += 1
            }
            guard pos > start else { throw GsonJSONError.syntax("empty unquoted value") }
            return GsonJSON.unquotedValue(String(decoding: units[start..<pos], as: UTF16.self))
        }

        mutating func parseUnquotedString() throws -> String {
            let v = try parseUnquoted()
            switch v {
            case .string(let s): return s
            case .number(let n): return n.literal
            case .bool(let b): return b ? "true" : "false"
            case .null: return "null"
            default: throw GsonJSONError.syntax("bad unquoted key")
            }
        }
    }

    static func hexDigit(_ c: UInt16) -> Int? {
        switch c {
        case 0x30...0x39: return Int(c - 0x30)
        case 0x41...0x46: return Int(c - 0x41 + 10)
        case 0x61...0x66: return Int(c - 0x61 + 10)
        default: return nil
        }
    }

    /// 宽松模式下未加引号的值：数字 / true / false / null / 字符串（Gson nextString 的行为）。
    static func unquotedValue(_ s: String) -> GsonValue {
        if s == "true" { return .bool(true) }
        if s == "false" { return .bool(false) }
        if s == "null" { return .null }
        if let num = parseNumber(s) { return .number(num) }
        return .string(s)
    }

    /// 按 Gson 的 LONG_OR_DOUBLE 策略把数字文本转成 GsonNumber。
    static func parseNumber(_ s: String) -> GsonNumber? {
        if s.isEmpty { return nil }
        let chars = Array(s.unicodeScalars)
        var i = 0
        if i < chars.count, chars[i] == "-" || chars[i] == "+" { i += 1 }
        var hasDigit = false
        var isIntegral = true
        while i < chars.count {
            let c = chars[i]
            if c.value >= 0x30 && c.value <= 0x39 {
                hasDigit = true
            } else if c.value == 0x2E || c.value == 0x65 || c.value == 0x45 { // . e E
                isIntegral = false
            } else if c.value == 0x2B || c.value == 0x2D { // + -
                // 指数符号，允许
            } else {
                return nil
            }
            i += 1
        }
        guard hasDigit else { return nil }
        if isIntegral, let l = Int64(s) { return .long(l) }
        guard let d = Double(s) else { return nil }
        return .double(d)
    }
}
