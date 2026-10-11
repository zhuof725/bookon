import UIKit
import CoreText

/// 渲染与分页共用 TextKit 1 的真实字形与换行；不拉伸字格、行距或更改原文。
enum ReaderTextLayout {
    fileprivate static let baselineKey = NSAttributedString.Key("ReaderTextBaseline")
    fileprivate static let commentTailKey = NSAttributedString.Key("ReaderCommentTailStart")
    fileprivate static let zhLayoutKey = NSAttributedString.Key("ReaderZhLayout")
    fileprivate static let fullJustifyKey = NSAttributedString.Key("ReaderFullJustify")
    fileprivate static let paragraphEndKey = NSAttributedString.Key("ReaderParagraphEnd")

    struct Metrics {
        let font: UIFont
        let cjkFont: UIFont
        let quoteFont: UIFont
        let cellWidth: CGFloat
        let indentWidth: CGFloat
        let tracking: CGFloat
        let lineHeight: CGFloat
        let baseline: CGFloat
    }

    private struct Fonts {
        let body: UIFont
        let cjk: UIFont
        let quote: UIFont
        let advance: CGFloat
        let ascent: CGFloat
        let descent: CGFloat
    }

    private static func advance(of text: String, font: UIFont) -> CGFloat {
        // 量 feature 生效后的字形，不能把引号一律当作半角再补半格：fwid 可能已给它一整格。
        let sample = NSAttributedString(string: text, attributes: [.font: font, .kern: 0, .ligature: 0])
        return CGFloat(CTLineGetTypographicBounds(CTLineCreateWithAttributedString(sample), nil, nil, nil))
    }

    // UIKit 排版入口均在主线程；分页二分测量不重复解析字体。
    private static var fontCache: [CGFloat: Fonts] = [:]

    static func metrics(fontSize: CGFloat, width: CGFloat? = nil) -> Metrics {
        let size = fontSize.isFinite ? max(fontSize, 1) : 19
        let fonts: Fonts
        if let cached = fontCache[size] {
            fonts = cached
        } else {
            let body = UIFont.systemFont(ofSize: size)
            let fallback = CTFontCreateForString(body as CTFont, "汉" as CFString,
                                                CFRange(location: 0, length: 1))
            // 系统 fallback 会随设备语言选择 PingFang HK/TC：其句读可能居中。
            // 阅读正文采用简体横排字形，让句读落在左下、开闭标点贴向文字侧。
            // 仍由字体提供 ink bearings，不移动 glyph origin 或破坏整格 advance。
            let cjk = UIFont(name: "PingFangSC-Regular", size: size)
                ?? UIFont(name: CTFontCopyPostScriptName(fallback) as String, size: size) ?? body
            let emoji = UIFont(name: "AppleColorEmoji", size: size) ?? body
            let bubbleBounds = CommentBubble.attachmentBounds(fontSize: size)
            // Reserve the SAME reference-bubble extents on every row, including
            // rows without comments: a last-row bubble must not move the baseline.
            let ascent = max(max(body.ascender, cjk.ascender),
                             max(emoji.ascender, bubbleBounds.maxY))
            let descent = max(max(-body.descender, -cjk.descender),
                              max(-emoji.descender, -bubbleBounds.minY))
            // PingFang 负责字形、标点侧边留白和天然 advance；没有宽度均分或逐字 kern。
            fonts = Fonts(body: body, cjk: cjk, quote: cjk,
                          advance: max(advance(of: "汉", font: cjk), 1),
                          ascent: ascent, descent: descent)
            fontCache[size] = fonts
        }
        let height = ceil(fonts.ascent + fonts.descent)
        let indent = advance(of: "　", font: fonts.cjk)
        return Metrics(font: fonts.body, cjkFont: fonts.cjk, quoteFont: fonts.quote, cellWidth: fonts.advance,
                       indentWidth: max(indent, fonts.advance), tracking: 0, lineHeight: height,
                       baseline: fonts.ascent + (height - fonts.ascent - fonts.descent) * 0.5)
    }

    /// Android ReadBookConfig stores line spacing as a tenth of the natural
    /// line-height multiplier (10 means 1.0H). TextKit wants the extra point
    /// distance between line fragments, so convert at the shared layout edge.
    static func androidLineSpacingPoints(fontSize: CGFloat, setting: CGFloat) -> CGFloat {
        let height = metrics(fontSize: fontSize).lineHeight
        let multiplier = max(setting, 0) / 10
        return max(height * multiplier - height, -height * 0.95)
    }

    /// Android paragraph spacing is also expressed in tenths of the actual
    /// font height, rather than as a raw point value.
    static func androidParagraphSpacingPoints(fontSize: CGFloat, setting: CGFloat) -> CGFloat {
        metrics(fontSize: fontSize).lineHeight * max(setting, 0) / 10
    }

    /// 只给单标量字符加字距；组合字符、变体选择符、ZWJ 和 Latin run 不拆开。
    private static func isGridScalar(_ scalar: UInt32) -> Bool {
        switch scalar {
        case 0x2E80...0x303F, 0x3040...0x30FF, 0x3100...0x312F, 0x31A0...0x31BF,
             0x31F0...0x31FF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF,
             0xFE10...0xFE1F, 0xFE30...0xFE4F, 0xFF01...0xFF60, 0xFFE0...0xFFE6,
             0x20000...0x323AF:
            return true
        default:
            return false
        }
    }

    static func attributedText(text: String, count: Int, fontSize: CGFloat,
                               lineSpacing: CGFloat, color: UIColor,
                               continuation: Bool = false, width: CGFloat? = nil,
                               fullJustify: Bool = false, zhLayout: Bool = false,
                               paragraphEnd: Bool = true) -> NSAttributedString {
        let grid = metrics(fontSize: fontSize, width: width)
        let style = NSMutableParagraphStyle()
        // `lineSpacing` is already the point value shared by pagination and
        // rendering. Negative values are valid for Android's lower settings,
        // but never allow a line fragment to collapse completely.
        style.lineSpacing = max(lineSpacing, -grid.lineHeight * 0.95)
        style.minimumLineHeight = grid.lineHeight
        style.maximumLineHeight = grid.lineHeight
        // Android adds paragraph spacing outside the paragraph's line layout;
        // the page/scroll containers do the same on iOS.
        style.paragraphSpacing = 0
        style.alignment = fullJustify ? .justified : .left
        // 只在显示副本中将纯中文成对 U+0022 识别为开/闭引号；原始正文不动，
        // 每个替换仍占一个 UTF-16 单元，分页、进度和命中索引一一对应。
        let displayed = displayText(for: text)
        style.lineBreakMode = .byWordWrapping
        style.lineBreakStrategy = []
        style.hyphenationFactor = 0
        style.headIndent = 0
        style.tailIndent = 0
        // Android ContentProcessor inserts two full-width spaces before each
        // paragraph. Measuring the same glyph keeps the indent out of justify
        // distribution while preserving the source character offsets.
        style.firstLineHeadIndent = continuation ? 0 : grid.indentWidth * 2
        let attrs: [NSAttributedString.Key: Any] = [
            .font: grid.font,
            .foregroundColor: color,
            .paragraphStyle: style,
            baselineKey: NSNumber(value: Double(grid.baseline)),
            zhLayoutKey: NSNumber(value: zhLayout),
            fullJustifyKey: NSNumber(value: fullJustify),
            paragraphEndKey: NSNumber(value: paragraphEnd)
        ]
        let result = NSMutableAttributedString(string: displayed, attributes: attrs)
        // 中文与中文标点统一使用 PingFang SC 的原始横排字形，不设置 fwid、
        // kern、ligature 或逐字 glyph 位置；Latin / emoji 仍交给系统字体塑形。
        let hasCJK = displayed.unicodeScalars.contains { (0x3400...0x9FFF).contains($0.value) }
        let marks = CharacterSet(charactersIn: "‘’“”—…·")
        var offset = 0
        var runStart: Int?
        func finishFontRun() {
            if let start = runStart {
                result.addAttribute(.font, value: grid.cjkFont, range: NSRange(location: start, length: offset - start))
            }
            runStart = nil
        }
        for character in displayed {
            let scalar = character.unicodeScalars.count == 1 ? character.unicodeScalars.first : nil
            let isCJK = scalar.map { isGridScalar($0.value) || (hasCJK && marks.contains($0)) } ?? false
            if isCJK { if runStart == nil { runStart = offset } }
            else { finishFontRun() }
            offset += String(character).utf16.count
        }
        finishFontRun()
        if count > 0 {
            // Keep the existing one-character separator for UTF-16 mapping,
            // but give it zero advance. The reference bubble already has 1pt
            // optical inset at 23pt; the old quarter-em gap displaced it.
            var gapAttributes = attrs
            gapAttributes[.kern] = -advance(of: " ", font: grid.font)
            result.append(NSAttributedString(string: " ", attributes: gapAttributes))
            let image = CommentBubble.image(count: count, fontSize: fontSize, color: color)
            let attachment = NSTextAttachment()
            attachment.image = image
            attachment.bounds = CommentBubble.attachmentBounds(fontSize: fontSize)
            let bubble = NSMutableAttributedString(attachment: attachment)
            bubble.addAttributes(attrs, range: NSRange(location: 0, length: bubble.length))
            result.append(bubble)
            // 段评与最后一个完整字符及尾随句读一起换行，不让附件自己占一行。
            // 原文、分隔字符和 UTF-16 索引均不改变；只限制排版断点。
            if let start = commentTailStart(in: text) {
                let tail = NSRange(location: start, length: result.length - start)
                let sample = result.attributedSubstring(from: NSRange(location: start, length: tail.length - 1))
                // CoreText 不会自动计入 UIKit NSTextAttachment 的图像宽度。
                let tailWidth = CGFloat(CTLineGetTypographicBounds(CTLineCreateWithAttributedString(sample), nil, nil, nil))
                    + attachment.bounds.width
                let usableWidth = width.map { max($0 - (start == 0 ? style.firstLineHeadIndent : 0), 1) }
                if let usableWidth, tailWidth <= usableWidth {
                    result.addAttribute(commentTailKey, value: start, range: tail)
                }
            }
        }
        return result
    }

    static func displayText(for original: String) -> String {
        let replacements = chineseDialogueQuotes(in: original)
        guard !replacements.isEmpty else { return original }
        let copy = NSMutableString(string: original)
        for (index, opening) in replacements {
            copy.replaceCharacters(in: NSRange(location: index, length: 1), with: opening ? "“" : "”")
        }
        return copy as String
    }

    private static func chineseDialogueQuotes(in text: String) -> [(Int, Bool)] {
        let scalars = Array(text.unicodeScalars)
        guard scalars.contains(where: { (0x4E00...0x9FFF).contains($0.value) }),
              scalars.contains(where: { $0.value == 0x22 }) else { return [] }
        // 纯中文才处理；英文引用、网址和 6\" × 12\" 尺寸保留原貌。
        guard !scalars.contains(where: {
            (CharacterSet.letters.contains($0) && !isGridScalar($0.value))
                || CharacterSet.decimalDigits.contains($0) || $0.value == 0x2F || $0.value == 0x5C
        }) else { return [] }
        var offset = 0
        var pending: (offset: Int, isASCII: Bool)?
        var replacements: [(Int, Bool)] = []
        let stops = CharacterSet(charactersIn: "。！？!?….")
        for (index, scalar) in scalars.enumerated() {
            defer { offset += scalar.value > 0xFFFF ? 2 : 1 }
            if scalar.value == 0x201C {
                pending = (offset, false)
            } else if scalar.value == 0x201D {
                if let opening = pending, opening.isASCII { replacements.append((opening.offset, true)) }
                pending = nil
            } else if scalar.value == 0x22 {
                if let opening = pending {
                    if opening.isASCII { replacements.append((opening.offset, true)) }
                    replacements.append((offset, false))
                    pending = nil
                } else if index > 0, stops.contains(scalars[index - 1]),
                          scalars[(index + 1)...].allSatisfy({ CharacterSet.whitespacesAndNewlines.contains($0) }) {
                    // 对话可能跨原文段落；句末标点后的最终直引号是明确的结束角色。
                    replacements.append((offset, false))
                } else {
                    pending = (offset, true)
                }
            }
        }
        // 未配对的起始直引号不猜测，避免改写正文语义；所有替换仍为单 UTF-16 单元。
        return replacements
    }

    private static func commentTailStart(in text: String) -> Int? {
        guard !text.isEmpty else { return nil }
        let closing = CharacterSet(charactersIn: "，。、；：！？,.!?;:’”\"'）】》〉」』〕］｝…")
        var boundary = text.endIndex
        var suffixCount = 0
        while boundary > text.startIndex {
            let previous = text.index(before: boundary)
            let character = text[previous]
            if character.isNewline { return nil }
            let isClosing = character.unicodeScalars.allSatisfy { closing.contains($0) }
            boundary = previous
            suffixCount += 1
            if !isClosing && !character.isWhitespace { return text[..<boundary].utf16.count }
            if suffixCount > 12 { return nil }
        }
        return 0
    }

    /// 显式使用 TextKit 1，避免测量器和 iOS 16+ UITextView 的默认引擎不同。
    static func makeTextView() -> CommentTextView {
        let storage = NSTextStorage()
        let manager = NSLayoutManager()
        manager.usesFontLeading = false
        manager.delegate = ReaderLineMetrics.shared
        storage.addLayoutManager(manager)
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        manager.addTextContainer(container)
        return CommentTextView(frame: .zero, textContainer: container)
    }

    static func configure(_ view: UITextView) {
        view.backgroundColor = .clear
        view.isEditable = false
        view.isSelectable = false
        view.isScrollEnabled = false
        view.showsVerticalScrollIndicator = false
        view.showsHorizontalScrollIndicator = false
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
    }

    /// Canonical paragraph bounds end at the last line box, not TextKit's trailing
    /// line-fragment spacing. Pagination, intrinsic sizing and scroll use these bounds.
    /// Every following paragraph explicitly adds lineSpacing + paragraphSpacing.
    static func paragraphGap(lineSpacing: CGFloat, paragraphSpacing: CGFloat) -> CGFloat {
        // Android advances after the final row by H * lineSpacingExtra and
        // then adds H * paragraphSpacing. Keep a negative line increment when
        // the user selects a value below 1.0H instead of silently dropping it.
        lineSpacing + max(paragraphSpacing, 0)
    }

    static func height(of view: UITextView, width: CGFloat) -> CGFloat {
        _ = view.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return rows(of: view).height
    }

    private static func rows(of view: UITextView) -> (count: Int, height: CGFloat) {
        let manager = view.layoutManager
        manager.ensureLayout(for: view.textContainer)
        var count = 0
        var bottom: CGFloat = 0
        manager.enumerateLineFragments(forGlyphRange: manager.glyphRange(for: view.textContainer)) {
            rect, used, _, glyphs, _ in
            guard glyphs.length > 0 else { return }
            count += 1
            let index = manager.characterIndexForGlyph(at: glyphs.location)
            let style = view.textStorage.attribute(.paragraphStyle, at: index,
                effectiveRange: nil) as? NSParagraphStyle
            bottom = rect.minY + (style?.minimumLineHeight ?? used.height)
        }
        return (count, bottom)
    }

    /// 一个分页请求复用一个测量 UITextView；必须在主线程使用。
    final class Measurer {
        private let view: CommentTextView
        init() {
            precondition(Thread.isMainThread)
            view = ReaderTextLayout.makeTextView()
            ReaderTextLayout.configure(view)
        }
        /// 不含末行之后的行距；与固定正文块 frame 共用实际 TextKit 行原点。
        func rows(text: String, count: Int, width: CGFloat, fontSize: CGFloat,
                  lineSpacing: CGFloat, continuation: Bool,
                  fullJustify: Bool = false, zhLayout: Bool = false,
                  paragraphEnd: Bool = true) -> (count: Int, height: CGFloat) {
            _ = height(text: text, count: count, width: width, fontSize: fontSize,
                       lineSpacing: lineSpacing, continuation: continuation,
                       fullJustify: fullJustify, zhLayout: zhLayout,
                       paragraphEnd: paragraphEnd)
            return ReaderTextLayout.rows(of: view)
        }

        func height(text: String, count: Int, width: CGFloat, fontSize: CGFloat,
                    lineSpacing: CGFloat, continuation: Bool = false,
                    fullJustify: Bool = false, zhLayout: Bool = false,
                    paragraphEnd: Bool = true) -> CGFloat {
            view.render(text: text, count: count, fontSize: fontSize, lineSpacing: lineSpacing,
                        color: .black, continuation: continuation,
                        fullJustify: fullJustify, zhLayout: zhLayout,
                        paragraphEnd: paragraphEnd)
            return ReaderTextLayout.height(of: view, width: width)
        }
    }
}

/// TextKit 负责原生塑形、合法断行和附件；代理只固定混排基线，不改写逐字位置。
/// NSLayoutManager.delegate 是弱引用，静态实例确保渲染器/分页器始终使用同一规则。
private final class ReaderLineMetrics: NSObject, NSLayoutManagerDelegate {
    static let shared = ReaderLineMetrics()

    func layoutManager(_ layoutManager: NSLayoutManager,
                       shouldBreakLineByWordBeforeCharacterAt charIndex: Int) -> Bool {
        allowsBreak(layoutManager, at: charIndex)
    }

    func layoutManager(_ layoutManager: NSLayoutManager,
                       shouldBreakLineByHyphenatingBeforeCharacterAt charIndex: Int) -> Bool {
        allowsBreak(layoutManager, at: charIndex)
    }

    private func allowsBreak(_ manager: NSLayoutManager, at index: Int) -> Bool {
        guard let storage = manager.textStorage, index > 0, index < storage.length else { return true }
        if let start = storage.attribute(ReaderTextLayout.commentTailKey, at: index,
                                         effectiveRange: nil) as? Int, index > start { return false }
        return true
    }

    func layoutManager(_ manager: NSLayoutManager, didCompleteLayoutFor container: NSTextContainer?,
                       atEnd layoutFinishedFlag: Bool) {
        guard let container, let storage = manager.textStorage else { return }
        let width = container.size.width
        guard width.isFinite, width > 0 else { return }
        let source = storage.string as NSString
        var rows: [(CGRect, CGRect, NSRange)] = []
        manager.enumerateLineFragments(forGlyphRange: manager.glyphRange(for: container)) {
            rect, used, _, glyphs, _ in
            guard glyphs.length > 0 else { return }
            rows.append((rect, used, glyphs))
        }
        for (rect, used, glyphs) in rows {
            let start = manager.characterIndexForGlyph(at: glyphs.location)
            guard start < storage.length,
                  (storage.attribute(ReaderTextLayout.fullJustifyKey, at: start, effectiveRange: nil) as? NSNumber)?.boolValue == true
            else { continue }
            let chars = manager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
            let paragraphEnd = (storage.attribute(ReaderTextLayout.paragraphEndKey, at: start,
                                                    effectiveRange: nil) as? NSNumber)?.boolValue ?? true
            // A real paragraph's final row remains natural. A page fragment
            // marked paragraphEnd=false is continued on the next page, so its
            // visible final row follows Android's middle-row justification.
            if paragraphEnd && NSMaxRange(chars) >= source.length { continue }
            let remainder = rect.maxX - used.maxX
            guard remainder > 0.25 else { continue }
            var boundaries = Set<Int>()
            for glyph in (glyphs.location + 1)..<NSMaxRange(glyphs) {
                let previous = manager.characterIndexForGlyph(at: glyph - 1)
                let current = manager.characterIndexForGlyph(at: glyph)
                guard previous < source.length, current < source.length else { continue }
                let prev = Int(source.character(at: previous))
                let next = Int(source.character(at: current))
                if (0x4E00...0x9FFF).contains(prev), (0x4E00...0x9FFF).contains(next) {
                    boundaries.insert(glyph)
                }
            }
            guard !boundaries.isEmpty else { continue }
            let extra = remainder / CGFloat(boundaries.count)
            let positions = (glyphs.location..<NSMaxRange(glyphs)).map { manager.location(forGlyphAt: $0) }
            var shift: CGFloat = 0
            for (offset, position) in positions.enumerated() {
                let glyph = glyphs.location + offset
                if boundaries.contains(glyph) { shift += extra }
                manager.setLocation(CGPoint(x: position.x + shift, y: position.y),
                                    forStartOfGlyphRange: NSRange(location: glyph, length: 1))
            }
            var filled = used
            filled.size.width += remainder
            manager.setLineFragmentRect(rect, forGlyphRange: glyphs, usedRect: filled)
        }
    }

    func layoutManager(_ layoutManager: NSLayoutManager,
                       shouldSetLineFragmentRect lineFragmentRect: UnsafeMutablePointer<CGRect>,
                       lineFragmentUsedRect: UnsafeMutablePointer<CGRect>,
                       baselineOffset: UnsafeMutablePointer<CGFloat>,
                       in textContainer: NSTextContainer, forGlyphRange glyphRange: NSRange) -> Bool {
        guard glyphRange.length > 0, let storage = layoutManager.textStorage else { return false }
        let index = layoutManager.characterIndexForGlyph(at: glyphRange.location)
        guard index < storage.length,
              let baseline = storage.attribute(ReaderTextLayout.baselineKey, at: index,
                                               effectiveRange: nil) as? NSNumber,
              let style = storage.attribute(.paragraphStyle, at: index,
                                            effectiveRange: nil) as? NSParagraphStyle else { return false }
        // 仅修改 baselineOffset 不足以抑制混合字体的自然行框差异；下一行起点由
        // lineFragmentRect 决定，必须与已预留所有字形/附件的统一行高一致。
        let height = style.minimumLineHeight
        lineFragmentRect.pointee.size.height = height + style.lineSpacing
        lineFragmentUsedRect.pointee.origin.y = lineFragmentRect.pointee.minY
        lineFragmentUsedRect.pointee.size.height = height
        baselineOffset.pointee = CGFloat(baseline.doubleValue)
        return true
    }
}
