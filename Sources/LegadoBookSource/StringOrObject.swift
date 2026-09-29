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

import Foundation

/// 包装一个「可能以对象或 JSON 字符串两种形式出现」的可选值。
/// - 解码：先尝试按对象解，失败再把它当字符串、对字符串内容做二次 JSON 解码。
/// - 编码：始终以对象形式输出（若为 nil 则输出 null）。
@propertyWrapper
struct StringOrObject<T: Codable>: Codable {
    var wrappedValue: T?

    init(wrappedValue: T?) { self.wrappedValue = wrappedValue }

    init(from decoder: Decoder) throws {
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
                self.wrappedValue = nil
                return
            }
            guard let data = jsonString.data(using: .utf8) else {
                self.wrappedValue = nil
                return
            }
            // 用宽松解码器解析内层 JSON
            let inner = try LegadoJSON.decoder.decode(T.self, from: data)
            self.wrappedValue = inner
            return
        }

        // 两种都不是：容错为 nil（书源 JSON 极不规范时不应整体失败）
        self.wrappedValue = nil
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let v = wrappedValue {
            try container.encode(v)   // 统一输出为对象
        } else {
            try container.encodeNil()
        }
    }
}

// 当内层类型可判等时，StringOrObject 亦可判等（比较解出的值）。
extension StringOrObject: Equatable where T: Equatable {
    static func == (lhs: StringOrObject<T>, rhs: StringOrObject<T>) -> Bool {
        lhs.wrappedValue == rhs.wrappedValue
    }
}

// 字段缺失时的重载：视为 nil，而不是抛 keyNotFound。
extension KeyedDecodingContainer {
    func decode<T>(_ type: StringOrObject<T>.Type, forKey key: Key) throws -> StringOrObject<T> {
        try decodeIfPresent(type, forKey: key) ?? StringOrObject<T>(wrappedValue: nil)
    }
}
