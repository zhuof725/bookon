import SwiftUI

/// 音频章节阅读界面：封面 + 章节信息 + 进度 + 播放控制 + 倍速。
struct AudioChapterView: View {
    @ObservedObject var audio: BookAudioPlayer
    let book: Book
    let positionLabel: String
    let onPrevious: () -> Void
    let onNext: () -> Void

    @ThemePalette private var palette
    @State private var scrub: Double?

    private let speedPresets: [Double] = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)
            BookCoverImage(url: BookCoverLocation.url(for: book), pixelSize: 900)
                .frame(width: 200, height: 266)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.2), radius: 16, x: 0, y: 8)
                .accessibilityIdentifier("reader.audio.cover")
            VStack(spacing: 6) {
                Text(book.name).appFont(.headline).lineLimit(1)
                Text(audio.chapterTitle)
                    .appFont(.subheadline).foregroundStyle(palette.secondary)
                    .lineLimit(2).multilineTextAlignment(.center)
                    .accessibilityIdentifier("reader.audio.title")
                Text(positionLabel).appFont(.caption).foregroundStyle(palette.secondary)
            }
            .padding(.top, 16)
            .padding(.horizontal, 24)
            Spacer(minLength: 8)
            progressBlock.padding(.horizontal, 28)
            controls.padding(.top, 4)
            speedRow.padding(.top, 4)
            Group {
                if audio.isBuffering {
                    Text("正在缓冲…")
                } else if let message = audio.message {
                    Text(message)
                } else {
                    Text(" ")
                }
            }
            .appFont(.caption)
            .foregroundStyle(audio.message == nil ? palette.secondary : .red)
            .lineLimit(2)
            .padding(.top, 6)
            .padding(.horizontal, 24)
            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(palette.primary)
        .tint(palette.accent)
        .animation(.easeInOut(duration: 0.15), value: audio.isPlaying)
    }

    private var fraction: Double {
        guard audio.duration > 0 else { return 0 }
        return min(max(audio.currentTime / audio.duration, 0), 1)
    }

    private var progressBlock: some View {
        VStack(spacing: 0) {
            Slider(value: Binding(get: { scrub ?? fraction },
                                  set: { scrub = $0 }), in: 0...1) { editing in
                if !editing, let value = scrub {
                    scrub = nil
                    audio.seek(toSeconds: value * audio.duration)
                }
            }
            .tint(palette.accent)
            .disabled(audio.duration <= 0)
            .accessibilityIdentifier("reader.audio.slider")
            .accessibilityLabel("播放进度")
            HStack {
                Text(PlaybackTimeText.string(audio.currentTime))
                    .accessibilityIdentifier("reader.audio.timeCurrent")
                Spacer()
                Text("-" + PlaybackTimeText.string(max(audio.duration - audio.currentTime, 0)))
                    .accessibilityIdentifier("reader.audio.timeRemaining")
            }
            .appFont(.caption)
            .monospacedDigit()
            .foregroundStyle(palette.secondary)
        }
    }

    private var controls: some View {
        HStack(spacing: 0) {
            controlButton(symbol: "gobackward.15", label: "后退15秒",
                          id: "reader.audio.back15") { audio.skip(-15) }
            controlButton(symbol: "backward.end.fill", label: "上一章",
                          id: "reader.audio.prevChapter", action: onPrevious)
            playButton
            controlButton(symbol: "forward.end.fill", label: "下一章",
                          id: "reader.audio.nextChapter", action: onNext)
            controlButton(symbol: "goforward.15", label: "前进15秒",
                          id: "reader.audio.forward15") { audio.skip(15) }
        }
    }

    private func controlButton(symbol: String, label: String, id: String,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 26))
                .foregroundStyle(palette.primary)
                .frame(maxWidth: .infinity, minHeight: 72)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    private var playButton: some View {
        Button { audio.toggle() } label: {
            ZStack {
                Circle().fill(palette.accent).frame(width: 74, height: 74)
                if audio.isBuffering {
                    ProgressView().tint(palette.onAccent)
                } else {
                    Image(systemName: audio.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(palette.onAccent)
                        .offset(x: audio.isPlaying ? 0 : 3)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 72)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(audio.isPlaying ? "暂停" : "播放")
        .accessibilityIdentifier("reader.audio.play")
    }

    private var speedRow: some View {
        Menu {
            ForEach(speedPresets.indices, id: \.self) { i in
                Button {
                    audio.speed = speedPresets[i]
                } label: {
                    if abs(audio.speed - speedPresets[i]) < 0.01 {
                        Label(speedText(speedPresets[i]), systemImage: "checkmark")
                    } else {
                        Text(speedText(speedPresets[i]))
                    }
                }
                .accessibilityIdentifier("reader.audio.speed.\(speedText(speedPresets[i]))")
            }
        } label: {
            Text(speedText(audio.speed) + " 倍速")
                .appFont(.subheadline)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("倍速")
        .accessibilityIdentifier("reader.audio.speed")
    }

    private func speedText(_ value: Double) -> String {
        if value == value.rounded() { return String(format: "%.1fx", value) }
        return String(format: "%gx", value)
    }
}
