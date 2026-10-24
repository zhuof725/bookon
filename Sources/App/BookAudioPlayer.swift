import SwiftUI
import AVFoundation
import MediaPlayer

/// 音频书（如喜马拉雅源）章节播放：AVPlayer 流式播放，支持锁屏控制台、
/// 变速（time pitch 保持音调）、±15 秒、上/下一章与播完自动进章。
@MainActor
final class BookAudioPlayer: NSObject, ObservableObject {
    /// 当前章节的音频地址；nil 表示不在音频播放状态，阅读器回到文字排版。
    @Published private(set) var chapterURL: URL?
    @Published private(set) var chapterTitle = ""
    @Published private(set) var isPlaying = false
    @Published private(set) var isBuffering = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var message: String?
    /// 定时停止：剩余分钟（0 = 未设置）。
    @Published private(set) var sleepMinutesLeft = 0
    @Published var speed: Double = BookAudioPlayer.loadSpeed() {
        didSet { BookAudioPlayer.saveSpeed(speed); applyRate() }
    }

    /// 一段播完（自然结束）回调；用于自动进下一章。
    var onFinish: (() -> Void)?
    /// 锁屏「下一章 / 上一章」回调，由阅读器接到章节跳转。
    var onRemoteNext: (() -> Void)?
    var onRemotePrevious: (() -> Void)?
    /// 播放进度（秒），约每秒回调一次，用于「上次听到哪」的记忆。
    var onProgress: ((TimeInterval) -> Void)?
    /// 当前章播放失败（多为时间签名链接过期返回 403）回调；
    /// 阅读器据此刷新目录换新链接后重试，本播放器保持原状态不改。
    var onPlaybackFailed: (() -> Void)?

    private var player: AVPlayer?
    /// 一章可能由多段音频组成（原版正文规则返回 JSON 数组时按段拼播）。
    private var queue: [URL] = []
    private var queueIndex = 0
    /// 本章的原始网络地址（用来写磁盘缓存；queue 里可能是已缓存的本地文件）。
    private var remoteQueue: [String] = []
    private var cacheTask: Task<Void, Never>?
    private var album = ""
    private var timeObserver: Any?
    private var itemEndObserver: NSObjectProtocol?
    private var itemFailureObserver: NSObjectProtocol?
    private var itemStatusObserver: NSKeyValueObservation?
    /// 一次播放只上报一次失败，避免状态与结束通知重复触发。
    private var failureNotified = false
    /// 直连失败后只尝试一次「下载再播」，避免来回重试。
    private var fallbackTried = false
    private var downloadTask: Task<Void, Never>?
    private var lastReportedSecond: TimeInterval = -1
    /// 上次计入「听书时长」的播放时刻；只累计真实前进的量。
    private var lastListenTime: TimeInterval = 0
    /// 刚发出的 seek 目标：AVPlayer 在跳转完成前还会吐几个旧时刻，
    /// 这段时间内忽略「离目标很远」的回调，进度条才不会先弹回原处。
    private var seekTarget: (time: TimeInterval, at: Date)?
    private var playerStatusObserver: NSKeyValueObservation?
    private var sleepTask: Task<Void, Never>?
    private var sleepSecondsLeft = 0
    // 只在 init/deinit 里访问；deinit 是 nonisolated。
    private nonisolated(unsafe) var systemObservers: [NSObjectProtocol] = []
    private var messageTask: Task<Void, Never>?
    private var resumeAfterInterruption = false
    private var remoteRegistered = false

    private static let speedKey = "reader.audio.speed.v1"

    /// AVPlayer 的变速稳定区间是 0.5–2.0：更快请用文字朗读的听书倍速。
    static func loadSpeed() -> Double {
        let v = UserDefaults.standard.double(forKey: speedKey)
        return (0.5...2.0).contains(v) ? v : 1.0
    }

    static func saveSpeed(_ value: Double) {
        UserDefaults.standard.set(min(max(value, 0.5), 2.0), forKey: speedKey)
    }

    override init() {
        super.init()
        registerSystemObservers()
    }

    deinit {
        systemObservers.forEach { NotificationCenter.default.removeObserver($0) }
        let cc = MPRemoteCommandCenter.shared()
        cc.playCommand.removeTarget(nil)
        cc.pauseCommand.removeTarget(nil)
        cc.togglePlayPauseCommand.removeTarget(nil)
        cc.nextTrackCommand.removeTarget(nil)
        cc.previousTrackCommand.removeTarget(nil)
    }

    // MARK: 播放控制

    func play(url rawURL: String, title: String, album: String) {
        play(urls: [rawURL], title: title, album: album)
    }

    /// 播放一章（可能是多段）。地址按顺序播完，最后一段结束才回调 onFinish。
    /// - Parameter startAt: 上次听到的秒数（同一章才传，>0 时从那里续播）。
    func play(urls rawURLs: [String], title: String, album: String, startAt: TimeInterval = 0) {
        let urls = rawURLs.compactMap { raw -> URL? in
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: trimmed) else { return nil }
            // 已缓存的段是本地文件（file://），同样可以播。
            let scheme = url.scheme?.lowercased() ?? ""
            guard scheme.hasPrefix("http") || scheme == "file" else { return nil }
            return url
        }
        guard !urls.isEmpty else {
            pushMessage("音频地址无效")
            return
        }
        stop()
        failureNotified = false
        fallbackTried = false
        chapterTitle = title
        self.album = album
        remoteQueue = urls.map(\.absoluteString)
        // 已经缓存过的段直接播本地文件（原版 SimpleCache 的效果），其余走网络边播边存。
        queue = urls.map { AudioDiskCache.cachedFile(for: $0.absoluteString) ?? $0 }
        queueIndex = 0
        chapterURL = urls[0]
        activateSession()
        // queue[0] 可能是已缓存的本地文件，直接播它。
        let created = AVPlayer(playerItem: makeItem(queue[0]))
        // 音频书起播优先：不等「缓冲到不易卡顿」的默认策略，拿到数据就开始。
        created.automaticallyWaitsToMinimizeStalling = false
        player = created
        currentTime = 0
        duration = 0
        isBuffering = true
        lastReportedSecond = -1
        startTimeObserver(created)
        if startAt > 1 {
            // 续播：先定位再起播，避免从 0 秒响一下再跳。
            let target = CMTime(seconds: startAt, preferredTimescale: 600)
            created.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
            currentTime = startAt
        }
        // 缓冲状态用 KVO 更新：周期性时间回调在卡住/失败时不可靠，界面会永远停在「正在缓冲」。
        playerStatusObserver = created.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            let status = player.timeControlStatus
            Task { @MainActor [weak self] in self?.playerStatusChanged(status) }
        }
        updateRemoteCommands(enabled: true)
        created.playImmediately(atRate: Float(speed))
        isPlaying = true
        updateNowPlaying()
        startDiskCaching()
    }

    /// 后台把本章音频存到本地缓存（原版 ExoPlayer SimpleCache 的等价物）。
    /// 不挡起播：先在线听，存完下次直接播本地文件。
    private func startDiskCaching() {
        cacheTask?.cancel()
        let remote = remoteQueue
        guard !remote.isEmpty else { return }
        cacheTask = Task.detached(priority: .utility) {
            for raw in remote {
                if Task.isCancelled { return }
                if AudioDiskCache.cachedFile(for: raw) != nil { continue }
                guard let url = URL(string: raw),
                      url.scheme?.lowercased().hasPrefix("http") == true else { continue }
                var request = URLRequest(url: url, timeoutInterval: 30)
                request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
                                 forHTTPHeaderField: "User-Agent")
                guard let (data, response) = try? await URLSession.shared.data(for: request),
                      let http = response as? HTTPURLResponse,
                      (200..<300).contains(http.statusCode), !data.isEmpty else { continue }
                AudioDiskCache.store(data, for: raw)
            }
        }
    }

    /// 建条目并按当前倍速保持音调（音频书倍速的关键设置）。
    private func makeItem(_ url: URL) -> AVPlayerItem {
        // 多段播放会换条目：旧条目的结束/失败通知必须先摘掉，
        // 否则上一段播完会再触发一次「播完」。
        removeItemObservers()
        let item = AVPlayerItem(url: url)
        item.audioTimePitchAlgorithm = .spectral
        registerItemObservers(item)
        return item
    }

    /// 一段播完：还有后续段就接着放，最后一段才算整章结束。
    private func advanceOrFinish() {
        if queueIndex + 1 < queue.count {
            queueIndex += 1
            let next = makeItem(queue[queueIndex])
            currentTime = 0
            duration = 0
            isBuffering = true
            lastReportedSecond = -1
            if let player {
                player.replaceCurrentItem(with: next)
                player.playImmediately(atRate: Float(speed))
            } else {
                let created = AVPlayer(playerItem: next)
                created.automaticallyWaitsToMinimizeStalling = false
                player = created
                startTimeObserver(created)
                created.playImmediately(atRate: Float(speed))
            }
            updateNowPlaying()
            return
        }
        isPlaying = false
        updateNowPlaying()
        onFinish?()
    }

    func toggle() {
        if isPlaying { pause() } else { resume() }
    }

    func pause() {
        guard isPlaying else { return }
        player?.pause()
        isPlaying = false
        updateNowPlaying()
    }

    func resume() {
        guard !isPlaying, let queuePlayer = player else { return }
        // 失败过的条目不能原地续播：按同一地址重建再播（等链接刷新后重试也走这里）。
        if queuePlayer.currentItem?.status == .failed,
           queue.indices.contains(queueIndex) {
            let remaining = queue[queueIndex...].map(\.absoluteString)
            play(urls: remaining, title: chapterTitle, album: album)
            return
        }
        queuePlayer.playImmediately(atRate: Float(speed))
        isPlaying = true
        updateNowPlaying()
    }

    func stop() {
        downloadTask?.cancel()
        downloadTask = nil
        cacheTask?.cancel()
        cacheTask = nil
        remoteQueue = []
        removeItemObservers()
        removeTimeObserver()
        playerStatusObserver?.invalidate()
        playerStatusObserver = nil
        sleepTask?.cancel()
        sleepTask = nil
        sleepSecondsLeft = 0
        sleepMinutesLeft = 0
        player?.pause()
        player = nil
        queue = []
        queueIndex = 0
        chapterURL = nil
        chapterTitle = ""
        album = ""
        currentTime = 0
        duration = 0
        isPlaying = false
        isBuffering = false
        message = nil
        updateRemoteCommands(enabled: false)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: [.notifyOthersOnDeactivation])
    }

    func seek(toSeconds seconds: TimeInterval) {
        guard let player, chapterURL != nil else { return }
        let clamped = min(max(seconds, 0), max(duration, 0))
        currentTime = clamped
        seekTarget = (clamped, Date())
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func skip(_ delta: TimeInterval) { seek(toSeconds: currentTime + delta) }

    // MARK: 变速

    private func applyRate() {
        guard let player, isPlaying else { return }
        player.rate = Float(speed)
        updateNowPlaying()
    }

    // MARK: 观察者

    private func registerItemObservers(_ item: AVPlayerItem) {
        let center = NotificationCenter.default
        itemEndObserver = center.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                                             object: item, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isPlaying else { return }
                self.advanceOrFinish()
            }
        }
        itemFailureObserver = center.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime,
                                                 object: item, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.handlePlaybackFailure() }
        }
        // 签名过期（403）会让条目在加载阶段直接 failed，这条路径同样要上报。
        itemStatusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            Task { @MainActor [weak self] in self?.handlePlaybackFailure() }
        }
    }

    /// 播放失败上报一次：提示用户并通知阅读器（可能刷新目录换新链接后重试）。
    private func handlePlaybackFailure() {
        guard !failureNotified else { return }
        failureNotified = true
        // 失败时立刻结束缓冲显示，否则界面停在「正在缓冲」会把错误提示挡住。
        isBuffering = false
        let reason = player?.currentItem?.error?.localizedDescription ?? "无法打开音频"
        // 直连失败常见于「服务器对 AVPlayer 的请求不友好」：自己带浏览器 UA 下载这一段，
        // 落盘后改播本地文件（原版用 ExoPlayer + 自定义 OkHttp DataSource，也是自己发请求）。
        if !fallbackTried, remoteQueue.indices.contains(queueIndex) {
            let remote = remoteQueue[queueIndex]
            if remote.lowercased().hasPrefix("http") {
                fallbackTried = true
                pushMessage("直连播放失败，正在下载这一段…")
                downloadThenPlay(remote, from: currentTime)
                return
            }
        }
        pushMessage("音频播放失败：\(reason)")
        onPlaybackFailed?()
    }

    /// 下载当前段到本地缓存后从同一位置继续播放。
    private func downloadThenPlay(_ raw: String, from seconds: TimeInterval) {
        downloadTask?.cancel()
        let title = chapterTitle, album = self.album
        downloadTask = Task { @MainActor in
            guard let url = URL(string: raw) else { return }
            var request = URLRequest(url: url, timeoutInterval: 60)
            request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
                             forHTTPHeaderField: "User-Agent")
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }
                guard (200..<300).contains(http.statusCode), !data.isEmpty else {
                    throw NSError(domain: "BookAudio", code: http.statusCode,
                                  userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode)，\(data.count) 字节"])
                }
                AudioDiskCache.store(data, for: raw)
                guard let file = AudioDiskCache.cachedFile(for: raw) else {
                    throw URLError(.fileDoesNotExist)
                }
                guard !Task.isCancelled else { return }
                play(urls: [file.absoluteString], title: title, album: album, startAt: seconds)
            } catch {
                guard !Task.isCancelled else { return }
                pushMessage("下载失败：\(error.localizedDescription)")
                onPlaybackFailed?()
            }
        }
    }

    // MARK: 定时停止（按播放时长倒计时，暂停不计）

    func setSleepTimer(minutes: Int) {
        sleepTask?.cancel()
        sleepTask = nil
        sleepSecondsLeft = max(0, minutes) * 60
        sleepMinutesLeft = sleepSecondsLeft > 0 ? max(1, Int(ceil(Double(sleepSecondsLeft) / 60))) : 0
        guard sleepSecondsLeft > 0 else { return }
        sleepTask = Task { @MainActor [weak self] in
            while !Task.isCancelled, let self, self.sleepSecondsLeft > 0 {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if Task.isCancelled { return }
                guard self.isPlaying else { continue }
                self.sleepSecondsLeft -= 5
                self.sleepMinutesLeft = max(0, Int(ceil(Double(self.sleepSecondsLeft) / 60)))
                if self.sleepSecondsLeft <= 0 {
                    self.pause()
                    break
                }
            }
        }
    }

    private func playerStatusChanged(_ status: AVPlayer.TimeControlStatus) {
        switch status {
        case .playing:
            isBuffering = false
        case .waitingToPlayAtSpecifiedRate:
            if isPlaying { isBuffering = true }
        case .paused:
            isBuffering = false
        @unknown default:
            break
        }
    }

    private func removeItemObservers() {
        let center = NotificationCenter.default
        if let token = itemEndObserver { center.removeObserver(token); itemEndObserver = nil }
        if let token = itemFailureObserver { center.removeObserver(token); itemFailureObserver = nil }
        itemStatusObserver?.invalidate()
        itemStatusObserver = nil
    }

    private func startTimeObserver(_ player: AVPlayer) {
        removeTimeObserver()
        // 0.5 秒一次：0.25 秒会让阅读页每 0.25 秒整体重绘，翻页会卡。
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self, let currentItem = self.player?.currentItem else { return }
                let reported = time.seconds.isFinite ? max(time.seconds, 0) : 0
                // seek 刚发出时还会收到旧时刻：离目标太远就跳过，避免进度条弹回去。
                if let target = self.seekTarget {
                    let stale = abs(reported - target.time) > 1.0
                        && Date().timeIntervalSince(target.at) < 1.2
                    if stale {
                        self.isBuffering = self.player?.timeControlStatus == .waitingToPlayAtSpecifiedRate
                        return
                    }
                    self.seekTarget = nil
                }
                self.currentTime = reported
                // 听书时长：只累计真正播放时前进的秒数；缓冲/seek 的大跳变直接忽略。
                if self.isPlaying, (self.player?.rate ?? 0) > 0 {
                    let delta = reported - self.lastListenTime
                    if delta > 0, delta <= 2.5 {
                        ListeningStatsStore.shared.add(seconds: delta)
                    }
                }
                self.lastListenTime = reported
                let total = currentItem.duration.seconds
                if total.isFinite, total > 0 { self.duration = total }
                self.isBuffering = self.player?.timeControlStatus == .waitingToPlayAtSpecifiedRate
                // 每秒报一次进度，界面关闭/杀进程都能记住听到哪。
                let second = floor(self.currentTime)
                if second != self.lastReportedSecond {
                    self.lastReportedSecond = second
                    self.onProgress?(self.currentTime)
                }
            }
        }
    }

    private func removeTimeObserver() {
        if let timeObserver, let player { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
    }

    private func registerSystemObservers() {
        let center = NotificationCenter.default
        let interrupt = center.addObserver(forName: AVAudioSession.interruptionNotification,
                                           object: nil, queue: .main) { [weak self] notice in
            // Notification 不是 Sendable：先取值，再进主线程任务。
            let type = notice.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let options = notice.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            Task { @MainActor [weak self] in
                guard let self, let type else { return }
                switch type {
                case AVAudioSession.InterruptionType.began.rawValue:
                    if self.isPlaying { self.resumeAfterInterruption = true; self.pause() }
                case AVAudioSession.InterruptionType.ended.rawValue:
                    if self.resumeAfterInterruption,
                       AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume) {
                        self.resumeAfterInterruption = false
                        self.resume()
                    }
                default: break
                }
            }
        }
        let route = center.addObserver(forName: AVAudioSession.routeChangeNotification,
                                       object: nil, queue: .main) { [weak self] notice in
            let reason = notice.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            Task { @MainActor [weak self] in
                guard let self, self.isPlaying, let reason,
                      reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue else { return }
                self.pause()
            }
        }
        systemObservers = [interrupt, route]
    }

    // MARK: 音频会话 / 锁屏

    private func activateSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [])
        try? session.setActive(true)
    }

    private func updateNowPlaying() {
        guard chapterURL != nil else { MPNowPlayingInfoCenter.default().nowPlayingInfo = nil; return }
        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle] = chapterTitle.isEmpty ? "音频播放" : chapterTitle
        info[MPMediaItemPropertyAlbumTitle] = album
        info[MPMediaItemPropertyArtist] = "有声书"
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? speed : 0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func updateRemoteCommands(enabled: Bool) {
        let cc = MPRemoteCommandCenter.shared()
        cc.playCommand.isEnabled = enabled
        cc.pauseCommand.isEnabled = enabled
        cc.togglePlayPauseCommand.isEnabled = enabled
        cc.nextTrackCommand.isEnabled = enabled
        cc.previousTrackCommand.isEnabled = enabled
        guard enabled, !remoteRegistered else { return }
        remoteRegistered = true
        _ = cc.playCommand.addTarget { [weak self] _ in self?.resume(); return .success }
        _ = cc.pauseCommand.addTarget { [weak self] _ in self?.pause(); return .success }
        _ = cc.togglePlayPauseCommand.addTarget { [weak self] _ in self?.toggle(); return .success }
        _ = cc.nextTrackCommand.addTarget { [weak self] _ in self?.onRemoteNext?(); return .success }
        _ = cc.previousTrackCommand.addTarget { [weak self] _ in self?.onRemotePrevious?(); return .success }
    }

    // MARK: 提示

    private func pushMessage(_ text: String) {
        message = text
        messageTask?.cancel()
        messageTask = Task { @MainActor [text] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if message == text { message = nil }
        }
    }
}

// MARK: - 音频章节界面（有声书）

/// 音频章节阅读界面：布局与听书播放器（AloudPlayerView）一致 ——
/// 顶栏返回胶囊 / ••• 菜单、书名/作者/章节、大封面（右下角「播放中」）、
/// 当前章节 + 下一章、播放进度、⏮ / 后退 15 秒 / 播放 / 前进 15 秒 / ⏭、底栏胶囊。
struct AudioChapterView: View {
    @ObservedObject var audio: BookAudioPlayer
    let book: Book
    /// 当前章节序号（从 1 开始）与总章数。
    let chapterNumber: Int
    let chapterCount: Int
    /// 下一章标题（显示成「下一章 · xxx」；nil 表示已是最后一章）。
    var nextChapterTitle: String? = nil
    /// 书源：有声书的音色由书源提供（番茄源的 tone_id），没有时音色按钮不显示。
    var source: BookSource? = nil
    /// 换音色后重新取一次本章音频。
    var onReloadAudio: (() -> Void)? = nil
    /// 显式停止播放（用于退出「书源音色」模式）。
    var onStop: (() -> Void)? = nil
    /// 正文页：取本章文字段落（有声书没有逐句时间戳，高亮按进度估算）。
    var onLoadParagraphs: (() async -> [String])? = nil
    /// 正文页的字号/行距：跟阅读器设置一致。
    var textFontSize: CGFloat = 18
    var textLineSpacing: CGFloat = 8
    /// 切到朗读（TTS）：停掉书源音频，用系统语音/在线引擎读这本书。
    var onSwitchToTTS: ((HTTPTTS?) -> Void)? = nil
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onBack: () -> Void
    let onTOC: () -> Void

    @ThemePalette private var palette
    @State private var showTone = false
    /// 0 = 封面，1 = 正文
    @State private var mode = 0
    @State private var paragraphs: [String] = []
    @State private var loadingText = false
    /// 段落时间轴（本地按停顿对齐）；没有时退回按比例估算。
    @State private var boundaries: [Double]?

    private let speedPresets: [Double] = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
    private let timerPresets = [0, 5, 10, 15, 30, 45, 60, 90, 180]

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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(palette.primary)
        .tint(palette.accent)
        .background { playerBackground }
        .animation(.easeInOut(duration: 0.15), value: audio.isPlaying)
        .sheet(isPresented: $showTone) {
            if let source {
                SourceToneSheet(source: source, onApplied: { onReloadAudio?() },
                                onSwitchToTTS: onSwitchToTTS)
                    .modifier(AppThemeRoot())
            }
        }
    }

    private var playerBackground: some View {
        ZStack {
            AppThemeCanvas()
            RadialGradient(colors: [palette.accent.opacity(0.14), palette.accent.opacity(0)],
                           center: UnitPoint(x: 0.5, y: 0.44),
                           startRadius: 8, endRadius: 330)
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

    private var modeSwitch: some View {
        HStack(spacing: 0) {
            modeButton(title: "封面", index: 0, id: "reader.audio.modeCover")
            modeButton(title: "正文", index: 1, id: "reader.audio.modeText")
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

    private var coverBody: some View {
        VStack(spacing: 0) {
            header

            Spacer(minLength: 10)
            HStack {
                Spacer(minLength: 0)
                coverArt
                Spacer(minLength: 0)
            }
            Spacer(minLength: 10)

            chapterBlock
                .padding(.horizontal, 24)

            AudioControlsPanel(audio: audio, onPrevious: onPrevious, onNext: onNext)
                .padding(.horizontal, 12)
                .padding(.top, 6)

            Spacer(minLength: 2)
        }
    }

    /// 正文页：显示本章文字，按音频进度估算高亮当前段落（番茄音频没有逐句时间戳）。
    private var textBody: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text(audio.chapterTitle.isEmpty ? " " : audio.chapterTitle)
                    .appFont(.title3.bold())
                    .lineLimit(1)
                Text(book.author.isEmpty ? book.name : "\(book.name) · \(book.author)")
                    .appFont(.caption)
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 2)
            .padding(.bottom, 6)

            if loadingText {
                ProgressView().padding(.top, 50)
                Spacer(minLength: 0)
            } else if paragraphs.isEmpty {
                Text("这一章没有可显示的文字")
                    .appFont(.footnote).foregroundStyle(palette.secondary)
                    .padding(.top, 50)
                Spacer(minLength: 0)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 18) {
                            ForEach(paragraphs.indices, id: \.self) { i in
                                paragraphView(i)
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                    }
                    .onChange(of: estimatedParagraphIndex) { index in
                        guard let index, paragraphs.indices.contains(index) else { return }
                        withAnimation(.easeInOut(duration: 0.25)) {
                            proxy.scrollTo(index, anchor: .center)
                        }
                    }
                    .onChange(of: paragraphs) { _ in
                        buildTimelineIfNeeded()
                        guard let index = estimatedParagraphIndex,
                              paragraphs.indices.contains(index) else { return }
                        proxy.scrollTo(index, anchor: .center)
                    }
                    .onChange(of: audio.duration) { _ in buildTimelineIfNeeded() }
                }
            }

            AudioControlsPanel(audio: audio, onPrevious: onPrevious, onNext: onNext)
                .padding(.horizontal, 12)
                .padding(.top, 2)
                .padding(.bottom, 4)
        }
        .task(id: audio.chapterTitle) { await loadParagraphsIfNeeded() }
    }

    /// 当前段落：有时间轴用时间轴，没有就按「已播比例 × 总字数」估算。
    private var estimatedParagraphIndex: Int? {
        guard !paragraphs.isEmpty, audio.duration > 0 else { return nil }
        if let boundaries, boundaries.count == paragraphs.count + 1 {
            let time = audio.currentTime
            for index in 0..<paragraphs.count where time < boundaries[index + 1] { return index }
            return paragraphs.count - 1
        }
        let total = paragraphs.reduce(0) { $0 + max($1.count, 1) }
        guard total > 0 else { return nil }
        let target = Int(Double(total) * min(max(audio.currentTime / audio.duration, 0), 1))
        var acc = 0
        for (i, text) in paragraphs.enumerated() {
            acc += max(text.count, 1)
            if target <= acc { return i }
        }
        return paragraphs.count - 1
    }

    /// 段内比例：优先用时间轴算，没有就用字数比例。
    private func fractionWithinParagraph(_ index: Int) -> Double {
        if let boundaries, boundaries.count == paragraphs.count + 1 {
            let start = boundaries[index]
            let end = boundaries[index + 1]
            guard end > start else { return 0 }
            return min(max((audio.currentTime - start) / (end - start), 0), 1)
        }
        let offsets = paragraphOffsets
        let total = max(offsets.total, 1)
        let played = Int(Double(total) * min(max(audio.currentTime / audio.duration, 0), 1))
        let start = offsets.starts.indices.contains(index) ? offsets.starts[index] : 0
        return min(max(Double(played - start) / Double(max(paragraphs[index].count, 1)), 0), 1)
    }

    /// 生成段落时间轴（下载/解码一次，按书+章缓存）。
    private func buildTimelineIfNeeded() {
        guard boundaries == nil, paragraphs.count > 1, audio.duration > 0,
              let url = audio.chapterURL else { return }
        let count = paragraphs.count
        let chapter = audio.chapterTitle
        if let cached = AudioSentenceTimeline.cached(bookUrl: book.bookUrl, chapter: chapter, count: count) {
            boundaries = cached
            return
        }
        let texts = paragraphs
        let duration = audio.duration
        Task.detached(priority: .utility) {
            guard let built = await AudioSentenceTimeline.build(url: url, paragraphs: texts, duration: duration) else { return }
            AudioSentenceTimeline.store(built, bookUrl: book.bookUrl, chapter: chapter)
            await MainActor.run { boundaries = built }
        }
    }

    /// 段落内按比例估到当前句（番茄音频没有逐句时间戳，只能按字数比例推进）。
    private func sentenceRange(in text: String, withinParagraph fraction: Double) -> Range<String.Index>? {
        guard !text.isEmpty else { return nil }
        let target = Int(Double(text.count) * min(max(fraction, 0), 1))
        let breaks = CharacterSet(charactersIn: "。！？…；\n")
        var start = text.startIndex
        var idx = text.startIndex
        var offset = 0
        for ch in text {
            if ch.unicodeScalars.contains(where: { breaks.contains($0) }) {
                if target <= offset + 1 {
                    let end = text.index(after: idx)
                    return start..<end
                }
                start = text.index(after: idx)
            }
            idx = text.index(after: idx)
            offset += 1
        }
        return start..<text.endIndex
    }

    /// 本章各段的累计字数，用来把「已播比例」换成段内比例。
    private var paragraphOffsets: (starts: [Int], total: Int) {
        var starts: [Int] = []
        var cursor = 0
        for text in paragraphs {
            starts.append(cursor)
            cursor += max(text.count, 1)
        }
        return (starts, cursor)
    }

    private func paragraphView(_ index: Int) -> some View {
        let current = index == estimatedParagraphIndex
        let text = paragraphs[index]
        var attributed = AttributedString(text)
        if current, audio.duration > 0 {
            let fraction = fractionWithinParagraph(index)
            if let range = sentenceRange(in: text, withinParagraph: fraction) {
                var combined = AttributedString(String(text[..<range.lowerBound]))
                var middle = AttributedString(String(text[range]))
                middle.backgroundColor = palette.highlight
                middle.foregroundColor = palette.accent
                combined.append(middle)
                combined.append(AttributedString(String(text[range.upperBound...])))
                attributed = combined
            } else {
                // 估不出句子就整段高亮，至少不会「什么都没亮」。
                attributed.backgroundColor = palette.highlight
            }
        }
        return Text(attributed)
            .font(.system(size: textFontSize))
            .lineSpacing(textLineSpacing)
            .foregroundStyle(palette.primary.opacity(0.88))
            .foregroundStyle(current ? palette.accent : palette.primary.opacity(0.88))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .overlay(alignment: .leading) {
                if current {
                    Capsule().fill(palette.accent)
                        .frame(width: 3)
                        .padding(.vertical, 10)
                }
            }
            .id(index)
            .accessibilityIdentifier("reader.audio.para.\(index)")
    }

    /// 手动校准：把当前高亮段的起点对齐到当前播放时间，后面所有边界整体平移。
    /// 段落级估算会越来越偏，用这个一键校正。
    private func calibrateTimeline() {
        guard let index = estimatedParagraphIndex,
              let current = boundaries ?? AudioSentenceTimeline.cached(bookUrl: book.bookUrl,
                                                                       chapter: audio.chapterTitle,
                                                                       count: paragraphs.count),
              current.indices.contains(index + 1),
              audio.duration > 0 else { return }
        let target = min(max(audio.currentTime, 0), audio.duration)
        let delta = target - current[index]
        var shifted: [Double] = []
        var last = 0.0
        for value in current {
            let next = min(max(value + delta, last + 0.05), audio.duration)
            shifted.append(next)
            last = next
        }
        if let lastIndex = shifted.indices.last { shifted[lastIndex] = audio.duration }
        boundaries = shifted
        AudioSentenceTimeline.store(shifted, bookUrl: book.bookUrl, chapter: audio.chapterTitle)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func loadParagraphsIfNeeded() async {
        guard let onLoadParagraphs else { return }
        loadingText = true
        let loaded = await onLoadParagraphs()
        paragraphs = loaded
        boundaries = nil
        loadingText = false
        buildTimelineIfNeeded()
    }

    private var backButton: some View {
        Button { onBack() } label: {
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
        .accessibilityIdentifier("reader.audio.back")
    }

    private var moreButton: some View {
        Menu {
            Button { onTOC() } label: {
                Label("目录", systemImage: "list.bullet.rectangle")
            }
            if mode == 1 {
                Button { calibrateTimeline() } label: {
                    Label("对齐到当前段", systemImage: "scope")
                }
                .accessibilityIdentifier("reader.audio.calibrate")
            }
            Divider()
            Button(role: .destructive) {
                onStop?()
                audio.stop()
            } label: {
                Label("停止播放", systemImage: "stop.circle")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(palette.primary)
                .frame(width: 34, height: 34)
                .background { AppGlassSurface(shape: Circle(), tint: palette.surface) }
                .contentShape(Circle())
        }
        .accessibilityLabel("更多")
        .accessibilityIdentifier("reader.audio.more")
    }

    // MARK: 书名 / 封面 / 章节

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(book.name)
                .appFont(.title.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            if !book.author.isEmpty {
                Text(book.author).appFont(.caption).foregroundStyle(palette.secondary)
            }
            HStack(spacing: 8) {
                Text("第 \(chapterNumber) 章")
                    .appFont(.subheadline)
                    .foregroundStyle(palette.secondary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text("\(chapterNumber) / \(chapterCount) 章")
                    .appFont(.caption)
                    .foregroundStyle(palette.secondary)
                    .fixedSize()
                    .accessibilityIdentifier("reader.audio.chapterProgress")
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
                playingBadge.padding(10)
            }
            .accessibilityIdentifier("reader.audio.cover")
    }

    /// 封面右下角的小胶囊：播放中 / 已暂停。
    private var playingBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "waveform")
                .font(.system(size: 10, weight: .bold))
            Text(audio.isPlaying ? "播放中" : "已暂停")
                .appFont(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.black.opacity(0.52)))
        .accessibilityHidden(true)
    }

    /// 当前章节（正在播的内容）+ 下一章 / 缓冲 / 错误提示。
    private var chapterBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(audio.chapterTitle.isEmpty ? " " : audio.chapterTitle)
                .appFont(.title3.weight(.semibold))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("reader.audio.title")
            Text(secondaryLine)
                .appFont(.caption)
                .foregroundStyle(audio.message == nil ? palette.secondary : .red)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("reader.audio.status")
        }
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
    }

    private var secondaryLine: String {
        if let message = audio.message { return message }
        if audio.isBuffering { return "正在缓冲…" }
        if let next = nextChapterTitle, !next.isEmpty { return "下一章 · \(next)" }
        return "已是最后一章"
    }

    // MARK: 底栏（目录 / 倍速 / 定时 / 设置）

    private var bottomBar: some View {
        HStack(spacing: 0) {
            bottomItem(title: "目录", symbol: "list.bullet.rectangle",
                       id: "reader.audio.toc") { onTOC() }
            Menu { speedMenuItems } label: {
                bottomLabel(title: speedText(audio.speed), symbol: "speedometer")
            }
            .accessibilityLabel("倍速")
            .accessibilityIdentifier("reader.audio.speed")
            Menu { timerMenuItems } label: {
                bottomLabel(title: timerTitle, symbol: "stopwatch")
            }
            .accessibilityLabel("定时")
            .accessibilityIdentifier("reader.audio.timer")
            if source != nil {
                bottomItem(title: "音色", symbol: "waveform",
                           id: "reader.audio.voice") { showTone = true }
            }
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

    private var timerTitle: String {
        audio.sleepMinutesLeft > 0 ? "\(audio.sleepMinutesLeft)分钟" : "定时"
    }

    @ViewBuilder
    private var speedMenuItems: some View {
        ForEach(speedPresets.indices, id: \.self) { i in
            Button {
                audio.speed = speedPresets[i]
            } label: {
                if abs(audio.speed - speedPresets[i]) < 0.01 {
                    Label(speedText(speedPresets[i]), systemImage: "checkmark")
                } else {
                    Text(speedText(speedPresets[i]))
                }
            }
            .accessibilityIdentifier("reader.audio.speed.\(speedText(speedPresets[i]))")
        }
    }

    @ViewBuilder
    private var timerMenuItems: some View {
        ForEach(timerPresets, id: \.self) { minutes in
            if minutes == 0 {
                Button("关闭定时") { audio.setSleepTimer(minutes: 0) }
                    .accessibilityIdentifier("reader.audio.timer.0")
            } else {
                Button("\(minutes) 分钟") { audio.setSleepTimer(minutes: minutes) }
                    .accessibilityIdentifier("reader.audio.timer.\(minutes)")
            }
        }
    }

    private func speedText(_ value: Double) -> String {
        if value == value.rounded() { return String(format: "%.1fx", value) }
        return String(format: "%gx", value)
    }
}

/// 播放进度 + 控制行。时间每 0.5 秒刷新，只重绘这一块，不跟着整页（封面、标题）重排。
struct AudioControlsPanel: View {
    @ObservedObject var audio: BookAudioPlayer
    let onPrevious: () -> Void
    let onNext: () -> Void

    @ThemePalette private var palette
    @State private var scrub: Double?
    /// 松手后到播放器真正到位之前的显示值：进度条不会先弹回旧位置再跳过去。
    @State private var pendingSeek: Double?
    @State private var pendingSeekTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 2) {
            progressBlock
            controlsRow
        }
    }

    private var fraction: Double {
        guard audio.duration > 0 else { return 0 }
        return min(max(audio.currentTime / audio.duration, 0), 1)
    }

    /// 进度条显示值：拖动中 → 松手后等待到位 → 真实进度。
    private var displayedFraction: Double { scrub ?? pendingSeek ?? fraction }

    private var displayedSeconds: TimeInterval {
        guard audio.duration > 0 else { return audio.currentTime }
        return displayedFraction * audio.duration
    }

    private var progressBlock: some View {
        VStack(spacing: 0) {
            Slider(value: Binding(get: { displayedFraction },
                                  set: { scrub = $0 }), in: 0...1) { editing in
                guard !editing, let value = scrub else { return }
                scrub = nil
                pendingSeek = value
                pendingSeekTask?.cancel()
                pendingSeekTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    guard !Task.isCancelled else { return }
                    if pendingSeek == value { pendingSeek = nil }
                }
                audio.seek(toSeconds: value * audio.duration)
            }
            .tint(palette.accent)
            .disabled(audio.duration <= 0)
            .onChange(of: fraction) { value in
                guard let target = pendingSeek, abs(value - target) < 0.01 else { return }
                pendingSeek = nil
            }
            .onDisappear { pendingSeekTask?.cancel() }
            .accessibilityIdentifier("reader.audio.slider")
            .accessibilityLabel("播放进度")
            HStack {
                Text(PlaybackTimeText.string(displayedSeconds))
                    .accessibilityIdentifier("reader.audio.timeCurrent")
                Spacer()
                Text("-" + PlaybackTimeText.string(max(audio.duration - displayedSeconds, 0)))
                    .accessibilityIdentifier("reader.audio.timeRemaining")
            }
            .appFont(.caption2)
            .monospacedDigit()
            .foregroundStyle(palette.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.top, 2)
    }

    // MARK: 控制行

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
        return Button { previous ? onPrevious() : onNext() } label: {
            controlFrame(Image(systemName: previous ? "backward.end.fill" : "forward.end.fill")
                .font(.system(size: 22))
                .foregroundStyle(palette.primary))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(previous ? "上一章" : "下一章")
        .accessibilityIdentifier(previous ? "reader.audio.prevChapter" : "reader.audio.nextChapter")
    }

    private func skipButton(direction: Int) -> some View {
        let previous = direction < 0
        return Button { audio.skip(previous ? -15 : 15) } label: {
            controlFrame(Image(systemName: previous ? "gobackward.15" : "goforward.15")
                .font(.system(size: 27))
                .foregroundStyle(palette.primary))
        }
        .buttonStyle(.plain)
        .disabled(audio.duration <= 0)
        .accessibilityLabel(previous ? "后退 15 秒" : "前进 15 秒")
        .accessibilityIdentifier(previous ? "reader.audio.back15" : "reader.audio.forward15")
    }

    private var playButton: some View {
        Button { audio.toggle() } label: {
            ZStack {
                Circle().fill(palette.primary).frame(width: 74, height: 74)
                if audio.isBuffering {
                    ProgressView().tint(palette.background)
                } else {
                    Image(systemName: audio.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(palette.background)
                        .offset(x: audio.isPlaying ? 0 : 3)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 74)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(audio.isPlaying ? "暂停" : "播放")
        .accessibilityIdentifier("reader.audio.play")
    }
}
