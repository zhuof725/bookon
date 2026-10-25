import Foundation
import UIKit
import MediaPlayer

/// 播放器取封面的统一入口：本机缓存 → 书源钩子（解密/带请求头下载）→ 系统请求。
///
/// 与 `RemoteCoverImageLoader`（给 SwiftUI 视图用）走同一套缓存与钩子，
/// 只是出口是「解码后的 JPEG 字节」，方便分别喂给 MPMediaItemArtwork 与 Live Activity。
enum CoverArtworkLoader {
    /// 取封面字节并缩到 maxPixel 内。
    /// - Parameters:
    ///   - url: 封面地址（可能是本地 file://，也可能是 http(s)）。
    ///   - origin: 书源地址；书源配了 coverDecodeJs 时走解密路径。
    static func load(url: URL, origin: String?, maxPixel: Int) async -> Data? {
        let budget = max(1, min(maxPixel, 1200))
        let resolved = BookCoverLocation.resolve(url) ?? url
        // 1) 本地文件（含 legado-cover:// 与 LocalBooks 归档）：直接读。
        if resolved.isFileURL {
            return thumbnail(fromFile: resolved, maxPixel: budget)
        }
        guard ["http", "https"].contains(resolved.scheme?.lowercased() ?? "") else { return nil }
        // 2) 本机磁盘缓存：命中的是原始字节，直接缩。
        if let cached = CoverDiskCache.data(for: resolved) {
            if let image = downsample(cached, maxPixel: budget) {
                return image.jpegData(compressionQuality: 0.82)
            }
        }
        // 3) 重新下载（带书源请求头；解密书源先解密）。
        guard let raw = await fetch(resolved, origin: origin) else { return nil }
        guard let image = downsample(raw, maxPixel: budget) else { return nil }
        return image.jpegData(compressionQuality: 0.82)
    }

    private static func fetch(_ url: URL, origin: String?) async -> Data? {
        if let origin, let needs = CoverDecodeRuntime.needsDecode, await needs(origin),
           let decode = CoverDecodeRuntime.load {
            return await decode(url, origin)
        }
        if let origin, let plain = CoverDecodeRuntime.loadPlain,
           let data = await plain(url, origin) {
            return data
        }
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

    private static func thumbnail(fromFile url: URL, maxPixel: Int) -> Data? {
        guard let data = try? Data(contentsOf: url), !data.isEmpty,
              let image = downsample(data, maxPixel: maxPixel) else { return nil }
        return image.jpegData(compressionQuality: 0.82)
    }

    /// 按最长边缩放（CFImageSource 的缩略图通道，避免把大图整读进内存）。
    private static func downsample(_ data: Data, maxPixel: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixel)
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: thumbnail)
    }

    /// 缩到指定边长并压成小图，给 Live Activity 的内联兜底用。
    static func tinyThumbnail(from data: Data, side: Int, quality: CGFloat) -> Data? {
        guard let image = downsample(data, maxPixel: side) else { return nil }
        return image.jpegData(compressionQuality: quality)
    }

    /// 把 JPEG 字节包成锁屏封面。解码失败时返回 1×1 空白图：
    /// `MPMediaItemArtwork` 的请求回调必须返回非可选 `UIImage`，不能返回 nil。
    static func mediaArtwork(from data: Data, side: CGSize = CGSize(width: 512, height: 512)) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: side) { _ in
            UIImage(data: data) ?? blankImage
        }
    }

    /// 1×1 透明图，仅用于「字节坏了」的极端情况，避免锁屏那块区域留空。
    private static let blankImage: UIImage = {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        return renderer.image { context in
            UIColor.clear.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
    }()
}
