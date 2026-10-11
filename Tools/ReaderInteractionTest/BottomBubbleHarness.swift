import SwiftUI
import UIKit

/// Test-only entry point. Every measured paragraph is hosted by PageContentView.
struct BottomBubbleHarnessView: View {
    @State private var report = "pending"

    var body: some View {
        if ProcessInfo.processInfo.arguments.contains("--bottom-bubble-reference") {
            BottomBubbleReferencePage()
        } else {
            VStack {
                Button("检查全页齐底与段尾气泡") { report = BottomBubbleAudit.inspect() }
                    .accessibilityIdentifier("inspect-bottom-bubble")
                Text(report).font(.system(size: 6)).lineLimit(1)
                    .accessibilityIdentifier("bottom-bubble-report")
            }
        }
    }
}

private enum BottomBubbleFixtures {
    static let title = "第一章 处理完夜鬼魔药的副作用之后，还有两样东西等着他逐一查明"
    static let referenceTexts = [
        "处理完夜鬼魔药的副作用后，还有两样东西等着他。",
        "这两样都是之前做试药实验时留下的存货。",
        "这药物来自波顿儿童医院的项目。",
        "合同上写的用途是：治疗癫痫、失眠及焦虑症状。",
        "签字的时候，那个戴金丝眼镜的年轻医生还笑着说：“副作用很轻微，不用担心”。"
    ]
    static let referenceCounts = [3, 1, 0, 23, 4]
    static let commentURL = "https://example.invalid/bottom-bubble/comment"
    static let longText = "\"报告，" + String(repeating: "他继续查看告示牌，走过长街与山川，保持平静。", count: 22)
        + "说完了。\""

    struct Fixture {
        let name: String
        let texts: [String]
        let counts: [Int]
        let title: String
        var blocks: [ContentBlock] {
            texts.indices.map { index in
                .paragraph(text: texts[index], commentCount: counts[index],
                           commentURL: counts[index] > 0 ? commentURL : nil)
            }
        }
    }

    static let reference = Fixture(name: "photo-590CCBC1", texts: referenceTexts,
                                   counts: referenceCounts, title: "")
    static let fullPage = Fixture(name: "photo-full-402", texts: referenceTexts + [
        "但伊文吃了之后，整个人像被人往脑子里灌了铅水。",
        "嗜睡，头晕，走路不稳，有两次差点从楼梯上滚下去。",
        "连续服用两周之后，更严重的症"], counts: referenceCounts + [0,1,0], title: "")

    static func screenshotConfiguration(size: CGSize, bottom: Bool, title: String = "") -> ReaderPaginator.Configuration {
        var value = configuration(font: 23, bottom: bottom, title: title, size: size, horizontalInset: 16)
        value.safeInsets = UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0)
        value.topInset = 24; value.bottomInset = 4
        value.lineSpacing = 10; value.paragraphSpacing = 8
        return value
    }

    static let fixtures = [
        Fixture(name: "multipage-long-title", texts: [longText,
            "Café e\u{301}、👨‍👩‍👧‍👦与中文。" + String(repeating: "纸页上仍有完整的故事。", count: 8), "短尾段。"],
            counts: [23, 3, 1], title: title),
        reference,
        Fixture(name: "short", texts: Array(referenceTexts.prefix(2)), counts: [3, 1], title: ""),
        Fixture(name: "single-line", texts: ["终。"], counts: [1], title: "")
    ]

    static func configuration(font: CGFloat, bottom: Bool,
                              title: String = "", size: CGSize? = nil,
                              horizontalInset: CGFloat = 20) -> ReaderPaginator.Configuration {
        ReaderPaginator.Configuration(pageSize: size ?? CGSize(width: 402, height: 620),
            safeInsets: UIEdgeInsets(top: 13, left: 0, bottom: 17, right: 0),
            fontSize: font, lineSpacing: 8, paragraphSpacing: 8,
            fullJustify: true, bottomJustify: bottom,
            leftInset: horizontalInset, rightInset: horizontalInset, topInset: 30, bottomInset: 20, chapterTitle: title)
    }

    static func content(_ page: BookPage, index: Int, count: Int,
                        config: ReaderPaginator.Configuration) -> PageContentView {
        PageContentView(page: page, fontSize: Double(config.fontSize), lineSpacing: Double(config.lineSpacing),
            fg: .black, bg: .white, title: config.chapterTitle, pageNumber: index + 1,
            pageCount: count, onTapComment: { _ in },
            safeInsets: EdgeInsets(top: config.safeInsets.top, leading: config.safeInsets.left,
                bottom: config.safeInsets.bottom, trailing: config.safeInsets.right),
            paragraphSpacing: Double(config.paragraphSpacing), leftMargin: Double(config.leftInset),
            rightMargin: Double(config.rightInset), topMargin: Double(config.topInset),
            bottomMargin: Double(config.bottomInset), showsChapterTitle: !config.chapterTitle.isEmpty)
    }
}

/// --bottom-bubble-reference renders the exact screenshot paragraphs; adding
/// --bottom-bubble-tail renders the last page of the long-title fixture instead.
/// Both fullJustify and bottomJustify stay enabled; no bubble pixels are fixed here.
private struct BottomBubbleReferencePage: View {
    var body: some View {
        GeometryReader { geometry in
            let tail = ProcessInfo.processInfo.arguments.contains("--bottom-bubble-tail")
            let fixture = tail ? BottomBubbleFixtures.fixtures[0] : BottomBubbleFixtures.fullPage
            let size = CGSize(width: 402, height: geometry.size.height)
            let config = BottomBubbleFixtures.screenshotConfiguration(size: size, bottom: true, title: fixture.title)
            let pages = ReaderPaginator.paginate(fixture.blocks, configuration: config)
            let index = tail ? max(pages.count - 1, 0) : 0
            if pages.indices.contains(index) {
                PageContentView(page: pages[index], fontSize: 23, lineSpacing: 10,
                    fg: Color(red: 69.0/255, green: 64.0/255, blue: 54.0/255),
                    bg: Color(red: 250.0/255, green: 244.0/255, blue: 232.0/255),
                    title: tail ? fixture.title : "第3章：三龙加持 · 样例", pageNumber: index + 1,
                    pageCount: pages.count, onTapComment: { _ in },
                    safeInsets: EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0),
                    paragraphSpacing: 8, leftMargin: 16, rightMargin: 16, topMargin: 24, bottomMargin: 4,
                    showsChapterTitle: tail)
                    .frame(width: size.width, height: size.height)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.ignoresSafeArea().statusBarHidden(true)
    }
}

private enum BottomBubbleAudit {
    private struct Row {
        let characters: NSRange
        let glyphs: NSRange
        let rect: CGRect
        let used: CGRect
        let baseline: CGFloat
        let firstGlyphX: CGFloat
    }

    private static func rows(_ view: CommentTextView) -> [Row] {
        let manager = view.layoutManager
        manager.ensureLayout(for: view.textContainer)
        var result: [Row] = []
        manager.enumerateLineFragments(forGlyphRange: manager.glyphRange(for: view.textContainer)) {
            rect, used, _, glyphs, _ in
            guard glyphs.length > 0 else { return }
            let characters = manager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
            let attachment = view.textStorage.attribute(.attachment, at: characters.location,
                effectiveRange: nil) as? NSTextAttachment
            let origin = manager.location(forGlyphAt: glyphs.location)
            result.append(Row(characters: characters, glyphs: glyphs, rect: rect, used: used,
                baseline: rect.minY + origin.y + (attachment?.bounds.origin.y ?? 0),
                firstGlyphX: rect.minX + origin.x))
        }
        return result
    }

    private static func descendants<T: UIView>(_ view: UIView, as type: T.Type) -> [T] {
        if let found = view as? T { return [found] }
        return view.subviews.flatMap { descendants($0, as: type) }
    }

    private static func rectJSON(_ rect: CGRect) -> [String: Double] {
        ["x": Double(rect.minX), "y": Double(rect.minY),
         "width": Double(rect.width), "height": Double(rect.height)]
    }

    private final class Audit {
        var counters: [String: Int] = [:]
        var maximumErrors: [String: Double] = [:]
        var failures: [[String: Any]] = []
        var failureCount = 0
        var pageSamples: [[String: Any]] = []
        var caseSamples: [[String: Any]] = []
        var bubbleSamples: [[String: Any]] = []

        func count(_ key: String, by value: Int = 1) { counters[key, default: 0] += value }
        func require(_ condition: Bool, _ check: String, _ context: [String: Any]) {
            count(check + "Checks")
            if !condition {
                var failure = context
                failure["check"] = check
                failureCount += 1
                if failures.count < 8 { failures.append(failure) }
            }
        }
        func error(_ difference: CGFloat, _ check: String, _ context: [String: Any], tolerance: CGFloat = 0.75) {
            let error = abs(difference)
            maximumErrors[check] = max(maximumErrors[check] ?? 0, Double(error))
            var detail = context
            detail["absoluteError"] = Double(error)
            detail["tolerance"] = Double(tolerance)
            require(error.isFinite && error <= tolerance, check, detail)
        }
    }

    private static func inspectFixture(_ fixture: BottomBubbleFixtures.Fixture,
                                       font: CGFloat, bottom: Bool, audit: Audit,
                                       configuration: ReaderPaginator.Configuration? = nil) {
        let config = configuration ?? BottomBubbleFixtures.configuration(font: font, bottom: bottom, title: fixture.title,
            horizontalInset: fixture.name == "photo-590CCBC1" ? 16 : 20)
        let pages = ReaderPaginator.paginate(fixture.blocks, configuration: config)
        let metrics = ReaderTextLayout.metrics(fontSize: font)
        let context: [String: Any] = ["fixture": fixture.name, "fontSize": Double(font), "bottomJustify": bottom]
        audit.count("cases")
        audit.require(!pages.isEmpty, "nonemptyPagination", context)
        if fixture.name == "multipage-long-title" {
            audit.require(pages.count >= 3, "firstMiddleLastCoverage", context)
        }
        if fixture.name == "short" || fixture.name == "single-line" {
            audit.require(pages.count == 1, "shortFixtureOnePage", context)
        }
        var sourceIndex = 0, sourceOffset = 0, offset = 0, reassembled = "", displayed = ""
        var casePages: [[String: Any]] = []
        for (pageIndex, page) in pages.enumerated() {
            var detail = context
            detail["pageNumber"] = pageIndex + 1
            detail["pageCount"] = pages.count
            let failureStart = audit.failureCount
            let role = pageIndex == 0 ? "first" : (pageIndex == pages.count - 1 ? "last" : "middle")
            detail["pageRole"] = role
            audit.count("pages")
            audit.count(bottom ? "bottomEnabledPages" : "bottomDisabledPages")
            audit.count((bottom ? "on" : "off") + role.capitalized + "Pages")
            if bottom && pageIndex == pages.count - 1 { audit.count("bottomTerminalPages") }
            audit.require(page.fullJustify, "fullJustifyFlag", detail)
            audit.require(page.startOffset == offset, "pageStartOffset", detail)
            audit.require(page.blockHeights.count == page.blocks.count
                && page.blockLineCounts.count == page.blocks.count, "blockMetadata", detail)
            if !bottom { audit.require(page.justifiedGap == nil, "offNaturalSpacing", detail) }
            if bottom && page.justifiedGap != nil { audit.count("distributedGapPages") }
            if bottom && page.justifiedGap == nil { audit.count("naturalHeightBottomPages") }
            let capacity = pageIndex == 0 ? config.firstPageBodyHeight : config.bodyHeight
            let bodyTop = config.safeInsets.top + config.topInset + (pageIndex == 0 ? config.headerHeight : 0)
            // Independent fixed footer contract, not inferred from page.justifiedGap.
            let bodyBottom = config.pageSize.height - config.safeInsets.bottom - config.bottomInset - 24
            let targetBaseline = bodyBottom - metrics.lineHeight + metrics.baseline
            let naturalHeight = CGFloat(page.blockHeights.reduce(0, +))
                + CGFloat(max(page.blocks.count - 1, 0)) * config.blockSpacing
            let rowCount = page.blockLineCounts.reduce(0, +)
            let advance = max(metrics.lineHeight + config.lineSpacing, 1)
            let surplus = capacity - naturalHeight
            let candidateGap = rowCount > 1 ? max(surplus, 0) / CGFloat(rowCount - 1) : 0
            let nextRowAdvance = advance + max(config.paragraphSpacing, 0)
            let shouldFill = bottom && rowCount > 1 && surplus >= -0.01 && surplus < nextRowAdvance
            audit.require(page.alignsBodyBottom == shouldFill, "alignmentFlag", detail)
            let extra = CGFloat(page.justifiedGap ?? 0)
            audit.error(extra - (shouldFill ? candidateGap : 0), "gapPolicyError", detail, tolerance: 0.001)
            audit.require(extra * CGFloat(max(rowCount - 1, 0)) < nextRowAdvance, "boundedGapExpansion", detail)
            if bottom && pageIndex + 1 < pages.count {
                // Ordinary pure-text pages must fill both ends; do not let a
                // restrictive eligibility condition silently evade this check.
                audit.require(shouldFill, "normalPageFillsBothEnds", detail)
            }
            let spacing = config.lineSpacing + extra
            let host = UIHostingController(rootView: BottomBubbleFixtures.content(page, index: pageIndex,
                count: pages.count, config: config))
            let window = UIWindow(frame: CGRect(origin: .zero, size: config.pageSize))
            window.rootViewController = host
            window.isHidden = false
            host.view.frame = window.bounds
            for _ in 0..<3 { host.view.setNeedsLayout(); host.view.layoutIfNeeded() }
            let views = descendants(host.view, as: CommentTextView.self).sorted {
                $0.convert(.zero, to: host.view).y < $1.convert(.zero, to: host.view).y
            }
            let labels = descendants(host.view, as: UILabel.self).filter { $0.accessibilityIdentifier == "chapter-title" }
            audit.require(views.count == page.blocks.count, "hostedParagraphCount", detail)
            let expectsTitle = pageIndex == 0 && !fixture.title.isEmpty
            audit.require(labels.count == (expectsTitle ? 1 : 0), "titlePresence", detail)
            if expectsTitle, let title = labels.first {
                audit.count("longTitlePages")
                audit.require(title.text == fixture.title && title.numberOfLines == 0, "titleContent", detail)
                audit.error(title.convert(.zero, to: host.view).y - config.safeInsets.top - config.topInset,
                    "titleTopError", detail)
                let titleHeight = ChapterTitleLayout.height(title: fixture.title, fontSize: font, width: config.textWidth)
                audit.error(title.bounds.height - titleHeight, "titleHeightError", detail)
                audit.require(titleHeight > title.font.lineHeight, "multilineTitle", detail)
                detail["titleFrame"] = rectJSON(title.convert(title.bounds, to: host.view))
                detail["title"] = title.text ?? ""
            }
            var firstBaseline: CGFloat?, lastBaseline: CGFloat?, previousBaseline: CGFloat?
            var usedHeight: CGFloat = 0, actualRowCount = 0
            var blockSamples: [[String: Any]] = []
            for (blockIndex, block) in page.blocks.enumerated() {
                var blockDetail = detail
                blockDetail["blockIndex"] = blockIndex
                guard case let .paragraph(text, count, url) = block,
                      fixture.texts.indices.contains(sourceIndex), views.indices.contains(blockIndex),
                      page.blockHeights.indices.contains(blockIndex), page.blockLineCounts.indices.contains(blockIndex) else {
                    audit.require(false, "validParagraphMetadata", blockDetail)
                    continue
                }
                let source = Array(fixture.texts[sourceIndex])
                let sourceDisplay = Array(ReaderTextLayout.displayText(for: fixture.texts[sourceIndex]))
                let end = sourceOffset + text.count
                guard end <= source.count, end <= sourceDisplay.count else {
                    audit.require(false, "sourceRange", blockDetail)
                    continue
                }
                let expectedRaw = String(source[sourceOffset..<end])
                let expectedDisplay = String(sourceDisplay[sourceOffset..<end])
                let actualDisplay = page.displayParagraphs[blockIndex] ?? ReaderTextLayout.displayText(for: text)
                let isEnd = end == source.count
                let continued = page.continuationIndices.contains(blockIndex)
                blockDetail["sourceParagraphIndex"] = sourceIndex
                blockDetail["sourceCharacterOffset"] = sourceOffset
                blockDetail["sourceCharacterEnd"] = end
                blockDetail["continuation"] = continued
                blockDetail["paragraphEnd"] = isEnd
                blockDetail["rawText"] = text
                blockDetail["displayText"] = actualDisplay
                blockDetail["commentCount"] = count
                audit.require(text == expectedRaw && actualDisplay == expectedDisplay
                    && text.utf16.count == expectedDisplay.utf16.count, "sourceFragment", blockDetail)
                audit.require(continued == (sourceOffset > 0), "continuationFlag", blockDetail)
                audit.require(page.paragraphEndIndices.contains(blockIndex) == isEnd, "paragraphEndFlag", blockDetail)
                audit.require(count == (isEnd ? fixture.counts[sourceIndex] : 0)
                    && url == (isEnd && fixture.counts[sourceIndex] > 0 ? BottomBubbleFixtures.commentURL : nil),
                    "originalParagraphTailBubble", blockDetail)
                let view = views[blockIndex]
                let actualRows = rows(view)
                actualRowCount += actualRows.count
                audit.count("actualRows", by: actualRows.count)
                audit.require(!actualRows.isEmpty && actualRows.count == page.blockLineCounts[blockIndex],
                    "actualRowCount", blockDetail)
                audit.require(view.textStorage.string == expectedDisplay + (count > 0 ? " \u{FFFC}" : ""),
                    "hostedSource", blockDetail)
                audit.error(view.bounds.width - config.textWidth, "bodyWidthError", blockDetail)
                audit.error(view.renderedWidth - config.textWidth, "renderedWidthError", blockDetail)
                let naturalHeight = CGFloat(page.blockHeights[blockIndex])
                let expectedHeight = naturalHeight + CGFloat(max(actualRows.count - 1, 0)) * extra
                audit.error(view.bounds.height - expectedHeight, "bodyHeightError", blockDetail)
                usedHeight += expectedHeight + (blockIndex > 0 ? config.blockSpacing + extra : 0)
                blockDetail["frame"] = rectJSON(view.convert(view.bounds, to: host.view))
                blockDetail["naturalHeight"] = Double(naturalHeight)
                blockDetail["actualHeight"] = Double(view.bounds.height)
                blockDetail["expectedLineHeight"] = Double(metrics.lineHeight)
                blockDetail["expectedLineGap"] = Double(spacing)
                if let first = actualRows.first {
                    if continued { audit.count("continuationParagraphs") }
                    let expectedIndent: CGFloat = continued ? 0 : metrics.indentWidth * 2
                    blockDetail["firstGlyphX"] = Double(first.firstGlyphX)
                    blockDetail["expectedFirstGlyphX"] = Double(expectedIndent)
                    audit.error(first.firstGlyphX - expectedIndent, "firstLineIndentError", blockDetail)
                    let firstY = view.convert(CGPoint(x: 0, y: first.baseline), to: host.view).y
                    if firstBaseline == nil { firstBaseline = firstY }
                    if let previous = previousBaseline {
                        audit.count("paragraphBoundaryPairs")
                        audit.error(firstY - previous - metrics.lineHeight - spacing - config.paragraphSpacing,
                            "paragraphBaselineGapError", blockDetail)
                    }
                }
                var lineSamples: [[String: Any]] = []
                for (rowIndex, row) in actualRows.enumerated() {
                    let globalBaseline = view.convert(CGPoint(x: 0, y: row.baseline), to: host.view).y
                    var lineDetail: [String: Any] = ["rowIndex": rowIndex,
                        "utf16Start": row.characters.location, "utf16End": NSMaxRange(row.characters),
                        "baseline": Double(globalBaseline), "lineFragment": rectJSON(row.rect),
                        "usedRect": rectJSON(row.used), "firstGlyphX": Double(row.firstGlyphX)]
                    audit.error(row.used.height - metrics.lineHeight, "actualLineHeightError", blockDetail)
                    audit.error(row.baseline - row.rect.minY - metrics.baseline, "localBaselineError", blockDetail)
                    if rowIndex > 0 {
                        let delta = row.baseline - actualRows[rowIndex - 1].baseline
                        lineDetail["baselineStep"] = Double(delta)
                        lineDetail["actualLineGap"] = Double(delta - row.used.height)
                        audit.count("withinParagraphPairs")
                        audit.error(delta - metrics.lineHeight - spacing, "withinParagraphGapError", blockDetail)
                    }
                    let globalBottom = view.convert(CGPoint(x: 0, y: row.used.maxY), to: host.view).y
                    audit.error(max(globalBottom - bodyBottom, 0), "lineOverflowError", blockDetail)
                    lineSamples.append(lineDetail)
                    lastBaseline = globalBaseline
                }
                previousBaseline = lastBaseline
                blockDetail["lines"] = lineSamples
                if let bubble = inspectBubble(view, text: actualDisplay, count: count,
                                               host: host.view, audit: audit, context: blockDetail) {
                    blockDetail["bubble"] = bubble
                    if fixture.name == "photo-590CCBC1" && bottom {
                        var sample = bubble
                        sample["fontSize"] = Double(font)
                        sample["commentCount"] = count
                        sample["sourceParagraphIndex"] = sourceIndex
                        audit.bubbleSamples.append(sample)
                    }
                }
                if !isEnd {
                    audit.count("splitFragments")
                    let remainder = String(sourceDisplay[sourceOffset...])
                    let probe = ReaderTextLayout.makeTextView()
                    ReaderTextLayout.configure(probe)
                    probe.render(text: remainder, count: fixture.counts[sourceIndex], fontSize: font,
                        lineSpacing: config.lineSpacing, color: .black, continuation: continued, fullJustify: true)
                    _ = ReaderTextLayout.height(of: probe, width: config.textWidth)
                    let endUTF16 = actualDisplay.utf16.count
                    let ends = rows(probe).map { NSMaxRange($0.characters) }
                    blockDetail["unsplitTextKitUTF16RowEnds"] = ends
                    audit.require(ends.contains(endUTF16)
                        && (remainder as NSString).rangeOfComposedCharacterSequence(at: endUTF16).location == endUTF16,
                        "actualLineSplitBoundary", blockDetail)
                }
                blockSamples.append(blockDetail)
                offset += text.count
                reassembled += text
                displayed += actualDisplay
                if isEnd { sourceIndex += 1; sourceOffset = 0 } else { sourceOffset = end }
            }
            audit.require(firstBaseline != nil && lastBaseline != nil, "baselinePresence", detail)
            if let actual = lastBaseline {
                if shouldFill {
                    audit.count("bottomBaselinePages")
                    audit.error(actual - targetBaseline, "bottomBaselineError", detail)
                } else {
                    audit.count("naturalTopPages")
                    let expectedLast = bodyTop + naturalHeight - metrics.lineHeight + metrics.baseline
                    audit.error(actual - expectedLast, "naturalLastBaselineError", detail)
                }
            }
            if let first = firstBaseline {
                // Assert BOTH endpoints on filled pages, and the same fixed
                // top origin even for sparse/on/single-row pages. An overflow-
                // only check cannot catch the whole-body downward shift.
                audit.count("topBaselinePages")
                audit.error(first - bodyTop - metrics.baseline, "topBaselineError", detail)
                audit.error(max(bodyTop + metrics.baseline - first, 0), "bodyTopOverflowError", detail)
                if !bottom {
                    audit.count("offTopBaselinePages")
                    audit.error(first - bodyTop - metrics.baseline, "offTopBaselineError", detail)
                }
            }
            if fixture.name == "short" || fixture.name == "single-line" {
                audit.require(page.justifiedGap == nil && !page.alignsBodyBottom, "sparsePageNaturalSpacing", detail)
                audit.require(capacity - usedHeight > metrics.lineHeight, "sparsePageHasSpareSpace", detail)
                if bottom { audit.count("sparseBottomPages") }
            }
            if fixture.name == "single-line" {
                audit.require(actualRowCount == 1, "singleLineRowCount", detail)
                if bottom { audit.count("singleLineBottomPages") }
            }
            audit.error(max(usedHeight - capacity, 0), "capacityOverflowError", detail)
            detail["alignsBodyBottom"] = page.alignsBodyBottom
            detail["shouldFill"] = shouldFill
            detail["targetFirstBaseline"] = Double(bodyTop + metrics.baseline)
            detail["expectedLastBaseline"] = Double(shouldFill ? targetBaseline
                : bodyTop + naturalHeight - metrics.lineHeight + metrics.baseline)
            detail["naturalBodyHeight"] = Double(naturalHeight)
            detail["justifiedGap"] = page.justifiedGap.map { $0 as Any } ?? NSNull()
            detail["startOffset"] = page.startOffset
            detail["endOffset"] = offset
            detail["bodyTop"] = Double(bodyTop)
            detail["bodyBottom"] = Double(bodyBottom)
            detail["actualBodyHeight"] = Double(usedHeight)
            detail["capacity"] = Double(capacity)
            detail["unusedHeight"] = Double(capacity - usedHeight)
            detail["firstBaseline"] = firstBaseline.map { Double($0) as Any } ?? NSNull()
            detail["lastBaseline"] = lastBaseline.map { Double($0) as Any } ?? NSNull()
            detail["targetLastBaseline"] = Double(targetBaseline)
            detail["actualRowCount"] = actualRowCount
            audit.pageSamples.append(detail)
            casePages.append(["pageNumber": pageIndex + 1, "startOffset": page.startOffset, "endOffset": offset])
            // Only failed pages carry full source slices and TextKit coordinates.
            if audit.failureCount > failureStart, audit.failures.count < 8 {
                detail["blocks"] = blockSamples
                audit.failures.append(["check": "failedPageSample", "page": detail])
            }
            window.isHidden = true
            window.rootViewController = nil
        }
        audit.require(sourceIndex == fixture.texts.count && sourceOffset == 0
            && reassembled == fixture.texts.joined()
            && displayed == fixture.texts.map { ReaderTextLayout.displayText(for: $0) }.joined(),
            "sourceReassembly", context)
        var summary = context
        summary["sourceCommentCounts"] = fixture.counts
        summary["sourceCharacterCount"] = fixture.texts.joined().count
        summary["reassembledCharacterCount"] = reassembled.count
        summary["displayCharacterCount"] = displayed.count
        summary["pageOffsets"] = casePages
        audit.caseSamples.append(summary)
    }

    private static func inspectBubble(_ view: CommentTextView, text: String, count: Int,
                                      host: UIView, audit: Audit, context: [String: Any]) -> [String: Any]? {
        guard count > 0 else {
            audit.require(view.bubbleRect == nil && !view.isBubble(at: CGPoint(x: 1, y: 1))
                && !view.textStorage.string.contains("\u{FFFC}"), "zeroCommentHasNoBubble", context)
            return nil
        }
        audit.count("bubbleParagraphs")
        let storage = view.textStorage
        guard let bubble = view.bubbleRect, storage.length > 0, !text.isEmpty,
              let attachment = storage.attribute(.attachment, at: storage.length - 1,
                  effectiveRange: nil) as? NSTextAttachment, let image = attachment.image else {
            audit.require(false, "bubbleAttachmentPresence", context)
            return nil
        }
        let manager = view.layoutManager
        let glyphs = manager.glyphRange(forCharacterRange: NSRange(location: storage.length - 1, length: 1),
                                       actualCharacterRange: nil)
        let glyphLine = manager.lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
        let glyphOrigin = manager.location(forGlyphAt: glyphs.location)
        let glyphRect = CGRect(x: glyphLine.minX + glyphOrigin.x + attachment.bounds.minX,
            y: glyphLine.minY + glyphOrigin.y - attachment.bounds.height,
            width: attachment.bounds.width, height: attachment.bounds.height)
            .offsetBy(dx: view.textContainerInset.left, dy: view.textContainerInset.top)
        let lastCharacter = (text as NSString).rangeOfComposedCharacterSequence(at: text.utf16.count - 1)
        let lastGlyphs = manager.glyphRange(forCharacterRange: lastCharacter, actualCharacterRange: nil)
        let lastTextRect = manager.boundingRect(forGlyphRange: lastGlyphs, in: view.textContainer)
            .offsetBy(dx: view.textContainerInset.left, dy: view.textContainerInset.top)
        let font = CGFloat(context["fontSize"] as? Double ?? 0)
        let scale = font / 23
        let textLine = manager.lineFragmentRect(forGlyphAt: lastGlyphs.location, effectiveRange: nil)
        let textBaseline = textLine.minY + manager.location(forGlyphAt: lastGlyphs.location).y
            + view.textContainerInset.top
        // Uploaded 23pt/@3x reference: canvas 109×85; canvas top -73px,
        // ink inset 3px, hence ink top -70px and x +3px after text advance.
        let expectedBounds = CGRect(x: 0, y: -4 * scale, width: 109.0 / 3 * scale, height: 85.0 / 3 * scale)
        let declared = CommentBubble.attachmentBounds(fontSize: font)
        for pair in [(attachment.bounds.minX, expectedBounds.minX), (attachment.bounds.minY, expectedBounds.minY),
                     (attachment.bounds.width, expectedBounds.width), (attachment.bounds.height, expectedBounds.height),
                     (declared.width, expectedBounds.width), (declared.height, expectedBounds.height)] {
            audit.error(pair.0 - pair.1, "referenceAttachmentGeometryError", context, tolerance: 0.5)
        }
        audit.error(bubble.minY - textBaseline + 73.0 / 3 * scale,
            "referenceCanvasBaselineError", context, tolerance: 0.5)
        audit.error(bubble.minY + scale - textBaseline + 70.0 / 3 * scale,
            "referenceInkBaselineError", context, tolerance: 0.5)
        audit.error(bubble.minX + scale - lastTextRect.maxX - scale,
            "referenceInkTailAdvanceError", context, tolerance: 0.5)
        audit.count("referenceGeometryBubbles")
        var bubbleLine = NSRange()
        _ = manager.lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: &bubbleLine)
        audit.require(NSLocationInRange(lastGlyphs.location, bubbleLine)
            && NSLocationInRange(NSMaxRange(lastGlyphs) - 1, bubbleLine), "bubbleSharesOriginalTailLine", context)
        for (actual, expected) in [(bubble.minX, glyphRect.minX), (bubble.minY, glyphRect.minY),
                                   (bubble.width, glyphRect.width), (bubble.height, glyphRect.height)] {
            audit.error(actual - expected, "bubbleGlyphRectError", context)
        }
        audit.error(image.size.width - attachment.bounds.width, "bubbleImageWidthError", context)
        audit.error(image.size.height - attachment.bounds.height, "bubbleImageHeightError", context)
        audit.error(max(bubble.maxX - view.bounds.width, -bubble.minX, 0), "bubbleHorizontalOverflowError", context)
        audit.error(max(bubble.maxY - view.bounds.height, -bubble.minY, 0), "bubbleVerticalOverflowError", context)
        audit.error(max(lastTextRect.maxX - bubble.minX, 0), "bubbleTextOverlapError", context)
        let positions: [CGFloat] = [-0.05, 0.1, 0.5, 0.9, 1.05]
        var hits: [Bool] = []
        for y in positions {
            for x in positions {
                let point = CGPoint(x: bubble.minX + x * bubble.width, y: bubble.minY + y * bubble.height)
                let actual = view.isBubble(at: point)
                hits.append(actual)
                audit.require(actual == (x > 0 && x < 1 && y > 0 && y < 1), "bubbleRectHit", context)
            }
        }
        audit.require(image.size.width > 0 && image.size.height > 0, "positiveBubbleImageSize", context)
        return ["bubbleRect": rectJSON(bubble), "hostBubbleRect": rectJSON(view.convert(bubble, to: host)),
            "glyphRect": rectJSON(glyphRect), "lastTextGlyphRect": rectJSON(lastTextRect),
            "lastTextBaseline": Double(textBaseline),
            "canvasTopRelativeToBaseline": Double(bubble.minY - textBaseline),
            "inkTopRelativeToBaseline": Double(bubble.minY + scale - textBaseline),
            "inkGapAfterTextAdvance": Double(bubble.minX + scale - lastTextRect.maxX),
            "attachmentBounds": rectJSON(attachment.bounds), "imageWidth": Double(image.size.width),
            "imageHeight": Double(image.size.height), "tailGap": Double(bubble.minX - lastTextRect.maxX),
            "normalizedHitMap": hits, "commentCount": count]
    }

    static func inspect() -> String {
        precondition(Thread.isMainThread)
        let started = CFAbsoluteTimeGetCurrent()
        let audit = Audit()
        let fonts: [CGFloat] = [19, 24, 28, 32]
        for font in fonts {
            for bottom in [true, false] {
                for fixture in BottomBubbleFixtures.fixtures {
                    autoreleasepool { inspectFixture(fixture, font: font, bottom: bottom, audit: audit) }
                }
            }
        }
        for font: CGFloat in [20, 23] {
            autoreleasepool {
                inspectFixture(BottomBubbleFixtures.reference, font: font, bottom: true, audit: audit)
            }
        }
        for bottom in [true, false] {
            autoreleasepool {
                let config = BottomBubbleFixtures.screenshotConfiguration(size: CGSize(width: 402, height: 874), bottom: bottom)
                inspectFixture(BottomBubbleFixtures.fullPage, font: 23, bottom: bottom, audit: audit, configuration: config)
            }
        }
        // Compare rendered images AND the independently queried TextKit hit boxes.
        // Their absolute pixel size/shape is deliberately not prescribed yet.
        for font in fonts + [20, 23] {
            let samples = audit.bubbleSamples.filter { ($0["fontSize"] as? Double) == Double(font) }
            let selected = [1, 3, 23].compactMap { count in
                samples.first { ($0["commentCount"] as? Int) == count }
            }
            let context: [String: Any] = ["fontSize": Double(font), "samples": selected]
            audit.require(selected.count == 3, "referenceCountsPresent", context)
            guard let first = selected.first else { continue }
            for sample in selected.dropFirst() {
                audit.count("equalSizeBubbleComparisons")
                for key in ["imageWidth", "imageHeight"] {
                    guard let a = first[key] as? Double, let b = sample[key] as? Double else {
                        audit.require(false, "bubbleSizeField", context)
                        continue
                    }
                    audit.error(CGFloat(a - b), "equalBubble" + key.capitalized + "Error", context, tolerance: 0.01)
                }
                for field in ["bubbleRect", "attachmentBounds"] {
                    for dimension in ["width", "height"] {
                        guard let a = first[field] as? [String: Double], let b = sample[field] as? [String: Double],
                              let av = a[dimension], let bv = b[dimension] else {
                            audit.require(false, "bubbleRectField", context)
                            continue
                        }
                        audit.error(CGFloat(av - bv), "equalBubbleRectSizeError", context, tolerance: 0.01)
                    }
                }
                audit.require(first["normalizedHitMap"] as? [Bool] == sample["normalizedHitMap"] as? [Bool],
                    "equalBubbleHitMap", context)
            }
        }
        var report: [String: Any] = ["schemaVersion": 1, "fontSizes": fonts.map { Double($0) },
            "referenceGeometryFontSizes": [20, 23, 24, 32],
            "counters": audit.counters, "maximumErrors": audit.maximumErrors,
            "failures": audit.failures, "failureCount": audit.failureCount,
            "pageSamples": audit.pageSamples, "caseSamples": audit.caseSamples,
            "referenceBubbleSamples": audit.bubbleSamples,
            "elapsedSeconds": CFAbsoluteTimeGetCurrent() - started]
        report.merge(BottomBubblePixelAudit.inspect()) { _, value in value }
        guard let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "serialization-failed" }
        return text
    }
}
