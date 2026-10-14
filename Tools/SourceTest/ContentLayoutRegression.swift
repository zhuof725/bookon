import Foundation

/// 验证我们这一侧的正文管线不会丢失段落结构：
/// 纯文本（\n 分段）→ ContentBlocks.parse → 每段独立且带两格缩进。
enum ContentLayoutRegression {
    static func run(_ check: (Bool, String) -> Void) {
        let raw = "　　第一段第一行。\n　　第二段内容。第二段继续。\n　　第三段。"
        let blocks = ContentBlocks.parse(raw)
        let paragraphs = blocks.compactMap { block -> String? in
            if case .paragraph(let text, _, _) = block { return text }
            return nil
        }
        check(paragraphs.count == 3, "换行分段保留为三个段落（实际 \(paragraphs.count)）")
        check(paragraphs.first == "第一段第一行。", "段落文本去除原有缩进")
        check(paragraphs.dropFirst().allSatisfy { !$0.isEmpty }, "段间不产生空段落")
        let plain = ContentBlocks.plainText(blocks)
        check(plain.components(separatedBy: "\n").count == 3
              && plain.contains("\u{3000}\u{3000}第二段内容。"),
              "纯文本还原保留分段与两格缩进")

        // rs-native 包裹（书山 iOS 分支的历史形态）：每行独立成段但不得产生空段。
        let wrapped = "<div rs-native>第一行。</div>\n<div rs-native>第二行。</div>"
        let wrappedBlocks = ContentBlocks.parse(wrapped)
        let wrappedText = wrappedBlocks.compactMap { block -> String? in
            if case .paragraph(let text, _, _) = block { return text }
            return nil
        }
        check(wrappedText == ["第一行。", "第二行。"], "rs-native div 不残留标签也不产生空段")
    }
}
