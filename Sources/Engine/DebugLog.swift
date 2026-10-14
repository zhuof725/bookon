import Foundation

/// 只在用户主动调试时记录。日志留在内存，不上传，不保存 Cookie/Authorization/请求体。
enum DebugLog {
    private static let lock = NSLock()
    private static var active = false
    private static var entries: [String] = []

    static func begin() {
        lock.lock(); defer { lock.unlock() }
        entries.removeAll(); active = true
    }
    static func end() { lock.lock(); active = false; lock.unlock() }
    static func add(_ message: String) {
        lock.lock(); defer { lock.unlock() }
        guard active else { return }
        entries.append(message)
        if entries.count > 400 { entries.removeFirst(entries.count - 400) }
    }
    static func snapshot() -> String {
        lock.lock(); defer { lock.unlock() }
        return entries.joined(separator: "\n")
    }
    static func url(_ raw: String) -> String {
        if raw.hasPrefix("data:") { return "data:（本地数据URL，内容省略）" }
        let plain = raw.components(separatedBy: ",{").first ?? raw
        guard var components = URLComponents(string: plain) else { return "（无法解析URL）" }
        components.user = nil; components.password = nil
        components.queryItems = components.queryItems?.map { item in
            let name = item.name.lowercased()
            if ["token", "sign", "auth", "cookie", "password", "secret", "key", "device", "uid", "guid"].contains(where: { name.contains($0) }) {
                return URLQueryItem(name: item.name, value: "[已隐藏]")
            }
            return item
        }
        return String((components.string ?? "（无URL）").prefix(600))
    }
    static func summary(_ body: String) -> String {
        if let data = body.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: data) {
            if let dict = obj as? [String: Any] { return "JSON 顶层字段：" + dict.keys.sorted().joined(separator: ", ") }
            if let list = obj as? [Any] { return "JSON 数组：\(list.count) 项" }
        }
        if body.isEmpty { return "响应为空" }
        if let r = body.range(of: "<title[^>]*>([^<]*)</title>", options: [.regularExpression, .caseInsensitive]) {
            let title = body[r].replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            return "HTML 标题：" + String(title.prefix(100))
        }
        return "不是JSON / 无HTML标题"
    }

    /// 只统计形态，不记录正文内容：用于判断正文是解码失败、编码错误还是确实为空。
    static func shape(_ text: String) -> String {
        let scalars = Array(text.unicodeScalars)
        let total = max(scalars.count, 1)
        let han = scalars.filter { (0x4E00...0x9FFF).contains($0.value) }.count
        let replacement = scalars.filter { $0.value == 0xFFFD }.count
        let ascii = scalars.filter { $0.value < 0x80 }.count
        let latin = scalars.filter { (0x80...0xFF).contains($0.value) }.count
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let base64 = trimmed.range(of: "^[A-Za-z0-9+/]+={0,2}$", options: .regularExpression) != nil
        let innerPad = trimmed.dropLast(2).contains("=")
        let boundaries = paragraphBoundaryShape(text)
        let recovered = WebBook.normalizeParagraphBoundaries(text).components(separatedBy: "\n").count - 1
        let images = text.components(separatedBy: "<img").count - 1
        let divs = text.components(separatedBy: "<div").count - 1
        let comments = text.components(separatedBy: "<comment").count - 1
        return "汉字 \(han)/\(total)，替换字符 \(replacement)，ASCII \(ascii)，Latin1 \(latin)，base64 形态 \(base64 ? "是" : "否")，内部含 = \(innerPad ? "是" : "否")，换行 \(text.components(separatedBy: "\n").count - 1)，全角空格 \(text.filter { $0 == "\u{3000}" }.count)"
            + "，段界候选 \(boundaries.candidates)（句末标点 \(boundaries.afterMark)／闭引号 \(boundaries.afterQuote)／汉字 \(boundaries.afterHan)／行首 \(boundaries.afterLineStart)／其他 \(boundaries.afterOther)）"
            + "，标签 img \(images)/div \(divs)/comment \(comments)，还原后换行 \(recovered)"
    }

    /// 只统计「全角空格前一个字符属于哪一类」，不输出任何正文片段。
    /// 用于判断段落边界是否是我们支持的形态（句末标点/闭引号 + U+3000）。
    private static func paragraphBoundaryShape(_ text: String) -> (candidates: Int, afterMark: Int, afterQuote: Int, afterHan: Int, afterLineStart: Int, afterOther: Int) {
        let marks: Set<Character> = ["。", "！", "？", "!", "?", "…"]
        let closers: Set<Character> = ["”", "’", "」", "』", "》", "〉", "】", "〕", "〗", "〙", "〛", "\"", "'", ")", "]", "}"]
        let characters = Array(text)
        var candidates = 0, afterMark = 0, afterQuote = 0, afterHan = 0, afterLineStart = 0, afterOther = 0
        for (index, character) in characters.enumerated() where character == "\u{3000}" {
            guard index > 0 else { afterLineStart += 1; continue }
            let previous = characters[index - 1]
            if marks.contains(previous) {
                afterMark += 1; candidates += 1
            } else if closers.contains(previous) {
                afterQuote += 1; candidates += 1
            } else if previous == "\n" {
                afterLineStart += 1
            } else if previous.unicodeScalars.first.map({ (0x4E00...0x9FFF).contains($0.value) }) == true {
                afterHan += 1
            } else {
                afterOther += 1
            }
        }
        return (candidates, afterMark, afterQuote, afterHan, afterLineStart, afterOther)
    }
}
