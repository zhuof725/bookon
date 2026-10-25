import SwiftUI

/// 书源音色列表：音色来自书源自己。
///
/// - 函数式（番茄源）：jsLib `_getTones()` + `setVoice(n)`。
/// - 声明式（书山聚合这类）：脚本里 `xxxTones = [{id,name}, …]`，写配置 `xxx_tts_tone`。
///
/// 既用在有声书播放器的「音色」面板，也嵌在朗读播放器的音色面板里。
struct SourceToneList: View {
    let source: BookSource
    /// 换音色后的回调（有声书播放器用来重新取本章音频）。
    var onApplied: (() -> Void)? = nil
    /// 切到朗读（TTS）：停掉书源音频，用系统语音/在线引擎读这本书。
    var onSwitchToTTS: ((HTTPTTS?) -> Void)? = nil
    /// 当前这本书可以用这个书源的音色：选中后切到书源音频播放，返回是否成功。
    var onUseForBook: ((SourceTone.Item) async -> Bool)? = nil
    /// 音色可用性探测（按当前书的章节，结果由调用方缓存）。
    struct Probe {
        var cached: (String) -> Bool?
        /// (分组, 音色) → 是否可用
        var run: (SourceTone.Group, SourceTone.Item) async -> Bool
        var reset: () -> Void = {}
        /// 打开列表就自动检测（书山这类聚合源只能手动重测）。
        var auto: Bool = true
    }
    var probe: Probe? = nil
    /// 当前这本书（「搜真人版」用书名搜索；没有时不显示这个入口）。
    var currentBook: Book? = nil
    /// 当前章节地址：番茄 v2 用它探测「这本书有没有该音色」。
    var chapterURL: String? = nil

    @ThemePalette private var palette
    @ObservedObject private var engineModel = SpeakEngineModel.shared
    @State private var groups: [SourceTone.Group] = []
    @State private var summary = ""
    @State private var loading = true
    @State private var applying = false
    @State private var message: String?
    @State private var showSourceSettings = false
    @State private var availability: [String: Bool] = [:]
    @State private var checking: Set<String> = []
    @State private var probeTask: Task<Void, Never>?
    @State private var sheet: ToneSheetKind?
    @State private var searchResults: [Book] = []
    @State private var searching = false
    @State private var diagnostics: String?

    private enum ToneSheetKind: Identifiable {
        case search
        case book(Book)
        var id: String {
            switch self {
            case .search: return "search"
            case .book(let book): return book.bookUrl
            }
        }
    }

    var body: some View {
        List {
            Section {
                Text(summary.isEmpty ? "默认音色" : summary)
                    .appFont(.body)
                    .lineLimit(2)
                    .accessibilityIdentifier("tone.current")
            } header: {
                Text("当前音色")
            }

            if let currentBook, chapterURL != nil {
                Section {
                    Button {
                        Task { await runDiagnostics(currentBook) }
                    } label: {
                        Label("检测本章音频", systemImage: "waveform.path.ecg")
                            .appFont(.body)
                    }
                    if let diagnostics {
                        Text(diagnostics)
                            .appFont(.caption)
                            .foregroundStyle(palette.secondary)
                            .textSelection(.enabled)
                    }
                } header: {
                    Text("诊断")
                } footer: {
                    Text("显示源变量里的 tone/abook，以及这本书本章最终拿到的音频地址。")
                        .appFont(.caption)
                }
            }

            if loading {
                Section {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("正在读取书源音色…").appFont(.footnote).foregroundStyle(palette.secondary)
                    }
                }
            } else if groups.isEmpty {
                Section {
                    Text("这个书源没有提供音色列表。\n可以打开「书源设置」切换朗读音色，切完重新进入本章。")
                        .appFont(.footnote).foregroundStyle(palette.secondary)
                }
            } else {
                ForEach(groups) { group in
                    Section {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8),
                                            GridItem(.flexible(), spacing: 8),
                                            GridItem(.flexible(), spacing: 8)], spacing: 8) {
                            ForEach(group.tones) { tone in
                                toneChip(tone, group: group)
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
                        .listRowBackground(Color.clear)
                    } header: {
                        Text(sectionTitle(group))
                    }
                }
            }

            if !groups.isEmpty {
                Section {
                    if let probeSummary {
                        Text(probeSummary)
                            .appFont(.footnote).foregroundStyle(palette.secondary)
                            .accessibilityIdentifier("tone.probeSummary")
                    }
                    Text(onUseForBook == nil
                         ? "音色由书源提供；有声书切换后会重新加载本章音频。"
                         : "选中后会用这个音色直接播这本书（书源按音色合成音频，不改书源的全局模式）。")
                        .appFont(.footnote).foregroundStyle(palette.secondary)
                }
            }

            if let onSwitchToTTS {
                Section {
                    Button {
                        onSwitchToTTS(nil)
                    } label: {
                        HStack {
                            Label("系统语音朗读", systemImage: "waveform")
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("tone.tts.system")
                    ForEach(engineModel.list) { engine in
                        Button {
                            onSwitchToTTS(engine)
                        } label: {
                            HStack {
                                Text(engine.displayName).appFont(.body)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("tone.tts.\(engine.id)")
                    }
                } header: {
                    Text("用朗读引擎读这本书")
                } footer: {
                    Text("选中后会停掉书源音频，改用系统语音/在线引擎朗读；音色面板里的系统音色/引擎设置同样生效。")
                }
            }

            if currentBook != nil {
                Section {
                    Button {
                        searchRealPerson()
                    } label: {
                        HStack(spacing: 12) {
                            Label("搜真人版", systemImage: "person.wave.2")
                            Spacer()
                            if searching { ProgressView() }
                            Image(systemName: "chevron.right")
                                .font(.caption).foregroundStyle(palette.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(searching)
                    .accessibilityIdentifier("tone.searchHost")
                } footer: {
                    Text("按书名搜这个书源，找作者里带「主播」的真人录播版本；点结果打开那本书。")
                }
            }

            Section {
                Button { showSourceSettings = true } label: {
                    HStack(spacing: 12) {
                        Label("打开书源设置", systemImage: "slider.horizontal.3")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption).foregroundStyle(palette.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("tone.sourceSettings")
            }

            if let message {
                Section {
                    Text(message).appFont(.footnote).foregroundStyle(.red)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background { AppThemeCanvas().ignoresSafeArea() }
        .task {
            await load()
            startProbing()
        }
        .sheet(item: $sheet) { kind in
            switch kind {
            case .search:
                NavigationStack {
                    List(searchResults) { book in
                        Button {
                            sheet = .book(book)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(book.name).appFont(.body).lineLimit(2)
                                Text(book.author).appFont(.caption).foregroundStyle(palette.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .scrollContentBackground(.hidden)
                    .background { AppThemeCanvas().ignoresSafeArea() }
                    .navigationTitle("真人版")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("关闭") { sheet = nil }
                        }
                    }
                }
            case .book(let book):
                BookDetailView(book: book)
                    .environmentObject(AppStore.shared)
                    .modifier(AppThemeRoot())
            }
        }
        .toolbar {
            if probe != nil {
                ToolbarItem(placement: .topBarLeading) {
                    Button("重新检测") {
                        probe?.reset()
                        availability.removeAll()
                        checking.removeAll()
                        startProbing(force: true)
                    }
                    .accessibilityIdentifier("tone.retest")
                }
            }
        }
        .onDisappear { probeTask?.cancel() }
        .sheet(isPresented: $showSourceSettings) {
            SourceLoginView(source: source)
        }
    }

    private enum ToneState { case unknown, checking, available, unavailable }

    private func toneState(_ tone: SourceTone.Item) -> ToneState {
        if let value = availability[tone.value] { return value ? .available : .unavailable }
        if checking.contains(tone.value) { return .checking }
        return .unknown
    }

    /// 音色网格：一排三个圆角标签，可用带绿点，不可用置灰且点不了。
    private func toneChip(_ tone: SourceTone.Item, group: SourceTone.Group) -> some View {
        let selected = !tone.value.isEmpty && tone.value == group.currentValue
        let state = toneState(tone)
        return Button {
            apply(tone, group: group)
        } label: {
            HStack(spacing: 4) {
                if state == .available {
                    Circle().fill(Color.green.opacity(0.7)).frame(width: 5, height: 5)
                }
                Text(tone.name)
                    .appFont(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(palette.accent)
                }
            }
            .foregroundStyle(selected ? palette.accent : palette.primary)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, minHeight: 34)
            .background {
                Capsule().fill(selected ? palette.accent.opacity(0.16) : palette.primary.opacity(0.06))
            }
            .overlay {
                if selected {
                    Capsule().strokeBorder(palette.accent.opacity(0.65), lineWidth: 1)
                }
            }
            .opacity(state == .unavailable ? 0.4 : 1)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(applying || state == .unavailable)
        .accessibilityIdentifier("tone.option.\(group.id).\(tone.index)")
    }

    // MARK: 可用性探测

    private func startProbing(force: Bool = false) {
        guard let probe else { return }
        if !force, !probe.auto { return }
        var queue: [(SourceTone.Group, SourceTone.Item)] = []
        for group in groups {
            for tone in group.tones where !tone.value.isEmpty {
                if !force, let cached = probe.cached(tone.value) {
                    availability[tone.value] = cached
                } else if availability[tone.value] == nil || force {
                    queue.append((group, tone))
                }
            }
        }
        guard !queue.isEmpty else { return }
        probeTask?.cancel()
        // 逐个检测很吃 CPU/网络：并发压到 2，结果每 5 个合并一次再刷 UI，
        // 否则 79 行列表每测完一个就整体重绘，明显掉帧。
        probeTask = Task { @MainActor in
            await withTaskGroup(of: (String, Bool).self) { taskGroup in
                var iterator = queue.makeIterator()
                var active = 0
                var pending: [String: Bool] = [:]
                func launchNext() -> Bool {
                    guard let entry = iterator.next() else { return false }
                    let boxedProbe = SendableBox(probe)
                    taskGroup.addTask {
                        let ok = await Task.detached { await boxedProbe.value.run(entry.0, entry.1) }.value
                        return (entry.1.value, ok)
                    }
                    return true
                }
                while active < 2, launchNext() { active += 1 }
                while let result = await taskGroup.next() {
                    pending[result.0] = result.1
                    if pending.count >= 5 {
                        availability.merge(pending) { _, new in new }
                        pending.removeAll()
                    }
                    if !launchNext() { active -= 1 }
                }
                if !pending.isEmpty {
                    availability.merge(pending) { _, new in new }
                }
            }
        }
    }

    private func sectionTitle(_ group: SourceTone.Group) -> String {
        let name = source.bookSourceName
        return name.contains(group.title) ? group.title : "\(name)：\(group.title)"
    }

    private func searchRealPerson() {
        guard let book = currentBook else { return }
        searching = true
        Task {
            let results = (try? await WebBook.search(source: source, key: book.name)) ?? []
            let hosts = results.filter { $0.author.contains("主播") }
            searchResults = hosts.isEmpty ? results : hosts
            searching = false
            sheet = .search
        }
    }

    private var probeSummary: String? {
        guard probe != nil, !groups.isEmpty else { return nil }
        let values = groups.flatMap(\.tones).filter { !$0.value.isEmpty }
        guard !values.isEmpty else { return nil }
        let ok = values.filter { availability[$0.value] == true }.count
        let bad = values.filter { availability[$0.value] == false }.count
        let pending = values.filter { availability[$0.value] == nil }.count
        if ok == 0, bad == 0 { return "正在逐个检测音色可用性…" }
        return "可用 \(ok) · 不可用 \(bad)" + (pending > 0 ? " · 检测中 \(pending)" : "")
    }

    private func load() async {
        let src = source
        let book = currentBook
        let result = await Task.detached { () -> ([SourceTone.Group], String) in
            (SourceTone.groups(source: src, book: book), SourceTone.summary(source: src))
        }.value
        groups = result.0
        summary = result.1
        loading = false
    }

    /// 面板诊断：读源变量里的 tone/abook，再按当前章节跑一次正文规则取音频地址。
    /// 用来区分「音色没写进变量」「书源只有一版音频」「地址打不开」。
    private func runDiagnostics(_ book: Book) async {
        let selection = SourceTone.currentSelection(source: source)
        let tone = selection.tone.isEmpty ? "-" : selection.tone
        let abook = selection.abook.isEmpty ? "-" : selection.abook
        var lines = ["源变量：tone=\(tone) · abook=\(abook)"]
        if let chapterURL {
            let chapter = BookChapter(url: chapterURL, title: "", index: 0)
            let urls = (try? await AudioChapter.playURLs(source: source, book: book, chapter: chapter)) ?? []
            if let first = urls.first {
                lines.append("音频：\(first.prefix(160))")
            } else {
                lines.append("音频：没有取到地址")
            }
        }
        diagnostics = lines.joined(separator: "\n")
    }

    private func apply(_ tone: SourceTone.Item, group: SourceTone.Group) {
        let src = source
        applying = true
        message = nil
        Task {
            // 先按当前章节探一次：没有音频说明书源会回落默认音色，直接告诉用户，别假装切换成功。
            if case .legacy = group.kind,
               let chapterURL, let book = currentBook,
               let result = await SourceTone.probeTone(source: src, book: book,
                                                       chapterURL: chapterURL, tone: tone.value) {
                switch result {
                case .unavailable:
                    applying = false
                    message = "这本书没有「\(tone.name)」这个音色，书源会回落到默认音色。换一个音色或试试「真人录播」。"
                    return
                case .sameAsDefault:
                    applying = false
                    message = "书源对这本书的不同音色返回了同一个音频（只有一版录音），换音色不会变声。可以试试「真人录播」专辑。"
                    return
                case .playable:
                    break
                }
            }
            let ok = await Task.detached { SourceTone.apply(tone, in: group, source: src) }.value
            guard ok else {
                applying = false
                message = "切换失败：书源脚本没有接受这个音色"
                return
            }
            groups = groups.map { item in
                guard item.id == group.id else { return item }
                return SourceTone.Group(id: item.id, title: item.title, kind: item.kind,
                                        tones: item.tones, currentValue: tone.value)
            }
            summary = SourceTone.summary(source: source)
            if let onUseForBook {
                let started = await onUseForBook(tone)
                applying = false
                if !started {
                    message = "这个音色暂时不能用于这本书（书源没有返回音频）"
                }
                return
            }
            applying = false
            onApplied?()
        }
    }
}

/// 有声书的「音色」面板：包一层导航栏，选完自动关闭。
struct SourceToneSheet: View {
    let source: BookSource
    /// 当前书：番茄 v2 的音色表要按书调 toneinfo，缺省时只能用静态音色表。
    var book: Book? = nil
    /// 当前章节地址：用于切换前探测音色是否可用。
    var chapterURL: String? = nil
    var onApplied: () -> Void
    var onSwitchToTTS: ((HTTPTTS?) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SourceToneList(source: source, onApplied: {
                onApplied()
                dismiss()
            }, onSwitchToTTS: { engine in
                dismiss()
                onSwitchToTTS?(engine)
            }, currentBook: book, chapterURL: chapterURL)
            .navigationTitle("音色")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .accessibilityIdentifier("tone.close")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
