import AVFoundation

/// AVAudioSession 的 setCategory/setActive 是同步调用，在部分场景（其他 App 占用音频、
/// 来电、模拟器）会阻塞明显时长，放在主线程会卡住界面——音频书停止/起播都触发它。
/// 这里把这类阻塞调用挪到一条串行队列：串行保证「先激活后释放」不会乱序，
/// 主线程只保留遥控注册、状态标记等必须在主线程做的事。
/// （与 Yuedu-Reader 的 AudioSessionActivator 同方案。）
enum AudioSessionActivator {
    private static let queue = DispatchQueue(label: "io.legado.audio.session", qos: .userInitiated)

    /// 配置分类并激活（fire-and-forget，调用方不等待结果）。
    static func activate(category: AVAudioSession.Category,
                         mode: AVAudioSession.Mode = .default,
                         options: AVAudioSession.CategoryOptions = []) {
        queue.async {
            let session = AVAudioSession.sharedInstance()
            try? session.setCategory(category, mode: mode, options: options)
            try? session.setActive(true)
        }
    }

    /// 只切换激活状态（不改分类），释放音频会话时用。
    static func setActive(_ active: Bool, options: AVAudioSession.SetActiveOptions = []) {
        queue.async {
            try? AVAudioSession.sharedInstance().setActive(active, options: options)
        }
    }
}
