import SwiftUI

/// 底栏上方的迷你播放条：封面 + `书名 - 章节` + 播放/暂停 + 列表 + 关闭。
/// 只在「有收听会话、且阅读器不在前台」时出现（阅读器自带控制条）。
/// 点条身/列表回到完整的听书界面；右侧 × 结束收听并收起这条。
struct ListeningBar: View {
    @ObservedObject private var center = ListeningCenter.shared
    @ObservedObject private var aloud = ListeningCenter.shared.aloud
    @ObservedObject private var audio = ListeningCenter.shared.audio
    @ThemePalette private var palette

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 10) {
                cover
                Text(center.displayTitle)
                    .appFont(.footnote.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(palette.primary)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .onTapGesture { center.openPlayer() }
            .accessibilityIdentifier("listening.bar.title")

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

            Button { center.openPlayer() } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(palette.primary)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("播放列表")
            .accessibilityIdentifier("listening.bar.list")

            Button { center.stopAll() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.secondary)
                    .frame(width: 30, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭播放条")
            .accessibilityIdentifier("listening.bar.close")
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .frame(height: 48)
        .background {
            AppGlassSurface(shape: RoundedRectangle(cornerRadius: 24, style: .continuous), tint: palette.surface)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
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

/// 从迷你条打开的完整听书界面：朗读走 `AloudPlayerView`，
/// 有声书走 `AudioChapterView`（和阅读页里是同一个界面）。
struct ListeningPlayerScreen: View {
    @ObservedObject private var center = ListeningCenter.shared
    @ObservedObject private var aloud = ListeningCenter.shared.aloud
    @ObservedObject private var audio = ListeningCenter.shared.audio
    @Environment(\.dismiss) private var dismiss
    @State private var showToc = false

    private var currentChapter: BookChapter? {
        center.chapters.indices.contains(center.chapterIndex) ? center.chapters[center.chapterIndex] : nil
    }

    private var nextChapterTitle: String? {
        let next = center.chapterIndex + 1
        return center.chapters.indices.contains(next) ? center.chapters[next].title : nil
    }

    var body: some View {
        Group {
            if let book = center.book, center.mode == .aloud {
                AloudPlayerView(aloud: aloud, book: book, chapters: center.chapters,
                                currentChapter: currentChapter)
            } else if let book = center.book {
                AudioChapterView(audio: audio, book: book,
                                 chapterNumber: max(center.chapterIndex, 0) + 1,
                                 chapterCount: center.chapters.count,
                                 nextChapterTitle: nextChapterTitle,
                                 sourceChapterURL: currentChapter?.url,
                                 source: center.source,
                                 onLoadParagraphs: { await center.chapterParagraphs(center.chapterIndex) },
                                 onLoadLyric: { center.chapterLyric(center.chapterIndex) },
                                 onPrevious: { center.skipChapter(-1) },
                                 onNext: { center.skipChapter(1) },
                                 onBack: { dismiss() },
                                 onTOC: { showToc = true })
            } else {
                Color.clear.onAppear { dismiss() }
            }
        }
        .sheet(isPresented: $showToc) {
            ListeningTocSheet().modifier(AppThemeRoot())
        }
    }
}

/// 有声书播放器里的「目录」：挑一章继续听。
private struct ListeningTocSheet: View {
    @ObservedObject private var center = ListeningCenter.shared
    @ThemePalette private var palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(center.chapters.enumerated()), id: \.offset) { index, chapter in
                    Button {
                        dismiss()
                        Task { @MainActor in await center.playAudio(index) }
                    } label: {
                        HStack(spacing: 10) {
                            Text(chapter.title)
                                .appFont(.subheadline)
                                .foregroundStyle(index == center.chapterIndex ? palette.primary : palette.primary.opacity(0.75))
                                .lineLimit(2)
                            Spacer(minLength: 8)
                            if index == center.chapterIndex {
                                Image(systemName: "waveform")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(palette.primary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.plain)
            .navigationTitle(center.book?.name ?? "目录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
