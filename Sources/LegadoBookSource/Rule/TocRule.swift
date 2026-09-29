//
//  TocRule.swift
//  LegadoBookSource
//
//  对应 Kotlin: data/entities/rule/TocRule.kt
//

import Foundation

/// 目录页规则
struct TocRule: Codable, Equatable {
    @LenientOptionalString var preUpdateJs: String?
    @LenientOptionalString var chapterList: String?
    @LenientOptionalString var chapterName: String?
    @LenientOptionalString var chapterUrl: String?
    @LenientOptionalString var formatJs: String?
    @LenientOptionalString var isVolume: String?
    @LenientOptionalString var isVip: String?
    @LenientOptionalString var isPay: String?
    @LenientOptionalString var updateTime: String?
    @LenientOptionalString var nextTocUrl: String?

    // Kotlin 全字段默认 null。
    init(
        preUpdateJs: String? = nil,
        chapterList: String? = nil,
        chapterName: String? = nil,
        chapterUrl: String? = nil,
        formatJs: String? = nil,
        isVolume: String? = nil,
        isVip: String? = nil,
        isPay: String? = nil,
        updateTime: String? = nil,
        nextTocUrl: String? = nil
    ) {
        self._preUpdateJs = LenientOptionalString(wrappedValue: preUpdateJs)
        self._chapterList = LenientOptionalString(wrappedValue: chapterList)
        self._chapterName = LenientOptionalString(wrappedValue: chapterName)
        self._chapterUrl = LenientOptionalString(wrappedValue: chapterUrl)
        self._formatJs = LenientOptionalString(wrappedValue: formatJs)
        self._isVolume = LenientOptionalString(wrappedValue: isVolume)
        self._isVip = LenientOptionalString(wrappedValue: isVip)
        self._isPay = LenientOptionalString(wrappedValue: isPay)
        self._updateTime = LenientOptionalString(wrappedValue: updateTime)
        self._nextTocUrl = LenientOptionalString(wrappedValue: nextTocUrl)
    }

    enum CodingKeys: String, CodingKey {
        case preUpdateJs
        case chapterList
        case chapterName
        case chapterUrl
        case formatJs
        case isVolume
        case isVip
        case isPay
        case updateTime
        case nextTocUrl
    }
}
