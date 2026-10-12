import SwiftUI
import Foundation
import CryptoKit

@MainActor
final class CacheManagementFixture: ObservableObject {
    @Published var service: AppCacheService?
    @Published var report = "fixture=starting"

    private let id: String
    private var root: URL?
    private let protectedSizes = [777, 555, 333]
    private let unmanagedSize = 257

    init(id: String) { self.id = id }

    func prepare() async {
        guard service == nil else { return }
        let fm = FileManager.default
        let safeID = id.replacingOccurrences(of: "/", with: "_")
        let base = fm.temporaryDirectory.appendingPathComponent("cache-management-\(safeID)", isDirectory: true)
        let caches = base.appendingPathComponent("Caches", isDirectory: true)
        let chapters = caches.appendingPathComponent("chapters", isDirectory: true)
        let content = chapters.appendingPathComponent("content-v2", isDirectory: true)
        let protected = base.appendingPathComponent("Documents/LocalBooks", isDirectory: true)
        do {
            try? fm.removeItem(at: base)
            try fm.createDirectory(at: content, withIntermediateDirectories: true)
            try fm.createDirectory(at: protected.appendingPathComponent("Fonts", isDirectory: true), withIntermediateDirectories: true)
            try fm.createDirectory(at: base.appendingPathComponent("unmanaged", isDirectory: true), withIntermediateDirectories: true)

            let key = ChapterContentKey(sourceURL: "fixture-source", bookURL: "fixture-book", chapterURL: "fixture-chapter")
            try Data(repeating: 0x41, count: 4096).write(to: content.appendingPathComponent(Self.fileName(for: key)))
            try Data(repeating: 0x42, count: 2048).write(to: chapters.appendingPathComponent("c_0123456789abcdef0123456789abcdef.txt"))
            try Data(repeating: 0x43, count: 1024).write(to: chapters.appendingPathComponent("toc_" + String(repeating: "b", count: 32) + ".json"))
            try Data(repeating: 0x44, count: unmanagedSize).write(to: base.appendingPathComponent("unmanaged/keep.dat"))
            try Data(repeating: 0x45, count: protectedSizes[0]).write(to: protected.appendingPathComponent("cover.img"))
            try Data(repeating: 0x46, count: protectedSizes[1]).write(to: protected.appendingPathComponent("Fonts/fixture.ttf"))
            try Data(repeating: 0x47, count: protectedSizes[2]).write(to: protected.appendingPathComponent("books.json"))

            let contentCache = ChapterContentCache(directory: content, memoryLimit: 4)
            _ = try await contentCache.content(for: key) { "fixture loader must not run" }
            let urlCache = URLCache(memoryCapacity: 64 * 1024, diskCapacity: 0, diskPath: nil)
            let request = URLRequest(url: URL(string: "https://cache-management.invalid/fixture")!)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            urlCache.storeCachedResponse(CachedURLResponse(response: response, data: Data(repeating: 0x48, count: 512)), for: request)
            let created = AppCacheService(cachesDirectory: caches, contentCache: contentCache, urlCache: urlCache)
            root = base
            let initial = await created.snapshot()
            report = makeReport(initial)
            service = created
        } catch {
            report = "fixture=error;message=\(error.localizedDescription)"
        }
    }

    func check() async {
        guard let service else { return }
        report = makeReport(await service.snapshot())
    }

    private func makeReport(_ snapshot: AppCacheSnapshot) -> String {
        let fm = FileManager.default
        let base = root ?? URL(fileURLWithPath: "/missing")
        let protected = base.appendingPathComponent("Documents/LocalBooks")
        let protectedFiles = ["cover.img", "Fonts/fixture.ttf", "books.json"].map { protected.appendingPathComponent($0) }
        let protectedBytes = protectedFiles.reduce(Int64(0)) { $0 + fileSize($1) }
        let unmanaged = fileSize(base.appendingPathComponent("unmanaged/keep.dat"))
        let protectedPresent = protectedFiles.enumerated().allSatisfy { i, url in
            (try? Data(contentsOf: url)) == Data(repeating: UInt8(0x45 + i), count: protectedSizes[i])
        }
        return "fixture=ready;content=\(snapshot.contentBytes);contentFiles=\(snapshot.contentFiles);memory=\(snapshot.contentMemoryEntries);catalog=\(snapshot.catalogBytes);catalogFiles=\(snapshot.catalogFiles);networkDisk=\(snapshot.networkDiskBytes);networkMemory=\(snapshot.networkMemoryBytes);protected=\(protectedBytes);protectedFiles=\(protectedPresent ? 3 : 0);unmanaged=\(unmanaged)"
    }

    private func fileSize(_ url: URL) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
    }

    private static func fileName(for key: ChapterContentKey) -> String {
        let data = (try? JSONEncoder().encode([key.sourceURL, key.bookURL, key.chapterURL])) ?? Data()
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return digest + ".txt"
    }
}

@MainActor
struct CacheManagementHarnessView: View {
    @StateObject private var fixture: CacheManagementFixture
    private let dark: Bool

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        dark = arguments.contains("--cache-management-dark")
        _fixture = StateObject(wrappedValue: CacheManagementFixture(
            id: ProcessInfo.processInfo.environment["CACHE_MANAGEMENT_FIXTURE_ID"] ?? UUID().uuidString))
    }

    var body: some View {
        Group {
            if let service = fixture.service {
                CacheManagementView(service: service)
            } else {
                ProgressView("准备缓存测试…").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .preferredColorScheme(dark ? .dark : .light)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 2) {
                Button("验证测试数据") { Task { await fixture.check() } }
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .accessibilityIdentifier("cache.fixture.check")
                Text("隔离缓存测试")
                    .font(.system(size: 9))
                    .accessibilityValue(fixture.report)
                    .accessibilityIdentifier("cache.fixture.report")
            }.background(AppPalette.background)
        }
        .task { await fixture.prepare() }
    }
}
