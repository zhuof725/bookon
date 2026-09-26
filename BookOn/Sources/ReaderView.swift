import SwiftUI

struct ReaderView: View {
    let book: Book
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var settings = ReadSettings.shared
    private let library = Library.shared

    @State private var chapters: [Chapter] = []
    @State private var fullText: NSString = ""
    @State private var chapterIndex = 0
    @State private var content = ""
    @State private var showMenu = false
    @State private var showToc = false
    @State private var scrollProgress: Double = 0
    @State private var restoreProgress: Double? = nil
    @State private var loading = false
    @State private var loadError: String?
    @State private var loadTask: Task<Void, Never>?
    private var source: BookSource? { book.type == .web ? SourceStore.shared.source(for: book.sourceUrl) : nil }

    var body: some View {
        ZStack {
            settings.theme.background.ignoresSafeArea()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Color.clear.frame(height: 1).id("top")
                        Text(chapters.indices.contains(chapterIndex) ? chapters[chapterIndex].title : book.title)
                            .font(.system(size: settings.fontSize + 6, weight: .bold))
                            .padding(.top, 24)
                        if loading {
                            HStack { Spacer(); ProgressView("加载中…"); Spacer() }.padding(.top, 60)
                        } else if let e = loadError {
                            VStack(spacing: 12) {
                                Text(e).font(.footnote).multilineTextAlignment(.center)
                                Button("重试") { refreshContent(force: true) }
                            }.frame(maxWidth: .infinity).padding(.top, 60)
                        } else {
                            Text(content)
                                .font(.system(size: settings.fontSize))
                                .lineSpacing(settings.lineSpacing)
                        }
                        chapterNav
                    }
                    .foregroundColor(settings.theme.foreground)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 40)
                    .background(GeometryReader { geo in
                        Color.clear.preference(key: ScrollKey.self,
                                               value: ScrollInfo(offset: -geo.frame(in: .named("scroll")).minY,
                                                                 height: geo.size.height))
                    })
                }
                .coordinateSpace(name: "scroll")
                .onPreferenceChange(ScrollKey.self) { info in
                    let visible = UIScreen.main.bounds.height
                    let scrollable = max(info.height - visible, 1)
                    scrollProgress = min(max(info.offset / scrollable, 0), 1)
                }
                .onChange(of: chapterIndex) { _ in
                    withAnimation(nil) { proxy.scrollTo("top", anchor: .top) }
                }
            }
            .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { showMenu.toggle() } }

            if showMenu { menuOverlay }
        }
        .preferredColorScheme(settings.theme.colorScheme)
        .statusBar(hidden: !showMenu)
        .onAppear(perform: load)
        .onDisappear(perform: saveProgress)
        .sheet(isPresented: $showToc) {
            TocView(chapters: chapters, current: chapterIndex) { idx in
                showToc = false
                go(to: idx)
            }
        }
    }

    // MARK: pieces

    private var chapterNav: some View {
        HStack {
            Button("上一章") { go(to: chapterIndex - 1) }.disabled(chapterIndex == 0)
            Spacer()
            Text("\(chapterIndex + 1) / \(chapters.count)").font(.footnote).opacity(0.6)
            Spacer()
            Button("下一章") { go(to: chapterIndex + 1) }.disabled(chapterIndex >= chapters.count - 1)
        }
        .padding(.top, 24)
    }

    private var menuOverlay: some View {
        VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: { Image(systemName: "chevron.left").font(.title3) }
                VStack(alignment: .leading) {
                    Text(book.title).lineLimit(1).font(.headline)
                    if book.type == .web { Text(book.sourceName).font(.caption2).foregroundColor(.secondary) }
                }
                Spacer()
                if book.type == .web {
                    Button { refreshContent(force: true) } label: { Image(systemName: "arrow.clockwise") }
                }
            }
            .padding()
            .background(.regularMaterial)

            Spacer()

            VStack(spacing: 14) {
                HStack {
                    Button("上一章") { go(to: chapterIndex - 1) }.disabled(chapterIndex == 0)
                    Slider(value: Binding(get: { Double(chapterIndex) },
                                          set: { go(to: Int($0.rounded())) }),
                           in: 0...Double(max(chapters.count - 1, 1)), step: 1)
                    Button("下一章") { go(to: chapterIndex + 1) }.disabled(chapterIndex >= chapters.count - 1)
                }
                HStack(spacing: 24) {
                    Button { showToc = true } label: { Label("目录", systemImage: "list.bullet") }
                    Spacer()
                    Button { settings.bump(-1) } label: { Text("A-").font(.callout) }
                    Text("\(Int(settings.fontSize))").font(.callout).frame(width: 28)
                    Button { settings.bump(1) } label: { Text("A+").font(.callout) }
                    Spacer()
                    Picker("主题", selection: Binding(get: { settings.theme }, set: { settings.theme = $0 })) {
                        ForEach(ReadTheme.allCases) { t in Text(t.name).tag(t) }
                    }
                    .pickerStyle(.menu)
                }
            }
            .padding()
            .background(.regularMaterial)
        }
        .transition(.opacity)
    }

    // MARK: logic

    private func load() {
        chapters = library.chapters(of: book)
        fullText = library.text(of: book)
        chapterIndex = min(book.currentChapter, max(chapters.count - 1, 0))
        restoreProgress = book.currentProgress
        refreshContent()
    }

    private func refreshContent(force: Bool = false) {
        loadTask?.cancel()
        loadError = nil
        guard chapters.indices.contains(chapterIndex) else {
            content = book.type == .web ? "" : fullText as String
            if book.type == .web && chapters.isEmpty { loadError = "目录为空，请返回详情页重新加载" }
            return
        }
        let ch = chapters[chapterIndex]
        if book.type == .local {
            content = TxtParser.content(of: ch, in: fullText); return
        }
        if !force, let cached = library.cachedContent(book, ch.index) { content = cached; loading = false; preloadNext(); return }
        guard let src = source else { loadError = "书源不存在：\(book.sourceName)"; return }
        loading = true; content = ""
        let idx = chapterIndex
        let next = chapters.indices.contains(idx + 1) ? chapters[idx + 1].url : nil
        loadTask = Task {
            do {
                let wc = WebChapter(index: ch.index, title: ch.title, url: ch.url)
                let text = try await WebBook.content(src, book: book.asSearchBook, chapter: wc, nextChapterUrl: next)
                guard !Task.isCancelled, idx == chapterIndex else { return }
                library.cacheContent(text, book, ch.index)
                await MainActor.run { content = text; loading = false; preloadNext() }
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run { loadError = error.localizedDescription; loading = false }
            }
        }
    }

    private func preloadNext() {
        guard book.type == .web, let src = source else { return }
        let nextIdx = chapterIndex + 1
        guard chapters.indices.contains(nextIdx), library.cachedContent(book, nextIdx) == nil else { return }
        let ch = chapters[nextIdx]
        let after = chapters.indices.contains(nextIdx + 1) ? chapters[nextIdx + 1].url : nil
        Task.detached(priority: .background) {
            let wc = WebChapter(index: ch.index, title: ch.title, url: ch.url)
            if let t = try? await WebBook.content(src, book: book.asSearchBook, chapter: wc, nextChapterUrl: after) {
                library.cacheContent(t, book, ch.index)
            }
        }
    }

    private func go(to idx: Int) {
        guard chapters.indices.contains(idx), idx != chapterIndex else { return }
        chapterIndex = idx
        scrollProgress = 0
        refreshContent()
        saveProgress()
    }

    private func saveProgress() {
        library.updateProgress(book, chapter: chapterIndex, progress: scrollProgress)
    }
}

private struct ScrollInfo: Equatable { var offset: CGFloat; var height: CGFloat }
private struct ScrollKey: PreferenceKey {
    static var defaultValue = ScrollInfo(offset: 0, height: 1)
    static func reduce(value: inout ScrollInfo, nextValue: () -> ScrollInfo) { value = nextValue() }
}

struct TocView: View {
    let chapters: [Chapter]
    let current: Int
    let onSelect: (Int) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollViewReader { proxy in
                List(chapters) { ch in
                    Button { onSelect(ch.index) } label: {
                        HStack {
                            Text(ch.title).lineLimit(1)
                                .font(ch.isVolume ? .headline : .body)
                                .foregroundColor(ch.index == current ? .accentColor : (ch.isVolume ? .secondary : .primary))
                            Spacer()
                            if ch.index == current { Image(systemName: "book.fill").foregroundColor(.accentColor) }
                        }
                    }
                    .id(ch.index)
                }
                .listStyle(.plain)
                .onAppear { if current >= 0 { proxy.scrollTo(current, anchor: .center) } }
            }
            .navigationTitle("目录（\(chapters.count) 章）")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
        }
    }
}
