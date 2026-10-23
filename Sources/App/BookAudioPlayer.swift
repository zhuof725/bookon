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
    private var playerStatusObserver: NSKeyValueObservation?
    private var sleepTask: Task<Void, Never>?
    private var sleepSecondsLeft = 0
    private var systemObservers: [NSObjectProtocol] = []
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
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self, let currentItem = self.player?.currentItem else { return }
                self.currentTime = time.seconds.isFinite ? max(time.seconds, 0) : 0
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
            Task { @MainActor [weak self] in
                guard let self,
                      let type = notice.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt else { return }
                switch type {
                case AVAudioSession.InterruptionType.began.rawValue:
                    if self.isPlaying { self.resumeAfterInterruption = true; self.pause() }
                case AVAudioSession.InterruptionType.ended.rawValue:
                    let options = notice.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
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
            Task { @MainActor [weak self] in
                guard let self, self.isPlaying,
                      let reason = notice.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
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
/// 音频章节阅读界面：整体布局与听书播放器（AloudPlayerView）一致 ——
/// 顶栏返回、书名/作者/章节、大封面、章节进度、播放进度条、控制行、底栏（目录/倍速/定时/设置）。
struct AudioChapterView: View {
    @ObservedObject var audio: BookAudioPlayer
    let book: Book
    let positionLabel: String
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onBack: () -> Void
    let onTOC: () -> Void
    let onSettings: () -> Void

    @ThemePalette private var palette

    private let speedPresets: [Double] = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
    private let timerPresets = [0, 5, 10, 15, 30, 45, 60, 90, 180]

    var body: some View {
        VStack(spacing: 0) {
            topBar
            titleBlock
            Spacer(minLength: 8)
            BookCoverImage(url: BookCoverLocation.url(for: book), pixelSize: 900, origin: book.origin)
                .frame(width: 240, height: 320)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.2), radius: 18, x: 0, y: 10)
                .accessibilityIdentifier("reader.audio.cover")
            Spacer(minLength: 8)
            // 播放状态/进度单独成视图：时间每 0.5 秒刷新，只重绘这一块，
            // 不再整页（封面、标题、底栏）跟着重排，拖进度条也就不会卡。
            AudioControlsPanel(audio: audio, positionLabel: positionLabel,
                               onPrevious: onPrevious, onNext: onNext, onTOC: onTOC)
            Spacer(minLength: 6)
            Rectangle().fill(palette.border).frame(height: 0.5)
            bottomBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(palette.primary)
        .tint(palette.accent)
        .animation(.easeInOut(duration: 0.15), value: audio.isPlaying)
    }

    // MARK: 顶栏

    private var topBar: some View {
        HStack {
            Button { onBack() } label: {
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
            .accessibilityIdentifier("reader.audio.back")
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(book.name)
                .appFont(.title3.bold())
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if !book.author.isEmpty {
                Text(book.author).appFont(.subheadline).foregroundStyle(palette.secondary)
            }
            Text(audio.chapterTitle.isEmpty ? " " : audio.chapterTitle)
                .appFont(.subheadline).foregroundStyle(palette.secondary).lineLimit(1)
                .accessibilityIdentifier("reader.audio.title")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 24)
        .padding(.top, 10)
    }

    // MARK: 底栏（目录 / 倍速 / 定时 / 设置）

    // MARK: 底栏

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
            bottomItem(title: "设置", symbol: "gearshape",
                       id: "reader.audio.settings") { onSettings() }
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

struct AudioControlsPanel: View {
    @ObservedObject var audio: BookAudioPlayer
    let positionLabel: String
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onTOC: () -> Void

    @ThemePalette private var palette
    @State private var scrub: Double?

    var body: some View {
        VStack(spacing: 0) {
            statusLine
            chapterCountLabel
            progressBlock
            controlsRow
        }
    }

    /// 缓冲/错误状态放在听书播放器「当前句」的位置。
    private var statusLine: some View {
        Text(audio.isBuffering ? "正在缓冲…" : (audio.message ?? " "))
            .appFont(.subheadline)
            .foregroundStyle(audio.message == nil ? palette.secondary : .red)
            .lineLimit(2)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .center)
            .padding(.horizontal, 24)
            .accessibilityIdentifier("reader.audio.status")
    }

    private var chapterCountLabel: some View {
        Text(positionLabel + "章")
            .appFont(.caption).foregroundStyle(palette.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 6)
            .accessibilityIdentifier("reader.audio.chapterProgress")
    }

    private var fraction: Double {
        guard audio.duration > 0 else { return 0 }
        return min(max(audio.currentTime / audio.duration, 0), 1)
    }

    private var progressBlock: some View {
        VStack(spacing: 0) {
            Slider(value: Binding(get: { scrub ?? fraction },
                                  set: { scrub = $0 }), in: 0...1) { editing in
                if !editing, let value = scrub {
                    scrub = nil
                    audio.seek(toSeconds: value * audio.duration)
                }
            }
            .tint(palette.accent)
            .disabled(audio.duration <= 0)
            .accessibilityIdentifier("reader.audio.slider")
            .accessibilityLabel("播放进度")
            HStack {
                Text(PlaybackTimeText.string(audio.currentTime))
                    .accessibilityIdentifier("reader.audio.timeCurrent")
                Spacer()
                Text("-" + PlaybackTimeText.string(max(audio.duration - audio.currentTime, 0)))
                    .accessibilityIdentifier("reader.audio.timeRemaining")
            }
            .appFont(.caption)
            .monospacedDigit()
            .foregroundStyle(palette.secondary)
        }
        .padding(.horizontal, 24)
        .padding(.top, 6)
    }

    // MARK: 控制行

    /// 与听书播放器一致：⏮/⏭ 15 秒图标对应上一章/下一章；倍速只在底栏，右侧留同宽占位保持播放键居中。
    private var controlsRow: some View {
        HStack(spacing: 0) {
            controlButton(symbol: "list.bullet", label: "目录",
                          id: "reader.audio.tocRow", action: onTOC)
            controlButton(symbol: "gobackward.15", label: "上一章",
                          id: "reader.audio.prevChapter", action: onPrevious)
            playButton
            controlButton(symbol: "goforward.15", label: "下一章",
                          id: "reader.audio.nextChapter", action: onNext)
            Color.clear.frame(maxWidth: .infinity, minHeight: 72)
        }
        .padding(.top, 10)
    }

    private func controlButton(symbol: String, label: String, id: String,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 26))
                .foregroundStyle(palette.primary)
                .frame(maxWidth: .infinity, minHeight: 72)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    private var playButton: some View {
        Button { audio.toggle() } label: {
            ZStack {
                Circle().fill(palette.accent).frame(width: 74, height: 74)
                if audio.isBuffering {
                    ProgressView().tint(palette.onAccent)
                } else {
                    Image(systemName: audio.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(palette.onAccent)
                        .offset(x: audio.isPlaying ? 0 : 3)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 72)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(audio.isPlaying ? "暂停" : "播放")
        .accessibilityIdentifier("reader.audio.play")
    }
}
