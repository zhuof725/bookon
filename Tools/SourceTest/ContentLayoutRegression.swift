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

        // 段落边界不能因书源而异：有的源把段界只写成 U+3000（整段无换行）。
        // 归一化后仍要得到与普通书源一致的逐段排版。
        let blob = "林七夜做了个梦。　梦中他回到半年前。　“嗷！”　林七夜醒了。"
        let blobNormalized = WebBook.normalizeParagraphBoundaries(blob)
        let blobParagraphs = ContentBlocks.parse(blobNormalized).compactMap { block -> String? in
            if case .paragraph(let text, _, _) = block { return text }
            return nil
        }
        check(blobParagraphs.count == 4, "无换行正文还原为四段（实际 \(blobParagraphs.count)）")
        check(blobParagraphs.first == "林七夜做了个梦。" && blobParagraphs.last == "林七夜醒了。",
              "还原后段落文本与缩进一起正确")
        let blobPlain = ContentBlocks.plainText(ContentBlocks.parse(blobNormalized))
        check(blobPlain.components(separatedBy: "\n").count == 4
              && blobPlain.components(separatedBy: "\n").allSatisfy { $0.hasPrefix("\u{3000}\u{3000}") },
              "还原后的纯文本每段都带两格缩进")

        // 分页拼接的正文（页与页之间是换行）：逐行判断，不因整篇含换行而放弃还原。
        let paged = "第一页第一段。　第一页第二段。　第一页第三段。\n第二页只有一段。"
        check(WebBook.normalizeParagraphBoundaries(paged) == "第一页第一段。\n第一页第二段。\n第一页第三段。\n第二页只有一段。",
              "多页正文逐行还原段界")

        // 常见书源的正常分段、句中空格、单处段界、含 CR 的行都不动。
        let normalText = "第一段。\n第二段内容，句中的　空格保留。"
        check(WebBook.normalizeParagraphBoundaries(normalText) == normalText, "正常分段正文完全不变")
        let singleBoundary = "只有一句。　后面没有第二处段界。"
        check(WebBook.normalizeParagraphBoundaries(singleBoundary) == singleBoundary, "单处段界不拆（阈值两处）")
        let carriageReturn = "第一句。　第二句。\r\n第三句。　第四句。"
        check(WebBook.normalizeParagraphBoundaries(carriageReturn) == carriageReturn, "含 CR 的行保持原样")
        let trailing = "第一句。　第二句。　第三句。　"
        check(WebBook.normalizeParagraphBoundaries(trailing) == "第一句。\n第二句。\n第三句。　",
              "行尾全角空格不是段界，不产生空段")
        check(WebBook.normalizeParagraphBoundaries("没有任何全角空格的正文。") == "没有任何全角空格的正文。",
              "没有 U+3000 的正文快速返回")
    }
}
