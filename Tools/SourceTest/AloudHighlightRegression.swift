import Foundation

/// Character offsets must follow spoken paragraphs, never rendered attachments or text search.
enum AloudHighlightRegression {
    private static func paragraph(_ text: String) -> ContentBlock {
        .paragraph(text: text, commentCount: 7, commentURL: "https://example.invalid/comments")
    }

    static func run(_ check: (Bool, String) -> Void) {
        let image = ContentBlock.image(src: "https://example.invalid/image", clickURL: nil, rawSrc: nil)
        let ignored: [ContentBlock] = [paragraph(""), image,
            .inlineBubble(src: "bubble", count: 9, clickURL: nil, rawSrc: nil),
            .hotComment(label: "热评", text: "不应朗读的评论", clickURL: nil),
            .chapterComments(title: "本章说", count: "123", items: [], clickURL: nil)]
        let blocks = ignored + [paragraph("甲乙"), paragraph("")] + [image, paragraph("丙丁")]
        let chapter = 7
        for (offset, block, start, length) in [(0, 5, 0, 2), (1, 5, 0, 2),
                                              (2, 8, 2, 2), (3, 8, 2, 2)] {
            check(AloudHighlightLocator.locate(offset: offset, chapter: chapter, blocks: blocks)
                == AloudHighlight(chapter: chapter, page: 0, block: block, start: start, length: length),
                "朗读高亮：空段、图片、气泡和评论不计偏移 \(offset)")
        }
        check(AloudHighlightLocator.locate(offset: 0, chapter: chapter, blocks: []) == nil,
              "朗读高亮：空章节返回 nil")
        check(AloudHighlightLocator.locate(offset: 0, chapter: chapter, blocks: ignored) == nil,
              "朗读高亮：仅空段和不可朗读块返回 nil")
        for offset in [Int.min, -1, 4, 5, Int.max] {
            check(AloudHighlightLocator.locate(offset: offset, chapter: chapter, blocks: blocks) == nil,
                  "朗读高亮：负数、结束位置及越界返回 nil \(offset)")
        }

        let repeated = [paragraph("相同段落"), image, paragraph(""), paragraph("相同段落")]
        for (offset, block, start, length) in [(0, 0, 0, 4), (3, 0, 0, 4),
                                              (4, 3, 4, 4), (7, 3, 4, 4)] {
            check(AloudHighlightLocator.locate(offset: offset, chapter: chapter, blocks: repeated)
                == AloudHighlight(chapter: chapter, page: 0, block: block, start: start, length: length),
                "朗读高亮：重复段落按字符偏移定位 \(offset)")
        }

        let unicode = "甲👨‍👩‍👧‍👦e\u{301}🇨🇳👍🏽乙"
        check(unicode.count == 6 && unicode.utf16.count > unicode.count,
              "朗读高亮：Unicode 样例包含组合字符、旗帜及肤色序列")
        let unicodeBlocks = [paragraph(unicode), paragraph("尾")]
        for offset in 0..<6 {
            check(AloudHighlightLocator.locate(offset: offset, chapter: chapter, blocks: unicodeBlocks)
                == AloudHighlight(chapter: chapter, page: 0, block: 0, start: 0, length: 6),
                "朗读高亮：emoji 与组合字符同样整段高亮 \(offset)")
        }
        check(AloudHighlightLocator.locate(offset: 6, chapter: chapter, blocks: unicodeBlocks)
            == AloudHighlight(chapter: chapter, page: 0, block: 1, start: 6, length: 1),
            "朗读高亮：Unicode 段后的起点不是 UTF-16 长度")

        // Include an empty leading page and an image-only page sharing the following start.
        // The second fragment ends with the repeated paragraph from the next source block.
        let pagedSource = [paragraph(""), image, paragraph("甲👨‍👩‍👧‍👦e\u{301}乙丙丁"),
                           paragraph("丙丁"), paragraph("")]
        let pages = [BookPage(blocks: [paragraph("")], startOffset: 0),
            BookPage(blocks: [paragraph(""), image, paragraph("甲👨‍👩‍👧‍👦e\u{301}")], startOffset: 0),
            BookPage(blocks: [image], startOffset: 3),
            BookPage(blocks: [image, paragraph(""), paragraph("乙丙丁"), paragraph("丙丁")],
                     startOffset: 3, continuationIndices: [2])]
        for (offset, page, block, start, length) in [
            (0, 1, 2, 0, 3), (1, 1, 2, 0, 3), (2, 1, 2, 0, 3),
            (3, 3, 2, 3, 3), (5, 3, 2, 3, 3), (6, 3, 3, 6, 2), (7, 3, 3, 6, 2)
        ] {
            check(AloudHighlightLocator.locateInPages(offset: offset, chapter: chapter,
                pages: pages, blocks: pagedSource)
                == AloudHighlight(chapter: chapter, page: page, block: block, start: start, length: length),
                "朗读高亮：跨页续段按页起点及页内块定位 \(offset)")
        }
        for offset in [Int.min, -1, 8, 9, Int.max] {
            check(AloudHighlightLocator.locateInPages(offset: offset, chapter: chapter,
                pages: pages, blocks: pagedSource) == nil,
                "朗读高亮：分页负数、结束位置及越界返回 nil \(offset)")
        }
        check(AloudHighlightLocator.locateInPages(offset: 0, chapter: chapter,
            pages: [], blocks: pagedSource) == nil, "朗读高亮：尚无分页返回 nil")
        check(AloudHighlightLocator.locateInPages(offset: 3, chapter: chapter,
            pages: Array(pages.prefix(2)), blocks: pagedSource) == nil,
            "朗读高亮：有效章节偏移不在已提供页面中时返回 nil")
        check(AloudHighlightLocator.locateInPages(offset: 0, chapter: chapter,
            pages: pages, blocks: []) == nil, "朗读高亮：陈旧页面不能命中空章节")
    }
}
