import Foundation

/// LRC 字幕解析：书源的 `ruleContent.subContent` 会输出标准 LRC
/// （`[mm:ss.xx]文本`），比本地「按停顿估算」的段落边界精确得多。
///
/// 用途：把 LRC 的每行时间戳映射成播放界面的「段落边界」数组
/// （`count + 1` 个元素，首尾是 0 与总时长），与 `AudioSentenceTimeline` 同构，
/// 谁先拿到就用谁——书源给了字幕就不必再下载整章音频做停顿检测。
enum LyricTimeline {
    /// 一行字幕：时间戳 + 文本。
    struct Line: Equatable {
        var time: TimeInterval
        var text: String
    }

    /// 解析 LRC 文本。时间戳支持 `[mm:ss]`、`[mm:ss.xx]`、`[mm:ss.xxx]`，
    /// 一行带多个时间戳（`[00:01][00:05]词`）会展开成多行；元信息标签（`[ar:]` 等）忽略。
    static func parse(_ raw: String) -> [Line] {
        guard !raw.isEmpty else { return [] }
        // 有的书源用字面量 \n 而不是真换行，统一拆开。
        let text = raw.replacingOccurrences(of: "\\n", with: "\n")
        var lines: [Line] = []
        for rawLine in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let line = String(rawLine).trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("[") else { continue }
            var times: [TimeInterval] = []
            var rest = Substring(line)
            // 前导的连续时间戳标签全部吃掉。
            while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
                let tag = rest[rest.index(after: rest.startIndex)..<close]
                if let t = parseTimestamp(String(tag)) { times.append(t) }
                rest = rest[rest.index(after: close)...]
            }
            guard !times.isEmpty else { continue }
            let content = String(rest).trimmingCharacters(in: .whitespaces)
            // 纯时间戳行（空文本）跳过：没有词可高亮。
            guard !content.isEmpty else { continue }
            for t in times { lines.append(Line(time: t, text: content)) }
        }
        return lines.sorted { $0.time < $1.time }
    }

    /// `mm:ss` / `mm:ss.xx` / `hh:mm:ss.xx` → 秒。解析失败返回 nil。
    private static func parseTimestamp(_ tag: String) -> TimeInterval? {
        let parts = tag.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3 else { return nil }
        // 最后一段带小数。
        guard let last = parts.last,
              let seconds = Double(last.replacingOccurrences(of: ",", with: ".")),
              seconds >= 0, seconds < 60 else { return nil }
        var total = seconds
        if parts.count == 2 {
            guard let minutes = Double(parts[0]), minutes >= 0 else { return nil }
            total += minutes * 60
        } else {
            guard let hours = Double(parts[0]), hours >= 0,
                  let minutes = Double(parts[1]), minutes >= 0, minutes < 60 else { return nil }
            total += hours * 3600 + minutes * 60
        }
        return total
    }

    /// 把字幕对齐到正文段落，产出 `count + 1` 个边界时间。
    ///
    /// 字幕的句子和正文段落不是一一对应（字幕更碎），所以按「段落文本在字幕里
    /// 依次出现的位置」找每个段落的起点；找不到就按时间比例退回。
    /// 返回 nil 表示字幕和段落完全对不上，交给原来的停顿估算。
    static func boundaries(lines: [Line], paragraphs: [String], duration: TimeInterval) -> [Double]? {
        guard lines.count >= 2, !paragraphs.isEmpty, duration > 0 else { return nil }
        var bounds: [Double] = []
        var cursor = 0
        for paragraph in paragraphs {
            // 段落开头的若干个字，用来在字幕里定位这一段的起点。
            let probe = String(paragraph.prefix(12))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            var found: Double?
            if probe.count >= 2 {
                for index in cursor..<lines.count {
                    let lineText = lines[index].text
                    if lineText.contains(probe) || probe.contains(lineText) {
                        found = lines[index].time
                        cursor = index
                        break
                    }
                }
            }
            bounds.append(found ?? .nan)
        }
        // 一个都没匹配上：字幕和正文没关系，别用。
        let matched = bounds.filter { !$0.isNaN }
        guard matched.count >= max(2, paragraphs.count / 3) else { return nil }
        // 没定位到的段落按前后锚点线性插值。
        var result: [Double] = []
        var lastKnown: Double = 0
        for (index, value) in bounds.enumerated() {
            if value.isNaN {
                // 找后面最近的一个锚点做插值目标。
                var next: Double?
                for j in (index + 1)..<bounds.count where !bounds[j].isNaN {
                    next = bounds[j]
                    break
                }
                let target = next ?? duration
                let span = max(1, target - lastKnown)
                // 简单均分：这一段落在上个锚点和下个锚点之间。
                let remaining = Double(bounds.count - index)
                let step = span / max(remaining, 1)
                result.append(min(lastKnown + step, target))
            } else {
                result.append(value)
                lastKnown = value
            }
        }
        // 首尾补齐 + 单调化（字幕偶尔乱序）。
        result.insert(0, at: 0)
        result.append(duration)
        for i in 1..<result.count where result[i] < result[i - 1] {
            result[i] = result[i - 1]
        }
        // 边界数必须正好等于段落数 + 1。
        if result.count > paragraphs.count + 1 { result = Array(result.prefix(paragraphs.count + 1)) }
        while result.count < paragraphs.count + 1 { result.append(duration) }
        return result
    }
}
