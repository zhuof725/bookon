import Foundation
import CryptoKit

var checks = 0, failures = 0
func check(_ ok: Bool, _ label: String) { checks += 1; if !ok { failures += 1 }; print("\(ok ? "PASS" : "FAIL") \(label)") }
func fileName(_ key: ChapterContentKey) throws -> String {
    SHA256.hash(data: try JSONEncoder().encode([key.sourceURL, key.bookURL, key.chapterURL])).map { String(format: "%02x", $0) }.joined() + ".txt"
}
func write(_ url: URL, _ text: String) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url)
}
func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
actor Gate {
    var started = false
    private var open = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func load() async -> String {
        started = true
        if !open { await withCheckedContinuation { waiters.append($0) } }
        return "old response ignoring cancellation"
    }
    func release() { open = true; waiters.forEach { $0.resume() }; waiters.removeAll() }
}
func run() async throws {
    let fm = FileManager.default
    let base = fm.temporaryDirectory.appendingPathComponent("CacheManagementTest-" + UUID().uuidString)
    defer { try? fm.removeItem(at: base) }
    let caches = base.appendingPathComponent("Caches"), chapters = caches.appendingPathComponent("chapters")
    let content = chapters.appendingPathComponent("content-v2")
    let cache = ChapterContentCache(directory: content)
    let network = URLCache(memoryCapacity: 1_000_000, diskCapacity: 0, diskPath: nil)
    let service = AppCacheService(cachesDirectory: caches, contentCache: cache, urlCache: network)
    let empty = await service.snapshot()
    check(empty.diskBytes == 0 && empty.contentFiles == 0 && empty.warnings.isEmpty, "missing directory reports zero")
    check(!exists(caches), "scan never creates cache directory")
    let key = ChapterContentKey(sourceURL: "s", bookURL: "b", chapterURL: "c")
    let fresh = try await cache.content(for: key) { "hello" }
    check(fresh == "hello", "real chapter cache seed")
    let oldFile = chapters.appendingPathComponent("c_" + String(repeating: "a", count: 32) + ".txt")
    let catalog = chapters.appendingPathComponent("toc_" + String(repeating: "b", count: 32) + ".json")
    try write(oldFile, "old"); try write(catalog, "[1]")
    let protected = [base.appendingPathComponent("Documents/LocalBooks/book/cover.img"),
        base.appendingPathComponent("Documents/LocalBooks/book/0.txt"),
        base.appendingPathComponent("Documents/ReadingFonts/font.ttf"),
        base.appendingPathComponent("Documents/bookshelf.json"),
        base.appendingPathComponent("Documents/bookSources.json"),
        base.appendingPathComponent("Library/Preferences/history.plist"),
        base.appendingPathComponent("Library/Cookies/session.binarycookies"),
        content.appendingPathComponent("unknown.txt"), chapters.appendingPathComponent("misc.json")]
    for (i, url) in protected.enumerated() { try write(url, "protected-\(i)") }
    let nested = content.appendingPathComponent(String(repeating: "d", count: 64) + ".txt/keep.txt")
    try write(nested, "nested")
    let symlink = content.appendingPathComponent(String(repeating: "e", count: 64) + ".txt")
    try fm.createSymbolicLink(at: symlink, withDestinationURL: protected[0])
    let request = URLRequest(url: URL(string: "https://example.invalid/cache-test")!)
    let response = URLResponse(url: request.url!, mimeType: "text/plain", expectedContentLength: 512, textEncodingName: "utf-8")
    network.storeCachedResponse(CachedURLResponse(response: response, data: Data(repeating: 65, count: 512), storagePolicy: .allowedInMemoryOnly), for: request)
    check(network.cachedResponse(for: request) != nil, "isolated URLCache seeded without network")
    let snapshot = await service.snapshot()
    check(snapshot.contentFiles == 2 && snapshot.contentBytes == 8, "counts known legacy and v2 body files only")
    check(snapshot.catalogFiles == 1 && snapshot.catalogBytes == 3, "counts recognized catalog")
    check(snapshot.contentMemoryEntries == 1, "counts actual memory entries")
    let cleared = await service.clear(.content)
    check(cleared.failures.isEmpty && cleared.removedFiles == 2 && cleared.removedBytes == 8, "body clear reports actual file removals")
    check(cleared.snapshot.contentBytes == 0 && cleared.snapshot.contentMemoryEntries == 0, "body disk and memory cleared")
    check(cleared.snapshot.catalogBytes == 3 && exists(catalog), "body clear preserves catalog")
    check(network.cachedResponse(for: request) != nil, "body clear preserves network responses")
    let reused = await cache.cached(for: key)
    check(reused == nil, "cleared body not returned from memory")
    _ = try await cache.content(for: key) { "new" }
    let catalogClear = await service.clear(.catalog)
    check(catalogClear.removedFiles == 1 && catalogClear.removedBytes == 3, "catalog-only clear")
    check(catalogClear.snapshot.contentBytes == 3 && catalogClear.snapshot.contentMemoryEntries == 1, "catalog clear preserves body")
    let networkClear = await service.clear(.network)
    check(network.cachedResponse(for: request) == nil, "network clear removes cached response")
    check(networkClear.removedFiles == 0 && networkClear.removedBytes == 0 && networkClear.snapshot.contentBytes == 3, "network reports no file removals and preserves body")
    try write(catalog, "catalog")
    let all = await service.clear(.all)
    check(all.failures.isEmpty && all.removedFiles == 2 && all.removedBytes == 10, "clear all recognized files")
    check(all.snapshot.diskBytes == 0 && all.snapshot.contentMemoryEntries == 0, "all managed data cleared")
    let repeated = await service.clear(.all)
    check(repeated.removedFiles == 0 && repeated.failures.isEmpty, "empty cleanup idempotent")
    for (i, url) in protected.enumerated() { check(try String(contentsOf: url, encoding: .utf8) == "protected-\(i)", "protected bytes unchanged \(i)") }
    check(try String(contentsOf: nested, encoding: .utf8) == "nested", "nested directories never removed")
    check((try? fm.destinationOfSymbolicLink(atPath: symlink.path)) != nil, "file symlink preserved")

    // A loader deliberately ignores cancellation. Clearing must reject its later writeback.
    let gate = Gate()
    let old = Task { try await cache.content(for: key) { await gate.load() } }
    while !(await gate.started) { await Task.yield() }
    _ = await service.clear(.content)
    let new = try await cache.content(for: key) { "post-clear" }
    check(new == "post-clear", "new request after clear succeeds")
    await gate.release()
    do { _ = try await old.value; check(false, "old flight must be rejected") }
    catch is CancellationError { check(true, "old flight rejected after clear") }
    let post = await cache.cached(for: key)
    check(post == "post-clear", "old completion cannot overwrite new cache")
    check(try String(contentsOf: content.appendingPathComponent(fileName(key)), encoding: .utf8) == "post-clear", "old completion cannot overwrite disk")
    _ = await service.clear(.all)

    // Matching paths under symlinked directories must never traverse to protected files.
    let external = base.appendingPathComponent("external"), target = external.appendingPathComponent("c_" + String(repeating: "c", count: 32) + ".txt")
    try write(target, "keep-external")
    try fm.removeItem(at: chapters)
    try fm.createSymbolicLink(at: chapters, withDestinationURL: external)
    let refused = await service.clear(.all)
    check(!refused.failures.isEmpty && refused.removedFiles == 0, "symlinked chapters directory refused")
    check(try String(contentsOf: target, encoding: .utf8) == "keep-external", "symlink target unchanged")
    try fm.removeItem(at: chapters)
    try fm.createDirectory(at: chapters, withIntermediateDirectories: true)
    try fm.createSymbolicLink(at: content, withDestinationURL: external)
    let refusedV2 = await service.clear(.content)
    check(!refusedV2.failures.isEmpty && exists(target), "symlinked v2 directory refused")
    let linkedRoot = base.appendingPathComponent("linked-Caches")
    try fm.createSymbolicLink(at: linkedRoot, withDestinationURL: caches)
    let linkedService = AppCacheService(cachesDirectory: linkedRoot, contentCache: cache, urlCache: network)
    let refusedRoot = await linkedService.clear(.all)
    check(!refusedRoot.failures.isEmpty && exists(target), "symlinked Caches root refused")
    let notDirectory = base.appendingPathComponent("file-root")
    try write(notDirectory, "protected-root")
    let invalidService = AppCacheService(cachesDirectory: notDirectory, contentCache: cache, urlCache: network)
    let invalid = await invalidService.clear(.catalog)
    check(!invalid.failures.isEmpty && invalid.removedFiles == 0, "non-directory reports failure")
    try await ChapterContentCacheRegression.run(check)
}
do { try await run() } catch { check(false, "unexpected: \(error)") }
print("Cache management regression: \(checks) checks, \(failures) failures")
if failures > 0 { exit(1) }
