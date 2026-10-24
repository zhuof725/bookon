import Foundation
import CryptoKit

/// 封面跨进程传递：App 把缩略图写进 App Group 容器，Widget Extension 读同一份文件。
///
/// Live Activity 的 ContentState 有 4 KB 上限，塞不下图片字节，所以图片只能落盘。
/// 自签工具没给 App Group entitlement 时 `containerURL` 返回 nil，
/// 这里静默退化成 nil —— 卡片仍能显示，只是没有封面，不能因此让播放失败。
enum NowPlayingCoverStore {
    /// 必须与 project.yml 里 app 与 widget 两个 target 的 entitlement 一致。
    static let appGroupID = "group.io.github.xianghuo.book"

    private static let folderName = "NowPlayingCovers"

    /// 共享容器里的封面目录；App Group 不可用时为 nil。
    static var directory: URL? {
        guard let base = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupID
        ) else { return nil }
        let dir = base.appendingPathComponent(folderName, isDirectory: true)
        guard (try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)) != nil else {
            return nil
        }
        return dir
    }

    /// 封面键 → 稳定文件名。同一本书跨章节复用同一张图，不必反复写盘。
    static func fileName(for key: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(key.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return "\(digest).jpg"
    }

    /// 写入封面，返回文件名；App Group 不可用或写失败返回 nil。
    @discardableResult
    static func store(_ data: Data, key: String) -> String? {
        guard !data.isEmpty, let directory else { return nil }
        let name = fileName(for: key)
        let file = directory.appendingPathComponent(name)
        guard (try? data.write(to: file, options: .atomic)) != nil else { return nil }
        return name
    }

    /// 读封面字节；文件不存在或为空返回 nil。
    static func data(named name: String) -> Data? {
        guard let directory else { return nil }
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(name)),
              !data.isEmpty else { return nil }
        return data
    }

    /// 停止播放时清理，避免共享容器里堆历史封面。
    static func removeAll() {
        guard let directory,
              let items = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil
              ) else { return }
        for item in items { try? FileManager.default.removeItem(at: item) }
    }
}
