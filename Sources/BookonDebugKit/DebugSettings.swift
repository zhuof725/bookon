//
//  DebugSettings.swift
//  BookonDebugKit
//
//  第 7 步 B 段：调试设置（连接/读取/总超时、记录响应体、日志详细级别）。
//  全部非界面逻辑，用 @Observable；可注入 UserDefaults 以便测试。
//

import Foundation
import Observation
import LegadoBookSource

@Observable
public final class DebugSettings {

    /// 连接超时（秒）。
    public var connectTimeout: Int
    /// 读取超时（秒）。
    public var readTimeout: Int
    /// 总超时（秒）。
    public var totalTimeout: Int
    /// 是否把响应体写入日志（对应 DebugLogger.recordResponseBody）。
    public var recordResponseBody: Bool
    /// 日志详细级别（对应 DebugLogger.verbosity）。
    public var verbosity: DebugVerbosity
    /// 源码页签显示上限（按 Character 计数，默认 30000，范围 1000...500000）。
    public var sourceDisplayLimit: Int
    /// 导出日志附带各阶段源码的上限（按 Character 计数，默认 5000，范围 0...100000，0=不附带）。
    public var exportSourceLimit: Int

    private let defaults: UserDefaults
    static let suiteName = "com.bookon.debug.settings"

    public init(connectTimeout: Int = 10,
                readTimeout: Int = 60,
                totalTimeout: Int = 60,
                recordResponseBody: Bool = false,
                verbosity: DebugVerbosity = .normal,
                sourceDisplayLimit: Int = DebugTextLimit.displayDefault,
                exportSourceLimit: Int = DebugTextLimit.exportDefault,
                defaults: UserDefaults = UserDefaults(suiteName: "com.bookon.debug.settings") ?? .standard) {
        self.connectTimeout = connectTimeout
        self.readTimeout = readTimeout
        self.totalTimeout = totalTimeout
        self.recordResponseBody = recordResponseBody
        self.verbosity = verbosity
        self.sourceDisplayLimit = DebugTextLimit.clamp(sourceDisplayLimit, to: DebugTextLimit.displayRange)
        self.exportSourceLimit = DebugTextLimit.clamp(exportSourceLimit, to: DebugTextLimit.exportRange)
        self.defaults = defaults
        load()
    }

    /// 把设置应用到日志器。
    public func apply(to logger: DebugLogger) {
        logger.recordResponseBody = recordResponseBody
        logger.verbosity = verbosity
    }

    /// 超时（毫秒）三元组，供网络层使用。
    public var timeoutsMilliseconds: (connect: Int, read: Int, total: Int) {
        (connectTimeout * 1000, readTimeout * 1000, totalTimeout * 1000)
    }

    /// 恢复两个字符上限到默认值（不改变超时与日志设置）。
    public func restoreDefaultTextLimits() {
        sourceDisplayLimit = DebugTextLimit.displayDefault
        exportSourceLimit = DebugTextLimit.exportDefault
        save()
    }

    // MARK: - 持久化（UserDefaults，可注入）

    public func save() {
        defaults.set(connectTimeout, forKey: "connectTimeout")
        defaults.set(readTimeout, forKey: "readTimeout")
        defaults.set(totalTimeout, forKey: "totalTimeout")
        defaults.set(recordResponseBody, forKey: "recordResponseBody")
        defaults.set(verbosity.rawValue, forKey: "verbosity")
        defaults.set(sourceDisplayLimit, forKey: "sourceDisplayLimit")
        defaults.set(exportSourceLimit, forKey: "exportSourceLimit")
    }

    private func load() {
        if defaults.object(forKey: "connectTimeout") != nil {
            connectTimeout = defaults.integer(forKey: "connectTimeout")
        }
        if defaults.object(forKey: "readTimeout") != nil {
            readTimeout = defaults.integer(forKey: "readTimeout")
        }
        if defaults.object(forKey: "totalTimeout") != nil {
            totalTimeout = defaults.integer(forKey: "totalTimeout")
        }
        if defaults.object(forKey: "recordResponseBody") != nil {
            recordResponseBody = defaults.bool(forKey: "recordResponseBody")
        }
        if let raw = defaults.string(forKey: "verbosity") {
            verbosity = DebugVerbosity(rawValue: raw) ?? .normal
        }
        // 两个字符上限：读到越界值/类型不对时钳位到合法范围，不崩溃、不静默忽略。
        sourceDisplayLimit = Self.readInt(
            defaults, key: "sourceDisplayLimit",
            fallback: DebugTextLimit.displayDefault,
            range: DebugTextLimit.displayRange
        )
        exportSourceLimit = Self.readInt(
            defaults, key: "exportSourceLimit",
            fallback: DebugTextLimit.exportDefault,
            range: DebugTextLimit.exportRange
        )
    }

    /// 读一个 Int 设置：缺省用默认值；越界钳位；类型不对（如存了字符串）也回退并写回。
    private static func readInt(_ defaults: UserDefaults,
                                key: String,
                                fallback: Int,
                                range: ClosedRange<Int>) -> Int {
        guard let obj = defaults.object(forKey: key) else {
            defaults.set(fallback, forKey: key)
            return fallback
        }
        let raw: Int
        if let i = obj as? Int {
            raw = i
        } else if let s = obj as? String, let i = Int(s) {
            raw = i
        } else {
            // 类型不对：回退并回写，避免每次启动都走异常分支。
            defaults.set(fallback, forKey: key)
            return fallback
        }
        let clamped = DebugTextLimit.clamp(raw, to: range)
        if clamped != raw { defaults.set(clamped, forKey: key) } // 越界回写
        return clamped
    }
}
