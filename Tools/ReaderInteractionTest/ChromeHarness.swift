import SwiftUI
import UIKit

/// Offline fixture: production chrome over production TextKit paragraphs. No book
/// source, audio synthesizer or network is required by these interaction tests.
private enum ChromeFixture {
    static let title = "巫师：从合成宝石开始"
    static let source = "起点小说 (qimo)"
    static let chapter = "第 3 章 语言课"
    static let visibleText = [
        "课程已经开始，讲台上的老师安静下来。",
        "奥勒良学院，是一个非常奇怪的学校，他的课程费用是如此之高昂，但课程毕业要求非常简单。",
        "因此，这里的大部分学生，基本不会怎么听课。",
        "交友、骑马、打球、宴会，这些才是学院里的二代们在乎的东西。",
        "按照惯例，学院院长通古斯先生，伸手收起他身边的几个学生的课本作业。",
        "等他收完以后，他转身正准备离开。",
        "小巫师👩🏽‍🔬把一颗宝石 gem 放在阳光下，微微发亮。"
    ]
    static let pages: [BookPage] = {
        var offset = 0
        return (0..<14).map { index in
            let lines = index == 6 ? visibleText : ["第\(index + 1)页，学生们安静地听着学院里的语言课。"]
            let blocks: [ContentBlock] = lines.map { .paragraph(text: $0, commentCount: 0, commentURL: nil) }
            let page = BookPage(blocks: blocks, startOffset: offset)
            offset += lines.reduce(0) { $0 + $1.count }
            return page
        }
    }()
    static let blocks = pages.flatMap(\.blocks)

    // Local generated cover exercises ReaderChromeCover's actual file-thumbnail path.
    static let coverURL: URL? = {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("reader-chrome-fixture-cover.png")
        let image = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 120)).image { renderer in
            let context = renderer.cgContext
            let colors = [UIColor(red: 0.14, green: 0.11, blue: 0.12, alpha: 1).cgColor,
                          UIColor(red: 0.73, green: 0.28, blue: 0.05, alpha: 1).cgColor,
                          UIColor(red: 0.09, green: 0.06, blue: 0.05, alpha: 1).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors,
                                         locations: [0, 0.48, 1]) {
                context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 112, y: 120), options: [])
            }
            UIColor(red: 1, green: 0.72, blue: 0.17, alpha: 0.75).setFill()
            context.fillEllipse(in: CGRect(x: 63, y: 8, width: 38, height: 31))
            ("巫师" as NSString).draw(at: CGPoint(x: 42, y: 75), withAttributes: [
                .font: UIFont.boldSystemFont(ofSize: 17), .foregroundColor: UIColor.white
            ])
        }
        guard let data = image.pngData() else { return nil }
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch { return nil }
    }()
}

private enum ChromeDestination: String, Identifiable {
    case details, toc, search, settings
    var id: String { rawValue }
}

struct ChromeHarnessView: View {
    private let dark = ProcessInfo.processInfo.arguments.contains("--chrome-dark")
    private let narrow = ProcessInfo.processInfo.arguments.contains("--chrome-narrow")
    private let scrollingSearch = ProcessInfo.processInfo.arguments.contains("--chrome-scroll-search")
    private let noScrub = ProcessInfo.processInfo.arguments.contains("--chrome-no-scrub")
    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let first = arguments.contains("--chrome-edge=first")
        let last = arguments.contains("--chrome-edge=last")
        let initialPage = first ? 1 : last ? 14 : 7
        _page = State(initialValue: initialPage)
        _progress = State(initialValue: Double(initialPage - 1) / 13)
    }

    @State private var visible = true
    @State private var destination: ChromeDestination?
    @State private var page = 7
    @State private var progress = 6.0 / 13.0
    @State private var speaking = false
    @State private var editing = false
    @State private var counts: [String: Int] = [:]
    @State private var began = 0
    @State private var ended = 0
    @State private var updatesWhileEditing = 0
    @State private var commits = 0
    @State private var committedBeforeEnd = 0

    private var colors: (bg: Color, fg: Color) {
        let theme = ReadSettings.themes[dark ? 3 : 0]
        return (theme.bg, theme.fg)
    }

    private var slider: Binding<Double> {
        Binding(get: { progress }, set: { value in
            if editing { updatesWhileEditing += 1 }
            progress = value
        })
    }

    private var report: String {
        let actions = ["back", "details", "previous", "next", "toc", "speech",
                       "search", "settings", "select"]
            .map { "\($0)=\(counts[$0, default: 0])" }
        return (actions + ["began=\(began)", "ended=\(ended)", "updatesWhileEditing=\(updatesWhileEditing)",
                           "commits=\(commits)", "committedBeforeEnd=\(committedBeforeEnd)"]).joined(separator: ";")
    }

    var body: some View {
        GeometryReader { geometry in
            let width = narrow ? min(geometry.size.width, 320) : geometry.size.width
            ZStack {
                colors.bg.ignoresSafeArea()
                readingBody
                    .frame(width: width)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .top) {
                if visible && destination == nil {
                    ReaderTopChrome(title: ChromeFixture.title, source: ChromeFixture.source,
                        coverURL: ChromeFixture.coverURL, background: colors.bg, foreground: colors.fg,
                        onBack: { record("back") },
                        onDetails: { record("details"); destination = .details })
                        .frame(width: width)
                        .transition(.opacity)
                }
            }
            .overlay(alignment: .bottom) {
                if visible && destination == nil {
                    ReaderBottomChrome(chapter: ChromeFixture.chapter, positionLabel: "\(page) / 14",
                        progress: slider, canScrub: !noScrub,
                        canPrevious: page > 1, canNext: page < 14,
                        isSpeaking: speaking, background: colors.bg, foreground: colors.fg,
                        onScrub: scrubChanged,
                        onPrevious: { record("previous"); page -= 1; syncProgress() },
                        onNext: { record("next"); page += 1; syncProgress() },
                        onTOC: { record("toc"); destination = .toc },
                        onSpeech: { record("speech"); speaking.toggle() },
                        onSearch: { record("search"); destination = .search },
                        onSettings: { record("settings"); destination = .settings })
                        .frame(width: width)
                        .transition(.opacity)
                }
            }
        }
        .sheet(item: $destination) { sheet in
            switch sheet {
            case .search:
                ReaderChapterSearch(blocks: ChromeFixture.blocks, chapter: ChromeFixture.chapter,
                    pages: scrollingSearch ? [] : ChromeFixture.pages, onSelect: { offset in
                        record("select")
                        if !scrollingSearch {
                            page = Paginator.pageIndex(containing: offset, in: ChromeFixture.pages) + 1
                            syncProgress()
                        }
                        destination = nil
                    })
            case .details, .toc, .settings:
                NavigationStack {
                    List {
                        if sheet == .details {
                            Text(ChromeFixture.title)
                            Text(ChromeFixture.source)
                        } else if sheet == .toc {
                            Text(ChromeFixture.chapter)
                        } else {
                            Text("字体大小")
                        }
                    }
                    .navigationTitle(sheet == .details ? "书籍信息" : sheet == .toc ? "目录" : "阅读设置")
                    .toolbar { ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { destination = nil }
                    } }
                }
            }
        }
        .preferredColorScheme(dark ? .dark : .light)
    }

    private var readingBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 27) {
                ForEach(Array(ChromeFixture.visibleText.enumerated()), id: \.offset) { index, text in
                    InlineCommentParagraph(text: text, count: 0, fontSize: 23,
                        lineSpacing: 10, color: UIColor(colors.fg),
                        onTextTap: { toggleChrome() }, onTap: {})
                        .accessibilityIdentifier("chrome.body.paragraph.\(index)")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 36)
        }
        .scrollIndicators(.hidden)
        .scrollDisabled(true)
        .overlay(alignment: .bottom) {
            HStack {
                Text(ChromeFixture.chapter).accessibilityIdentifier("reader-footer-title")
                Spacer()
                Text("\(page)/14")
                    .accessibilityIdentifier("reader-footer-page")
                    .accessibilityValue(report)
            }
            .font(.system(size: 11))
            .foregroundStyle(colors.fg.opacity(0.5))
            .padding(.horizontal, 20)
            .padding(.bottom, 6)
            .allowsHitTesting(false)
        }
        // Fixed central region: like the production page host's center-tap
        // gesture, and never a full-screen hit shield over the actual controls.
        .overlay {
            GeometryReader { proxy in
                Color.clear.contentShape(Rectangle())
                    .frame(width: min(96, proxy.size.width * 0.28),
                           height: min(80, proxy.size.height * 0.16))
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                    .onTapGesture { toggleChrome() }
            }
        }
        .background(colors.bg)
    }

    private func toggleChrome() {
        withAnimation(.easeInOut(duration: 0.18)) { visible.toggle() }
    }

    private func record(_ action: String) { counts[action, default: 0] += 1 }
    private func syncProgress() { progress = Double(page - 1) / 13 }

    private func scrubChanged(_ nowEditing: Bool) {
        editing = nowEditing
        if nowEditing {
            began += 1
        } else {
            ended += 1
            if ended < began { committedBeforeEnd += 1 }
            guard !noScrub else { return }
            page = min(max(Int((progress * 13).rounded()) + 1, 1), 14)
            commits += 1
        }
    }
}
