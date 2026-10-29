import Foundation

/// 朗读净化：去掉与正文无关的网址、站点广告、本章完/求票之类的文字。
///
/// 只做保守的通用清理，具体站点的怪格式交给用户的自定义规则。
/// 纯 Foundation，可回归测试。
enum AloudPurifier {
    private static let urlExpression = try? NSRegularExpression(
        pattern: #"(?:https?://|www\.)[A-Za-z0-9\-._~:/?#\[\]@!$&'()*+,;=%]+"#,
        options: [.caseInsensitive])

    /// 括号里的固定尾注/求票。
    private static let noteExpression = try? NSRegularExpression(
        pattern: #"[（(【\[](?:[^）)】\]]{0,24})(?:本章未完|本章完|未完待续|全文完|求收藏|求推荐|求月票|求订阅|推荐票|月票)(?:[^）)】\]]{0,24})[）)】\]]"#)

    /// 句尾的「本章完」之类。
    private static let endingExpression = try? NSRegularExpression(
        pattern: #"(?:本章未完|本章完|未完待续|全文完)[。！？!?]?$"#)

    /// 整行都是广告/站点提示时丢弃。
    private static let adLineExpression = try? NSRegularExpression(
        pattern: #"^(?:本章未完|本章完|未完待续|全文完|求收藏|求推荐|求月票|求订阅|推荐票|月票|章节报错|请记住本站|手机用户请|最新网址|首发域名|笔趣阁|www\.)"#)

    private static let repeatedPunctuation = try? NSRegularExpression(
        pattern: #"([。！？!?，,])\1{1,}"#)

    private static let repeatedSpaces = try? NSRegularExpression(
        pattern: #"[ \t\u3000]{2,}"#)

    static func clean(_ text: String) -> String {
        var value = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        value = replacing(urlExpression, in: value, with: "")
        value = replacing(noteExpression, in: value, with: "")
        value = replacing(endingExpression, in: value, with: "")

        if let adLineExpression {
            let kept = value.components(separatedBy: "\n").filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return true }
                let range = NSRange(location: 0, length: (trimmed as NSString).length)
                let hit = adLineExpression.firstMatch(in: trimmed, range: range) != nil
                return !(hit && trimmed.count <= 60)
            }
            value = kept.joined(separator: "\n")
        }

        value = replacing(repeatedPunctuation, in: value, with: "$1")
        value = replacing(repeatedSpaces, in: value, with: " ")
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func replacing(_ expression: NSRegularExpression?, in text: String,
                                  with template: String) -> String {
        guard let expression else { return text }
        let range = NSRange(location: 0, length: (text as NSString).length)
        return expression.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }
}
