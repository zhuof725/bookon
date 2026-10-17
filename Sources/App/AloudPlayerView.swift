import SwiftUI

/// 全屏听书播放器：参照听书 App 的样式 — 顶部「封面/正文」分段，
/// 封面模式大封面 + 当前句 + 进度；正文模式跟随文本，当前段主题色高亮。
/// ⏮/⏭ 15 秒图标对应上一章/下一章，‖◄ ►‖ 对应上一句/下一句。
/// 返回只关闭播放器，朗读在后台继续（进阅读页底栏可再次打开）。
struct AloudPlayerView: View {
    @ObservedObject var aloud: ReaderAloudController
    let book: Book
    let chapters: [BookChapter]
    /// 刷新目录闭包（本地书籍为 nil，目录页不显示刷新）。
    var onRefreshToc: (@MainActor () async -> String?)? = nil

    @Environment(\.dismiss) private var dismiss
    @ThemePalette private var palette
    @AppStorage("reader.aloud.player.mode.v1") private var mode = 0
    @State private var showToc = false
    @State private var showQueue = false
    @State private var showSettings = false
    /// 拖动进度条时的临时值；松手才真正 seek，避免播放回调打架。
    @State private var scrub: Double?

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
            Rectangle().fill(palette.border).frame(height: 0.5)
            bottomBar
        }
        .foregroundStyle(palette.primary)
        .tint(palette.accent)
        .background { AppThemeCanvas().ignoresSafeArea() }
        .statusBarHidden(false)
        // 打开播放器未启动即自动开始；中途重新打开不打断正在读的。
        .onAppear {
            if !aloud.isRunning { aloud.openCurrent() }
            aloud.refreshEngineLabel()
        }
        .sheet(isPresented: $showToc) { tocSheet.modifier(AppThemeRoot()) }
        .sheet(isPresented: $showQueue) { queueSheet.modifier(AppThemeRoot()) }
        .sheet(isPresented: $showSettings, onDismiss: { aloud.refreshEngineLabel() }) { settingsSheet.modifier(AppThemeRoot()) }
        .overlay(alignment: .bottom) { noticeToast }
    }

    // MARK: 顶栏

    private var topBar: some View {
        ZStack {
            modeSwitch
            HStack {
                Button { dismiss() } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                        Text("返回").appFont(.body)
                    }
                    .foregroundStyle(palette.accent)
                    .padding(.vertical, 8).padding(.trailing, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("reader.aloud.player.back")
                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
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
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { mode = index }
        } label: {
            Text(title)
                .appFont(.subheadline.weight(mode == index ? .semibold : .regular))
                .foregroundStyle(mode == index ? palette.onAccent : palette.secondary)
                .frame(width: 86, height: 32)
                .background(Capsule().fill(mode == index ? palette.accent : Color.clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
        .accessibilityValue(mode == index ? "已选中" : "未选中")
    }

    // MARK: 封面模式

    private var coverBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text(book.name)
                    .appFont(.title3.bold())
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if !book.author.isEmpty {
                    Text(book.author).appFont(.subheadline).foregroundStyle(palette.secondary)
                }
                Text(aloud.chapterTitle.isEmpty ? " " : aloud.chapterTitle)
                    .appFont(.subheadline).foregroundStyle(palette.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 10)

            Spacer(minLength: 8)
            HStack {
                Spacer()
                BookCoverImage(url: BookCoverLocation.url(for: book), pixelSize: 900)
                    .frame(width: 240, height: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: .black.opacity(0.2), radius: 18, x: 0, y: 10)
                    .accessibilityIdentifier("reader.aloud.cover")
                Spacer()
            }
            Spacer(minLength: 8)

            Text(aloud.unitText.isEmpty ? " " : aloud.unitText)
                .appFont(.title3)
                .lineSpacing(6)
                .lineLimit(2)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                .padding(.horizontal, 24)
                .accessibilityIdentifier("reader.aloud.unit")

            chapterCountLabel
                .padding(.horizontal, 24)
                .padding(.top, 6)
            progressBlock
                .padding(.horizontal, 24)
                .padding(.top, 6)
            controlsRow(unitButtons: false)
                .padding(.top, 10)
            Spacer(minLength: 6)
        }
    }

    // MARK: 正文模式

    private var textBody: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                BookCoverImage(url: BookCoverLocation.url(for: book), pixelSize: 200)
                    .frame(width: 54, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(book.name).appFont(.headline).lineLimit(2)
                    if !book.author.isEmpty {
                        Text(book.author).appFont(.caption).foregroundStyle(palette.secondary)
                    }
                    Text(aloud.chapterTitle.isEmpty ? " " : aloud.chapterTitle)
                        .appFont(.caption).foregroundStyle(palette.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
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
                                Text(aloud.unitList[i].text)
                                    .appFont(.title3)
                                    .lineSpacing(8)
                                    .foregroundStyle(i == aloud.unitIndex
                                        ? palette.accent : palette.primary.opacity(0.88))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(i)
                                    .accessibilityIdentifier("reader.aloud.para.\(i)")
                            }
                            Color.clear.frame(height: 2).id(-1)
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 10)
                }
                .onChange(of: aloud.unitIndex) { i in scrollToCurrent(proxy, i) }
                .onChange(of: aloud.chapterIndex) { _ in scrollToCurrent(proxy, aloud.unitIndex) }
            }

            chapterCountLabel
                .padding(.horizontal, 24)
            playerCard
        }
    }

    private func scrollToCurrent(_ proxy: ScrollViewProxy, _ index: Int) {
        guard index >= 0, index < aloud.unitList.count else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            proxy.scrollTo(index, anchor: .center)
        }
    }

    private var playerCard: some View {
        VStack(spacing: 10) {
            Capsule().fill(palette.secondary.opacity(0.3))
                .frame(width: 40, height: 4)
                .padding(.top, 8)
            progressBlock
            controlsRow(unitButtons: true)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
        .padding(.top, 4)
        .background {
            ThemeSurface(shape: UnevenRoundedRectangle(cornerRadii: .init(topLeading: 24, topTrailing: 24),
                                                       style: .continuous), isCard: true)
                .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: -4)
        }
    }

    // MARK: 进度

    private var chapterCountLabel: some View {
        Text(aloud.chapterIndex >= 0
            ? "\(aloud.chapterIndex + 1)/\(chapters.count)章"
            : "-/\(chapters.count)章")
            .appFont(.caption).foregroundStyle(palette.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("reader.aloud.chapterProgress")
    }

    private var progressBlock: some View {
        VStack(spacing: 0) {
            Slider(value: Binding(
                    get: { scrub ?? Double(aloud.unitIndex) },
                    set: { scrub = $0 }),
                in: 0...Double(max(aloud.unitTotal - 1, 1)), step: 1) { editing in
                if !editing, let value = scrub {
                    scrub = nil
                    aloud.seekUnit(Int(value.rounded()))
                }
            }
            .tint(palette.accent)
            .disabled(aloud.unitTotal <= 1)
            .accessibilityIdentifier("reader.aloud.slider")
            .accessibilityLabel("朗读进度")
            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                HStack {
                    Text(currentTimeLabel)
                        .accessibilityIdentifier("reader.aloud.timeCurrent")
                    Spacer()
                    Text(remainingTimeLabel)
                        .accessibilityIdentifier("reader.aloud.timeRemaining")
                }
                .appFont(.caption)
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

    /// unitButtons=true：⏮15(上一章) ⏮(上一句) 播放 ⏭(下一句) ⏭15(下一章)；
    /// false（封面模式）：队列 ⏮15 播放 ⏭15 倍速。
    private func controlsRow(unitButtons: Bool) -> some View {
        HStack(spacing: 0) {
            if unitButtons {
                chapterButton(direction: -1)
                unitButton(direction: -1)
                playButton
                unitButton(direction: 1)
                chapterButton(direction: 1)
            } else {
                queueButton
                chapterButton(direction: -1)
                playButton
                chapterButton(direction: 1)
                speedLabel
            }
        }
    }

    private func controlFrame<V: View>(_ content: V) -> some View {
        content.frame(maxWidth: .infinity, minHeight: 72).contentShape(Rectangle())
    }

    private var queueButton: some View {
        Button { showQueue = true } label: {
            controlFrame(Image(systemName: "list.bullet")
                .font(.system(size: 22)).foregroundStyle(palette.primary))
        }
        .buttonStyle(.plain)
        .disabled(aloud.unitList.isEmpty)
        .accessibilityLabel("朗读队列")
        .accessibilityIdentifier("reader.aloud.queue")
    }

    private func chapterButton(direction: Int) -> some View {
        let previous = direction < 0
        return Button { aloud.manualChapter(direction: direction) } label: {
            controlFrame(Image(systemName: previous ? "gobackward.15" : "goforward.15")
                .font(.system(size: 26))
                .foregroundStyle(palette.primary))
        }
        .buttonStyle(.plain)
        .disabled(!aloud.isRunning)
        .accessibilityLabel(previous ? "上一章" : "下一章")
        .accessibilityIdentifier(previous ? "reader.aloud.prevChapter" : "reader.aloud.nextChapter")
    }

    private func unitButton(direction: Int) -> some View {
        let previous = direction < 0
        return Button { previous ? aloud.previousUnit() : aloud.nextUnit() } label: {
            controlFrame(Image(systemName: previous ? "backward.end.fill" : "forward.end.fill")
                .font(.system(size: 26)).foregroundStyle(palette.primary))
        }
        .buttonStyle(.plain)
        .disabled(!aloud.isRunning)
        .accessibilityLabel(previous ? "上一句" : "下一句")
        .accessibilityIdentifier(previous ? "reader.aloud.prev" : "reader.aloud.next")
    }

    private var playButton: some View {
        Button { aloud.togglePlay() } label: {
            ZStack {
                Circle().fill(palette.accent).frame(width: 74, height: 74)
                if aloud.isBuffering {
                    ProgressView().tint(palette.onAccent)
                } else {
                    Image(systemName: aloud.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(palette.onAccent)
                        .offset(x: aloud.isPlaying ? 0 : 3)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 72)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(aloud.isPlaying ? "暂停" : "播放")
        .accessibilityIdentifier("reader.aloud.play")
    }

    private var speedLabel: some View {
        Menu { speedMenuItems } label: {
            controlFrame(Text(speedTitle)
                .appFont(.headline)
                .foregroundStyle(palette.primary))
        }
        .accessibilityLabel("语速")
        .accessibilityIdentifier("reader.aloud.speedLabel")
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
            bottomItem(title: "设置", symbol: "gearshape",
                       id: "reader.aloud.settings") { showSettings = true }
        }
        .padding(.top, 6)
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
        VStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 22))
            Text(title).appFont(.caption)
        }
        .foregroundStyle(palette.primary)
        .frame(maxWidth: .infinity, minHeight: 52)
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
        ReaderTocSheet(chapters: chapters,
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

    private var settingsSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    NavigationLink {
                        SpeakEngineList(aloud: aloud)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "waveform.badge.mic").frame(width: 24)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("朗读引擎").appFont(.subheadline)
                                Text(aloud.engineName).appFont(.caption).foregroundStyle(palette.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").appFont(.caption).foregroundStyle(palette.secondary)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .modifier(SettingsGlassSurface())
                    .accessibilityIdentifier("reader.aloud.engines")

                    AloudPreloadCard()

                    Button {
                        aloud.stop()
                        showSettings = false
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "stop.circle").frame(width: 24)
                            Text("停止朗读").appFont(.subheadline)
                            Spacer()
                        }
                        .foregroundStyle(.red)
                        .padding(.horizontal, 16).padding(.vertical, 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .modifier(SettingsGlassSurface())
                    .accessibilityIdentifier("reader.aloud.stop")

                    Text("「返回」只收起播放器，朗读会在后台继续；想结束请在这里停止。")
                        .appFont(.footnote).foregroundStyle(palette.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }
                .padding(16)
            }
            .background { AppThemeCanvas().ignoresSafeArea() }
            .navigationTitle("朗读设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { showSettings = false }
                        .accessibilityIdentifier("reader.aloud.settings.close")
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
