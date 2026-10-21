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
        var result = decoded
        // 封面超分：只放大比显示目标小的封面。放大与缓存由 UpscaleRuntime 承担
        // （Engine 层注入点，测试工程里没有超分实现时保持原图）。
        if UpscaleSettings.coverEnabled,
           let cgImage = decoded?.cgImage,
           UpscaleSettings.shouldUpscale(pixelWidth: cgImage.width,
                                         pixelHeight: cgImage.height,
                                         targetWidth: pixelBudget,
                                         quality: UpscaleSettings.quality) {
            let cacheKey = "\(url.absoluteString)|\(pixelBudget)|\(UpscaleSettings.quality.rawValue)"
            if let upscaled = await UpscaleRuntime.coverUpscaler?(cgImage, pixelBudget, cacheKey) {
                result = UIImage(cgImage: upscaled)
            }
        }
        if let result { image = result; didFail = false }
        else { didFail = image == nil }
    }
}

/// 书源 coverDecodeJs 的封面解密注入点。
/// 正式 App 在启动时由 RemoteCoverLoader 注入；测试工程不注入，封面走普通加载路径。
enum CoverDecodeRuntime {
    /// 该书源是否配置了 coverDecodeJs。
    static var needsDecode: ((String) -> Bool)?
    /// 下载 + 解密 + 解码；失败返回 nil。
    static var load: ((URL, String, Int) async -> UIImage?)?
}

/// Shared production loader for shelf/detail/list/reader-cover views.
struct BookCoverImage: View {
    @ThemePalette private var palette
    let url: URL?
    var pixelSize: Int = 600
    /// 书源地址（Book.origin）；有 coverDecodeJs 时改走解密加载。
    var origin: String? = nil
    @StateObject private var loader = LocalCoverImageLoader()
    @State private var decodedImage: UIImage?
    @State private var decodeFailed = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var retry = 0

    private var resolvedURL: URL? { url.flatMap { BookCoverLocation.resolve($0) } }
    private var needsDecode: Bool {
        guard let origin else { return false }
        return CoverDecodeRuntime.needsDecode?(origin) ?? false
    }
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
                    if needsDecode {
                        if let image = decodedImage {
                            Image(uiImage: image).resizable().scaledToFill()
                        } else if decodeFailed { fallback } else { placeholder }
                    } else {
                        AsyncImage(url: resolvedURL) { phase in
                            switch phase {
                            case .success(let image): image.resizable().scaledToFill()
                            case .failure: fallback
                            default: placeholder
                            }
                        }
                    }
                } else { fallback }
            }
            .frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }
        .task(id: requestID) {
            if needsDecode, let resolvedURL, let origin, let decode = CoverDecodeRuntime.load {
                let image = await decode(resolvedURL, origin, pixelSize)
                guard !Task.isCancelled else { return }
                decodedImage = image
                decodeFailed = image == nil
            } else {
                await loader.load(resolvedURL, pixelSize: pixelSize)
            }
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
