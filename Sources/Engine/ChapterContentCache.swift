import Foundation
import CryptoKit

/// 不能只用章 URL：不同书源/书籍可使用相同的相对或 API 地址。
struct ChapterContentKey: Hashable, Sendable {
    let sourceURL: String
    let bookURL: String
    let chapterURL: String

    fileprivate var fileName: String {
        let data = (try? JSONEncoder().encode([sourceURL, bookURL, chapterURL])) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() + ".txt"
    }
}

/// raw 正文缓存（保留段评标记）。actor 隔离磁盘读写与在途任务，网络工作不在 MainActor 上执行。
actor ChapterContentCache {
    static let shared = ChapterContentCache(directory: FileManager.default
        .urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("chapters/content-v2", isDirectory: true))

    enum CacheError: LocalizedError {
        case emptyContent
        var errorDescription: String? { "正文为空，请重试或检查书源" }
    }

    private struct Flight {
        let id: UUID
        let task: Task<String, Error>
    }
    private let directory: URL
    private let memoryLimit: Int
    private var memory: [ChapterContentKey: String] = [:]
    private var recent: [ChapterContentKey] = []
    private var flights: [ChapterContentKey: Flight] = [:]
    private var generation = UUID()

    var memoryEntryCount: Int { memory.count }

    /// A synchronous deletion closure runs on this actor, preventing chapter
    /// reads or writeback from interleaving with the purge.
    func invalidate<Result: Sendable>(_ removeFiles: @Sendable () -> Result) -> Result {
        generation = UUID()
        let oldFlights = Array(flights.values)
        flights.removeAll()
        memory.removeAll()
        recent.removeAll()
        oldFlights.forEach { $0.task.cancel() }
        return removeFiles()
    }
    /// 诊断计数，不含书名、地址或正文，可验证前台是否复用了预读请求。
    private(set) var coalescedRequestCount = 0

    init(directory: URL, memoryLimit: Int = 12) {
        self.directory = directory
        self.memoryLimit = max(memoryLimit, 0)
    }

    func cached(for key: ChapterContentKey) -> String? {
        if let raw = memory[key] {
            touch(key)
            return raw
        }
        guard let raw = try? String(contentsOf: directory.appendingPathComponent(key.fileName), encoding: .utf8),
              !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        remember(raw, for: key)
        return raw
    }

    /// 目录里的「已缓存」标识：只检查存在性，不读取正文、不占用内存 LRU。
    /// 目录可能有上千章，不能用 cached(for:) 逐章加载。
    func hasCached(for key: ChapterContentKey) -> Bool {
        if memory[key] != nil { return true }
        return FileManager.default.fileExists(atPath: directory.appendingPathComponent(key.fileName).path)
    }

    /// 预读尚未完成时，前台等待同一个 Task；不会再次调用 load。
    /// 一个等待者取消只停止其后续行为，不取消其他等待者共享的网络请求。
    func content(for key: ChapterContentKey, priority: TaskPriority = .userInitiated,
                 load: @escaping @Sendable () async throws -> String) async throws -> String {
        try Task.checkCancellation()
        let requestedGeneration = generation
        if let hit = cached(for: key) { return hit }
        let task: Task<String, Error>
        if let flight = flights[key] {
            coalescedRequestCount += 1
            task = flight.task
        } else {
            let id = UUID()
            task = Task.detached(priority: priority) {
                do {
                    let raw = try await load()
                    guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        throw CacheError.emptyContent
                    }
                    // 所有等待者拿到结果前先完成写盘，不依赖最早等待者是否已取消。
                    try await self.storeLoaded(raw, for: key, flightID: id)
                    return raw
                } catch {
                    await self.finishFlight(for: key, id: id)
                    throw error
                }
            }
            flights[key] = Flight(id: id, task: task)
        }
        let raw = try await task.value
        try Task.checkCancellation()
        guard generation == requestedGeneration else { throw CancellationError() }
        return raw
    }

    private func storeLoaded(_ raw: String, for key: ChapterContentKey, flightID: UUID) throws {
        // A loader may ignore cancellation. Only the currently registered flight may publish.
        guard flights[key]?.id == flightID else { throw CancellationError() }
        remember(raw, for: key)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try raw.write(to: directory.appendingPathComponent(key.fileName), atomically: true, encoding: .utf8)
        } catch {
            // 磁盘满时仍允许阅读已取到的正文；不把写盘错误当成书源请求失败。
        }
        finishFlight(for: key, id: flightID)
    }

    private func finishFlight(for key: ChapterContentKey, id: UUID) {
        if flights[key]?.id == id { flights[key] = nil }
    }

    private func touch(_ key: ChapterContentKey) {
        recent.removeAll { $0 == key }
        recent.append(key)
    }

    private func remember(_ raw: String, for key: ChapterContentKey) {
        guard memoryLimit > 0 else { return }
        memory[key] = raw
        touch(key)
        while recent.count > memoryLimit { memory[recent.removeFirst()] = nil }
    }
}
