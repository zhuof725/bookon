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
//  容错策略（三种情况区分记录警告，均不抛错、wrappedValue 置 nil）：
//    - 值是字符串 -> 走二次 JSON 解析；内层解析失败记「(JSON 字符串)内层解析失败」；
//      二次解析复用外层同一个 DecodingWarningCollector，避免更深一层的警告丢失。
//    - 值是对象但解码失败 -> 记「规则字段是对象但解码失败：具体错误」（不用 try? 吞错误）。
//    - 值既不是对象也不是字符串（数字/数组/布尔）-> 记「既不是对象也不是字符串」。
//  警告通过 decoder.userInfo 里的 DecodingWarningCollector 收集，
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

        // 先判断值是不是「字符串」：字符串则走二次解析分支；否则再判断是不是对象。
        // 注意：这里用 decode(String.self) 判定，成功即为字符串形式。
        if let jsonString = try? container.decode(String.self) {
            self.decodeFromJSONString(jsonString, decoder: decoder)
            return
        }

        // 不是字符串。尝试作为对象（T）解码。
        // 关键：不要用 try? 吞掉错误——要区分「是对象但解码失败」与「压根不是对象」。
        // 先用一个无类型探针判断底层 JSON 到底是不是对象（{}）。
        let shape = (try? decoder.singleValueContainer().decode(JSONShapeProbe.self))?.kind

        if shape == .object {
            // 值确实是对象：正式解码 T，保留失败错误写进警告。
            do {
                self.wrappedValue = try container.decode(T.self)
            } catch {
                self.wrappedValue = nil
                StringOrObject.recordWarning(
                    decoder: decoder,
                    message: "规则字段是对象但解码失败：\((error as NSError).localizedDescription)",
                    rawSnippet: nil
                )
            }
            return
        }

        // 既不是对象也不是字符串（数字 / 数组 / 布尔）：保持原有警告。
        self.wrappedValue = nil
        StringOrObject.recordWarning(
            decoder: decoder,
            message: "规则字段既不是对象也不是字符串，已置空",
            rawSnippet: nil
        )
    }

    /// 处理「字符串形式」：对字符串内容做二次 JSON 解析。
    private mutating func decodeFromJSONString(_ jsonString: String, decoder: Decoder) {
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
        // 二次解析：若外层 decoder 带了警告收集器，内层也复用同一个 collector，
        // 这样内层更深一层（例如内层某个 StringOrObject）的警告不会丢失。
        let innerDecoder: JSONDecoder
        if let collector = decoder.userInfo[.decodingWarningCollector] as? DecodingWarningCollector {
            innerDecoder = LegadoJSON.decoder(collectingWarningsInto: collector)
        } else {
            innerDecoder = LegadoJSON.decoder
        }
        do {
            self.wrappedValue = try innerDecoder.decode(T.self, from: data)
        } catch {
            self.wrappedValue = nil
            StringOrObject.recordWarning(
                decoder: decoder,
                message: "规则字段(JSON 字符串)内层解析失败，已置空：\((error as NSError).localizedDescription)",
                rawSnippet: jsonString
            )
        }
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

/// 一个只用来「探测底层 JSON 值形状」的辅助解码类型。
/// 用于区分：值是对象({}) / 数组([]) / 标量(数字·布尔·字符串)。
/// 不承载任何数据，只判断结构。
private struct JSONShapeProbe: Decodable {
    enum Kind { case object, array, scalar }
    let kind: Kind

    init(from decoder: Decoder) throws {
        // JSONDecoder 语义：container(keyedBy:) 仅当值是 JSON 对象（含空对象 {}）时成功；
        // unkeyedContainer() 仅当值是数组时成功；其余为标量。
        if (try? decoder.container(keyedBy: AnyCodingKey.self)) != nil {
            self.kind = .object
        } else if (try? decoder.unkeyedContainer()) != nil {
            self.kind = .array
        } else {
            self.kind = .scalar
        }
    }

    /// 任意字符串键，用于建立 keyedContainer 探测对象结构。
    private struct AnyCodingKey: CodingKey {
        var stringValue: String
        var intValue: Int?
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { self.intValue = intValue; self.stringValue = String(intValue) }
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
