import Foundation
import Darwin

enum AppCacheCategory: String, CaseIterable, Identifiable, Sendable {
    case content, catalog, network, all
    var id: String { rawValue }
}

struct AppCacheSnapshot: Sendable {
    let contentBytes: Int64
    let contentFiles: Int
    let contentMemoryEntries: Int
    let catalogBytes: Int64
    let catalogFiles: Int
    let networkDiskBytes: Int64
    let networkMemoryBytes: Int64
    let warnings: [String]
    static let empty = AppCacheSnapshot(contentBytes: 0, contentFiles: 0, contentMemoryEntries: 0,
        catalogBytes: 0, catalogFiles: 0, networkDiskBytes: 0, networkMemoryBytes: 0, warnings: [])
    var diskBytes: Int64 { contentBytes + catalogBytes + networkDiskBytes }
}

struct AppCacheClearResult: Sendable {
    let category: AppCacheCategory
    /// URLCache does not expose its file count; these are chapter/catalog files only.
    let removedFiles: Int
    /// Logical bytes of deleted chapter/catalog files only; excludes URLCache and RAM.
    let removedBytes: Int64
    let failures: [String]
    let snapshot: AppCacheSnapshot
}

actor AppCacheService {
    static let shared = AppCacheService(cachesDirectory: FileManager.default
        .urls(for: .cachesDirectory, in: .userDomainMask)[0], contentCache: .shared, urlCache: .shared)
    private let cachesDirectory: URL
    private let contentCache: ChapterContentCache
    private let urlCache: URLCache
    private var busy = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(cachesDirectory: URL, contentCache: ChapterContentCache, urlCache: URLCache) {
        self.cachesDirectory = cachesDirectory
        self.contentCache = contentCache
        self.urlCache = urlCache
    }

    // An actor alone is not a mutex across awaits. Transfer ownership directly to the next waiter.
    private func acquire() async {
        if busy { await withCheckedContinuation { waiting.append($0) } }
        else { busy = true }
    }
    private func release() {
        if waiting.isEmpty { busy = false } else { waiting.removeFirst().resume() }
    }

    func snapshot() async -> AppCacheSnapshot {
        await acquire()
        defer { release() }
        return await readSnapshot()
    }

    func clear(_ category: AppCacheCategory) async -> AppCacheClearResult {
        await acquire()
        defer { release() }
        let root = cachesDirectory
        var files = AppCacheFiles.Report()
        if category == .content || category == .all {
            // Invalidation and disk removal cannot interleave with a chapter read/write.
            files = await contentCache.invalidate {
                AppCacheFiles.scan(root, removing: category)
            }
        } else if category == .catalog {
            files = AppCacheFiles.scan(root, removing: category)
        }
        if category == .network || category == .all {
            urlCache.removeAllCachedResponses()
            // 封面本地缓存也算网络缓存：清掉后下次联网会重新下载。
            CoverDiskCache.removeAll()
            if urlCache.currentDiskUsage > 0 || urlCache.currentMemoryUsage > 0 {
                files.failures.append("URLCache 清理后仍有缓存占用（可能有并发网络写入或延迟释放）")
            }
        }
        return AppCacheClearResult(category: category, removedFiles: files.removedFiles,
            removedBytes: files.removedBytes, failures: files.failures,
            snapshot: await readSnapshot())
    }

    private func readSnapshot() async -> AppCacheSnapshot {
        let entries = await contentCache.memoryEntryCount
        let files = AppCacheFiles.scan(cachesDirectory)
        return AppCacheSnapshot(contentBytes: files.contentBytes, contentFiles: files.contentFiles,
            contentMemoryEntries: entries, catalogBytes: files.catalogBytes, catalogFiles: files.catalogFiles,
            networkDiskBytes: Int64(urlCache.currentDiskUsage) + CoverDiskCache.diskBytes(),
            networkMemoryBytes: Int64(urlCache.currentMemoryUsage),
            warnings: files.failures)
    }
}

/// All paths below the injected/trusted Caches root are opened relative to pinned directory FDs.
/// O_NOFOLLOW protects root/chapters/content-v2; fstatat never follows file symlinks.
/// unlinkat(..., 0) cannot recursively remove a directory, even if an entry changes during scanning.
private enum AppCacheFiles {
    struct Report: Sendable {
        var contentBytes: Int64 = 0, catalogBytes: Int64 = 0, removedBytes: Int64 = 0
        var contentFiles = 0, catalogFiles = 0, removedFiles = 0
        var failures: [String] = []
        mutating func fail(_ path: String) { failures.append("\(path): \(String(cString: strerror(errno)))") }
    }

    private static func matches(_ name: String, prefix: String, digits: Int, suffix: String) -> Bool {
        guard name.hasPrefix(prefix), name.hasSuffix(suffix),
              name.utf8.count == prefix.utf8.count + digits + suffix.utf8.count else { return false }
        return name.utf8.dropFirst(prefix.utf8.count).dropLast(suffix.utf8.count)
            .allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    static func scan(_ root: URL, removing: AppCacheCategory? = nil) -> Report {
        var report = Report()
        let flags = O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
        let rootFD = open(root.path, flags)
        guard rootFD >= 0 else {
            if errno != ENOENT { report.fail(root.path) }
            return report
        }
        defer { close(rootFD) }
        let chaptersPath = root.appendingPathComponent("chapters").path
        let chapters = openat(rootFD, "chapters", flags)
        guard chapters >= 0 else {
            if errno != ENOENT { report.fail(chaptersPath) }
            return report
        }
        defer { close(chapters) }
        scanDirectory(chapters, path: chaptersPath, v2: false, removing: removing, report: &report)
        if removing != .catalog {
            let path = chaptersPath + "/content-v2"
            let v2 = openat(chapters, "content-v2", flags)
            if v2 >= 0 {
                defer { close(v2) }
                scanDirectory(v2, path: path, v2: true, removing: removing, report: &report)
            } else if errno != ENOENT { report.fail(path) }
        }
        return report
    }

    private static func scanDirectory(_ fd: Int32, path: String, v2: Bool,
                                      removing: AppCacheCategory?, report: inout Report) {
        let duplicate = dup(fd)
        guard duplicate >= 0 else { report.fail(path); return }
        guard let stream = fdopendir(duplicate) else {
            close(duplicate); report.fail(path); return
        }
        defer { closedir(stream) }
        while true {
            errno = 0
            guard let entry = readdir(stream) else {
                if errno != 0 { report.fail(path) }
                break
            }
            let name = withUnsafeBytes(of: entry.pointee.d_name) { buffer in
                String(cString: buffer.baseAddress!.assumingMemoryBound(to: CChar.self))
            }
            let isContent = v2
                ? matches(name, prefix: "", digits: 64, suffix: ".txt")
                : matches(name, prefix: "c_", digits: 32, suffix: ".txt")
            let isCatalog = !v2 && matches(name, prefix: "toc_", digits: 32, suffix: ".json")
            guard isContent || isCatalog else { continue }
            var info = stat()
            guard fstatat(fd, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else {
                if errno != ENOENT { report.fail(path + "/" + name) }
                continue
            }
            guard (info.st_mode & S_IFMT) == S_IFREG else { continue }
            let bytes = max(Int64(info.st_size), 0)
            if isContent { report.contentFiles += 1; report.contentBytes += bytes }
            else { report.catalogFiles += 1; report.catalogBytes += bytes }
            let shouldRemove = removing == .all || (isContent && removing == .content) || (isCatalog && removing == .catalog)
            guard shouldRemove else { continue }
            var current = stat()
            guard fstatat(fd, name, &current, AT_SYMLINK_NOFOLLOW) == 0 else {
                if errno != ENOENT { report.fail(path + "/" + name) }
                continue
            }
            guard (current.st_mode & S_IFMT) == S_IFREG,
                  current.st_ino == info.st_ino, current.st_dev == info.st_dev else {
                report.failures.append("缓存文件在清理期间发生变化，已跳过：" + name)
                continue
            }
            // A final replacement with a symlink can only unlink the link itself,
            // never its target. A directory replacement cannot be recursively deleted.
            if unlinkat(fd, name, 0) == 0 {
                report.removedFiles += 1
                report.removedBytes += max(Int64(current.st_size), 0)
            } else if errno != ENOENT { report.fail(path + "/" + name) }
        }
    }
}
