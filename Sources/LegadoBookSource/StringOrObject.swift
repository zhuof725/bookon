//
//  StringOrObject.swift
//  LegadoBookSource
//
//  处理「既可能是对象，也可能是 JSON 字符串」的字段。
//
//  在 BookSource 的 ruleSearch / ruleExplore / ruleBookInfo / ruleToc /
//  ruleContent / ruleReview 字段上，JSON 里有两种写法：
//    1. 直接是对象：  "ruleSearch": { "name": "...", ... }
//    2. 是 JSON 字符串（字符串里再嵌套一层 JSON）：
//                     "ruleSearch": "{\n  \"name\": \"...\" }"
//  这两种都要能解码。对应 Kotlin 侧各 Rule 的 companion object 里的
//  jsonDeserializer：json.isJsonObject -> 直接解析；
//  json.isJsonPrimitive -> 把字符串再当作 JSON 解析。
//
//  编码时统一输出为「对象」形式（与 Kotlin Converters 里
//  xxxRuleToString(GSON.toJson(rule)) 存库、但对外导出 JSON 时为对象一致，
//  且导入现有书源 JSON 后再导出的规范形式为对象）。
//
//  容错策略：当内层 JSON 字符串解析失败时，不抛错，wrappedValue 置 nil，
//  同时通过 decoder.userInfo 里的 DecodingWarningCollector 记录一条可读警告，
//  最终汇总进 BookSourceImportResult.warnings。
//

import Foundation

/// 解码过程中产生的一条警告（非致命，解码仍继续）。
public struct DecodingWarning: Equatable {
    /// 相关字段名（尽力而为，可能为空）。
    public let field: String?
    /// 警告信息。
    public let message: String
    /// 触发警告的原始文本片段（截断以防过长）。
    public let rawSnippet: String?

    public init(field: String?, message: String, rawSnippet: String?) {
        self.field = field
        self.message = message
        self.rawSnippet = rawSnippet
    }
}

/// 线程内使用的警告收集器（引用类型，便于在 Codable 解码链中传递并累积）。
public final class DecodingWarningCollector {
    public private(set) var warnings: [DecodingWarning] = []

    public init() {}

    public func append(_ warning: DecodingWarning) {
        warnings.append(warning)
    }

    public func drain() -> [DecodingWarning] {
        let w = warnings
        warnings = []
        return w
    }
}

public extension CodingUserInfoKey {
    /// 在 decoder.userInfo 中传递 DecodingWarningCollector 的键。
    static let decodingWarningCollector =
        CodingUserInfoKey(rawValue: "io.legado.decodingWarningCollector")!
}

/// 包装一个「可能以对象或 JSON 字符串两种形式出现」的可选值。
/// - 解码：先尝试按对象解，失败再把它当字符串、对字符串内容做二次 JSON 解码。
/// - 编码：始终以对象形式输出（若为 nil 则输出 null）。
@propertyWrapper
public struct StringOrObject<T: Codable>: Codable {
    public var wrappedValue: T?

    public init(wrappedValue: T?) { self.wrappedValue = wrappedValue }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        // 显式 null
        if container.decodeNil() {
            self.wrappedValue = nil
            return
        }

        // 情况 1：直接是对象
        if let obj = try? container.decode(T.self) {
            self.wrappedValue = obj
            return
        }

        // 情况 2：是 JSON 字符串，需要二次解析
        if let jsonString = try? container.decode(String.self) {
            let trimmed = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                // 空字符串视为「无规则」，不算错误，也不记警告。
                self.wrappedValue = nil
                return
            }
            guard let data = jsonString.data(using: .utf8) else {
                self.wrappedValue = nil
                StringOrObject.recordWarning(
                    decoder: decoder,
                    message: "规则字段是字符串但无法转为 UTF-8 数据，已置空",
                    rawSnippet: jsonString
                )
                return
            }
            // 用宽松解码器解析内层 JSON；失败不抛错，置 nil 并记录警告。
            do {
                let inner = try LegadoJSON.decoder.decode(T.self, from: data)
                self.wrappedValue = inner
            } catch {
                self.wrappedValue = nil
                StringOrObject.recordWarning(
                    decoder: decoder,
                    message: "规则字段(JSON 字符串)内层解析失败，已置空：\((error as NSError).localizedDescription)",
                    rawSnippet: jsonString
                )
            }
            return
        }

        // 两种都不是：容错为 nil，并记录警告（书源 JSON 极不规范时不应整体失败）。
        self.wrappedValue = nil
        StringOrObject.recordWarning(
            decoder: decoder,
            message: "规则字段既不是对象也不是字符串，已置空",
            rawSnippet: nil
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let v = wrappedValue {
            try container.encode(v)   // 统一输出为对象
        } else {
            try container.encodeNil()
        }
    }

    /// 从 decoder.userInfo 取出收集器并记录一条警告（若无收集器则忽略）。
    private static func recordWarning(decoder: Decoder, message: String, rawSnippet: String?) {
        guard let collector = decoder.userInfo[.decodingWarningCollector] as? DecodingWarningCollector else {
            return
        }
        // 字段名：取当前 codingPath 最后一段。
        let field = decoder.codingPath.last?.stringValue
        let snippet = rawSnippet.map { String($0.prefix(200)) }
        collector.append(DecodingWarning(field: field, message: message, rawSnippet: snippet))
    }
}

// 字段缺失时的重载：视为 nil，而不是抛 keyNotFound。
extension KeyedDecodingContainer {
    func decode<T>(_ type: StringOrObject<T>.Type, forKey key: Key) throws -> StringOrObject<T> {
        try decodeIfPresent(type, forKey: key) ?? StringOrObject<T>(wrappedValue: nil)
    }
}

// 当内层类型可判等时，StringOrObject 亦可判等（比较解出的值）。
extension StringOrObject: Equatable where T: Equatable {
    public static func == (lhs: StringOrObject<T>, rhs: StringOrObject<T>) -> Bool {
        lhs.wrappedValue == rhs.wrappedValue
    }
}
