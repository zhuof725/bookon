//
//  FlexChildStyle.swift
//  LegadoBookSource
//
//  对应 Kotlin: data/entities/rule/FlexChildStyle.kt
//
//  注意：Kotlin 原类含 Android UI 相关方法（alignSelf()/apply(view:View)）以及
//  FlexboxLayout 依赖，这些属于 UI 层，本步骤（仅数据模型）不移植。
//  这里只保留可 Codable 的数据字段与其默认值（用 decodeIfPresent 加同样的默认值）。
//
//  Kotlin 里 layout_flexGrow / layout_flexShrink / layout_flexBasisPercent 为 Float，
//  这里保持 Float（Double 会改变精度语义，故不改）。
//

import Foundation

struct FlexChildStyle: Codable, Equatable {
    var layout_flexGrow: Float          // 默认 0F
    var layout_flexShrink: Float        // 默认 1F
    var layout_alignSelf: String        // 默认 "auto"
    var layout_flexBasisPercent: Float  // 默认 -1F
    var layout_wrapBefore: Bool         // 默认 false
    /// 自定义的内部水平对齐属性
    var layout_justifySelf: String      // 默认 "auto"

    init(
        layout_flexGrow: Float = 0,
        layout_flexShrink: Float = 1,
        layout_alignSelf: String = "auto",
        layout_flexBasisPercent: Float = -1,
        layout_wrapBefore: Bool = false,
        layout_justifySelf: String = "auto"
    ) {
        self.layout_flexGrow = layout_flexGrow
        self.layout_flexShrink = layout_flexShrink
        self.layout_alignSelf = layout_alignSelf
        self.layout_flexBasisPercent = layout_flexBasisPercent
        self.layout_wrapBefore = layout_wrapBefore
        self.layout_justifySelf = layout_justifySelf
    }

    enum CodingKeys: String, CodingKey {
        case layout_flexGrow
        case layout_flexShrink
        case layout_alignSelf
        case layout_flexBasisPercent
        case layout_wrapBefore
        case layout_justifySelf
    }

    // 缺字段用同样的默认值，JSON 缺字段不报错。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.layout_flexGrow = try c.decodeIfPresent(Float.self, forKey: .layout_flexGrow) ?? 0
        self.layout_flexShrink = try c.decodeIfPresent(Float.self, forKey: .layout_flexShrink) ?? 1
        self.layout_alignSelf = try c.decodeIfPresent(String.self, forKey: .layout_alignSelf) ?? "auto"
        self.layout_flexBasisPercent = try c.decodeIfPresent(Float.self, forKey: .layout_flexBasisPercent) ?? -1
        self.layout_wrapBefore = try c.decodeIfPresent(Bool.self, forKey: .layout_wrapBefore) ?? false
        self.layout_justifySelf = try c.decodeIfPresent(String.self, forKey: .layout_justifySelf) ?? "auto"
    }

    /// 对应 Kotlin companion object 里的 defaultStyle。
    static let defaultStyle = FlexChildStyle()
}
