//
//  RowUi.swift
//  LegadoBookSource
//
//  对应 Kotlin: data/entities/rule/RowUi.kt
//
//  登录 UI 行定义。
//  注意：Kotlin 里 chars 为 Array<String?>?（元素可空），Swift 用 [String?]? 精确对应。
//

import Foundation

public struct RowUi: Codable, Equatable {
    public let name: String            // 默认 ""
    public let type: String            // 默认 "text"
    public let action: String?         // 默认 null
    public let chars: [String?]?       // 默认 null，元素可空
    public let `default`: String?      // 默认 null
    public var viewName: String?       // 默认 null
    public let style: FlexChildStyle?  // 默认 null

    public init(
        name: String = "",
        type: String = "text",
        action: String? = nil,
        chars: [String?]? = nil,
        default defaultValue: String? = nil,
        viewName: String? = nil,
        style: FlexChildStyle? = nil
    ) {
        self.name = name
        self.type = type
        self.action = action
        self.chars = chars
        self.default = defaultValue
        self.viewName = viewName
        self.style = style
    }

    public enum CodingKeys: String, CodingKey {
        case name
        case type
        case action
        case chars
        case `default`
        case viewName
        case style
    }

    // 缺字段用同样的默认值。
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        self.type = try c.decodeIfPresent(String.self, forKey: .type) ?? "text"
        self.action = try c.decodeIfPresent(String.self, forKey: .action)
        self.chars = try c.decodeIfPresent([String?].self, forKey: .chars)
        self.default = try c.decodeIfPresent(String.self, forKey: .default)
        self.viewName = try c.decodeIfPresent(String.self, forKey: .viewName)
        self.style = try c.decodeIfPresent(FlexChildStyle.self, forKey: .style)
    }

    /// 对应 Kotlin 的 fun style(): 空时返回 defaultStyle。
    public func styleOrDefault() -> FlexChildStyle {
        return style ?? FlexChildStyle.defaultStyle
    }

    /// 对应 Kotlin 内嵌的 object Type。
    public enum `Type` {
        public static let text = "text"
        public static let password = "password"
        public static let button = "button"
        public static let toggle = "toggle"
        public static let select = "select"
    }

    // 对应 Kotlin 自定义 equals：仅比较 name/type/action/default。
    public static func == (lhs: RowUi, rhs: RowUi) -> Bool {
        return lhs.name == rhs.name
            && lhs.type == rhs.type
            && lhs.action == rhs.action
            && lhs.default == rhs.default
    }
}
