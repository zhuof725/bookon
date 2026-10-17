import Foundation

/// 朗读进度高亮：播报偏移落在正文的哪一段、段内已读到多少字符。
/// 只统计文字段落（与 ReaderMenuText.paragraphs / 朗读单元的偏移口径一致）。
struct AloudHighlight: Equatable {
    /// 章节号：跨章加载期间旧章的高亮不会画到新章上。
    var chapter: Int = 0
    /// 分页模式下所在页（滚动模式恒为 0）。
    var page: Int = 0
    /// 段落在块数组里的下标：分页模式为页内块下标，滚动模式为章节块下标。
    var block: Int = 0
    /// 段落（或页内续段块）的章节字符偏移。
    var start: Int = 0
    /// 段内已朗读的字符数（高亮前缀长度，0 = 不画）。
    var length: Int = 0
}

/// 纯查找逻辑，便于离线回归；渲染层只负责把 length 转成属性字符串背景。
enum AloudHighlightLocator {
    struct Bounds {
        let block: Int
        let start: Int
        let length: Int
    }

    /// 章节块 → 文字段落边界。图片/卡片/章末评论不占朗读偏移。
    static func paragraphBounds(_ blocks: [ContentBlock]) -> [Bounds] {
        var start = 0
        var list: [Bounds] = []
        for (index, block) in blocks.enumerated() {
            guard case .paragraph(let text, _, _) = block else { continue }
            list.append(Bounds(block: index, start: start, length: text.count))
            start += text.count
        }
        return list
    }

    /// 滚动模式：字符偏移 → 所在段落与已读前缀。
    static func locate(offset: Int, chapter: Int, blocks: [ContentBlock]) -> AloudHighlight? {
        guard offset >= 0 else { return nil }
        for item in paragraphBounds(blocks) where item.length > 0 {
            if offset >= item.start, offset < item.start + item.length {
                return AloudHighlight(chapter: chapter, page: 0, block: item.block,
                                      start: item.start, length: offset - item.start + 1)
            }
        }
        return nil
    }

    /// 分页模式：字符偏移 → 所在页与页内块（长段落跨页时只高亮本页那一段）。
    static func locateInPages(offset: Int, chapter: Int, pages: [BookPage],
                              blocks: [ContentBlock]) -> AloudHighlight? {
        let bounds = paragraphBounds(blocks)
        guard !bounds.isEmpty, !pages.isEmpty, offset >= 0 else { return nil }
        // 用页的 startOffset 作为全局锚点；页内页面块只累计自身的文字长度。
        // 这样长段落跨页时，续页的第一页字符不会被前页的空块错位。
        for (pageIndex, page) in pages.enumerated() {
            var start = page.startOffset
            for (blockIndex, block) in page.blocks.enumerated() {
                guard case .paragraph(let text, _, _) = block else { continue }
                let length = text.count
                guard length > 0 else { continue }
                if offset >= start, offset < start + length {
                    return AloudHighlight(chapter: chapter, page: pageIndex, block: blockIndex,
                                          start: start, length: offset - start + 1)
                }
                start += length
            }
        }
        return nil
    }
}
