//
//  SearchRule.swift
//  LegadoBookSource
//
//  对应 Kotlin: data/entities/rule/SearchRule.kt
//

import Foundation

/// 搜索结果处理规则
public struct SearchRule: Codable, Equatable, BookListRule {
    /// 校验关键字
    @LenientOptionalString public var checkKeyWord: String?
    @LenientOptionalString public var bookList: String?
    @LenientOptionalString public var name: String?
    @LenientOptionalString public var author: String?
    @LenientOptionalString public var intro: String?
    @LenientOptionalString public var kind: String?
    @LenientOptionalString public var lastChapter: String?
    @LenientOptionalString public var updateTime: String?
    @LenientOptionalString public var bookUrl: String?
    @LenientOptionalString public var coverUrl: String?
    @LenientOptionalString public var wordCount: String?

    // Kotlin 全字段默认 null。
    public init(
        checkKeyWord: String? = nil,
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
        self._checkKeyWord = LenientOptionalString(wrappedValue: checkKeyWord)
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

    // 字段名与 JSON key 完全一致，不转 snake_case。
    public enum CodingKeys: String, CodingKey {
        case checkKeyWord
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
