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
    /// 临时诊断行（截图排障）：链接、签名年龄、HTTP 探测与播放器状态。
    @Published private(set) var diagnostics = ""
    @Published var speed: Double = BookAudioPlayer.loadSpeed() {
        didSet { BookAudioPlayer.saveSpeed(speed); applyRate() }
    }

    /// 一段播完（自然结束）回调；用于自动进下一章。
    var onFinish: (() -> Void)?
    /// 锁屏「下一章 / 上一章」回调，由阅读器接到章节跳转。
    var onRemoteNext: (() -> Void)?
    var onRemotePrevious: (() -> Void)?
    /// 当前章播放失败（多为时间签名链接过期返回 403）回调；
    /// 阅读器据此刷新目录换新链接后重试，本播放器保持原状态不改。
    var onPlaybackFailed: (() -> Void)?

    private var player: AVPlayer?
    private var album = ""
    private var timeObserver: Any?
    private var itemEndObserver: NSObjectProtocol?
    private var itemFailureObserver: NSObjectProtocol?
    private var itemStatusObserver: NSKeyValueObservation?
    /// 一次播放只上报一次失败，避免状态与结束通知重复触发。
    private var failureNotified = false
    private var playerStatusObserver: NSKeyValueObservation?
    private var probeTask: Task<Void, Never>?
    private var linkProbe = "未探测"
    private var signatureText = ""
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
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme?.lowercased().hasPrefix("http") == true else {
            pushMessage("音频地址无效")
            return
        }
        stop()
        failureNotified = false
        chapterTitle = title
        self.album = album
        chapterURL = url
        activateSession()
        let item = AVPlayerItem(url: url)
        // 变速时保持音调（音频书倍速的关键设置）。
        item.audioTimePitchAlgorithm = .spectral
        let created = AVPlayer(playerItem: item)
        // 音频书起播优先：不等「缓冲到不易卡顿」的默认策略，拿到数据就开始。
        created.automaticallyWaitsToMinimizeStalling = false
        player = created
        currentTime = 0
        duration = 0
        isBuffering = true
        registerItemObservers(item)
        startTimeObserver(created)
        // 缓冲状态用 KVO 更新：周期性时间回调在卡住/失败时不可靠，界面会永远停在「正在缓冲」。
        playerStatusObserver = created.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            let status = player.timeControlStatus
            Task { @MainActor [weak self] in self?.playerStatusChanged(status) }
        }
        startLinkProbe(url)
        updateRemoteCommands(enabled: true)
        created.playImmediately(atRate: Float(speed))
        isPlaying = true
        updateNowPlaying()
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
        if let failedURL = chapterURL, queuePlayer.currentItem?.status == .failed {
            play(url: failedURL.absoluteString, title: chapterTitle, album: album)
            return
        }
        queuePlayer.playImmediately(atRate: Float(speed))
        isPlaying = true
        updateNowPlaying()
    }

    func stop() {
        removeItemObservers()
        removeTimeObserver()
        playerStatusObserver?.invalidate()
        playerStatusObserver = nil
        probeTask?.cancel()
        probeTask = nil
        linkProbe = "未探测"
        signatureText = ""
        diagnostics = ""
        player?.pause()
        player = nil
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
                self.isPlaying = false
                self.updateNowPlaying()
                self.onFinish?()
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
        pushMessage("音频播放失败，点播放重试")
        refreshDiagnostics()
        onPlaybackFailed?()
    }

    // MARK: 诊断（临时）

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
        refreshDiagnostics()
    }

    /// 用与播放相同的地址发一个 Range 探测，把 HTTP 结果与签名年龄显示到界面上。
    private func startLinkProbe(_ url: URL) {
        probeTask?.cancel()
        linkProbe = "探测中…"
        signatureText = Self.signatureAge(from: url)
        refreshDiagnostics()
        probeTask = Task { @MainActor [weak self] in
            var request = URLRequest(url: url)
            request.setValue("bytes=0-1", forHTTPHeaderField: "Range")
            request.timeoutInterval = 15
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                self?.linkProbe = "HTTP \(code)"
            } catch {
                self?.linkProbe = "失败 \(error.localizedDescription.prefix(36))"
            }
            self?.refreshDiagnostics()
        }
    }

    /// buy_key 链接的 timestamp 参数（微秒）= 签名签发时刻，用于判断链接是否过期。
    private static func signatureAge(from url: URL) -> String {
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let raw = items.first(where: { $0.name == "timestamp" })?.value,
              let micros = Double(raw), micros > 0 else { return "无签名字段" }
        let age = Date().timeIntervalSince1970 - micros / 1_000_000
        guard age > 0 else { return "刚刚签名" }
        if age < 3600 { return String(format: "签名 %.0f 分钟前", age / 60) }
        if age < 86400 { return String(format: "签名 %.1f 小时前", age / 3600) }
        return String(format: "签名 %.1f 天前", age / 86400)
    }

    private func refreshDiagnostics() {
        guard chapterURL != nil else { diagnostics = ""; return }
        let host = chapterURL.map { ($0.host ?? "?") + $0.path } ?? "-"
        let itemText: String
        if let item = player?.currentItem {
            switch item.status {
            case .unknown: itemText = "unknown"
            case .readyToPlay: itemText = "ready"
            case .failed: itemText = "failed \((item.error as? NSError)?.code ?? 0)"
            @unknown default: itemText = "?"
            }
        } else {
            itemText = "无条目"
        }
        let statusText: String
        if let player {
            switch player.timeControlStatus {
            case .playing: statusText = "playing"
            case .waitingToPlayAtSpecifiedRate: statusText = "waiting"
            case .paused: statusText = "paused"
            @unknown default: statusText = "?"
            }
        } else {
            statusText = "无播放器"
        }
        let next = "\(host.suffix(60))\n\(signatureText) · \(linkProbe)\n条目 \(itemText) · \(statusText)"
        if diagnostics != next { diagnostics = next }
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
                self.refreshDiagnostics()
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

/// 音频章节阅读界面：封面 + 章节信息 + 进度 + 播放控制 + 倍速。
struct AudioChapterView: View {
    @ObservedObject var audio: BookAudioPlayer
    let book: Book
    let positionLabel: String
    let onPrevious: () -> Void
    let onNext: () -> Void

    @ThemePalette private var palette
    @State private var scrub: Double?

    private let speedPresets: [Double] = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0]

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)
            BookCoverImage(url: BookCoverLocation.url(for: book), pixelSize: 900)
                .frame(width: 200, height: 266)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: .black.opacity(0.2), radius: 16, x: 0, y: 8)
                .accessibilityIdentifier("reader.audio.cover")
            VStack(spacing: 6) {
                Text(book.name).appFont(.headline).lineLimit(1)
                Text(audio.chapterTitle)
                    .appFont(.subheadline).foregroundStyle(palette.secondary)
                    .lineLimit(2).multilineTextAlignment(.center)
                    .accessibilityIdentifier("reader.audio.title")
                Text(positionLabel).appFont(.caption).foregroundStyle(palette.secondary)
            }
            .padding(.top, 16)
            .padding(.horizontal, 24)
            Spacer(minLength: 8)
            progressBlock.padding(.horizontal, 28)
            controls.padding(.top, 4)
            speedRow.padding(.top, 4)
            Group {
                if audio.isBuffering {
                    Text("正在缓冲…")
                } else if let message = audio.message {
                    Text(message)
                } else {
                    Text(" ")
                }
            }
            .appFont(.caption)
            .foregroundStyle(audio.message == nil ? palette.secondary : .red)
            .lineLimit(2)
            .padding(.top, 6)
            .padding(.horizontal, 24)
            if !audio.diagnostics.isEmpty {
                Text(audio.diagnostics)
                    .font(.system(size: 10, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .lineLimit(5)
                    .foregroundStyle(palette.secondary)
                    .padding(.top, 8)
                    .padding(.horizontal, 16)
                    .accessibilityIdentifier("reader.audio.diagnostics")
            }
            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(palette.primary)
        .tint(palette.accent)
        .animation(.easeInOut(duration: 0.15), value: audio.isPlaying)
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
                Text(AloudPlayerView.timeString(audio.currentTime))
                    .accessibilityIdentifier("reader.audio.timeCurrent")
                Spacer()
                Text("-" + AloudPlayerView.timeString(max(audio.duration - audio.currentTime, 0)))
                    .accessibilityIdentifier("reader.audio.timeRemaining")
            }
            .appFont(.caption)
            .monospacedDigit()
            .foregroundStyle(palette.secondary)
        }
    }

    private var controls: some View {
        HStack(spacing: 0) {
            controlButton(symbol: "gobackward.15", label: "后退15秒",
                          id: "reader.audio.back15") { audio.skip(-15) }
            controlButton(symbol: "backward.end.fill", label: "上一章",
                          id: "reader.audio.prevChapter", action: onPrevious)
            playButton
            controlButton(symbol: "forward.end.fill", label: "下一章",
                          id: "reader.audio.nextChapter", action: onNext)
            controlButton(symbol: "goforward.15", label: "前进15秒",
                          id: "reader.audio.forward15") { audio.skip(15) }
        }
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

    private var speedRow: some View {
        Menu {
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
        } label: {
            Text(speedText(audio.speed) + " 倍速")
                .appFont(.subheadline)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("倍速")
        .accessibilityIdentifier("reader.audio.speed")
    }

    private func speedText(_ value: Double) -> String {
        if value == value.rounded() { return String(format: "%.1fx", value) }
        return String(format: "%gx", value)
    }
}
