import Foundation
import ActivityKit

/// 锁屏 / 灵动岛播放卡片的共享模型。
///
/// App 与 Widget Extension 各自编译同一份源码（两个 target 的 module 名不同，
/// ActivityKit 按类型名匹配，这正是官方 sample 的做法）。
/// 只有 ContentState 会随更新下发；「播放类别」在 request 时固定，所以放属性里。
struct NowPlayingAttributes: ActivityAttributes {
    /// 播放类别：书源音频（有声书）或文字朗读（TTS）。
    enum Kind: String, Codable, Hashable, Sendable {
        case audio
        case aloud
    }

    struct ContentState: Codable, Hashable, Sendable {
        /// 章节标题。
        var title: String
        /// 书名；有声书带「有声书」，朗读带引擎名。
        var subtitle: String
        var isPlaying: Bool
        var elapsed: Double
        var duration: Double
        /// 封面：App Group 容器里的文件名。nil 表示没写成，改看下面的内联图。
        var coverFile: String?
        /// 封面：内联的极小缩略图（JPEG base64）。
        /// ContentState 整个编码后不能超过 4 KB，所以只在共享容器不可用时才带，
        /// 且上限卡得很死（见 NowPlayingActivityController）。都没有就显示占位图标。
        var coverInlineBase64: String?
        /// 进度条的基准时刻：播放中交给系统自己推进，省掉逐秒刷新。
        var referenceDate: Date

        /// 解码内联封面；没有或损坏返回 nil。
        var inlineCoverData: Data? {
            guard let coverInlineBase64 else { return nil }
            return Data(base64Encoded: coverInlineBase64)
        }
    }

    var kind: Kind
}
