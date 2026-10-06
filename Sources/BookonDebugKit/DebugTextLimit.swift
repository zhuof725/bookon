//
//  DebugTextLimit.swift
//  BookonDebugKit
//
//  第 7 步 C 段返工：文本按「Character」截断的纯逻辑 + 两个字符上限的默认值/范围。
//  不按字节截断、不在代理对或组合字符中间切开；5MB 硬上限。
//  全部非界面逻辑，可测试（不带 SwiftUI、不带 UIKit）。
//

import Foundation

/// 两个字符上限的默认值与合法范围（供 DebugSettings 与界面共用）。
public enum DebugTextLimit {
    /// 源码页签显示上限：默认 30000，范围 1000...500000。
    public static let displayDefault = 30000
    public static let displayRange = 1000...500000

    /// 导出附带源码上限：默认 5000，范围 0...100000（0 表示不附带）。
    public static let exportDefault = 5000
    public static let exportRange = 0...100000

    /// 单个阶段响应体的硬上限：5MB（按 UTF-8 字节）。
    /// 超出时只保留前缀，并在源码页签顶部提示。
    public static let hardByteLimit = 5 * 1024 * 1024

    /// 把一个值钳位到指定范围（越界或负数都收敛到边界）。
    public static func clamp(_ value: Int, to range: ClosedRange<Int>) -> Int {
        if value < range.lowerBound { return range.lowerBound }
        if value > range.upperBound { return range.upperBound }
        return value
    }

    // MARK: - 截断

    /// 截断结果。
    public struct TruncationResult: Equatable {
        /// 截断后的文本。
        public let text: String
        /// 原文总字符数。
        public let totalCount: Int
        /// 是否发生了截断。
        public let truncated: Bool
        /// 追加在末尾的提示行（未截断时为空串）。
        public let notice: String

        public init(text: String, totalCount: Int, truncated: Bool, notice: String) {
            self.text = text
            self.totalCount = totalCount
            self.truncated = truncated
            self.notice = notice
        }
    }

    /// 按 Character 截断到 `limit` 个字符，超出则追加「已截断，显示 N / 共 M 字符」。
    ///
    /// - 按 `Character`（用户可见字符）计数，不会在 emoji 的代理对或组合字符中间切开。
    /// - `limit <= 0` 时返回空文本并标记截断（totalCount 仍为原文长度）。
    /// - 未超限时 `notice` 为空、`truncated` 为 false，文本原样返回。
    public static func truncate(_ source: String, limit: Int) -> TruncationResult {
        let total = source.count
        guard limit > 0 else {
            let notice = "已截断，显示 0 / 共 \(total) 字符"
            return TruncationResult(text: "", totalCount: total, truncated: total > 0, notice: notice)
        }
        if total <= limit {
            return TruncationResult(text: source, totalCount: total, truncated: false, notice: "")
        }
        let cut = String(source.prefix(limit))
        let notice = "已截断，显示 \(limit) / 共 \(total) 字符"
        return TruncationResult(text: cut, totalCount: total, truncated: true, notice: notice)
    }

    /// 导出用：给某阶段源码生成「搜索源码 前 N 字符（共 M）」标注（0 表示不附带）。
    /// - Returns: 需要附加的段落（含标题与内容）；`limit == 0` 时返回 nil。
    public static func exportSection(for source: String, name: String, limit: Int) -> String? {
        guard limit > 0 else { return nil }
        let total = source.count
        let shown = min(limit, total)
        let body = String(source.prefix(shown))
        let suffix = total > limit ? "（已截断）" : ""
        return "--- \(name) 前 \(shown) 字符（共 \(total)）\(suffix) ---\n\(body)"
    }

    /// 判断 UTF-8 字节数是否超过硬上限，并在超限时给出保留前缀。
    /// - Returns: `(是否超限, 需要保留的文本前缀, 提示语)`。
    public static func applyHardByteLimit(_ source: String) -> (exceeded: Bool, kept: String, notice: String) {
        let bytes = source.utf8.count
        guard bytes > hardByteLimit else { return (false, source, "") }
        // 按字节前缀保留，再退到最近的一个合法 Character（用 utf8 前缀重建，失败则逐步退让）。
        var kept = source
        var data = Data(source.utf8.prefix(hardByteLimit))
        while !data.isEmpty, String(data: data, encoding: .utf8) == nil {
            data = data.dropLast()
        }
        kept = String(data: data, encoding: .utf8) ?? ""
        let notice = "响应体超过 5MB，仅保留前 5MB"
        return (true, kept, notice)
    }
}
