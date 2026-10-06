//
//  DebugTab.swift
//  BookonDebugKit
//
//  第 7 步 C 段返工：调试页分页签的纯逻辑（标签标题 / 对应阶段 / 占位文案 /
//  是否有数据 / 标签小圆点与错误红点判定）。全部非界面逻辑，界面只绑定。
//

import Foundation
import LegadoBookSource

/// 调试页的分页签枚举（顺序即界面上的显示顺序）。
public enum DebugTab: String, CaseIterable, Identifiable, Equatable {
    case logs
    case searchSource
    case infoSource
    case tocSource
    case contentSource
    case result

    public var id: String { rawValue }

    /// 标签标题。
    public var title: String {
        switch self {
        case .logs: return "日志"
        case .searchSource: return "搜索源码"
        case .infoSource: return "详情源码"
        case .tocSource: return "目录源码"
        case .contentSource: return "正文源码"
        case .result: return "结果"
        }
    }

    /// 该标签对应的流程阶段；日志/结果页没有对应阶段，返回 nil。
    public var stage: DebugStage? {
        switch self {
        case .searchSource: return .search
        case .infoSource: return .info
        case .tocSource: return .toc
        case .contentSource: return .content
        case .logs, .result: return nil
        }
    }

    /// 尚无数据时的占位文案。
    public var placeholder: String {
        switch self {
        case .logs: return "尚无日志。输入调试关键字后点「开始调试」。"
        case .searchSource: return "尚无搜索响应源码。"
        case .infoSource: return "尚无详情响应源码。"
        case .tocSource: return "尚无目录响应源码。"
        case .contentSource: return "尚无正文响应源码。"
        case .result: return "尚无解析结果。"
        }
    }

    /// 是否为「源码」类标签（用等宽字体 + 横向滚动 + 截断提示）。
    public var isSourceTab: Bool { stage != nil }

    /// 该标签是否在正文区显示「复制」按钮。
    public var hasCopyButton: Bool { true }
}

/// 一个阶段响应的摘要（供「有数据」判定与标签小圆点）。
public struct DebugResponseSummary: Equatable {
    /// 是否已捕获到该阶段响应。
    public let hasResponse: Bool
    /// 响应 URL（无则空串）。
    public let url: String
    /// 响应状态码（无响应时为 0）。
    public let statusCode: Int
    /// 响应体字符数。
    public let bodyCount: Int

    public init(hasResponse: Bool, url: String, statusCode: Int, bodyCount: Int) {
        self.hasResponse = hasResponse
        self.url = url
        self.statusCode = statusCode
        self.bodyCount = bodyCount
    }

    public static let empty = DebugResponseSummary(hasResponse: false, url: "", statusCode: 0, bodyCount: 0)
}

/// 分页签的展示状态（供界面渲染标签条：小圆点 / 红点）。
///
/// 全部判定逻辑集中在此，界面只读结果，便于测试。
public struct DebugTabBarState: Equatable {
    /// 每个源码标签是否已有响应（标签后显示小圆点）。
    public let stageHasResponse: [DebugStage: Bool]
    /// 日志中是否出现过错误（状态码 -1，日志标签后显示红点）。
    public let hasError: Bool

    public init(stageHasResponse: [DebugStage: Bool], hasError: Bool) {
        self.stageHasResponse = stageHasResponse
        self.hasError = hasError
    }

    public static let empty = DebugTabBarState(stageHasResponse: [:], hasError: false)

    /// 判断某标签是否显示小圆点。
    /// 规则：仅源码类标签、且该阶段已有响应时为 true；日志标签显示红点走 `hasError`。
    public func showsDot(for tab: DebugTab) -> Bool {
        guard let stage = tab.stage else { return false }
        return stageHasResponse[stage] ?? false
    }

    /// 判断某标签是否显示错误红点（目前仅「日志」标签）。
    public func showsErrorDot(for tab: DebugTab) -> Bool {
        tab == .logs && hasError
    }
}

/// 输入框下方的「示例提示」条目（关键字 / 详情页网址 / ::发现页 / ++目录页 / --正文页）。
///
/// 放在 DebugKit 而不是界面里：文案属于产品逻辑，测试可直接断言 5 种形式齐全。
public struct DebugKeyExample: Equatable, Identifiable, Sendable {
    /// 形式提示，例如 `::发现页`。
    public let hint: String
    /// 示例值，例如 `::https://example.com/list`。
    public let sample: String

    public var id: String { hint }

    public init(hint: String, sample: String) {
        self.hint = hint
        self.sample = sample
    }

    /// 5 种 key 形式，与 `Debug.startDebug` 的分发一一对应。
    public static let all: [DebugKeyExample] = [
        DebugKeyExample(hint: "关键字", sample: "斗罗大陆"),
        DebugKeyExample(hint: "详情页网址", sample: "https://www.example.com/book/1"),
        DebugKeyExample(hint: "::发现页", sample: "::https://www.example.com/list"),
        DebugKeyExample(hint: "++目录页", sample: "++https://www.example.com/toc/1"),
        DebugKeyExample(hint: "--正文页", sample: "--https://www.example.com/chapter/1"),
    ]
}
