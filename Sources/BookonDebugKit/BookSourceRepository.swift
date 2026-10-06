//
//  BookSourceRepository.swift
//  BookonDebugKit
//
//  第 7 步 B 段：书源仓库（导入 / 持久化 / 启用开关 / 搜索）。
//  全部非界面逻辑，用 @Observable（Observation 框架），供 SwiftUI App 与测试复用。
//
//  导入来源：粘贴/剪贴板文本（importSources(jsonText:)）、文件（importSources(fileURL:)）、
//  URL（importSources(url:)，可注入 fetcher 以便测试）。
//  持久化：Documents/sources.json，原子写（write options .atomic），启动时加载。
//

import Foundation
import Observation
import LegadoBookSource

/// URL 数据抓取抽象（可注入，测试用假实现避免真实网络）。
public typealias BookSourceURLFetcher = (URL) async throws -> Data

/// 默认 URL 抓取：URLSession.shared（Linux 类型检查环境无 URLSession，抛错占位）。
public enum BookSourceFetcher {
    public static func urlSession(_ url: URL) async throws -> Data {
        #if os(macOS) || os(iOS)
        let (data, _) = try await URLSession.shared.data(from: url)
        return data
        #else
        throw RuleEngineError.unsupported("URLSession 不可用（Linux 类型检查环境）")
        #endif
    }
}

@Observable
public final class BookSourceRepository {

    /// 当前书源列表（按 customOrder 排序）。
    public private(set) var sources: [BookSource] = []
    /// 搜索关键字。
    public var searchText: String = ""

    /// 最近一次导入/保存的报错信息（非致命，供 UI 展示）。
    public private(set) var lastError: String?

    private let storageURL: URL
    private let fetcher: BookSourceURLFetcher

    public init(storageURL: URL? = nil,
                fetcher: @escaping BookSourceURLFetcher = BookSourceFetcher.urlSession) {
        self.storageURL = storageURL ?? Self.defaultStorageURL()
        self.fetcher = fetcher
        load()
    }

    /// Documents/sources.json
    public static func defaultStorageURL() -> URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return dir.appendingPathComponent("sources.json")
    }

    // MARK: - 导入

    /// 从 JSON 文本导入（粘贴 / 剪贴板）。
    /// 支持 `[BookSource]` 数组或单个 BookSource 对象；同名 bookSourceUrl 覆盖旧值。
    @discardableResult
    public func importSources(jsonText: String) throws -> Int {
        let imported = try Self.decodeSources(from: Data(jsonText.utf8))
        merge(imported)
        try save()
        return imported.count
    }

    /// 从文件导入。
    @discardableResult
    public func importSources(fileURL: URL) throws -> Int {
        let data = try Data(contentsOf: fileURL)
        let imported = try Self.decodeSources(from: data)
        merge(imported)
        try save()
        return imported.count
    }

    /// 从 URL 下载并导入（可注入 fetcher）。
    @discardableResult
    public func importSources(url: URL) async throws -> Int {
        let data = try await fetcher(url)
        let imported = try Self.decodeSources(from: data)
        merge(imported)
        try save()
        return imported.count
    }

    /// 剪贴板文本导入（等价 importSources(jsonText:)）。
    @discardableResult
    public func importFromClipboard(_ text: String) throws -> Int {
        try importSources(jsonText: text)
    }

    /// 从 JSON 文本导入，并返回**完整结果**（成功条数 / 失败原因列表 / 警告）。
    ///
    /// 与 `importSources(jsonText:)` 的区别：后者只返回成功条数，失败条目被静默丢弃；
    /// 导入面板需要把失败原因与警告原样展示给用户，故提供本方法。
    /// 解析失败（顶层 JSON 非法 / 非 UTF-8）仍按原样抛错。
    @discardableResult
    public func importSourcesDetailed(jsonText: String) throws -> ImportOutcome {
        let result = try BookSourceImporter.importSources(fromJSONString: jsonText)
        merge(result.successes)
        try save()
        return ImportOutcome(
            importedCount: result.successes.count,
            failures: result.failures.map { ImportOutcome.Failure(index: $0.index, reason: $0.reason) },
            warnings: result.warnings.map { warning in
                ImportOutcome.Warning(field: warning.field, message: warning.message)
            }
        )
    }

    /// 从 URL 下载并导入，返回完整结果（供导入面板的「URL 下载」入口）。
    @discardableResult
    public func importSourcesDetailed(url: URL) async throws -> ImportOutcome {
        let data = try await fetcher(url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw BookSourceImportError.invalidEncoding
        }
        return try importSourcesDetailed(jsonText: text)
    }

    /// 从本地文件读取并导入，返回完整结果（供导入面板的「选择文件」入口）。
    @discardableResult
    public func importSourcesDetailed(fileURL: URL) throws -> ImportOutcome {
        let data = try Data(contentsOf: fileURL)
        guard let text = String(data: data, encoding: .utf8) else {
            throw BookSourceImportError.invalidEncoding
        }
        return try importSourcesDetailed(jsonText: text)
    }

    // MARK: - 启用开关

    public func setEnabled(_ enabled: Bool, sourceUrl: String) {
        guard let idx = sources.firstIndex(where: { $0.bookSourceUrl == sourceUrl }) else { return }
        sources[idx].enabled = enabled
        try? save()
    }

    public func toggleEnabled(sourceUrl: String) {
        guard let idx = sources.firstIndex(where: { $0.bookSourceUrl == sourceUrl }) else { return }
        sources[idx].enabled.toggle()
        try? save()
    }

    // MARK: - 搜索 / 过滤

    public func search(_ query: String) {
        searchText = query
    }

    /// 按搜索关键字过滤后的书源（名称或 URL 模糊匹配）。
    public var filteredSources: [BookSource] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return sources }
        return sources.filter {
            $0.bookSourceName.localizedCaseInsensitiveContains(q)
                || $0.bookSourceUrl.localizedCaseInsensitiveContains(q)
        }
    }

    // MARK: - 持久化

    public func save() throws {
        let data = try LegadoJSON.prettyEncoder.encode(sources)
        try data.write(to: storageURL, options: .atomic)
        lastError = nil
    }

    // MARK: - 内部

    static func decodeSources(from data: Data) throws -> [BookSource] {
        // 先按数组解，失败再按单个对象解（兼容两种形态）。
        if let arr = try? LegadoJSON.decoder.decode([BookSource].self, from: data) {
            return arr
        }
        let single = try LegadoJSON.decoder.decode(BookSource.self, from: data)
        return [single]
    }

    private func merge(_ imported: [BookSource]) {
        var map: [String: BookSource] = [:]
        for s in sources { map[s.bookSourceUrl] = s }
        for s in imported { map[s.bookSourceUrl] = s }
        sources = map.values.sorted { $0.customOrder < $1.customOrder }
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let arr = try? LegadoJSON.decoder.decode([BookSource].self, from: data) else {
            sources = []
            return
        }
        sources = arr
    }
}
