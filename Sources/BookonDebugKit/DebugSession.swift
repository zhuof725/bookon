//
//  DebugSession.swift
//  BookonDebugKit
//
//  第 7 步 B 段：调试会话（5 种 key 形式 / 取消 / 计时 / 阶段来源 / 结果导出 JSON）。
//  全部非界面逻辑，用 @Observable；实际解析委托给 LegadoBookSource.Debug.startDebug。
//

import Foundation
import Observation
import LegadoBookSource

/// 把日志 state 映射回阶段（与 DebugStage.stateCode 互为逆映射）。
enum DebugStageMapping {
    static func stage(forState state: Int) -> DebugStage? {
        switch state {
        case DebugLogState.searchSource: return .search
        case DebugLogState.infoSource: return .info
        case DebugLogState.tocSource: return .toc
        case DebugLogState.contentSource: return .content
        default: return nil
        }
    }
}

/// 追踪当前阶段的 sink：把带阶段 state 的日志映射到 currentStage。
final class StageTrackingSink: DebugLogSink {
    let onStage: (DebugStage) -> Void
    init(onStage: @escaping (DebugStage) -> Void) { self.onStage = onStage }
    func printLog(state: Int, msg: String) {
        if let stage = DebugStageMapping.stage(forState: state) {
            onStage(stage)
        }
    }
}

@Observable
public final class DebugSession {

    public enum State: Equatable {
        case idle
        case running
        case finished
        case cancelled
    }

    public private(set) var state: State = .idle
    public private(set) var startTime: Date?
    public private(set) var endTime: Date?
    /// 当前所处的阶段（搜索/详情/目录/正文），由带阶段 state 的日志推导。
    public private(set) var currentStage: DebugStage?
    /// 当前书源 URL / 调试 key（供导出元数据）。
    public private(set) var sourceUrl: String?
    public private(set) var debugKey: String?

    /// 底层日志器（含 records / lastResponses / 各阶段最后响应）。
    public let logger: DebugLogger

    private var runTask: Task<Void, Never>?
    private var sink: StageTrackingSink?

    public init(logger: DebugLogger = DebugLogger()) {
        self.logger = logger
    }

    public var isRunning: Bool { state == .running }

    public var elapsed: TimeInterval {
        guard let start = startTime else { return 0 }
        return (endTime ?? Date()).timeIntervalSince(start)
    }

    public var records: [DebugRecord] { logger.records }

    /// 启动调试（5 种 key 形式由 Debug.startDebug 分发：绝对地址/::/++/--/搜索）。
    public func start(bookSource: BookSource, key: String, options: WebBookOptions) {
        guard state != .running else { return }
        state = .running
        startTime = Date()
        endTime = nil
        currentStage = nil
        sourceUrl = bookSource.bookSourceUrl
        debugKey = key

        logger.beginDebug(sourceUrl: bookSource.bookSourceUrl)
        let sink = StageTrackingSink { [weak self] stage in
            self?.currentStage = stage
        }
        self.sink = sink
        logger.callback = sink

        runTask = Task { [weak self] in
            await Debug.startDebug(bookSource: bookSource, key: key, options: options)
            guard let self = self else { return }
            if Task.isCancelled {
                self.state = .cancelled
            } else {
                self.state = .finished
            }
            self.endTime = Date()
        }
    }

    /// 取消调试（不销毁 logger 的 debugSource，保留已收集日志）。
    public func cancel() {
        runTask?.cancel()
        logger.cancelDebug(destroy: false)
        state = .cancelled
        endTime = Date()
    }

    // MARK: - 结果导出

    /// 导出为 JSON：元数据 + 日志行 + 各阶段最后响应 URL/状态码。
    public func exportResultJSON() -> String {
        let export = DebugSessionExport(
            sourceUrl: sourceUrl,
            key: debugKey,
            startTime: startTime?.description,
            elapsed: elapsed,
            records: logger.records.map { $0.message },
            stages: DebugStage.allCases.compactMap { stage -> DebugStageExport? in
                guard let cap = logger.capturedResponse(stage: stage) else { return nil }
                return DebugStageExport(stage: stage.rawValue, url: cap.url, statusCode: cap.statusCode)
            }
        )
        let data = (try? LegadoJSON.prettyEncoder.encode(export)) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

/// 导出结构（Codable，供 JSON 序列化）。
public struct DebugSessionExport: Codable {
    public let sourceUrl: String?
    public let key: String?
    public let startTime: String?
    public let elapsed: Double
    public let records: [String]
    public let stages: [DebugStageExport]
}

public struct DebugStageExport: Codable {
    public let stage: String
    public let url: String
    public let statusCode: Int
}
