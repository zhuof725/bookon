import SwiftUI

/// 封面下载并发闸门：同时进行的下载数量不超过设置值。
actor CoverLoadGate {
    static let shared = CoverLoadGate()
    private var limit = DiscoverSettings.defaultCoverConcurrency
    private var active = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func updateLimit(_ value: Int) {
        limit = max(1, value)
    }

    func acquire() async {
        if active < limit {
            active += 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if waiters.isEmpty {
            active = max(0, active - 1)
        } else {
            waiters.removeFirst().resume()
        }
    }
}

/// 发现页封面内存缓存。
final class DiscoverCoverCache {
    static let shared = DiscoverCoverCache()
    private let cache = NSCache<NSURL, UIImage>()
    private init() { cache.countLimit = 400 }

    func image(for url: URL) -> UIImage? { cache.object(forKey: url as NSURL) }
    func store(_ image: UIImage, for url: URL) { cache.setObject(image, forKey: url as NSURL) }
}

/// 发现板块专用封面：下载受「封面并发数」限制，内存缓存。
struct DiscoverCoverImage: View {
    @AppStorage(DiscoverSettings.coverConcurrencyKey) private var concurrency = DiscoverSettings.defaultCoverConcurrency
    let url: URL?
    @State private var image: UIImage?

    var body: some View {
        GeometryReader { geometry in
            Group {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Rectangle().fill(Color(uiColor: .secondarySystemFill))
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .task(id: url) { await load() }
    }

    private func load() async {
        guard let raw = url, let resolved = BookCoverLocation.resolve(raw) else { return }
        if let cached = DiscoverCoverCache.shared.image(for: resolved) {
            image = cached
            return
        }
        guard resolved.scheme == "http" || resolved.scheme == "https" else {
            if let data = try? Data(contentsOf: resolved), let decoded = UIImage(data: data) {
                DiscoverCoverCache.shared.store(decoded, for: resolved)
                image = decoded
            }
            return
        }
        await CoverLoadGate.shared.updateLimit(concurrency)
        await CoverLoadGate.shared.acquire()
        do {
            let (data, _) = try await URLSession.shared.data(from: resolved)
            if let decoded = UIImage(data: data) {
                DiscoverCoverCache.shared.store(decoded, for: resolved)
                image = decoded
            }
        } catch {
            // 失败时保持占位色块。
        }
        await CoverLoadGate.shared.release()
    }
}
