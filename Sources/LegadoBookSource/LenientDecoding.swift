//
//  LenientDecoding.swift
//  LegadoBookSource
//
//  宽松解码基础设施。
//
//  书源 JSON 在野外并不严格：同一字段的类型可能不统一——
//  数字被写成字符串、布尔被写成 0/1、字符串被写成数字等。
//  这里提供一组 property wrapper 与辅助类型，用来「尽力而为」地
//  把这些不规范的值解码成期望的 Swift 类型，覆盖 Int / Int64 / Bool / String。
//
//  设计对应 Kotlin 侧 GsonExtensions.kt 中的
//  StringJsonDeserializer / IntJsonDeserializer / MapDeserializerDoubleAsIntFix
//  以及 GSON 的宽松反序列化行为。
//

import Foundation

// MARK: - 宽松标量解码器

/// 一组静态方法，把任意 JSON 标量（字符串 / 数字 / 布尔）宽松地转换为目标类型。
/// 解析失败时返回 nil，交由上层决定是否使用默认值。
public enum LenientScalar {

    /// 宽松解码 Int：接受 Int、Double(取整)、Bool(true=1/false=0)、可解析的字符串。
    public static func int(from container: SingleValueDecodingContainer) -> Int? {
        if let v = try? container.decode(Int.self) { return v }
        if let v = try? container.decode(Int64.self) { return Int(exactly: v) ?? Int(truncatingIfNeeded: v) }
        if let v = try? container.decode(Double.self) { return Int(v) }
        if let v = try? container.decode(Bool.self) { return v ? 1 : 0 }
        if let s = try? container.decode(String.self) { return parseInt(from: s) }
        return nil
    }

    /// 宽松解码 Int64。
    public static func int64(from container: SingleValueDecodingContainer) -> Int64? {
        if let v = try? container.decode(Int64.self) { return v }
        if let v = try? container.decode(Int.self) { return Int64(v) }
        if let v = try? container.decode(Double.self) { return Int64(v) }
        if let v = try? container.decode(Bool.self) { return v ? 1 : 0 }
        if let s = try? container.decode(String.self) { return parseInt64(from: s) }
        return nil
    }

    /// 宽松解码 Bool：接受 Bool、数字(0=false 非0=true)、"true"/"false"/"1"/"0"/"yes"/"no" 等字符串。
    public static func bool(from container: SingleValueDecodingContainer) -> Bool? {
        if let v = try? container.decode(Bool.self) { return v }
        if let v = try? container.decode(Int.self) { return v != 0 }
        if let v = try? container.decode(Int64.self) { return v != 0 }
        if let v = try? container.decode(Double.self) { return v != 0 }
        if let s = try? container.decode(String.self) { return parseBool(from: s) }
        return nil
    }

    /// 宽松解码 String：接受 String、数字(转字符串)、布尔(转字符串)。
    /// 对应 Kotlin StringJsonDeserializer：primitive 直接 asString，其余 toString。
    public static func string(from container: SingleValueDecodingContainer) -> String? {
        if let v = try? container.decode(String.self) { return v }
        if let v = try? container.decode(Bool.self) { return v ? "true" : "false" }
        if let v = try? container.decode(Int64.self) { return String(v) }
        if let v = try? container.decode(Int.self) { return String(v) }
        if let v = try? container.decode(Double.self) {
            // 尽量避免把整数写成 "3.0"：与 Gson LONG_OR_DOUBLE 策略一致，
            // 若为整数值则输出为整数形式。
            if v == v.rounded() && abs(v) < 9.007e15 {
                return String(Int64(v))
            }
            return String(v)
        }
        return nil
    }

    // MARK: 字符串解析辅助

    public static func parseInt(from s: String) -> Int? {
        let t = s.trimmingCharacters(in: .whitespaces)
        if let v = Int(t) { return v }
        if let d = Double(t) { return Int(d) }
        return nil
    }

    public static func parseInt64(from s: String) -> Int64? {
        let t = s.trimmingCharacters(in: .whitespaces)
        if let v = Int64(t) { return v }
        if let d = Double(t) { return Int64(d) }
        return nil
    }

    public static func parseBool(from s: String) -> Bool? {
        switch s.trimmingCharacters(in: .whitespaces).lowercased() {
        case "true", "1", "yes", "y", "on": return true
        case "false", "0", "no", "n", "off", "": return false
        default:
            // 尝试当作数字：非 0 即 true
            if let d = Double(s) { return d != 0 }
            return nil
        }
    }
}

// MARK: - Property Wrapper：带默认值的宽松标量

/// 提供默认值的类型需实现该协议。
public protocol DefaultValueProvider {
    associatedtype Value
    static var defaultValue: Value { get }
}

// 常用默认值定义。字段缺失或类型不可解析时使用。
public enum Defaults {
    public enum FalseBool: DefaultValueProvider { public static let defaultValue = false }
    public enum TrueBool: DefaultValueProvider { public static let defaultValue = true }
    public enum ZeroInt: DefaultValueProvider { public static let defaultValue = 0 }
    public enum ZeroInt64: DefaultValueProvider { public static let defaultValue = Int64(0) }
    public enum EmptyString: DefaultValueProvider { public static let defaultValue = "" }
}

/// 宽松解码的 Int，带默认值。JSON 缺字段或类型不符时回退到默认值，绝不抛错。
@propertyWrapper
public struct LenientInt<D: DefaultValueProvider>: Codable, Equatable, Hashable where D.Value == Int {
    public var wrappedValue: Int

    public init(wrappedValue: Int) { self.wrappedValue = wrappedValue }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.wrappedValue = LenientScalar.int(from: container) ?? D.defaultValue
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue)
    }

    // phantom 泛型 D 不参与判等，仅比较 wrappedValue。
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.wrappedValue == rhs.wrappedValue }
    public func hash(into hasher: inout Hasher) { hasher.combine(wrappedValue) }
}

/// 宽松解码的 Int64，带默认值。
@propertyWrapper
public struct LenientInt64<D: DefaultValueProvider>: Codable, Equatable, Hashable where D.Value == Int64 {
    public var wrappedValue: Int64

    public init(wrappedValue: Int64) { self.wrappedValue = wrappedValue }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.wrappedValue = LenientScalar.int64(from: container) ?? D.defaultValue
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.wrappedValue == rhs.wrappedValue }
    public func hash(into hasher: inout Hasher) { hasher.combine(wrappedValue) }
}

/// 宽松解码的 Bool，带默认值。
@propertyWrapper
public struct LenientBool<D: DefaultValueProvider>: Codable, Equatable, Hashable where D.Value == Bool {
    public var wrappedValue: Bool

    public init(wrappedValue: Bool) { self.wrappedValue = wrappedValue }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.wrappedValue = LenientScalar.bool(from: container) ?? D.defaultValue
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.wrappedValue == rhs.wrappedValue }
    public func hash(into hasher: inout Hasher) { hasher.combine(wrappedValue) }
}

/// 宽松解码的 String，带默认值。
@propertyWrapper
public struct LenientString<D: DefaultValueProvider>: Codable, Equatable, Hashable where D.Value == String {
    public var wrappedValue: String

    public init(wrappedValue: String) { self.wrappedValue = wrappedValue }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.wrappedValue = LenientScalar.string(from: container) ?? D.defaultValue
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(wrappedValue)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.wrappedValue == rhs.wrappedValue }
    public func hash(into hasher: inout Hasher) { hasher.combine(wrappedValue) }
}

// MARK: - Property Wrapper：可空的宽松标量

/// 宽松解码的可空 Int?。字段缺失或 null 时为 nil；类型不符时尽力转换，无法转换则 nil。
@propertyWrapper
public struct LenientOptionalInt: Codable, Equatable, Hashable {
    public var wrappedValue: Int?

    public init(wrappedValue: Int?) { self.wrappedValue = wrappedValue }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self.wrappedValue = nil; return }
        self.wrappedValue = LenientScalar.int(from: container)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let v = wrappedValue { try container.encode(v) } else { try container.encodeNil() }
    }
}

/// 宽松解码的可空 Bool?。
@propertyWrapper
public struct LenientOptionalBool: Codable, Equatable, Hashable {
    public var wrappedValue: Bool?

    public init(wrappedValue: Bool?) { self.wrappedValue = wrappedValue }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self.wrappedValue = nil; return }
        self.wrappedValue = LenientScalar.bool(from: container)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let v = wrappedValue { try container.encode(v) } else { try container.encodeNil() }
    }
}

/// 宽松解码的可空 String?。对应 Kotlin 里大量 `var x: String? = null` 字段。
@propertyWrapper
public struct LenientOptionalString: Codable, Equatable, Hashable {
    public var wrappedValue: String?

    public init(wrappedValue: String?) { self.wrappedValue = wrappedValue }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self.wrappedValue = nil; return }
        self.wrappedValue = LenientScalar.string(from: container)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let v = wrappedValue { try container.encode(v) } else { try container.encodeNil() }
    }
}

/// 宽松解码的可空 Int64?。
@propertyWrapper
public struct LenientOptionalInt64: Codable, Equatable, Hashable {
    public var wrappedValue: Int64?

    public init(wrappedValue: Int64?) { self.wrappedValue = wrappedValue }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self.wrappedValue = nil; return }
        self.wrappedValue = LenientScalar.int64(from: container)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let v = wrappedValue { try container.encode(v) } else { try container.encodeNil() }
    }
}

// MARK: - KeyedDecodingContainer 扩展：让 property wrapper 支持「字段缺失」

// Swift 的 property wrapper 在字段缺失时默认会抛 keyNotFound，
// 除非为 wrapper 类型提供 decodeIfPresent 的重载。
// 下面为所有 Lenient wrapper 提供该重载：字段缺失时使用 wrapper 内定义的默认值 / nil。

extension KeyedDecodingContainer {

    func decode<D>(_ type: LenientInt<D>.Type, forKey key: Key) throws -> LenientInt<D> {
        try decodeIfPresent(type, forKey: key) ?? LenientInt<D>(wrappedValue: D.defaultValue)
    }

    func decode<D>(_ type: LenientInt64<D>.Type, forKey key: Key) throws -> LenientInt64<D> {
        try decodeIfPresent(type, forKey: key) ?? LenientInt64<D>(wrappedValue: D.defaultValue)
    }

    func decode<D>(_ type: LenientBool<D>.Type, forKey key: Key) throws -> LenientBool<D> {
        try decodeIfPresent(type, forKey: key) ?? LenientBool<D>(wrappedValue: D.defaultValue)
    }

    func decode<D>(_ type: LenientString<D>.Type, forKey key: Key) throws -> LenientString<D> {
        try decodeIfPresent(type, forKey: key) ?? LenientString<D>(wrappedValue: D.defaultValue)
    }

    func decode(_ type: LenientOptionalInt.Type, forKey key: Key) throws -> LenientOptionalInt {
        try decodeIfPresent(type, forKey: key) ?? LenientOptionalInt(wrappedValue: nil)
    }

    func decode(_ type: LenientOptionalInt64.Type, forKey key: Key) throws -> LenientOptionalInt64 {
        try decodeIfPresent(type, forKey: key) ?? LenientOptionalInt64(wrappedValue: nil)
    }

    func decode(_ type: LenientOptionalBool.Type, forKey key: Key) throws -> LenientOptionalBool {
        try decodeIfPresent(type, forKey: key) ?? LenientOptionalBool(wrappedValue: nil)
    }

    func decode(_ type: LenientOptionalString.Type, forKey key: Key) throws -> LenientOptionalString {
        try decodeIfPresent(type, forKey: key) ?? LenientOptionalString(wrappedValue: nil)
    }
}
