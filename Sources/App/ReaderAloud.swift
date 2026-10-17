import SwiftUI
import AVFoundation
import MediaPlayer

/// 朗读单元：正文段落 + 其在整章文本里的字符偏移（与搜索/书签的偏移口径一致）。
struct AloudUnit: Equatable {
    var offset: Int
    var text: String
}

/// 阅读器注入给朗读控制器的宿主能力。离开阅读页时调用 detach() 清空，
/// 防止闭包回持阅读器的状态包装。
struct ReaderAloudHost {
    var currentChapter: () -> Int = { 0 }
    var chapterCount: () -> Int = { 0 }
    var chapterTitle: (Int) -> String = { _ in "" }
    var bookLabel: () -> String = { "" }
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

    @Published private(set) var isRunning = false
    @Published private(set) var isPlaying = false
    @Published private(set) var isBuffering = false
    @Published private(set) var chapterIndex = -1
    @Published private(set) var unitIndex = 0
    @Published private(set) var unitTotal = 0
    @Published private(set) var unitText = ""
    @Published private(set) var chapterTitle = ""
    @Published private(set) var timerLeft = 0
    @Published private(set) var notice: String?
    @Published private(set) var engineName = AloudTTSConfig.engineLabel
    @Published var speed = AloudTTSConfig.speechRate {
        didSet { didChangeSpeed() }
    }

    private var host: ReaderAloudHost?
    private var units: [AloudUnit] = []
    private var engine: HTTPTTS?
    var playbackEngine: PlaybackEngine { engine == nil ? .system : .http }

    private let synthesizer = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?
    private var audioTask: Task<Void, Never>?
    private var prefetchTask: Task<Void, Never>?
    private var chapterTask: Task<Void, Never>?
    private var progressTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?
    private var noticeTask: Task<Void, Never>?
    private var timerPlayedSeconds = 0
    private var expectingFinish = false
    private var resumeAfterInterruption = false
    private var downloadErrorCount = 0
    private var playErrorCount = 0
    private let rateLock = NSLock()
    private var lastRequestAt = Date.distantPast
    private var noticeObservers: [NSObjectProtocol] = []
    private let prefetchCount = 10

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
        isRunning = true
        isPlaying = true
        chapterIndex = chapter
        chapterTitle = host.chapterTitle(chapter)
        units = list
        unitIndex = resolveStartUnit(offset)
        unitTotal = list.count
        downloadErrorCount = 0
        playErrorCount = 0
        activateSession()
        updateRemoteCommands(enabled: true)
        if applyTimer { applyTimerDefault() }
        restartTimerLoop()
        host.follow(chapter, list[unitIndex].offset)
        playUnit()
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
        audioTask?.cancel(); audioTask = nil
        progressTask?.cancel(); progressTask = nil
        expectStop()
        player?.pause()
        updateNowPlaying()
    }

    func resume() {
        guard isRunning, !isPlaying else { return }
        isPlaying = true
        if isBuffering { return }
        if playbackEngine == .http, let player, player.url != nil {
            player.play()
            startProgressTracking()
        } else {
            playUnit()
        }
        updateNowPlaying()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        isPlaying = false
        isBuffering = false
        audioTask?.cancel(); audioTask = nil
        prefetchTask?.cancel(); prefetchTask = nil
        chapterTask?.cancel(); chapterTask = nil
        progressTask?.cancel(); progressTask = nil
        timerTask?.cancel(); timerTask = nil
        timerLeft = 0
        expectStop()
        player?.stop()
        player = nil
        units = []
        chapterIndex = -1
        unitTotal = 0
        unitText = ""
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
            units = fresh
            unitTotal = fresh.count
            unitIndex = direction > 0 ? 0 : max(fresh.count - 1, 0)
            host.follow(next, fresh[unitIndex].offset)
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
        player = nil
        isBuffering = false
    }

    private func playUnit() {
        guard isRunning, isPlaying, let host, units.indices.contains(unitIndex) else { return }
        let unit = units[unitIndex]
        unitText = unit.text
        unitTotal = units.count
        isBuffering = false
        host.follow(chapterIndex, unit.offset)
        updateNowPlaying()
        guard let speak = AloudText.speakText(for: unit.text) else {
            // 整段没有字母数字（如纯标点分隔行）：直接进下一段。
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 120_000_000)
                guard isRunning, isPlaying else { return }
                advance()
            }
            return
        }
        if let httpEngine = engine {
            playHTTPUnit(unit, speak: speak, engine: httpEngine)
        } else {
            speakSystemUnit(speak)
        }
    }

    // MARK: 系统语音

    private func speakSystemUnit(_ speak: String) {
        let utterance = AVSpeechUtterance(string: speak)
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        utterance.rate = ReaderAloudController.utteranceRate(speed)
        utterance.preUtteranceDelay = 0.08
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
        let key = AloudAudioCache.shared.key(chapter: chapterTitle, engineURL: engine.url,
                                             speed: AloudTTSConfig.httpSpeakSpeed, text: speak)
        audioTask = Task { @MainActor in
            let fileURL: URL
            if let cached = AloudAudioCache.shared.cachedFile(forKey: key) {
                fileURL = cached
            } else {
                do {
                    await waitForRateLimit(engine)
                    let data = try await AloudAudioFetcher.fetchAudio(
                        engine: engine, text: speak, speed: AloudTTSConfig.httpSpeakSpeed)
                    try Task.checkCancellation()
                    fileURL = try AloudAudioCache.shared.store(data, forKey: key)
                    downloadErrorCount = 0
                } catch is CancellationError {
                    return
                } catch {
                    handleDownloadError(error, key: key)
                    return
                }
            }
            guard !Task.isCancelled, isRunning, isPlaying else { return }
            isBuffering = false
            do {
                let newPlayer = try AVAudioPlayer(contentsOf: fileURL)
                newPlayer.delegate = self
                newPlayer.prepareToPlay()
                player = newPlayer
                playErrorCount = 0
                newPlayer.play()
                expectingFinish = true
                startProgressTracking()
                prefetch(from: unitIndex + 1)
            } catch {
                handlePlayError(key: key)
            }
        }
    }

    private func handleDownloadError(_ error: Error, key: String) {
        _ = error   // 下载失败统一提示+跳过，错误细节在调试日志里。
        AloudAudioCache.shared.remove(key)
        downloadErrorCount += 1
        if downloadErrorCount >= 5 {
            pushNotice("连续 \(downloadErrorCount) 次语音下载失败，已暂停朗读")
            downloadErrorCount = 0
            isPlaying = false
            isBuffering = false
            updateNowPlaying()
        } else {
            pushNotice("语音下载失败，跳过本段")
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

    /// 提前下载后续段落音频；有并发率时按间隔限速。
    private func prefetch(from index: Int) {
        guard isRunning, playbackEngine == .http, let engine else { return }
        prefetchTask?.cancel()
        let snapshot = units
        let title = chapterTitle
        let speed = AloudTTSConfig.httpSpeakSpeed
        let limit = min(index + prefetchCount - 1, snapshot.count - 1)
        guard index <= limit else { return }
        prefetchTask = Task.detached(priority: .utility) { [weak self] in
            var i = index
            while i <= limit {
                guard !Task.isCancelled else { return }
                let unit = snapshot[i]
                if let speak = AloudText.speakText(for: unit.text) {
                    let key = AloudAudioCache.shared.key(chapter: title, engineURL: engine.url,
                                                         speed: speed, text: speak)
                    if AloudAudioCache.shared.cachedFile(forKey: key) == nil {
                        do {
                            await self?.waitForRateLimit(engine)
                            let data = try await AloudAudioFetcher.fetchAudio(engine: engine, text: speak, speed: speed)
                            try Task.checkCancellation()
                            _ = try AloudAudioCache.shared.store(data, forKey: key)
                        } catch {
                            return
                        }
                    }
                }
                i += 1
            }
        }
    }

    private func waitForRateLimit(_ engine: HTTPTTS) async {
        let ms = engine.requestIntervalMilliseconds
        guard ms > 0 else { return }
        let interval = TimeInterval(ms) / 1000
        var wait: TimeInterval = 0
        rateLock.lock()
        let now = Date()
        let next = lastRequestAt.addingTimeInterval(interval)
        if next > now {
            lastRequestAt = next
            wait = next.timeIntervalSince(now)
        } else {
            lastRequestAt = now
        }
        rateLock.unlock()
        if wait > 0 {
            try? await Task.sleep(nanoseconds: UInt64(min(wait, 10) * 1_000_000_000))
        }
    }

    /// 在线音频把「播放到哪段」按字符占比估算回报，阅读进度跟随（原版 upPlayPos）。
    private func startProgressTracking() {
        progressTask?.cancel()
        guard let player else { return }
        let unit = units[unitIndex]
        let engine = playbackEngine
        progressTask = Task { @MainActor [weak self, unit] in
            guard let self else { return }
            let duration = max(player.duration, 0.1)
            let chars = max(unit.text.count, 1)
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 400_000_000)
                guard !Task.isCancelled, isRunning, isPlaying,
                      self.unitIndex < self.units.count else { return }
                let current = self.units[self.unitIndex]
                guard current == unit else { return }
                _ = engine
                let index = min(Int(Double(chars) * player.currentTime / duration), chars - 1)
                self.host?.follow(chapterIndex, unit.offset + max(index, 0))
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

    func changeSpeed(_ delta: Int) { speed += delta }

    private func didChangeSpeed() {
        let clamped = min(max(speed, 0), 45)
        if clamped != speed { speed = clamped; return }
        AloudTTSConfig.speechRate = speed
        // 原版 upTtsSpeechRate：改语速立即生效（http 重新合成当前段）。
        guard isRunning, isPlaying else { return }
        if playbackEngine == .http {
            prefetchTask?.cancel()
            cancelUnitPlayback()
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
        engineName = host2engineName()
        prefetchTask?.cancel()
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
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let type = notice.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt else { return }
                switch type {
                case AVAudioSession.InterruptionType.began.rawValue:
                    if isRunning && isPlaying { resumeAfterInterruption = true; pause() }
                case AVAudioSession.InterruptionType.ended.rawValue:
                    let options = notice.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
                    if resumeAfterInterruption, AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume) {
                        resumeAfterInterruption = false
                        resume()
                    }
                default: break
                }
            }
        }
        let route = center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] notice in
            Task { @MainActor [weak self] in
                guard let self, isPlaying else { return }
                guard let reason = notice.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                      reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue else { return }
                pause()
            }
        }
        noticeObservers = [interrupt, route]
    }

    // MARK: 锁屏控制台

    private func updateRemoteCommands(enabled: Bool) {
        let cc = MPRemoteCommandCenter.shared()
        cc.playCommand.isEnabled = enabled
        cc.pauseCommand.isEnabled = enabled
        cc.nextTrackCommand.isEnabled = enabled
        cc.previousTrackCommand.isEnabled = enabled
        cc.playCommand.removeTarget(self, action: #selector(remotePlay))
        cc.pauseCommand.removeTarget(self, action: #selector(remotePause))
        cc.nextTrackCommand.removeTarget(self, action: #selector(remoteNext))
        cc.previousTrackCommand.removeTarget(self, action: #selector(remotePrevious))
        guard enabled else { return }
        cc.playCommand.addTarget(self, action: #selector(remotePlay))
        cc.pauseCommand.addTarget(self, action: #selector(remotePause))
        cc.nextTrackCommand.addTarget(self, action: #selector(remoteNext))
        cc.previousTrackCommand.addTarget(self, action: #selector(remotePrevious))
    }

    @objc private func remotePlay() -> MPRemoteCommandStatus { resume(); return .success }
    @objc private func remotePause() -> MPRemoteCommandStatus { pause(); return .success }
    @objc private func remoteNext() -> MPRemoteCommandStatus { nextUnit(); return .success }
    @objc private func remotePrevious() -> MPRemoteCommandStatus { previousUnit(); return .success }

    private func updateNowPlaying() {
        guard isRunning else { MPNowPlayingInfoCenter.default().nowPlayingInfo = nil; return }
        guard let host else { return }
        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle] = chapterTitle.isEmpty ? "朗读" : chapterTitle
        info[MPMediaItemPropertyAlbumTitle] = host.bookLabel()
        info[MPMediaItemPropertyArtist] = engineName
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    // MARK: 预期完成管理

    private func expectStop() {
        expectingFinish = false
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
        Task { @MainActor [weak self] in
            guard let self, expectingFinish else { return }
            expectingFinish = false
            finishedUnit()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self, isRunning, isPlaying, playbackEngine == .system,
                  units.indices.contains(unitIndex) else { return }
            host?.follow(chapterIndex, units[unitIndex].offset + characterRange.location)
        }
    }
}

extension ReaderAloudController: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self, expectingFinish else { return }
            expectingFinish = false
            finishedUnit()
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            handlePlayError(key: "")
        }
    }
}
