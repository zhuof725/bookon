import SwiftUI
import UIKit
import ImageIO

/// Keep the last valid bitmap while a same-URL retry is cancelled or the file is
/// temporarily unavailable (for example during device data protection).
@MainActor
final class LocalCoverImageLoader: ObservableObject {
    @Published private(set) var image: UIImage?
    @Published private(set) var didFail = false
    private(set) var sourceURL: URL?
    private var generation = UUID()

    func load(_ requestedURL: URL?, pixelSize: Int) async {
        let url = requestedURL.flatMap { BookCoverLocation.resolve($0) }
        let token = UUID()
        generation = token
        if sourceURL != url {
            sourceURL = url
            image = nil
            didFail = false
        }
        guard let url, url.isFileURL else { return }
        let pixelBudget = max(1, min(pixelSize, 1200))
        let decoded: UIImage? = await Task.detached(priority: .utility) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: pixelBudget
                  ] as CFDictionary) else { return nil }
            return UIImage(cgImage: thumbnail)
        }.value
        guard !Task.isCancelled, generation == token, sourceURL == url else { return }
        let result = decoded
        if let result { image = result; didFail = false }
        else { didFail = image == nil }
    }
}

/// 书源 coverDecodeJs 的封面解密注入点。
/// 正式 App 在启动时由 RemoteCoverLoader 注入；测试工程不注入，封面走普通加载路径。
enum CoverDecodeRuntime {
    /// 该书源是否配置了 coverDecodeJs（实现里会切到主线程读 AppStore）。
    typealias NeedsDecode = (String) async -> Bool
    /// 下载 + 解密 → 返回可以直接显示的图片字节；失败返回 nil。
    typealias Loader = (URL, String) async -> Data?
    /// 普通封面（没有解密规则）：带书源请求头下载 → 返回图片字节；失败返回 nil。
    typealias PlainLoader = (URL, String) async -> Data?
    nonisolated(unsafe) static var needsDecode: NeedsDecode?
    nonisolated(unsafe) static var load: Loader?
    nonisolated(unsafe) static var loadPlain: PlainLoader?
}

/// 远程封面加载：先看本机缓存（换网络/开 VPN 也显示得出来），没有再下载并落盘。
@MainActor
final class RemoteCoverImageLoader: ObservableObject {
    @Published private(set) var image: UIImage?
    @Published private(set) var failed = false
    private var token = UUID()

    func load(url: URL, origin: String?, pixelSize: Int) async {
        let id = UUID()
        token = id
        failed = false
        let budget = max(1, min(pixelSize, 1200))
        // 1) 本机缓存：有就直接显示，不碰网络。
        if let cached = CoverDiskCache.data(for: url),
           let image = Self.downsample(cached, maxPixel: budget) {
            self.image = image
            return
        }
        // 2) 重新下载（带书源请求头；解密书源走解密路径）。
        let data = await fetch(url: url, origin: origin)
        guard token == id else { return }
        guard let data, let loaded = Self.downsample(data, maxPixel: budget) else {
            failed = true
            return
        }
        image = loaded
    }

    private func fetch(url: URL, origin: String?) async -> Data? {
        if let origin, let needs = CoverDecodeRuntime.needsDecode, await needs(origin),
           let decode = CoverDecodeRuntime.load {
            return await decode(url, origin)
        }
        if let origin, let plain = CoverDecodeRuntime.loadPlain,
           let data = await plain(url, origin) {
            return data
        }
        return await Self.systemDownload(url: url)
    }

    /// 没有书源钩子时的兜底：系统请求（缓存仍会落到本机）。
    private static func systemDownload(url: URL) async -> Data? {
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

    /// 按显示尺寸缩放（缓存里存的是原始字节，显示时才缩，避免大图占内存）。
    static func downsample(_ data: Data, maxPixel: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixel)
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: thumbnail)
    }
}

/// Shared production loader for shelf/detail/list/reader-cover views.
struct BookCoverImage: View {
    @ThemePalette private var palette
    let url: URL?
    var pixelSize: Int = 600
    /// 书源地址（Book.origin）；有 coverDecodeJs 时改走解密加载。
    var origin: String? = nil
    @StateObject private var loader = LocalCoverImageLoader()
    @StateObject private var remote = RemoteCoverImageLoader()
    @Environment(\.scenePhase) private var scenePhase
    @State private var retry = 0

    private var resolvedURL: URL? { url.flatMap { BookCoverLocation.resolve($0) } }

    private var requestID: String { "\(resolvedURL?.absoluteString ?? "nil")|\(retry)" }

    var body: some View {
        GeometryReader { geometry in
            Group {
                if let resolvedURL, resolvedURL.isFileURL {
                    if loader.sourceURL == resolvedURL, let image = loader.image {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else if loader.sourceURL == resolvedURL, loader.didFail {
                        fallback
                    } else { placeholder }
                } else if let resolvedURL, ["http", "https"].contains(resolvedURL.scheme?.lowercased() ?? "") {
                    if let image = remote.image {
                        Image(uiImage: image).resizable().scaledToFill()
                    } else if remote.failed { fallback } else { placeholder }
                } else { fallback }
            }
            .frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }
        .task(id: requestID) {
            guard let resolvedURL else { return }
            if resolvedURL.isFileURL {
                await loader.load(resolvedURL, pixelSize: pixelSize)
                return
            }
            guard ["http", "https"].contains(resolvedURL.scheme?.lowercased() ?? "") else { return }
            // 先查本机缓存，没有再下载；下载到的封面会落到本机，下次开 VPN/断网也显示得出来。
            await remote.load(url: resolvedURL, origin: origin, pixelSize: pixelSize)
        }
        .onChange(of: scenePhase) { phase in if phase == .active { retry += 1 } }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in retry += 1 }
        .accessibilityHidden(true)
    }

    private var fallback: some View { ThemeDefaultCover(placeholder: placeholder) }

    private var placeholder: some View {
        ZStack {
            LinearGradient(colors: [palette.placeholderTop, palette.placeholderBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: "book.closed").font(.system(size: 26, weight: .light)).foregroundStyle(palette.primary.opacity(0.55))
        }
    }
}

/// Only mounted for missing/failed covers, never while a valid cover is loading.
private struct ThemeDefaultCover<Placeholder: View>: View {
    @Environment(\.appTheme) private var theme
    @StateObject private var loader = ThemeAssetImageLoader()
    let placeholder: Placeholder
    var body: some View {
        Group {
            if loader.assetID == theme.customization?.defaultCoverImage, let image = loader.image {
                Image(uiImage: image).resizable().scaledToFill()
            } else { placeholder }
        }
        .task(id: theme.customization?.defaultCoverImage) {
            await loader.load(theme.customization?.defaultCoverImage)
        }
    }
}
