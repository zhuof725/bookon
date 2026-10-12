import SwiftUI
import UIKit
import ImageIO

/// Keep the last valid bitmap while a same-URL retry is cancelled or the file is
/// temporarily unavailable (for example during device data protection).
@MainActor
final class LocalCoverImageLoader: ObservableObject {
    @Published private(set) var image: UIImage?
    private(set) var sourceURL: URL?
    private var generation = UUID()

    func load(_ requestedURL: URL?, pixelSize: Int) async {
        let url = requestedURL.flatMap { BookCoverLocation.resolve($0) }
        let token = UUID()
        generation = token
        if sourceURL != url {
            sourceURL = url
            image = nil
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
        if let decoded { image = decoded }
    }
}

/// Shared production loader for shelf/detail/list/reader-cover views.
struct BookCoverImage: View {
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
                    } else { placeholder }
                } else if let resolvedURL, ["http", "https"].contains(resolvedURL.scheme?.lowercased() ?? "") {
                    AsyncImage(url: resolvedURL) { phase in
                        if let image = phase.image { image.resizable().scaledToFill() }
                        else { placeholder }
                    }
                } else { placeholder }
            }
            .frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }
        .task(id: requestID) { await loader.load(resolvedURL, pixelSize: pixelSize) }
        .onChange(of: scenePhase) { phase in if phase == .active { retry += 1 } }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in retry += 1 }
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(colors: [AppPalette.placeholderTop, AppPalette.placeholderBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: "book.closed").font(.system(size: 26, weight: .light)).foregroundStyle(.white.opacity(0.55))
        }
    }
}
