import Foundation

/// 角色性别提示。只在语气/提示语里出现「他」「她」时推断，不保证准确。
enum AloudGender: String, Codable, Equatable, Sendable {
    case male
    case female
}

/// 一段文字属于谁：旁白、未识别说话人的对话，或某个角色。
enum AloudSpeaker: Equatable, Hashable, Sendable {
    case narrator
    case dialogue(gender: AloudGender?)
    case character(name: String, gender: AloudGender?)
}

/// 拆段结果：文本、它在整章里的字符偏移（与 ReaderSearchHit 的口径一致）、说话人。
struct AloudRoleSegment: Equatable, Sendable {
    let text: String
    let offset: Int
    let speaker: AloudSpeaker
}

/// 把正文拆成「旁白 / 引号对话」，并尽量从「林晚晴说道」「张三笑道」这类提示语里
/// 认出说话人。认不出时退回对话声线，不阻断朗读。
///
/// 只做纯文本处理，不依赖 AVFoundation，方便回归测试。
enum AloudRoleParser {
    static func segments(in text: String, baseOffset: Int = 0,
                         knownNames: Set<String> = []) -> [AloudRoleSegment] {
        let chars = Array(text)
        var result: [AloudRoleSegment] = []
        var cursor = 0
        var index = 0

        while index < chars.count {
            guard let pair = quotePair(for: chars[index]),
                  let close = chars[(index + 1)...].firstIndex(of: pair.close) else {
                index += 1
                continue
            }
            appendNarration(chars, from: cursor, to: index, baseOffset: baseOffset, into: &result)
            let body = String(chars[(index + 1)..<close])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty {
                result.append(AloudRoleSegment(
                    text: body,
                    offset: baseOffset + index + 1,
                    speaker: speaker(chars: chars, open: index, close: close,
                                     knownNames: knownNames)))
            }
            index = close + 1
            cursor = index
        }
        appendNarration(chars, from: cursor, to: chars.count, baseOffset: baseOffset, into: &result)
        return result
    }

    // MARK: - 引号

    private struct QuotePair {
        let close: Character
    }

    private static func quotePair(for char: Character) -> QuotePair? {
        switch char {
        case "“": return QuotePair(close: "”")
        case "「": return QuotePair(close: "」")
        case "『": return QuotePair(close: "』")
        default: return nil
        }
    }

    private static func appendNarration(_ chars: [Character], from start: Int, to end: Int,
                                        baseOffset: Int, into result: inout [AloudRoleSegment]) {
        guard start < end else { return }
        let raw = String(chars[start..<end])
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let leading = raw.prefix { $0.isWhitespace }.count
        result.append(AloudRoleSegment(text: trimmed,
                                       offset: baseOffset + start + leading,
                                       speaker: .narrator))
    }

    // MARK: - 说话人

    private struct NameHit {
        let name: String
        let gender: AloudGender?
    }

    private static func speaker(chars: [Character], open: Int, close: Int,
                                knownNames: Set<String>) -> AloudSpeaker {
        let before = clause(before: open, chars: chars)
        if let hit = name(in: before, knownNames: knownNames, atEnd: true) {
            return .character(name: hit.name, gender: hit.gender)
        }
        let limit = min(chars.count, close + 20)
        let after = String(chars[(close + 1)..<limit])
        if let hit = name(in: after, knownNames: knownNames, atEnd: false) {
            return .character(name: hit.name, gender: hit.gender)
        }
        if let gender = pronoun(in: before) ?? pronoun(in: String(after.prefix(8))) {
            return .dialogue(gender: gender)
        }
        return .dialogue(gender: nil)
    }

    /// 取引号前最后一个句子，避免把上一句的人名误当成说话人。
    private static func clause(before index: Int, chars: [Character]) -> String {
        let start = max(0, index - 36)
        var begin = start
        var i = index - 1
        while i >= start {
            if "。！？!?；;\n".contains(chars[i]) {
                begin = i + 1
                break
            }
            i -= 1
        }
        return String(chars[begin..<index])
    }

    private static func name(in text: String, knownNames: Set<String>, atEnd: Bool) -> NameHit? {
        guard !text.isEmpty else { return nil }
        // 已知角色名优先：命中就不再瞎猜。
        var best: (name: String, range: Range<String.Index>)?
        for name in knownNames where name.count >= 2 {
            guard let range = text.range(of: name) else { continue }
            if let current = best {
                let better = atEnd
                    ? range.upperBound > current.range.upperBound
                    : range.lowerBound < current.range.lowerBound
                if better { best = (name, range) }
            } else {
                best = (name, range)
            }
        }
        if let best {
            return NameHit(name: best.name, gender: gender(in: text))
        }

        let pieces = text.split(whereSeparator: { "，,、：:".contains($0) }).map(String.init)
        let ordered = atEnd ? Array(pieces.reversed()) : pieces
        for piece in ordered {
            guard let candidate = candidate(from: piece, leading: !atEnd) else { continue }
            return NameHit(name: candidate, gender: gender(in: text))
        }
        return nil
    }

    /// 从「林晚晴笑了笑，轻声道」这样的小句里剥出名字。
    private static func candidate(from piece: String, leading: Bool) -> String? {
        guard speechVerbs.contains(where: { piece.contains($0) }) else { return nil }
        let chars = Array(piece.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !chars.isEmpty else { return nil }
        let run = leading ? Array(chars.prefix(9)) : Array(chars.suffix(9))
        var value = String(run)
            .trimmingCharacters(in: CharacterSet(charactersIn: "。！？!?，,、；;：: \t"))
        var changed = true
        while changed, !value.isEmpty {
            changed = false
            for token in trailingTokens where value.hasSuffix(token) && value.count > token.count {
                value.removeLast(token.count)
                changed = true
                break
            }
        }
        let chinese = String(value.reversed().prefix { isChinese($0) }.reversed())
        value = chinese
        guard (2...4).contains(value.count), isValidName(value) else { return nil }
        return value
    }

    private static func isValidName(_ value: String) -> Bool {
        guard value.allSatisfy(isChinese) else { return false }
        if nameBlocklist.contains(value) { return false }
        if value.contains(where: { nameBadChars.contains($0) }) { return false }
        return true
    }

    private static func gender(in text: String) -> AloudGender? {
        if text.contains("她") { return .female }
        if text.contains("他") { return .male }
        return nil
    }

    private static func pronoun(in text: String) -> AloudGender? {
        guard !text.isEmpty else { return nil }
        let tail = String(text.suffix(8))
        if tail.contains("她") { return .female }
        if tail.contains("他") { return .male }
        return nil
    }

    private static func isChinese(_ char: Character) -> Bool {
        char.unicodeScalars.allSatisfy { (0x3400...0x9FFF).contains(Int($0.value)) }
    }

    private static let speechVerbs: [String] = [
        "说道", "问道", "答道", "喊道", "叫道", "笑道", "骂道", "哼道",
        "低声道", "沉声道", "冷声道", "轻声道", "开口道", "开口",
        "说", "道", "问", "答", "喊", "叫", "笑", "骂", "哼", "吼", "叹"
    ]

    private static let trailingTokens: [String] = [
        "冷哼一声", "低声道", "沉声道", "冷声道", "轻声道", "开口道",
        "说道", "问道", "答道", "喊道", "叫道", "笑道", "骂道",
        "轻声", "低声", "沉声", "冷声", "大声", "柔声", "淡淡", "缓缓",
        "忽然", "随即", "接着", "继续", "笑着", "冷笑", "苦笑", "皱眉", "点头", "摇头",
        "开口", "说", "道", "问", "答", "喊", "叫", "笑", "骂", "哼", "吼", "叹",
        "地", "的", "着", "了"
    ].sorted { $0.count > $1.count }

    private static let nameBlocklist: Set<String> = [
        "他们", "她们", "我们", "你们", "大家", "众人", "两人", "一人", "有人",
        "对方", "老者", "少年", "少女", "男子", "女子", "此人", "那人", "这人",
        "只听", "只见", "只闻", "此时", "这时", "随后", "然后", "于是", "不过",
        "但是", "所以", "如果", "因为", "只是", "便是", "却是", "忽然", "突然",
        "轻声", "低声", "沉声", "冷声", "大声", "柔声", "小声", "开口",
        "皱眉", "点头", "摇头", "冷笑", "苦笑", "冷哼", "淡淡", "缓缓",
        "笑着", "说完", "听了", "看着", "说道", "问道", "答道", "接着", "继续"
    ]

    private static let nameBadChars = "他她我你您的了着过便就才又却也还都"
}
