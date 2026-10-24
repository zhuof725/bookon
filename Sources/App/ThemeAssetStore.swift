import SwiftUI
import Foundation
import UIKit
import ImageIO

/// Downsampling and disk reads stay off the main actor; stale requests cannot win.
@MainActor
final class ThemeAssetImageLoader: ObservableObject {
    @Published private(set) var image: UIImage?
    private(set) var assetID: String?
    private var generation = UUID()

    func load(_ id: String?, store: ThemeAssetStore = .shared) async {
        if assetID == id, image != nil { return }
        let token = UUID()
        generation = token
        assetID = id
        image = nil
        guard let id, ThemeAssetStore.isValidID(id) else { return }
        let decoded = await Task.detached(priority: .utility) { store.image(for: id) }.value
        guard !Task.isCancelled, generation == token, assetID == id else { return }
        image = decoded
    }
}

/// Durable app-owned assets. Theme JSON contains only UUID.jpg identifiers.
/// No method changes or deletes the user's original imported file.
final class ThemeAssetStore: @unchecked Sendable {
    nonisolated(unsafe) static let shared = ThemeAssetStore()
    static let maximumInputBytes = 20 * 1024 * 1024
    static let maximumPixelSize = 2000

    enum AssetError: LocalizedError {
        case invalidFile, tooLarge, invalidImage, unavailableDirectory
        var errorDescription: String? {
            switch self {
            case .invalidFile: return "无法读取这张图片，请重新选择本地图片。"
            case .tooLarge: return "主题图片不能超过 20 MB。"
            case .invalidImage: return "图片已损坏或格式不受支持。"
            case .unavailableDirectory: return "无法访问主题图片目录。"
            }
        }
    }

    private let directory: URL
    private let cache = NSCache<NSString, UIImage>()

    init(directory: URL? = nil) {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        // Resolve platform aliases (/var, tmp) in the trusted parent only.
        // Resolving the final leaf would silently trust a ThemeImages symlink.
        let requested = (directory ?? documents.appendingPathComponent("ThemeImages", isDirectory: true)).standardizedFileURL
        self.directory = requested.deletingLastPathComponent().resolvingSymlinksInPath()
            .appendingPathComponent(requested.lastPathComponent, isDirectory: true).standardizedFileURL
        cache.countLimit = 6
        cache.totalCostLimit = 48 * 1024 * 1024
    }

    static func isValidID(_ id: String) -> Bool {
        guard id.utf8.count == 40, id.hasSuffix(".jpg") || id.hasSuffix(".png") else { return false }
        let stem = String(id.dropLast(4))
        guard let uuid = UUID(uuidString: stem) else { return false }
        return uuid.uuidString.lowercased() == stem.lowercased()
    }

    /// Bounded plain symbol names only: never a path, URL or control sequence.
    static func isValidSymbolName(_ name: String) -> Bool {
        guard !name.isEmpty, name.utf8.count <= 128,
              !name.unicodeScalars.contains(where: {
                  CharacterSet.controlCharacters.contains($0) || CharacterSet.whitespacesAndNewlines.contains($0)
              }),
              !name.contains("/"), !name.contains("\\"), !name.contains(":") else { return false }
        return true
    }

    /// nil when the name fails validation or matches no SF Symbol.
    func symbolImage(for name: String) -> UIImage? {
        guard Self.isValidSymbolName(name) else { return nil }
        return UIImage(systemName: name)
    }

    func importFile(_ url: URL) throws -> String {
        guard url.isFileURL else { throw AssetError.invalidFile }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        return try importData(Self.readBounded(url))
    }

    func importData(_ data: Data) throws -> String {
        guard data.count <= Self.maximumInputBytes else { throw AssetError.tooLarge }
        guard !data.isEmpty, let bitmap = Self.downsample(data),
              let jpeg = UIImage(cgImage: bitmap).jpegData(compressionQuality: 0.88),
              jpeg.count <= Self.maximumInputBytes else { throw AssetError.invalidImage }
        try prepareDirectory()
        let id = UUID().uuidString.lowercased() + ".jpg"
        guard let target = ownedURL(id), !FileManager.default.fileExists(atPath: target.path) else {
            throw AssetError.unavailableDirectory
        }
        try jpeg.write(to: target, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        // Do not cache the source bitmap: reads should match the durable JPEG.
        return id
    }

    func importIconFile(_ url: URL) throws -> String {
        guard url.isFileURL else { throw AssetError.invalidFile }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        return try importIconData(Self.readBounded(url))
    }

    func importIconData(_ data: Data) throws -> String {
        guard data.count <= Self.maximumInputBytes else { throw AssetError.tooLarge }
        guard let bitmap = Self.downsample(data), let icon = ThemeIconTransparency.image(bitmap),
              let png = UIImage(cgImage: icon).pngData(), png.count <= Self.maximumInputBytes else {
            throw AssetError.invalidImage
        }
        try prepareDirectory()
        let id = UUID().uuidString.lowercased() + ".png"
        guard let target = ownedURL(id), !FileManager.default.fileExists(atPath: target.path) else {
            throw AssetError.unavailableDirectory
        }
        try png.write(to: target, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return id
    }

    func image(for id: String?) -> UIImage? {
        guard let id, let url = ownedURL(id), isRegularOwnedFile(url) else { return nil }
        if let image = cache.object(forKey: id as NSString) { return image }
        guard let data = try? Self.readBounded(url), let bitmap = Self.downsample(data) else { return nil }
        let image = UIImage(cgImage: bitmap)
        cache.setObject(image, forKey: id as NSString, cost: bitmap.bytesPerRow * bitmap.height)
        return image
    }

    /// Idempotent; refuses paths, directories and symbolic links, even in tests.
    func remove(_ id: String) {
        guard let url = ownedURL(id), isRegularOwnedFile(url) else { return }
        cache.removeObject(forKey: id as NSString)
        try? FileManager.default.removeItem(at: url)
    }

    private func prepareDirectory() throws {
        guard directory.isFileURL,
              directory.resolvingSymlinksInPath().standardizedFileURL.path == directory.path else {
            throw AssetError.unavailableDirectory
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard isOwnedDirectory else { throw AssetError.unavailableDirectory }
    }

    private var isOwnedDirectory: Bool {
        guard directory.isFileURL,
              directory.resolvingSymlinksInPath().standardizedFileURL.path == directory.path,
              let values = try? directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return false }
        return values.isDirectory == true && values.isSymbolicLink != true
    }

    private func ownedURL(_ id: String) -> URL? {
        guard Self.isValidID(id), isOwnedDirectory else { return nil }
        let result = directory.appendingPathComponent(id, isDirectory: false).standardizedFileURL
        guard result.deletingLastPathComponent().path == directory.path else { return nil }
        return result
    }

    private func isRegularOwnedFile(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
              values.isRegularFile == true, values.isSymbolicLink != true else { return false }
        return url.resolvingSymlinksInPath().standardizedFileURL.path == url.path
    }

    private static func readBounded(_ url: URL) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw AssetError.invalidFile }
        if let size = values.fileSize, size > maximumInputBytes { throw AssetError.tooLarge }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var data = Data()
        // A growing/replaced file cannot turn a metadata check into an unbounded read.
        while data.count <= maximumInputBytes {
            let count = min(1_048_576, maximumInputBytes + 1 - data.count)
            let chunk = try handle.read(upToCount: count) ?? Data()
            if chunk.isEmpty { break }
            data.append(chunk)
        }
        guard data.count <= maximumInputBytes else { throw AssetError.tooLarge }
        return data
    }

    private static func downsample(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData,
                [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0 else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize
        ] as CFDictionary)
    }
}
