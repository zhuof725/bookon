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
        if waiters.isEmpty { active = max(0, active - 1) } else { waiters.removeFirst().resume() }
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

/// 发现板块专用封面：内存缓存 + 本机磁盘缓存（退出页面/换网络也显示得出来），
/// 下载受「封面并发数」限制。
struct DiscoverCoverImage: View {
    @AppStorage(DiscoverSettings.coverConcurrencyKey) private var concurrency = DiscoverSettings.defaultCoverConcurrency
    let url: URL?
    /// 书源地址（Book.origin）：有书源时按书源请求头下载，图床校验 Referer/UA 也不会被拒。
    var origin: String? = nil
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
        // 1) 内存缓存。
        if let cached = DiscoverCoverCache.shared.image(for: resolved) {
            image = cached
            return
        }
        // 2) 本机磁盘缓存：退出页面再进来直接显示，不重新下载。
        if let data = CoverDiskCache.data(for: resolved),
           let decoded = RemoteCoverImageLoader.downsample(data, maxPixel: 600) {
            DiscoverCoverCache.shared.store(decoded, for: resolved)
            image = decoded
            return
        }
        // 3) 本地文件封面。
        guard resolved.scheme == "http" || resolved.scheme == "https" else {
            if let data = try? Data(contentsOf: resolved), let decoded = UIImage(data: data) {
                DiscoverCoverCache.shared.store(decoded, for: resolved)
                image = decoded
            }
            return
        }
        // 4) 下载（受并发闸门限制；优先带书源请求头）。
        await CoverLoadGate.shared.updateLimit(concurrency)
        await CoverLoadGate.shared.acquire()
        var payload: Data?
        if let origin, let needs = CoverDecodeRuntime.needsDecode, await needs(origin),
           let decode = CoverDecodeRuntime.load {
            payload = await decode(resolved, origin)
        } else if let origin, let plain = CoverDecodeRuntime.loadPlain {
            payload = await plain(resolved, origin)
        } else {
            payload = await Self.systemDownload(resolved)
        }
        await CoverLoadGate.shared.release()
        guard let payload, let decoded = RemoteCoverImageLoader.downsample(payload, maxPixel: 600) else {
            // 失败时保持占位色块。
            return
        }
        DiscoverCoverCache.shared.store(decoded, for: resolved)
        image = decoded
    }

    /// 没有书源钩子时的兜底：系统请求（结果同样落到本机缓存）。
    private static func systemDownload(_ url: URL) async -> Data? {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return nil }
            guard !data.isEmpty else { return nil }
            CoverDiskCache.store(data, for: url)
            return data
        } catch {
            return nil
        }
    }
}
