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

    /// 解析结果（「结果」页签）：书籍 / 目录 / 正文。由流程层经 resultSink 回填。
    public private(set) var parsedResult = DebugParsedResult()

    /// 底层日志器（含 records / lastResponses / 各阶段最后响应）。
    public let logger: DebugLogger

    private var runTask: Task<Void, Never>?
    private var sink: StageTrackingSink?
    private var resultRelay: ResultRelay?

    public init(logger: DebugLogger = DebugLogger()) {
        self.logger = logger
    }

    public var isRunning: Bool { state == .running }

    public var elapsed: TimeInterval {
        guard let start = startTime else { return 0 }
        return (endTime ?? Date()).timeIntervalSince(start)
    }

    public var records: [DebugRecord] { logger.records }

    // MARK: - 启动 / 取消

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

        // 结果留存：把流程层解析出的书籍/目录/正文回填到 parsedResult（主线程更新）。
        parsedResult = DebugParsedResult()
        let relay = ResultRelay { [weak self] result in
            self?.parsedResult = result
        }
        self.resultRelay = relay
        logger.resultSink = relay

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

    // MARK: - 源码 / 结果读取（供界面各页签）

    /// 读取某阶段最后一次响应（源码页签用）。
    public func capturedResponse(for tab: DebugTab) -> CapturedResponse? {
        guard let stage = tab.stage else { return nil }
        return logger.capturedResponse(stage: stage)
    }

    /// 各源码页签的响应摘要（供「有数据」判定）。
    public func responseSummary(for tab: DebugTab) -> DebugResponseSummary {
        guard let cap = capturedResponse(for: tab) else { return .empty }
        return DebugResponseSummary(
            hasResponse: true,
            url: cap.url,
            statusCode: cap.statusCode,
            bodyCount: cap.body.count
        )
    }

    /// 标签条状态（小圆点 / 错误红点）。
    public var tabBarState: DebugTabBarState {
        var map: [DebugStage: Bool] = [:]
        for stage in DebugStage.allCases {
            if let cap = logger.capturedResponse(stage: stage) {
                map[stage] = !cap.body.isEmpty || !cap.url.isEmpty
            }
        }
        let hasError = logger.records.contains { $0.state == DebugLogState.error }
        return DebugTabBarState(stageHasResponse: map, hasError: hasError)
    }

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

    /// 解析结果导出为 JSON（「结果」页签的「复制 JSON」用）。
    public func exportParsedResultJSON() -> String {
        let export = DebugParsedResultExport(
            books: parsedResult.books.map { DebugBookExport($0) },
            book: parsedResult.book.map { DebugBookExport($0) },
            chapters: parsedResult.chapters.map {
                DebugChapterExport(title: $0.title, url: $0.url, isVolume: $0.isVolume)
            },
            content: parsedResult.content
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = (try? encoder.encode(export)) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

/// 把流程层的 `DebugResultSink` 回调转成主线程上的 `parsedResult` 更新。
final class ResultRelay: DebugResultSink {
    private let onUpdate: (DebugParsedResult) -> Void
    private var current = DebugParsedResult()

    init(onUpdate: @escaping (DebugParsedResult) -> Void) { self.onUpdate = onUpdate }

    func updateParsedResult(_ update: (inout DebugParsedResult) -> Void) {
        var next = current
        update(&next)
        current = next
        let snapshot = next
        if Thread.isMainThread {
            onUpdate(snapshot)
        } else {
            DispatchQueue.main.async { [weak self] in self?.onUpdate(snapshot) }
        }
    }
}

/// 书籍导出结构（只取关键字段，避免把 Book 的全部属性都暴露成 JSON）。
public struct DebugBookExport: Codable, Equatable {
    public let name: String
    public let author: String
    public let bookUrl: String
    public let tocUrl: String
    public let kind: String?
    public let intro: String?
    public let coverUrl: String?
    public let latestChapterTitle: String?

    public init(_ book: Book) {
        self.name = book.name
        self.author = book.author
        self.bookUrl = book.bookUrl
        self.tocUrl = book.tocUrl
        self.kind = book.kind
        self.intro = book.intro
        self.coverUrl = book.coverUrl
        self.latestChapterTitle = book.latestChapterTitle
    }
}

/// 章节导出结构。
public struct DebugChapterExport: Codable, Equatable {
    public let title: String
    public let url: String
    public let isVolume: Bool

    public init(title: String, url: String, isVolume: Bool) {
        self.title = title
        self.url = url
        self.isVolume = isVolume
    }
}

/// 解析结果导出结构。
public struct DebugParsedResultExport: Codable, Equatable {
    public let books: [DebugBookExport]
    public let book: DebugBookExport?
    public let chapters: [DebugChapterExport]
    public let content: String?
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
