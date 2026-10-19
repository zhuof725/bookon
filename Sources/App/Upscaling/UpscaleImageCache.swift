import UIKit
import CryptoKit

/// 放大后图片的缓存（内存 + 磁盘）。主要给封面用：书架一次几十张，
/// 不能每次滚动都重新推理；漫画页只用内存缓存（单张太大，磁盘会很快膨胀）。
enum UpscaleImageCache {
    private static let memory = NSCache<NSString, UIImage>()

    /// 缓存键：来源 + 目标尺寸 + 档位（换模型/换尺寸要重新推理）。
    static func key(_ parts: String) -> String {
        Insecure.MD5.hash(data: Data(parts.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func image(forKey key: String) -> UIImage? {
        if let hit = memory.object(forKey: key as NSString) { return hit }
        guard let url = fileURL(forKey: key),
              let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else { return nil }
        memory.setObject(image, forKey: key as NSString)
        return image
    }

    static func store(_ image: UIImage, forKey key: String) {
        memory.setObject(image, forKey: key as NSString)
        guard let url = fileURL(forKey: key), let data = image.pngData() else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// 磁盘占用上限：超过就整目录清空（封面都是小图，简单处理就够）。
    static func pruneIfNeeded(limitBytes: Int = 64 * 1024 * 1024) {
        guard let dir = directory() else { return }
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else { return }
        var total = 0
        for file in files {
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            total += size
        }
        guard total > limitBytes else { return }
        for file in files { try? fm.removeItem(at: file) }
    }

    /// 清空缓存（内存 + 磁盘）。模型换过、或旧版本存过坏图（比如全黑的封面）时用。
    static func clearAll() {
        memory.removeAllObjects()
        guard let base = try? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask,
                                                      appropriateFor: nil, create: true) else { return }
        try? FileManager.default.removeItem(at: base.appendingPathComponent("LegadoReading/upscaled", isDirectory: true))
        try? FileManager.default.removeItem(at: base.appendingPathComponent("LegadoReading/upscaled-v2", isDirectory: true))
    }

    // MARK: 内部

    /// 目录带版本号：早期版本（v1）在推理失败时会把整张黑图缓存下来，
    /// 换目录名可以直接让那些坏缓存失效。
    private static func directory() -> URL? {
        let base = try? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask,
                                                appropriateFor: nil, create: true)
        guard let base else { return nil }
        let dir = base.appendingPathComponent("LegadoReading/upscaled-v2", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private static func fileURL(forKey key: String) -> URL? {
        directory()?.appendingPathComponent(key + ".png")
    }
}
