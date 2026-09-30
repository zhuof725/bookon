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
    /// ⚠️ 已废弃且不应使用：SwiftSoup 的 `Elements.empty()` 语义是「清空每个元素的子节点」
    /// （对应 Jsoup `Element#empty()`：会真的修改 DOM，移除子节点！），
    /// 与 Kotlin `MutableList.clear()`（只清空集合、不触碰 DOM）完全不同。
    /// 之前在这里错误地用 `self.empty()` 实现"清空集合"，导致 `getResultList` 循环里
    /// `elements.clearAll()` 会把 `self.element`（原始 document）的子节点整个清空，
    /// 破坏了后续规则的查询结果（真实 bug，已通过测试定位并修复：调用方一律改为
    /// 新建 `Elements()` 而不是"清空复用"，不再提供这个方法）。
    /// 安全获取（越界返回 nil，避免 get(_:) 潜在越界）。
    func getOrNil(_ i: Int) -> Element? {
        guard i >= 0 && i < self.size() else { return nil }
        return self.get(i)
    }
}
