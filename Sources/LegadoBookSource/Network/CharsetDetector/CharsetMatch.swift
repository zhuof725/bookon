//
//  CharsetMatch.swift
//  LegadoBookSource
//
//  第 6 步 6B：ICU4J CharsetMatch 的 Swift 移植。
//
//  对应 Java：app/src/main/java/io/legado/app/lib/icu4j/CharsetMatch.java
//
//  本结构体承载一次识别的结果：字符集名、置信度（0-100）、语言。
//  排序语义与 Java 完全一致：Collections.sort（按 confidence 升序、稳定）+ reverse，
//  即「confidence 相同者，识别器列表靠后者优先」。
//

import Foundation

/// ICU4J CharsetMatch 的 Swift 等价物（内部类型；公开 API 只暴露字符集名字符串）。
///
/// 对应 Java `CharsetMatch`（`getConfidence()` / `getName()` / `getLanguage()`）。
struct CharsetMatch {
    /// 匹配置信度，0-100（Java `getConfidence()`）。
    let confidence: Int
    /// 检测出的字符集名（Java `getName()`，如 "UTF-8"/"GB18030"）。
    let name: String
    /// 语言（Java `getLanguage()`，可能为空）。
    let language: String
    /// 在识别器列表中的原始下标，用于复刻 Java「稳定排序 + reverse」的并列次序。
    let index: Int
}