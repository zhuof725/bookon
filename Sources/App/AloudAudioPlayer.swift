import AVFoundation

/// 在线朗读音频播放器：AVAudioEngine + AVAudioUnitTimePitch，
/// 变速时保持音调不变（AVAudioPlayer.rate 会变调，所以不用它）。
/// 引擎 URL 不含 `{{speakSpeed}}` 时，倍速由这里在本机实现；
/// 含 `{{speakSpeed}}` 的引擎由服务端合成，播放速率固定 1.0。
@MainActor
final class AloudAudioPlayer {
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let timePitch = AVAudioUnitTimePitch()
    private var finishHandler: (() -> Void)?
    private var loaded = false
    private var pausedTime: TimeInterval = 0

    private(set) var duration: TimeInterval = 0
    private(set) var isPlaying = false
    private(set) var rate: Float = 1

    var hasAudio: Bool { loaded }

    init() {
        engine.attach(node)
        engine.attach(timePitch)
    }

    deinit {
        engine.stop()
    }

    /// 开始播放一个音频文件；onFinish 在整段真实播完后回调。
    func play(url: URL, rate: Float, onFinish: @escaping () -> Void) throws {
        stop()
        let file = try AVAudioFile(forReading: url)
        duration = Double(file.length) / file.processingFormat.sampleRate
        finishHandler = onFinish
        loaded = true
        pausedTime = 0
        self.rate = rate
        timePitch.rate = rate
        // 按文件格式接线：TTS 音频采样率可能不同，直连硬件格式会报错。
        engine.disconnectNodeOutput(node)
        engine.connect(node, to: timePitch, format: file.processingFormat)
        engine.connect(timePitch, to: engine.mainMixerNode, format: nil)
        node.scheduleFile(file, at: nil, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.loaded else { return }
                self.isPlaying = false
                self.finishHandler?()
            }
        }
        if !engine.isRunning { try engine.start() }
        node.play()
        isPlaying = true
    }

    /// 变速立即生效（正在播放的段落实时变；不用重新合成）。
    func setRate(_ value: Float) {
        rate = value
        timePitch.rate = value
    }

    func pause() {
        if isPlaying { pausedTime = currentTime }
        node.pause()
        isPlaying = false
    }

    func resumePlayback() {
        guard loaded else { return }
        if !engine.isRunning { try? engine.start() }
        node.play()
        isPlaying = true
    }

    func stop() {
        node.stop()
        isPlaying = false
        loaded = false
        finishHandler = nil
        duration = 0
        pausedTime = 0
        timePitch.rate = 1
        rate = 1
    }

    /// 当前播放位置（音频源文件的秒数，与 AVAudioPlayer.currentTime 口径一致）。
    var currentTime: TimeInterval {
        guard isPlaying,
              let nodeTime = node.lastRenderTime,
              let playerTime = node.playerTime(forNodeTime: nodeTime),
              playerTime.sampleRate > 0 else { return pausedTime }
        return max(Double(playerTime.sampleTime) / playerTime.sampleRate, 0)
    }
}
