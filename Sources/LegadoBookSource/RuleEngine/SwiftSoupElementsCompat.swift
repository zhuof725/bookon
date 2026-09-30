//
//  SwiftSoupElementsCompat.swift
//  LegadoBookSource
//
//  SwiftSoup 的 Elements API 与 Jsoup 不同（无 add(contentsOf:) / clear()）。
//  这里提供内部辅助，便于 AnalyzeByJSoup 逐条对照移植 Kotlin 而不改行为。
//

import Foundation
import SwiftSoup

extension Elements {
    /// 批量追加（对应 Kotlin Elements.addAll(collection)）。
    func addElements(_ es: [Element]) {
        for e in es { self.add(e) }
    }
    /// 批量追加另一个 Elements。
    func addElements(_ es: Elements) {
        for e in es.array() { self.add(e) }
    }
    /// 清空（对应 Kotlin Elements.clear()）。SwiftSoup 用 empty()。
    func clearAll() {
        _ = self.empty()
    }
    /// 安全获取（越界返回 nil，避免 get(_:) 潜在越界）。
    func getOrNil(_ i: Int) -> Element? {
        guard i >= 0 && i < self.size() else { return nil }
        return self.get(i)
    }
}
