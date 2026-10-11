import SwiftUI
import UIKit

/// Production paginator and TextKit row audit, triggered on the main thread by UI test.
struct ReaderPageFlowHarnessView: View {
    @State private var report = "pending"

    var body: some View {
        VStack {
            Button("检查真实行边界分页") { report = ReaderPageFlowAudit.inspect() }
                .accessibilityIdentifier("inspect-reader-page-flow")
            Text(report).font(.system(size: 6)).lineLimit(1)
                .accessibilityIdentifier("reader-page-flow-report")
        }
    }
}

private enum ReaderPageFlowAudit {
    private static let commentURL = "https://example.test/comment"
    private static let long = "他说：\"这个👨‍👩‍👧‍👦章节的书页应当完整地显示一整行，不得从字符中间截断。"
        + String(repeating: "他们沿着长街走去，读到最后一行时仍然能够看到全文🌙🇨🇳👍🏽与标点。", count: 32)
        + "我们到了。\""
    private static let short = "收尾段落仍在原文里。"
    private static let mixed = String(repeating:
        "Café e\u{301} 👩🏽‍💻 extraordinary pagination preserves complete words, 🇨🇳 flags and ligatures. ", count: 18)

    private static func textCount(_ page: BookPage) -> Int {
        page.blocks.reduce(0) { total, block in
            if case .paragraph(let text, _, _) = block { return total + text.count }
            return total
        }
    }

    private static func rowEnds(_ text: String, count: Int, fontSize: CGFloat,
                                lineSpacing: CGFloat, width: CGFloat, continuation: Bool) -> Set<Int> {
        let view = ReaderTextLayout.makeTextView()
        ReaderTextLayout.configure(view)
        view.attributedText = ReaderTextLayout.attributedText(text: text, count: count,
            fontSize: fontSize, lineSpacing: lineSpacing, color: .black,
            continuation: continuation, width: width)
        view.textContainer.widthTracksTextView = false
        view.textContainer.heightTracksTextView = false
        view.textContainer.size = CGSize(width: width, height: .greatestFiniteMagnitude)
        let manager = view.layoutManager
        manager.ensureLayout(for: view.textContainer)
        var ends = Set<Int>()
        manager.enumerateLineFragments(forGlyphRange: manager.glyphRange(for: view.textContainer)) {
            _, _, _, glyphs, _ in
            guard glyphs.length > 0 else { return }
            let range = manager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
            ends.insert(min(NSMaxRange(range), text.utf16.count))
        }
        return ends
    }

    private static func naturalRowSteps(_ text: String, count: Int, fontSize: CGFloat,
                                         lineSpacing: CGFloat, width: CGFloat, continuation: Bool) -> Bool {
        let view = ReaderTextLayout.makeTextView()
        ReaderTextLayout.configure(view)
        view.render(text: text, count: count, fontSize: fontSize, lineSpacing: lineSpacing,
                    color: .black, continuation: continuation)
        _ = ReaderTextLayout.height(of: view, width: width)
        let manager = view.layoutManager
        manager.ensureLayout(for: view.textContainer)
        let expected = ReaderTextLayout.metrics(fontSize: fontSize, width: width).lineHeight + lineSpacing
        var previous: CGFloat?
        var ok = true
        manager.enumerateLineFragments(forGlyphRange: manager.glyphRange(for: view.textContainer)) {
            rect, _, _, glyphs, _ in
            guard glyphs.length > 0 else { return }
            if let previous { ok = ok && abs(rect.minY - previous - expected) < 0.5 }
            previous = rect.minY
        }
        return ok
    }

    private static func bubbleSharesLastCharacter(_ text: String, fontSize: CGFloat,
                                                  width: CGFloat, continuation: Bool) -> Bool {
        let view = ReaderTextLayout.makeTextView()
        ReaderTextLayout.configure(view)
        view.render(text: text, count: 42, fontSize: fontSize, lineSpacing: 8,
                    color: .black, continuation: continuation)
        _ = ReaderTextLayout.height(of: view, width: width)
        guard !text.isEmpty else { return false }
        let manager = view.layoutManager
        manager.ensureLayout(for: view.textContainer)
        let lastText = manager.glyphIndexForCharacter(at: text.utf16.count - 1)
        let attachment = manager.glyphIndexForCharacter(at: view.textStorage.length - 1)
        var finalRow = NSRange()
        _ = manager.lineFragmentRect(forGlyphAt: attachment, effectiveRange: &finalRow)
        return NSLocationInRange(lastText, finalRow)
    }

    static func inspect() -> String {
        var sourceOK = true, boundaryOK = true, offsetsOK = true
        var heightsOK = true, commentOK = true, titleOK = true, quoteOK = true
        var continuations = 0, splits = 0, cases = 0
        var cuts: [[String: Any]] = []
        let original = Array(long)
        let display = Array(ReaderTextLayout.displayText(for: long))
        let widths: [CGFloat] = [240, 315]
        let fonts: [CGFloat] = [19, 26]
        for width in widths {
            for font in fonts {
                cases += 1
                let config = ReaderPaginator.Configuration(pageSize: CGSize(width: width + 40, height: 420),
                    safeInsets: UIEdgeInsets(top: 12, left: 0, bottom: 14, right: 0),
                    fontSize: font, lineSpacing: 8, paragraphSpacing: 10,
                    chapterTitle: "第一章 一个有章标题的阅读分页")
                let source: [ContentBlock] = [
                    .paragraph(text: long, commentCount: 42, commentURL: commentURL),
                    .paragraph(text: short, commentCount: 0, commentURL: nil)
                ]
                let pages = ReaderPaginator.paginate(source, configuration: config)
                let withoutTitle = ReaderPaginator.paginate(source, configuration: {
                    var copy = config
                    copy.chapterTitle = ""
                    return copy
                }())
                titleOK = titleOK && config.firstPageBodyHeight < config.bodyHeight
                    && pages.count > 1 && !pages[0].blocks.isEmpty
                    && pages[0].startOffset == 0
                    && textCount(pages[0]) < textCount(withoutTitle[0])
                let measurer = ReaderTextLayout.Measurer()
                var consumed = 0
                var assembled = ""
                var nextPageStart = 0
                var bubbleCount = 0
                for (pageIndex, page) in pages.enumerated() {
                    offsetsOK = offsetsOK && page.startOffset == nextPageStart
                    heightsOK = heightsOK && page.justifiedGap == nil
                        && page.blockHeights.count == page.blocks.count
                    var used: CGFloat = 0
                    var previous: ContentBlock?
                    for (blockIndex, block) in page.blocks.enumerated() {
                        used += config.spacing(before: block, after: previous)
                        previous = block
                        used += CGFloat(page.blockHeights[blockIndex])
                        guard case .paragraph(let text, let count, let url) = block else {
                            sourceOK = false
                            continue
                        }
                        let actualHeight = measurer.height(text: page.displayParagraphs[blockIndex] ?? text,
                            count: count, width: config.textWidth, fontSize: font,
                            lineSpacing: config.lineSpacing,
                            continuation: page.continuationIndices.contains(blockIndex))
                        heightsOK = heightsOK && abs(actualHeight - CGFloat(page.blockHeights[blockIndex])) < 0.5
                            && naturalRowSteps(page.displayParagraphs[blockIndex] ?? text,
                                count: count, fontSize: font, lineSpacing: config.lineSpacing,
                                width: config.textWidth,
                                continuation: page.continuationIndices.contains(blockIndex))
                        assembled += text
                        if consumed < original.count {
                            let size = text.count
                            if consumed + size > original.count { sourceOK = false; continue }
                            let expected = String(original[consumed..<(consumed + size)])
                            let displayPiece = String(display[consumed..<(consumed + size)])
                            quoteOK = quoteOK && text == expected
                                && (page.displayParagraphs[blockIndex] ?? text) == displayPiece
                            let continued = consumed > 0
                            if continued { continuations += 1 }
                            offsetsOK = offsetsOK && page.continuationIndices.contains(blockIndex) == continued
                            if consumed + size < original.count {
                                splits += 1
                                let tail = String(display[consumed...])
                                let nativeEnds = rowEnds(tail, count: 42, fontSize: font,
                                    lineSpacing: config.lineSpacing, width: config.textWidth,
                                    continuation: continued)
                                boundaryOK = boundaryOK && nativeEnds.contains(displayPiece.utf16.count)
                                if pageIndex < 2 {
                                    cuts.append(["width": Double(width), "font": Double(font),
                                        "page": pageIndex, "startCharacter": consumed,
                                        "endCharacter": consumed + size,
                                        "pieceUTF16": displayPiece.utf16.count,
                                        "nativeRowUTF16Ends": nativeEnds.filter {
                                            $0 <= displayPiece.utf16.count + 40
                                        }.sorted()])
                                }
                            }
                            let final = consumed + size == original.count
                            if count > 0 {
                                bubbleCount += 1
                                commentOK = commentOK && bubbleSharesLastCharacter(displayPiece,
                                    fontSize: font, width: config.textWidth, continuation: continued)
                            }
                            commentOK = commentOK && (count == (final ? 42 : 0))
                                && url == (final ? commentURL : nil)
                            consumed += size
                        } else {
                            sourceOK = sourceOK && text == short
                            commentOK = commentOK && count == 0 && url == nil
                        }
                    }
                    if pageIndex == 0 {
                        heightsOK = heightsOK && used <= config.firstPageBodyHeight + 0.5
                    } else {
                        heightsOK = heightsOK && used <= config.bodyHeight + 0.5
                    }
                    nextPageStart = assembled.count
                }
                sourceOK = sourceOK && assembled == long + short && consumed == original.count
                commentOK = commentOK && bubbleCount == 1
                offsetsOK = offsetsOK && nextPageStart == (long + short).count

                let mixedPages = ReaderPaginator.paginate([
                    .paragraph(text: mixed, commentCount: 0, commentURL: nil)
                ], configuration: config)
                var mixedSource = ""
                var mixedOffset = 0
                for page in mixedPages {
                    offsetsOK = offsetsOK && page.startOffset == mixedOffset
                    for (blockIndex, block) in page.blocks.enumerated() {
                        guard case .paragraph(let text, let count, _) = block else {
                            sourceOK = false
                            continue
                        }
                        if mixedOffset + text.count < mixed.count {
                            let tail = String(mixed.dropFirst(mixedOffset))
                            boundaryOK = boundaryOK && rowEnds(tail, count: 0, fontSize: font,
                                lineSpacing: config.lineSpacing, width: config.textWidth,
                                continuation: mixedOffset > 0).contains(text.utf16.count)
                            splits += 1
                        }
                        sourceOK = sourceOK && count == 0
                        offsetsOK = offsetsOK && page.continuationIndices.contains(blockIndex) == (mixedOffset > 0)
                        mixedSource += text
                        mixedOffset += text.count
                    }
                }
                sourceOK = sourceOK && mixedSource == mixed && mixedPages.count > 1
            }
        }
        // Source 23 screenshot used to leave only “手提箱弹开，露出了里面”
        // on the previous page. A paragraph's first line must move together with
        // its following line when another paragraph already occupies that page.
        let reported: [ContentBlock] = [
            .paragraph(text: "远处的井盖上。", commentCount: 21, commentURL: nil),
            .paragraph(text: "臭味，越来越浓。", commentCount: 54, commentURL: nil),
            .paragraph(text: "赵空城的手紧紧的攥着手提箱的把手，他深吸一口气，微弯下腰，将手提箱放在了地上。", commentCount: 34, commentURL: nil),
            .paragraph(text: "他很清楚这个臭味代表着什么。", commentCount: 42, commentURL: nil),
            .paragraph(text: "\"报告，守望者赵空城，在老住宅区发现鬼面王……\"他打开耳麦，声音十分平静。", commentCount: 99, commentURL: nil),
            .paragraph(text: "边说话，他便按下了手提箱上的按钮。", commentCount: 50, commentURL: nil),
            .paragraph(text: "啪——！", commentCount: 7, commentURL: nil),
            .paragraph(text: "手提箱弹开，露出了里面整齐而又崭新的三块告示牌。", commentCount: 36, commentURL: nil),
            .paragraph(text: "赵空城将三块告示牌扛起", commentCount: 0, commentURL: nil)
        ]
        let reportedPages = ReaderPaginator.paginate(reported, configuration:
            ReaderPaginator.Configuration(pageSize: CGSize(width: 402, height: 874),
                fontSize: 26, lineSpacing: 8, paragraphSpacing: 8,
                leftInset: 20, rightInset: 20, topInset: 70, bottomInset: 30))
        let relevant = "手提箱弹开，露出了里面整齐而又崭新的三块告示牌。"
        var pageOrphans = 0, reportedRebuilt = "", orphanEligible = 0
        for page in reportedPages {
            for (position, block) in page.blocks.enumerated() {
                guard case let .paragraph(text, _, _) = block else { continue }
                reportedRebuilt += text
                guard position > 0, !page.continuationIndices.contains(position),
                      relevant.hasPrefix(text), text.count < relevant.count else { continue }
                // Only a new paragraph whose *first fragment* is split across
                // pages can be orphaned. Earlier complete short paragraphs are fine.
                orphanEligible += 1
                let rows = rowEnds(ReaderTextLayout.displayText(for: text), count: 0,
                    fontSize: 26, lineSpacing: 8, width: 362, continuation: false)
                if rows.count == 1 { pageOrphans += 1 }
            }
        }
        let originalReported = reported.compactMap { block -> String? in
            if case let .paragraph(text, _, _) = block { return text }; return nil
        }.joined()
        let reportedSourceOK = reportedRebuilt == originalReported
        var orphanCases = 0, orphanMovedOK = true, orphanSourceOK = true
        var orphanHeightsOK = true, orphanCommentsOK = true
        for (font, width) in [(CGFloat(19), CGFloat(240)), (26, 362), (32, 315)] {
            let lead = "上一段结束。"
            let next = String(repeating: "手提箱弹开，露出了里面整齐而又崭新的三块告示牌。", count: 8)
            let measure = ReaderTextLayout.Measurer()
            let lineHeight = ReaderTextLayout.metrics(fontSize: font).lineHeight
            let leadHeight = measure.height(text: lead, count: 0, width: width, fontSize: font, lineSpacing: 8)
            var cfg = ReaderPaginator.Configuration(pageSize: CGSize(width: width + 40, height: 500),
                fontSize: font, lineSpacing: 8, paragraphSpacing: 8)
            // Existing complete paragraph + paragraph boundary + exactly ONE new row.
            cfg.pageSize.height = cfg.topInset + cfg.bottomInset + cfg.footerHeight + cfg.footerGap
                + leadHeight + cfg.blockSpacing + lineHeight + 0.25
            let fixture: [ContentBlock] = [.paragraph(text: lead, commentCount: 0, commentURL: nil),
                .paragraph(text: next, commentCount: 36, commentURL: commentURL)]
            let output = ReaderPaginator.paginate(fixture, configuration: cfg)
            orphanCases += 1
            orphanMovedOK = orphanMovedOK && output.count > 1 && output[0].blocks.count == 1
            if output.count > 1, let first = output[1].blocks.first,
               case let .paragraph(fragment, _, _) = first {
                let n = measure.rows(text: fragment, count: 0, width: width, fontSize: font,
                    lineSpacing: 8, continuation: false).count
                orphanMovedOK = orphanMovedOK && next.hasPrefix(fragment) && n >= 2
                    && !output[1].continuationIndices.contains(0)
            } else { orphanMovedOK = false }
            var rebuilt = "", bubbles = 0
            for page in output {
                orphanSourceOK = orphanSourceOK && page.startOffset == rebuilt.count
                var height: CGFloat = 0, previous: ContentBlock?
                for (blockIndex, block) in page.blocks.enumerated() {
                    height += cfg.spacing(before: block, after: previous) + CGFloat(page.blockHeights[blockIndex])
                    previous = block
                    guard case let .paragraph(fragment, count, url) = block else { orphanSourceOK = false; continue }
                    rebuilt += fragment
                    if count > 0 {
                        bubbles += 1
                        orphanCommentsOK = orphanCommentsOK && count == 36 && url == commentURL && next.hasSuffix(fragment)
                    }
                }
                orphanHeightsOK = orphanHeightsOK && height <= cfg.bodyHeight + 0.5 && page.justifiedGap == nil
            }
            orphanSourceOK = orphanSourceOK && rebuilt == lead + next
            orphanCommentsOK = orphanCommentsOK && bubbles == 1
        }
        let values: [String: Any] = [
            "orphanCases": orphanCases, "orphanMovedOK": orphanMovedOK, "orphanSourceOK": orphanSourceOK,
            "orphanHeightsOK": orphanHeightsOK, "orphanCommentsOK": orphanCommentsOK,
            "reportedSourceOK": reportedSourceOK, "reportedPages": reportedPages.count,
            "reportedOrphans": pageOrphans, "reportedEligible": orphanEligible,
            "cases": cases, "splits": splits, "continuations": continuations,
            "sourceOK": sourceOK, "boundaryOK": boundaryOK, "offsetsOK": offsetsOK,
            "heightsOK": heightsOK, "commentOK": commentOK, "titleOK": titleOK,
            "quoteOK": quoteOK, "cuts": cuts
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: values, options: [.sortedKeys]),
              let result = String(data: data, encoding: .utf8) else { return "{}" }
        return result
    }
}
