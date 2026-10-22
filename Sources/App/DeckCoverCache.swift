import SwiftUI
import CryptoKit

// MARK: - 封面缓存

/// 封面两级缓存：内存（NSCache）+ 磁盘（Caches/LegadoReading/discover-covers）。
///
/// 为什么需要磁盘：滚动时卡片反复进出屏幕，只靠内存会在系统压内存时全部丢掉，
/// 于是每次回滑都要重新下载，表现就是「卡卡的」。
/// 磁盘缓存按 URL 的 SHA256 命名，不解析扩展名，也不依赖服务器给的文件名。
final class DeckCoverCache {
    static let shared = DeckCoverCache()

    private let memory = NSCache<NSURL, UIImage>()
    /// 同一条 URL 只下载一次：并发的重复请求直接复用同一个任务
    private var inflight: [NSURL: Task<UIImage?, Never>] = [:]
    private let lock = NSLock()

    private let ioQueue = DispatchQueue(label: "deckcover.disk", qos: .utility)

    private init() {
        memory.countLimit = 320
        memory.totalCostLimit = 96 * 1024 * 1024   // 约 96MB，超出自动回收
    }

    /// 缓存目录。
    private var directory: URL? {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LegadoReading", isDirectory: true)
            .appendingPathComponent("discover-covers", isDirectory: true)
        if !FileManager.default.fileExists(atPath: base.path) {
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        }
        return base
    }

    private func diskURL(for url: URL) -> URL? {
        guard let directory else { return nil }
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(name)
    }

    /// 已在内存里的图（同步，用于首帧直接出图，避免闪一下占位色）。
    func memoryImage(for url: URL) -> UIImage? {
        memory.object(forKey: url as NSURL)
    }

    /// 取图：内存 → 磁盘 → 网络。命中磁盘会回填内存。
    func image(for url: URL) async -> UIImage? {
        if let hit = memoryImage(for: url) { return hit }

        // 同一个 URL 并发请求合并成一个任务
        lock.lock()
        if let existing = inflight[url as NSURL] {
            lock.unlock()
            return await existing.value
        }
        let task = Task<UIImage?, Never> { [weak self] in
            guard let self else { return nil }
            if let disk = await self.loadFromDisk(url), let decoded = UIImage(data: disk) {
                self.remember(decoded, for: url)
                return decoded
            }
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let decoded = UIImage(data: data) else { return nil }
            self.remember(decoded, for: url)
            await self.saveToDisk(data, for: url)
            return decoded
        }
        inflight[url as NSURL] = task
        lock.unlock()

        let result = await task.value

        lock.lock()
        inflight[url as NSURL] = nil
        lock.unlock()
        return result
    }

    private func remember(_ image: UIImage, for url: URL) {
        let cost = Int(image.size.width * image.size.height * image.scale * 4)
        memory.setObject(image, forKey: url as NSURL, cost: cost)
    }

    private func loadFromDisk(_ url: URL) async -> Data? {
        guard let file = diskURL(for: url) else { return nil }
        return await withCheckedContinuation { continuation in
            ioQueue.async {
                continuation.resume(returning: try? Data(contentsOf: file))
            }
        }
    }

    private func saveToDisk(_ data: Data, for url: URL) async {
        guard let file = diskURL(for: url) else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            ioQueue.async {
                try? data.write(to: file, options: .atomic)
                continuation.resume()
            }
        }
    }

    /// 清空（用于「缓存管理」里的一键清理）。
    func clearAll() {
        memory.removeAllObjects()
        guard let directory else { return }
        try? FileManager.default.removeItem(at: directory)
    }

    /// 当前磁盘占用（字节），给缓存管理页显示。
    func diskUsage() -> Int64 {
        guard let directory,
              let files = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return files.reduce(into: Int64(0)) { total, file in
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            total += Int64(size)
        }
    }
}

// MARK: - 封面视图

/// 板块内统一封面：内存缓存 → 磁盘缓存 → 网络，失败保持占位色。
///
/// 首帧先同步取内存里的图，避免每次滚动回来都闪一下灰色占位。
struct DeckCoverImage: View {
    let url: URL?

    @State private var image: UIImage?

    var body: some View {
        // 用 Color.clear + overlay 撑尺寸，比 GeometryReader 省：后者在滚动中
        // 每次尺寸变化都会重新求值 body，一屏几十张封面就是持续的布局开销。
        Color.clear
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle().fill(Color(uiColor: .secondarySystemFill))
                }
            }
            .clipped()
            .task(id: url) { await load() }
    }

    private func load() async {
        guard let url, url.scheme == "http" || url.scheme == "https" else { return }

        // 1. 同步命中内存：这一帧就能画出来，不闪占位
        if let hit = DeckCoverCache.shared.memoryImage(for: url) {
            image = hit
            return
        }
        // 2. 走完整链路（磁盘 → 网络）
        // 直接赋值，不加隐式动画：一屏几十张图同时做过渡会堆积动画事务
        if let loaded = await DeckCoverCache.shared.image(for: url) {
            image = loaded
        }
    }
}
