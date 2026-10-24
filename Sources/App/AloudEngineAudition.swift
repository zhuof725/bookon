import AVFoundation
import Combine

/// 引擎试听独立于正文朗读：只播固定示例，不选择引擎、不更新正文进度。
/// 每次请求都有独立标识；取消后的下载/播放器回调不能影响后来的试听。
@MainActor
final class AloudEngineAudition: NSObject, ObservableObject {
    @Published private(set) var engineID: Int64?
    @Published private(set) var isPlaying = false
    @Published private(set) var isSystem = false
    @Published private(set) var errorMessage: String?

    private static let sampleText = "欢迎使用朗读功能。"
    private var requestID: UUID?
    private var downloadTask: Task<Void, Never>?
    private var systemTask: Task<Void, Never>?
    private var systemSynthesizer: AVSpeechSynthesizer?
    private var player: AVAudioPlayer?
    private weak var reader: ReaderAloudController?
    /// 只有试听自己激活的会话才有资格释放；主朗读暂停仍持有自己的会话。
    private var activatedSession = false

    /// 正在试听同一引擎时再次点击即取消；点击其他引擎会取消旧请求再试听。
    func toggle(engine: HTTPTTS, reader: ReaderAloudController) {
        if engineID == engine.id {
            cancel()
            return
        }
        cancel()
        errorMessage = nil
        reader.pause()
        self.reader = reader
        let request = UUID()
        requestID = request
        engineID = engine.id
        let speed = engine.usesServerSpeed ? AloudTTSConfig.httpSpeakSpeed : 10
        downloadTask = Task { @MainActor [weak self] in
            do {
                try Task.checkCancellation()
                // 与正文相同的 fetchAudio：含登录头、Cookie、jsLib 和 loginCheckJs。
                let data = try await AloudAudioFetcher.fetchAudio(
                    engine: engine, text: Self.sampleText, speed: speed)
                try Task.checkCancellation()
                guard let self, self.requestID == request else { return }
                self.downloadTask = nil
                // 用户可能通过锁屏恢复了正文；让正文优先，不叠加试听。
                guard self.reader?.isPlaying != true else { self.cancel(); return }
                try self.play(data)
            } catch {
                guard let self, self.requestID == request else { return }
                let cancelled = Task.isCancelled || error is CancellationError
                self.finish(message: cancelled ? nil : "试听失败：\(error.localizedDescription)")
            }
        }
    }

    func cancel() { finish() }

    func dismissError() { errorMessage = nil }

    /// 试听系统语音；每轮使用独立合成器，旧回调不会结束新试听。
    func toggleSystem(reader: ReaderAloudController) {
        if isSystem { cancel(); return }
        cancel()
        errorMessage = nil
        reader.pause()
        self.reader = reader
        let request = UUID()
        requestID = request
        isSystem = true
        do {
            try activateSessionIfNeeded()
            let synthesizer = AVSpeechSynthesizer()
            systemSynthesizer = synthesizer
            let utterance = AVSpeechUtterance(string: Self.sampleText)
            utterance.voice = AloudVoiceConfig.speechVoice
            utterance.rate = ReaderAloudController.utteranceRate(AloudTTSConfig.speechRate)
            synthesizer.speak(utterance)
            isPlaying = true
            systemTask = Task { @MainActor [weak self, synthesizer] in
                // 留出合成器开始播放的时间；取消后不创建新播放。
                repeat {
                    do { try await Task.sleep(nanoseconds: 150_000_000) }
                    catch { return }
                    guard self?.requestID == request else { return }
                } while synthesizer.isSpeaking
                self?.finish()
            }
        } catch {
            finish(message: "试听失败：\(error.localizedDescription)")
        }
    }

    private func activateSessionIfNeeded() throws {
        guard reader?.isRunning != true else { return }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .spokenAudio, options: [])
        try session.setActive(true)
        activatedSession = true
    }


    private func play(_ data: Data) throws {
        let newPlayer = try AVAudioPlayer(data: data)
        newPlayer.delegate = self
        // delegate 为弱引用；对象本身持续持有 player，直到结束或取消。
        player = newPlayer
        try activateSessionIfNeeded()
        guard newPlayer.prepareToPlay(), newPlayer.play() else {
            throw PlaybackError.cannotStart
        }
        isPlaying = true
    }

    private func finish(message: String? = nil) {
        // 先作废请求，避免被取消的任务或已排队的 delegate 回调覆盖新状态。
        requestID = nil
        downloadTask?.cancel()
        downloadTask = nil
        systemTask?.cancel()
        systemTask = nil
        systemSynthesizer?.stopSpeaking(at: .immediate)
        systemSynthesizer = nil
        isSystem = false
        player?.delegate = nil
        player?.stop()
        player = nil
        engineID = nil
        isPlaying = false
        if activatedSession, reader?.isRunning != true {
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        }
        activatedSession = false
        reader = nil
        if let message { errorMessage = message }
    }

    private enum PlaybackError: LocalizedError {
        case cannotStart
        var errorDescription: String? { "音频无法播放，请检查引擎返回的音频格式" }
    }

    deinit {
        downloadTask?.cancel()
        systemTask?.cancel()
        // AVAudioPlayer 释放时自己会停止；deinit 是 nonisolated，不在这里碰 player。
        // 正常销毁前列表的 onDisappear 会 cancel；不在这里触碰共享音频会话。
    }
}

extension AloudEngineAudition: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self, self.player === player else { return }
            self.finish(message: flag ? nil : "试听失败：音频未能正常播放完毕")
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor [weak self] in
            guard let self, self.player === player else { return }
            self.finish(message: "试听失败：音频解码失败，请检查引擎返回的音频格式")
        }
    }
}
