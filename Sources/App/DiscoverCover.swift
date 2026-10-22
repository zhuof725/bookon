import SwiftUI
import UIKit

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
    /// 封面下载失败（签名过期、链接失效等）时回调：让板块用书名重搜一次，换新的封面地址。
    var onFailure: (() -> Void)? = nil
    @State private var image: UIImage?

    /// 封面下载超时（秒）：CDN 偶尔会卡住，占位图一直不换。
    private static let timeout: TimeInterval = 12

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
        var failed = false
        do {
            var request = URLRequest(url: resolved)
            request.timeoutInterval = Self.timeout
            let (data, response) = try await URLSession.shared.data(for: request)
            if let decoded = UIImage(data: data) {
                DiscoverCoverCache.shared.store(decoded, for: resolved)
                image = decoded
            } else {
                failed = true
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                DebugLog.readerAdd("◇发现页封面加载失败（\(status)）：\(resolved.absoluteString)")
            }
        } catch let error as URLError where error.code == .cancelled {
            // 视图被销毁 / 任务被取消：不是封面本身的问题，不重试也不上报。
        } catch {
            failed = true
            DebugLog.readerAdd("◇发现页封面加载出错：\(error.localizedDescription)")
        }
        await CoverLoadGate.shared.release()
        if failed { onFailure?() }
    }
}
