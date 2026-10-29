import SwiftUI
import AVFoundation
import MediaPlayer

/// 朗读单元：正文段落 + 其在整章文本里的字符偏移（与搜索/书签的偏移口径一致）。
/// 多角色朗读会把一个段落再切成旁白/对话小段，`speaker` 决定用哪个声线。
struct AloudUnit: Equatable {
    var offset: Int
    var text: String
    var speaker: AloudSpeaker = .narrator
}

/// 阅读器注入给朗读控制器的宿主能力。离开阅读页时调用 detach() 清空，
/// 防止闭包回持阅读器的状态包装。
struct ReaderAloudHost {
    var currentChapter: () -> Int = { 0 }
    var chapterCount: () -> Int = { 0 }
    var chapterTitle: (Int) -> String = { _ in "" }
    var bookLabel: () -> String = { "" }
    /// 本书封面地址与书源地址：锁屏 / 灵动岛的封面从这里取（nil 表示没有封面）。
    var coverURL: () -> String? = { nil }
    var bookOrigin: () -> String? = { nil }
    /// 当前阅读位置的章节内字符偏移（朗读从这里开始）。
    var currentOffset: () -> Int = { 0 }
    /// 某章的朗读段落；章节未加载完成时返回 nil。
    var units: (Int) -> [AloudUnit]? = { _ in nil }
    /// 按方向取下一个可读章节号（跳过分卷），没有返回 nil；起点即目标。
    var readableChapter: (Int, Int) -> Int? = { _, _ in nil }
    /// 让阅读器加载并显示某章；返回是否成功（失败：网络错误/无法解析）。
    var openChapter: (Int) async -> Bool = { _ in false }
    /// 播报朗读进度：章节号 + 字符偏移。界面依此翻页/滚动并保存进度。
    var follow: (Int, Int) -> Void = { _, _ in }
}

/// 听书朗读控制器：系统语音用 AVSpeechSynthesizer，在线引擎先缓存音频再播。
/// 行为对齐原版 service/BaseReadAloudService：逐段朗读、段末自动进段、
/// 章末自动进章、上一句/下一句/上下章、定时停止、语速即时生效、音频中断暂停。
@MainActor
final class ReaderAloudController: NSObject, ObservableObject {
    enum PlaybackEngine { case system, http }

    let highlight = AloudHighlightModel()
    private var currentUtterance: AVSpeechUtterance?
    @Published private(set) var isRunning = false
    @Published private(set) var isPlaying = false
    @Published private(set) var isBuffering = false
    @Published private(set) var chapterIndex = -1
    @Published private(set) var unitIndex = 0
    @Published private(set) var unitTotal = 0
    @Published private(set) var unitText = ""
    /// 当前章全部朗读段落的快照，供全屏播放器正文模式与队列展示。
    @Published private(set) var unitList: [AloudUnit] = []
    @Published private(set) var chapterTitle = ""
    /// 本章播放进度：已播放秒数 / 估算总时长（在线引擎按各段音频时长累计、
    /// 未知段按字数估算；系统语音没有音频时长，保持 0/0）。
    @Published private(set) var chapterPlayed: TimeInterval = 0
    @Published private(set) var chapterDuration: TimeInterval = 0
    @Published private(set) var timerLeft = 0
    @Published private(set) var notice: String?
    @Published private(set) var engineName = AloudTTSConfig.engineLabel
    @Published var speed = AloudTTSConfig.speechRate {
        didSet { didChangeSpeed() }
    }

    private var host: ReaderAloudHost?
    private var units: [AloudUnit] = []
    private var engine: HTTPTTS?
    /// 本书封面的 JPEG 字节与来源地址（锁屏封面 + 灵动岛共用），按地址缓存。
    /// 存 Data 不存 UIImage：MPMediaItemArtwork 回调是 @Sendable，UIImage 不是 Sendable。
    private var artworkData: Data?
    private var artworkKey: String?
    private var artworkTask: Task<Void, Never>?
    /// 本章各段已知的音频时长（在线引擎，随播放逐段记录），用于本章进度条。
    private var unitDurations: [Int: TimeInterval] = [:]
    /// 当前段实际使用的在线引擎；nil = 系统语音。
    /// 多角色可以让旁白用系统语音、对话用某个在线引擎，所以不能只看会话引擎。
    private var activeEngine: HTTPTTS?
    var playbackEngine: PlaybackEngine { activeEngine == nil ? .system : .http }

    private let synthesizer = AVSpeechSynthesizer()
    /// 整个收听会话复用一个播放器（音频图只建一次，段间只换源文件）。
    private var player: AloudAudioPlayer?
    /// 换成另一个系统音色：立刻用新声部重读当前段（暂停中则下次播放生效）。
    func applyVoiceChange() {
        guard isRunning, playbackEngine == .system else { return }
        cancelUnitPlayback()
        isBuffering = false
        if isPlaying { playUnit() }
    }

    /// 播放器当前载入的章节/段落；resume 只恢复同段的暂停。
    private var playerLoadedUnit: (chapter: Int, unit: Int)?
    /// 跨段定位后，等新段音频载入时从这个秒数开始（拖进度条 / ±15 秒用）。
    private var pendingUnitOffset: TimeInterval?
    private var audioTask: Task<Void, Never>?
    private var prefetchTask: Task<Void, Never>?
    /// 已安排的预取窗口（段索引范围）：窗口内的后续段不再重复取消/重建，
    /// 否则旁白（系统语音）每读一两秒就会把在线音频的预取任务打断，永远下不完。
    private var prefetchWindow: Range<Int>?
    /// 正在下载的音频（key → 任务）：播放与预取共用，避免同一段重复请求。
    private var inflightAudio: [String: Task<URL, Error>] = [:]
    private var chapterTask: Task<Void, Never>?
    private var progressTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?
    /// 听书时长累计：每秒加一次，只在实际播放时计入。
    private var listenTask: Task<Void, Never>?
    private var noticeTask: Task<Void, Never>?
    private var timerPlayedSeconds = 0
    private var expectingFinish = false
    private var resumeAfterInterruption = false
    private var downloadErrorCount = 0
    private var playErrorCount = 0
    private let rateLock = NSLock()
    private var lastRequestAt = Date.distantPast
    // 只在 init/deinit 里访问；deinit 是 nonisolated，不能读主 actor 隔离的属性。
    private nonisolated(unsafe) var noticeObservers: [NSObjectProtocol] = []

    override init() {
        super.init()
        synthesizer.delegate = self
        registerInterruptions()
    }

    deinit {
        noticeObservers.forEach { NotificationCenter.default.removeObserver($0) }
        let cc = MPRemoteCommandCenter.shared()
        cc.playCommand.isEnabled = false
        cc.pauseCommand.isEnabled = false
        cc.nextTrackCommand.isEnabled = false
        cc.previousTrackCommand.isEnabled = false
        cc.playCommand.removeTarget(nil)
        cc.pauseCommand.removeTarget(nil)
        cc.nextTrackCommand.removeTarget(nil)
        cc.previousTrackCommand.removeTarget(nil)
    }

    // MARK: 宿主

    func attach(_ host: ReaderAloudHost) {
        self.host = host
        refreshEngineLabel()
    }

    func detach() {
        stop()
        host = nil
    }

    // MARK: 入口

    /// 阅读页点击「听书」：已启动就只展示面板；否则从当前位置开始朗读。
    func openCurrent() {
        guard let host else { return }
        guard !isRunning else { return }
        start(chapter: host.currentChapter(), fromOffset: host.currentOffset())
    }

    /// 开始朗读：startOffset 是章节内字符偏移，nil 表示章首。
    /// 当前章还没加载或是分卷页时，自动跳到下一个可读章。
    func start(chapter: Int, fromOffset startOffset: Int? = nil) {
        guard let host, !isRunning else { return }
        resolveEngineSelection()
        guard host.chapterCount() > 0 else { pushNotice("章节还在加载，稍后再播放"); return }
        if let list = host.units(chapter), !list.isEmpty {
            beginRun(chapter: chapter, units: list, offset: startOffset ?? 0, applyTimer: true)
            return
        }
        guard host.readableChapter(chapter + 1, 1) != nil else {
            pushNotice("本章还没有可朗读的内容")
            return
        }
        isRunning = true
        isPlaying = true
        chapterIndex = chapter
        activateSession()
        updateRemoteCommands(enabled: true)
        applyTimerDefault()
        restartTimerLoop()
        advanceChapter(direction: 1)
    }

    private func beginRun(chapter: Int, units list: [AloudUnit], offset: Int, applyTimer: Bool = false) {
        guard let host else { return }
        AloudPurifyStore.shared.reloadBodyRules()
        AloudPrefetchStatus.shared.reset()
        prefetchTask?.cancel()
        prefetchWindow = nil
        let expanded = AloudMultiVoice.expand(list)
        isRunning = true
        isPlaying = true
        chapterIndex = chapter
        chapterTitle = host.chapterTitle(chapter)
        units = expanded
        unitList = expanded
        unitIndex = resolveStartUnit(offset)
        unitTotal = expanded.count
        unitDurations.removeAll()
        downloadErrorCount = 0
        playErrorCount = 0
        activateSession()
        updateRemoteCommands(enabled: true)
        if applyTimer { applyTimerDefault() }
        restartTimerLoop()
        restartListeningClock()
        host.follow(chapter, expanded[unitIndex].offset)
        playUnit()
    }

    /// 开关多角色 / 改完角色声线后：按当前段的偏移重建本章队列，原地继续。
    func reloadRoleVoices() {
        guard isRunning, let host, let list = host.units(chapterIndex) else { return }
        let offset = units.indices.contains(unitIndex) ? units[unitIndex].offset : 0
        prefetchTask?.cancel()
        prefetchWindow = nil
        cancelUnitPlayback()
        let expanded = AloudMultiVoice.expand(list)
        units = expanded
        unitList = expanded
        unitTotal = expanded.count
        unitIndex = resolveStartUnit(offset)
        unitDurations.removeAll()
        if isPlaying { playUnit() }
    }

    private func resolveStartUnit(_ offset: Int) -> Int {
        guard offset > 0 else { return 0 }
        // 从包含 offset 的段落开始读；后面的段落不回头。
        for (i, unit) in units.enumerated() where unit.offset + unit.text.count > offset {
            return i
        }
        return max(units.count - 1, 0)
    }

    // MARK: 播放状态

    func togglePlay() {
        if !isRunning { openCurrent(); return }
        if isPlaying { pause() } else { resume() }
    }

    func pause() {
        guard isRunning, isPlaying else { return }
        isPlaying = false
        isBuffering = false
        listenTask?.cancel(); listenTask = nil
        audioTask?.cancel(); audioTask = nil
        progressTask?.cancel(); progressTask = nil
        expectStop()
        player?.pause()
        updateNowPlaying()
    }

    func resume() {
        guard isRunning, !isPlaying else { return }
        isPlaying = true
        restartListeningClock()
        if isBuffering { return }
        if playbackEngine == .http, let player, player.hasAudio,
           playerLoadedUnit?.chapter == chapterIndex,
           playerLoadedUnit?.unit == unitIndex {
            expectingFinish = true
            _ = player.play()
            startProgressTracking()
        } else {
            playUnit()
        }
        updateNowPlaying()
    }

    func stop() {
        highlight.clear()
        guard isRunning else { return }
        isRunning = false
        isPlaying = false
        isBuffering = false
        audioTask?.cancel(); audioTask = nil
        prefetchTask?.cancel(); prefetchTask = nil
        prefetchWindow = nil
        chapterTask?.cancel(); chapterTask = nil
        progressTask?.cancel(); progressTask = nil
        timerTask?.cancel(); timerTask = nil
        listenTask?.cancel(); listenTask = nil
        timerLeft = 0
        expectStop()
        player?.stop()
        playerLoadedUnit = nil
        pendingUnitOffset = nil
        units = []
        unitList = []
        activeEngine = nil
        chapterIndex = -1
        unitTotal = 0
        unitText = ""
        unitDurations.removeAll()
        chapterPlayed = 0
        chapterDuration = 0
        updateRemoteCommands(enabled: false)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: [.notifyOthersOnDeactivation])
    }

    // MARK: 段落切换（原版 prevP / nextP）

    func previousUnit() {
        guard isRunning else { return }
        cancelUnitPlayback()
        if unitIndex > 0 {
            unitIndex -= 1
            playUnit()
        } else {
            advanceChapter(direction: -1)
        }
    }

    func nextUnit() {
        guard isRunning else { return }
        cancelUnitPlayback()
        advance()
    }

    private func advance() {
        guard isRunning else { return }
        if unitIndex + 1 < units.count {
            unitIndex += 1
            playUnit()
        } else {
            advanceChapter(direction: 1)
        }
    }

    // MARK: 章节切换（原版 prevChapter / nextChapter）

    func manualChapter(direction: Int) {
        guard isRunning else { return }
        cancelUnitPlayback()
        advanceChapter(direction: direction)
    }

    private func advanceChapter(direction: Int) {
        guard let host, isRunning else { return }
        guard let next = host.readableChapter(chapterIndex + direction, direction) else {
            if direction > 0 {
                stopAllForBookEnd()
            } else {
                pushNotice("前面没有章节了")
                if isPlaying { playUnit() }
            }
            return
        }
        loadAndPlayChapter(next, direction: direction)
    }

    /// 目录里点选章节：朗读中直接跳到该章章首继续读（跨章跳过分卷）。
    func seekChapter(_ target: Int) {
        guard let host, isRunning, target != chapterIndex else { return }
        let direction = target > chapterIndex ? 1 : -1
        guard let next = host.readableChapter(target, direction) ?? host.readableChapter(target, -direction) else {
            pushNotice("这一章没有可朗读的内容")
            return
        }
        guard next != chapterIndex else { return }
        cancelUnitPlayback()
        loadAndPlayChapter(next, direction: 1)
    }

    /// 进度条/队列定位：跳到本章第 index 段；暂停时只定位不播放。
    /// - Parameter seconds: 跨段定位时在目标段内的起始秒数（音频载入后 seek 到这里）。
    func seekUnit(_ index: Int, inside seconds: TimeInterval? = nil) {
        guard isRunning, units.indices.contains(index), index != unitIndex else { return }
        cancelUnitPlayback()
        pendingUnitOffset = seconds
        unitIndex = index
        unitTotal = units.count
        unitText = units[index].text
        host?.follow(chapterIndex, units[index].offset)
        updateChapterProgress()
        if let seconds, seconds > 0 {
            let model = chapterTimeline()
            if model.starts.indices.contains(index) {
                chapterPlayed = min(model.starts[index] + seconds, model.total)
            }
        }
        updateNowPlaying()
        if isPlaying { playUnit() }
    }

    // MARK: 本章播放进度

    /// 拖动本章进度条：按比例定位到对应时间段所在的段。
    /// 目标落在当前段、而这一段已经有真实音频时，直接在段内 seek ——
    /// 长段落里拖进度条不会「先弹回段首」，松手就是松手的位置。
    func seekChapterProgress(_ fraction: Double) {
        guard isRunning, !units.isEmpty else { return }
        let model = chapterTimeline()
        guard model.total > 0 else { return }
        let target = min(max(fraction, 0), 1) * model.total
        var index = 0
        for i in model.starts.indices where model.starts[i] <= target { index = i }
        if index == unitIndex, canSeekInsideLoadedUnit, let player {
            let inside = min(max(target - model.starts[index], 0), player.duration)
            player.seek(to: inside)
            chapterPlayed = model.starts[index] + inside
            updateNowPlaying()
            return
        }
        // 跨段：新段音频载入后再跳到段内目标秒数，精度到秒。
        seekUnit(index, inside: max(target - model.starts[index], 0))
    }

    /// 播放器载入的就是当前段，且这段有真实音频（在线引擎）。
    private var canSeekInsideLoadedUnit: Bool {
        guard playbackEngine == .http,
              let player, player.hasAudio, player.duration > 0,
              let loaded = playerLoadedUnit else { return false }
        return loaded.chapter == chapterIndex && loaded.unit == unitIndex
    }

    /// 前进/后退若干秒：在线引擎按真实音频时间跳，系统语音按估算时间轴跳；
    /// 目标还落在同一段（段落很长或已到头）时至少走一段，避免按了没反应。
    func skip(seconds delta: TimeInterval) {
        guard isRunning, !units.isEmpty else { return }
        let model = chapterTimeline()
        guard model.total > 0 else {
            if delta < 0 { previousUnit() } else { nextUnit() }
            return
        }
        let start = model.starts.indices.contains(unitIndex) ? model.starts[unitIndex] : 0
        let base = chapterPlayed > 0 ? chapterPlayed : start
        let target = min(max(base + delta, 0), model.total)
        // 目标还在当前段、这段有真实音频：直接在段内跳，精度到秒。
        if canSeekInsideLoadedUnit, let player, target - start <= player.duration {
            let inside = min(max(target - start, 0), player.duration)
            player.seek(to: inside)
            chapterPlayed = start + inside
            updateNowPlaying()
            return
        }
        var index = 0
        for i in model.starts.indices where model.starts[i] <= target { index = i }
        if index != unitIndex {
            seekUnit(index, inside: max(target - model.starts[index], 0))
        } else if delta < 0 {
            previousUnit()
        } else {
            nextUnit()
        }
    }

    /// 记录当前段的音频时长并刷新本章进度（在线引擎；系统语音没有时间概念）。
    private func updateChapterProgress() {
        guard playbackEngine == .http, units.indices.contains(unitIndex) else {
            chapterPlayed = 0
            chapterDuration = 0
            return
        }
        let loaded = playerLoadedUnit
        if loaded?.chapter == chapterIndex, loaded?.unit == unitIndex,
           let player, player.hasAudio, player.duration > 0 {
            unitDurations[unitIndex] = player.duration
        }
        let model = chapterTimeline()
        guard model.total > 0 else {
            chapterPlayed = 0
            chapterDuration = 0
            return
        }
        let base = model.starts.indices.contains(unitIndex) ? model.starts[unitIndex] : 0
        let inside: TimeInterval = (loaded?.chapter == chapterIndex && loaded?.unit == unitIndex)
            ? max(player?.currentTime ?? 0, 0) : 0
        chapterDuration = model.total
        chapterPlayed = min(max(base + inside, 0), model.total)
    }

    /// 本章各段的累计时间轴：已知时长的段用实际时长，未知段按字数 × 步长估算；
    /// 步长优先用已播段标定，没有已知段时按 0.18 秒/字随倍速缩放。
    private func chapterTimeline() -> (starts: [TimeInterval], total: TimeInterval) {
        guard !units.isEmpty else { return ([], 0) }
        var knownSeconds: TimeInterval = 0
        var knownChars = 0
        for (i, unit) in units.enumerated() {
            if let known = unitDurations[i], known > 0 {
                knownSeconds += known
                knownChars += max(unit.text.count, 1)
            }
        }
        let fallbackPace = 0.18 / max(AloudTTSConfig.rateDisplay(for: speed), 0.5)
        let pace = knownChars > 0 ? knownSeconds / TimeInterval(knownChars) : fallbackPace
        var starts: [TimeInterval] = []
        starts.reserveCapacity(units.count)
        var cursor: TimeInterval = 0
        for (i, unit) in units.enumerated() {
            starts.append(cursor)
            if let known = unitDurations[i], known > 0 {
                cursor += known
            } else {
                cursor += TimeInterval(max(unit.text.count, 1)) * pace
            }
        }
        return (starts, cursor)
    }

    /// 当前段落音频的时间轴（在线引擎才有；系统语音 TTS 无时间概念返回 nil）。
    var audioTime: (current: TimeInterval, duration: TimeInterval)? {
        guard playbackEngine == .http, let player, player.hasAudio,
              player.duration > 0 else { return nil }
        return (player.currentTime, player.duration)
    }

    private func loadAndPlayChapter(_ next: Int, direction: Int) {
        guard let host, isRunning else { return }
        isBuffering = true
        chapterTask?.cancel()
        chapterTask = Task { @MainActor in
            let ok = await host.openChapter(next)
            guard !Task.isCancelled, isRunning else { return }
            guard ok, let fresh = host.units(next), !fresh.isEmpty else {
                isBuffering = false
                isPlaying = false
                updateNowPlaying()
                pushNotice(direction > 0 ? "下一章加载失败，点播放重试" : "上一章加载失败")
                return
            }
            chapterIndex = next
            chapterTitle = host.chapterTitle(next)
            let expanded = AloudMultiVoice.expand(fresh)
            units = expanded
            unitList = expanded
            unitTotal = expanded.count
            unitDurations.removeAll()
            prefetchTask?.cancel()
            prefetchWindow = nil
            unitIndex = direction > 0 ? 0 : max(expanded.count - 1, 0)
            host.follow(next, expanded[unitIndex].offset)
            updateNowPlaying()
            playUnit()
        }
    }

    private func stopAllForBookEnd() {
        pushNotice("朗读完毕")
        stop()
    }

    // MARK: 单元播放

    private func cancelUnitPlayback() {
        audioTask?.cancel(); audioTask = nil
        progressTask?.cancel(); progressTask = nil
        expectStop()
        player?.stop()
        playerLoadedUnit = nil
        pendingUnitOffset = nil
        isBuffering = false
    }

    private func playUnit() {
        guard isRunning, isPlaying, let host, units.indices.contains(unitIndex) else { return }
        let unit = units[unitIndex]
        unitText = unit.text
        unitTotal = units.count
        isBuffering = false
        host.follow(chapterIndex, unit.offset)

        // 多角色：角色能覆盖引擎；没配置就沿用当前会话引擎。
        var httpEngine: HTTPTTS? = engine
        var systemVoice: AVSpeechSynthesisVoice? = AloudVoiceConfig.speechVoice
        if let roleChoice = AloudRoleVoiceResolver.choice(for: unit.speaker,
                                                          config: AloudRoleVoiceStore.shared.config) {
            switch roleChoice {
            case let .engine(value):
                httpEngine = value
                systemVoice = nil
            case let .system(value):
                httpEngine = nil
                systemVoice = value ?? AloudVoiceConfig.speechVoice
            }
        }
        activeEngine = httpEngine

        updateNowPlaying()
        updateChapterProgress()
        guard let speak = AloudSpeechText.prepare(unit.text) else {
            // 整段没有字母数字（如纯标点分隔行）：直接进下一段。
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 120_000_000)
                guard isRunning, isPlaying else { return }
                advance()
            }
            return
        }
        if let httpEngine {
            playHTTPUnit(unit, speak: speak, engine: httpEngine)
        } else {
            speakSystemUnit(speak, voice: systemVoice)
            // 系统语音段不会下载，但后面可能是在线引擎的对话段，提前预热。
            prefetch(from: unitIndex + 1)
        }
    }

    // MARK: 系统语音

    private func speakSystemUnit(_ speak: String, voice: AVSpeechSynthesisVoice?) {
        let utterance = AVSpeechUtterance(string: speak)
        utterance.voice = voice ?? AloudVoiceConfig.speechVoice
        utterance.rate = ReaderAloudController.utteranceRate(speed)
        utterance.preUtteranceDelay = 0.08
        currentUtterance = utterance
        expectingFinish = true
        synthesizer.speak(utterance)
    }

    /// 原版语速值 0–45（默认 5）显示 ((v+5)/10) 倍；映射到 AVSpeech 的 0.5=1.0x。
    static func utteranceRate(_ value: Int) -> Float {
        let factor = Float(min(max(value, 0), 45) + 5) / 10
        let rate = 0.5 * factor
        return min(max(rate, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)
    }

    // MARK: 在线引擎

    private func playHTTPUnit(_ unit: AloudUnit, speak: String, engine: HTTPTTS) {
        isBuffering = true
        audioTask?.cancel()
        // 先让预取跑起来：当前段下载可能要 1–3 秒，这段时间正好用来下载下一段。
        prefetch(from: unitIndex + 1)
        let speed = downloadSpeed(for: engine)
        let key = AloudAudioCache.shared.key(chapter: chapterTitle, engineURL: engine.url,
                                             speed: speed, text: speak)
        audioTask = Task { @MainActor in
            let fileURL: URL
            do {
                fileURL = try await downloadAudio(key: key, engine: engine, text: speak,
                                                  speed: speed, limitRate: false)
                downloadErrorCount = 0
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                handleDownloadError(error, key: key)
                return
            }
            guard !Task.isCancelled, isRunning, isPlaying else { return }
            isBuffering = false
            let audio = audioPlayer()
            do {
                try audio.load(url: fileURL)
            } catch {
                handlePlayError(key: key)
                return
            }
            audio.rate = playbackRate(for: engine)
            // 跨段定位：音频载入后先跳到段内目标秒数再播。
            if let offset = pendingUnitOffset {
                pendingUnitOffset = nil
                audio.seek(to: offset)
            }
            playerLoadedUnit = (chapterIndex, unitIndex)
            expectingFinish = true
            guard audio.play() else {
                expectingFinish = false
                handlePlayError(key: key)
                return
            }
            playErrorCount = 0
            startProgressTracking()
        }
    }

    /// 整场收听复用一个播放器实例：音频图只建一次，段间换源文件，
    /// 避免每段重建音频图造成的锁屏/后台音频会话断点。
    private func audioPlayer() -> AloudAudioPlayer {
        if let player { return player }
        let created = AloudAudioPlayer()
        created.onFinish = { [weak self] in
            guard let self, expectingFinish else { return }
            expectingFinish = false
            finishedUnit()
        }
        player = created
        return created
    }

    /// 请求服务端用的语速值：URL 不含 `{{speakSpeed}}` 的引擎固定基准值，
    /// 缓存键稳定，倍速由本机播放器变速实现。
    private func downloadSpeed(for engine: HTTPTTS) -> Int {
        engine.usesServerSpeed ? AloudTTSConfig.httpSpeakSpeed : 10
    }

    /// 本机播放速率：服务端不吃语速的引擎按界面倍速播放（音调不变）。
    private func playbackRate(for engine: HTTPTTS) -> Float {
        engine.usesServerSpeed ? 1 : Float(AloudTTSConfig.rateDisplay)
    }

    private func handleDownloadError(_ error: Error, key: String) {
        AloudAudioCache.shared.remove(key)
        downloadErrorCount += 1
        let detail = ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            .replacingOccurrences(of: "\n", with: " ")
            .prefix(50)
        if downloadErrorCount >= 5 {
            pushNotice("连续 \(downloadErrorCount) 次语音下载失败，已暂停朗读：\(detail)")
            downloadErrorCount = 0
            isPlaying = false
            isBuffering = false
            updateNowPlaying()
        } else {
            pushNotice("语音下载失败，跳过本段：\(detail)")
            advance()
        }
    }

    private func handlePlayError(key: String) {
        AloudAudioCache.shared.remove(key)
        playErrorCount += 1
        if playErrorCount >= 5 {
            pushNotice("音频连续播放失败，已暂停朗读")
            playErrorCount = 0
            isPlaying = false
            updateNowPlaying()
        } else {
            advance()
        }
    }

    private struct PrefetchItem {
        let key: String
        let text: String
        let engine: HTTPTTS
        let speed: Int
    }

    /// 提前下载后续「有在线引擎」的段落音频。多角色下旁白/对话可能用不同引擎，
    /// 所以按段解析引擎，而不是只看会话引擎；系统语音段自然跳过。
    /// 段落数取设置（1–20），只统计真正要下载音频的段。
    private func prefetch(from index: Int) {
        guard isRunning else { return }
        // 窗口内的后续段：让现有任务继续跑，不要每秒取消重建。
        if let window = prefetchWindow, index >= window.lowerBound, index < window.upperBound {
            return
        }
        prefetchTask?.cancel()
        prefetchWindow = nil
        let snapshot = units
        guard index < snapshot.count else { return }
        let config = AloudRoleVoiceStore.shared.config
        let limit = AloudTTSConfig.preloadCount
        var items: [PrefetchItem] = []

        var i = index
        let scanEnd = min(snapshot.count, index + max(limit * 12, 48))
        let title = chapterTitle
        while i < scanEnd, items.count < limit {
            let unit = snapshot[i]
            if let engine = httpEngine(for: unit.speaker, config: config),
               let speak = AloudSpeechText.prepare(unit.text) {
                let key = AloudAudioCache.shared.key(chapter: title, engineURL: engine.url,
                                                     speed: downloadSpeed(for: engine), text: speak)
                items.append(PrefetchItem(key: key, text: speak, engine: engine,
                                          speed: downloadSpeed(for: engine)))
            }
            i += 1
        }
        prefetchWindow = index..<scanEnd
        guard !items.isEmpty else { return }
        prefetchTask = Task { @MainActor [weak self] in
            guard let self else { return }
            // 同时下 2 段：短句引擎单请求就要 1–3 秒，串行永远追不上播放。
            await withTaskGroup(of: Void.self) { group in
                var next = 0
                let workers = min(2, items.count)
                while next < workers {
                    let item = items[next]
                    next += 1
                    group.addTask { await self.prefetchItem(item) }
                }
                while await group.next() != nil {
                    if Task.isCancelled {
                        group.cancelAll()
                        break
                    }
                    if next < items.count {
                        let item = items[next]
                        next += 1
                        group.addTask { await self.prefetchItem(item) }
                    }
                }
            }
        }
    }

    /// 预取一段。和当前段并行下载：当前段下载/播放的这几秒正是攒缓冲的时间。
    private func prefetchItem(_ item: PrefetchItem) async {
        guard !Task.isCancelled else { return }
        AloudPrefetchStatus.shared.started()
        do {
            _ = try await downloadAudio(key: item.key, engine: item.engine,
                                        text: item.text, speed: item.speed,
                                        limitRate: true)
            AloudPrefetchStatus.shared.finished()
        } catch {
            if Task.isCancelled {
                AloudPrefetchStatus.shared.finished()
                return
            }
            prefetchWindow = nil
            let message = ((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
                .replacingOccurrences(of: "\n", with: " ")
            AloudPrefetchStatus.shared.failed(String(message.prefix(40)))
        }
    }

    /// 同一段音频只发一次请求：播放和预取共用 in-flight 任务。
    /// 播放（limitRate: false）不排限速队列，优先拿到音频；预取按引擎并发率退让。
    private func downloadAudio(key: String, engine: HTTPTTS, text: String, speed: Int,
                               limitRate: Bool) async throws -> URL {
        if let cached = AloudAudioCache.shared.cachedFile(forKey: key) { return cached }
        if let task = inflightAudio[key] { return try await task.value }
        let task = Task { @MainActor in
            if limitRate { await waitForRateLimit(engine) }
            let data = try await AloudAudioFetcher.fetchAudio(engine: engine, text: text, speed: speed)
            try Task.checkCancellation()
            return try AloudAudioCache.shared.store(data, forKey: key)
        }
        inflightAudio[key] = task
        defer { inflightAudio[key] = nil }
        return try await task.value
    }

    private func resetPrefetchWindow() {
        prefetchWindow = nil
    }

    /// 某一段实际会用到的在线引擎；明确选了系统音色的段返回 nil。
    private func httpEngine(for speaker: AloudSpeaker, config: AloudRoleVoiceConfig) -> HTTPTTS? {
        guard config.enabled else { return engine }
        guard let choice = AloudRoleVoiceResolver.choice(for: speaker, config: config) else {
            return engine
        }
        switch choice {
        case let .engine(value): return value
        case .system: return nil
        }
    }

    /// 同步取一个限速槽位：锁只在同步函数里加，Swift 6 不允许在 async 上下文直接用 NSLock。
    private func reserveRateLimitSlot(_ interval: TimeInterval) -> TimeInterval {
        rateLock.lock()
        defer { rateLock.unlock() }
        let now = Date()
        let next = lastRequestAt.addingTimeInterval(interval)
        guard next > now else {
            lastRequestAt = now
            return 0
        }
        lastRequestAt = next
        return next.timeIntervalSince(now)
    }

    private func waitForRateLimit(_ engine: HTTPTTS) async {
        let ms = engine.requestIntervalMilliseconds
        guard ms > 0 else { return }
        let wait = reserveRateLimitSlot(TimeInterval(ms) / 1000)
        if wait > 0 {
            try? await Task.sleep(nanoseconds: UInt64(min(wait, 10) * 1_000_000_000))
        }
    }

    /// 在线音频把「播放到哪段」按字符占比估算回报，阅读进度跟随（原版 upPlayPos）。
    private func startProgressTracking() {
        progressTask?.cancel()
        guard let player else { return }
        let unit = units[unitIndex]
        progressTask = Task { @MainActor [weak self, unit] in
            guard let self else { return }
            let duration = max(player.duration, 0.1)
            let chars = max(unit.text.count, 1)
            while !Task.isCancelled {
                // 临近片尾时采样更密，片尾切换的触发点才够准。
                let remaining = max(duration - player.currentTime, 0)
                let interval: UInt64 = remaining < 1.2 ? 80_000_000 : 300_000_000
                try? await Task.sleep(nanoseconds: interval)
                guard !Task.isCancelled, isRunning, isPlaying,
                      self.unitIndex < self.units.count else { return }
                let current = self.units[self.unitIndex]
                guard current == unit else { return }
                if self.shouldAdvanceBeforeEnd(duration: duration) {
                    self.advanceBeforeEnd()
                    return
                }
                let index = min(Int(Double(chars) * player.currentTime / duration), chars - 1)
                self.host?.follow(chapterIndex, unit.offset + max(index, 0))
                self.unitDurations[self.unitIndex] = max(player.duration, 0.1)
                self.updateChapterProgress()
            }
        }
    }

    /// 片尾提前切换：在线音频剩余不足设定毫秒时，不再等它自然播完。
    /// 系统语音没有音频文件，不会走到这里。
    private func shouldAdvanceBeforeEnd(duration: TimeInterval) -> Bool {
        guard let player, player.isPlaying else { return false }
        let milliseconds = AloudTTSConfig.earlyAdvanceMilliseconds
        guard milliseconds > 0 else { return false }
        let threshold = Double(milliseconds) / 1000
        // 很短的一段不要刚播就被判成片尾。
        guard duration > threshold + 0.3, player.currentTime >= 0.2 else { return false }
        let remaining = duration - player.currentTime
        return remaining > 0 && remaining <= threshold
    }

    private func advanceBeforeEnd() {
        expectingFinish = false
        progressTask?.cancel()
        progressTask = nil
        player?.stop()
        finishedUnit()
    }

    // MARK: 听书时长

    private func restartListeningClock() {
        listenTask?.cancel()
        listenTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled, let self else { return }
                guard self.isRunning, self.isPlaying else { continue }
                ListeningStatsStore.shared.add(seconds: 1)
            }
        }
    }

    // MARK: 定时（原版 setTimer / addTimer：按播放时长倒计时，暂停不计）

    func setTimer(minutes: Int) {
        timerLeft = max(minutes, 0)
        AloudTTSConfig.timerDefault = timerLeft
        timerPlayedSeconds = 0
        if timerLeft > 0 { pushNotice("朗读定时 \(timerLeft) 分钟") }
        if isRunning { restartTimerLoop() }
    }

    private func applyTimerDefault() {
        timerLeft = AloudTTSConfig.timerDefault
        if timerLeft > 0 { pushNotice("朗读定时 \(timerLeft) 分钟") }
    }

    private func restartTimerLoop() {
        timerTask?.cancel(); timerTask = nil
        guard timerLeft > 0 else { return }
        timerTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                guard isRunning else { return }
                guard isPlaying, timerLeft > 0 else { continue }
                timerPlayedSeconds += 1
                if timerPlayedSeconds >= 60 {
                    timerPlayedSeconds = 0
                    timerLeft -= 1
                    if timerLeft <= 0 {
                        pushNotice("朗读定时结束")
                        stop()
                        return
                    }
                }
            }
        }
    }

    // MARK: 语速与引擎

    private func didChangeSpeed() {
        let clamped = min(max(speed, 0), 45)
        if clamped != speed { speed = clamped; return }
        AloudTTSConfig.speechRate = speed
        // 原版 upTtsSpeechRate：改语速立即生效。
        guard isRunning, isPlaying else { return }
        if playbackEngine == .http {
            // 音频字节与语速无关的引擎：直接改实时倍速，缓存与播放都不动。
            if let engine, !engine.usesServerSpeed {
                player?.setRate(playbackRate(for: engine))
                return
            }
            prefetchTask?.cancel()
            prefetchWindow = nil
            unitDurations.removeAll()
            cancelUnitPlayback()
            updateChapterProgress()
            playUnit()
        } else {
            expectStop()
            playUnit()
        }
    }

    /// 阅读页之外选引擎；朗读中切换会立即用新引擎重读当前段。
    func selectEngine(_ engine: HTTPTTS?) {
        AloudTTSConfig.selectedEngineID = engine.map { "\($0.id)" } ?? ""
        self.engine = engine
        activeEngine = engine
        engineName = host2engineName()
        prefetchTask?.cancel()
        prefetchWindow = nil
        downloadErrorCount = 0
        guard isRunning else { return }
        cancelUnitPlayback()
        if isPlaying { playUnit() }
    }

    /// 选中引擎失效（比如被删除）时回退系统语音。
    func resolveEngineSelection() {
        let selected = AloudTTSConfig.selectedEngine
        if selected == nil, !(AloudTTSConfig.selectedEngineID.isEmpty || AloudTTSConfig.selectedEngineID == "0") {
            AloudTTSConfig.selectedEngineID = ""
        }
        engine = selected
        activeEngine = selected
        engineName = host2engineName()
    }

    func refreshEngineLabel() {
        engineName = host2engineName()
        if engine == nil { engine = AloudTTSConfig.selectedEngine }
    }

    private func host2engineName() -> String {
        AloudTTSConfig.engineLabel
    }

    // MARK: 提示

    func pushNotice(_ text: String) {
        notice = text
        noticeTask?.cancel()
        noticeTask = Task { @MainActor [text] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if notice == text { notice = nil }
        }
    }

    // MARK: 音频会话/中断

    private func activateSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [])
        try? session.setActive(true)
    }

    private func registerInterruptions() {
        let center = NotificationCenter.default
        let interrupt = center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notice in
            // Notification 不是 Sendable：先把字段取成值类型，再进主线程任务。
            let type = notice.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let options = notice.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let type else { return }
                switch type {
                case AVAudioSession.InterruptionType.began.rawValue:
                    if isRunning && isPlaying { resumeAfterInterruption = true; pause() }
                case AVAudioSession.InterruptionType.ended.rawValue:
                    if resumeAfterInterruption, AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume) {
                        resumeAfterInterruption = false
                        resume()
                    }
                default: break
                }
            }
        }
        let route = center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] notice in
            let reason = notice.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            Task { @MainActor [weak self] in
                guard let self, isPlaying, let reason,
                      reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue else { return }
                pause()
            }
        }
        noticeObservers = [interrupt, route]
    }

    // MARK: 锁屏控制台

    private var remoteRegistered = false

    private func updateRemoteCommands(enabled: Bool) {
        let cc = MPRemoteCommandCenter.shared()
        cc.playCommand.isEnabled = enabled
        cc.pauseCommand.isEnabled = enabled
        cc.nextTrackCommand.isEnabled = enabled
        cc.previousTrackCommand.isEnabled = enabled
        guard enabled, !remoteRegistered else { return }
        remoteRegistered = true
        // 闭包统一登记，不点名当前系统对返回枚举的 Swift 名称（SDK 版本间有更名）。
        _ = cc.playCommand.addTarget { [weak self] _ in self?.resume(); return .success }
        _ = cc.pauseCommand.addTarget { [weak self] _ in self?.pause(); return .success }
        _ = cc.nextTrackCommand.addTarget { [weak self] _ in self?.nextUnit(); return .success }
        _ = cc.previousTrackCommand.addTarget { [weak self] _ in self?.previousUnit(); return .success }
    }

    private func updateNowPlaying() {
        guard isRunning else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            NowPlayingActivityController.shared.endImmediately()
            return
        }
        guard let host else { return }
        let bookName = host.bookLabel()
        let cover = host.coverURL()
        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle] = chapterTitle.isEmpty ? "朗读" : chapterTitle
        info[MPMediaItemPropertyAlbumTitle] = bookName
        info[MPMediaItemPropertyArtist] = engineName
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        if let artworkData = artworkData {
            // 回调是 @Sendable：只捕获 Data，解码放回调里。
            info[MPMediaItemPropertyArtwork] = CoverArtworkLoader.mediaArtwork(from: artworkData)
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        loadArtworkIfNeeded(cover)
        NowPlayingActivityController.shared.start(
            kind: .aloud,
            title: chapterTitle.isEmpty ? "朗读" : chapterTitle,
            subtitle: bookName,
            isPlaying: isPlaying,
            elapsed: chapterPlayed,
            duration: chapterDuration,
            coverKey: cover,
            coverData: artworkData
        )
    }

    /// 封面按地址缓存：同一本书朗读全程只取一次。
    private func loadArtworkIfNeeded(_ coverUrl: String?) {
        guard let coverUrl, !coverUrl.isEmpty, let url = URL(string: coverUrl) else {
            artworkTask?.cancel()
            artworkTask = nil
            artworkData = nil
            artworkKey = nil
            return
        }
        if artworkKey == coverUrl, artworkData != nil { return }
        artworkKey = coverUrl
        artworkData = nil
        let origin = host?.bookOrigin()
        artworkTask?.cancel()
        artworkTask = Task { @MainActor [weak self] in
            let data = await CoverArtworkLoader.load(url: url, origin: origin, maxPixel: 600)
            guard !Task.isCancelled, let self, self.artworkKey == coverUrl else { return }
            self.artworkData = data
            self.updateNowPlaying()
        }
    }

    // MARK: 预期完成管理

    private func expectStop() {
        expectingFinish = false
        currentUtterance = nil
        synthesizer.stopSpeaking(at: .immediate)
    }

    private func finishedUnit() {
        progressTask?.cancel(); progressTask = nil
        guard isRunning, isPlaying else { return }
        advance()
    }
}

// MARK: - 语音委托

extension ReaderAloudController: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        // AVSpeechUtterance 不是 Sendable：用对象标识跨到主线程比较。
        let identity = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in
            guard let self, expectingFinish, let current = currentUtterance,
                  ObjectIdentifier(current) == identity else { return }
            currentUtterance = nil
            expectingFinish = false
            finishedUnit()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        // 同上：只把值类型的文本与对象标识带过并发域。
        let identity = ObjectIdentifier(utterance)
        let string = utterance.speechString
        Task { @MainActor [weak self] in
            guard let self, isRunning, isPlaying, playbackEngine == .system,
                  let current = currentUtterance, ObjectIdentifier(current) == identity,
                  units.indices.contains(unitIndex) else { return }
            let unit = units[unitIndex]
            // AVSpeech 使用 UTF-16；阅读偏移是 Character。组合 Emoji 和前导空白要映射回原文。
            let end = min(max(NSMaxRange(characterRange), 0), string.utf16.count)
            let spoken = (string as NSString).substring(to: end).count
            let leading = unit.text.prefix(while: { $0.isWhitespace }).count
            let position = min(max(leading + spoken - 1, 0), max(unit.text.count - 1, 0))
            host?.follow(chapterIndex, unit.offset + position)
        }
    }
}
