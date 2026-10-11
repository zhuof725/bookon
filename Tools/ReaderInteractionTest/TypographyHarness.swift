import SwiftUI
import CoreText

private enum TypographyFixtures {
    static let dialogue = "“春江花月夜，”他说，‘远处的山川——仍在风雨里……’玛丽·苏回答：“明天继续阅读。”"
    static let paragraphs = [String(repeating: dialogue, count: 6), "“好。”", String(repeating: dialogue, count: 4)]
}

private struct TypographyScrollParagraphs: View {
    let size: CGFloat
    let spacing: CGFloat
    var body: some View {
        VStack(alignment: .leading, spacing: ReaderTextLayout.paragraphGap(lineSpacing: spacing, paragraphSpacing: 8)) {
            ForEach(TypographyFixtures.paragraphs.indices, id: \.self) { index in
                InlineCommentParagraph(text: TypographyFixtures.paragraphs[index], count: 82,
                    fontSize: size, lineSpacing: spacing, color: .black, onTap: {})
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }.padding(.horizontal, 20)
    }
}

struct TypographyHarnessView: View {
    @StateObject private var settings = ReadSettings()
    @State private var showSettings = false
    @State private var metrics = "pending"
    private let title = "这是一个很长的章节标题，用来确认标题不会被截断或从阅读页面消失"

    var body: some View {
        if ProcessInfo.processInfo.arguments.contains("--reference-page") {
            ReferenceTypographyPage()
        } else {
            inspectionBody
        }
    }

    private var inspectionBody: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: CGFloat(settings.paragraphSpacing)) {
                    ChapterTitleView(title: title, fontSize: CGFloat(settings.fontSize), color: .black)
                        .accessibilityIdentifier("typography-title")
                    InlineCommentParagraph(text: String(repeating: "这是版式设置的长正文，中文标点应保留自然字形和间距。", count: 30),
                        count: 82, fontSize: CGFloat(settings.fontSize),
                        lineSpacing: CGFloat(settings.lineSpacing), color: .black, onTap: {})
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("typography-body")
                }
                .padding(.leading, CGFloat(settings.leftMargin))
                .padding(.trailing, CGFloat(settings.rightMargin))
                .padding(.top, CGFloat(settings.topMargin))
                .padding(.bottom, CGFloat(settings.bottomMargin))
            }
            VStack {
                HStack {
                    Spacer()
                    Button("设置") { showSettings = true }
                        .accessibilityIdentifier("open-settings")
                }
                .padding()
                Spacer()
            }
            if showSettings {
                VStack(spacing: 0) {
                    HStack {
                        Text("阅读设置").font(.headline)
                        Spacer()
                        Button("完成") { showSettings = false }
                            .accessibilityIdentifier("close-settings")
                    }
                    .padding()
                    Form { ReaderTypographyControls(settings: settings) }
                }
                .background(.background)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(12)
                .shadow(radius: 12)
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 2) {
                Button("检查原生字形与行距") { metrics = TypographyInspection.snapshot() }
                    .accessibilityIdentifier("inspect-typography")
                Text(metrics).font(.system(size: 7)).lineLimit(1)
                    .accessibilityIdentifier("typography-metrics")
            }.frame(maxWidth: .infinity).background(Color.white)
        }
    }
}

/// Numeric acceptance reads actual TextKit glyphs and hosted production views.
/// A ragged right edge is intentional; native advances must never be stretched to fill it.
private enum TypographyInspection {
    private struct Line {
        let glyphs: NSRange
        let characters: NSRange
        let rect: CGRect
        let used: CGRect
        let baseline: CGFloat
    }

    private static func lines(_ view: CommentTextView) -> [Line] {
        let manager = view.layoutManager
        manager.ensureLayout(for: view.textContainer)
        var result: [Line] = []
        manager.enumerateLineFragments(forGlyphRange: manager.glyphRange(for: view.textContainer)) {
            rect, used, _, glyphs, _ in
            guard glyphs.length > 0 else { return }
            let characters = manager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
            let attachment = view.textStorage.attribute(.attachment, at: characters.location,
                effectiveRange: nil) as? NSTextAttachment
            let baseline = rect.minY + manager.location(forGlyphAt: glyphs.location).y
                + (attachment?.bounds.origin.y ?? 0)
            result.append(Line(glyphs: glyphs, characters: characters, rect: rect, used: used, baseline: baseline))
        }
        return result
    }

    @discardableResult
    private static func layout(_ view: CommentTextView, text: String, count: Int = 0,
                               width: CGFloat, size: CGFloat, spacing: CGFloat,
                               continuation: Bool = false) -> CGFloat {
        view.render(text: text, count: count, fontSize: size, lineSpacing: spacing,
                    color: .black, continuation: continuation)
        let height = ReaderTextLayout.height(of: view, width: width)
        view.frame = CGRect(x: 0, y: 0, width: width, height: height)
        view.setNeedsLayout()
        view.layoutIfNeeded()
        return height
    }

    private static func descendants(_ root: UIView) -> [CommentTextView] {
        if let own = root as? CommentTextView { return [own] }
        return root.subviews.flatMap { descendants($0) }
    }

    private static func nativeAdvance(_ font: UIFont) -> CGFloat {
        CGFloat(CTLineGetTypographicBounds(CTLineCreateWithAttributedString(
            NSAttributedString(string: "汉", attributes: [.font: font])), nil, nil, nil))
    }

    /// Comparing each UTF-16 unit also catches accidental surrogate/combining-mark edits.
    /// Only paired Chinese ASCII quotes may differ, and each replacement occupies one unit.
    private static func mappedSource(_ source: String, display: String) -> Bool {
        let raw = Array(source.utf16), shown = Array(display.utf16)
        guard raw.count == shown.count else { return false }
        var changed = 0
        for index in raw.indices where raw[index] != shown[index] {
            guard raw[index] == 0x22,
                  shown[index] == (changed.isMultiple(of: 2) ? 0x201C : 0x201D) else { return false }
            changed += 1
        }
        return changed.isMultiple(of: 2)
    }

    private static func breaksOK(_ view: CommentTextView) -> Bool {
        let text = view.textStorage.string as NSString
        let closing = Set("，。！？；：、’”】》）〉」』〕］｝")
        let opening = Set("‘“【《（〈「『〔［｛")
        return lines(view).allSatisfy { line in
            let part = text.substring(with: line.characters)
            if line.characters.location > 0, let first = part.first, closing.contains(first) { return false }
            if NSMaxRange(line.characters) < text.length, let last = part.last, opening.contains(last) { return false }
            return true
        }
    }

    private static func naturalReport() -> [String: Any] {
        let view = ReaderTextLayout.makeTextView(), reference = ReaderTextLayout.makeTextView()
        ReaderTextLayout.configure(view); ReaderTextLayout.configure(reference)
        reference.textContainer.widthTracksTextView = false
        reference.textContainer.heightTracksTextView = false
        let measurer = ReaderTextLayout.Measurer()
        let text = String(repeating: TypographyFixtures.dialogue + "【山川】（风雨）《故事》！？；：、。", count: 2)
        let ns = text as NSString
        var advanceError: CGFloat = 0, sizeError: CGFloat = 0, indentError: CGFloat = 0
        var glyphError: CGFloat = 0, widthError: CGFloat = 0, baselineError: CGFloat = 0
        var heightError: CGFloat = 0, largestHanStep: CGFloat = 0
        var hanPairs = 0, punctuationGlyphs = 0, rowCount = 0, baselinePairs = 0, cases = 0
        var sourceOK = true, attributesOK = true, nativeGlyphs = true, lineBreaksOK = true
        var quotes: [String: Int] = [:]
        let settings: [(CGFloat, CGFloat, CGFloat)] = [
            (12, 333.5, 0), (19, 351, 8), (19, 362, 8),
            (24, 351, 0), (26, 362, 16), (36, 370, 24)
        ]
        for (size, width, spacing) in settings {
            guard let font = UIFont(name: "PingFangSC-Regular", size: size) else { attributesOK = false; continue }
            let advance = nativeAdvance(font)
            let metrics = ReaderTextLayout.metrics(fontSize: size)
            for continuation in [false, true] {
                cases += 1
                let height = layout(view, text: text, width: width, size: size,
                    spacing: spacing, continuation: continuation)
                let rows = lines(view)
                rowCount += rows.count
                sourceOK = sourceOK && view.textStorage.string == text
                widthError = max(widthError, abs(view.renderedWidth - width), abs(view.textContainer.size.width - width))
                heightError = max(heightError, abs(height - measurer.height(text: text, count: 0,
                    width: width, fontSize: size, lineSpacing: spacing, continuation: continuation)),
                    abs(height - CGFloat(rows.count) * metrics.lineHeight - CGFloat(max(rows.count - 1, 0)) * spacing))
                let style = NSMutableParagraphStyle()
                style.alignment = .left; style.lineBreakMode = .byWordWrapping; style.lineBreakStrategy = []
                style.firstLineHeadIndent = continuation ? 0 : advance * 2
                style.lineSpacing = spacing
                style.minimumLineHeight = metrics.lineHeight; style.maximumLineHeight = metrics.lineHeight
                // Independent native font/layout, not width-aware production metrics or copied attributes.
                reference.attributedText = NSAttributedString(string: text, attributes: [.font: font, .paragraphStyle: style])
                reference.textContainer.size = CGSize(width: width, height: .greatestFiniteMagnitude)
                reference.frame = CGRect(x: 0, y: 0, width: width, height: height)
                reference.layoutManager.ensureLayout(for: reference.textContainer)
                let manager = view.layoutManager, native = reference.layoutManager
                nativeGlyphs = nativeGlyphs && manager.numberOfGlyphs == native.numberOfGlyphs
                for glyph in 0..<min(manager.numberOfGlyphs, native.numberOfGlyphs) {
                    nativeGlyphs = nativeGlyphs && manager.glyph(at: glyph) == native.glyph(at: glyph)
                        && manager.characterIndexForGlyph(at: glyph) == native.characterIndexForGlyph(at: glyph)
                    glyphError = max(glyphError, abs(manager.location(forGlyphAt: glyph).x - native.location(forGlyphAt: glyph).x))
                }
                view.textStorage.enumerateAttributes(in: NSRange(location: 0, length: ns.length)) { attrs, _, _ in
                    let applied = attrs[.font] as? UIFont
                    attributesOK = attributesOK && attrs[.kern] == nil && attrs[.ligature] == nil
                        && applied?.fontName == font.fontName
                        && applied?.fontDescriptor.isEqual(font.fontDescriptor) == true
                }
                for (rowIndex, row) in rows.enumerated() {
                    if rowIndex == 0 {
                        indentError = max(indentError, abs(row.rect.minX + manager.location(forGlyphAt: row.glyphs.location).x
                            - (continuation ? 0 : advance * 2)))
                    }
                    for glyph in row.glyphs.location..<NSMaxRange(row.glyphs) {
                        let index = manager.characterIndexForGlyph(at: glyph)
                        let unit = ns.character(at: index)
                        if [0x2018, 0x2019, 0x201C, 0x201D].contains(unit) {
                            quotes[ns.substring(with: NSRange(location: index, length: 1))] = Int(manager.glyph(at: glyph))
                        }
                        if "，。！？；：、‘’“”【】（）《》—…·".utf16.contains(unit) { punctuationGlyphs += 1 }
                        guard glyph > row.glyphs.location, index > 0,
                              manager.characterIndexForGlyph(at: glyph - 1) == index - 1,
                              (0x4E00...0x9FFF).contains(Int(unit)),
                              (0x4E00...0x9FFF).contains(Int(ns.character(at: index - 1))) else { continue }
                        let step = manager.location(forGlyphAt: glyph).x - manager.location(forGlyphAt: glyph - 1).x
                        advanceError = max(advanceError, abs(step - advance))
                        sizeError = max(sizeError, abs(step - size))
                        largestHanStep = max(largestHanStep, step / size)
                        hanPairs += 1
                    }
                }
                for pair in zip(rows, rows.dropFirst()) {
                    baselineError = max(baselineError, abs(pair.1.baseline - pair.0.baseline - metrics.lineHeight - spacing))
                    baselinePairs += 1
                }
                lineBreaksOK = lineBreaksOK && breaksOK(view)
                nativeGlyphs = nativeGlyphs && quotes.count == 4 && Set(quotes.values).count == 4
                    && quotes.values.allSatisfy { $0 > 0 }
            }
        }
        // Latin ligatures, combining marks and emoji remain native runs, not individual cells.
        let latin = "“AVATAR” ‘office’ don’t — ffi… café·e\u{301} 👨‍👩‍👧‍👦"
        _ = layout(view, text: latin, width: 900, size: 19, spacing: 8, continuation: true)
        reference.attributedText = NSAttributedString(string: latin, attributes: [.font: UIFont.systemFont(ofSize: 19)])
        reference.textContainer.size = CGSize(width: 900, height: CGFloat.greatestFiniteMagnitude)
        reference.layoutManager.ensureLayout(for: reference.textContainer)
        let actual = view.layoutManager, native = reference.layoutManager
        var shapingError: CGFloat = 0
        var nativeRuns = actual.numberOfGlyphs == native.numberOfGlyphs
        for glyph in 0..<min(actual.numberOfGlyphs, native.numberOfGlyphs) {
            nativeRuns = nativeRuns && actual.glyph(at: glyph) == native.glyph(at: glyph)
                && actual.characterIndexForGlyph(at: glyph) == native.characterIndexForGlyph(at: glyph)
            shapingError = max(shapingError, abs(actual.location(forGlyphAt: glyph).x - native.location(forGlyphAt: glyph).x))
        }
        return ["naturalCases": cases, "naturalRows": rowCount, "hanPairs": hanPairs,
            "punctuationGlyphs": punctuationGlyphs, "nativeAdvanceError": Double(advanceError),
            "nativeSizeError": Double(sizeError), "largestHanStepRatio": Double(largestHanStep),
            "nativeGlyphError": Double(glyphError), "indentError": Double(indentError),
            "widthError": Double(widthError), "heightError": Double(heightError),
            "baselineError": Double(baselineError), "baselinePairs": baselinePairs,
            "naturalSourceOK": sourceOK, "naturalAttributesOK": attributesOK,
            "nativeGlyphsOK": nativeGlyphs, "lineBreaksOK": lineBreaksOK,
            "quoteGlyphs": quotes, "nativeRunsOK": nativeRuns, "shapingError": Double(shapingError)]
    }

    private static func bubbleReport() -> [String: Any] {
        let view = ReaderTextLayout.makeTextView()
        ReaderTextLayout.configure(view)
        let source = "她说：“AVATAR、office、e\u{301}、👨‍👩‍👧‍👦都不能拆开。”"
        var hitOK = true, sourceOK = true, tailOK = true, naturalRuns = true
        var widthError: CGFloat = 0, heightError: CGFloat = 0, baselineError: CGFloat = 0
        var checks = 0
        for (size, width, spacing) in [(CGFloat(12), CGFloat(333.5), CGFloat(0)),
                                       (19, 351, 8), (24, 362, 16), (36, 370, 24)] {
            let height = layout(view, text: source, count: 82, width: width, size: size, spacing: spacing)
            let rows = lines(view), metrics = ReaderTextLayout.metrics(fontSize: size)
            sourceOK = sourceOK && view.textStorage.string == source + " \u{FFFC}"
            view.textStorage.enumerateAttributes(in: NSRange(location: 0, length: source.utf16.count)) { attrs, _, _ in
                naturalRuns = naturalRuns && attrs[.kern] == nil && attrs[.ligature] == nil
            }
            for pair in zip(rows, rows.dropFirst()) {
                baselineError = max(baselineError, abs(pair.1.baseline - pair.0.baseline - metrics.lineHeight - spacing))
            }
            let last = rows.last.map { (view.textStorage.string as NSString).substring(with: $0.characters) } ?? ""
            tailOK = tailOK && last.contains("开。” \u{FFFC}")
            guard let bubble = view.bubbleRect else { hitOK = false; continue }
            checks += 1
            hitOK = hitOK && view.isBubble(at: CGPoint(x: bubble.midX, y: bubble.midY))
                && !view.isBubble(at: CGPoint(x: bubble.maxX + 2, y: bubble.midY))
                && !view.isBubble(at: CGPoint(x: bubble.midX, y: bubble.maxY + 2))
                && bubble.maxX <= width + 0.5 && bubble.maxY <= height + 0.5
            // A speculative SwiftUI width must not invalidate hit-testing on the visible frame.
            _ = view.sizeThatFits(CGSize(width: width + 47, height: .greatestFiniteMagnitude))
            if let restored = view.bubbleRect {
                widthError = max(widthError, abs(restored.minX - bubble.minX), abs(restored.minY - bubble.minY),
                                 abs(view.renderedWidth - width))
            } else { hitOK = false }
            let plain = layout(view, text: "汉", width: width, size: size, spacing: spacing)
            let plainBaseline = lines(view).first?.baseline ?? -999
            let withBubble = layout(view, text: "汉", count: 82, width: width, size: size, spacing: spacing)
            heightError = max(heightError, abs(withBubble - plain))
            baselineError = max(baselineError, abs((lines(view).first?.baseline ?? 999) - plainBaseline))
        }
        return ["bubbleChecks": checks, "bubbleHitOK": hitOK, "bubbleSourceOK": sourceOK,
            "bubbleTailOK": tailOK, "mixedNativeRunsOK": naturalRuns,
            "bubbleWidthError": Double(widthError), "bubbleHeightError": Double(heightError),
            "bubbleBaselineError": Double(baselineError)]
    }

    private static func pageReport() -> [String: Any] {
        // Paired ASCII dialogue crosses pages; a separate paragraph covers ZWJ and UTF-16.
        let rawDialogue = "\"报告，" + String(repeating: "他继续查看告示牌，保持平静。", count: 16) + "说完了。\""
        let texts = [rawDialogue, "“好。”", "AVATAR、office、e\u{301}、👨‍👩‍👧‍👦与中文混排。" + String(repeating: "山川风雨天地。", count: 7), "短尾段。"]
        let counts = [36, 7, 82, 0]
        let url = "https://example.invalid/comments"
        let blocks: [ContentBlock] = texts.indices.map { .paragraph(text: texts[$0], commentCount: counts[$0], commentURL: counts[$0] > 0 ? url : nil) }
        let measurer = ReaderTextLayout.Measurer(), probe = ReaderTextLayout.makeTextView()
        ReaderTextLayout.configure(probe)
        var sourceOK = true, offsetsOK = true, splitsOK = true, continuationOK = true
        var commentsOK = true, bubblesOK = true, naturalPages = true
        var within: CGFloat = 0, across: CGFloat = 0, heightError: CGFloat = 0
        var widthError: CGFloat = 0, overflow: CGFloat = 0, topError: CGFloat = 0
        var bottomBaselineError: CGFloat = 0, terminalBottomError: CGFloat = 0, titleTopError: CGFloat = 0
        var anchoredPages = 0, terminalAnchors = 0, titleChecks = 0
        var pagesChecked = 0, nonterminals = 0, pairs = 0, boundaries = 0, splitChecks = 0, comments = 0
        var samples: [[String: Any]] = []
        let settings: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [(19, 0, 0, 391), (24, 8, 2, 402), (26, 16, 8, 373.5)]
        for (size, line, paragraph, width) in settings {
            let config = ReaderPaginator.Configuration(pageSize: CGSize(width: width, height: 520),
                safeInsets: UIEdgeInsets(top: 13, left: 0, bottom: 17, right: 0),
                fontSize: size, lineSpacing: line, paragraphSpacing: paragraph,
                fullJustify: true, bottomJustify: true,
                leftInset: 20, rightInset: 20, topInset: 30, bottomInset: 20,
                chapterTitle: "章节标题固定在上方而正文最后一行统一到底部")
            let pages = ReaderPaginator.paginate(blocks, configuration: config)
            let metrics = ReaderTextLayout.metrics(fontSize: size)
            var offset = 0, sourceIndex = 0, localOffset = 0, rawJoined = "", shownJoined = ""
            for (pageIndex, page) in pages.enumerated() {
                pagesChecked += 1
                if pageIndex + 1 < pages.count { nonterminals += 1 }
                // Android only distributes spare height on near-full pages;
                // a sparse terminal page keeps its natural top position.
                naturalPages = naturalPages && (pageIndex + 1 < pages.count || page.justifiedGap == nil)
                offsetsOK = offsetsOK && page.startOffset == offset && page.blockHeights.count == page.blocks.count
                let content = PageContentView(page: page, fontSize: Double(size), lineSpacing: Double(line),
                    fg: .black, bg: .white, title: config.chapterTitle, pageNumber: pageIndex + 1,
                    pageCount: pages.count, onTapComment: { _ in },
                    safeInsets: EdgeInsets(top: 13, leading: 0, bottom: 17, trailing: 0),
                    paragraphSpacing: Double(paragraph), leftMargin: 20, rightMargin: 20,
                    topMargin: 30, bottomMargin: 20, showsChapterTitle: true)
                let host = UIHostingController(rootView: content)
                let window = UIWindow(frame: CGRect(origin: .zero, size: config.pageSize))
                window.rootViewController = host; window.isHidden = false; host.view.frame = window.bounds
                for _ in 0..<3 { host.view.setNeedsLayout(); host.view.layoutIfNeeded() }
                let views = descendants(host.view).sorted { $0.convert(.zero, to: host.view).y < $1.convert(.zero, to: host.view).y }
                sourceOK = sourceOK && views.count == page.blocks.count
                var previousBaseline: CGFloat?, used: CGFloat = 0
                for (index, block) in page.blocks.enumerated() {
                    guard case let .paragraph(text, count, commentURL) = block,
                          sourceIndex < texts.count, index < views.count else { sourceOK = false; continue }
                    let original = texts[sourceIndex], allRaw = Array(original)
                    let display = ReaderTextLayout.displayText(for: original), allDisplay = Array(display)
                    let end = localOffset + text.count
                    guard end <= allRaw.count else { sourceOK = false; continue }
                    let expectedDisplay = String(allDisplay[localOffset..<end])
                    let actualDisplay = page.displayParagraphs[index] ?? ReaderTextLayout.displayText(for: text)
                    let continued = page.continuationIndices.contains(index)
                    continuationOK = continuationOK && continued == (localOffset > 0)
                    sourceOK = sourceOK && text == String(allRaw[localOffset..<end])
                        && actualDisplay == expectedDisplay && text.utf16.count == expectedDisplay.utf16.count
                        && mappedSource(original, display: display)
                    let atEnd = end == allRaw.count
                    commentsOK = commentsOK && count == (atEnd ? counts[sourceIndex] : 0)
                        && commentURL == (atEnd && counts[sourceIndex] > 0 ? url : nil)
                    if count > 0 { comments += 1 }
                    if !atEnd {
                        // Independent actual TextKit row table for the unsplit remainder.
                        // Never accept an arbitrary prefix merely because its height fits.
                        let remainder = String(allDisplay[localOffset...])
                        _ = layout(probe, text: remainder, count: counts[sourceIndex], width: config.textWidth,
                            size: size, spacing: line, continuation: continued)
                        let endUTF16 = expectedDisplay.utf16.count
                        let actualEnds = Set(lines(probe).map { NSMaxRange($0.characters) })
                        splitsOK = splitsOK && actualEnds.contains(endUTF16)
                            && (remainder as NSString).rangeOfComposedCharacterSequence(at: endUTF16).location == endUTF16
                        splitChecks += 1
                    }
                    let view = views[index], rows = lines(view)
                    sourceOK = sourceOK && view.textStorage.string == expectedDisplay + (count > 0 ? " \u{FFFC}" : "")
                    widthError = max(widthError, abs(view.bounds.width - config.textWidth),
                        abs(view.renderedWidth - config.textWidth), abs(view.textContainer.size.width - config.textWidth))
                    let extra = CGFloat(page.justifiedGap ?? 0)
                    let rowSpacing = line + extra
                    let measured = measurer.height(text: expectedDisplay, count: count, width: config.textWidth,
                        fontSize: size, lineSpacing: line + extra, continuation: continued,
                        fullJustify: page.fullJustify, zhLayout: page.zhLayout,
                        paragraphEnd: page.paragraphEndIndices.isEmpty
                            ? true : page.paragraphEndIndices.contains(index))
                    let stored = index < page.blockHeights.count ? CGFloat(page.blockHeights[index]) : -999
                    let lineCount = page.blockLineCounts.indices.contains(index) ? page.blockLineCounts[index] : 0
                    let expectedHeight = stored + CGFloat(max(lineCount - 1, 0)) * extra
                    heightError = max(heightError, abs(expectedHeight - measured), abs(view.bounds.height - measured))
                    used += expectedHeight + (index > 0 ? config.blockSpacing + extra : 0)
                    if index == 0 {
                        let minimumTop = config.safeInsets.top + config.topInset + (pageIndex == 0 ? config.headerHeight : 0)
                        topError = max(topError, minimumTop - view.convert(.zero, to: host.view).y)
                    }
                    for pair in zip(rows, rows.dropFirst()) {
                        within = max(within, abs(pair.1.baseline - pair.0.baseline - metrics.lineHeight - line - extra)); pairs += 1
                    }
                    if let first = rows.first, let previous = previousBaseline {
                        let delta = view.convert(CGPoint(x: 0, y: first.baseline), to: host.view).y - previous
                        across = max(across, abs(delta - metrics.lineHeight - line - extra - paragraph)); boundaries += 1
                    }
                    if let last = rows.last {
                        previousBaseline = view.convert(CGPoint(x: 0, y: last.baseline), to: host.view).y
                        let bottom = view.convert(CGPoint(x: 0, y: last.rect.minY + metrics.lineHeight), to: host.view).y
                        overflow = max(overflow, bottom - config.safeInsets.top - config.topInset - config.bodyHeight)
                    }
                    if count > 0 {
                        if let bubble = view.bubbleRect {
                            bubblesOK = bubblesOK && view.isBubble(at: CGPoint(x: bubble.midX, y: bubble.midY))
                                && !view.isBubble(at: CGPoint(x: bubble.maxX + 2, y: bubble.midY))
                                && bubble.maxY <= view.bounds.height + 0.75
                        } else { bubblesOK = false }
                    }
                    offset += text.count; rawJoined += text; shownJoined += actualDisplay
                    if atEnd { sourceIndex += 1; localOffset = 0 } else { localOffset = end }
                }
                let capacity = pageIndex == 0 ? config.firstPageBodyHeight : config.bodyHeight
                overflow = max(overflow, used - capacity)
                let target = config.pageSize.height - config.safeInsets.bottom - config.bottomInset
                    - config.footerHeight - config.footerGap - metrics.lineHeight + metrics.baseline
                if let actual = previousBaseline {
                    // Android only anchors pages that received a justified gap;
                    // sparse terminal pages intentionally keep their natural top.
                    if page.justifiedGap != nil {
                        anchoredPages += 1
                        bottomBaselineError = max(bottomBaselineError, abs(actual - target))
                        if pageIndex + 1 == pages.count {
                            terminalAnchors += 1
                            terminalBottomError = max(terminalBottomError, abs(actual - target))
                        }
                    }
                } else { sourceOK = false }
                if pageIndex == 0 {
                    func titleLabel(_ view: UIView) -> UILabel? {
                        if let label = view as? UILabel, label.accessibilityIdentifier == "chapter-title" { return label }
                        return view.subviews.lazy.compactMap { titleLabel($0) }.first
                    }
                    if let label = titleLabel(host.view) {
                        titleChecks += 1
                        titleTopError = max(titleTopError, abs(label.convert(.zero, to: host.view).y
                            - config.safeInsets.top - config.topInset))
                    } else { sourceOK = false }
                }
                samples.append(["font": Double(size), "page": pageIndex + 1, "rowsHeight": Double(used),
                    "unusedHeight": Double(capacity - used), "terminal": pageIndex + 1 == pages.count,
                    "actualBaseline": Double(previousBaseline ?? -1), "targetBaseline": Double(target)])
                window.isHidden = true; window.rootViewController = nil
            }
            sourceOK = sourceOK && sourceIndex == texts.count && localOffset == 0
                && rawJoined == texts.joined() && shownJoined == texts.map { ReaderTextLayout.displayText(for: $0) }.joined()
        }
        return ["pageSourceOK": sourceOK, "offsetsOK": offsetsOK, "actualLineSplitsOK": splitsOK,
            "continuationsOK": continuationOK, "pageCommentsOK": commentsOK, "pageBubblesOK": bubblesOK,
            "naturalPagesOK": naturalPages, "pageWithinError": Double(within), "pageAcrossError": Double(across),
            "pageHeightError": Double(heightError), "pageWidthError": Double(widthError),
            "pageOverflow": Double(overflow), "pageTopError": Double(topError),
            "pageBottomBaselineError": Double(bottomBaselineError), "terminalBottomError": Double(terminalBottomError),
            "titleTopError": Double(titleTopError), "anchoredPages": anchoredPages,
            "terminalAnchors": terminalAnchors, "titleChecks": titleChecks,
            "pages": pagesChecked, "nonterminalPages": nonterminals, "pagePairs": pairs,
            "pageBoundaries": boundaries, "splitChecks": splitChecks, "pageComments": comments, "pageSamples": samples]
    }

    private static func scrollHostReport() -> [String: Any] {
        let controller = ReaderContinuousScrollController()
        controller.update(ReaderContinuousScrollView(chapters: [ReaderScrollChapter(id: 0,
            revision: "dialogue", content: AnyView(TypographyScrollParagraphs(size: 19, spacing: 8)))],
            request: nil, layoutID: "dialogue", background: .white,
            onPosition: { _, _ in }, onApproachEdge: { _ in }))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 391, height: 700))
        window.rootViewController = controller; window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        let measurer = ReaderTextLayout.Measurer()
        let metrics = ReaderTextLayout.metrics(fontSize: 19)
        var widthError: CGFloat = 0, heightError: CGFloat = 0, baselineError: CGFloat = 0
        var paragraphs = 0, boundaries = 0, pairs = 0, sourceOK = true, bubbleOK = true
        for width in [CGFloat(391), 373.5] {
            window.frame.size.width = width
            controller.view.frame = window.bounds
            for _ in 0..<3 {
                controller.view.setNeedsLayout(); controller.view.layoutIfNeeded()
                controller.children.forEach { $0.view.layoutIfNeeded() }
            }
            let expectedWidth = width - 40
            let views = descendants(controller.view).sorted {
                $0.convert(.zero, to: controller.view).y < $1.convert(.zero, to: controller.view).y
            }
            sourceOK = sourceOK && views.count == TypographyFixtures.paragraphs.count
            for pair in zip(views, views.dropFirst()) {
                if let last = lines(pair.0).last, let first = lines(pair.1).first {
                    let delta = pair.1.convert(CGPoint(x: 0, y: first.baseline), to: controller.view).y
                        - pair.0.convert(CGPoint(x: 0, y: last.baseline), to: controller.view).y
                    baselineError = max(baselineError, abs(delta - metrics.lineHeight - 8 - 8)); boundaries += 1
                }
            }
            for (index, view) in views.enumerated() {
                guard index < TypographyFixtures.paragraphs.count else { sourceOK = false; continue }
                let text = TypographyFixtures.paragraphs[index]
                paragraphs += 1
                sourceOK = sourceOK && view.textStorage.string == text + " \u{FFFC}"
                widthError = max(widthError, abs(view.bounds.width - expectedWidth),
                    abs(view.renderedWidth - expectedWidth), abs(view.textContainer.size.width - expectedWidth),
                    abs(view.convert(.zero, to: controller.view).x - 20))
                heightError = max(heightError, abs(view.bounds.height - measurer.height(text: text, count: 82,
                    width: expectedWidth, fontSize: 19, lineSpacing: 8)))
                let rows = lines(view)
                for pair in zip(rows, rows.dropFirst()) {
                    baselineError = max(baselineError, abs(pair.1.baseline - pair.0.baseline - metrics.lineHeight - 8)); pairs += 1
                }
                if let bubble = view.bubbleRect {
                    bubbleOK = bubbleOK && view.isBubble(at: CGPoint(x: bubble.midX, y: bubble.midY))
                        && !view.isBubble(at: CGPoint(x: bubble.maxX + 2, y: bubble.midY))
                } else { bubbleOK = false }
            }
        }
        return ["scrollWidthError": Double(widthError), "scrollHeightError": Double(heightError),
            "scrollBaselineError": Double(baselineError), "scrollParagraphs": paragraphs,
            "scrollBoundaries": boundaries, "scrollPairs": pairs, "scrollSourceOK": sourceOK, "scrollBubbleOK": bubbleOK]
    }

    static func snapshot() -> String {
        precondition(Thread.isMainThread)
        let started = CFAbsoluteTimeGetCurrent()
        var report = naturalReport()
        report.merge(bubbleReport()) { _, value in value }
        report.merge(pageReport()) { _, value in value }
        report.merge(scrollHostReport()) { _, value in value }
        report["elapsedSeconds"] = CFAbsoluteTimeGetCurrent() - started
        guard let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]),
              let result = String(data: data, encoding: .utf8) else { return "invalid" }
        return result
    }
}


private enum ReferenceTypography {
    static let texts = [
        "洛城，秋。",
        "空洞的办公室里，惨白的白炽灯下，中年医生推了推鼻梁上的眼镜。",
        "“陈迹你好，我现在需要问你一些问题。你回答后，我会根据我的判断，按照‘无’、‘很轻’、‘中等’、‘严重’、‘非常严重’这五个程度来做出评分，可以吗？”",
        "“可以。”", "“你想结束生命吗？”", "“……结束谁的生命？”", "“你自己的。”", "“那没有。”",
        "中年医生迟疑片刻：“你是否记仇，是否很难原谅那些伤害过你的人？”", "“我不记仇。”",
        "“你是否会常常忘记事情，你是否会感到疲惫？”"
    ]
    static let counts = [99,82,99,46,55,99,31,37,42,99,82]
    static var blocks: [ContentBlock] { texts.enumerated().map {
        .paragraph(text: $0.element, commentCount: counts[$0.offset], commentURL: nil)
    } }
}

private struct ReferenceTypographyPage: View {
    var body: some View {
        GeometryReader { geometry in
            let config = configuration(geometry.size)
            let pages = ReaderPaginator.paginate(ReferenceTypography.blocks, configuration: config)
            if let page = pages.first {
                PageContentView(page: page, fontSize: 24, lineSpacing: 8,
                    fg: Color(red: 0.25, green: 0.24, blue: 0.21),
                    bg: Color(red: 0.98, green: 0.96, blue: 0.91), title: "1、归零",
                    pageNumber: 1, pageCount: pages.count, onTapComment: { _ in },
                    paragraphSpacing: 8, leftMargin: 16, rightMargin: 16,
                    topMargin: 90, bottomMargin: 30, showsChapterTitle: true)
            }
        }.ignoresSafeArea()
    }
    private func configuration(_ size: CGSize) -> ReaderPaginator.Configuration {
        var value = ReaderPaginator.Configuration(pageSize: size, fontSize: 24, lineSpacing: 8,
            paragraphSpacing: 8, leftInset: 16, rightInset: 16, topInset: 90, bottomInset: 30)
        value.chapterTitle = "1、归零"
        return value
    }
}
