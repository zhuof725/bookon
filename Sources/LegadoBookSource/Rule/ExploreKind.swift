//
//  ExploreKind.swift
//  LegadoBookSource
//
//  对应 Kotlin: data/entities/rule/ExploreKind.kt
//
//  发现分类。
//  注意：Kotlin 里 chars 为 Array<String?>?（元素可空），Swift 用 [String?]? 精确对应。
//  Type 内嵌常量对象移植为 Swift 枚举命名空间。
//

import Foundation

/// 发现分类
struct ExploreKind: Codable, Equatable {
    let title: String           // 默认 ""
    let url: String?            // 默认 null
    let type: String            // 默认 "url"
    let action: String?         // 默认 null
    let chars: [String?]?       // 默认 null，元素可空
    let `default`: String?      // 默认 null
    var viewName: String?       // 默认 null
    let style: FlexChildStyle?  // 默认 null

    init(
        title: String = "",
        url: String? = nil,
        type: String = "url",
        action: String? = nil,
        chars: [String?]? = nil,
        default defaultValue: String? = nil,
        viewName: String? = nil,
        style: FlexChildStyle? = nil
    ) {
        self.title = title
        self.url = url
        self.type = type
        self.action = action
        self.chars = chars
        self.default = defaultValue
        self.viewName = viewName
        self.style = style
    }

    enum CodingKeys: String, CodingKey {
        case title
        case url
        case type
        case action
        case chars
        case `default`
        case viewName
        case style
    }

    // 缺字段用同样的默认值。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        self.url = try c.decodeIfPresent(String.self, forKey: .url)
        self.type = try c.decodeIfPresent(String.self, forKey: .type) ?? "url"
        self.action = try c.decodeIfPresent(String.self, forKey: .action)
        self.chars = try c.decodeIfPresent([String?].self, forKey: .chars)
        self.default = try c.decodeIfPresent(String.self, forKey: .default)
        self.viewName = try c.decodeIfPresent(String.self, forKey: .viewName)
        self.style = try c.decodeIfPresent(FlexChildStyle.self, forKey: .style)
    }

    /// 对应 Kotlin 的 fun style(): 空时返回 defaultStyle。
    func styleOrDefault() -> FlexChildStyle {
        return style ?? FlexChildStyle.defaultStyle
    }

    /// 对应 Kotlin 内嵌的 object Type。
    enum `Type` {
        static let url = "url"
        static let text = "text"
        static let button = "button"
        static let toggle = "toggle"
        static let select = "select"
    }

    // 对应 Kotlin 自定义 equals：仅比较 title/type/url/action/default。
    static func == (lhs: ExploreKind, rhs: ExploreKind) -> Bool {
        return lhs.title == rhs.title
            && lhs.type == rhs.type
            && lhs.url == rhs.url
            && lhs.action == rhs.action
            && lhs.default == rhs.default
    }
}
