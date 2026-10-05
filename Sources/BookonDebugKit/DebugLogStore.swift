//
//  DebugLogStore.swift
//  BookonDebugKit
//
//  第 7 步 B 段：调试日志持久化（Documents/logs/时间戳-书源名.txt，写后即刷、保留 50）+ 日志导出。
//  全部非界面逻辑。
//

import Foundation
import LegadoBookSource

/// 日志导出头（应用版本 / git commit / CI run / OS / 书源 / key / 时间）。
public struct DebugLogExportHeader {
    public var appVersion: String?
    public var gitCommit: String?
    public var ciRun: String?
    public var osVersion: String
    public var sourceName: String?
    public var key: String?

    public init(appVersion: String? = nil,
                gitCommit: String? = nil,
                ciRun: String? = nil,
                osVersion: String = ProcessInfo.processInfo.operatingSystemVersionString,
                sourceName: String? = nil,
                key: String? = nil) {
        self.appVersion = appVersion
        self.gitCommit = gitCommit
        self.ciRun = ciRun
        self.osVersion = osVersion
        self.sourceName = sourceName
        self.key = key
    }
}

public final class DebugLogStore {

    private let logsDirectory: URL
    private let maxLogFiles: Int
    private let now: () -> Date
    private let fileManager: FileManager

    public init(logsDirectory: URL? = nil,
                maxLogFiles: Int = 50,
                now: @escaping () -> Date = { Date() },
                fileManager: FileManager = .default) {
        self.logsDirectory = logsDirectory ?? Self.defaultLogsDirectory()
        self.maxLogFiles = maxLogFiles
        self.now = now
        self.fileManager = fileManager
        try? fileManager.createDirectory(at: self.logsDirectory, withIntermediateDirectories: true)
    }

    /// Documents/logs/
    public static func defaultLogsDirectory() -> URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return dir.appendingPathComponent("logs", isDirectory: true)
    }

    // MARK: - 保存

    /// 保存一份日志到 `时间戳-书源名.txt`（原子写，写后即刷），并裁剪到保留 maxLogFiles 份。
    @discardableResult
    public func saveLog(sourceName: String, content: String) throws -> URL {
        let url = logsDirectory.appendingPathComponent(Self.fileName(for: sourceName, now: now()))
        // .atomic 写临时文件后 rename，等价于「写后即刷」，不会留下半截文件。
        try Data(content.utf8).write(to: url, options: .atomic)
        prune()
        return url
    }

    /// 追加一行（写后即刷）。用于流式记录（每个 printLog 立即落盘）。
    public func appendLine(_ line: String, to url: URL) throws {
        if fileManager.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            if let data = (line + "\n").data(using: .utf8) {
                try handle.write(contentsOf: data)
                try handle.synchronize()
            }
        } else {
            try Data((line + "\n").utf8).write(to: url, options: .atomic)
        }
    }

    static func fileName(for sourceName: String, now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let stamp = formatter.string(from: now)
        let safe = sanitize(sourceName)
        return "\(stamp)-\(safe).txt"
    }

    static func sanitize(_ name: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let parts = name.components(separatedBy: forbidden)
        return parts.joined(separator: "_")
    }

    // MARK: - 列表 / 裁剪

    public func listLogs() -> [URL] {
        guard let files = try? fileManager.contentsOfDirectory(
            at: logsDirectory, includingPropertiesForKeys: nil, options: []) else {
            return []
        }
        return files.filter { $0.pathExtension == "txt" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    public var logCount: Int { listLogs().count }

    private func prune() {
        var files = listLogs()
        while files.count > maxLogFiles {
            let oldest = files.removeFirst()
            try? fileManager.removeItem(at: oldest)
        }
    }

    // MARK: - 导出

    /// 拼接导出文本：头 + 正文 +（可选）书源规则前 N 字符。
    public func exportContent(header: DebugLogExportHeader,
                              body: String,
                              sourceSnippet: String? = nil,
                              sourceSnippetLimit: Int = 0) -> String {
        var lines: [String] = []
        lines.append("=== 调试日志导出 ===")
        if let v = header.appVersion { lines.append("App 版本: \(v)") }
        if let c = header.gitCommit { lines.append("Git 提交: \(c)") }
        if let c = header.ciRun { lines.append("CI Run: \(c)") }
        lines.append("OS: \(header.osVersion)")
        if let s = header.sourceName { lines.append("书源: \(s)") }
        if let k = header.key { lines.append("关键字: \(k)") }
        lines.append("时间: \(Self.timestamp(now: now()))")
        lines.append("")
        lines.append("--- 日志正文 ---")
        lines.append(body)
        if let snippet = sourceSnippet, !snippet.isEmpty {
            let limited = sourceSnippetLimit > 0 ? String(snippet.prefix(sourceSnippetLimit)) : snippet
            lines.append("")
            lines.append("--- 书源规则（前 \(limited.count) 字符）---")
            lines.append(limited)
        }
        return lines.joined(separator: "\n")
    }

    static func timestamp(now: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: now)
    }
}
