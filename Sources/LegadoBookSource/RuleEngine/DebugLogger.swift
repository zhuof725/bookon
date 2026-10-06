//
//  DebugLogger.swift
//  LegadoBookSource
//
//  对应 Kotlin: model/Debug.kt 的**书源调试部分**（RSS 部分不做，见 README「不做」清单）。
//
//  Kotlin 的 Debug 是全局 object + 静态 callback；Swift 侧改成**协议注入**，
//  以便：
//    1) 库内部（AnalyzeRule / WebBook 流程层）通过依赖注入上报调试日志；
//    2) 测试用可记录的实现断言「每个字段的 ┌获取书名 / └结果」输出；
//    3) App 层（BookonDebugKit）用同一个协议接 UI / 文件持久化。
//
//  日志格式、符号、状态码全部与 Kotlin 对齐：
//    符号：⇒ ︾ ︽ ┌ └ ◇ ≡
//    状态码：-1 错误；1 普通（默认）；10/20/30/40 各阶段响应源码（搜索/详情/目录/正文）；1000 完成
//    时间前缀：[mm:ss.SSS]（相对 startTime），showTime=true 且已有 startTime 时才加
//    过滤：仅当 (debugSource == sourceUrl) && print 时才输出
//    重定向/内容等日志用 HtmlFormatter.format 做 isHtml 处理
//
//  —— 全局规范：绝不崩溃。任何一处都不 throw。
//

import Foundation

/// 对应 Kotlin: Debug.Callback（printLog(state, msg)）
public protocol DebugLogSink: AnyObject {
    /// 对应 Kotlin: Debug.Callback.printLog(state: Int, msg: String)
    func printLog(state: Int, msg: String)
}

/// 调试日志级别（对应 Kotlin `state` 参数语义）。
public enum DebugLogState {
    /// 对应 Kotlin state = -1：错误
    public static let error = -1
    /// 对应 Kotlin state 默认值 1：普通
    public static let normal = 1
    /// 对应 Kotlin state = 10：搜索响应源码
    public static let searchSource = 10
    /// 对应 Kotlin state = 20：详情响应源码
    public static let infoSource = 20
    /// 对应 Kotlin state = 30：目录响应源码
    public static let tocSource = 30
    /// 对应 Kotlin state = 40：正文响应源码
    public static let contentSource = 40
    /// 对应 Kotlin state = 1000：解析完成
    public static let finished = 1000
}

/// 对应 Kotlin: object Debug 的书源调试部分（RSS 部分不移植）。
///
/// Kotlin 是全局单例，Swift 用「可注入实例」表达同一语义：
/// 每个 WebBook 流程调用持有一个 DebugLogger，未注入时用 NoopDebugLogger。
public final class DebugLogger {

    /// 对应 Kotlin: Debug.debugSource
    public private(set) var debugSource: String?
    /// 对应 Kotlin: Debug.startTime
    public private(set) var startTime: Int64 = DebugLogger.nowMillis()
    /// 对应 Kotlin: Debug.callback
    public weak var callback: DebugLogSink?
    /// 解析结果接收者（第 7 步 C 段：「结果」页签；由流程层在调试过程中回调）。
    /// 未注入时为 nil，不产生任何额外开销，也不改变 Kotlin 行为。
    public weak var resultSink: DebugResultSink?

    /// 额外保留一份内存日志（便于测试与「最终解析结果」导出，不改变 Kotlin 行为）。
    public private(set) var records: [DebugRecord] = []
    /// 响应源码留存（对应任务 A 段第 4 点「每个阶段的最后响应」）。
    public private(set) var lastResponses: [DebugStage: CapturedResponse] = [:]
    /// 线程安全：Kotlin 用 @Synchronized。
    private let lock = NSRecursiveLock()
    /// 是否记录响应体到日志（对应 B 段设置项 `recordResponseBody`，默认 false = Kotlin 行为）。
    public var recordResponseBody: Bool = false
    /// 日志详细级别（B 段设置项；`.verbose` 时保留 -1 以外的全部，`.normal` 与 Kotlin 一致）。
    public var verbosity: DebugVerbosity = .normal

    public init() {}

    // MARK: - 生命周期（对应 Kotlin cancelDebug / startDebug 的 reset 部分）

    /// 对应 Kotlin: fun cancelDebug(destroy: Boolean = false)
    public func cancelDebug(destroy: Bool = false) {
        lock.lock(); defer { lock.unlock() }
        if destroy {
            debugSource = nil
            callback = nil
        }
    }

    /// 对应 Kotlin: `debugSource = bookSource.bookSourceUrl; startTime = System.currentTimeMillis()`
    public func beginDebug(sourceUrl: String) {
        lock.lock(); defer { lock.unlock() }
        debugSource = sourceUrl
        startTime = DebugLogger.nowMillis()
        records.removeAll()
        lastResponses.removeAll()
    }

    // MARK: - log（对应 Kotlin fun log(...)）

    /// 对应 Kotlin:
    /// ```kotlin
    /// fun log(sourceUrl: String?, msg: String = "", print: Boolean = true,
    ///         isHtml: Boolean = false, showTime: Boolean = true, state: Int = 1)
    /// ```
    /// - Parameter print: Kotlin 关键字参数名，Swift 用 `printLog` 避免与全局 print 冲突。
    public func log(
        _ sourceUrl: String?,
        _ msg: String = "",
        printLog print: Bool = true,
        isHtml: Bool = false,
        showTime: Bool = true,
        state: Int = DebugLogState.normal
    ) {
        lock.lock(); defer { lock.unlock() }

        // Kotlin: callback?.let { if (debugSource != sourceUrl || !print) return ... }
        guard let cb = callback else { return }
        if debugSource != sourceUrl || !print { return }

        var printMsg = msg
        if isHtml {
            printMsg = HtmlFormatter.format(msg)
        }
        if showTime {
            let time = formatTime(DebugLogger.nowMillis() &- startTime)
            printMsg = "\(time) \(printMsg)"
        }
        // 详细级别过滤（B 段设置项；normal 与 Kotlin 完全一致：不过滤）。
        if verbosity == .errorsOnly && state != DebugLogState.error {
            return
        }
        cb.printLog(state: state, msg: printMsg)
        records.append(DebugRecord(state: state, message: printMsg, raw: msg))
    }

    /// 对应 Kotlin: fun log(msg: String?)  —— 不带 sourceUrl，用当前 debugSource
    public func log(_ msg: String?) {
        log(debugSource, msg ?? "", printLog: true)
    }

    /// 仅记录响应源码（stage 10/20/30/40），同时留存原始 body 供「源码」页。
    /// 对应 Kotlin 流程层里的 `Debug.log(bookSource.bookSourceUrl, body, state = 10/20/30/40)`。
    public func logResponseSource(stage: DebugStage, sourceUrl: String, body: String) {
        log(sourceUrl, body, state: stage.stateCode)
    }

    // MARK: - 响应留存（任务 A 段第 4 点）

    /// 记录某阶段最后一次响应的 URL / 状态码 / 头 / 原始 body。
    public func captureResponse(_ captured: CapturedResponse) {
        lock.lock(); defer { lock.unlock() }
        lastResponses[captured.stage] = captured
    }

    /// 读取某阶段最后一次响应（界面「源码」页用）。
    public func capturedResponse(stage: DebugStage) -> CapturedResponse? {
        lock.lock(); defer { lock.unlock() }
        return lastResponses[stage]
    }

    // MARK: - 时间（对应 Kotlin SimpleDateFormat("[mm:ss.SSS]")）

    /// 对应 Kotlin: debugTimeFormat.format(Date(millis))，格式 "[mm:ss.SSS]"。
    /// Kotlin 的 mm/ss 是「分钟/秒」（非月/秒），Long 按 0 起算，超过 60 分不回绕到小时。
    func formatTime(_ millis: Int64) -> String {
        let ms = max(0, millis)
        let totalSeconds = ms / 1000
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        let millisPart = ms % 1000
        return String(format: "[%02d:%02d.%03d]", minutes, seconds, millisPart)
    }

    static func nowMillis() -> Int64 {
        return Int64((Date().timeIntervalSince1970 * 1000).rounded())
    }
}

/// 对应 Kotlin `Debug.log` 的一次输出记录。
public struct DebugRecord: Equatable {
    /// 对应 Kotlin state 参数
    public let state: Int
    /// 已加时间前缀/HTML 格式化后的最终文本
    public let message: String
    /// 未加前缀的原始 msg（便于断言业务文本）
    public let raw: String
    public init(state: Int, message: String, raw: String) {
        self.state = state
        self.message = message
        self.raw = raw
    }
}

/// 调试阶段（对应任务 A 段第 4 点的五个阶段）。
public enum DebugStage: String, CaseIterable, Equatable {
    case search
    case explore
    case info
    case toc
    case content

    /// 对应 Kotlin 流程层里该阶段响应源码使用的 state（无对应阶段的回退 normal）。
    public var stateCode: Int {
        switch self {
        case .search: return DebugLogState.searchSource
        case .explore: return DebugLogState.searchSource
        case .info: return DebugLogState.infoSource
        case .toc: return DebugLogState.tocSource
        case .content: return DebugLogState.contentSource
        }
    }
}

/// 某阶段最后一次响应的留存对象（供界面「源码」页）。
public struct CapturedResponse: Equatable {
    public let stage: DebugStage
    public let url: String
    public let statusCode: Int
    public let headers: [String: String]
    public let body: String
    public init(stage: DebugStage, url: String, statusCode: Int, headers: [String: String], body: String) {
        self.stage = stage
        self.url = url
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }
}

/// 日志详细级别（B 段设置项）。
public enum DebugVerbosity: String, Codable, CaseIterable, Equatable, Sendable {
    /// 与 Kotlin 完全一致（不过滤）
    case normal
    /// 只保留错误行
    case errorsOnly
}

/// 空实现：未注入时使用，绝不输出、绝不崩溃（对应 Kotlin callback == null 的行为）。
public final class NoopDebugSink: DebugLogSink {
    public init() {}
    public func printLog(state: Int, msg: String) {}
}

// MARK: - 解析结果留存（第 7 步 C 段返工：「结果」页签）

/// 调试过程中解析出的结果快照。
///
/// Kotlin 的 `Debug.startDebug` 只打日志、不返回解析对象；为了界面「结果」页签，
/// 这里额外留存一份**可观察的解析结果**（仅内存，不改变 Kotlin 的日志行为）。
public struct DebugParsedResult: Equatable {
    /// 搜索/发现阶段解析出的书籍列表。
    public var books: [Book]
    /// 详情阶段解析出的第一本书（含书名/作者/简介等）。
    public var book: Book?
    /// 目录阶段解析出的章节列表。
    public var chapters: [BookChapter]
    /// 正文阶段解析出的正文（取第一章）。
    public var content: String?

    public init(books: [Book] = [],
                book: Book? = nil,
                chapters: [BookChapter] = [],
                content: String? = nil) {
        self.books = books
        self.book = book
        self.chapters = chapters
        self.content = content
    }

    /// 是否已有任何解析结果。
    public var isEmpty: Bool {
        books.isEmpty && book == nil && chapters.isEmpty && (content?.isEmpty ?? true)
    }
}

/// 解析结果接收协议（由流程层在调试过程中回调，界面侧的 DebugSession 实现）。
public protocol DebugResultSink: AnyObject {
    func updateParsedResult(_ update: (inout DebugParsedResult) -> Void)
}
