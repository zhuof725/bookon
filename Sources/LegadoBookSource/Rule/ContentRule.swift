//
//  ContentRule.swift
//  LegadoBookSource
//
//  对应 Kotlin: data/entities/rule/ContentRule.kt
//

import Foundation

/// 正文处理规则
public struct ContentRule: Codable, Equatable {
    @LenientOptionalString public var content: String?
    /// 副文规则，拼接在正文后面或者获取歌词等
    @LenientOptionalString public var subContent: String?
    /// 有些网站只能在正文中获取标题
    @LenientOptionalString public var title: String?
    @LenientOptionalString public var nextContentUrl: String?
    @LenientOptionalString public var webJs: String?
    @LenientOptionalString public var sourceRegex: String?
    /// 替换规则
    @LenientOptionalString public var replaceRegex: String?
    /// 默认大小居中,FULL最大宽度
    @LenientOptionalString public var imageStyle: String?
    /// 图片bytes二次解密js, 返回解密后的bytes
    @LenientOptionalString public var imageDecode: String?
    /// 购买操作,js或者包含{{js}}的url
    @LenientOptionalString public var payAction: String?
    /// 监听到事件后执行的回调js代码
    @LenientOptionalString public var callBackJs: String?

    // Kotlin 全字段默认 null。
    public init(
        content: String? = nil,
        subContent: String? = nil,
        title: String? = nil,
        nextContentUrl: String? = nil,
        webJs: String? = nil,
        sourceRegex: String? = nil,
        replaceRegex: String? = nil,
        imageStyle: String? = nil,
        imageDecode: String? = nil,
        payAction: String? = nil,
        callBackJs: String? = nil
    ) {
        self._content = LenientOptionalString(wrappedValue: content)
        self._subContent = LenientOptionalString(wrappedValue: subContent)
        self._title = LenientOptionalString(wrappedValue: title)
        self._nextContentUrl = LenientOptionalString(wrappedValue: nextContentUrl)
        self._webJs = LenientOptionalString(wrappedValue: webJs)
        self._sourceRegex = LenientOptionalString(wrappedValue: sourceRegex)
        self._replaceRegex = LenientOptionalString(wrappedValue: replaceRegex)
        self._imageStyle = LenientOptionalString(wrappedValue: imageStyle)
        self._imageDecode = LenientOptionalString(wrappedValue: imageDecode)
        self._payAction = LenientOptionalString(wrappedValue: payAction)
        self._callBackJs = LenientOptionalString(wrappedValue: callBackJs)
    }

    public enum CodingKeys: String, CodingKey {
        case content
        case subContent
        case title
        case nextContentUrl
        case webJs
        case sourceRegex
        case replaceRegex
        case imageStyle
        case imageDecode
        case payAction
        case callBackJs
    }
}
