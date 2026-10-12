import SwiftUI
import UIKit
import ImageIO

/// Place in a safe-area-respecting `.overlay(alignment: .top)`.
/// Only the individual controls have hit regions; there is no backdrop.
struct ReaderTopChrome: View {
    let title: String
    let source: String
    let coverURL: URL?
    let background: Color
    let foreground: Color
    let onBack: () -> Void
    let onDetails: () -> Void

    @ScaledMetric(relativeTo: .subheadline) private var titleSize: CGFloat = 15
    @ScaledMetric(relativeTo: .caption) private var sourceSize: CGFloat = 12
    @Environment(\.dynamicTypeSize) private var typeSize

    init(title: String, source: String, coverURL: URL?, background: Color,
         foreground: Color, onBack: @escaping () -> Void,
         onDetails: @escaping () -> Void) {
        self.title = title
        self.source = source
        self.coverURL = coverURL
        self.background = background
        self.foreground = foreground
        self.onBack = onBack
        self.onDetails = onDetails
    }

    var body: some View {
        HStack(spacing: 32) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 21, weight: .medium))
                    .frame(width: 46, height: 46)
                    .modifier(ReaderChromeSurface(shape: Circle(), background: background,
                                                  foreground: foreground))
                    .contentShape(Circle())
            }
            .accessibilityLabel("返回")
            .accessibilityIdentifier("reader.back")

            VStack(spacing: 2) {
                Text(title)
                    .appFont(.system(size: titleSize, weight: .semibold))
                    .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                    .accessibilityIdentifier("reader.title")
                Text(source)
                    .appFont(.system(size: sourceSize))
                    .foregroundStyle(foreground.opacity(0.65))
                    .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                    .accessibilityIdentifier("reader.source")
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, minHeight: 40)
            .modifier(ReaderChromeSurface(shape: Capsule(), background: background,
                                          foreground: foreground))
            .accessibilityElement(children: .contain)
            .allowsHitTesting(false)

            Button(action: onDetails) {
                ReaderChromeCover(url: coverURL, foreground: foreground)
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                    .frame(width: 46, height: 46)
                    .modifier(ReaderChromeSurface(shape: Circle(), background: background,
                                                  foreground: foreground))
                    .contentShape(Circle())
            }
            .accessibilityLabel("书籍详情")
            .accessibilityValue(title)
            .accessibilityIdentifier("reader.details")
        }
        .foregroundStyle(foreground)
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }
}

/// Place in a safe-area-respecting `.overlay(alignment: .bottom)`.
/// Progress is normalized to 0...1. The caller owns seeking and playback.
struct ReaderBottomChrome: View {
    let chapter: String
    let positionLabel: String
    @Binding var progress: Double
    let canScrub: Bool
    let canPrevious: Bool
    let canNext: Bool
    let isSpeaking: Bool
    let background: Color
    let foreground: Color
    let onScrub: (Bool) -> Void
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onTOC: () -> Void
    let onSpeech: () -> Void
    let onSearch: () -> Void
    let onSettings: () -> Void

    @ScaledMetric(relativeTo: .footnote) private var headerSize: CGFloat = 13
    @ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 17
    @Environment(\.dynamicTypeSize) private var typeSize

    init(chapter: String, positionLabel: String, progress: Binding<Double>,
         canScrub: Bool, canPrevious: Bool, canNext: Bool, isSpeaking: Bool,
         background: Color, foreground: Color, onScrub: @escaping (Bool) -> Void,
         onPrevious: @escaping () -> Void, onNext: @escaping () -> Void,
         onTOC: @escaping () -> Void, onSpeech: @escaping () -> Void,
         onSearch: @escaping () -> Void, onSettings: @escaping () -> Void) {
        self.chapter = chapter
        self.positionLabel = positionLabel
        self._progress = progress
        self.canScrub = canScrub
        self.canPrevious = canPrevious
        self.canNext = canNext
        self.isSpeaking = isSpeaking
        self.background = background
        self.foreground = foreground
        self.onScrub = onScrub
        self.onPrevious = onPrevious
        self.onNext = onNext
        self.onTOC = onTOC
        self.onSpeech = onSpeech
        self.onSearch = onSearch
        self.onSettings = onSettings
    }

    private var safeProgress: Double {
        progress.isFinite ? min(max(progress, 0), 1) : 0
    }

    private var sliderProgress: Binding<Double> {
        Binding(get: { safeProgress }, set: { value in
            guard canScrub, value.isFinite else { return }
            progress = min(max(value, 0), 1)
        })
    }

    var body: some View {
        VStack(spacing: 4) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    chapterText
                    Spacer(minLength: 0)
                    positionText.fixedSize(horizontal: true, vertical: false)
                }
                VStack(alignment: .leading, spacing: 4) {
                    chapterText
                    positionText
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 10)

            HStack(spacing: 0) {
                pageButton("chevron.left", label: "上一章", id: "reader.previous",
                           enabled: canPrevious, action: onPrevious)
                Slider(value: sliderProgress, in: 0...1, onEditingChanged: onScrub)
                    .tint(foreground)
                    .frame(minWidth: 44, minHeight: 44)
                    .disabled(!canScrub)
                    .accessibilityLabel("阅读进度")
                    .accessibilityValue(Text(safeProgress, format: .percent.precision(.fractionLength(0))))
                    .accessibilityIdentifier("reader.progress")
                pageButton("chevron.right", label: "下一章", id: "reader.next",
                           enabled: canNext, action: onNext)
            }

            HStack(spacing: 0) {
                toolButton("目录", id: "reader.toc", symbol: "list.bullet", action: onTOC)
                toolButton(isSpeaking ? "停止朗读" : "开始朗读", id: "reader.speech",
                           symbol: "speaker.wave.2", action: onSpeech)
                    .accessibilityValue(isSpeaking ? "正在朗读" : "未朗读")
                    .background {
                        if isSpeaking {
                            Circle().fill(foreground.opacity(0.10))
                                .frame(width: 40, height: 40)
                                .allowsHitTesting(false)
                        }
                    }
                toolButton("搜索正文", id: "reader.search", symbol: "magnifyingglass", action: onSearch)
                toolButton("阅读设置，字体大小", id: "reader.settings", symbol: nil, action: onSettings)
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .frame(minHeight: 140)
        .foregroundStyle(foreground)
        .buttonStyle(.plain)
        .modifier(ReaderChromeSurface(shape: RoundedRectangle(cornerRadius: 26, style: .continuous),
                                      background: background, foreground: foreground))
        .padding(.horizontal, 12)
    }

    private var chapterText: some View {
        Text(chapter)
            .appFont(.system(size: headerSize, weight: .semibold))
            .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
            .accessibilityIdentifier("reader.chapter")
    }

    private var positionText: some View {
        Text(positionLabel)
            .appFont(.system(size: headerSize))
            .foregroundStyle(foreground.opacity(0.65))
            .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
            .accessibilityIdentifier("reader.position")
    }

    private func pageButton(_ symbol: String, label: String, id: String,
                            enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: min(iconSize, 30), weight: .medium))
                .foregroundStyle(foreground.opacity(enabled ? 0.7 : 0.25))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .disabled(!enabled)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    private func toolButton(_ label: String, id: String, symbol: String?,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if let symbol {
                    Image(systemName: symbol)
                } else {
                    Text("大小")
                }
            }
            .font(.system(size: min(iconSize, 30), weight: .regular))
            .frame(minWidth: 44, maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }
}

private struct ReaderChromeSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    let background: Color
    let foreground: Color
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    private var materialScheme: ColorScheme {
        let traits = UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light)
        let color = UIColor(background).resolvedColor(with: traits)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard color.getRed(&red, green: &green, blue: &blue, alpha: &alpha), alpha > 0 else {
            return colorScheme
        }
        return red * 0.2126 + green * 0.7152 + blue * 0.0722 < 0.5 ? .dark : .light
    }

    func body(content: Content) -> some View {
        content.background {
            ZStack {
                if reduceTransparency {
                    shape.fill(background)
                } else {
                    shape.fill(.ultraThinMaterial)
                    shape.fill(background.opacity(0.55))
                }
                shape.strokeBorder(foreground.opacity(0.14), lineWidth: 0.5)
            }
            .environment(\.colorScheme, materialScheme)
            .shadow(color: .black.opacity(0.07), radius: 10, x: 0, y: 4)
            .allowsHitTesting(false)
        }
    }
}

private struct ReaderChromeCover: View {
    let url: URL?
    let foreground: Color
    @State private var localImage: UIImage?
    @State private var loadedURL: URL?

    var body: some View {
        Group {
            if let url, url.isFileURL {
                if loadedURL == url, let localImage {
                    Image(uiImage: localImage).resizable().scaledToFill()
                } else {
                    placeholder
                }
            } else if let url, ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .accessibilityHidden(true)
        .task(id: url) {
            localImage = nil
            loadedURL = nil
            guard let url, url.isFileURL else { return }
            // File I/O is off the main actor; thumbnail decoding is bounded.
            let data = await Task.detached(priority: .utility) {
                try? Data(contentsOf: url)
            }.value
            guard !Task.isCancelled, let data,
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 160
                  ] as CFDictionary) else { return }
            localImage = UIImage(cgImage: thumbnail)
            loadedURL = url
        }
    }

    private var placeholder: some View {
        ZStack {
            foreground.opacity(0.06)
            Image(systemName: "book.closed")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(foreground.opacity(0.6))
        }
    }
}
