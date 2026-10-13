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
        let decoded: UIImage? = await Task.detached(priority: .utility) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: max(1, min(pixelSize, 1200))
                  ] as CFDictionary) else { return nil }
            return UIImage(cgImage: thumbnail)
        }.value
        guard !Task.isCancelled, generation == token, sourceURL == url else { return }
        if let decoded { image = decoded; didFail = false }
        else { didFail = image == nil }
    }
}

/// Shared production loader for shelf/detail/list/reader-cover views.
struct BookCoverImage: View {
    @ThemePalette private var palette
    let url: URL?
    var pixelSize: Int = 600
    @StateObject private var loader = LocalCoverImageLoader()
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
                    AsyncImage(url: resolvedURL) { phase in
                        switch phase {
                        case .success(let image): image.resizable().scaledToFill()
                        case .failure: fallback
                        default: placeholder
                        }
                    }
                } else { fallback }
            }
            .frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }
        .task(id: requestID) { await loader.load(resolvedURL, pixelSize: pixelSize) }
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
