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
        return "汉字 \(han)/\(total)，替换字符 \(replacement)，ASCII \(ascii)，Latin1 \(latin)，base64 形态 \(base64 ? "是" : "否")，内部含 = \(innerPad ? "是" : "否")"
    }
}
