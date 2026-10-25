import SwiftUI

/// 全屏听书播放器：参照听书 App 的样式 — 顶部「封面/正文」分段，
/// 封面模式大封面 + 当前句 + 进度；正文模式跟随文本，当前段主题色高亮。
/// ⏮/⏭ 对应上一章/下一章，两侧 15 秒按钮对应后退/前进 15 秒。
/// 返回只关闭播放器，朗读在后台继续（进阅读页底栏可再次打开）。
struct AloudPlayerView: View {
    @ObservedObject var aloud: ReaderAloudController
    let book: Book
    let chapters: [BookChapter]
    /// 刷新目录闭包（本地书籍为 nil，目录页不显示刷新）。
    var onRefreshToc: (@MainActor () async -> String?)? = nil
    /// 当前正在读的章节（音色面板要用它检测该书的音色可用性）。
    var currentChapter: BookChapter? = nil
    /// 音色面板里给当前书选了书源音色：交给阅读器切到书源音频播放，返回是否成功。
    var onUseSourceTone: (@MainActor (BookSource, SourceTone.Item) async -> Bool)? = nil
    /// 音色面板切到系统语音/引擎：停掉书源音频。
    var onStopSourceAudio: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @ThemePalette private var palette
    @AppStorage("reader.aloud.player.mode.v1") private var mode = 0
    @State private var showToc = false
    @State private var showQueue = false
    @State private var showVoice = false
    /// 拖动进度条时的临时值；松手才真正 seek，避免播放回调打架。
    @State private var scrub: Double?
    /// 松手后到播放器真正到位之前的显示值：进度条不会先弹回旧位置再跳过去。
    @State private var pendingSeek: Double?
    @State private var pendingSeekTask: Task<Void, Never>?

    private let timerPresets = [0, 5, 10, 15, 30, 45, 60, 90, 180]
    /// 与 0…45 语速值整数映射完全对齐的倍速档位（v = 倍速×10 − 5）。
    private let ratePresets: [(label: String, value: Int)] = [
        ("0.5x", 0), ("0.8x", 3), ("1.0x", 5), ("1.2x", 7), ("1.5x", 10),
        ("1.8x", 13), ("2.0x", 15), ("2.5x", 20), ("3.0x", 25),
    ]

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if mode == 0 {
                coverBody
            } else {
                textBody
            }
            bottomBar
        }
        .foregroundStyle(palette.primary)
        .tint(palette.accent)
        .background { playerBackground }
        .statusBarHidden(false)
        // 打开播放器未启动即自动开始；中途重新打开不打断正在读的。
        .onAppear {
            if !aloud.isRunning { aloud.openCurrent() }
            aloud.refreshEngineLabel()
        }
        .onDisappear { pendingSeekTask?.cancel() }
        // 播放器真正走到目标位置后，把「等待到位」的显示值撤掉。
        .onChange(of: aloud.chapterPlayed) { _ in
            guard let target = pendingSeek else { return }
            if abs(actualFraction - target) < 0.015 { pendingSeek = nil }
        }
        .sheet(isPresented: $showToc) { tocSheet.modifier(AppThemeRoot()) }
        .sheet(isPresented: $showQueue) { queueSheet.modifier(AppThemeRoot()) }
        .sheet(isPresented: $showVoice, onDismiss: { aloud.refreshEngineLabel() }) {
            AloudVoiceSheet(aloud: aloud, currentBook: book, currentChapter: currentChapter,
                            onUseSourceTone: onUseSourceTone,
                            onStopSourceAudio: onStopSourceAudio)
                .modifier(AppThemeRoot())
        }
        .overlay(alignment: .bottom) { noticeToast }
    }

    /// 主题画布 + 一团主题色柔光：封面背后有一点光晕，不跟随封面色走（浅色主题也成立）。
    private var playerBackground: some View {
        ZStack {
            AppThemeCanvas()
            RadialGradient(colors: [palette.accent.opacity(0.14), palette.accent.opacity(0)],
                           center: UnitPoint(x: 0.5, y: 0.44),
                           startRadius: 8, endRadius: 330)
                .opacity(mode == 0 ? 1 : 0.55)
        }
        .ignoresSafeArea()
    }

    // MARK: 顶栏

    private var topBar: some View {
        ZStack {
            modeSwitch
            HStack(spacing: 8) {
                backButton
                Spacer(minLength: 0)
                moreButton
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
    }

    private var backButton: some View {
        Button { dismiss() } label: {
            HStack(spacing: 2) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                Text("返回").appFont(.subheadline)
            }
            .foregroundStyle(palette.primary)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background { AppGlassSurface(shape: Capsule(), tint: palette.surface) }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("返回")
        .accessibilityIdentifier("reader.aloud.player.back")
    }

    private var moreButton: some View {
        Menu {
            Button { showQueue = true } label: {
                Label("朗读队列", systemImage: "list.bullet")
            }
            .accessibilityIdentifier("reader.aloud.queue")
            Divider()
            Button(role: .destructive) { aloud.stop() } label: {
                Label("停止朗读", systemImage: "stop.circle")
            }
            .accessibilityIdentifier("reader.aloud.stop")
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(palette.primary)
                .frame(width: 34, height: 34)
                .background { AppGlassSurface(shape: Circle(), tint: palette.surface) }
                .contentShape(Circle())
        }
        .accessibilityLabel("更多")
        .accessibilityIdentifier("reader.aloud.more")
    }

    private var modeSwitch: some View {
        HStack(spacing: 0) {
            modeButton(title: "封面", index: 0, id: "reader.aloud.modeCover")
            modeButton(title: "正文", index: 1, id: "reader.aloud.modeText")
        }
        .padding(3)
        .background(Capsule().fill(palette.primary.opacity(0.08)))
    }

    private func modeButton(title: String, index: Int, id: String) -> some View {
        let selected = mode == index
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { mode = index }
        } label: {
            Text(title)
                .appFont(.subheadline.weight(selected ? .semibold : .regular))
                .foregroundStyle(selected ? palette.background : palette.secondary)
                .frame(width: 78, height: 32)
                .background(Capsule().fill(selected ? palette.primary : Color.clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
        .accessibilityValue(selected ? "已选中" : "未选中")
    }

    // MARK: 封面模式

    private var coverBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            coverHeader

            Spacer(minLength: 10)
            HStack {
                Spacer(minLength: 0)
                coverArt
                Spacer(minLength: 0)
            }
            Spacer(minLength: 10)

            sentenceBlock
                .padding(.horizontal, 24)

            progressBlock
                .padding(.horizontal, 24)
                .padding(.top, 8)

            controlsRow
                .padding(.horizontal, 12)
                .padding(.top, 2)

            Spacer(minLength: 2)
        }
    }

    private var coverHeader: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(book.name)
                .appFont(.title.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            if !book.author.isEmpty {
                Text(book.author).appFont(.caption).foregroundStyle(palette.secondary)
            }
            HStack(spacing: 8) {
                Text(aloud.chapterTitle.isEmpty ? " " : aloud.chapterTitle)
                    .appFont(.subheadline)
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text(chapterCountText)
                    .appFont(.caption)
                    .foregroundStyle(palette.secondary)
                    .fixedSize()
                    .accessibilityIdentifier("reader.aloud.chapterProgress")
            }
            .padding(.top, 5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 4)
    }

    private var coverArt: some View {
        BookCoverImage(url: BookCoverLocation.url(for: book), pixelSize: 900, origin: book.origin)
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .frame(maxWidth: 230, maxHeight: 306)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.22), radius: 22, x: 0, y: 12)
            .overlay(alignment: .bottomTrailing) {
                speakingBadge.padding(10)
            }
            .accessibilityIdentifier("reader.aloud.cover")
    }

    /// 封面右下角的小胶囊：正在读 / 已暂停。
    private var speakingBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "waveform")
                .font(.system(size: 10, weight: .bold))
            Text(aloud.isPlaying ? "朗读中" : "已暂停")
                .appFont(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.black.opacity(0.52)))
        .accessibilityHidden(true)
    }

    /// 当前句：正在读的句子加粗高亮，下一句压暗放在后面（读过亮、没读淡）。
    private var sentenceBlock: some View {
        Group {
            if aloud.unitText.isEmpty {
                Text(aloud.isBuffering ? "正在加载正文…" : "准备朗读…")
                    .foregroundStyle(palette.secondary)
            } else {
                sentenceText
            }
        }
        .appFont(.title3)
        .lineSpacing(6)
        .lineLimit(2)
        .truncationMode(.tail)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .accessibilityIdentifier("reader.aloud.unit")
    }

    private var sentenceText: Text {
        let current = Text(aloud.unitText)
            .fontWeight(.semibold)
            .foregroundColor(palette.primary)
        guard let next = nextUnitText else { return current }
        return current
            + Text(" ")
            + Text(next).foregroundColor(palette.secondary.opacity(0.62))
    }

    private var nextUnitText: String? {
        let next = aloud.unitIndex + 1
        guard aloud.unitList.indices.contains(next) else { return nil }
        let text = aloud.unitList[next].text
        return text.isEmpty ? nil : text
    }

    // MARK: 正文模式

    private var textBody: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text(aloud.chapterTitle.isEmpty ? " " : aloud.chapterTitle)
                    .appFont(.title3.bold())
                    .lineLimit(1)
                Text(bookLine)
                    .appFont(.caption)
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 2)
            .padding(.bottom, 8)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        if aloud.unitList.isEmpty {
                            Text(aloud.isBuffering ? "正在加载正文…" : "正文加载后开始朗读")
                                .appFont(.body).foregroundStyle(palette.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 60)
                        } else {
                            ForEach(aloud.unitList.indices, id: \.self) { i in
                                paragraphView(i)
                            }
                            Color.clear.frame(height: 2).id(-1)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .onChange(of: aloud.unitIndex) { i in scrollToCurrent(proxy, i) }
                .onChange(of: aloud.chapterIndex) { _ in scrollToCurrent(proxy, aloud.unitIndex) }
            }

            playerCard
        }
    }

    private var bookLine: String {
        book.author.isEmpty ? book.name : "\(book.name) · \(book.author)"
    }

    /// 正文段落：正在朗读的段落带主题色高亮底 + 左侧竖条标识，
    /// 文字同时用强调色（主题强调色与正文同色时，高亮底和竖条仍然可见）。
    private func paragraphView(_ index: Int) -> some View {
        let current = index == aloud.unitIndex
        return Text(aloud.unitList[index].text)
            .appFont(.title3)
            .lineSpacing(8)
            .foregroundStyle(current ? palette.accent : palette.primary.opacity(0.88))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background {
                if current {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(palette.highlight)
                }
            }
            .overlay(alignment: .leading) {
                if current {
                    Capsule().fill(palette.accent)
                        .frame(width: 3)
                        .padding(.vertical, 10)
                }
            }
            .id(index)
            .accessibilityIdentifier("reader.aloud.para.\(index)")
    }

    private func scrollToCurrent(_ proxy: ScrollViewProxy, _ index: Int) {
        guard index >= 0, index < aloud.unitList.count else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            proxy.scrollTo(index, anchor: .center)
        }
    }

    /// 正文模式底部悬浮的播放卡片（进度条 + 控制行）。
    private var playerCard: some View {
        VStack(spacing: 4) {
            progressBlock
                .padding(.horizontal, 24)
            controlsRow
                .padding(.horizontal, 12)
        }
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    // MARK: 进度

    private var chapterCountText: String {
        guard aloud.chapterIndex >= 0, !chapters.isEmpty else { return "- / \(chapters.count) 章" }
        return "\(aloud.chapterIndex + 1) / \(chapters.count) 章"
    }

    /// 播放器真实进度（0…1）。
    private var actualFraction: Double {
        guard aloud.chapterDuration > 0 else { return 0 }
        return min(max(aloud.chapterPlayed / aloud.chapterDuration, 0), 1)
    }

    /// 进度条显示值：拖动中 → 松手后等待到位 → 真实进度。
    private var displayedFraction: Double {
        scrub ?? pendingSeek ?? actualFraction
    }

    private var displayedPlayed: TimeInterval {
        guard aloud.chapterDuration > 0 else { return aloud.chapterPlayed }
        return displayedFraction * aloud.chapterDuration
    }

    private var timeSliderValue: Binding<Double> {
        Binding(get: { displayedFraction }, set: { scrub = $0 })
    }

    /// 松手：先记住目标值把滑块按住，等播放器真的走到那里再交还给真实进度。
    private func commitSeek(_ value: Double) {
        pendingSeek = value
        pendingSeekTask?.cancel()
        pendingSeekTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            if pendingSeek == value { pendingSeek = nil }
        }
        aloud.seekChapterProgress(value)
    }

    private var progressBlock: some View {
        VStack(spacing: 0) {
            if aloud.chapterDuration > 0 {
                // 在线引擎：本章播放进度（各段音频时长累计 + 当前段进度）。
                Slider(value: timeSliderValue, in: 0...1) { editing in
                    guard !editing, let value = scrub else { return }
                    scrub = nil
                    commitSeek(value)
                }
                .tint(palette.accent)
                .accessibilityIdentifier("reader.aloud.slider")
                .accessibilityLabel("本章播放进度")
                HStack {
                    Text(AloudPlayerView.timeString(displayedPlayed))
                        .accessibilityIdentifier("reader.aloud.timeCurrent")
                    Spacer()
                    Text("-" + AloudPlayerView.timeString(max(aloud.chapterDuration - displayedPlayed, 0)))
                        .accessibilityIdentifier("reader.aloud.timeRemaining")
                }
                .appFont(.caption2)
                .monospacedDigit()
                .foregroundStyle(palette.secondary)
            } else {
                // 系统语音没有音频时长：保留按段定位的进度。
                Slider(value: Binding(
                        get: { scrub ?? Double(aloud.unitIndex) },
                        set: { scrub = $0 }),
                    in: 0...Double(max(aloud.unitTotal - 1, 1)), step: 1) { editing in
                    guard !editing, let value = scrub else { return }
                    scrub = nil
                    aloud.seekUnit(Int(value.rounded()))
                }
                .tint(palette.accent)
                .disabled(aloud.unitTotal <= 1)
                .accessibilityIdentifier("reader.aloud.slider")
                .accessibilityLabel("朗读进度")
                HStack {
                    Text(currentTimeLabel)
                        .accessibilityIdentifier("reader.aloud.timeCurrent")
                    Spacer()
                    Text(remainingTimeLabel)
                        .accessibilityIdentifier("reader.aloud.timeRemaining")
                }
                .appFont(.caption2)
                .monospacedDigit()
                .foregroundStyle(palette.secondary)
            }
        }
    }

    private var currentTimeLabel: String {
        guard let time = aloud.audioTime else { return "--:--" }
        return AloudPlayerView.timeString(time.current)
    }

    private var remainingTimeLabel: String {
        guard let time = aloud.audioTime else { return "--:--" }
        return "-" + AloudPlayerView.timeString(max(time.duration - time.current, 0))
    }

    static func timeString(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds.rounded()), 0)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: 控制行

    /// ⏮(上一章) 后退15秒 播放 前进15秒 ⏭(下一章)；和参考图一致，播放键在正中。
    private var controlsRow: some View {
        HStack(spacing: 0) {
            chapterButton(direction: -1)
            skipButton(direction: -1)
            playButton
            skipButton(direction: 1)
            chapterButton(direction: 1)
        }
    }

    private func controlFrame<V: View>(_ content: V) -> some View {
        content.frame(maxWidth: .infinity, minHeight: 74).contentShape(Rectangle())
    }

    private func chapterButton(direction: Int) -> some View {
        let previous = direction < 0
        return Button { aloud.manualChapter(direction: direction) } label: {
            controlFrame(Image(systemName: previous ? "backward.end.fill" : "forward.end.fill")
                .font(.system(size: 22))
                .foregroundStyle(palette.primary))
        }
        .buttonStyle(.plain)
        .disabled(!aloud.isRunning)
        .accessibilityLabel(previous ? "上一章" : "下一章")
        .accessibilityIdentifier(previous ? "reader.aloud.prevChapter" : "reader.aloud.nextChapter")
    }

    /// 在线引擎按真实音频时间跳 15 秒；系统语音按估算时间轴跳（至少走一段）。
    private func skipButton(direction: Int) -> some View {
        let previous = direction < 0
        return Button { aloud.skip(seconds: previous ? -15 : 15) } label: {
            controlFrame(Image(systemName: previous ? "gobackward.15" : "goforward.15")
                .font(.system(size: 27))
                .foregroundStyle(palette.primary))
        }
        .buttonStyle(.plain)
        .disabled(!aloud.isRunning)
        .accessibilityLabel(previous ? "后退 15 秒" : "前进 15 秒")
        .accessibilityIdentifier(previous ? "reader.aloud.back15" : "reader.aloud.forward15")
    }

    private var playButton: some View {
        Button { aloud.togglePlay() } label: {
            ZStack {
                Circle().fill(palette.primary).frame(width: 74, height: 74)
                if aloud.isBuffering {
                    ProgressView().tint(palette.background)
                } else {
                    Image(systemName: aloud.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(palette.background)
                        .offset(x: aloud.isPlaying ? 0 : 3)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 74)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(aloud.isPlaying ? "暂停" : "播放")
        .accessibilityIdentifier("reader.aloud.play")
    }

    // MARK: 底栏

    private var bottomBar: some View {
        HStack(spacing: 0) {
            bottomItem(title: "目录", symbol: "list.bullet.rectangle",
                       id: "reader.aloud.toc") { showToc = true }
            Menu { speedMenuItems } label: {
                bottomLabel(title: speedTitle, symbol: "speedometer")
            }
            .accessibilityLabel("语速")
            .accessibilityIdentifier("reader.aloud.speed")
            Menu { timerMenuItems } label: {
                bottomLabel(title: timerTitle, symbol: "stopwatch")
            }
            .accessibilityLabel("定时")
            .accessibilityIdentifier("reader.aloud.timer")
            bottomItem(title: "音色", symbol: "waveform",
                       id: "reader.aloud.voice") { showVoice = true }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 7)
        .background {
            AppGlassSurface(shape: Capsule(), tint: palette.surface)
        }
        .overlay {
            Capsule().strokeBorder(palette.border.opacity(0.55), lineWidth: 0.5)
                .allowsHitTesting(false)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private func bottomItem(title: String, symbol: String, id: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) { bottomLabel(title: title, symbol: symbol) }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityIdentifier(id)
    }

    private func bottomLabel(title: String, symbol: String) -> some View {
        VStack(spacing: 3) {
            Image(systemName: symbol).font(.system(size: 20))
            Text(title).appFont(.caption2)
        }
        .foregroundStyle(palette.primary)
        .frame(maxWidth: .infinity, minHeight: 46)
        .contentShape(Rectangle())
    }

    private var speedTitle: String {
        String(format: "%.1fx", AloudTTSConfig.rateDisplay(for: aloud.speed))
    }

    private var timerTitle: String {
        aloud.timerLeft > 0 ? "\(aloud.timerLeft)分钟" : "定时"
    }

    @ViewBuilder
    private var speedMenuItems: some View {
        ForEach(ratePresets.indices, id: \.self) { i in
            Button {
                aloud.speed = ratePresets[i].value
            } label: {
                if ratePresets[i].value == aloud.speed {
                    Label(ratePresets[i].label, systemImage: "checkmark")
                } else {
                    Text(ratePresets[i].label)
                }
            }
            .accessibilityIdentifier("reader.aloud.speed.\(ratePresets[i].label)")
        }
    }

    @ViewBuilder
    private var timerMenuItems: some View {
        ForEach(timerPresets, id: \.self) { minutes in
            if minutes == 0 {
                Button("关闭定时") { aloud.setTimer(minutes: 0) }
                    .accessibilityIdentifier("reader.aloud.timer.0")
            } else {
                Button("\(minutes) 分钟") { aloud.setTimer(minutes: minutes) }
                    .accessibilityIdentifier("reader.aloud.timer.\(minutes)")
            }
        }
    }

    // MARK: 弹层

    private var tocSheet: some View {
        ReaderTocSheet(chapters: chapters, bookURL: book.bookUrl,
                       currentIndex: min(max(aloud.chapterIndex, 0), max(chapters.count - 1, 0)),
                       manager: .shared,
                       onSelect: { target in
                           showToc = false
                           if aloud.isRunning {
                               aloud.seekChapter(target)
                           } else {
                               aloud.start(chapter: target)
                           }
                       },
                       onRefresh: onRefreshToc)
    }

    private var queueSheet: some View {
        NavigationStack {
            List {
                ForEach(aloud.unitList.indices, id: \.self) { i in
                    Button {
                        showQueue = false
                        aloud.seekUnit(i)
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("\(i + 1)")
                                .appFont(.caption).monospacedDigit()
                                .foregroundStyle(palette.secondary)
                                .frame(width: 34, alignment: .trailing)
                            Text(aloud.unitList[i].text)
                                .appFont(.body)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .foregroundStyle(i == aloud.unitIndex ? palette.accent : palette.primary)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("reader.aloud.queue.\(i)")
                    .independentGlassRow()
                }
            }
            .scrollContentBackground(.hidden)
            .background { AppThemeCanvas().ignoresSafeArea() }
            .navigationTitle("朗读队列")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { showQueue = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: 提示

    @ViewBuilder
    private var noticeToast: some View {
        if let notice = aloud.notice {
            Text(notice).appFont(.caption).foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(Capsule().fill(Color.black.opacity(0.78)))
                .padding(.bottom, 128)
                .transition(.opacity)
                .accessibilityIdentifier("reader.aloud.notice")
        }
    }
}
