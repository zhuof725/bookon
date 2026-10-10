import SwiftUI
import UIKit
import CoreText

/// Regression fixture transcribed verbatim from photo_5A9EDD22 (第23章 screenshot).
/// The first line is already a continuation of a paragraph on the preceding page.
private enum LayoutAuditFixture {
    static let title = "第23章 鬼面王"
    static let texts = [
        "远处的井盖上。",
        "臭味，越来越浓。",
        "赵空城的手紧紧的攥着手提箱的把手，他深吸一口气，微弯下腰，将手提箱放在了地上。",
        "他很清楚这个臭味代表着什么。",
        "\"报告，守望者赵空城，在老住宅区发现鬼面王……\"他打开耳麦，声音十分平静。",
        "边说话，他便按下了手提箱上的按钮。",
        "啪——！",
        "手提箱弹开，露出了里面整齐而又崭新的三块告示牌。",
        "赵空城将三块告示牌扛起"
    ]
    static let counts = [21, 54, 34, 42, 99, 50, 7, 36, 0]
    static var blocks: [ContentBlock] {
        texts.indices.map { .paragraph(text: texts[$0], commentCount: counts[$0], commentURL: nil) }
    }
    static func configuration(_ size: CGSize) -> ReaderPaginator.Configuration {
        // Real physical screenshot 1206px / 3 = 402pt; no fabricated 10/15 pagination.
        ReaderPaginator.Configuration(pageSize: size, fontSize: 26, lineSpacing: 8,
            paragraphSpacing: 8, leftInset: 20, rightInset: 20, topInset: 70, bottomInset: 30)
    }
    static func referencePage(_ pages: [BookPage]) -> Int {
        pages.firstIndex { page in
            page.blocks.contains { if case .paragraph(_, 36, _) = $0 { return true }; return false }
        } ?? 0
    }
}

struct LayoutAuditHarnessView: View {
    @State private var report = "pending"

    var body: some View {
        if ProcessInfo.processInfo.arguments.contains("--layout-audit-reference-page") {
            GeometryReader { geometry in
                let config = LayoutAuditFixture.configuration(geometry.size)
                let pages = ReaderPaginator.paginate(LayoutAuditFixture.blocks, configuration: config)
                if !pages.isEmpty {
                    let index = ProcessInfo.processInfo.arguments.contains("--layout-audit-first-page")
                        ? 0 : LayoutAuditFixture.referencePage(pages)
                    PageContentView(page: pages[index], fontSize: 26, lineSpacing: 8,
                        fg: Color(red: 0.18, green: 0.18, blue: 0.17),
                        bg: Color(red: 0.985, green: 0.965, blue: 0.92),
                        title: LayoutAuditFixture.title, pageNumber: index + 1,
                        pageCount: pages.count, onTapComment: { _ in },
                        paragraphSpacing: 8, leftMargin: 20, rightMargin: 20,
                        topMargin: 70, bottomMargin: 30)
                }
            }.ignoresSafeArea().statusBarHidden(true)
        } else {
            VStack {
                Button("检查原文换行、段间距与孤行气泡") { report = LayoutAuditInspection.snapshot() }
                    .accessibilityIdentifier("inspect-layout-audit")
                Text(report).font(.system(size: 7)).lineLimit(1)
                    .accessibilityIdentifier("layout-audit-report")
            }.frame(maxWidth: .infinity, maxHeight: .infinity).background(.white)
        }
    }
}

/// The pass/fail metrics below come from actual TextKit glyphs and hosted production pages.
/// Alternative wrapping is recorded separately as evidence, never used to produce the page.
private enum LayoutAuditInspection {
    private struct Row {
        let text: String
        let characters: NSRange
        let glyphs: NSRange
        let rect: CGRect
        let used: CGRect
        let baseline: CGFloat
    }

    private static func rows(_ view: CommentTextView) -> [Row] {
        let manager = view.layoutManager
        manager.ensureLayout(for: view.textContainer)
        let source = view.textStorage.string as NSString
        var output: [Row] = []
        manager.enumerateLineFragments(forGlyphRange: manager.glyphRange(for: view.textContainer)) {
            rect, used, _, glyphs, _ in
            guard glyphs.length > 0 else { return }
            let range = manager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
            guard range.location >= 0, NSMaxRange(range) <= source.length else { return }
            let first = manager.characterIndexForGlyph(at: glyphs.location)
            guard first >= 0, first < view.textStorage.length else { return }
            let attachment = view.textStorage.attribute(.attachment, at: first,
                                                        effectiveRange: nil) as? NSTextAttachment
            let baseline = rect.minY + manager.location(forGlyphAt: glyphs.location).y
                + (attachment?.bounds.origin.y ?? 0)
            output.append(Row(text: source.substring(with: range), characters: range,
                              glyphs: glyphs, rect: rect, used: used, baseline: baseline))
        }
        return output
    }

    @discardableResult
    private static func render(_ view: CommentTextView, text: String, count: Int,
                               width: CGFloat, size: CGFloat, line: CGFloat,
                               continuation: Bool = false) -> CGFloat {
        view.render(text: text, count: count, fontSize: size, lineSpacing: line,
                    color: .black, continuation: continuation)
        let height = ReaderTextLayout.height(of: view, width: width)
        view.frame = CGRect(x: 0, y: 0, width: width, height: height)
        view.layoutIfNeeded()
        return height
    }

    private static func descendants(_ root: UIView) -> [CommentTextView] {
        if let text = root as? CommentTextView { return [text] }
        return root.subviews.flatMap { descendants($0) }
    }

    private static func number(_ value: CGFloat) -> Double { Double(value) }

    private static func mappedSource(_ original: String, _ displayed: String, count: Int) -> Bool {
        let suffix = count > 0 ? " \u{FFFC}" : ""
        guard displayed.hasSuffix(suffix), displayed.utf16.count == original.utf16.count + suffix.utf16.count else { return false }
        let units = Array(displayed.utf16.prefix(original.utf16.count))
        var quote = 0
        for (index, unit) in original.utf16.enumerated() {
            if unit == units[index] { continue }
            guard unit == 0x22, units[index] == (quote.isMultiple(of: 2) ? 0x201C : 0x201D) else { return false }
            quote += 1
        }
        return quote.isMultiple(of: 2)
    }

    /// Isolated attributed copies expose native line-break policy without mutating production.
    private static func diagnosticBreaks(text: String, width: CGFloat, size: CGFloat) -> [String: [String]] {
        var result: [String: [String]] = [:]
        for (name, mode, clearsStrategy) in [
            ("word-production", NSLineBreakMode.byWordWrapping, false),
            ("word-no-strategy", NSLineBreakMode.byWordWrapping, true),
            ("character-no-strategy", NSLineBreakMode.byCharWrapping, true)
        ] {
            let view = ReaderTextLayout.makeTextView()
            ReaderTextLayout.configure(view)
            let attributed = ReaderTextLayout.attributedText(text: text, count: 0,
                fontSize: size, lineSpacing: 8, color: .black, width: width).mutableCopy() as! NSMutableAttributedString
            if attributed.length > 0 {
                let style = (attributed.attribute(.paragraphStyle, at: 0, effectiveRange: nil)
                    as! NSParagraphStyle).mutableCopy() as! NSMutableParagraphStyle
                style.lineBreakMode = mode
                if clearsStrategy { style.lineBreakStrategy = [] }
                attributed.addAttribute(.paragraphStyle, value: style,
                                        range: NSRange(location: 0, length: attributed.length))
            }
            view.attributedText = attributed
            view.textContainer.size = CGSize(width: width, height: .greatestFiniteMagnitude)
            view.frame = CGRect(x: 0, y: 0, width: width, height: 1000)
            view.layoutManager.ensureLayout(for: view.textContainer)
            result[name] = rows(view).map(\.text)
        }
        return result
    }

    static func snapshot() -> String {
        precondition(Thread.isMainThread)
        let started = CFAbsoluteTimeGetCurrent()
        var cases = 0, rowsChecked = 0, sourceOK = true, attachmentsOK = true
        var bubbles = 0, eligibleSuffixes = 0, orphanBubbles = 0, eligibleOrphans = 0
        var nativeAdvanceError: CGFloat = 0, nativeSizeError: CGFloat = 0
        var hanPairs = 0, nativeAttributesOK = true
        var lineBreakRulesOK = true
        var lineBreakViolations: [String] = []
        var quoteSample: [[String: Any]] = [], bubbleSample: [[String: Any]] = []
        var maxAcrossError: CGFloat = 0, acrossPairs = 0, maxWithinError: CGFloat = 0, withinPairs = 0
        var quoteProbe = "", mixedSourceOK = true, isolatedBreaks: [String: [String]] = [:]
        let work = ReaderTextLayout.makeTextView()
        ReaderTextLayout.configure(work)
        // Representative cases (not a 27-case Cartesian product): reported 26/362/8
        // plus narrower, wider, 19/24pt and 0/16pt. Paragraph 2/8 is hosted below.
        for (size, width, line) in [
            (CGFloat(19), CGFloat(333.5), CGFloat(0)), (19, 351, 8),
            (24, 351, 8), (24, 362, 16), (26, 333.5, 16),
            (26, 351, 0), (26, 362, 8)
        ] {
                    cases += 1
                    let grid = ReaderTextLayout.metrics(fontSize: size, width: width)
                    for index in LayoutAuditFixture.texts.indices {
                        let text = LayoutAuditFixture.texts[index], count = LayoutAuditFixture.counts[index]
                        // First line continues an earlier page, all others are new paragraphs.
                        _ = render(work, text: text, count: count, width: width, size: size,
                                   line: line, continuation: index == 0)
                        let storage = work.textStorage.string
                        sourceOK = sourceOK && mappedSource(text, storage, count: count)
                        let result = rows(work)
                        rowsChecked += result.count
                        for pair in zip(result, result.dropFirst()) {
                            withinPairs += 1
                            maxWithinError = max(maxWithinError,
                                abs(pair.1.baseline - pair.0.baseline - grid.lineHeight - line))
                        }
                        let ns = storage as NSString, textLength = (text as NSString).length
                        let manager = work.layoutManager
                        if count > 0 {
                            bubbles += 1
                            let attachmentIndex = textLength + 1
                            if attachmentIndex >= 0 && attachmentIndex < work.textStorage.length {
                                let attachment = work.textStorage.attribute(.attachment, at: attachmentIndex,
                                    effectiveRange: nil) as? NSTextAttachment
                                attachmentsOK = attachmentsOK && attachment != nil
                                    && ns.substring(with: NSRange(location: textLength, length: 2)) == " \u{FFFC}"
                                let bubbleGlyph = manager.glyphIndexForCharacter(at: attachmentIndex)
                                let bubbleRow = result.first { NSLocationInRange(bubbleGlyph, $0.glyphs) }
                                let alone = bubbleRow.map {
                                    $0.text.replacingOccurrences(of: " ", with: "") == "\u{FFFC}"
                                } ?? false
                                if alone { orphanBubbles += 1 }
                                // The final composed character plus punctuation plus separator and
                                // attachment fits on a *fresh* text line: no excuse for FFFC alone.
                                let suffix = String(text.suffix(2))
                                let trial = ReaderTextLayout.makeTextView()
                                ReaderTextLayout.configure(trial)
                                _ = render(trial, text: suffix, count: count, width: width,
                                           size: size, line: line, continuation: true)
                                let fits = rows(trial).count == 1
                                    && rows(trial).first?.text == suffix + " \u{FFFC}"
                                if fits { eligibleSuffixes += 1; if alone { eligibleOrphans += 1 } }
                                if index == 7 && size == 26 && width == 362 && line == 8 {
                                    bubbleSample = result.map { ["text": $0.text,
                                        "used": number($0.used.maxX), "unused": number(width - $0.used.maxX)] }
                                }
                            } else { attachmentsOK = false }
                        }
                        // Validate native Han advances, not the unused space at the right edge.
                        // Quote/punctuation grouping is allowed to leave any necessary ragged margin.
                        if let font = UIFont(name: "PingFangSC-Regular", size: size) {
                            let expected = CGFloat(CTLineGetTypographicBounds(CTLineCreateWithAttributedString(
                                NSAttributedString(string: "汉", attributes: [.font: font])), nil, nil, nil))
                            work.textStorage.enumerateAttributes(in: NSRange(location: 0, length: textLength)) { attrs, _, _ in
                                nativeAttributesOK = nativeAttributesOK && attrs[.kern] == nil && attrs[.ligature] == nil
                            }
                            for row in result {
                                let part = row.text.trimmingCharacters(in: .whitespacesAndNewlines)
                                let closing = Set("，。！？；：、’”】》）〉」』〕］｝")
                                let opening = Set("‘“【《（〈「『〔［｛")
                                let badStart = row.characters.location > 0 && part.first.map { closing.contains($0) } == true
                                let badEnd = NSMaxRange(row.characters) < textLength && part.last.map { opening.contains($0) } == true
                                if badStart || badEnd {
                                    lineBreakRulesOK = false
                                    lineBreakViolations.append("\(size)/\(width):\(row.text)")
                                }
                                for glyph in (row.glyphs.location + 1)..<NSMaxRange(row.glyphs) {
                                    let index = manager.characterIndexForGlyph(at: glyph)
                                    guard index > 0, index < textLength,
                                          manager.characterIndexForGlyph(at: glyph - 1) == index - 1,
                                          (0x4E00...0x9FFF).contains(Int(ns.character(at: index))),
                                          (0x4E00...0x9FFF).contains(Int(ns.character(at: index - 1))) else { continue }
                                    let step = manager.location(forGlyphAt: glyph).x - manager.location(forGlyphAt: glyph - 1).x
                                    nativeAdvanceError = max(nativeAdvanceError, abs(step - expected))
                                    nativeSizeError = max(nativeSizeError, abs(step - size))
                                    let applied = work.textStorage.attribute(.font, at: index - 1, effectiveRange: nil) as? UIFont
                                    nativeAttributesOK = nativeAttributesOK && applied?.fontName == font.fontName
                                    hanPairs += 1
                                }
                            }
                        } else { nativeAttributesOK = false }
                        if size == 26 && width == 362 && line == 8 && index == 4 {
                            quoteProbe = storage
                            quoteSample = result.map { ["text": $0.text,
                                "advance": number($0.used.maxX), "unused": number(width - $0.used.maxX),
                                "glyphs": $0.glyphs.length] }
                        }
                    }
        }
        // ASCII dialogue quotes, native curly quotations, Latin contractions and inches:
        // inspect codepoints in NSTextStorage, not font appearance or a scalar cast of emoji.
        for text in ["\"报告，鬼面王……\"他说。", "她说：“鬼面王……”然后离开。",
                     "don't change 12\" inch marks 👨‍👩‍👧‍👦 e\u{301}。"] {
            _ = render(work, text: text, count: 7, width: 351, size: 24, line: 8)
            mixedSourceOK = mixedSourceOK && mappedSource(text, work.textStorage.string, count: 7)
        }
        isolatedBreaks = diagnosticBreaks(text: LayoutAuditFixture.texts[4], width: 362, size: 26)
        // Diagnostic-only glyph comparison; do not rewrite fixture or the rendered page.
        // U+2026 twice and six ASCII dots may have different native break behavior.
        var quoteVariants: [String: [[String: Any]]] = [:]
        let unicode = LayoutAuditFixture.texts[4]
        let variants = ["ascii-ellipsis": unicode,
                        "ascii-six-dots": unicode.replacingOccurrences(of: "……", with: "......"),
                        "curly-ellipsis-diagnostic": unicode.replacingOccurrences(of: "\"", with: "”"),
                        "curly-six-dots-diagnostic": unicode.replacingOccurrences(of: "……", with: "......")
                            .replacingOccurrences(of: "\"", with: "”")]
        for (name, text) in variants {
            _ = render(work, text: text, count: 99, width: 362, size: 26, line: 8)
            let allRows = rows(work)
            quoteVariants[name] = allRows.map { row in
                ["text": row.text, "glyphs": row.glyphs.length,
                 "advance": number(row.used.maxX), "unused": number(362 - row.used.maxX)]
            }
            if name.hasPrefix("ascii-") {
                mixedSourceOK = mixedSourceOK && mappedSource(text, work.textStorage.string, count: 7)
            }
        }
        let config = LayoutAuditFixture.configuration(CGSize(width: 402, height: 874))
        let pages = ReaderPaginator.paginate(LayoutAuditFixture.blocks, configuration: config)
        var pageSourceOK = true, pageBubbleOrphans = 0, pageEligibleOrphans = 0
        var naturalPagesOK = true, pageHitOK = true
        var pageWidthError: CGFloat = 0, pageHeightError: CGFloat = 0, pageOverflow: CGFloat = 0
        let measurer = ReaderTextLayout.Measurer()
        var pageEligible = 0, renderedPages = 0, pageParagraphs = 0, pageBubble36 = false
        var pageSamples: [[String: Any]] = [], reconstructed = "", offset = 0
        for (pageIndex, page) in pages.enumerated() {
            naturalPagesOK = naturalPagesOK && page.justifiedGap == nil
            pageSourceOK = pageSourceOK && page.startOffset == offset
                && page.blockHeights.count == page.blocks.count
            let content = PageContentView(page: page, fontSize: 26, lineSpacing: 8,
                fg: .black, bg: .white, title: LayoutAuditFixture.title,
                pageNumber: pageIndex + 1, pageCount: pages.count, onTapComment: { _ in },
                paragraphSpacing: 8, leftMargin: 20, rightMargin: 20,
                topMargin: 70, bottomMargin: 30)
            let host = UIHostingController(rootView: content)
            let window = UIWindow(frame: CGRect(origin: .zero, size: config.pageSize))
            window.rootViewController = host
            window.isHidden = false
            host.view.frame = window.bounds
            for _ in 0..<3 { host.view.setNeedsLayout(); host.view.layoutIfNeeded() }
            let views = descendants(host.view).sorted {
                $0.convert(.zero, to: host.view).y < $1.convert(.zero, to: host.view).y
            }
            pageSourceOK = pageSourceOK && views.count == page.blocks.count
            renderedPages += 1
            var previousBaseline: CGFloat?
            for (blockIndex, block) in page.blocks.enumerated() {
                guard blockIndex < views.count,
                      case let .paragraph(text, count, _) = block else { pageSourceOK = false; continue }
                let view = views[blockIndex]
                let blockRows = rows(view)
                pageParagraphs += 1
                let displayed = page.displayParagraphs[blockIndex] ?? ReaderTextLayout.displayText(for: text)
                pageSourceOK = pageSourceOK && view.textStorage.string == displayed
                    + (count > 0 ? " \u{FFFC}" : "")
                    && displayed.utf16.count == text.utf16.count
                    && abs(view.bounds.width - config.textWidth) <= 0.75
                reconstructed += text
                offset += text.count
                let grid = ReaderTextLayout.metrics(fontSize: 26, width: config.textWidth)
                let measured = measurer.height(text: displayed, count: count, width: config.textWidth,
                    fontSize: 26, lineSpacing: 8, continuation: page.continuationIndices.contains(blockIndex))
                let stored = blockIndex < page.blockHeights.count ? CGFloat(page.blockHeights[blockIndex]) : -999
                pageHeightError = max(pageHeightError, abs(view.bounds.height - measured), abs(stored - measured))
                pageWidthError = max(pageWidthError, abs(view.bounds.width - config.textWidth),
                    abs(view.renderedWidth - config.textWidth), abs(view.textContainer.size.width - config.textWidth))
                if let last = blockRows.last {
                    let bottom = view.convert(CGPoint(x: 0, y: last.rect.minY + grid.lineHeight), to: host.view).y
                    pageOverflow = max(pageOverflow, bottom - config.topInset - config.bodyHeight)
                }
                if count > 0 {
                    if let bubble = view.bubbleRect {
                        pageHitOK = pageHitOK && view.isBubble(at: CGPoint(x: bubble.midX, y: bubble.midY))
                            && !view.isBubble(at: CGPoint(x: bubble.maxX + 2, y: bubble.midY))
                    } else { pageHitOK = false }
                }
                for pair in zip(blockRows, blockRows.dropFirst()) {
                    withinPairs += 1
                    maxWithinError = max(maxWithinError,
                        abs(pair.1.baseline - pair.0.baseline - grid.lineHeight - 8))
                }
                if let first = blockRows.first, let previousBaseline {
                    let y = view.convert(CGPoint(x: 0, y: first.baseline), to: host.view).y
                    acrossPairs += 1
                    maxAcrossError = max(maxAcrossError,
                        abs(y - previousBaseline - grid.lineHeight - 8 - 8))
                }
                if let last = blockRows.last {
                    previousBaseline = view.convert(CGPoint(x: 0, y: last.baseline), to: host.view).y
                }
                if count == 36 { pageBubble36 = true }
                if count > 0 {
                    let attachmentIndex = (text as NSString).length + 1
                    if attachmentIndex >= 0 && attachmentIndex < view.textStorage.length {
                        let glyph = view.layoutManager.glyphIndexForCharacter(at: attachmentIndex)
                        let row = blockRows.first { NSLocationInRange(glyph, $0.glyphs) }
                        let orphan = row?.text.replacingOccurrences(of: " ", with: "") == "\u{FFFC}"
                        if orphan { pageBubbleOrphans += 1 }
                        let suffix = String(text.suffix(2))
                        let probe = ReaderTextLayout.makeTextView()
                        ReaderTextLayout.configure(probe)
                        _ = render(probe, text: suffix, count: count, width: config.textWidth,
                                   size: 26, line: 8, continuation: true)
                        let fits = rows(probe).count == 1
                            && rows(probe).first?.text == suffix + " \u{FFFC}"
                        if fits { pageEligible += 1; if orphan { pageEligibleOrphans += 1 } }
                    } else { pageSourceOK = false }
                }
                if count == 99 || count == 36 {
                    pageSamples.append(["page": pageIndex + 1, "pages": pages.count,
                        "count": count, "rows": blockRows.map(\.text),
                        "bubble": blockRows.last?.used.maxX ?? -1,
                        "extra": page.justifiedGap ?? 0])
                }
            }
            window.isHidden = true
            window.rootViewController = nil
        }
        pageSourceOK = pageSourceOK && reconstructed == LayoutAuditFixture.texts.joined()
        // A small natural terminal page checks paragraph=2 independently of the
        // reported page's paragraph=8, using hosted glyph baselines, not usedRect.
        var paragraph2Pairs = 0
        let compactConfig = ReaderPaginator.Configuration(pageSize: CGSize(width: 402, height: 874),
            fontSize: 24, lineSpacing: 0, paragraphSpacing: 2,
            leftInset: 25, rightInset: 25, topInset: 70, bottomInset: 30)
        let compactBlocks = Array(LayoutAuditFixture.blocks.prefix(3))
        if let compactPage = ReaderPaginator.paginate(compactBlocks, configuration: compactConfig).first {
            let compactHost = UIHostingController(rootView: PageContentView(page: compactPage,
                fontSize: 24, lineSpacing: 0, fg: .black, bg: .white,
                title: LayoutAuditFixture.title, pageNumber: 1, pageCount: 1,
                onTapComment: { _ in }, paragraphSpacing: 2,
                leftMargin: 25, rightMargin: 25, topMargin: 70, bottomMargin: 30))
            let compactWindow = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
            compactWindow.rootViewController = compactHost
            compactWindow.isHidden = false
            compactHost.view.frame = compactWindow.bounds
            for _ in 0..<3 { compactHost.view.setNeedsLayout(); compactHost.view.layoutIfNeeded() }
            let compactViews = descendants(compactHost.view).sorted {
                $0.convert(.zero, to: compactHost.view).y < $1.convert(.zero, to: compactHost.view).y
            }
            pageSourceOK = pageSourceOK && compactViews.count == compactPage.blocks.count
            let grid = ReaderTextLayout.metrics(fontSize: 24, width: compactConfig.textWidth)
            for (left, right) in zip(compactViews, compactViews.dropFirst()) {
                guard let last = rows(left).last, let first = rows(right).first else { continue }
                let previous = left.convert(CGPoint(x: 0, y: last.baseline), to: compactHost.view).y
                let next = right.convert(CGPoint(x: 0, y: first.baseline), to: compactHost.view).y
                maxAcrossError = max(maxAcrossError, abs(next - previous - grid.lineHeight - 2))
                acrossPairs += 1
                paragraph2Pairs += 1
            }
            compactWindow.isHidden = true
            compactWindow.rootViewController = nil
        }
        let spanningRaw = "\"报告，" + String(repeating: "他继续查看手提箱里的告示牌，保持平静。", count: 18) + "说完了。\""
        let spanningConfig = ReaderPaginator.Configuration(pageSize: CGSize(width: 391, height: 260),
            fontSize: 26, lineSpacing: 8, paragraphSpacing: 2)
        let spanning = ReaderPaginator.paginate([.paragraph(text: spanningRaw, commentCount: 36, commentURL: nil)],
                                               configuration: spanningConfig)
        var joinedRaw = "", joinedDisplay = "", spanningOffsetsOK = true, spanningOffset = 0
        var spanningLineSplitsOK = true, spanningSplits = 0
        let fullDisplay = Array(ReaderTextLayout.displayText(for: spanningRaw))
        for page in spanning {
            spanningOffsetsOK = spanningOffsetsOK && page.startOffset == spanningOffset
            for (blockIndex, block) in page.blocks.enumerated() {
                guard case let .paragraph(text, _, _) = block else { continue }
                let display = page.displayParagraphs[blockIndex] ?? text
                spanningOffsetsOK = spanningOffsetsOK && text.utf16.count == display.utf16.count
                if spanningOffset + text.count < fullDisplay.count {
                    let remainder = String(fullDisplay[spanningOffset...])
                    _ = render(work, text: remainder, count: 36, width: spanningConfig.textWidth,
                        size: 26, line: 8, continuation: spanningOffset > 0)
                    let actualEnds = Set(rows(work).map { NSMaxRange($0.characters) })
                    spanningLineSplitsOK = spanningLineSplitsOK && actualEnds.contains(display.utf16.count)
                    spanningSplits += 1
                }
                spanningOffset += text.count
                joinedRaw += text
                joinedDisplay += display
            }
        }
        let spanningOK = spanning.count > 2 && spanningOffsetsOK && joinedRaw == spanningRaw
            && joinedDisplay == "“" + String(spanningRaw.dropFirst().dropLast()) + "”"
        let untouched = ["6\" × 12\"", "The \"report\" is fine.", "他说\"未闭合", "don't change this"]
        let nonDialogueOK = untouched.allSatisfy { ReaderTextLayout.displayText(for: $0) == $0 }
        let closingCases = [("他说完了。\"", "他说完了。”"), ("真的？\"", "真的？”"),
                            ("快走！\"", "快走！”"), ("说到这里……\"", "说到这里……”"),
                            ("“报告，结束。\"", "“报告，结束。”")]
        let contextualClosingOK = closingCases.allSatisfy { raw, expected in
            let actual = ReaderTextLayout.displayText(for: raw)
            return actual == expected && actual.utf16.count == raw.utf16.count
        }
        let report: [String: Any] = [
            "elapsedSeconds": CFAbsoluteTimeGetCurrent() - started,
            "contextualClosingOK": contextualClosingOK,
            "spanningLineSplitsOK": spanningLineSplitsOK, "spanningSplits": spanningSplits,
            "naturalPagesOK": naturalPagesOK, "pageHitOK": pageHitOK,
            "pageWidthError": number(pageWidthError), "pageHeightError": number(pageHeightError),
            "pageOverflow": number(pageOverflow),
            "spanningQuoteOK": spanningOK, "spanningPages": spanning.count, "nonDialogueOK": nonDialogueOK,
            "cases": cases, "rowsChecked": rowsChecked, "sourceOK": sourceOK,
            "attachmentsOK": attachmentsOK, "mixedSourceOK": mixedSourceOK,
            "bubbles": bubbles, "eligibleSuffixes": eligibleSuffixes,
            "orphanBubbles": orphanBubbles, "eligibleOrphans": eligibleOrphans,
            "nativeAdvanceError": number(nativeAdvanceError), "nativeSizeError": number(nativeSizeError),
            "hanPairs": hanPairs, "nativeAttributesOK": nativeAttributesOK,
            "quoteSource": quoteProbe, "quoteRows": quoteSample,
            "quoteVariants": quoteVariants,
            "lineBreakRulesOK": lineBreakRulesOK, "lineBreakViolations": lineBreakViolations,
            "bubble36Rows": bubbleSample,
            "isolatedNativeBreaks": isolatedBreaks, "pageRows": pageSamples,
            "pageCount": pages.count, "renderedPages": renderedPages,
            "pageParagraphs": pageParagraphs, "pageBubble36": pageBubble36,
            "pageSourceOK": pageSourceOK, "pageOrphans": pageBubbleOrphans,
            "pageEligibleSuffixes": pageEligible, "pageEligibleOrphans": pageEligibleOrphans,
            "maxWithinError": number(maxWithinError), "withinPairs": withinPairs,
            "maxAcrossError": number(maxAcrossError), "acrossPairs": acrossPairs,
            "paragraph2Pairs": paragraph2Pairs
        ]
        guard JSONSerialization.isValidJSONObject(report),
              let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else { return "invalid-json" }
        // Accessibility strips literal attachment placeholders from labels; JSON
        // escaping preserves the source code unit for the UI test to decode.
        return json.replacingOccurrences(of: "\u{FFFC}", with: "\\ufffc")
    }
}
