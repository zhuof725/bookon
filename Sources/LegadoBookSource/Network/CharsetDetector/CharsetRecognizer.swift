//
//  CharsetRecognizer.swift
//  LegadoBookSource
//
//  第 6 步 6B：ICU4J CharsetRecognizer 抽象类的 Swift 等价物。
//
//  对应 Java：app/src/main/java/io/legado/app/lib/icu4j/CharsetRecognizer.java
//

import Foundation

/// 单个字符集的识别器（ICU4J `CharsetRecognizer`）。
///
/// 每个识别器实例是「无状态、可共享」的常对象，`match` 只读检测器上下文。
protocol CharsetRecognizer: AnyObject {
    /// 获取 IANA 字符集名（Java `getName()`）。
    var name: String { get }
    /// 获取语言代码（Java `getLanguage()`，无则不提供）。
    var language: String { get }
    /// 用检测器上下文做一次匹配（Java `match(CharsetDetector)`）。
    /// `index` 为该识别器在 ALL_CS_RECOGNIZERS 中的下标（用于并列决胜）。
    /// 返回 nil 表示置信度为 0、不参与排序。
    func match(_ det: CharsetDetectorEngine, index: Int) -> CharsetMatch?
}

extension CharsetRecognizer {
    /// Java `getLanguage()` 的默认实现：返回空串。
    var language: String { "" }
}