//
//  ExploreRule.swift
//  LegadoBookSource
//
//  对应 Kotlin: data/entities/rule/ExploreRule.kt
//

import Foundation

/// 发现结果规则
struct ExploreRule: Codable, Equatable, BookListRule {
    @LenientOptionalString var bookList: String?
    @LenientOptionalString var name: String?
    @LenientOptionalString var author: String?
    @LenientOptionalString var intro: String?
    @LenientOptionalString var kind: String?
    @LenientOptionalString var lastChapter: String?
    @LenientOptionalString var updateTime: String?
    @LenientOptionalString var bookUrl: String?
    @LenientOptionalString var coverUrl: String?
    @LenientOptionalString var wordCount: String?

    // Kotlin 全字段默认 null。
    init(
        bookList: String? = nil,
        name: String? = nil,
        author: String? = nil,
        intro: String? = nil,
        kind: String? = nil,
        lastChapter: String? = nil,
        updateTime: String? = nil,
        bookUrl: String? = nil,
        coverUrl: String? = nil,
        wordCount: String? = nil
    ) {
        self._bookList = LenientOptionalString(wrappedValue: bookList)
        self._name = LenientOptionalString(wrappedValue: name)
        self._author = LenientOptionalString(wrappedValue: author)
        self._intro = LenientOptionalString(wrappedValue: intro)
        self._kind = LenientOptionalString(wrappedValue: kind)
        self._lastChapter = LenientOptionalString(wrappedValue: lastChapter)
        self._updateTime = LenientOptionalString(wrappedValue: updateTime)
        self._bookUrl = LenientOptionalString(wrappedValue: bookUrl)
        self._coverUrl = LenientOptionalString(wrappedValue: coverUrl)
        self._wordCount = LenientOptionalString(wrappedValue: wordCount)
    }

    enum CodingKeys: String, CodingKey {
        case bookList
        case name
        case author
        case intro
        case kind
        case lastChapter
        case updateTime
        case bookUrl
        case coverUrl
        case wordCount
    }
}
