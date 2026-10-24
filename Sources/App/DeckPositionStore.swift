import SwiftUI

/// 卡片类模板（弧形走廊 / 卡片堆叠）记住「滑到第几张」。
///
/// 为什么不放在 `@State` 里：这些板块在首页每次重建、以及进出「添加模板」预览时
/// 都会重新创建，`@State` 会跟着归零，用户一回头就跳回第一张。
/// 这里按「模板 + 书源 + 分类」做键存在内存里，App 运行期间一直有效；
/// 同时写入 UserDefaults，重启后也还在原位。
final class DeckPositionStore: @unchecked Sendable {
    /// 位置只被界面线程读写，但 `key(template:sourceUrl:kindUrl:)` 是纯函数、
    /// 不碰状态，必须能在任何上下文调用（DeckIdentity 就可能在非隔离处调用）。
    /// 所以类本身不加 @MainActor，只在读写字典时加锁。
    static let shared = DeckPositionStore()
    private let lock = NSLock()

    private var memory: [String: Int] = [:]
    private let defaultsKey = "discover.deckPositions"

    private init() {
        if let stored = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: Int] {
            memory = stored
        }
    }

    /// 取某个板块上次停留的下标。
    func position(for key: String) -> Int? {
        lock.lock(); defer { lock.unlock() }
        return memory[key]
    }

    /// 记下滑到第几张。相同值不重复写盘。
    func set(_ index: Int, for key: String) {
        lock.lock()
        guard memory[key] != index else { lock.unlock(); return }
        memory[key] = index
        let snapshot = memory
        lock.unlock()
        UserDefaults.standard.set(snapshot, forKey: defaultsKey)
    }

    /// 板块被删掉或书源换了时清掉，避免旧键累积。
    func remove(key: String) {
        lock.lock()
        let removed = memory.removeValue(forKey: key) != nil
        let snapshot = memory
        lock.unlock()
        guard removed else { return }
        UserDefaults.standard.set(snapshot, forKey: defaultsKey)
    }

    /// 「模板 + 书源 + 分类」拼出的唯一键。
    /// 分类用网址而不是标题：同一本书源的分类标题可能重名，网址才唯一。
    nonisolated static func key(template: DiscoverTemplateKind,
                    sourceUrl: String,
                    kindUrl: String) -> String {
        "\(template.rawValue)|\(sourceUrl)|\(kindUrl)"
    }
}
