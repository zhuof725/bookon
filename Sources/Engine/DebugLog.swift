import Foundation

/// 只在用户主动调试时记录。日志留在内存，不上传，不保存 Cookie/Authorization/请求头。
/// 每行带 [mm:ss.SSS] 时间戳，与 Legado 原版调试页一致。
enum DebugLog {
    private static let lock = NSLock()
    private static var active = false
    private static var entries: [String] = []
    private static var startedAt = Date()

    /// 当前调试阶段：10 搜索/发现、20 详情、30 目录、40 正文（与原版 printLog state 一致）。
    private static var stage = 0
    private static var sources: [Int: String] = [:]

    static func begin() {
        lock.lock(); defer { lock.unlock() }
        entries.removeAll(); sources.removeAll(); stage = 0
        active = true; startedAt = Date()
    }

    static func setStage(_ value: Int) { lock.lock(); stage = value; lock.unlock() }

    /// 保存当前阶段最后一次请求的响应源码，供调试页「搜索源码/详情源码/目录源码/正文源码」查看。
    /// 只留在内存，不写盘、不上传；超大响应截断到 200k 字符。
    static func recordSource(_ body: String, stage value: Int) {
        lock.lock(); defer { lock.unlock() }
        guard active else { return }
        sources[value] = body.count > 200_000 ? String(body.prefix(200_000)) + "\n…（已截断）" : body
    }

    static func source(stage value: Int) -> String? {
        lock.lock(); defer { lock.unlock() }
        return sources[value]
    }
    static func end() { lock.lock(); active = false; lock.unlock() }
    static func add(_ message: String) {
        lock.lock(); defer { lock.unlock() }
        guard active else { return }
        entries.append("\(formatTime(Date().timeIntervalSince(startedAt))) \(message)")
        if entries.count > 1200 { entries.removeFirst(entries.count - 1200) }
    }
    /// 按条返回日志，调试页逐条显示（一条可含多行，如正文）。
    static func lines() -> [String] {
        lock.lock(); defer { lock.unlock() }
        return entries
    }
    static func snapshot() -> String {
        lock.lock(); defer { lock.unlock() }
        return entries.joined(separator: "\n")
    }

    /// 阅读器的点击链路诊断（点评论气泡的每一步）：**一直记录**，不管有没有在调试。
    /// 只留最近 80 行，不含 Cookie/请求头。
    private static var readerEntries: [String] = []

    static func readerAdd(_ message: String) {
        lock.lock(); defer { lock.unlock() }
        readerEntries.append("\(formatTime(Date().timeIntervalSince(startedAt))) \(message)")
        if readerEntries.count > 80 { readerEntries.removeFirst(readerEntries.count - 80) }
    }

    /// 阅读器诊断日志；调试页把它附在报告后面，方便用户反馈「点了没反应」时的现场。
    static func readerSnapshot() -> String {
        lock.lock(); defer { lock.unlock() }
        guard !readerEntries.isEmpty else { return "" }
        return "── 阅读器 ──\n" + readerEntries.joined(separator: "\n")
    }

    /// [mm:ss.SSS]，从本次调试开始计时；与 Legado 的 debugTimeFormat 一致。
    static func formatTime(_ seconds: TimeInterval) -> String {
        let totalMS = Int((max(0, seconds) * 1000).rounded())
        let minutes = totalMS / 60_000
        let secs = (totalMS % 60_000) / 1000
        let ms = totalMS % 1000
        return String(format: "[%02d:%02d.%03d]", minutes, secs, ms)
    }

    static func url(_ raw: String) -> String {
        // 与原版一样完整显示 data: 网址与请求选项 ,{...}；只隐藏查询参数里的敏感值。
        if raw.hasPrefix("data:") { return String(raw.prefix(4000)) }
        let parts = raw.components(separatedBy: ",{")
        let plain = parts.first ?? raw
        let options = parts.count > 1 ? ",{" + parts.dropFirst().joined(separator: ",{") : ""
        guard var components = URLComponents(string: plain) else { return "（无法解析URL）" }
        components.user = nil; components.password = nil
        components.queryItems = components.queryItems?.map { item in
            let name = item.name.lowercased()
            if ["token", "sign", "auth", "cookie", "password", "secret", "key", "device", "uid", "guid"].contains(where: { name.contains($0) }) {
                return URLQueryItem(name: item.name, value: "[已隐藏]")
            }
            return item
        }
        return String(((components.string ?? plain) + options).prefix(2000))
    }

    /// 响应行：与 Legado 一样在日志里单占一行，但只记录形态（字符数/JSON 字段/HTML 标题），不记录正文。
    static func bodyLine(_ body: String) -> String {
        if body.isEmpty { return "响应为空" }
        return "响应 \(body.count) 字符；\(summary(body))"
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
}
