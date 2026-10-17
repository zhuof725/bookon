import Foundation

/// 播放进度时间显示（分:秒）：朗读播放器与音频书共用。
enum PlaybackTimeText {
    static func string(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds.rounded()), 0)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
