import Foundation
import ActivityKit

/// Live Activity（灵动岛 / 锁屏播放卡片）的生命周期管理。
///
/// 同一时刻只挂一张卡：有声书与文字朗读共用一个入口，切换播放类型时收掉旧的、起新的。
@MainActor
final class NowPlayingActivityController {
    static let shared = NowPlayingActivityController()

    private var activity: Activity<NowPlayingAttributes>?

    /// 已写入共享容器的封面：键 → 文件名。写成功过就一直复用，不再重复落盘。
    private var storedCoverKey: String?
    private var storedCoverFile: String?
    /// 共享容器不可用时退化成的内联缩略图（同一本书复用）。
    private var inlineCoverKey: String?
    private var inlineCoverBase64: String?

    private init() {}

    private var activitiesEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    /// 起卡（同类型已在则改为更新，不重复 request）。
    func start(
        kind: NowPlayingAttributes.Kind,
        title: String,
        subtitle: String,
        isPlaying: Bool,
        elapsed: Double,
        duration: Double,
        coverKey: String?,
        coverData: Data?
    ) {
        guard activitiesEnabled else { return }
        if let activity, activity.attributes.kind != kind { endImmediately() }

        let state = makeState(
            title: title, subtitle: subtitle, isPlaying: isPlaying,
            elapsed: elapsed, duration: duration,
            coverKey: coverKey, coverData: coverData
        )
        if let activity, activity.attributes.kind == kind {
            Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
            return
        }
        do {
            activity = try Activity.request(
                attributes: NowPlayingAttributes(kind: kind),
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
        } catch {
            // 用户关了实时活动、或系统拒绝时安静降级；不能影响播放。
            activity = nil
        }
    }

    /// 只更新进度/状态，不碰封面。
    func update(
        title: String,
        subtitle: String,
        isPlaying: Bool,
        elapsed: Double,
        duration: Double
    ) {
        guard let activity else { return }
        var state = activity.content.state
        state.title = title
        state.subtitle = subtitle
        state.isPlaying = isPlaying
        state.elapsed = elapsed
        state.duration = duration
        state.referenceDate = Date()
        Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
    }

    /// 正常收卡：先钉在「已暂停」停在锁屏上，半小时后由系统收起。
    func end() {
        guard let activity else { return }
        var final = activity.content.state
        final.isPlaying = false
        final.referenceDate = Date()
        Task {
            await activity.end(
                ActivityContent(state: final, staleDate: nil),
                dismissalPolicy: .after(Date().addingTimeInterval(30 * 60))
            )
        }
        release()
    }

    /// 立刻收掉（切换播放器 / 停止播放）。
    func endImmediately() {
        guard let activity else { release(); return }
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
        release()
    }

    private func release() {
        activity = nil
        storedCoverKey = nil
        storedCoverFile = nil
        inlineCoverKey = nil
        inlineCoverBase64 = nil
        NowPlayingCoverStore.removeAll()
    }

    // MARK: 状态组装

    private func makeState(
        title: String,
        subtitle: String,
        isPlaying: Bool,
        elapsed: Double,
        duration: Double,
        coverKey key: String?,
        coverData: Data?
    ) -> NowPlayingAttributes.ContentState {
        var state = NowPlayingAttributes.ContentState(
            title: title,
            subtitle: subtitle,
            isPlaying: isPlaying,
            elapsed: elapsed,
            duration: duration,
            coverFile: nil,
            coverInlineBase64: nil,
            referenceDate: Date()
        )
        guard let key else { return state }

        // 换了书才重算封面；同一本书翻章直接复用上次的结果。
        if storedCoverKey != key {
            storedCoverKey = key
            storedCoverFile = nil
            inlineCoverBase64 = nil
            if let data = coverData {
                // 首选共享容器。存量要缩：Live Activity 的图片超过呈现尺寸时，
                // 系统可能直接让这张活动起不来（灵动岛圆点才 20pt，锁屏卡 58pt）。
                let sized = CoverArtworkLoader.tinyThumbnail(from: data, side: 240, quality: 0.8) ?? data
                storedCoverFile = NowPlayingCoverStore.store(sized, key: key)
                if storedCoverFile == nil {
                    // 落盘失败（未签名包常丢 App Group 权限）就退化到内联小图。
                    inlineCoverBase64 = makeInlineCover(from: data)
                }
            }
            inlineCoverKey = key
        }
        state.coverFile = storedCoverFile
        if storedCoverFile == nil, inlineCoverKey == key {
            state.coverInlineBase64 = inlineCoverBase64
        }
        return state
    }

    /// 内联兜底图：尺寸小、质量低，为了塞进 ContentState 的 4 KB 里。
    /// 灵动岛紧凑态那颗圆点约 40pt@3x，72px 够用。
    private func makeInlineCover(from data: Data) -> String? {
        // 逐级降质，取第一个能让整个 ContentState 编码后不超过预算的。
        for (side, quality) in [(72, 0.4), (64, 0.3), (56, 0.25)] {
            guard let tiny = CoverArtworkLoader.tinyThumbnail(from: data, side: side, quality: quality) else {
                continue
            }
            let base64 = tiny.base64EncodedString()
            if contentStateFits(base64: base64) { return base64 }
        }
        return nil
    }

    /// ContentState 整个编码后必须小于 4 KB（ActivityKit 的硬限制）。
    /// 用真实编码长度判断，而不是估算 base64 字符数——标题里也可能有中文和 emoji。
    private func contentStateFits(base64: String) -> Bool {
        var probe = NowPlayingAttributes.ContentState(
            title: String(repeating: "标", count: 40),
            subtitle: String(repeating: "副", count: 40),
            isPlaying: true,
            elapsed: 99_999,
            duration: 99_999,
            coverFile: nil,
            coverInlineBase64: base64,
            referenceDate: Date()
        )
        probe.coverInlineBase64 = base64
        guard let encoded = try? JSONEncoder().encode(probe) else { return false }
        // 留 512 字节余量给运行时补的字段与编码差异。
        return encoded.count < 4096 - 512
    }
}
