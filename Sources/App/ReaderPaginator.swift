import UIKit

/// UIKit 分页器：分页和 InlineCommentParagraph 使用相同的 TextKit 属性与附件。
/// Engine/Paginator.swift 继续提供 Foundation 估算分页，供源书回归和无 UIKit 场景使用。
enum ReaderPaginator {
    struct Configuration: Equatable {
        var pageSize: CGSize
        var safeInsets: UIEdgeInsets = .zero
        var fontSize: CGFloat
        /// These two values are physical points at the UIKit boundary. The
        /// ReaderView converts Android's tenth-of-line settings before it
        /// creates this configuration.
        var lineSpacing: CGFloat
        var paragraphSpacing: CGFloat = 8
        var fullJustify: Bool = false
        var zhLayout: Bool = false
        var bottomJustify: Bool = false
        var leftInset: CGFloat = 20
        var rightInset: CGFloat = 20
        var topInset: CGFloat = 16
        var bottomInset: CGFloat = 10
        var chapterTitle: String = ""
        /// PageContentView 底部页码栏及与正文间的固定距离。
        var footerHeight: CGFloat = 16
        var footerGap: CGFloat = 8
        var blockSpacing: CGFloat {
            ReaderTextLayout.paragraphGap(lineSpacing: lineSpacing, paragraphSpacing: paragraphSpacing)
        }
        func spacing(before block: ContentBlock, after previous: ContentBlock?) -> CGFloat {
            guard let previous else { return 0 }
            if case .paragraph = previous, case .paragraph = block { return blockSpacing }
            return max(paragraphSpacing, 0)
        }
        var headerHeight: CGFloat {
            chapterTitle.isEmpty ? 0 : ChapterTitleLayout.height(title: chapterTitle,
                fontSize: fontSize, width: textWidth) + ChapterTitleLayout.bottomSpacing(fontSize: fontSize) + paragraphSpacing
        }

        var textWidth: CGFloat {
            max(pageSize.width - leftInset - rightInset, 1)
        }

        var bodyHeight: CGFloat {
            max(pageSize.height - safeInsets.top - safeInsets.bottom
                - topInset - bottomInset - footerHeight - footerGap, 1)
        }

        var firstPageBodyHeight: CGFloat {
            max(bodyHeight - headerHeight, 1)
        }
    }

    /// 返回的 BookPage.blockHeights 与 PageContentView 的块顺序一一对应。
    /// 入口应在主线程调用，因为 TextKit/UIKit 不支持后台布局。
    static func paginate(_ blocks: [ContentBlock], configuration: Configuration) -> [BookPage] {
        precondition(Thread.isMainThread, "ReaderPaginator must run on the main thread")
        guard !blocks.isEmpty else { return [] }
        let measurer = ReaderTextLayout.Measurer()
        // 与正文渲染共用 TextKit 1 容器/代理，提取真正的行断点。
        let lineView = ReaderTextLayout.makeTextView()
        ReaderTextLayout.configure(lineView)
        let width = configuration.textWidth
        var pages: [BookPage] = []
        var pageBlocks: [ContentBlock] = []
        var pageHeights: [Double] = []
        var pageLineCounts: [Int] = []
        var continuations = Set<Int>()
        var paragraphEnds = Set<Int>()
        var displayParagraphs: [Int: String] = [:]
        var used: CGFloat = 0
        var offset = 0
        var pageStart = 0

        func flush() {
            guard !pageBlocks.isEmpty else { return }
            let lineCount = pageLineCounts.reduce(0, +)
            let capacity = pages.isEmpty ? configuration.firstPageBodyHeight : configuration.bodyHeight
            var justifiedGap: Double?
            var alignsBodyBottom = false
            // Never lower the body's top origin to fake bottom alignment.
            // Only a near-full text page distributes its remaining height:
            // the total spare is less than ONE natural line advance. A fixed
            // per-gap percentage would wrongly reject normal large-font pages.
            // Sparse/one-row pages stay at the top with natural spacing.
            if configuration.bottomJustify,
               lineCount > 1,
               pageBlocks.allSatisfy({ if case .paragraph = $0 { return true }; return false }) {
                let lineHeight = ReaderTextLayout.metrics(fontSize: configuration.fontSize).lineHeight
                let advance = max(lineHeight + configuration.lineSpacing, 1)
                let surplus = capacity - used
                let extra = max(surplus, 0) / CGFloat(lineCount - 1)
                if surplus >= -0.01, surplus < advance {
                    alignsBodyBottom = true
                    if surplus > 0 { justifiedGap = Double(extra) }
                }
            }
            pages.append(BookPage(blocks: pageBlocks, startOffset: pageStart,
                                  continuationIndices: continuations,
                                  blockHeights: pageHeights,
                                  blockLineCounts: pageLineCounts,
                                  paragraphEndIndices: paragraphEnds,
                                  justifiedGap: justifiedGap,
                                  fullJustify: configuration.fullJustify,
                                  zhLayout: configuration.zhLayout,
                                  displayParagraphs: displayParagraphs,
                                  alignsBodyBottom: alignsBodyBottom))
            pageBlocks.removeAll(keepingCapacity: true)
            pageHeights.removeAll(keepingCapacity: true)
            pageLineCounts.removeAll(keepingCapacity: true)
            continuations.removeAll(keepingCapacity: true)
            paragraphEnds.removeAll(keepingCapacity: true)
            displayParagraphs.removeAll(keepingCapacity: true)
            used = 0
            pageStart = offset
        }

        func append(_ block: ContentBlock, height: CGFloat, lineCount: Int = 0,
                    continuation: Bool = false, paragraphEnd: Bool = false) {
            used += configuration.spacing(before: block, after: pageBlocks.last)
            if continuation { continuations.insert(pageBlocks.count) }
            if paragraphEnd { paragraphEnds.insert(pageBlocks.count) }
            pageBlocks.append(block)
            pageHeights.append(Double(height))
            pageLineCounts.append(lineCount)
            used += height
        }

        for block in blocks {
            switch block {
            case .paragraph(let text, let commentCount, let commentURL):
                let rawChars = Array(text)
                let chars = Array(ReaderTextLayout.displayText(for: text))
                assert(rawChars.count == chars.count)
                if chars.isEmpty { continue }
                // Character 索引是阅读位置；TextKit 的字形区间是 UTF-16。
                // 整段一次建表，行尾只在恰好落于 Character 边界时才允许分页。
                var utf16Offsets = [0]
                utf16Offsets.reserveCapacity(chars.count + 1)
                for character in chars {
                    utf16Offsets.append(utf16Offsets[utf16Offsets.count - 1] + String(character).utf16.count)
                }
                var index = 0
                var continuation = false
                var lineEnds: [LineEnd] = []
                var layoutStart = -1
                var layoutIsContinuation = false
                var lineCursor = 0
                while index < chars.count {
                    let capacity = pages.isEmpty ? configuration.firstPageBodyHeight : configuration.bodyHeight
                    let room = capacity - used - configuration.spacing(before: block, after: pageBlocks.last)
                    if room <= 0.5, !pageBlocks.isEmpty {
                        flush()
                        continue
                    }
                    if layoutStart < 0 {
                        layoutStart = index
                        lineEnds = textLineEnds(view: lineView, chars: chars, start: index,
                                                utf16Offsets: utf16Offsets, commentCount: commentCount,
                                                width: width, configuration: configuration,
                                                continuation: continuation)
                        lineCursor = 0
                    }
                    while lineCursor < lineEnds.count && lineEnds[lineCursor].characterEnd <= index {
                        lineCursor += 1
                    }
                    let origin = lineCursor < lineEnds.count ? lineEnds[lineCursor].top : 0
                    var candidate = -1
                    for row in lineCursor..<lineEnds.count {
                        let line = lineEnds[row]
                        guard line.bottom - origin <= room + 0.01 else { break }
                        // 若气泡产生额外一行，文本虽已到末尾，也必须连同气泡一起放下。
                        if line.characterEnd < chars.count || row == lineEnds.count - 1 {
                            candidate = row
                        }
                    }
                    // 用实际渲染的片段复核高度（独立片段的尾行字距可能稍有差异）。
                    var end = candidate >= 0 ? lineEnds[candidate].characterEnd : index
                    var height: CGFloat = 0
                    var lineCount = 0
                    while end > index {
                        let result = measured(measurer: measurer, chars: chars, start: index, count: end - index,
                                               commentCount: end == chars.count ? commentCount : 0,
                                               width: width, fontSize: configuration.fontSize,
                                               lineSpacing: configuration.lineSpacing,
                                               continuation: continuation,
                                               fullJustify: configuration.fullJustify,
                                               zhLayout: configuration.zhLayout,
                                               paragraphEnd: end == chars.count)
                        height = result.height
                        lineCount = result.count
                        if height <= room + 0.01 { break }
                        candidate -= 1
                        while candidate >= lineCursor && lineEnds[candidate].characterEnd >= end {
                            candidate -= 1
                        }
                        end = candidate >= lineCursor ? lineEnds[candidate].characterEnd : index
                    }
                    // legado-E packs complete rows greedily, including a new
                    // paragraph's first row at the bottom of a page.
                    if end == index {
                        if !pageBlocks.isEmpty {
                            flush()
                            continue
                        }
                        // 极窄/极矮页面：宁可留一整行溢出，也不切开一个字形。
                        if lineCursor < lineEnds.count {
                            end = max(index + 1, lineEnds[lineCursor].characterEnd)
                        } else {
                            end = index + 1
                        }
                        let result = measured(measurer: measurer, chars: chars, start: index, count: end - index,
                                              commentCount: end == chars.count ? commentCount : 0,
                                              width: width, fontSize: configuration.fontSize,
                                              lineSpacing: configuration.lineSpacing,
                                              continuation: continuation,
                                              fullJustify: configuration.fullJustify,
                                              zhLayout: configuration.zhLayout,
                                              paragraphEnd: end == chars.count)
                        height = result.height
                        lineCount = result.count
                    }
                    let isLast = end == chars.count
                    let piece = String(rawChars[index..<end])
                    let displayPiece = String(chars[index..<end])
                    if displayPiece != piece { displayParagraphs[pageBlocks.count] = displayPiece }
                    append(.paragraph(text: piece,
                                      commentCount: isLast ? commentCount : 0,
                                      commentURL: isLast ? commentURL : nil),
                           height: height, lineCount: lineCount, continuation: continuation,
                           paragraphEnd: isLast)
                    offset += end - index
                    index = end
                    continuation = true
                    if !isLast {
                        // 首段有首行缩进；首次续段从这里开始重新排一次，无缩进后
                        // 此后的页均从同一份 TextKit 行表取整行，不逐页重排整段。
                        if !layoutIsContinuation {
                            layoutStart = -1
                            layoutIsContinuation = true
                        }
                        flush()
                    }
                }
            default:
                let h = nonTextHeight(block, configuration: configuration)
                let capacity = pages.isEmpty ? configuration.firstPageBodyHeight : configuration.bodyHeight
                if used + h + configuration.spacing(before: block, after: pageBlocks.last) > capacity + 0.01,
                   !pageBlocks.isEmpty {
                    flush()
                }
                append(block, height: h)
            }
        }
        flush()
        // Page membership uses natural row heights; flush only adds bounded
        // display spacing after those immutable complete-row cuts are chosen.
        return pages
    }

    private static func measured(measurer: ReaderTextLayout.Measurer, chars: [Character], start: Int,
                                 count: Int, commentCount: Int, width: CGFloat, fontSize: CGFloat,
                                 lineSpacing: CGFloat, continuation: Bool,
                                 fullJustify: Bool, zhLayout: Bool,
                                 paragraphEnd: Bool) -> (count: Int, height: CGFloat) {
        let text = String(chars[start..<(start + count)])
        return measurer.rows(text: text, count: commentCount, width: width, fontSize: fontSize,
                             lineSpacing: lineSpacing, continuation: continuation,
                             fullJustify: fullJustify, zhLayout: zhLayout,
                             paragraphEnd: paragraphEnd)
    }

    private struct LineEnd {
        let characterEnd: Int
        let top: CGFloat
        let bottom: CGFloat
    }

    /// 一次排出整段（包含尾部气泡），取实际 glyph 行尾而非可塞入的字符前缀。
    /// UTF-16 游标单向扫描 Character 边界，emoji/ZWJ/组合音标不会被拆开。
    /// 有气泡的行只有连附件一起能容纳时才可作为最终片段。
    private static func textLineEnds(view: CommentTextView, chars: [Character], start: Int,
                                     utf16Offsets: [Int], commentCount: Int, width: CGFloat,
                                     configuration: Configuration, continuation: Bool) -> [LineEnd] {
        let text = String(chars[start...])
        view.attributedText = ReaderTextLayout.attributedText(text: text, count: commentCount,
            fontSize: configuration.fontSize, lineSpacing: configuration.lineSpacing,
            color: .black, continuation: continuation, width: width,
            fullJustify: configuration.fullJustify, zhLayout: configuration.zhLayout)
        view.textContainer.widthTracksTextView = false
        view.textContainer.heightTracksTextView = false
        view.textContainer.size = CGSize(width: width, height: .greatestFiniteMagnitude)
        let manager = view.layoutManager
        manager.ensureLayout(for: view.textContainer)
        var result: [LineEnd] = []
        var character = start
        var pendingTop: CGFloat?
        let base = utf16Offsets[start]
        let textEnd = utf16Offsets[chars.count]
        manager.enumerateLineFragments(forGlyphRange: manager.glyphRange(for: view.textContainer)) {
            rect, used, _, glyphs, _ in
            guard glyphs.length > 0 else { return }
            let range = manager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
            let end = min(base + NSMaxRange(range), textEnd)
            if pendingTop == nil { pendingTop = rect.minY }
            while character < chars.count && utf16Offsets[character] < end { character += 1 }
            // 不把字素簇中间的 UTF-16 偏移向上/向下取整成伪造的行尾。
            guard character > start, utf16Offsets[character] == end else { return }
            let style = view.textStorage.attribute(.paragraphStyle, at: range.location,
                effectiveRange: nil) as? NSParagraphStyle
            result.append(LineEnd(characterEnd: character, top: pendingTop ?? rect.minY,
                                  bottom: rect.minY + (style?.minimumLineHeight ?? used.height)))
            pendingTop = nil
        }
        return result
    }

    /// 与 PageContentView 的 SwiftUI 固定 padding/字体相同的非文本块高度。
    static func nonTextHeight(_ block: ContentBlock, configuration: Configuration) -> CGFloat {
        switch block {
        case .image:
            return 120
        case .hotComment:
            return max(configuration.fontSize - 3, 12) + 20
        case .chapterComments:
            return max(configuration.fontSize - 2, 11) + 24
        case .inlineBubble, .paragraph:
            return 0
        }
    }
}
