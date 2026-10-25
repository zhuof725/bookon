import Foundation
import CoreFoundation

/// 书源导入结果：原版 Gson 是宽松解析，网上的书源经常带尾逗号、注释、单引号，
/// 或者数组中夹着一条坏数据。这里逐条解析，坏项只记失败原因，不影响其余书源。
struct SourceImportReport: Equatable {
    var imported: Int = 0
    var failed: Int = 0
    var failures: [String] = []

    var summary: String {
        if failed == 0 { return "成功导入 \(imported) 条书源" }
        var text = "成功 \(imported) 条、失败 \(failed) 条"
        if let first = failures.first { text += "（\(first)）" }
        return text
    }
}

struct SourceImportOutcome {
    var sources: [BookSource]
    var report: SourceImportReport
}

enum SourceImportError: LocalizedError {
    case empty
    case unreadable(String)

    var errorDescription: String? {
        switch self {
        case .empty: return "没有可导入的内容"
        case .unreadable(let detail): return "无法解析书源 JSON：\(detail)"
        }
    }
}

enum SourceImportParser {
    /// 宽松解析：JSON5（注释、尾逗号、单引号）+ 数组逐项恢复 + 单对象/JSONL。
    static func parse(_ text: String) throws -> SourceImportOutcome {
        var t = text
        if t.hasPrefix("\u{FEFF}") { t.removeFirst() }
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { throw SourceImportError.empty }

        var report = SourceImportReport()
        var items: [Any] = []

        // 标准 JSON 直接解码：完全合法的导出文件优先走这条。
        // 不经过 JSONSerialization 的「字典 → JSON」往返，规则里的控制字符
        // （例如番茄畅听 subContent 用 \u0000 做分隔）不会被改写。
        if let data = t.data(using: .utf8) {
            func usable(_ source: BookSource) -> Bool {
                !source.bookSourceUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            if let direct = try? JSONDecoder().decode([BookSource].self, from: data) {
                let good = direct.filter(usable)
                if !good.isEmpty {
                    report.imported = good.count
                    report.failed = direct.count - good.count
                    return SourceImportOutcome(sources: good, report: report)
                }
            }
            if let one = try? JSONDecoder().decode(BookSource.self, from: data), usable(one) {
                report.imported = 1
                return SourceImportOutcome(sources: [one], report: report)
            }
        }

        if let root = jsonObject(t) {
            items = unwrappedItems(root)
        } else {
            // 整段 JSON 坏了：按顶层 {} 切开，逐条解析，坏项不再拖垮整批。
            let chunks = topLevelObjects(in: t)
            if !chunks.isEmpty {
                for (index, chunk) in chunks.enumerated() {
                    if let obj = jsonObject(chunk) {
                        items.append(obj)
                    } else {
                        report.failed += 1
                        report.failures.append("第 \(index + 1) 条：JSON 语法错误 \(snippet(chunk))")
                    }
                }
            } else {
                // JSON Lines：一行一个书源对象。
                let lines = t.components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { $0.hasPrefix("{") }
                for (index, line) in lines.enumerated() {
                    if let obj = jsonObject(line) { items.append(obj) }
                    else {
                        report.failed += 1
                        report.failures.append("第 \(index + 1) 条：JSON 语法错误 \(snippet(line))")
                    }
                }
            }
            if items.isEmpty && report.failed == 0 {
                throw SourceImportError.unreadable(snippet(t))
            }
        }

        var sources: [BookSource] = []
        for (index, item) in items.enumerated() {
            guard let dict = item as? [String: Any] else {
                report.failed += 1
                report.failures.append("第 \(index + 1) 条：不是书源对象")
                continue
            }
            do {
                let data = try jsonData(dict)
                let source = try JSONDecoder().decode(BookSource.self, from: data)
                guard !source.bookSourceUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    report.failed += 1
                    report.failures.append("第 \(index + 1) 条：缺少 bookSourceUrl")
                    continue
                }
                sources.append(source)
            } catch {
                report.failed += 1
                let name = (dict["bookSourceName"] as? String) ?? (dict["bookSourceUrl"] as? String) ?? "第 \(index + 1) 条"
                report.failures.append("\(name)：\(error.localizedDescription)")
            }
        }
        report.imported = sources.count
        return SourceImportOutcome(sources: sources, report: report)
    }

    /// 支持 `{"sources":[...]}` / `{"bookSources":[...]}` 这类导出包装。
    private static func unwrappedItems(_ root: Any) -> [Any] {
        if let array = root as? [Any] { return array }
        if let dict = root as? [String: Any] {
            for key in ["sources", "bookSources", "bookSourceList", "data"] {
                if let array = dict[key] as? [Any] { return array }
            }
            return [dict]
        }
        return []
    }

    private static func jsonObject(_ text: String) -> Any? {
        guard let data = text.data(using: .utf8) else { return nil }
        // .json5Allowed：注释、尾逗号、单引号、无引号键；Gson 宽松模式能读的常见写法都覆盖。
        return try? JSONSerialization.jsonObject(with: data, options: [.json5Allowed, .fragmentsAllowed])
    }

    /// 扫描顶层对象（跳过字符串与注释），用于一条坏数据时的逐项恢复。
    private static func topLevelObjects(in text: String) -> [String] {
        var chunks: [String] = []
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "/" && i + 1 < chars.count {
                if chars[i + 1] == "/" {
                    i += 2
                    while i < chars.count && chars[i] != "\n" { i += 1 }
                    continue
                }
                if chars[i + 1] == "*" {
                    i += 2
                    while i + 1 < chars.count && !(chars[i] == "*" && chars[i + 1] == "/") { i += 1 }
                    i = min(i + 2, chars.count)
                    continue
                }
            }
            guard c == "{" else { i += 1; continue }
            let start = i
            var depth = 0
            var quote: Character?
            var escaped = false
            while i < chars.count {
                let ch = chars[i]
                if let q = quote {
                    if escaped { escaped = false }
                    else if ch == "\\" { escaped = true }
                    else if ch == q { quote = nil }
                } else if ch == "\"" || ch == "'" {
                    quote = ch
                } else if ch == "/" && i + 1 < chars.count && chars[i + 1] == "/" {
                    i += 2
                    while i < chars.count && chars[i] != "\n" { i += 1 }
                    continue
                } else if ch == "/" && i + 1 < chars.count && chars[i + 1] == "*" {
                    i += 2
                    while i + 1 < chars.count && !(chars[i] == "*" && chars[i + 1] == "/") { i += 1 }
                    i = min(i + 2, chars.count)
                    continue
                } else if ch == "{" {
                    depth += 1
                } else if ch == "}" {
                    depth -= 1
                    if depth == 0 {
                        i += 1
                        chunks.append(String(chars[start..<i]))
                        break
                    }
                }
                i += 1
            }
        }
        return chunks
    }

    /// 把解析出来的字典写成 JSON 文本。
    /// 不用 `JSONSerialization.data(withJSONObject:)`：它会改写字符串里的控制字符，
    /// 番茄畅听 v2 的 subContent 用 \u0000 做分隔，丢了整条规则就变了。
    private static func jsonData(_ value: Any) throws -> Data {
        guard let data = jsonText(value).data(using: .utf8) else {
            throw SourceImportError.unreadable("无法写出 JSON")
        }
        return data
    }

    private static func jsonText(_ value: Any) throws -> String {
        switch value {
        case is NSNull:
            return "null"
        case let string as String:
            return quoted(string)
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "true" : "false"
            }
            let double = number.doubleValue
            if double.rounded() == double,
               double >= Double(Int64.min), double <= Double(Int64.max) {
                return String(number.int64Value)
            }
            return String(double)
        case let array as [Any]:
            return "[" + (try array.map { try jsonText($0) }.joined(separator: ",")) + "]"
        case let object as [String: Any]:
            let body = try object.map { key, value in
                quoted(key) + ":" + (try jsonText(value))
            }.joined(separator: ",")
            return "{" + body + "}"
        default:
            return quoted(String(describing: value))
        }
    }

    private static func quoted(_ string: String) -> String {
        var out = "\""
        for scalar in string.unicodeScalars {
            switch scalar.value {
            case 0x22: out += "\\\""
            case 0x5C: out += "\\\\"
            case 0x0A: out += "\\n"
            case 0x0D: out += "\\r"
            case 0x09: out += "\\t"
            case 0x08: out += "\\b"
            case 0x0C: out += "\\f"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }

    private static func snippet(_ text: String, limit: Int = 80) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        return flat.count > limit ? String(flat.prefix(limit)) + "…" : flat
    }
}
