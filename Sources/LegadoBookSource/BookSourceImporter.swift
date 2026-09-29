//
//  BookSourceImporter.swift
//  LegadoBookSource
//
//  书源导入器。
//  - 输入可以是单个书源对象，也可以是书源数组。
//  - 单个书源解析失败不影响其他书源。
//  - 返回「成功列表」与「失败原因列表」。
//
//  该行为对应 legado 导入书源时「逐条容错」的思路：
//  一份 JSON 里某个书源坏了，不应该导致整份导入失败。
//

import Foundation

/// 单条书源导入失败的信息。
struct BookSourceImportFailure {
    /// 出错书源在原始数组中的下标（顶层为单对象时为 0）。
    let index: Int
    /// 该书源的原始 JSON 片段（便于定位问题）。
    let rawJSON: String
    /// 失败原因。
    let error: Error
    /// 失败原因的可读描述。
    var reason: String { (error as NSError).localizedDescription }
}

/// 导入结果：成功列表 + 失败原因列表。
struct BookSourceImportResult {
    /// 成功解析的书源。
    let successes: [BookSource]
    /// 解析失败的条目。
    let failures: [BookSourceImportFailure]

    var isAllSuccess: Bool { failures.isEmpty }
}

/// 导入过程中可能抛出的顶层错误。
enum BookSourceImportError: Error, LocalizedError {
    /// 输入既不是 JSON 对象也不是 JSON 数组。
    case invalidTopLevelJSON
    /// 输入不是合法 UTF-8。
    case invalidEncoding

    var errorDescription: String? {
        switch self {
        case .invalidTopLevelJSON:
            return "输入不是合法的 JSON 对象或数组"
        case .invalidEncoding:
            return "输入不是合法的 UTF-8 文本"
        }
    }
}

enum BookSourceImporter {

    /// 从 JSON 文本导入。
    /// - Parameter jsonString: 单个书源对象，或书源数组的 JSON 文本。
    /// - Returns: 成功列表与失败原因列表。
    /// - Throws: 仅当顶层 JSON 结构完全无法识别时抛出（invalidTopLevelJSON / invalidEncoding）。
    static func importSources(fromJSONString jsonString: String) throws -> BookSourceImportResult {
        guard let data = jsonString.data(using: .utf8) else {
            throw BookSourceImportError.invalidEncoding
        }
        return try importSources(fromData: data)
    }

    /// 从 JSON Data 导入。
    static func importSources(fromData data: Data) throws -> BookSourceImportResult {
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

            do {
                let source = try LegadoJSON.decoder.decode(BookSource.self, from: elementData)
                successes.append(source)
            } catch {
                let raw = String(data: elementData, encoding: .utf8) ?? String(describing: element)
                failures.append(
                    BookSourceImportFailure(index: idx, rawJSON: raw, error: error)
                )
            }
        }

        return BookSourceImportResult(successes: successes, failures: failures)
    }

    /// 从单个书源对象的 Data 导入。
    private static func importFromSingle(_ data: Data) -> BookSourceImportResult {
        do {
            let source = try LegadoJSON.decoder.decode(BookSource.self, from: data)
            return BookSourceImportResult(successes: [source], failures: [])
        } catch {
            let raw = String(data: data, encoding: .utf8) ?? ""
            return BookSourceImportResult(
                successes: [],
                failures: [BookSourceImportFailure(index: 0, rawJSON: raw, error: error)]
            )
        }
    }

    /// 把书源数组导出为 JSON 文本（统一对象形式的规则字段）。
    static func exportSources(_ sources: [BookSource], pretty: Bool = false) throws -> String {
        let encoder = pretty ? LegadoJSON.prettyEncoder : LegadoJSON.encoder
        let data = try encoder.encode(sources)
        return String(data: data, encoding: .utf8) ?? ""
    }
}
