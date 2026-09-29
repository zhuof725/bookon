//
//  LegadoJSON.swift
//  LegadoBookSource
//
//  统一的 JSONEncoder / JSONDecoder 配置。
//  对应 Kotlin 侧的 GSON 实例（disableHtmlEscaping + prettyPrinting）。
//

import Foundation

enum LegadoJSON {

    /// 共享解码器。字段顺序、宽松解码逻辑都在各 property wrapper 内处理。
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()

    /// 共享编码器。
    /// - 不做 key 转换（字段名与 JSON key 保持一致，不转 snake_case）。
    /// - 保留斜杠不转义（对应 Gson disableHtmlEscaping）。
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.withoutEscapingSlashes]
        return e
    }()

    /// 供人类阅读的美化编码器（对应 Gson setPrettyPrinting）。
    static let prettyEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        return e
    }()
}
