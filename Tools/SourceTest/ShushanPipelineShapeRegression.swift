import Foundation

/// 诊断 + 回归：正文在「书源替换规则 → 段界还原 → 分块」过程中不能丢段落结构。
/// 用书山 fixture 的真实 replaceRegex 跑一遍三种形态（纯文本／带段评气泡／带段评标签），
/// 打印每一步的换行数，便于在 CI 日志里定位是哪一步把段落并成一段。
/// 打印的正文是本测试自己合成的，不含任何用户内容。
enum ShushanPipelineShapeRegression {
    static func run(_ check: (Bool, String) -> Void) throws {
        let fixture = URL(fileURLWithPath: "Tools/SourceTest/Fixtures/shushan-aggregate-v5.63.json")
        let sources = try JSONDecoder().decode([BookSource].self, from: Data(contentsOf: fixture))
        guard let source = sources.first, let rule = source.ruleContent else {
            check(false, "书山 fixture 与正文规则可读取")
            return
        }

        // 与源内 Android 分支一致：段落用 "\n" 连接；段评是 <img data:image/svg+xml…>。
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\"><text>12</text></svg>"
        let bubble = "<img src=\"data:image/svg+xml;base64,\(Data(svg.utf8).base64EncodedString())\""
            + " onClick=\"java.startBrowser('https://example.invalid/c')\">"
        let comment = "<comment count=\"7\" onClick=\"java.startBrowser('https://example.invalid/c')\"/>"
        let first = "第一段内容。"
        let second = "第二段内容。"
        let third = "第三段内容。"
        let plain = [first, second, third].joined(separator: "\n")
        let withBubble = [first, second + bubble, third].joined(separator: "\n")
        let withComment = [first, second + comment, third].joined(separator: "\n")

        func newlines(_ s: String) -> Int { s.components(separatedBy: "\n").count - 1 }
        func paragraphs(_ s: String) -> Int {
            ContentBlocks.parse(s).compactMap { block -> String? in
                if case .paragraph(let text, _, _) = block { return text }
                return nil
            }.count
        }

        let rr = rule.replaceRegex ?? ""
        let ruleText = rr.hasPrefix("##") ? rr : "##" + rr
        let context = RuleContext(source: source)
        func apply(_ text: String) -> String {
            AnalyzeRule(content: text, baseUrl: "https://example.invalid/chapter",
                        jsLib: source.jsLib, context: context)
                .getReplacementString(ruleText, from: text)
        }
        func report(_ label: String, _ input: String, _ output: String) {
            print("PIPELINE \(label) inNewlines=\(newlines(input)) inParagraphs=\(paragraphs(input))"
                + " outNewlines=\(newlines(output)) outParagraphs=\(paragraphs(output))"
                + " htmlWrapped=\(output.hasPrefix("<html")) length=\(output.count)")
            print("PIPELINE \(label) out=\(output.replacingOccurrences(of: "\n", with: "⏎"))")
        }

        report("plain", plain, apply(plain))
        report("bubble", withBubble, apply(withBubble))
        report("comment", withComment, apply(withComment))

        check(newlines(apply(plain)) == newlines(plain),
              "纯文本正文替换后换行不变（\(newlines(plain)) -> \(newlines(apply(plain)))）")
        check(paragraphs(apply(plain)) == 3, "纯文本正文替换后仍是三段（实际 \(paragraphs(apply(plain)))）")
        check(newlines(apply(withBubble)) == newlines(withBubble),
              "带段评气泡的正文替换后换行不变（\(newlines(withBubble)) -> \(newlines(apply(withBubble)))）")
        check(paragraphs(apply(withBubble)) == 3, "带段评气泡的正文仍是三段（实际 \(paragraphs(apply(withBubble)))）")
        check(paragraphs(apply(withComment)) == 3, "带段评标签的正文仍是三段（实际 \(paragraphs(apply(withComment)))）")

        let normalized = WebBook.normalizeParagraphBoundaries(apply(withBubble))
        print("PIPELINE normalized newlines=\(newlines(normalized)) paragraphs=\(paragraphs(normalized))")
        check(paragraphs(normalized) == 3, "书山形态正文还原后仍是三段（实际 \(paragraphs(normalized))）")
    }
}
