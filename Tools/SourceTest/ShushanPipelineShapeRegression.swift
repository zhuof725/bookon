import Foundation

/// 诊断 + 回归：正文在「书源替换规则 → 段界还原 → 分块」过程中不能丢段落结构。
/// 用书山 fixture 的真实 replaceRegex 跑一遍，并打印每一步的换行数，
/// 便于在 CI 日志里定位是哪一步把段落合并成一段（日志不含用户正文）。
enum ShushanPipelineShapeRegression {
    static func run(_ check: (Bool, String) -> Void) throws {
        let fixture = URL(fileURLWithPath: "Tools/SourceTest/Fixtures/shushan-aggregate-v5.63.json")
        let sources = try JSONDecoder().decode([BookSource].self, from: Data(contentsOf: fixture))
        guard let source = sources.first, let rule = source.ruleContent else {
            check(false, "书山 fixture 与正文规则可读取")
            return
        }
        check(true, "书山 fixture 与正文规则可读取")

        // 与源内 Android 分支一致：段落用 "\n" 连接，段评气泡是 <img data:image/svg+xml…>。
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\"><text>12</text></svg>"
        let bubble = "<img src=\"data:image/svg+xml;base64,\(Data(svg.utf8).base64EncodedString())\""
            + " onClick=\"java.startBrowser('https://example.invalid/c')\">"
        let first = "第一段内容。"
        let second = "第二段内容。" + bubble
        let third = "第三段内容。"
        let raw = [first, second, third].joined(separator: "\n")
        let plain = [first, "第二段内容。", third].joined(separator: "\n")

        func newlines(_ s: String) -> Int { s.components(separatedBy: "\n").count - 1 }
        func paragraphs(_ s: String) -> Int {
            ContentBlocks.parse(s).compactMap { block -> String? in
                if case .paragraph(let text, _, _) = block { return text }
                return nil
            }.count
        }

        print("PIPELINE raw newlines=\(newlines(raw)) paragraphs=\(paragraphs(raw))")
        if let rr = rule.replaceRegex, !rr.isEmpty {
            let context = RuleContext(source: source)
            let ruleText = rr.hasPrefix("##") ? rr : "##" + rr
            let replaced = AnalyzeRule(content: raw, baseUrl: "https://example.invalid/chapter",
                                       jsLib: source.jsLib, context: context).getString(ruleText, from: raw)
            print("PIPELINE afterReplaceRegex newlines=\(newlines(replaced)) length=\(replaced.count)"
                + " htmlWrapped=\(replaced.hasPrefix("<html")) paragraphs=\(paragraphs(replaced))")
            check(newlines(replaced) == newlines(raw),
                  "带段评标签的正文替换后换行不变（\(newlines(raw)) -> \(newlines(replaced))）")

            let plainReplaced = AnalyzeRule(content: plain, baseUrl: "https://example.invalid/chapter",
                                            jsLib: source.jsLib, context: context).getString(ruleText, from: plain)
            print("PIPELINE plainAfterReplaceRegex newlines=\(newlines(plainReplaced))"
                + " htmlWrapped=\(plainReplaced.hasPrefix("<html"))")
            check(newlines(plainReplaced) == newlines(plain),
                  "纯文本正文替换后换行不变（\(newlines(plain)) -> \(newlines(plainReplaced))）")
        }

        let normalized = WebBook.normalizeParagraphBoundaries(raw)
        print("PIPELINE normalized newlines=\(newlines(normalized)) paragraphs=\(paragraphs(normalized))")
        check(paragraphs(normalized) == 3, "书山形态正文解析为三段（实际 \(paragraphs(normalized))）")
    }
}
