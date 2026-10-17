import AVFoundation

/// 在线朗读音频播放器。
///
/// 设计参考 Yuedu-Reader 的 `TTSChunkAudioPlayer`：
/// - 整个收听会话**复用一个音频图**（engine/node/timePitch 只建一次，段间只换源
///   文件）。每段重建 AVAudioEngine 会在锁屏/后台时产生音频会话断点，iOS 可能
///   在下一个图启动前把播放挂起——这是听书在后台最容易翻车的地方。
/// - 变速用 `AVAudioUnitTimePitch`（`AVAudioPlayer.rate` 只覆盖 0.5–2.0，超过
///   会静默失效），保持音调，支持到 5 倍。
/// - 路由/配置变化（锁屏、切换耳机）后自动重连音频图并从原位置继续。
@MainActor
final class AloudAudioPlayer {
    /// 当前段自然播完的回调；stop()/load() 会让被取代的旧回调失效。
    var onFinish: (() -> Void)?

    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let timePitch = AVAudioUnitTimePitch()

    private var file: AVAudioFile?
    /// 当前排程的起始帧；seek/重新排程从这里开始。
    private var scheduleStartFrame: AVAudioFramePosition = 0
    private var totalFrames: AVAudioFramePosition = 0
    private var sampleRate: Double = 0
    private var connectedSampleRate: Double = 0
    private var connectedChannelCount: AVAudioChannelCount = 0

    /// 令被 stop()/load() 取代的排程完成回调失效。
    private var scheduleToken = UUID()
    private var hasStarted = false
    /// pause 时记录位置；engine.pause() 之后 lastRenderTime 会变 nil。
    private var pausedTime: TimeInterval?

    /// 源文件时长（不受 rate 影响，与 AVAudioPlayer.duration 口径一致）。
    private(set) var duration: TimeInterval = 0
    private(set) var isPlaying = false
    var hasAudio: Bool { file != nil && totalFrames > 0 }

    /// 当前倍速下的实际墙钟时长。
    var effectiveDuration: TimeInterval { duration / Double(max(rate, 0.01)) }

    /// 播放速率（变速不变调）；范围取 AVAudioUnitTimePitch 的 1/32–32。
    var rate: Float {
        get { timePitch.rate }
        set { timePitch.rate = Self.clampRate(newValue) }
    }

    /// 源文件内的播放位置（秒）。
    var currentTime: TimeInterval {
        if let pausedTime { return pausedTime }
        guard hasStarted,
              let nodeTime = node.lastRenderTime,
              let playerTime = node.playerTime(forNodeTime: nodeTime) else {
            return frameToSeconds(scheduleStartFrame)
        }
        return min(max(frameToSeconds(scheduleStartFrame + playerTime.sampleTime), 0), duration)
    }

    init() {
        engine.attach(node)
        engine.attach(timePitch)
        NotificationCenter.default.addObserver(self, selector: #selector(handleConfigurationChange),
                                               name: .AVAudioEngineConfigurationChange, object: engine)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        engine.stop()
    }

    /// 换源文件，保留音频图；准备从头播放。
    func load(url: URL) throws {
        stop()
        let newFile = try AVAudioFile(forReading: url)
        file = newFile
        sampleRate = newFile.processingFormat.sampleRate
        totalFrames = newFile.length
        duration = sampleRate > 0 ? Double(totalFrames) / sampleRate : 0
        connectGraph(for: newFile.processingFormat, force: true)
        scheduleStartFrame = 0
        pausedTime = nil
        hasStarted = false
    }

    @discardableResult
    func play() -> Bool {
        guard let file, totalFrames > 0, scheduleStartFrame < totalFrames else { return false }
        do {
            if !engine.isRunning { try engine.start() }
        } catch {
            return false
        }
        if !hasStarted { scheduleFromCurrentStartFrame(file: file) }
        node.play()
        pausedTime = nil
        hasStarted = true
        isPlaying = true
        return true
    }

    /// 播放中实时变速（音调不变，不用重新合成/重新加载）。
    func setRate(_ value: Float) { rate = value }

    func pause() {
        guard isPlaying else { return }
        pausedTime = currentTime
        node.pause()
        engine.pause()
        isPlaying = false
    }

    func stop() {
        scheduleToken = UUID()
        node.stop()
        engine.stop()
        pausedTime = nil
        hasStarted = false
        isPlaying = false
        scheduleStartFrame = 0
    }

    // MARK: - 内部

    /// 从当前位置重新排程并播放（配置变化恢复用）。
    private func restart(at time: TimeInterval) {
        guard hasAudio else { return }
        let wasPlaying = isPlaying
        scheduleToken = UUID()
        node.stop()
        engine.stop()
        pausedTime = nil
        hasStarted = false
        isPlaying = false
        scheduleStartFrame = secondsToFrame(min(max(time, 0), duration))
        if wasPlaying { _ = play() }
    }

    private func scheduleFromCurrentStartFrame(file: AVAudioFile) {
        let remaining = totalFrames - scheduleStartFrame
        guard remaining > 0 else { return }
        let token = scheduleToken
        node.scheduleSegment(file, startingFrame: scheduleStartFrame,
                             frameCount: AVAudioFrameCount(remaining), at: nil,
                             completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, token == self.scheduleToken, self.isPlaying else { return }
                self.isPlaying = false
                self.onFinish?()
            }
        }
    }

    private func connectGraph(for format: AVAudioFormat, force: Bool = false) {
        let channels = format.channelCount
        guard force || connectedSampleRate != format.sampleRate || connectedChannelCount != channels else { return }
        engine.disconnectNodeOutput(node)
        engine.disconnectNodeOutput(timePitch)
        engine.connect(node, to: timePitch, format: format)
        engine.connect(timePitch, to: engine.mainMixerNode, format: format)
        connectedSampleRate = format.sampleRate
        connectedChannelCount = channels
    }

    /// 路由变化（锁屏、拔插耳机、切换输出）会让正在跑的图失效：重连后原位继续。
    @objc nonisolated private func handleConfigurationChange(_ notification: Notification) {
        Task { @MainActor [weak self] in
            guard let self, self.isPlaying, let file = self.file else { return }
            let resumeAt = self.currentTime
            self.connectGraph(for: file.processingFormat, force: true)
            self.restart(at: resumeAt)
        }
    }

    private func frameToSeconds(_ frame: AVAudioFramePosition) -> TimeInterval {
        sampleRate > 0 ? Double(frame) / sampleRate : 0
    }

    private func secondsToFrame(_ seconds: TimeInterval) -> AVAudioFramePosition {
        sampleRate > 0 ? AVAudioFramePosition(seconds * sampleRate) : 0
    }

    private static func clampRate(_ value: Float) -> Float {
        min(max(value, 1.0 / 32.0), 32.0)
    }
}
