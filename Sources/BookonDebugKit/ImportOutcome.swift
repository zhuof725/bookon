//
//  ImportOutcome.swift
//  BookonDebugKit
//
//  第 7 步 C 段返工：书源「导入结果」的纯逻辑表示与文案生成。
//
//  导入面板需要在导入完成后弹窗展示：成功条数、失败原因列表、警告。
//  把这些文案拼装从 SwiftUI 里挪到这里，界面只读结果字符串，便于测试
//  （测试不依赖 UIKit，也不需要构造 View）。
//

import Foundation

/// 一次书源导入的结果（成功条数 + 失败原因 + 警告）。
public struct ImportOutcome: Equatable {

    /// 单条失败原因。
    public struct Failure: Equatable {
        /// 原始数组中的下标（顶层为单对象时为 0）。
        public let index: Int
        /// 可读的失败原因。
        public let reason: String

        public init(index: Int, reason: String) {
            self.index = index
            self.reason = reason
        }
    }

    /// 单条非致命警告。
    public struct Warning: Equatable {
        /// 相关字段名（可能为空）。
        public let field: String?
        /// 警告信息。
        public let message: String

        public init(field: String?, message: String) {
            self.field = field
            self.message = message
        }
    }

    /// 成功导入的条数。
    public let importedCount: Int
    /// 失败条目。
    public let failures: [Failure]
    /// 警告条目。
    public let warnings: [Warning]

    public init(importedCount: Int, failures: [Failure], warnings: [Warning]) {
        self.importedCount = importedCount
        self.failures = failures
        self.warnings = warnings
    }

    /// 是否全部成功（无失败）。
    public var isAllSuccess: Bool { failures.isEmpty }

    /// 失败原因的多行文本（每行 `#下标 原因`）；无失败时为空串。
    public var failureText: String {
        failures
            .map { "#\($0.index) \($0.reason)" }
            .joined(separator: "\n")
    }

    /// 警告的多行文本（每行 `字段：信息`）；无警告时为空串。
    public var warningText: String {
        warnings
            .map { warning in
                if let field = warning.field, !field.isEmpty {
                    return "\(field)：\(warning.message)"
                }
                return warning.message
            }
            .joined(separator: "\n")
    }
}

/// 导入成功后弹窗展示的摘要（把 ImportOutcome 转成界面要显示的三段文案）。
public struct ImportResultSummary: Equatable {

    /// 成功条数的文案，例如「成功导入 5 个书源」。
    public let successText: String
    /// 失败原因列表（无则为 nil）。
    public let failureText: String?
    /// 警告列表（无则为 nil）。
    public let warningText: String?

    public init(outcome: ImportOutcome) {
        self.successText = "成功导入 \(outcome.importedCount) 个书源"
        self.failureText = outcome.failures.isEmpty ? nil : outcome.failureText
        self.warningText = outcome.warnings.isEmpty ? nil : outcome.warningText
    }

    /// 弹窗正文：成功 +（失败）+（警告）三段，空段不显示。
    public var detailText: String {
        var parts = [successText]
        if let failureText {
            parts.append("失败 \(failureText.components(separatedBy: "\n").count) 条：\n\(failureText)")
        }
        if let warningText {
            parts.append("警告：\n\(warningText)")
        }
        return parts.joined(separator: "\n\n")
    }
}
