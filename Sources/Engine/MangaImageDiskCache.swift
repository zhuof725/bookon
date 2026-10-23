import Foundation
import CryptoKit

/// 漫画图片磁盘缓存。
///
/// 对应原版 `BookHelp.saveImage`：漫画图片下载后写进缓存目录
/// （`downloadDir/cacheImageFolderName/<md5>.<后缀>`），同一章再看、断网重开都不重新下载。
/// 这里存的是**解密后**的图片字节（原版 `ImageUtils.decode` 之后才落盘），
/// 文件名用地址的 MD5，扩展名取地址里的后缀。
enum MangaImageDiskCache {
    static var directory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MangaImages", isDirectory: true)
    }

    /// 单张图片的缓存上限（12MB）：条漫单页偶尔很大，超过就不落盘。
    static let maxImageBytes = 12 * 1024 * 1024

    static func key(_ url: String) -> String {
        Insecure.MD5.hash(data: Data(url.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func fileURL(for url: String) -> URL {
        let suffix = suffix(of: url)
        return directory.appendingPathComponent(key(url)).appendingPathExtension(suffix)
    }

    /// 地址后缀（jpg/png/webp…），拿不到时用 jpg。
    private static func suffix(of url: String) -> String {
        let path = url.split(separator: "?", maxSplits: 1)[0].split(separator: "#", maxSplits: 1)[0]
        guard let ext = path.split(separator: ".").last.map(String.init)?.lowercased(),
              !ext.isEmpty, ext.count <= 5, ext.allSatisfy({ $0.isLetter || $0.isNumber }) else {
            return "jpg"
        }
        return ext
    }

    static func data(for url: String) -> Data? {
        guard let data = try? Data(contentsOf: fileURL(for: url)), !data.isEmpty else { return nil }
        return data
    }

    static func store(_ data: Data, for url: String) {
        guard !data.isEmpty, data.count <= maxImageBytes else { return }
        let fm = FileManager.default
        guard (try? fm.createDirectory(at: directory, withIntermediateDirectories: true)) != nil else { return }
        try? data.write(to: fileURL(for: url), options: .atomic)
    }

    @discardableResult
    static func removeAll() -> Int {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return 0 }
        var removed = 0
        for item in items where (try? fm.removeItem(at: item)) != nil { removed += 1 }
        return removed
    }

    static func diskBytes() -> Int64 {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        var total: Int64 = 0
        for item in items {
            total += Int64((try? item.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }
}

/// 有声书音频磁盘缓存。
///
/// 原版用 ExoPlayer 的 `SimpleCache`（边听边存，100MB）；AVPlayer 没有等价的流式缓存，
/// 这里改成「播放在线地址的同时后台把整段音频存下来」，下次同一章直接播本地文件：
/// 不耽误第一次起播，回听/断网也能用。
enum AudioDiskCache {
    static var directory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AudioChapters", isDirectory: true)
    }

    /// 单个音频文件的缓存上限（80MB）。
    static let maxFileBytes = 80 * 1024 * 1024

    static func key(_ url: String) -> String {
        Insecure.MD5.hash(data: Data(url.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func fileURL(for url: String) -> URL {
        directory.appendingPathComponent(key(url)).appendingPathExtension("audio")
    }

    /// 已缓存且文件非空。
    static func cachedFile(for url: String) -> URL? {
        let file = fileURL(for: url)
        guard let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.intValue,
              size > 0 else { return nil }
        return file
    }

    static func store(_ data: Data, for url: String) {
        guard !data.isEmpty, data.count <= maxFileBytes else { return }
        let fm = FileManager.default
        guard (try? fm.createDirectory(at: directory, withIntermediateDirectories: true)) != nil else { return }
        try? data.write(to: fileURL(for: url), options: .atomic)
    }

    @discardableResult
    static func removeAll() -> Int {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return 0 }
        var removed = 0
        for item in items where (try? fm.removeItem(at: item)) != nil { removed += 1 }
        return removed
    }

    static func diskBytes() -> Int64 {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        var total: Int64 = 0
        for item in items {
            total += Int64((try? item.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }
}
