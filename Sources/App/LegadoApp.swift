import SwiftUI
import UniformTypeIdentifiers

@main
struct LegadoApp: App {
    @StateObject private var store = AppStore.shared
    @StateObject private var settings = ReadSettings()
    @AppStorage(AppAppearance.storageKey) private var appearanceRawValue = AppAppearance.system.rawValue
    @State private var importMessage: String?
    @Environment(\.scenePhase) private var scenePhase

    private var appColorScheme: ColorScheme? {
        (AppAppearance(rawValue: appearanceRawValue) ?? .system).colorScheme
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(appColorScheme)
                .modifier(AppTypographyRoot())
                .modifier(ThemeLaunchHost())
                .modifier(MonochromeAppStyle())
                .modifier(AppThemeRoot())
                .onAppear { VerifyPresenter.install() }
                .environmentObject(store)
                .environmentObject(settings)
                .onOpenURL { handle($0) }
                .onChange(of: scenePhase) { phase in
                    // 书源变量（段评开关等）在进后台时立即落盘，避免被系统回收前丢设置。
                    if phase != .active { JavaBridge.store.flush() }
                }
                .alert(importMessage ?? "", isPresented: Binding(get: { importMessage != nil }, set: { if !$0 { importMessage = nil } })) {
                    Button("好", role: .cancel) {}
                }
        }
    }

    /// legado://import/bookSource?src=URL、yuedu://booksource/importonline?src=URL，或分享来的 .json 文件
    private func handle(_ url: URL) {
        if url.isFileURL {
            let ok = url.startAccessingSecurityScopedResource()
            defer { if ok { url.stopAccessingSecurityScopedResource() } }
            if let t = try? String(contentsOf: url, encoding: .utf8) {
                let n = (try? store.importSources(json: t)) ?? 0
                importMessage = "导入了 \(n) 个书源"
            }
            return
        }
        guard let src = SourceImportLink.sourceURL(url) else { return }
        Task {
            do { let n = try await store.importSources(from: src); importMessage = "导入了 \(n) 个书源" }
            catch { importMessage = "导入失败：\(error.localizedDescription)" }
        }
    }
}

struct RootView: View {
    @State private var selection: LibraryTab = .shelf
    var body: some View {
        NavigationStack {
            LibraryTabContainer(selection: $selection) {
                BookshelfView()
            } statistics: {
                LibraryStatisticsView()
            } profile: {
                LibraryProfileView()
            } search: {
                SearchView()
            }
            .background { AppThemeCanvas().ignoresSafeArea() }
        }
    }
}

// MARK: - Bookshelf

struct BookshelfView: View {
    @EnvironmentObject var store: AppStore
    @State private var showImport = false
    @State private var importMessage: String?
    @State private var selectedBook: Book?
    @State private var showDetail = false

    var body: some View {
        BookshelfScreen(books: store.books, localOrigin: AppStore.localOrigin,
            onOpen: { book in selectedBook = book; showDetail = true },
            onImport: { showImport = true },
            onRemove: { books in books.forEach { store.removeFromShelf($0) } },
            loadListChapters: { book in store.isLocal(book) ? store.localToc(book) : store.cachedToc(book) },
            onRefresh: { await refreshShelf() })
        .navigationDestination(isPresented: $showDetail) {
            if let selectedBook { BookDetailView(book: selectedBook) }
        }
        .sheet(isPresented: $showImport) {
            DocumentPicker(contentTypes: BookshelfView.localTypes, allowsMultiple: true, onPick: { urls in
                showImport = false
                importLocal(urls)
            }, onCancel: { showImport = false })
        }
        .alert("导入结果", isPresented: Binding(get: { importMessage != nil }, set: { if !$0 { importMessage = nil } })) {
            Button("好") { importMessage = nil }
        } message: { Text(importMessage ?? "") }
    }

    /// TXT 与 EPUB。EPUB 没有系统内置类型时用扩展名声明的类型兜底。
    static var localTypes: [UTType] {
        var t: [UTType] = [.plainText, .text]
        if let epub = UTType(filenameExtension: "epub") { t.append(epub) }
        t.append(.data)
        return t
    }

    private func importLocal(_ urls: [URL]) {
        var ok = 0
        var failed: [String] = []
        for u in urls {
            let access = u.startAccessingSecurityScopedResource()
            defer { if access { u.stopAccessingSecurityScopedResource() } }
            do { try store.importLocalBook(url: u); ok += 1 }
            catch LocalBookError.unsupported(let ext) { failed.append("\(u.lastPathComponent)：不支持 .\(ext)（目前支持 TXT、EPUB）") }
            catch LocalBookError.empty { failed.append("\(u.lastPathComponent)：没有读到内容") }
            catch { failed.append("\(u.lastPathComponent)：文件无法读取或已损坏") }
        }
        importMessage = "成功导入 \(ok) 本" + (failed.isEmpty ? "" : "\n\n失败：\n" + failed.joined(separator: "\n"))
    }

    /// 书架下拉刷新：逐本重新取书籍信息与目录，更新书名/封面/最新章节，保留阅读进度。
    /// 本地书籍与找不到书源的书跳过；失败不影响其它书。
    @MainActor
    private func refreshShelf() async -> String? {
        let all = store.books
        let targets = ShelfRefresh.targets(all, localOrigin: AppStore.localOrigin) { store.source(for: $0.origin) != nil }
        let skipped = all.count - targets.count
        guard !targets.isEmpty else { return ShelfRefresh.summary(updated: 0, failed: 0, skipped: skipped) }
        let result = await ShelfRefresh.run(targets) { book in
            await refreshOne(book)
        } onResult: { result in
            guard let refreshed = result.book else { return }
            store.applyShelfRefresh(refreshed, chapters: result.chapters)
        }
        store.flushProgress()
        return ShelfRefresh.summary(updated: result.updated, failed: result.failed, skipped: skipped)
    }

    @MainActor
    private func refreshOne(_ book: Book) async -> ShelfRefresh.Result {
        guard let source = store.source(for: book.origin) else {
            return ShelfRefresh.Result(bookUrl: book.bookUrl, book: nil)
        }
        do {
            let latest = try await WebBook.bookInfo(source: source, book: book)
            guard !Task.isCancelled else { return ShelfRefresh.Result(bookUrl: book.bookUrl, book: nil) }
            var chapters: [BookChapter] = []
            // 目录拿不到（部分源需要登录）时仍然更新书目信息，不整本算失败。
            chapters = (try? await WebBook.chapters(source: source, book: latest)) ?? []
            return ShelfRefresh.Result(bookUrl: book.bookUrl,
                                       book: ShelfRefresh.merge(latest, into: book),
                                       chapters: chapters)
        } catch {
            return ShelfRefresh.Result(bookUrl: book.bookUrl, book: nil)
        }
    }
}

struct BookRow: View {
    @ThemePalette private var palette
    let book: Book
    var subtitle: String = ""

    var body: some View {
        HStack(spacing: 12) {
            ShelfCoverImage(url: BookCoverLocation.url(for: book))
            .frame(width: 48, height: 66)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            VStack(alignment: .leading, spacing: 4) {
                Text(book.name).appFont(.headline).foregroundStyle(palette.primary).lineLimit(1)
                Text(book.author).appFont(.subheadline).foregroundStyle(palette.secondary).lineLimit(1)
                if !subtitle.isEmpty { Text(subtitle).appFont(.caption).foregroundStyle(palette.secondary).lineLimit(1) }
            }
        }
    }
}

// MARK: - Sources

struct SourcesView: View {
    @ThemePalette private var palette
    @EnvironmentObject var store: AppStore
    @State private var showImport = false
    @State private var showFile = false
    @State private var input = ""
    @State private var importTitle = "输入书源 JSON"
    @State private var message: String?
    @State private var busy = false
    @State private var debugSource: BookSource?
    @State private var loginSource: BookSource?
    @State private var checkList: [BookSource] = []
    @State private var showCheck = false
    @State private var groupSource: BookSource?
    @State private var groupText = ""
    @State private var deleteSource: BookSource?
    @State private var exportItem: SourceExportItem?
    @State private var editTarget: SourceEditTarget?
    @State private var collapsedGroups: Set<String> = []

    var body: some View {
        List {
            Section {
                Text("共 \(store.sources.count) 个书源，启用 \(store.sources.filter { $0.isEnabled }.count) 个")
                    .appFont(.footnote).foregroundStyle(palette.secondary)
            }
            .independentGlassRow()
            ForEach(BookSource.groupedSections(store.sources), id: \.name) { section in
                Section {
                    if !collapsedGroups.contains(section.name) {
                        ForEach(section.sources) { s in sourceRow(s) }
                            .independentGlassRow()
                    }
                } header: { groupHeader(section.name, count: section.sources.count) }
            }
        }
        .scrollContentBackground(.hidden)
        .background { AppThemeCanvas().ignoresSafeArea() }
        .navigationTitle("书源")
        .sheet(item: $debugSource) { source in SourceDebugView(source: source) }
        .sheet(item: $loginSource) { source in SourceLoginView(source: source) }
        .sheet(item: $editTarget) { t in SourceEditView(original: t.source, store: store) }
        .sheet(item: $exportItem) { item in ActivityShareSheet(items: [item.url]).ignoresSafeArea() }
        .alert("移动到分组", isPresented: Binding(get: { groupSource != nil }, set: { if !$0 { groupSource = nil } })) {
            TextField("分组名（多个用逗号分隔）", text: $groupText)
            Button("取消", role: .cancel) { groupSource = nil }
            Button("确定") { if let s = groupSource { store.moveSource(s, toGroup: groupText) }; groupSource = nil }
        } message: { Text(groupSource?.bookSourceName ?? "") }
        .alert("删除书源「\(deleteSource?.bookSourceName ?? "")」？", isPresented: Binding(get: { deleteSource != nil }, set: { if !$0 { deleteSource = nil } })) {
            Button("取消", role: .cancel) { deleteSource = nil }
            Button("删除", role: .destructive) { if let s = deleteSource { store.deleteSource(s) }; deleteSource = nil }
        }
        .sheet(isPresented: $showCheck) { SourceCheckView(sources: checkList, store: store) }
        .overlay { if busy { ProgressView() } }
        .toolbar {
            Button { editTarget = SourceEditTarget(source: nil) } label: { Image(systemName: "square.and.pencil") }
                .accessibilityLabel("新建书源")
                .accessibilityIdentifier("sources.new")
            Menu {
                Section("校验书源") {
                    Button("校验全部书源") { startCheck(store.sources) }
                    Button("校验启用中的书源") { startCheck(store.sources.filter { $0.isEnabled }) }
                }
                Section("导入配置文件") {
                    Button("文本导入") { input = ""; importTitle = "输入书源 JSON"; showImport = true }
                    Button("本地文件导入") { showFile = true }
                    Button("URL 导入") { input = ""; importTitle = "输入书源链接"; showImport = true }
                    Button("剪贴板导入") { importClipboard() }
                }
            } label: { Image(systemName: "plus") }
            .accessibilityIdentifier("sources.import")
        }
        .sheet(isPresented: $showImport) {
            NavigationStack {
                TextEditor(text: $input)
                    .appFont(.system(.footnote, design: .monospaced))
                    .foregroundStyle(palette.primary)
                    .scrollContentBackground(.hidden)
                    .padding()
                    .background { AppThemeCanvas().ignoresSafeArea() }
                    .navigationTitle(importTitle)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("取消") { showImport = false } }
                        ToolbarItem(placement: .confirmationAction) { Button("导入") { showImport = false; doImport(input) } }
                    }
            }
        }
        .sheet(isPresented: $showFile) {
            DocumentPicker(onPick: { urls in
                showFile = false
                importFiles(urls)
            }, onCancel: { showFile = false })
            .ignoresSafeArea()
        }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("好", role: .cancel) {}
        }
    }

    /// 分组标题：组名 + 书源数，点按折叠/展开。
    private func groupHeader(_ name: String, count: Int) -> some View {
        let collapsed = collapsedGroups.contains(name)
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                if collapsed { collapsedGroups.remove(name) } else { collapsedGroups.insert(name) }
            }
        } label: {
            HStack(spacing: 8) {
                Text(name).appFont(.headline).foregroundStyle(palette.primary)
                Text("\(count)").appFont(.caption).foregroundStyle(palette.secondary)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.secondary)
                    .rotationEffect(.degrees(collapsed ? -90 : 0))
            }
            .textCase(nil)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(collapsed ? "已折叠" : "已展开")
        .accessibilityIdentifier("sources.group.\(name)")
    }

    @ViewBuilder
    private func sourceRow(_ s: BookSource) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(s.bookSourceName).foregroundStyle(palette.primary).lineLimit(1)
                HStack(spacing: 6) {
                    Text(s.bookSourceUrl)
                        .appFont(.caption).foregroundStyle(palette.secondary).lineLimit(1)
                    if let rt = s.respondTime, rt > 0 {
                        Text("响应 \(rt)ms")
                            .appFont(.caption2).foregroundStyle(palette.secondary.opacity(0.8))
                    }
                }
            }
            Spacer()
            Toggle("", isOn: Binding(get: { s.isEnabled }, set: { _ in store.toggleSource(s) })).labelsHidden()
        }
        .contentShape(Rectangle())
        .contextMenu {
            // 只有配置了登录（loginUi 或可用的 loginUrl）的书源才显示「登录」。
            if SourceLoginForm.hasLogin(s) {
                Button { loginSource = s } label: { Label("登录", systemImage: "person.crop.circle") }
            }
            Button { editTarget = SourceEditTarget(source: s) } label: { Label("编辑书源", systemImage: "square.and.pencil") }
            Button { debugSource = s } label: { Label("调试", systemImage: "ladybug") }
            Button { checkList = [s]; showCheck = true } label: { Label("校验此书源", systemImage: "checkmark.circle") }
            Button { groupText = s.bookSourceGroup ?? ""; groupSource = s } label: { Label("移动到分组", systemImage: "folder") }
            Button { exportSource(s) } label: { Label("导出配置文件", systemImage: "square.and.arrow.up") }
            Button { copySource(s) } label: { Label("复制配置", systemImage: "doc.on.doc") }
            Button(role: .destructive) { deleteSource = s } label: { Label("删除配置", systemImage: "trash") }
        }
    }

    /// 导出配置文件：写成临时 JSON 文件后弹系统分享面板（可存到文件、发送给其它 App）。
    private func exportSource(_ s: BookSource) {
        guard let json = store.sourceJSON(s) else { message = "导出失败"; return }
        let safe = s.bookSourceName.components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|\n")).joined()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safe.isEmpty ? "bookSource" : safe).json")
        do {
            try ("[" + json + "]").write(to: url, atomically: true, encoding: .utf8)
            exportItem = SourceExportItem(url: url)
        } catch { message = "导出失败：\(error.localizedDescription)" }
    }

    private func copySource(_ s: BookSource) {
        guard let json = store.sourceJSON(s) else { message = "复制失败"; return }
        UIPasteboard.general.string = json
        message = "已复制书源配置"
    }

    /// 批量校验入口：把选中的书源交给校验页（原版「校验书源 / 校验所选」）。
    private func startCheck(_ list: [BookSource]) {
        guard !list.isEmpty else { message = "还没有书源"; return }
        checkList = list
        showCheck = true
    }

    private func importFiles(_ urls: [URL]) {        guard !urls.isEmpty else { return }
        var total = 0
        var failed: [String] = []
        for url in urls {
            guard let t = DocumentPicker.readText(url) else { failed.append(url.lastPathComponent); continue }
            do { total += try store.importSources(json: t) }
            catch { failed.append(url.lastPathComponent) }
        }
        var msg = "成功导入 \(total) 个书源"
        if !failed.isEmpty { msg += "\n失败文件：" + failed.joined(separator: "、") }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { message = msg }
    }

    /// 剪贴板导入：剪贴板里是书源链接或 JSON 都直接导入，空剪贴板给出提示。
    private func importClipboard() {
        let text = (UIPasteboard.general.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { message = "剪贴板里没有内容"; return }
        doImport(text)
    }

    private func doImport(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                let n = t.hasPrefix("http") ? try await store.importSources(from: t) : try store.importSources(json: t)
                message = "成功导入 \(n) 个书源"
            } catch {
                message = "导入失败：\(error.localizedDescription)"
            }
        }
    }
}

struct SourceExportItem: Identifiable {
    let id = UUID()
    let url: URL
}

/// 系统分享面板（导出书源配置文件）。
struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// 书源编辑页的打开目标：source 为 nil 表示新建。
struct SourceEditTarget: Identifiable {
    let id = UUID()
    let source: BookSource?
}
