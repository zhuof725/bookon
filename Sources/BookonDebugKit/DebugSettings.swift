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

    private let defaults: UserDefaults
    static let suiteName = "com.bookon.debug.settings"

    public init(connectTimeout: Int = 10,
                readTimeout: Int = 60,
                totalTimeout: Int = 60,
                recordResponseBody: Bool = false,
                verbosity: DebugVerbosity = .normal,
                defaults: UserDefaults = UserDefaults(suiteName: "com.bookon.debug.settings") ?? .standard) {
        self.connectTimeout = connectTimeout
        self.readTimeout = readTimeout
        self.totalTimeout = totalTimeout
        self.recordResponseBody = recordResponseBody
        self.verbosity = verbosity
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

    // MARK: - 持久化（UserDefaults，可注入）

    public func save() {
        defaults.set(connectTimeout, forKey: "connectTimeout")
        defaults.set(readTimeout, forKey: "readTimeout")
        defaults.set(totalTimeout, forKey: "totalTimeout")
        defaults.set(recordResponseBody, forKey: "recordResponseBody")
        defaults.set(verbosity.rawValue, forKey: "verbosity")
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
    }
}
