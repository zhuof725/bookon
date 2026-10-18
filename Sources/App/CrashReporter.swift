import Foundation

/// 崩溃日志：捕获未捕获异常与常见信号，连同最近的操作记录（面包屑）写入本机文件。
/// 用户可在「我的 → 崩溃日志」查看、复制或分享，便于反馈闪退原因。
///
/// - NSException：记录异常名/原因/调用栈（Foundation 可用，信息最全）。
/// - 信号（SIGABRT/SIGSEGV/SIGBUS/SIGILL/SIGFPE/SIGTRAP）：信号处理函数里只做
///   异步信号安全的操作（open/read/write），把信号号与面包屑写入 pending 文件，
///   下次启动时整理成正式报告。
/// - 上次会话没有正常进入后台就消失（未捕获异常以外的闪退/强杀）：用 session 标记补一条记录。
enum CrashReporter {
    struct Report: Identifiable {
        let url: URL
        let date: Date
        let kind: String
        let preview: String

        var id: URL { url }
        var contents: String { (try? String(contentsOf: url, encoding: .utf8)) ?? "" }
        var title: String {
            let formatter = DateFormatter()
            formatter.dateFormat = "MM-dd HH:mm:ss"
            return "\(formatter.string(from: date)) · \(kind)"
        }
    }

    static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("LegadoReading/crashes", isDirectory: true)
    }()

    private static let breadcrumbURL = directory.appendingPathComponent("breadcrumbs.log")
    private static let markerURL = directory.appendingPathComponent("session.active")
    private static let pendingSignalURL = directory.appendingPathComponent("pending-signal.txt")

    private static let lock = NSLock()
    private static var crumbs: [String] = []
    private static var installed = false

    // 信号处理里不能分配内存：路径与固定文本预先转成 C 数组，读文件用静态缓冲。
    private static var pendingPath: [CChar] = []
    private static var breadcrumbPath: [CChar] = []
    private static var signalBuffer = [CChar](repeating: 0, count: 64 * 1024)
    private static let signalPrefix: [CChar] = Array("signal=".utf8CString)
    private static let newlineByte: [CChar] = Array("\n".utf8CString)
    private static var digitBuffer = [CChar](repeating: 0, count: 16)

    // MARK: 安装

    static func install() {
        guard !installed else { return }
        installed = true
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        pendingPath = Array(pendingSignalURL.path.utf8CString)
        breadcrumbPath = Array(breadcrumbURL.path.utf8CString)
        promotePendingReports()
        note("启动 \(deviceSummary())")

        NSSetUncaughtExceptionHandler { exception in
            handleException(exception)
        }
        for sig in [SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGTRAP] {
            _ = signal(sig) { number in
                handleSignal(number)
                _ = signal(number, SIG_DFL)
                raise(number)
            }
        }
    }

    /// 进入后台说明上次运行是正常挂起/退出，不再把 session 标记当成异常结束。
    static func markSessionClean() {
        try? FileManager.default.removeItem(at: markerURL)
    }

    // MARK: 面包屑

    /// 记录一条最近操作。只在关键节点调用（开书、换章、加载失败等），不要放进滚动循环。
    static func note(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        let line = "[\(formatter.string(from: Date()))] \(message)\n"
        lock.lock()
        crumbs.append(line)
        if crumbs.count > 300 { crumbs.removeFirst(crumbs.count - 300) }
        lock.unlock()
        appendBreadcrumb(line)
    }

    private static func appendBreadcrumb(_ line: String) {
        guard let data = line.data(using: .utf8) else { return }
        if !FileManager.default.fileExists(atPath: breadcrumbURL.path) {
            try? data.write(to: breadcrumbURL)
            return
        }
        if let handle = try? FileHandle(forWritingTo: breadcrumbURL) {
            defer { try? handle.close() }
            try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        }
    }

    private static func readBreadcrumbs() -> String {
        (try? String(contentsOf: breadcrumbURL, encoding: .utf8)) ?? ""
    }

    // MARK: 报告整理

    /// 启动时把上次留下的 pending 信号记录 / 未正常结束标记整理成正式报告。
    private static func promotePendingReports() {
        let fm = FileManager.default
        if let pending = try? String(contentsOf: pendingSignalURL, encoding: .utf8), !pending.isEmpty {
            let report = reportHeader(kind: "信号崩溃（无调用栈）")
                + pending
                + "\n提示：完整调用栈可查看 iOS「设置 → 隐私与安全性 → 分析与改进 → 分析数据」里本 App 的 .ips 日志。\n"
            writeReport(report, kind: "signal")
            try? fm.removeItem(at: pendingSignalURL)
        } else if fm.fileExists(atPath: markerURL.path) {
            // 上次运行没有进入后台就消失了：多半是闪退（也可能是强制结束）。
            let report = reportHeader(kind: "上次会话异常结束（无异常信息）")
                + "最近操作：\n"
                + readBreadcrumbs()
            writeReport(report, kind: "session")
        }
        try? fm.removeItem(at: markerURL)
        try? "".write(to: breadcrumbURL, atomically: true, encoding: .utf8)
        try? "".write(to: markerURL, atomically: true, encoding: .utf8)
    }

    private static func handleException(_ exception: NSException) {
        var text = reportHeader(kind: "未捕获异常")
        text += "异常: \(exception.name.rawValue)\n"
        text += "原因: \(exception.reason ?? "-")\n"
        text += "调用栈:\n" + exception.callStackSymbols.joined(separator: "\n") + "\n"
        text += "最近操作：\n" + readBreadcrumbs()
        writeReport(text, kind: "exception")
    }

    private static func handleSignal(_ number: Int32) {
        guard !pendingPath.isEmpty else { return }
        let fd = pendingPath.withUnsafeBufferPointer {
            open($0.baseAddress!, O_CREAT | O_WRONLY | O_TRUNC, mode_t(0o644))
        }
        guard fd >= 0 else { return }
        signalPrefix.withUnsafeBufferPointer { _ = write(fd, $0.baseAddress, signalPrefix.count - 1) }
        var value = number
        var count = 0
        if value <= 0 {
            digitBuffer[0] = 48
            count = 1
        } else {
            while value > 0, count < digitBuffer.count {
                digitBuffer[count] = CChar(48 + value % 10)
                value /= 10
                count += 1
            }
        }
        // 从高位到低位逐字节写出（信号处理里不能分配内存）
        var index = count - 1
        while index >= 0 {
            digitBuffer.withUnsafeBufferPointer { _ = write(fd, $0.baseAddress! + index, 1) }
            index -= 1
        }
        newlineByte.withUnsafeBufferPointer { _ = write(fd, $0.baseAddress, 1) }
        if !breadcrumbPath.isEmpty {
            let bfd = breadcrumbPath.withUnsafeBufferPointer { open($0.baseAddress!, O_RDONLY) }
            if bfd >= 0 {
                signalBuffer.withUnsafeMutableBufferPointer { buffer in
                    let n = read(bfd, buffer.baseAddress, buffer.count)
                    if n > 0 { _ = write(fd, buffer.baseAddress, n) }
                }
                _ = close(bfd)
            }
        }
        _ = close(fd)
    }

    // MARK: 写入 / 查询

    private static func reportHeader(kind: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return "崩溃类型: \(kind)\n时间: \(formatter.string(from: Date()))\n\(deviceInfo())\n\n"
    }

    static func deviceInfo() -> String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "-"
        let build = info?["CFBundleVersion"] as? String ?? "-"
        let system = ProcessInfo.processInfo.operatingSystemVersionString
        var uts = utsname()
        var machine = "?"
        if uname(&uts) == 0 {
            machine = withUnsafeBytes(of: &uts.machine) { raw in
                String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
            }
        }
        return "应用: 阅读iOS \(version) (\(build))\n系统: \(system)\n设备: \(machine)"
    }

    private static func deviceSummary() -> String {
        deviceInfo().replacingOccurrences(of: "\n", with: " / ")
    }

    private static func writeReport(_ text: String, kind: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let name = "crash-\(formatter.string(from: Date()))-\(kind).txt"
        try? text.write(to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8)
        prune()
    }

    private static func prune() {
        let urls = reportURLs()
        guard urls.count > 20 else { return }
        for url in urls.dropFirst(20) { try? FileManager.default.removeItem(at: url) }
    }

    private static func reportURLs() -> [URL] {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(at: directory,
                                                     includingPropertiesForKeys: [.contentModificationDateKey]) else { return [] }
        return urls
            .filter { $0.lastPathComponent.hasPrefix("crash-") }
            .sorted { lhs, rhs in
                let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return l > r
            }
    }

    static func reports() -> [Report] {
        reportURLs().map { url in
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            let lines = text.components(separatedBy: "\n")
            let kind = lines.first?.replacingOccurrences(of: "崩溃类型: ", with: "") ?? "崩溃"
            let headerPrefixes = ["崩溃类型:", "时间:", "应用:", "系统:", "设备:", "提示:"]
            let preview = lines.first { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return !trimmed.isEmpty && !headerPrefixes.contains { trimmed.hasPrefix($0) }
            } ?? ""
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return Report(url: url, date: date, kind: kind, preview: String(preview.prefix(120)))
        }
    }

    static func delete(_ report: Report) {
        try? FileManager.default.removeItem(at: report.url)
    }

    static func deleteAll() {
        for url in reportURLs() { try? FileManager.default.removeItem(at: url) }
    }

    /// 全部报告拼成一段文本（复制/分享用）。
    static func combinedText() -> String {
        let reports = reports()
        guard !reports.isEmpty else { return "暂无崩溃日志" }
        return reports.map { report in
            "======== \(report.kind) ========\n" + report.contents
        }.joined(separator: "\n\n")
    }
}
