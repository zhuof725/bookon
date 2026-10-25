import Foundation
import AVFoundation

/// 有声书的「段落时间轴」：本地分析音频里的停顿，把段落边界对齐到停顿点。
///
/// 番茄这类源的音频是整章合成的一条 mp3，接口不提供逐句时间戳。
/// 折中办法：把整章音频逐段测音量，找出说话间的停顿；再按字数比例算出每段
/// 应该落在哪个时间点，把边界「吸附」到最近的停顿。比纯比例准，但不是逐字对齐。
enum AudioSentenceTimeline {
    private static let storagePrefix = "reader.audio.timeline.v1."
    /// 停顿时长阈值（秒）：太短的换气声不算段落边界。
    private static let minPause: Double = 0.18
    /// 吸附半径：估算时间与停顿相差超过这个值就不吸附。
    private static let snapRadius: Double = 3.0

    // MARK: 缓存

    static func cached(bookUrl: String, chapter: String, count: Int) -> [Double]? {
        guard let data = UserDefaults.standard.data(forKey: key(bookUrl, chapter)),
              let list = try? JSONDecoder().decode([Double].self, from: data),
              list.count == count + 1 else { return nil }
        return list
    }

    static func store(_ boundaries: [Double], bookUrl: String, chapter: String) {
        guard let data = try? JSONEncoder().encode(boundaries) else { return }
        UserDefaults.standard.set(data, forKey: key(bookUrl, chapter))
    }

    static func clear(bookUrl: String, chapter: String) {
        UserDefaults.standard.removeObject(forKey: key(bookUrl, chapter))
    }

    private static func key(_ bookUrl: String, _ chapter: String) -> String {
        let raw = bookUrl + "\u{1F}" + chapter
        let digest = raw.utf8.reduce(UInt64(1469598103934665603)) { hash, byte in
            (hash ^ UInt64(byte)) &* 1099511628211
        }
        return storagePrefix + String(digest, radix: 16)
    }

    // MARK: 构建

    /// 段落边界时间戳（count = paragraphs + 1，首尾是 0 和时长）。
    static func build(url: URL, paragraphs: [String], duration: TimeInterval) async -> [Double]? {
        guard paragraphs.count > 1, duration > 5 else { return nil }
        guard let local = await localFile(for: url) else { return nil }
        // 以文件真实时长为准；和播放器报的时长差太多（多段拼接/换过章）就别用。
        guard let fileDuration = audioDuration(local), fileDuration > 5,
              abs(fileDuration - duration) <= max(5, duration * 0.05) else { return nil }
        guard let pauses = pauseTimes(url: local, duration: fileDuration) else { return nil }

        let totalChars = paragraphs.reduce(0) { $0 + max($1.count, 1) }
        guard totalChars > 0 else { return nil }

        // 吸附窗口跟章节长度走：长章节的估算误差更大。
        let window = max(2.5, min(9.0, fileDuration * 0.07))
        var boundaries: [Double] = [0]
        var cursor = 0
        var last = 0.0
        var searchStart = 0
        for (index, text) in paragraphs.enumerated() {
            cursor += max(text.count, 1)
            if index == paragraphs.count - 1 { break }
            let expected = Double(cursor) / Double(totalChars) * fileDuration
            while searchStart < pauses.count, pauses[searchStart] < last + 0.15 { searchStart += 1 }
            var best: Double?
            var bestDelta = Double.greatestFiniteMagnitude
            var probe = searchStart
            while probe < pauses.count, pauses[probe] <= expected + window {
                let delta = abs(pauses[probe] - expected)
                if delta < bestDelta {
                    bestDelta = delta
                    best = pauses[probe]
                }
                probe += 1
            }
            let chosen = min(max(best ?? expected, last + 0.15), fileDuration)
            boundaries.append(chosen)
            last = chosen
        }
        boundaries.append(fileDuration)
        return boundaries
    }

    private static func audioDuration(_ url: URL) -> TimeInterval? {
        guard let file = try? AVAudioFile(forReading: url), file.processingFormat.sampleRate > 0 else { return nil }
        return Double(file.length) / file.processingFormat.sampleRate
    }

    /// 分析要读本地文件：远端地址先下载（已经缓存过就直接用缓存）。
    private static func localFile(for url: URL) async -> URL? {
        if url.isFileURL { return url }
        if let cached = AudioDiskCache.cachedFile(for: url.absoluteString) { return cached }
        let key = url.absoluteString.utf8.reduce(UInt64(1469598103934665603)) { hash, byte in
            (hash ^ UInt64(byte)) &* 1099511628211
        }
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent("audio-analysis-\(String(key, radix: 16))")
        if FileManager.default.fileExists(atPath: dest.path) { return dest }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (200..<300).contains((response as? HTTPURLResponse)?.statusCode ?? 200),
              !data.isEmpty else { return nil }
        guard (try? data.write(to: dest)) != nil else { return nil }
        return dest
    }

    /// 静音段的中点（秒）。
    private static func pauseTimes(url: URL, duration: TimeInterval) -> [Double]? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let format = file.processingFormat
        let sampleRate = format.sampleRate
        guard sampleRate > 0, file.length > 0 else { return nil }
        let window = AVAudioFrameCount(max(sampleRate * 0.05, 256))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: window) else { return nil }

        var levels: [Float] = []
        levels.reserveCapacity(Int(file.length / AVAudioFramePosition(window)) + 1)
        file.framePosition = 0
        while file.framePosition < file.length {
            do { try file.read(into: buffer, frameCount: window) } catch { break }
            guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else { break }
            let count = Int(buffer.frameLength)
            var sum: Float = 0
            let data = channels[0]
            for i in 0..<count { sum += data[i] * data[i] }
            levels.append((sum / Float(max(count, 1))).squareRoot())
        }
        guard let peak = levels.max(), peak > 0.0005 else { return nil }

        let threshold = max(peak * 0.06, 0.0015)
        let windowSeconds = Double(window) / sampleRate
        var pauses: [Double] = []
        var silenceStart: Int?
        for (index, level) in levels.enumerated() {
            if level < threshold {
                if silenceStart == nil { silenceStart = index }
            } else if let start = silenceStart {
                let length = Double(index - start) * windowSeconds
                if length >= minPause {
                    let mid = (Double(start) + Double(index)) / 2.0 * windowSeconds
                    pauses.append(min(max(mid, 0), duration))
                }
                silenceStart = nil
            }
        }
        if let start = silenceStart {
            let length = Double(levels.count - start) * windowSeconds
            if length >= minPause {
                pauses.append(min((Double(start) + Double(levels.count)) / 2.0 * windowSeconds, duration))
            }
        }
        return pauses
    }
}
