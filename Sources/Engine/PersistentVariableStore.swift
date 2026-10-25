import Foundation

/// 对应原版 CacheManager 的书源变量存储：书源脚本里的
/// `source.setVariable` / `source.getVariable` / `java.put` / `java.get` / `java.cache`
/// 都落在 Application Support，重启应用后仍能读回（「段评开关」等设置因此记住）。
/// 仅本机、不联网、不加密（原版存在缓存数据库，这里为 JSON 文件，内容与书源自身写入一致）。
/// 全局共享的书源变量存储：JSEngine 与详情面板 WebView 桥共用同一份。
enum SourceVariableStore {
    static let shared = PersistentVariableStore(fileURL: PersistentVariableStore.defaultFileURL())
}

final class PersistentVariableStore: @unchecked Sendable {
    private let fileURL: URL
    private let lock = NSLock()
    private var values: [String: String]
    private var writeScheduled = false

    init(fileURL: URL) {
        self.fileURL = fileURL
        if let data = try? Data(contentsOf: fileURL),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
            values = obj
        } else {
            values = [:]
        }
    }

    static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("LegadoVariables", isDirectory: true)
            .appendingPathComponent("variables.json")
    }

    func get(_ key: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return values[key]
    }

    func set(_ key: String, _ value: String) {
        lock.lock()
        let changed = values[key] != value
        values[key] = value
        lock.unlock()
        if changed { scheduleWrite() }
    }

    func remove(_ key: String) {
        lock.lock()
        let removed = values.removeValue(forKey: key) != nil
        lock.unlock()
        if removed { scheduleWrite() }
    }

    /// 写盘合并：短时间内的多次写入只落盘一次，避免书源高频 put 造成卡顿。
    private func scheduleWrite() {
        lock.lock()
        if writeScheduled { lock.unlock(); return }
        writeScheduled = true
        lock.unlock()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.flush()
        }
    }

    /// 立即落盘；应用进后台等时机也应调用。
    func flush() {
        lock.lock()
        writeScheduled = false
        let snapshot = values
        lock.unlock()
        do {
            let dir = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys])
            #if os(iOS)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #else
            try data.write(to: fileURL, options: .atomic)
            #endif
            var u = fileURL
            var rv = URLResourceValues(); rv.isExcludedFromBackup = true
            try? u.setResourceValues(rv)
        } catch {
            // 磁盘失败不影响本次阅读会话；不输出任何值，避免把书源变量写进日志。
        }
    }
}
