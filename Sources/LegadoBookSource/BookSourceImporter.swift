//
//  BookSourceImporter.swift
//  LegadoBookSource
//
//  书源导入器。
//  - 输入可以是单个书源对象，也可以是书源数组。
//  - 单个书源解析失败不影响其他书源。
//  - 返回「成功列表」、「失败原因列表」与「警告列表」。
//
//  该行为对应 legado 导入书源时「逐条容错」的思路：
//  一份 JSON 里某个书源坏了，不应该导致整份导入失败。
//

import Foundation

/// 单条书源导入失败的信息。
public struct BookSourceImportFailure {
    /// 出错书源在原始数组中的下标（顶层为单对象时为 0）。
    public let index: Int
    /// 该书源的原始 JSON 片段（便于定位问题）。
    public let rawJSON: String
    /// 失败原因。
    public let error: Error
    /// 失败原因的可读描述。
    public var reason: String { (error as NSError).localizedDescription }

    public init(index: Int, rawJSON: String, error: Error) {
        self.index = index
        self.rawJSON = rawJSON
        self.error = error
    }
}

/// 导入结果：成功列表 + 失败原因列表 + 警告列表。
public struct BookSourceImportResult {
    /// 成功解析的书源。
    public let successes: [BookSource]
    /// 解析失败的条目。
    public let failures: [BookSourceImportFailure]
    /// 非致命警告（例如某个规则字段是 JSON 字符串但内层解析失败，已被置空）。
    public let warnings: [DecodingWarning]

    public var isAllSuccess: Bool { failures.isEmpty }

    public init(successes: [BookSource],
                failures: [BookSourceImportFailure],
                warnings: [DecodingWarning]) {
        self.successes = successes
        self.failures = failures
        self.warnings = warnings
    }
}

/// 导入过程中可能抛出的顶层错误。
public enum BookSourceImportError: Error, LocalizedError {
    /// 输入既不是 JSON 对象也不是 JSON 数组。
    case invalidTopLevelJSON
    /// 输入不是合法 UTF-8。
    case invalidEncoding

    public var errorDescription: String? {
        switch self {
        case .invalidTopLevelJSON:
            return "输入不是合法的 JSON 对象或数组"
        case .invalidEncoding:
            return "输入不是合法的 UTF-8 文本"
        }
    }
}

public enum BookSourceImporter {

    /// 从 JSON 文本导入。
    /// - Parameter jsonString: 单个书源对象，或书源数组的 JSON 文本。
    /// - Returns: 成功列表、失败原因列表与警告列表。
    /// - Throws: 仅当顶层 JSON 结构完全无法识别时抛出（invalidTopLevelJSON / invalidEncoding）。
    public static func importSources(fromJSONString jsonString: String) throws -> BookSourceImportResult {
        guard let data = jsonString.data(using: .utf8) else {
            throw BookSourceImportError.invalidEncoding
        }
        return try importSources(fromData: data)
    }

    /// 从 JSON Data 导入。
    public static func importSources(fromData data: Data) throws -> BookSourceImportResult {
        // 先用 JSONSerialization 判定顶层结构（对象 or 数组），
        // 再对每一条单独用 Codable 解码，做到逐条容错。
        let top = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])

        if let array = top as? [Any] {
            return importFromArray(array)
        } else if top is [String: Any] {
            // 单个书源对象
            return importFromSingle(data)
        } else {
            throw BookSourceImportError.invalidTopLevelJSON
        }
    }

    /// 从已经是数组的 JSON 元素逐条导入。
    private static func importFromArray(_ array: [Any]) -> BookSourceImportResult {
        var successes: [BookSource] = []
        var failures: [BookSourceImportFailure] = []
        var warnings: [DecodingWarning] = []

        for (idx, element) in array.enumerated() {
            // 把单个元素重新序列化成 Data，再单独解码，实现逐条隔离。
            let elementData: Data
            do {
                elementData = try JSONSerialization.data(withJSONObject: element, options: [.fragmentsAllowed])
            } catch {
                failures.append(
                    BookSourceImportFailure(
                        index: idx,
                        rawJSON: String(describing: element),
                        error: error
                    )
                )
                continue
            }

            let collector = DecodingWarningCollector()
            let decoder = LegadoJSON.decoder(collectingWarningsInto: collector)
            do {
                let source = try decoder.decode(BookSource.self, from: elementData)
                successes.append(source)
                // 给每条警告标注它属于哪个书源下标。
                warnings.append(contentsOf: collector.drain().map { annotate($0, index: idx) })
            } catch {
                let raw = String(data: elementData, encoding: .utf8) ?? String(describing: element)
                failures.append(
                    BookSourceImportFailure(index: idx, rawJSON: raw, error: error)
                )
                // 即使该条失败，之前累积的警告也带出来（便于诊断）。
                warnings.append(contentsOf: collector.drain().map { annotate($0, index: idx) })
            }
        }

        return BookSourceImportResult(successes: successes, failures: failures, warnings: warnings)
    }

    /// 从单个书源对象的 Data 导入。
    private static func importFromSingle(_ data: Data) -> BookSourceImportResult {
        let collector = DecodingWarningCollector()
        let decoder = LegadoJSON.decoder(collectingWarningsInto: collector)
        do {
            let source = try decoder.decode(BookSource.self, from: data)
            return BookSourceImportResult(
                successes: [source],
                failures: [],
                warnings: collector.drain().map { annotate($0, index: 0) }
            )
        } catch {
            let raw = String(data: data, encoding: .utf8) ?? ""
            return BookSourceImportResult(
                successes: [],
                failures: [BookSourceImportFailure(index: 0, rawJSON: raw, error: error)],
                warnings: collector.drain().map { annotate($0, index: 0) }
            )
        }
    }

    /// 把书源数组导出为 JSON 文本（统一对象形式的规则字段）。
    public static func exportSources(_ sources: [BookSource], pretty: Bool = false) throws -> String {
        let encoder = pretty ? LegadoJSON.prettyEncoder : LegadoJSON.encoder
        let data = try encoder.encode(sources)
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// 在警告信息前补充书源下标，便于定位。
    private static func annotate(_ w: DecodingWarning, index: Int) -> DecodingWarning {
        DecodingWarning(
            field: w.field,
            message: "[书源#\(index)] \(w.message)",
            rawSnippet: w.rawSnippet
        )
    }
}
