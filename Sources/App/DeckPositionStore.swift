import SwiftUI

/// 卡片类模板（弧形走廊 / 卡片堆叠）记住「滑到第几张」。
///
/// 为什么不放在 `@State` 里：这些板块在首页每次重建、以及进出「添加模板」预览时
/// 都会重新创建，`@State` 会跟着归零，用户一回头就跳回第一张。
/// 这里按「模板 + 书源 + 分类」做键存在内存里，App 运行期间一直有效；
/// 同时写入 UserDefaults，重启后也还在原位。
@MainActor
final class DeckPositionStore {
    static let shared = DeckPositionStore()

    private var memory: [String: Int] = [:]
    private let defaultsKey = "discover.deckPositions"

    private init() {
        if let stored = UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: Int] {
            memory = stored
        }
    }

    /// 取某个板块上次停留的下标。
    func position(for key: String) -> Int? {
        memory[key]
    }

    /// 记下滑到第几张。相同值不重复写盘。
    func set(_ index: Int, for key: String) {
        guard memory[key] != index else { return }
        memory[key] = index
        UserDefaults.standard.set(memory, forKey: defaultsKey)
    }

    /// 板块被删掉或书源换了时清掉，避免旧键累积。
    func remove(key: String) {
        guard memory.removeValue(forKey: key) != nil else { return }
        UserDefaults.standard.set(memory, forKey: defaultsKey)
    }

    /// 「模板 + 书源 + 分类」拼出的唯一键。
    /// 分类用网址而不是标题：同一本书源的分类标题可能重名，网址才唯一。
    static func key(template: DiscoverTemplateKind,
                    sourceUrl: String,
                    kindUrl: String) -> String {
        "\(template.rawValue)|\(sourceUrl)|\(kindUrl)"
    }
}
