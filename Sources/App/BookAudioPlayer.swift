import SwiftUI
import AVFoundation
import MediaPlayer
import UIKit

/// 音频书（如喜马拉雅源）章节播放。
///
/// 一个收听会话只用一个 AVQueuePlayer：当前章播放时就把下一章预载入队，
/// AVFoundation 在后台预载（preroll），章末连播、点「下一章」都近乎无感；
/// 章节间不复建播放器、不重设音频会话、不闪封面页，整场停止时才释放。
/// 方案参照 Yuedu-Reader 的 AudiobookPlayer / AudiobookResourcePreloader。
@MainActor
final class BookAudioPlayer: NSObject, ObservableObject {
    /// 预载候选：下一章的播放信息。
    struct NextChapter {
        let index: Int
        let url: String
        let title: String
    }

    /// 当前章节的音频地址；nil 表示不在音频播放状态，阅读器回到文字排版。
    @Published private(set) var chapterURL: URL?
    @Published private(set) var chapterTitle = ""
    /// 当前播放章号（目录下标）；-1 表示未在播放。
    @Published private(set) var chapterIndex = -1
    /// 已预载入队、等待接管的下一章章号；nil 表示没有预载。
    @Published private(set) var queuedChapterIndex: Int?
    @Published private(set) var isPlaying = false
    @Published private(set) var isBuffering = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var message: String?
    @Published var speed: Double = BookAudioPlayer.loadSpeed() {
        didSet { BookAudioPlayer.saveSpeed(speed); applyRate() }
    }

    /// 一章自然播完、且没有可接管的预载章时回调（末章或预载失败）；用于自动进章兜底。
    var onFinish: (() -> Void)?
    /// 锁屏「下一章 / 上一章」回调，由阅读器接到章节跳转。
    var onRemoteNext: (() -> Void)?
    var onRemotePrevious: (() -> Void)?
    /// 预载章被播放队列自动接管时的回调（携带新章号）；阅读器据此对齐进度与目录高亮。
    var onChapterChanged: ((Int) -> Void)?
    /// 下一章预载来源：给出当前章之后可播的下一章；nil 表示没有下一章（末章等）。
    var nextChapterProvider: ((Int) -> NextChapter?)?

    /// 队列中的一章：章节信息 + 播放条目 + 观察者。
    private final class Entry {
        let chapterIndex: Int
        let url: URL
        let title: String
        let item: AVPlayerItem
        var statusObservation: NSKeyValueObservation?
        var notifications: [NSObjectProtocol] = []

        init(chapterIndex: Int, url: URL, title: String, item: AVPlayerItem) {
            self.chapterIndex = chapterIndex
            self.url = url
            self.title = title
            self.item = item
        }

        /// 解除全部回调与观察，避免条目释放后继续收到事件。
        func detach() {
            statusObservation?.invalidate()
            statusObservation = nil
            notifications.forEach { NotificationCenter.default.removeObserver($0) }
            notifications = []
        }
    }

    private var player: AVQueuePlayer?
    private var currentEntry: Entry?
    private var queuedEntry: Entry?
    private var album = ""
    private var timeObserver: Any?
    private var playerObservations: [NSKeyValueObservation] = []
    private var systemObservers: [NSObjectProtocol] = []
    private var messageTask: Task<Void, Never>?
    private var resumeAfterInterruption = false
    private var remoteRegistered = false
    private var sessionActive = false
    /// 章节切换间隙的后台任务：从开始加载到真正出声为止，避免锁屏/后台时被挂起。
    private var transitionTask: UIBackgroundTaskIdentifier = .invalid

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
        currentEntry?.detach()
        queuedEntry?.detach()
        systemObservers.forEach { NotificationCenter.default.removeObserver($0) }
        let cc = MPRemoteCommandCenter.shared()
        cc.playCommand.removeTarget(nil)
        cc.pauseCommand.removeTarget(nil)
        cc.togglePlayPauseCommand.removeTarget(nil)
        cc.nextTrackCommand.removeTarget(nil)
        cc.previousTrackCommand.removeTarget(nil)
    }

    // MARK: 播放控制

    /// 播放指定章节。同一收听会话内复用播放器与音频会话，不重建、不断音。
    func play(chapterIndex index: Int, url rawURL: String, title: String, album: String) {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme?.lowercased().hasPrefix("http") == true else {
            pushMessage("音频地址无效")
            return
        }
        let queuePlayer = ensurePlayer()
        activateSessionIfNeeded()
        discardQueue()
        queuePlayer.pause()

        let item = AVPlayerItem(url: url)
        // 变速时保持音调（音频书倍速的关键设置）。
        item.audioTimePitchAlgorithm = .spectral
        let entry = Entry(chapterIndex: index, url: url, title: title, item: item)
        currentEntry = entry
        observeCurrent(entry)
        queuePlayer.insert(item, after: nil)

        self.album = album
        chapterIndex = index
        chapterURL = url
        chapterTitle = title
        currentTime = 0
        duration = 0
        message = nil
        isBuffering = true
        isPlaying = true
        updateRemoteCommands(enabled: true)
        beginTransition()
        // 音频书起播优先：不等「缓冲到不易卡顿」的默认策略，拿到数据就开始。
        queuePlayer.playImmediately(atRate: Float(speed))
        updateNowPlaying()
    }

    func toggle() {
        if isPlaying { pause() } else { resume() }
    }

    func pause() {
        guard isPlaying else { return }
        catchUpWithQueue()
        player?.pause()
        isPlaying = false
        endTransition()
        updateNowPlaying()
    }

    func resume() {
        guard !isPlaying, let queuePlayer = player, let entry = currentEntry,
              chapterURL != nil else { return }
        // 失败过的条目不能原地续播：按同一地址重建条目重试。
        if entry.item.status == .failed {
            play(chapterIndex: entry.chapterIndex, url: entry.url.absoluteString,
                 title: entry.title, album: album)
            return
        }
        isPlaying = true
        beginTransition()
        queuePlayer.playImmediately(atRate: Float(speed))
        updateNowPlaying()
    }

    /// 整场停止：释放播放器、预载与音频会话（离开阅读器/末章播完/切回文字章节）。
    func stop() {
        endTransition()
        currentEntry?.detach()
        queuedEntry?.detach()
        currentEntry = nil
        queuedEntry = nil
        queuedChapterIndex = nil
        if let queuePlayer = player {
            queuePlayer.pause()
            if let timeObserver { queuePlayer.removeTimeObserver(timeObserver) }
            queuePlayer.removeAllItems()
        }
        timeObserver = nil
        playerObservations.forEach { $0.invalidate() }
        playerObservations = []
        player = nil
        chapterURL = nil
        chapterIndex = -1
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
        sessionActive = false
    }

    // MARK: 预载与自动接管

    /// 若目标章已预载入队，交给播放队列立即接管并返回 true；否则返回 false，调用方回退重新加载。
    @discardableResult
    func advanceToQueued(chapterIndex index: Int) -> Bool {
        catchUpWithQueue()
        guard let queued = queuedEntry, queued.chapterIndex == index,
              queued.item.status != .failed, let queuePlayer = player else { return false }
        queuePlayer.advanceToNextItem()
        adopt(queued)
        return true
    }

    /// 队列在章末自行接管预载章（currentItem 变化）时对齐状态；
    /// 同时兜住任何在 KVO 到达前就作用于「当前章」的操作。
    private func catchUpWithQueue() {
        if let queued = queuedEntry, player?.currentItem === queued.item {
            adopt(queued)
        }
    }

    /// 预载章成为当前章：更新状态、通知阅读器、随后再预载新的下一章。
    private func adopt(_ entry: Entry) {
        guard queuedEntry === entry else { return }
        queuedEntry = nil
        queuedChapterIndex = nil
        player?.actionAtItemEnd = .pause
        currentEntry?.detach()
        currentEntry = entry

        chapterIndex = entry.chapterIndex
        chapterURL = entry.url
        chapterTitle = entry.title
        currentTime = 0
        let total = entry.item.duration.seconds
        duration = total.isFinite && total > 0 ? total : 0
        isBuffering = entry.item.status != .readyToPlay
        message = nil
        isPlaying = true
        beginTransition()
        player?.rate = Float(speed)
        updateNowPlaying()
        // 先把阅读器状态对齐（章号/进度/统计），再预载再下一章。
        onChapterChanged?(entry.chapterIndex)
        enqueueNextIfReady()
    }

    /// 当前章就绪后，把下一章提前放进播放队列：AVFoundation 会在当前章播放期间预载它。
    private func enqueueNextIfReady() {
        guard let queuePlayer = player, let current = currentEntry,
              current.item.status != .failed,
              let provider = nextChapterProvider,
              let next = provider(current.chapterIndex),
              next.index != current.chapterIndex else { return }
        if let queued = queuedEntry {
            guard queued.chapterIndex != next.index else { return }
            dequeueNext()
        }
        let trimmed = next.url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme?.lowercased().hasPrefix("http") == true,
              url != current.url else { return }
        let item = AVPlayerItem(url: url)
        item.audioTimePitchAlgorithm = .spectral
        guard queuePlayer.canInsert(item, after: current.item) else { return }
        let entry = Entry(chapterIndex: next.index, url: url, title: next.title, item: item)
        entry.statusObservation = item.observe(\.status, options: [.new]) { [weak self, weak entry] item, _ in
            let status = item.status
            Task { @MainActor [weak self, weak entry] in
                guard let self, let entry else { return }
                self.queuedItemStatusChanged(entry, status: status)
            }
        }
        queuePlayer.insert(item, after: current.item)
        queuePlayer.actionAtItemEnd = .advance
        queuedEntry = entry
        queuedChapterIndex = next.index
    }

    /// 移除预载的下一章（保留当前章播放）。
    private func dequeueNext() {
        guard let queued = queuedEntry else { return }
        queuedEntry = nil
        queuedChapterIndex = nil
        queued.detach()
        player?.remove(queued.item)
        player?.actionAtItemEnd = .pause
    }

    /// 清空当前章与预载章（重建会话时用）。
    private func discardQueue() {
        currentEntry?.detach()
        queuedEntry?.detach()
        currentEntry = nil
        queuedEntry = nil
        queuedChapterIndex = nil
        player?.removeAllItems()
        player?.actionAtItemEnd = .pause
    }

    // MARK: 跳转

    func seek(toSeconds seconds: TimeInterval) {
        guard chapterURL != nil else { return }
        catchUpWithQueue()
        guard let queuePlayer = player, currentEntry != nil else { return }
        let clamped = min(max(seconds, 0), max(duration, 0))
        currentTime = clamped
        queuePlayer.seek(to: CMTime(seconds: clamped, preferredTimescale: 600),
                         toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func skip(_ delta: TimeInterval) { seek(toSeconds: currentTime + delta) }

    // MARK: 变速

    private func applyRate() {
        guard let player, isPlaying else { return }
        player.rate = Float(speed)
        updateNowPlaying()
    }

    // MARK: 播放器与观察者

    private func ensurePlayer() -> AVQueuePlayer {
        if let player { return player }
        let queuePlayer = AVQueuePlayer()
        queuePlayer.actionAtItemEnd = .pause
        queuePlayer.automaticallyWaitsToMinimizeStalling = false
        player = queuePlayer

        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = queuePlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in self?.sampleTime(time) }
        }
        // 章末由队列自行接管预载章：currentItem 变化即对齐状态。
        playerObservations.append(queuePlayer.observe(\.currentItem, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in self?.catchUpWithQueue() }
        })
        // 真正出声后结束切换的后台任务；缓冲状态也按它更新。
        playerObservations.append(queuePlayer.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            let status = player.timeControlStatus
            Task { @MainActor [weak self] in self?.timeControlStatusChanged(status) }
        })
        return queuePlayer
    }

    private func observeCurrent(_ entry: Entry) {
        let center = NotificationCenter.default
        entry.notifications.append(center.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                                                      object: entry.item, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.currentItemDidPlayToEnd(entry) }
        })
        entry.notifications.append(center.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime,
                                                      object: entry.item, queue: .main) { [weak self] notice in
            let failure = notice.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
            Task { @MainActor [weak self] in self?.currentItemFailed(entry, error: failure) }
        })
        entry.statusObservation = entry.item.observe(\.status, options: [.new]) { [weak self, weak entry] item, _ in
            let status = item.status
            Task { @MainActor [weak self, weak entry] in
                guard let self, let entry else { return }
                self.currentItemStatusChanged(entry, status: status)
            }
        }
    }

    private func currentItemStatusChanged(_ entry: Entry, status: AVPlayerItem.Status) {
        guard entry === currentEntry else { return }
        switch status {
        case .readyToPlay:
            isBuffering = false
            let total = entry.item.duration.seconds
            if total.isFinite, total > 0 { duration = total }
            // 当前章就绪后才预载下一章，避免与起播争抢带宽。
            enqueueNextIfReady()
        case .failed:
            currentItemFailed(entry, error: entry.item.error)
        default:
            break
        }
    }

    private func queuedItemStatusChanged(_ entry: Entry, status: AVPlayerItem.Status) {
        guard entry === queuedEntry else { return }
        if status == .failed {
            // 预载失败：静默移除，章末走 onFinish 兜底重新加载。
            dequeueNext()
        }
    }

    private func currentItemDidPlayToEnd(_ entry: Entry) {
        guard entry === currentEntry else { return }
        // 队列已备好下一章：等 currentItem 变化由 adopt 接管，不打断连播。
        if let queued = queuedEntry,
           player?.items().contains(where: { $0 === queued.item }) == true {
            return
        }
        isPlaying = false
        updateNowPlaying()
        onFinish?()
    }

    private func currentItemFailed(_ entry: Entry, error failure: Error?) {
        guard entry === currentEntry else { return }
        isPlaying = false
        isBuffering = false
        endTransition()
        pushMessage("音频播放失败，点播放重试")
        updateNowPlaying()
    }

    private func sampleTime(_ time: CMTime) {
        guard let queuePlayer = player, let entry = currentEntry,
              queuePlayer.currentItem === entry.item else { return }
        let seconds = time.seconds
        if seconds.isFinite { currentTime = max(seconds, 0) }
        let total = entry.item.duration.seconds
        if total.isFinite, total > 0 { duration = total }
    }

    private func timeControlStatusChanged(_ status: AVPlayer.TimeControlStatus) {
        switch status {
        case .playing:
            isBuffering = false
            endTransition()
        case .waitingToPlayAtSpecifiedRate:
            if isPlaying { isBuffering = true }
        case .paused:
            isBuffering = false
        @unknown default:
            break
        }
    }

    // MARK: 章节切换的后台时间

    /// 从开始加载到音频真正出声之间没有音频输出，后台音频 App 会被挂起；
    /// 用后台任务撑过这段间隙（参照 Yuedu-Reader 的 transitionBackgroundTask）。
    private func beginTransition() {
        guard transitionTask == .invalid else { return }
        transitionTask = UIApplication.shared.beginBackgroundTask(withName: "音频章节切换") { [weak self] in
            Task { @MainActor [weak self] in self?.endTransition() }
        }
    }

    private func endTransition() {
        guard transitionTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(transitionTask)
        transitionTask = .invalid
    }

    // MARK: 系统观察

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

    /// 整场会话只激活一次；切章不经过这里，避免每章重设音频会话。
    private func activateSessionIfNeeded() {
        guard !sessionActive else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [])
        try? session.setActive(true)
        sessionActive = true
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
