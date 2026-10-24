import WidgetKit
import SwiftUI
import ActivityKit
import UIKit

/// 灵动岛 / 锁屏播放卡片的界面。
///
/// 封面来源有两级：App Group 共享文件（首选）→ ContentState 里的内联小图（兜底）
/// → 都没有则显示占位音符。文件读取必须放在主线程之外做缓存，
/// 否则每次 timeline 刷新都会同步读盘，灵动岛会掉帧。
struct NowPlayingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NowPlayingAttributes.self) { context in
            LockScreenCard(context: context)
                .activityBackgroundTint(Color.black.opacity(0.28))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    CoverThumb(state: context.state, side: 52, corner: 8)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    PlayStateBadge(isPlaying: context.state.isPlaying)
                        .padding(.top, 2)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(context.state.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ProgressRow(
                        elapsed: context.state.elapsed,
                        duration: context.state.duration,
                        isPlaying: context.state.isPlaying,
                        referenceDate: context.state.referenceDate,
                        compact: true
                    )
                }
            } compactLeading: {
                // 紧凑态那颗小圆点：封面做成圆形，没有封面时退回音符图标。
                CoverThumb(state: context.state, side: 20, corner: 10, circular: true)
            } compactTrailing: {
                Image(systemName: context.state.isPlaying ? "waveform" : "pause.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
            } minimal: {
                CoverThumb(state: context.state, side: 18, corner: 9, circular: true)
            }
            .keylineTint(.white.opacity(0.35))
        }
    }
}

// MARK: - 锁屏卡片

private struct LockScreenCard: View {
    let context: ActivityViewContext<NowPlayingAttributes>

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CoverThumb(state: context.state, side: 58, corner: 9)
            VStack(alignment: .leading, spacing: 3) {
                Text(context.state.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Text(context.state.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                ProgressRow(
                    elapsed: context.state.elapsed,
                    duration: context.state.duration,
                    isPlaying: context.state.isPlaying,
                    referenceDate: context.state.referenceDate,
                    compact: false
                )
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
            PlayStateBadge(isPlaying: context.state.isPlaying)
                .padding(.top, 2)
        }
        .padding(14)
    }
}

// MARK: - 零件

/// 封面方块：共享文件优先，其次内联小图，最后占位图标。
private struct CoverThumb: View {
    let state: NowPlayingAttributes.ContentState
    let side: CGFloat
    let corner: CGFloat
    var circular = false

    var body: some View {
        Group {
            if let image = CoverImageStore.shared.image(for: state) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    LinearGradient(
                        colors: [Color.white.opacity(0.18), Color.white.opacity(0.06)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                    Image(systemName: "headphones")
                        .font(.system(size: side * 0.4, weight: .light))
                        .foregroundStyle(.white.opacity(0.65))
                }
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(.white.opacity(0.16), lineWidth: 0.5)
        }
    }
}

private struct PlayStateBadge: View {
    let isPlaying: Bool

    var body: some View {
        Image(systemName: isPlaying ? "waveform" : "pause.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.75))
    }
}

/// 进度条 + 两侧时间。播放中不逐秒刷新：给系统一个基准时刻，让它自己走。
private struct ProgressRow: View {
    let elapsed: Double
    let duration: Double
    let isPlaying: Bool
    let referenceDate: Date
    let compact: Bool

    var body: some View {
        if duration > 0 {
            VStack(spacing: 2) {
                if isPlaying {
                    ProgressView(
                        timerInterval: referenceDate...referenceDate.addingTimeInterval(max(duration - elapsed, 0.1)),
                        countsDown: false
                    ) {
                        EmptyView()
                    } currentValueLabel: {
                        EmptyView()
                    }
                    .progressViewStyle(.linear)
                    .tint(.white.opacity(0.85))
                } else {
                    ProgressView(value: min(max(elapsed / duration, 0), 1))
                        .progressViewStyle(.linear)
                        .tint(.white.opacity(0.85))
                }
                if !compact {
                    HStack {
                        Text(Self.format(elapsed))
                        Spacer(minLength: 0)
                        Text("-" + Self.format(max(duration - elapsed, 0)))
                    }
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private static func format(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - 封面读取缓存

/// 共享容器的封面文件按文件名缓存，避免每条 timeline 都同步读盘。
///
/// `@unchecked Sendable` 的理由：这个类没有可变实例状态，
/// 唯一的存储是 NSCache（Apple 明确保证线程安全），
/// 加 @MainActor 反而会让 widget 的渲染路径被迫切主线程。
private final class CoverImageStore: @unchecked Sendable {
    static let shared = CoverImageStore()
    private nonisolated(unsafe) static let cache = NSCache<NSString, UIImage>()

    func image(for state: NowPlayingAttributes.ContentState) -> UIImage? {
        if let file = state.coverFile {
            let key = file as NSString
            if let hit = Self.cache.object(forKey: key) { return hit }
            if let data = NowPlayingCoverStore.data(named: file), let decoded = UIImage(data: data) {
                Self.cache.setObject(decoded, forKey: key, cost: data.count)
                return decoded
            }
        }
        if let data = state.inlineCoverData, let decoded = UIImage(data: data) {
            return decoded
        }
        return nil
    }
}

@main
struct NowPlayingWidgetBundle: WidgetBundle {
    var body: some Widget {
        NowPlayingLiveActivity()
    }
}
