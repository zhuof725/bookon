//
//  BookInfoRule.swift
//  LegadoBookSource
//
//  对应 Kotlin: data/entities/rule/BookInfoRule.kt
//

import Foundation

/// 书籍详情页规则
struct BookInfoRule: Codable, Equatable {
    @LenientOptionalString var `init`: String?
    @LenientOptionalString var name: String?
    @LenientOptionalString var author: String?
    @LenientOptionalString var intro: String?
    @LenientOptionalString var kind: String?
    @LenientOptionalString var lastChapter: String?
    @LenientOptionalString var updateTime: String?
    @LenientOptionalString var coverUrl: String?
    @LenientOptionalString var tocUrl: String?
    @LenientOptionalString var wordCount: String?
    @LenientOptionalString var canReName: String?
    @LenientOptionalString var downloadUrls: String?

    // Kotlin 全字段默认 null。
    init(
        init initValue: String? = nil,
        name: String? = nil,
        author: String? = nil,
        intro: String? = nil,
        kind: String? = nil,
        lastChapter: String? = nil,
        updateTime: String? = nil,
        coverUrl: String? = nil,
        tocUrl: String? = nil,
        wordCount: String? = nil,
        canReName: String? = nil,
        downloadUrls: String? = nil
    ) {
        self._init = LenientOptionalString(wrappedValue: initValue)
        self._name = LenientOptionalString(wrappedValue: name)
        self._author = LenientOptionalString(wrappedValue: author)
        self._intro = LenientOptionalString(wrappedValue: intro)
        self._kind = LenientOptionalString(wrappedValue: kind)
        self._lastChapter = LenientOptionalString(wrappedValue: lastChapter)
        self._updateTime = LenientOptionalString(wrappedValue: updateTime)
        self._coverUrl = LenientOptionalString(wrappedValue: coverUrl)
        self._tocUrl = LenientOptionalString(wrappedValue: tocUrl)
        self._wordCount = LenientOptionalString(wrappedValue: wordCount)
        self._canReName = LenientOptionalString(wrappedValue: canReName)
        self._downloadUrls = LenientOptionalString(wrappedValue: downloadUrls)
    }

    enum CodingKeys: String, CodingKey {
        case `init`
        case name
        case author
        case intro
        case kind
        case lastChapter
        case updateTime
        case coverUrl
        case tocUrl
        case wordCount
        case canReName
        case downloadUrls
    }
}
