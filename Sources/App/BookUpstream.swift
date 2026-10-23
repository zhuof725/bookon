import Foundation

/// 聚合源的「子源/上游」识别：书地址或章节地址里常见的标记字段。
enum BookUpstream {
    private static let keys = ["source", "src", "site", "platform", "from", "channel", "origin", "源"]

    static func name(for book: Book, toc: [BookChapter]? = nil) -> String? {
        if let name = fromURL(book.bookUrl) { return name }
        if let first = toc?.first, let name = fromURL(first.url) { return name }
        return nil
    }

    static func fromURL(_ raw: String) -> String? {
        if let range = raw.range(of: "base64,") {
            let rest = raw[range.upperBound...]
            let part = rest.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
            let trimmed = String(part).trimmingCharacters(in: .whitespacesAndNewlines)
            if let data = Data(base64Encoded: trimmed),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                for key in keys {
                    if let value = object[key] as? String, !value.isEmpty { return value }
                }
            }
        }
        if let items = URLComponents(string: raw)?.queryItems {
            for key in keys {
                if let value = items.first(where: { $0.name.lowercased() == key })?.value,
                   !value.isEmpty { return value }
            }
        }
        return nil
    }
}
