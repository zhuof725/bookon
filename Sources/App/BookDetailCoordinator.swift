import SwiftUI

/// Coordinates the actual book, source and TOC; the screen itself is reusable.
struct BookDetailView: View {
    @ThemePalette private var palette
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State var book: Book
    @State private var chapters: [BookChapter] = []
    @State private var loading = true
    @State private var message: String?
    @State private var showingReader = false
    @State private var showingTOC = false
    @State private var showingCategory = false
    @State private var showingSources = false
    @State private var showingIntroEditor = false
    @State private var showingMore = false
    @State private var confirmingRemoval = false
    /// 书源没声明类型时，从正文识别出的阅读模式（文本/漫画/音频）。
    @State private var detectedKind: BookKind?
    /// 正在抓正文探测（「类型」栏显示「识别中…」）。
    @State private var detectingKind = false

    private var onCurrentShelf: Bool {
        store.isOnShelf(book)
    }

    /// 「类型」栏：书源声明的类型 → 正文识别（+缓存）→ 识别中。
    private var sourceTypeLabel: String {
        if store.isLocal(book) { return BookKind.local.label }
        if let declared = BookKind.from(sourceType: store.source(for: book.origin)?.bookSourceType) {
            return declared.label
        }
        if detectingKind { return "识别中…" }
        return detectedKind?.label ?? "文本"
    }

    /// 书源没写类型（或写得不对）时，抓一章正文判断到底是文本、漫画还是音频。
    /// 识别结果按书缓存，之后打开不再重复抓。
    @MainActor
    private func detectKindIfNeeded() async {
        guard !store.isLocal(book) else { detectedKind = .local; return }
        guard let source = store.source(for: book.origin) else { return }
        if let declared = BookKind.from(sourceType: source.bookSourceType) {
            detectedKind = declared
            return
        }
        if let saved = BookKindStore.saved(bookUrl: book.bookUrl) {
            detectedKind = saved
            return
        }
        // 书上/地址里自带的类型标记（聚合源把 tab=漫画 编在书地址里），不用联网。
        if let inferred = BookKind.infer(source: source, book: book,
                                         sourceVariables: SourceVariable.get(source.bookSourceUrl)) {
            BookKindStore.save(inferred, bookUrl: book.bookUrl)
            detectedKind = inferred
            return
        }
        // 书源名/章节名能看出来（番茄漫画、七猫听书这类），不必抓正文。
        if let guess = BookKind.guess(source: source, chapters: chapters) {
            BookKindStore.save(guess, bookUrl: book.bookUrl)
            detectedKind = guess
            return
        }
        // 开篇常是「片花/序章/公告」这类文字章，只看第一章会误判成文本；
        // 取前三个可读章节里第一个识别为非文本的结果。
        let readable = chapters.filter { !$0.isVolume && !$0.url.isEmpty }.prefix(3)
        guard !readable.isEmpty else { return }
        detectingKind = true
        defer { detectingKind = false }
        var kind: BookKind = .text
        for chapter in readable {
            // 不走章节缓存：识别要的是「书源现在返回什么」，不是早前失败留下的文本。
            guard let raw = try? await WebBook.rawContent(source: source, chapter: chapter, book: book),
                  !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let scanned = BookKind.detect(inContent: raw)
            if scanned != .text { kind = scanned; break }
        }
        BookKindStore.save(kind, bookUrl: book.bookUrl)
        detectedKind = kind
    }

    private var current: Book {
        guard let shelf = store.books.first(where: { $0.bookUrl == book.bookUrl }) else {
            var current = book
            current.intro = BookDetailMetadata.intro(for: current)
            return current
        }
        var current = book
        current.durChapterIndex = shelf.durChapterIndex
        current.durChapterPos = shelf.durChapterPos
        current.durChapterTitle = shelf.durChapterTitle
        current.lastReadAt = shelf.lastReadAt
        current.intro = BookDetailMetadata.intro(for: current)
        return current
    }

    var body: some View {
        BookDetailScreen(book: current, onShelf: onCurrentShelf,
            category: BookDetailMetadata.category(for: book), chapters: chapters,
            loading: loading, message: message, sourceType: sourceTypeLabel,
            onBack: { dismiss() }, onMore: { showingMore = true },
            onRead: { showingReader = true }, onCategory: { showingCategory = true },
            onSource: { showingSources = true },
            onShelfAction: {
                if store.isOnShelf(book) { confirmingRemoval = true }
                else { store.addToShelf(book) }
            },
            onEditIntro: { if store.isLocal(book) { showingIntroEditor = true } }, onTOC: { showingTOC = true })
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .navigationDestination(isPresented: $showingReader) { ReaderView(book: current) }
        .sheet(isPresented: $showingCategory) {
            NavigationStack {
                List {
                    ForEach(BookDetailMetadata.categories, id: \.self) { value in
                        Button {
                            BookDetailMetadata.setCategory(value, for: book)
                            showingCategory = false
                        } label: {
                            HStack { Text(value); Spacer(); if value == BookDetailMetadata.category(for: book) { Image(systemName: "checkmark") } }
                        }.accessibilityIdentifier("detail.category." + value)
                    }
                    .independentGlassRow()
                }
                .foregroundStyle(palette.primary)
                .scrollContentBackground(.hidden)
                .background { AppThemeCanvas().ignoresSafeArea() }
                .navigationTitle("切换类型").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showingCategory = false } } }
            }
            .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showingIntroEditor) {
            BookDetailIntroEditor(initial: BookDetailMetadata.intro(for: book) ?? "") { value in
                BookDetailMetadata.setIntro(value, for: book)
                book.intro = value
                showingIntroEditor = false
            }
        }
        .sheet(isPresented: $showingTOC) {
            BookDetailChapterList(book: current, chapters: chapters, loading: loading,
                onRefresh: { Task { await refreshChapters() } })
        }
        .sheet(isPresented: $showingSources) {
            BookDetailSourcePicker(book: book) { replacement in
                // Keep the original book and its reading position. Switching here
                // changes this detail's source; it never deletes a local book.
                BookKindStore.clear(bookUrl: book.bookUrl)
                BookKindStore.clear(bookUrl: replacement.bookUrl)
                book = replacement
                showingSources = false
                chapters = []
                message = nil
                detectedKind = nil
                // .task(id: book.bookUrl) starts exactly one load for the replacement.
            }
        }
        .confirmationDialog("从书架移除「\(book.name)」？", isPresented: $confirmingRemoval, titleVisibility: .visible) {
            Button("移除书架", role: .destructive) {
                store.removeFromShelf(book)
                dismiss()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(store.isLocal(book) ? "本地书籍文件也会删除，此操作无法撤销。" : "阅读进度会从书架移除，此操作无法撤销。")
        }
        .confirmationDialog("更多操作", isPresented: $showingMore) {
            Button("刷新书籍信息") { Task { await load(force: true) } }
            Button("查看目录") { showingTOC = true }
            Button("取消", role: .cancel) {}
        }
        .task(id: book.bookUrl) { await load() }
    }

    @MainActor
    private func load(force: Bool = false) async {
        loading = true
        message = nil
        if let cached = store.isLocal(book) ? store.localToc(book) : store.cachedToc(book), !cached.isEmpty {
            chapters = cached
        } else { chapters = [] }
        if store.isLocal(book) {
            detectedKind = .local
            loading = false
            if chapters.isEmpty { message = "本地目录不可用，请重新导入文件" }
            return
        }
        guard let source = store.source(for: book.origin) else {
            loading = false; message = "找不到当前书源"; return
        }
        do {
            let latest = try await WebBook.bookInfo(source: source, book: book)
            guard !Task.isCancelled else { loading = false; return }
            if let old = store.books.first(where: { $0.bookUrl == latest.bookUrl }) {
                var updated = latest
                updated.durChapterIndex = old.durChapterIndex
                updated.durChapterPos = old.durChapterPos
                updated.durChapterTitle = old.durChapterTitle
                updated.addedAt = old.addedAt
                updated.lastReadAt = old.lastReadAt
                book = updated
                if force { store.addToShelf(updated) }
                // Avoid silently persisting unrelated metadata on view appearance.
            } else { book = latest }
        } catch {
            if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                loading = false
                return
            }
            message = "详情加载失败：\(error.localizedDescription)"
        }
        await refreshChapters(source: source, force: force)
        await detectKindIfNeeded()
    }

    @MainActor
    private func refreshChapters(source: BookSource? = nil, force: Bool = false) async {
        guard !store.isLocal(book), let source = source ?? store.source(for: book.origin) else { return }
        if !force && !chapters.isEmpty { loading = false; return }
        loading = true
        defer { loading = false }
        do {
            let result = try await WebBook.chapters(source: source, book: book)
            guard !Task.isCancelled else { return }
            chapters = result
            if !result.isEmpty { store.saveToc(book, result) }
        } catch {
            if chapters.isEmpty { message = "目录加载失败：\(error.localizedDescription)" }
        }
    }
}

private struct BookDetailIntroEditor: View {
    @ThemePalette private var palette
    @Environment(\.dismiss) private var dismiss
    @State var initial: String
    let onSave: (String) -> Void
    var body: some View {
        NavigationStack {
            TextEditor(text: $initial)
                .foregroundStyle(palette.primary)
                .padding(14).scrollContentBackground(.hidden)
                .background { AppThemeCanvas().ignoresSafeArea() }
                .accessibilityIdentifier("detail.introEditor")
                .navigationTitle("编辑简介")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("保存") { onSave(initial) } }
                }
        }
    }
}

/// Modal directory that uses only parsed/cached real chapter entries.
struct BookDetailChapterList: View {
    @ThemePalette private var palette
    let book: Book
    let chapters: [BookChapter]
    let loading: Bool
    let onRefresh: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedChapter: Int?
    @State private var showingReader = false
    var body: some View {
        NavigationStack {
            List {
                if chapters.isEmpty {
                    Group {
                        if loading { ProgressView("正在加载目录…") }
                        else { Text("暂无目录").foregroundStyle(palette.secondary) }
                    }
                    .independentGlassRow()
                }
                ForEach(chapters) { chapter in
                    Button {
                        guard !chapter.isVolume else { return }
                        selectedChapter = chapter.index
                        showingReader = true
                    } label: {
                        HStack {
                            Text(chapter.title).foregroundStyle(chapter.isVolume ? palette.secondary : palette.primary)
                            Spacer()
                            if chapter.index == book.durChapterIndex {
                                Image(systemName: "book.fill").foregroundStyle(palette.accent)
                            }
                            if chapter.isVip { Image(systemName: "lock.fill").foregroundStyle(palette.secondary) }
                        }
                    }
                    .disabled(chapter.isVolume)
                    .accessibilityIdentifier("detail.chapter.\(chapter.index)")
                }
                .independentGlassRow()
            }
            .foregroundStyle(palette.primary)
            .scrollContentBackground(.hidden)
            .background { AppThemeCanvas().ignoresSafeArea() }
            .navigationTitle("目录（\(chapters.count)）")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("刷新") { onRefresh() }.disabled(loading) }
            }
            .navigationDestination(isPresented: $showingReader) {
                if let selectedChapter { ReaderView(book: book, requestedChapter: selectedChapter) }
            }
        }
    }
}

/// Search actual enabled sources for the same book, never inject example matches.
struct BookDetailSourcePicker: View {
    @ThemePalette private var palette
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let book: Book
    let onSelect: (Book) -> Void
    @State private var results: [Book] = []
    @State private var loading = true
    @State private var message: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("按书名和作者查找相同书籍；选择书源后先预览，不会自动替换书架或删除本地文件。")
                        .appFont(.footnote).foregroundStyle(palette.secondary)
                }
                .independentGlassRow()
                if loading { ProgressView("查找可用书源…").independentGlassRow() }
                if let message { Text(message).foregroundStyle(palette.secondary).independentGlassRow() }
                ForEach(results) { found in
                    Button { onSelect(found) } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(found.originName.isEmpty ? found.origin : found.originName).foregroundStyle(palette.primary)
                            Text(found.name + (found.author.isEmpty ? "" : " · " + found.author))
                                .appFont(.subheadline).foregroundStyle(palette.secondary)
                        }
                    }
                }
                .independentGlassRow()
            }
            .scrollContentBackground(.hidden)
            .background { AppThemeCanvas().ignoresSafeArea() }
            .navigationTitle("换源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }
        .task(id: book.bookUrl) { await search() }
    }

    @MainActor private func search() async {
        loading = true
        results = []
        message = nil
        let sources = store.sources.filter { $0.isEnabled && $0.bookSourceUrl != book.origin && !($0.searchUrl ?? "").isEmpty }
        guard !sources.isEmpty else { loading = false; message = "没有其他可搜索的书源"; return }
        let reference = SearchRanking.mergeKey(book)
        let name = book.name
        let matches = await withTaskGroup(of: [Book].self) { group in
            var iterator = sources.makeIterator()
            var found: [Book] = []
            func addNext() {
                if let source = iterator.next() {
                    group.addTask { (try? await WebBook.search(source: source, key: name)) ?? [] }
                }
            }
            for _ in 0..<min(4, sources.count) { addNext() }
            for await list in group {
                if Task.isCancelled { group.cancelAll(); break }
                found.append(contentsOf: list.filter { SearchRanking.mergeKey($0) == reference })
                addNext()
            }
            return found
        }
        guard !Task.isCancelled else { return }
        results = matches.filter { candidate in candidate.bookUrl != book.bookUrl }
            .sorted { $0.originName.localizedStandardCompare($1.originName) == .orderedAscending }
        if results.isEmpty { message = "其他书源没有找到同名同作者的书" }
        loading = false
    }
}
