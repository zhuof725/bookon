import SwiftUI

/// 底栏上方的迷你播放条：封面 + `书名 - 章节` + 播放/暂停 + 列表。
/// 只在「有收听会话、且阅读器不在前台」时出现（阅读器自带控制条）。
struct ListeningBar: View {
    @ObservedObject private var center = ListeningCenter.shared
    @ObservedObject private var aloud = ListeningCenter.shared.aloud
    @ObservedObject private var audio = ListeningCenter.shared.audio
    @ThemePalette private var palette

    var body: some View {
        HStack(spacing: 10) {
            cover
            Text(center.displayTitle)
                .appFont(.footnote.weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(palette.primary)
                .contentShape(Rectangle())
                .onTapGesture { center.showSheet = true }
                .accessibilityIdentifier("listening.bar.title")
            Spacer(minLength: 4)
            Button { center.toggle() } label: {
                Image(systemName: center.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(palette.primary)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(center.isPlaying ? "暂停" : "播放")
            .accessibilityIdentifier("listening.bar.toggle")
            Button { center.showSheet = true } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(palette.primary)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("播放列表")
            .accessibilityIdentifier("listening.bar.list")
        }
        .padding(.horizontal, 10)
        .frame(height: 48)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var cover: some View {
        if let book = center.book {
            BookCoverImage(url: BookCoverLocation.url(for: book), pixelSize: 120, origin: book.origin)
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(palette.primary.opacity(0.08))
                }
        } else {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(palette.primary.opacity(0.1))
                .frame(width: 32, height: 32)
        }
    }
}

/// 收听面板：迷你条点开后的简版播放器（两种收听方式共用）。
struct ListeningSheet: View {
    @ObservedObject private var center = ListeningCenter.shared
    @ObservedObject private var aloud = ListeningCenter.shared.aloud
    @ObservedObject private var audio = ListeningCenter.shared.audio
    @ThemePalette private var palette
    @Environment(\.dismiss) private var dismiss

    private var elapsed: TimeInterval? {
        switch center.mode {
        case .aloud:
            return aloud.chapterDuration > 0 ? aloud.chapterPlayed : nil
        case .audio:
            return audio.duration > 0 ? audio.currentTime : nil
        case .none:
            return nil
        }
    }

    private var total: TimeInterval? {
        switch center.mode {
        case .aloud:
            return aloud.chapterDuration > 0 ? aloud.chapterDuration : nil
        case .audio:
            return audio.duration > 0 ? audio.duration : nil
        case .none:
            return nil
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(palette.primary.opacity(0.16))
                .frame(width: 36, height: 5)
                .padding(.top, 10)
            HStack {
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.primary)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("收起")
            }
            .padding(.horizontal, 10)

            if let book = center.book {
                BookCoverImage(url: BookCoverLocation.url(for: book), pixelSize: 700, origin: book.origin)
                    .frame(width: 132, height: 176)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: .black.opacity(0.16), radius: 16, y: 8)
                    .padding(.top, 4)
            }

            VStack(spacing: 6) {
                Text(center.book?.name ?? "")
                    .appFont(.title3.weight(.semibold))
                    .foregroundStyle(palette.primary)
                    .lineLimit(1)
                Text(center.chapterTitle)
                    .appFont(.subheadline)
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
            }
            .padding(.top, 18)
            .padding(.horizontal, 24)

            progressView
                .padding(.top, 20)
                .padding(.horizontal, 24)

            HStack(spacing: 34) {
                control("backward.end.fill", label: "上一章") { center.skipChapter(-1) }
                Button { center.toggle() } label: {
                    ZStack {
                        Circle().fill(palette.primary).frame(width: 66, height: 66)
                        if center.isPlaying {
                            Image(systemName: "pause.fill")
                                .font(.system(size: 26, weight: .semibold))
                                .foregroundStyle(palette.background)
                        } else {
                            Image(systemName: "play.fill")
                                .font(.system(size: 26, weight: .semibold))
                                .foregroundStyle(palette.background)
                                .offset(x: 2)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(center.isPlaying ? "暂停" : "播放")
                .accessibilityIdentifier("listening.sheet.toggle")
                control("forward.end.fill", label: "下一章") { center.skipChapter(1) }
            }
            .padding(.top, 18)

            Button {
                center.stopAll()
                dismiss()
            } label: {
                Text("停止收听")
                    .appFont(.subheadline.weight(.medium))
                    .foregroundStyle(palette.primary.opacity(0.85))
                    .padding(.horizontal, 22)
                    .frame(height: 38)
                    .background { AppGlassSurface(shape: Capsule(), tint: palette.surface) }
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 22)
            .accessibilityIdentifier("listening.sheet.stop")

            Spacer(minLength: 12)
        }
        .frame(maxWidth: .infinity)
        .background { AppThemeCanvas().ignoresSafeArea() }
        .presentationDetents([.height(520), .large])
        .presentationDragIndicator(.hidden)
    }

    @ViewBuilder private var progressView: some View {
        if let progress = center.progress, let elapsed, let total {
            VStack(spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(palette.primary.opacity(0.12))
                        Capsule().fill(palette.primary)
                            .frame(width: max(geo.size.width * progress, 2))
                    }
                }
                .frame(height: 4)
                HStack {
                    Text(PlaybackTimeText.string(elapsed))
                    Spacer()
                    Text(PlaybackTimeText.string(total))
                }
                .appFont(.caption2)
                .foregroundStyle(palette.secondary)
                .monospacedDigit()
            }
        }
    }

    private func control(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 24))
                .foregroundStyle(palette.primary)
                .frame(width: 56, height: 56)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
