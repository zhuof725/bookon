import UIKit
import CoreText

/// 渲染和分页共用 TextKit 1。只修改属性，不插入字格占位符或改写原文。
enum ReaderTextLayout {
    fileprivate static let baselineKey = NSAttributedString.Key("ReaderTextBaseline")
    fileprivate static let commentTailKey = NSAttributedString.Key("ReaderCommentTailStart")
    fileprivate static let quoteOpeningKey = NSAttributedString.Key("ReaderASCIIQuoteOpening")

    struct Metrics {
        let font: UIFont
        let cjkFont: UIFont
        let quoteFont: UIFont
        let cellWidth: CGFloat
        let tracking: CGFloat
        let lineHeight: CGFloat
        let baseline: CGFloat
        fileprivate let punctuationAdvances: [UInt32: CGFloat]
    }

    private struct Fonts {
        let body: UIFont
        let cjk: UIFont
        let quote: UIFont
        let advance: CGFloat
        let ascent: CGFloat
        let descent: CGFloat
        let punctuationAdvances: [UInt32: CGFloat]
    }

    // 这些 Unicode 标点也用于西文，只在相邻 CJK 上下文中占一格。
    private static let contextualPunctuation: [UInt32] = [0x00B7, 0x2014, 0x2018, 0x2019, 0x201C, 0x201D, 0x2026]

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
            // 仅中文使用全宽字形，关闭标点的比例宽度；不把西文/emoji 变成等宽字体。
            let descriptor = cjk.fontDescriptor.addingAttributes([
                .featureSettings: [[UIFontDescriptor.FeatureKey.type: kTextSpacingType,
                                    UIFontDescriptor.FeatureKey.selector: kMonospacedTextSelector]]
            ])
            let fullWidth = UIFont(descriptor: descriptor, size: size)
            let emoji = UIFont(name: "AppleColorEmoji", size: size) ?? body
            let bubbleSize = max(size - 5, 11)
            let tail = CommentBubble.tailHeight(for: bubbleSize)
            // 包含气泡（即便本段没有），避免附加气泡或最后一页改变行高。
            let ascent = max(max(body.ascender, fullWidth.ascender),
                             max(emoji.ascender, bubbleSize + tail * 0.5 + 2))
            let descent = max(max(-body.descender, -fullWidth.descender),
                              max(-emoji.descender, tail * 0.5))
            let punctuationAdvances = Dictionary(uniqueKeysWithValues: contextualPunctuation.map {
                ($0, advance(of: String(UnicodeScalar($0)!), font: fullWidth))
            })
            // “/”/‘/’ 必须使用 PingFang 原生弯曲字形：系统西文字体在
            // 中文上下文中的引号虽仍是 U+201C/U+201D，却画成两根斜直线。
            // 只对句读启用等宽特性，不让特性替换原始引号字形。
            fonts = Fonts(body: body, cjk: fullWidth, quote: cjk,
                          advance: max(advance(of: "汉", font: fullWidth), 1),
                          ascent: ascent, descent: descent, punctuationAdvances: punctuationAdvances)
            fontCache[size] = fonts
        }
        let available = width.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        let columns = available.map { max(floor($0 / fonts.advance), 1) } ?? 1
        let cell = available.map { max($0 / columns, fonts.advance) } ?? fonts.advance
        let height = ceil(fonts.ascent + fonts.descent)
        return Metrics(font: fonts.body, cjkFont: fonts.cjk, quoteFont: fonts.quote, cellWidth: cell,
                       tracking: cell - fonts.advance, lineHeight: height,
                       baseline: fonts.ascent + (height - fonts.ascent - fonts.descent) * 0.5,
                       punctuationAdvances: fonts.punctuationAdvances)
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
                               continuation: Bool = false, width: CGFloat? = nil) -> NSAttributedString {
        let grid = metrics(fontSize: fontSize, width: width)
        let style = NSMutableParagraphStyle()
        style.lineSpacing = max(lineSpacing, 0)
        style.minimumLineHeight = grid.lineHeight
        style.maximumLineHeight = grid.lineHeight
        // 段间距和标题仍由外层布局计算；不把最后一行/章尾撑满。
        style.paragraphSpacing = 0
        // TextKit 使用稳定字距决定合法断行；不为填满行尾拉散汉字。
        style.alignment = .left
        // 只在显示副本中将纯中文成对 U+0022 识别为开/闭引号；原始正文不动，
        // 每个替换仍占一个 UTF-16 单元，分页、进度和命中索引一一对应。
        let dialogueQuotes = chineseDialogueQuotes(in: text)
        let displayed = displayText(for: text)
        style.lineBreakMode = .byWordWrapping
        style.lineBreakStrategy = []
        style.hyphenationFactor = 0
        style.headIndent = 0
        style.tailIndent = 0
        style.firstLineHeadIndent = continuation ? 0 : grid.cellWidth * 2
        let attrs: [NSAttributedString.Key: Any] = [
            .font: grid.font,
            .foregroundColor: color,
            .paragraphStyle: style,
            baselineKey: NSNumber(value: Double(grid.baseline))
        ]
        let result = NSMutableAttributedString(string: displayed, attributes: attrs)
        var offset = 0
        var runStart = 0, runEnd = 0
        var runKern: CGFloat?
        func finishRun() {
            guard let kern = runKern else { return }
            // 明确的 advance + kern 组成一格；只关闭字格 run 的连字/自动 kerning。
            result.addAttributes([.font: grid.cjkFont, .kern: kern, .ligature: 0],
                                 range: NSRange(location: runStart, length: runEnd - runStart))
            runKern = nil
        }
        func appendGrid(start: Int, length: Int, kern: CGFloat) {
            if runKern != kern || runEnd != start {
                finishRun()
                runStart = start
                runKern = kern
            }
            runEnd = start + length
        }
        var pending: [(start: Int, length: Int, kern: CGFloat)] = []
        var leftIsGrid = false
        func resolvePunctuation(rightIsGrid: Bool) {
            // 只查看紧邻的非候选字符；不跨越空格/西文/emoji，把英文引号和 don't 留给原生塑形。
            if leftIsGrid || rightIsGrid {
                for mark in pending { appendGrid(start: mark.start, length: mark.length, kern: mark.kern) }
            } else if !pending.isEmpty {
                finishRun()
            }
            pending.removeAll(keepingCapacity: true)
        }
        for character in displayed {
            let scalar = character.unicodeScalars.count == 1 ? character.unicodeScalars.first?.value : nil
            let length = scalar.map { $0 > 0xFFFF ? 2 : 1 } ?? String(character).utf16.count
            if let scalar, isGridScalar(scalar) {
                resolvePunctuation(rightIsGrid: true)
                appendGrid(start: offset, length: length, kern: grid.tracking)
                leftIsGrid = true
            } else if let scalar, let advance = grid.punctuationAdvances[scalar] {
                pending.append((offset, length, grid.cellWidth - advance))
            } else {
                resolvePunctuation(rightIsGrid: false)
                finishRun()
                leftIsGrid = false
            }
            offset += length
        }
        resolvePunctuation(rightIsGrid: false)
        finishRun()
        // PingFang SC draws authentic curved U+2018/19/1C/1D glyphs. Assign it
        // directly only to CJK-context quotes, with a proportional advance; do not
        // substitute characters or expand adjacent Han to hide a width mismatch.
        let source = displayed as NSString
        let quotes = CharacterSet(charactersIn: "‘’“”")
        for index in 0..<source.length {
            guard let scalar = UnicodeScalar(source.character(at: index)), quotes.contains(scalar),
                  result.attribute(.kern, at: index, effectiveRange: nil) != nil else { continue }
            result.addAttributes([.font: grid.quoteFont, .kern: 0, .ligature: 0],
                                 range: NSRange(location: index, length: 1))
        }
        for (position, opening) in dialogueQuotes {
            result.addAttribute(quoteOpeningKey, value: opening, range: NSRange(location: position, length: 1))
        }
        result.addAttribute(.paragraphStyle, value: style,
                            range: NSRange(location: 0, length: result.length))
        if count > 0 {
            // 保留原有的一个分隔字符；显式固定为四分之一字格，避免系统空格宽度漂移。
            var gapAttributes = attrs
            gapAttributes[.kern] = grid.cellWidth * 0.25 - advance(of: " ", font: grid.font)
            result.append(NSAttributedString(string: " ", attributes: gapAttributes))
            let size = max(fontSize - 5, 11)
            let image = CommentBubble.image(count: count, size: size, color: color)
            let attachment = NSTextAttachment()
            attachment.image = image
            attachment.bounds = CGRect(x: 0, y: -CommentBubble.tailHeight(for: size) * 0.5,
                                       width: image.size.width, height: image.size.height)
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
        var positions: [Int] = [], offset = 0
        var hasHan = false
        for scalar in text.unicodeScalars {
            let value = scalar.value
            // 不改变英文单词、网址、尺寸符号、数字或其他字母的断行。
            if CharacterSet.letters.contains(scalar) && !isGridScalar(value) { return [] }
            if CharacterSet.decimalDigits.contains(scalar) || value == 0x2F || value == 0x5C { return [] }
            if value == 0x22 { positions.append(offset) }
            if (0x4E00...0x9FFF).contains(value) { hasHan = true }
            offset += value > 0xFFFF ? 2 : 1
        }
        guard hasHan, !positions.isEmpty, positions.count.isMultiple(of: 2) else { return [] }
        return positions.enumerated().map { ($0.element, $0.offset.isMultiple(of: 2)) }
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
        max(lineSpacing, 0) + max(paragraphSpacing, 0)
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
                  lineSpacing: CGFloat, continuation: Bool) -> (count: Int, height: CGFloat) {
            _ = height(text: text, count: count, width: width, fontSize: fontSize,
                       lineSpacing: lineSpacing, continuation: continuation)
            return ReaderTextLayout.rows(of: view)
        }

        func height(text: String, count: Int, width: CGFloat, fontSize: CGFloat,
                    lineSpacing: CGFloat, continuation: Bool = false) -> CGFloat {
            view.render(text: text, count: count, fontSize: fontSize, lineSpacing: lineSpacing,
                        color: .black, continuation: continuation)
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
