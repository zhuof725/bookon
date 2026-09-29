//
//  BookListRule.swift
//  LegadoBookSource
//
//  对应 Kotlin: data/entities/rule/BookListRule.kt
//

import Foundation

/// 书籍列表规则
/// Kotlin 原为 interface（SearchRule / ExploreRule 实现它）。
/// Swift 用 protocol 表达同样的字段约束。
protocol BookListRule {
    var bookList: String? { get set }
    var name: String? { get set }
    var author: String? { get set }
    var intro: String? { get set }
    var kind: String? { get set }
    var lastChapter: String? { get set }
    var updateTime: String? { get set }
    var bookUrl: String? { get set }
    var coverUrl: String? { get set }
    var wordCount: String? { get set }
}
