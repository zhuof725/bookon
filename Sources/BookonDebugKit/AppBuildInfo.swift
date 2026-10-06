//
//  AppBuildInfo.swift
//  BookonDebugKit
//
//  第 7 步 C 段返工：从 Info.plist 读取 App 版本 / commit 哈希 / CI run 编号。
//  Info.plist 里分别是 CFBundleShortVersionString / BuildCommit / BuildCIRun。
//  dictionary 可注入，便于测试（不在测试里依赖真实 Bundle）。
//

import Foundation

public struct AppBuildInfo: Equatable {

    /// App 版本（Info.plist 的 CFBundleShortVersionString）。
    public let version: String
    /// git commit 短哈希（Info.plist 的 BuildCommit，来自构建时注入的 GIT_COMMIT）。
    public let commit: String
    /// CI run 编号（Info.plist 的 BuildCIRun，来自构建时注入的 CI_RUN_ID）。
    public let ciRun: String

    public init(version: String, commit: String, ciRun: String) {
        self.version = version
        self.commit = commit
        self.ciRun = ciRun
    }

    /// 未知 / 未注入时统一显示的值。
    public static let unknown = "—"

    /// 从任意 `infoDictionary`（形如 Bundle.main.infoDictionary）解析。
    /// 缺键或空串时回退到 `unknown`，不崩溃。
    public init(infoDictionary: [String: Any]?) {
        func value(_ key: String) -> String {
            guard let raw = infoDictionary?[key] as? String else { return Self.unknown }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            // 构建时未注入时 plist 里可能残留 "$(GIT_COMMIT)" 这类未展开的占位符。
            if trimmed.isEmpty || trimmed.hasPrefix("$(") { return Self.unknown }
            return trimmed
        }
        self.version = value("CFBundleShortVersionString")
        self.commit = value("BuildCommit")
        self.ciRun = value("BuildCIRun")
    }

    /// 从真实 Bundle 读取（App 运行时用）。
    public static func fromMainBundle() -> AppBuildInfo {
        AppBuildInfo(infoDictionary: Bundle.main.infoDictionary)
    }

    /// 供界面展示的一行摘要，例如：`1.0.0 · commit 315b58e · CI 37313519896`。
    public var summary: String {
        "\(version) · commit \(commit) · CI \(ciRun)"
    }
}
