import SwiftUI
import UIKit

/// Literal fragments and comment counts from the newly reported chapter 23, page 13/15.
/// They are NOT a claim that this synthetic fixture has the same preceding 12 pages.
private enum PunctuationFixture {
    static let title = "第23章 鬼面王"
    static let texts = [
        "面王损失一个核心队员，这是绝对的得不偿失！",
        "老赵，老赵！你听得见吗？\"",
        "砰——！",
        "井盖像是炮弹般被弹飞，冲天而起，黑洞洞的下水道口，一只狰狞的手臂猛地探出，紧接着一个比原先鬼面人大了数倍的怪物从中跃出！",
        "赵空城平静的看着这一幕，缓缓将手中的最后一块告示牌放下，咬破指尖，在告示牌表。涂上一横鲜血。",
        "“湘南，你还记得你曾立下的誓言吗......”",
        "赵空城注视着眼前的鬼面王，微微蹲下身，余光落在了"
    ]
    static let counts = [99, 99, 21, 57, 64, 99, 0]
    static var blocks: [ContentBlock] {
        texts.indices.map { .paragraph(text: texts[$0], commentCount: counts[$0], commentURL: nil) }
    }
    static func config(width: CGFloat, height: CGFloat = 874) -> ReaderPaginator.Configuration {
        ReaderPaginator.Configuration(pageSize: CGSize(width: width + 40, height: height),
            fontSize: 26, lineSpacing: 8, paragraphSpacing: 8,
            leftInset: 20, rightInset: 20, topInset: 70, bottomInset: 30)
    }
    static func quotePage(_ pages: [BookPage]) -> Int {
        // Prefer the page containing the literal six dots and attachment (rather
        // than a page with only the opening of a split, multi-page paragraph).
        pages.firstIndex { page in
            page.blocks.contains { block in
                if case .paragraph(let text, _, _) = block { return text.contains("......") }
                return false
            }
        } ?? pages.firstIndex { page in
            page.blocks.contains { block in
                if case .paragraph(let text, _, _) = block { return text.contains("湘南") }
                return false
            }
        } ?? max(pages.count - 1, 0)
    }
}

struct PunctuationFlowHarnessView: View {
    @State private var report = "pending"
    private var arguments: [String] { ProcessInfo.processInfo.arguments }

    var body: some View {
        if arguments.contains("--punctuation-flow-reference-page") {
            GeometryReader { geometry in
                let width: CGFloat = arguments.contains("--punctuation-flow-width-351") ? 351 : 362
                let config = PunctuationFixture.config(width: width, height: geometry.size.height)
                let pages = ReaderPaginator.paginate(PunctuationFixture.blocks, configuration: config)
                if !pages.isEmpty {
                    let requested = arguments.first { $0.hasPrefix("--punctuation-flow-page=") }
                        .flatMap { Int($0.dropFirst("--punctuation-flow-page=".count)) }
                    let index = min(max(requested ?? PunctuationFixture.quotePage(pages), 0), pages.count - 1)
                    PageContentView(page: pages[index], fontSize: 26, lineSpacing: 8,
                        fg: Color(red: 0.18, green: 0.18, blue: 0.17),
                        bg: Color(red: 0.985, green: 0.965, blue: 0.92),
                        title: PunctuationFixture.title, pageNumber: index + 1, pageCount: pages.count,
                        onTapComment: { _ in }, paragraphSpacing: 8,
                        leftMargin: 20, rightMargin: Double(config.pageSize.width - width - 20),
                        topMargin: 70, bottomMargin: 30)
                    .frame(width: config.pageSize.width, height: config.pageSize.height)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }.ignoresSafeArea().statusBarHidden(true)
        } else {
            VStack {
                Button("检查六点省略号、引号与段评换行") { report = PunctuationFlowInspection.snapshot() }
                    .accessibilityIdentifier("inspect-punctuation-flow")
                Text(report).font(.system(size: 6)).lineLimit(1)
                    .accessibilityIdentifier("punctuation-flow-report")
            }.frame(maxWidth: .infinity, maxHeight: .infinity).background(.white)
        }
    }
}

/// Inspect actual TextKit line fragments and glyph origins, not guessed character columns.
private enum PunctuationFlowInspection {
    private struct Row {
        let text: String
        let characters: NSRange
        let glyphs: NSRange
        let used: CGRect
    }
    private static func rows(_ view: CommentTextView) -> [Row] {
        let manager = view.layoutManager
        manager.ensureLayout(for: view.textContainer)
        let source = view.textStorage.string as NSString
        var output: [Row] = []
        manager.enumerateLineFragments(forGlyphRange: manager.glyphRange(for: view.textContainer)) {
            _, used, _, glyphs, _ in
            guard glyphs.length > 0 else { return }
            let range = manager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
            guard range.location >= 0, NSMaxRange(range) <= source.length else { return }
            output.append(Row(text: source.substring(with: range), characters: range,
                              glyphs: glyphs, used: used))
        }
        return output
    }
        private static func render(_ text: String, count: Int, width: CGFloat,
                               continuation: Bool = false) -> CommentTextView {
        let view = ReaderTextLayout.makeTextView()
        ReaderTextLayout.configure(view)
        view.render(text: text, count: count, fontSize: 26, lineSpacing: 8,
                    color: .black, continuation: continuation)
        let height = ReaderTextLayout.height(of: view, width: width)
        view.frame = CGRect(x: 0, y: 0, width: width, height: height)
        view.layoutIfNeeded()
        return view
    }
    private static func descendants(_ view: UIView) -> [CommentTextView] {
        if let text = view as? CommentTextView { return [text] }
        return view.subviews.flatMap { descendants($0) }
    }
    private static func glyph(_ index: Int, _ view: CommentTextView) -> Int? {
        guard index >= 0, index < view.textStorage.length else { return nil }
        return view.layoutManager.glyphIndexForCharacter(at: index)
    }
    private static func row(_ index: Int, _ view: CommentTextView, _ lines: [Row]) -> Int? {
        guard let g = glyph(index, view) else { return nil }
        return lines.firstIndex { NSLocationInRange(g, $0.glyphs) }
    }
    private static func x(_ index: Int, _ view: CommentTextView) -> CGFloat? {
        guard let g = glyph(index, view) else { return nil }
        return view.layoutManager.location(forGlyphAt: g).x
    }
    private static func number(_ n: CGFloat) -> Double { Double(n) }
    private static func mapped(_ raw: String, display: String) -> Bool {
        guard raw.utf16.count == display.utf16.count else { return false }
        let before = Array(raw.utf16), after = Array(display.utf16)
        for i in before.indices where before[i] != after[i] {
            guard before[i] == 0x22, after[i] == 0x201C || after[i] == 0x201D else { return false }
        }
        return true
    }
    private static func textAndAttachmentOK(_ raw: String, count: Int,
                                            _ view: CommentTextView) -> Bool {
        let displayed = view.textStorage.string
        let sourceLength = raw.utf16.count
        guard displayed.utf16.count == sourceLength + (count > 0 ? 2 : 0),
              mapped(raw, display: (displayed as NSString).substring(to: sourceLength)) else { return false }
        guard count > 0 else { return true }
        let location = sourceLength + 1
        return (displayed as NSString).substring(from: sourceLength) == " \u{FFFC}"
            && view.textStorage.attribute(.attachment, at: location, effectiveRange: nil) is NSTextAttachment
    }
    private static func detail(_ lines: [Row], width: CGFloat) -> [[String: Any]] {
        lines.map { ["text": $0.text, "utf16": $0.characters.location,
                     "usedX": number($0.used.maxX), "remaining": number(width - $0.used.maxX)] }
    }
    private static func cleanStart(_ line: String) -> Bool {
        // Used only for the CJK fixtures; Latin is measured separately against UIKit.
        guard let c = line.first else { return false }
        return !"，。、；：！？’”\"）】》〉」』〕］｝….!?,;:".contains(c)
    }
    private static func endCharacterWithBubble(_ raw: String, count: Int, width: CGFloat,
                                               _ view: CommentTextView, _ lines: [Row]) -> (Bool, Bool) {
        guard count > 0 else { return (true, false) }
        let lastIndex = raw.utf16.count - 1, bubbleIndex = raw.utf16.count + 1
        let sameRow = row(lastIndex, view, lines) == row(bubbleIndex, view, lines)
            && row(bubbleIndex, view, lines) != nil
        // A fresh row containing the last composed character + trailing punctuation +
        // separator + attachment can fit. This avoids imposing an impossible fit rule.
        let closing = "，。、；：！？,.!?;:’”\"'）】》〉」』〕］｝…"
        var start = raw.endIndex
        while start > raw.startIndex {
            start = raw.index(before: start)
            if !closing.contains(raw[start]) && !raw[start].isWhitespace { break }
        }
        let suffix = String(raw[start...])
        let trial = render(suffix, count: count, width: width, continuation: true)
        let trialRows = rows(trial)
        let eligible = trialRows.count == 1 && trialRows[0].text == ReaderTextLayout.displayText(for: suffix) + " \u{FFFC}"
        return (sameRow, eligible)
    }

    private static func inspect(_ raw: String, count: Int, width: CGFloat,
                                view: CommentTextView, id: String) -> [String: Any] {
        let lines = rows(view), manager = view.layoutManager
        let ns = view.textStorage.string as NSString
        let sourceLength = raw.utf16.count
        var violations: [String] = []
        var focus: [[String: Any]] = [], hanSteps: [CGFloat] = []
        var cjkGapOutliers: [[String: Any]] = []
        let punctuation = "，。、；：！？‘’“”——…"
        var attachmentCount = 0
        view.textStorage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: view.textStorage.length)) {
            value, _, _ in if value is NSTextAttachment { attachmentCount += 1 }
        }
        let sourceOK = textAndAttachmentOK(raw, count: count, view)
        if !sourceOK { violations.append("source-or-UTF16-mapping") }
        if attachmentCount != (count > 0 ? 1 : 0) { violations.append("attachment-count") }
        for (i, line) in lines.enumerated() {
            if i > 0 && !cleanStart(line.text) { violations.append("closing-punctuation-at-row-\(i)") }
            if line.text.trimmingCharacters(in: .whitespaces) == "\u{FFFC}" { violations.append("bubble-only-row-\(i)") }
            if i + 1 < lines.count && line.text.last.map({ "“‘（【《「『".contains($0) }) == true {
                violations.append("opening-punctuation-at-row-end-\(i)")
            }
            if line.used.maxX > width + 0.75 { violations.append("horizontal-overflow-row-\(i)") }
        }
        for i in 0..<min(sourceLength, ns.length) {
            let unit = ns.character(at: i)
            let isHan = (0x4E00...0x9FFF).contains(unit)
            if i + 1 < sourceLength, isHan, (0x4E00...0x9FFF).contains(ns.character(at: i + 1)),
               row(i, view, lines) == row(i + 1, view, lines),
               let a = x(i, view), let b = x(i + 1, view) { hanSteps.append(b - a) }
            if [0x22, 0x2E, 0x201C, 0x201D, 0x2026, 0x2014].contains(Int(unit)),
               let g = glyph(i, view), let position = x(i, view) {
                let font = view.textStorage.attribute(.font, at: i, effectiveRange: nil) as? UIFont
                let box = manager.boundingRect(forGlyphRange: NSRange(location: g, length: 1), in: view.textContainer)
                var sample: [String: Any] = ["u16": i, "text": ns.substring(with: NSRange(location: i, length: 1)),
                    "glyph": Int(manager.glyph(at: g)), "row": row(i, view, lines) ?? -1,
                    "x": number(position), "boxWidth": number(box.width), "font": font?.fontName ?? "missing",
                    "kern": (view.textStorage.attribute(.kern, at: i, effectiveRange: nil) as? NSNumber)?.doubleValue ?? 0]
                if i + 1 < ns.length, row(i, view, lines) == row(i + 1, view, lines), let next = x(i + 1, view) {
                    sample["advanceToNext"] = number(next - position)
                }
                focus.append(sample)
            }
        }
        // Do not force 100% line fill or exact N-column Han tracking. Detect actual
        // extra blank-sized holes; report the measured range for holistic redesign.
        if hanSteps.contains(where: { $0 < 26 * 0.7 || $0 > 26 * 1.5 }) { violations.append("odd-Han-intercharacter-gap") }
        let bubble = endCharacterWithBubble(raw, count: count, width: width, view, lines)
        if count > 0 && bubble.1 && !bubble.0 { violations.append("tail-and-bubble-separated-despite-fit") }
        var clusterRows: [Int] = [], dotSteps: [CGFloat] = []
        var closeAndBubble = true
        for marker in ["......", "……", "——"] {
            let range = (raw as NSString).range(of: marker)
            guard range.location != NSNotFound else { continue }
            let indices = Array(range.location..<NSMaxRange(range))
            let foundRows = indices.compactMap { row($0, view, lines) }
            clusterRows = foundRows
            if foundRows.count != indices.count || Set(foundRows).count != 1 { violations.append("split-cluster-\(marker)") }
            if marker == "......" {
                for (left, right) in zip(indices, indices.dropFirst()) {
                    if row(left, view, lines) == row(right, view, lines), let a = x(left, view), let b = x(right, view) {
                        dotSteps.append(b - a)
                    }
                }
                if let low = dotSteps.min(), let high = dotSteps.max(), low <= 0 || high > 26 * 0.55 || high - low > 0.75 {
                    violations.append("six-dots-have-intercharacter-holes")
                }
            }
            if marker != "——", count > 0 {
                let closeIndex = NSMaxRange(range)
                if closeIndex < sourceLength, [0x22, 0x201D].contains(Int((raw as NSString).character(at: closeIndex))) {
                    closeAndBubble = row(range.location, view, lines) == row(closeIndex, view, lines)
                        && row(closeIndex, view, lines) == row(sourceLength + 1, view, lines)
                        && row(closeIndex, view, lines) != nil
                    // These short clusters fit a fresh row at both requested widths.
                    if !closeAndBubble { violations.append("ellipsis-closing-quote-bubble-not-together") }
                }
            }
        }
        let last = lines.last
        var bubbleDetail: [String: Any] = [:]
        if count > 0, let g = glyph(sourceLength + 1, view) {
            let box = manager.boundingRect(forGlyphRange: NSRange(location: g, length: 1), in: view.textContainer)
            bubbleDetail = ["utf16": sourceLength + 1, "glyph": g,
                "row": row(sourceLength + 1, view, lines) ?? -1,
                "x": number(box.minX), "y": number(box.minY),
                "width": number(box.width), "height": number(box.height)]
        }
        return ["id": id, "width": number(width), "raw": raw, "count": count,
                "attachment": bubbleDetail, "sourceOK": sourceOK, "rawUTF16": sourceLength, "storageUTF16": ns.length,
                "rows": detail(lines, width: width), "focusGlyphs": focus,
                "hanPairs": hanSteps.count, "hanStepMin": number(hanSteps.min() ?? 0),
                "hanStepMax": number(hanSteps.max() ?? 0), "clusterRows": clusterRows,
                "dotSteps": dotSteps.map(number), "tailFits": bubble.1,
                "tailAndBubbleSameRow": bubble.0, "quoteClosesWithBubble": closeAndBubble,
                "lastLineRemaining": number(last.map { width - $0.used.maxX } ?? 0),
                "violations": violations]
    }

        static func snapshot() -> String {
        precondition(Thread.isMainThread)
        var cases: [[String: Any]] = [], pagesReport: [[String: Any]] = []
        var sourceOK = true, offsetsOK = true, renderOK = true, terminalNatural = true
        var totalPages = 0, pageParagraphs = 0, continuationPieces = 0
        let joined = PunctuationFixture.texts.joined()
        for width in [CGFloat(351), CGFloat(362)] {
            for index in PunctuationFixture.texts.indices {
                let raw = PunctuationFixture.texts[index], count = PunctuationFixture.counts[index]
                cases.append(inspect(raw, count: count, width: width,
                    view: render(raw, count: count, width: width, continuation: index == 0),
                    id: "screenshot-\(index)"))
            }
            // U+201C is a curved opening quotation mark; U+0022 is the straight one.
            // Exercise both, including the mixed pairs rather than guessing the source.
            for (name, open, close) in [("curly", "“", "”"), ("ascii", "\"", "\""),
                                         ("curly-ascii", "“", "\""), ("ascii-curly", "\"", "”")] {
                for (suffix, marks) in [("six-dots", "......"), ("two-ellipsis", "……")] {
                    let raw = open + "湘南，你还记得你曾立下的誓言吗" + marks + close
                    cases.append(inspect(raw, count: 99, width: width,
                        view: render(raw, count: 99, width: width), id: "\(name)-\(suffix)"))
                }
            }
            let config = PunctuationFixture.config(width: width)
            let pages = ReaderPaginator.paginate(PunctuationFixture.blocks, configuration: config)
            totalPages += pages.count
            var reconstructed = "", characterOffset = 0, utf16Offset = 0
            var counts: [Int] = [], boundaries: [String] = []
            for (pageIndex, page) in pages.enumerated() {
                offsetsOK = offsetsOK && page.startOffset == characterOffset
                if pageIndex == pages.count - 1 { terminalNatural = terminalNatural && page.justifiedGap == nil }
                let host = UIHostingController(rootView: PageContentView(page: page,
                    fontSize: 26, lineSpacing: 8, fg: .black, bg: .white, title: PunctuationFixture.title,
                    pageNumber: pageIndex + 1, pageCount: pages.count, onTapComment: { _ in },
                    paragraphSpacing: 8, leftMargin: 20, rightMargin: 20, topMargin: 70, bottomMargin: 30))
                let window = UIWindow(frame: CGRect(origin: .zero, size: config.pageSize))
                window.rootViewController = host
                window.isHidden = false
                host.view.frame = window.bounds
                for _ in 0..<3 { host.view.setNeedsLayout(); host.view.layoutIfNeeded() }
                let views = descendants(host.view).sorted {
                    $0.convert(.zero, to: host.view).y < $1.convert(.zero, to: host.view).y
                }
                renderOK = renderOK && views.count == page.blocks.count
                    && page.blockHeights.count == page.blocks.count
                var blockReports: [[String: Any]] = []
                for (blockIndex, block) in page.blocks.enumerated() {
                    guard case let .paragraph(raw, count, _) = block else { renderOK = false; continue }
                    reconstructed += raw
                    characterOffset += raw.count
                    utf16Offset += raw.utf16.count
                    if count > 0 { counts.append(count) }
                    if page.continuationIndices.contains(blockIndex) { continuationPieces += 1 }
                    if blockIndex == 0, pageIndex > 0, !cleanStart(raw) { boundaries.append(raw) }
                    guard blockIndex < views.count else { continue }
                    let view = views[blockIndex]
                    renderOK = renderOK && abs(view.bounds.width - width) <= 0.75
                    let expected = page.displayParagraphs[blockIndex] ?? ReaderTextLayout.displayText(for: raw)
                    sourceOK = sourceOK && mapped(raw, display: expected)
                        && view.textStorage.string == expected + (count > 0 ? " \u{FFFC}" : "")
                    pageParagraphs += 1
                    let result = inspect(raw, count: count, width: width, view: view,
                                         id: "page-\(pageIndex)-block-\(blockIndex)")
                    blockReports.append(result)
                    cases.append(result)
                }
                pagesReport.append(["width": number(width), "page": pageIndex, "pageCount": pages.count,
                    "startOffset": page.startOffset, "endUTF16": utf16Offset,
                    "extraLineSpacing": page.justifiedGap ?? 0, "blocks": blockReports.map { $0["id"] as! String },
                    "badPageStarts": boundaries])
                window.isHidden = true
                window.rootViewController = nil
            }
            sourceOK = sourceOK && Array(reconstructed.utf16) == Array(joined.utf16)
                && counts == PunctuationFixture.counts.filter { $0 > 0 }
            offsetsOK = offsetsOK && utf16Offset == joined.utf16.count && boundaries.isEmpty
        }
        var latin: [[String: Any]] = []
        var latinOK = true, maxLatinAdvanceError: CGFloat = 0
        for raw in ["6\" × 12\"", "The \"report\" is fine.", "don't change this", "wait...... done", "https://example.com/a.b"] {
            let actual = render(raw, count: 0, width: 362)
            let native = ReaderTextLayout.makeTextView()
            ReaderTextLayout.configure(native)
            let style = actual.textStorage.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as! NSParagraphStyle
            native.attributedText = NSAttributedString(string: raw, attributes: [
                .font: UIFont.systemFont(ofSize: 26), .paragraphStyle: style])
            native.textContainer.size = CGSize(width: 362, height: 1000)
            let a = rows(actual), b = rows(native)
            var error: CGFloat = 0
            let equalText = actual.textStorage.string == raw && ReaderTextLayout.displayText(for: raw) == raw
            var glyphsEqual = true
            for i in 0..<raw.utf16.count {
                if let ag = glyph(i, actual), let bg = glyph(i, native) {
                    glyphsEqual = glyphsEqual && actual.layoutManager.glyph(at: ag) == native.layoutManager.glyph(at: bg)
                } else { glyphsEqual = false }
                if i + 1 < raw.utf16.count, row(i, actual, a) == row(i + 1, actual, a),
                   row(i, native, b) == row(i + 1, native, b),
                   let a0 = x(i, actual), let a1 = x(i + 1, actual), let b0 = x(i, native), let b1 = x(i + 1, native) {
                    error = max(error, abs((a1 - a0) - (b1 - b0)))
                }
            }
            maxLatinAdvanceError = max(maxLatinAdvanceError, error)
            latinOK = latinOK && equalText && glyphsEqual && a.map(\.text) == b.map(\.text) && error <= 0.25
            latin.append(["text": raw, "unchanged": equalText, "glyphsEqual": glyphsEqual, "advanceError": number(error)])
        }
        // Deliberately low pages exercise source/UTF16 reconstruction and offsets at
        // splits. No fabricated page13/15, no mutation of raw paragraph text.
        let unicodeRaw = "“湘南👩🏽‍🚀，" + String(repeating: "你还记得你曾立下的誓言吗，", count: 5) + "吗......”"
        let stress = ReaderPaginator.paginate([.paragraph(text: unicodeRaw, commentCount: 99, commentURL: nil)],
            configuration: PunctuationFixture.config(width: 351, height: 300))
        var rebuilt = "", stressOffset = 0, stressBubbleCount = 0, stressBoundaries: [String] = []
        for (pageIndex, page) in stress.enumerated() {
            offsetsOK = offsetsOK && page.startOffset == stressOffset
            for block in page.blocks {
                guard case let .paragraph(text, count, _) = block else { continue }
                if pageIndex > 0, !cleanStart(text) || text.hasPrefix(".") { stressBoundaries.append(text) }
                rebuilt += text
                stressOffset += text.count
                if count > 0 { stressBubbleCount += 1 }
            }
        }
        let stressSourceOK = Array(rebuilt.utf16) == Array(unicodeRaw.utf16) && stressBubbleCount == 1
        let failures = cases.compactMap { sample -> [String: Any]? in
            guard let violations = sample["violations"] as? [String], !violations.isEmpty else { return nil }
            return ["id": sample["id"]!, "width": sample["width"]!, "violations": violations]
        }
        let report: [String: Any] = ["schema": 1, "font": 26, "widths": [351, 362],
            "lineSpacing": 8, "paragraphSpacing": 8,
            "firstFragment": "isolated continuation; paginated fixture starts a synthetic paragraph",
            "texts": PunctuationFixture.texts, "counts": PunctuationFixture.counts,
            "cases": cases, "failures": failures, "pages": pagesReport,
            "pageSourceOK": sourceOK, "offsetsOK": offsetsOK, "renderOK": renderOK,
            "terminalNatural": terminalNatural, "renderedPages": totalPages,
            "pageParagraphs": pageParagraphs, "continuationPieces": continuationPieces,
            "latinOK": latinOK, "latin": latin, "maxLatinAdvanceError": number(maxLatinAdvanceError),
            "stressPages": stress.count, "stressSourceOK": stressSourceOK, "stressBadPageStarts": stressBoundaries]
        guard JSONSerialization.isValidJSONObject(report),
              let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8) else { return "invalid-json" }
        return string.replacingOccurrences(of: "\u{FFFC}", with: "\\ufffc")
    }
}
