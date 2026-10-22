import Foundation
import CryptoKit

/// 封面本地缓存：下载过的封面落到本机（Caches/Covers），换网络/开 VPN 也能显示。
/// 键是封面地址的 MD5，文件是原始字节（显示时再按需要缩放，避免大图占内存）。
enum CoverDiskCache {
    static var directory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Covers", isDirectory: true)
    }

    /// 封面地址 → 缓存文件路径（不保证文件存在）。
    static func fileURL(for url: URL) -> URL {
        let key = Insecure.MD5.hash(data: Data(url.absoluteString.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(key).appendingPathExtension("img")
    }

    /// 读缓存字节；没有或读失败返回 nil。
    static func data(for url: URL) -> Data? {
        let file = fileURL(for: url)
        guard let data = try? Data(contentsOf: file), !data.isEmpty else { return nil }
        return data
    }

    /// 写缓存字节（空数据不写；超大文件不写，避免个别大图撑爆缓存）。
    static func store(_ data: Data, for url: URL) {
        guard !data.isEmpty, data.count <= maxCoverBytes else { return }
        let file = fileURL(for: url)
        let fm = FileManager.default
        guard (try? fm.createDirectory(at: directory, withIntermediateDirectories: true)) != nil else { return }
        try? data.write(to: file, options: .atomic)
    }

    /// 单个封面的缓存上限（4MB）：超过的封面不落盘。
    static let maxCoverBytes = 4 * 1024 * 1024

    /// 清空封面缓存，返回删除的文件数。
    @discardableResult
    static func removeAll() -> Int {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return 0 }
        var removed = 0
        for item in items {
            if (try? fm.removeItem(at: item)) != nil { removed += 1 }
        }
        return removed
    }

    /// 封面缓存占用空间（字节）。
    static func diskBytes() -> Int64 {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        var total: Int64 = 0
        for item in items {
            let size = (try? item.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            total += Int64(size)
        }
        return total
    }
}
