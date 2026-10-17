import SwiftUI
import WebKit
import CoreText

extension URL: Identifiable { public var id: String { absoluteString } }

/// 段评/章评：默认半屏，上划可展开到全屏；内容区域优先滚动网页。
struct CommentSheet: View {
    let url: URL
    var heightFraction: CGFloat = 0.6

    var body: some View {
        // 不放额外按钮：下拉或点半屏外侧即可关闭。
        CommentWebView(url: url)
            .ignoresSafeArea(edges: .bottom)
            // 默认半屏；上划可展开到全屏，网页内容仍优先接收滚动。
            .presentationDetents([.fraction(heightFraction), .large])
            .presentationDragIndicator(.visible)
            .modifier(SheetCorner(radius: 20))
    }
}

/// presentationCornerRadius 需要 iOS 16.4；低版本保持系统默认圆角。
private struct SheetCorner: ViewModifier {
    let radius: CGFloat
    func body(content: Content) -> some View {
        if #available(iOS 16.4, *) {
            content.presentationCornerRadius(radius).presentationContentInteraction(.scrolls)
        } else {
            content
        }
    }
}

struct CommentWebView: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> WKWebView {
        let web = WKWebView(frame: .zero)
        web.customUserAgent = WebViewSupport.userAgent
        web.load(URLRequest(url: url))
        return web
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

/// 正文里的图片块：支持 data: URI（SVG 章评气泡、图片）与网络图片。
struct ContentImageView: View {
    let src: String
    @State private var image: UIImage?
    @State private var svgHTML: String?

    var body: some View {
        Group {
            if let img = image {
                Image(uiImage: img).resizable().scaledToFit().frame(maxWidth: .infinity)
            } else if let html = svgHTML {
                SVGWebView(html: html).frame(height: 120)
            } else {
                Color.clear.frame(height: 1)
            }
        }
        .task { await load() }
    }

    private func load() async {
        if src.hasPrefix("data:") {
            guard let comma = src.firstIndex(of: ",") else { return }
            let meta = src[..<comma].lowercased()
            let payload = String(src[src.index(after: comma)...])
            if meta.contains("svg") {
                // 段评气泡等 SVG：解码规则与正文数据源一致，但需要用 WebView 渲染。
                guard let d = DataURIDecode.data(src) ?? payload.removingPercentEncoding?.data(using: .utf8) else { return }
                svgHTML = "<html><head><meta name='viewport' content='width=device-width,initial-scale=1'><style>body{margin:0;background:transparent}svg{width:100%;height:auto}</style></head><body>" + (String(data: d, encoding: .utf8) ?? "") + "</body></html>"
            } else {
                image = DataURIDecode.data(src).flatMap(UIImage.init(data:))
            }
        } else if let u = URL(string: src), let (d, _) = try? await URLSession.shared.data(from: u) {
            image = UIImage(data: d)
        }
    }
}

struct SVGWebView: UIViewRepresentable {
    let html: String
    func makeUIView(context: Context) -> WKWebView {
        let web = WKWebView(frame: .zero)
        web.isOpaque = false
        web.backgroundColor = .clear
        web.scrollView.isScrollEnabled = false
        web.isUserInteractionEnabled = false
        return web
    }
    func updateUIView(_ uiView: WKWebView, context: Context) { uiView.loadHTMLString(html, baseURL: nil) }
}


/// Outline traced from the user's photo_590CCBC1.png, not a rounded rectangle
/// with an extra triangle. Reference: 23pt body, @3x, 109x85px canvas;
/// ink 103x79px, origin 3px after the preceding glyph advance, baseline -70px.
enum CommentBubble {
    private static var cache: [String: UIImage] = [:]

    static func attachmentBounds(fontSize: CGFloat) -> CGRect {
        if let style = BubbleStyleRuntime.snapshot() { return BubbleStyleRenderer.bounds(style: style, fontSize: fontSize) }
        let scale = max(fontSize, 1) / 23
        return CGRect(x: 0, y: -4 * scale, width: 109 / 3 * scale, height: 85 / 3 * scale)
    }

    /// The 3px inset is INSIDE the image; no extra quarter-em separator.
    static func image(count: Int, fontSize: CGFloat, color: UIColor) -> UIImage {
        if let style = BubbleStyleRuntime.snapshot() { return BubbleStyleRenderer.image(style: style, count: count, fontSize: fontSize, color: color) }
        let label = String(min(max(count, 0), 99))
        let scale = max(fontSize, 1) / 23
        let format = UIGraphicsImageRendererFormat.default()
        format.opaque = false
        let key = "ref590-v1|\(label)|\(fontSize)|\(color)|\(format.scale)"
        if let hit = cache[key] { return hit }
        let canvas = attachmentBounds(fontSize: fontSize).size
        let img = UIGraphicsImageRenderer(size: canvas, format: format).image { renderer in
            let context = renderer.cgContext
            context.saveGState()
            context.translateBy(x: 0, y: canvas.height)
            context.scaleBy(x: scale / 30, y: -scale / 30)
            context.addPath(outline)
            context.setFillColor(color.cgColor)
            context.drawPath(using: .eoFill)
            context.restoreGState()
            // Fixed body size for both 1 and 23. Center the number by its ink,
            // not the font's advance (which biases narrow digits sideways).
            let font = UIFont.systemFont(ofSize: 10.8 * scale, weight: .semibold)
            let text = NSAttributedString(string: label, attributes: [.font: font, .foregroundColor: color])
            let line = CTLineCreateWithAttributedString(text)
            let ink = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds])
            context.saveGState()
            context.translateBy(x: 0, y: canvas.height)
            context.scaleBy(x: 1, y: -1)
            context.textMatrix = .identity
            let center = CGPoint(x: 54.5 / 3 * scale, y: canvas.height - 42 / 3 * scale)
            context.textPosition = CGPoint(x: center.x - ink.midX, y: center.y - ink.midY)
            CTLineDraw(line, context)
            context.restoreGState()
        }.withRenderingMode(.alwaysOriginal)
        if cache.count >= 128 { cache.removeAll(keepingCapacity: true) }
        cache[key] = img
        return img
    }

    /// Two continuous contours, original units 0.1px, origin bottom-left.
    private static let outline: CGPath = {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 340, y: 802))
        p.addCurve(to: CGPoint(x: 149, y: 689), control1: CGPoint(x: 253, y: 773), control2: CGPoint(x: 200, y: 742))
        p.addCurve(to: CGPoint(x: 40, y: 350), control1: CGPoint(x: 62, y: 600), control2: CGPoint(x: 19, y: 466))
        p.addCurve(to: CGPoint(x: 115, y: 176), control1: CGPoint(x: 54, y: 273), control2: CGPoint(x: 71, y: 233))
        p.addCurve(to: CGPoint(x: 144, y: 78), control1: CGPoint(x: 148, y: 132), control2: CGPoint(x: 150, y: 126))
        p.addLine(to: CGPoint(x: 137, y: 27))
        p.addLine(to: CGPoint(x: 196, y: 32))
        p.addCurve(to: CGPoint(x: 327, y: 70), control1: CGPoint(x: 231, y: 36), control2: CGPoint(x: 285, y: 51))
        p.addCurve(to: CGPoint(x: 447, y: 90), control1: CGPoint(x: 396, y: 101), control2: CGPoint(x: 402, y: 102))
        p.addCurve(to: CGPoint(x: 765, y: 79), control1: CGPoint(x: 517, y: 72), control2: CGPoint(x: 695, y: 66))
        p.addCurve(to: CGPoint(x: 1043, y: 291), control1: CGPoint(x: 901, y: 104), control2: CGPoint(x: 1010, y: 187))
        p.addCurve(to: CGPoint(x: 1039, y: 555), control1: CGPoint(x: 1067, y: 362), control2: CGPoint(x: 1065, y: 472))
        p.addCurve(to: CGPoint(x: 967, y: 675), control1: CGPoint(x: 1022, y: 610), control2: CGPoint(x: 1008, y: 633))
        p.addCurve(to: CGPoint(x: 540, y: 816), control1: CGPoint(x: 870, y: 772), control2: CGPoint(x: 753, y: 810))
        p.addCurve(to: CGPoint(x: 340, y: 802), control1: CGPoint(x: 419, y: 820), control2: CGPoint(x: 386, y: 817))
        p.closeSubpath()
        p.move(to: CGPoint(x: 702, y: 735))
        p.addCurve(to: CGPoint(x: 923, y: 621), control1: CGPoint(x: 795, y: 716), control2: CGPoint(x: 870, y: 678))
        p.addCurve(to: CGPoint(x: 1000, y: 406), control1: CGPoint(x: 976, y: 564), control2: CGPoint(x: 1000, y: 497))
        p.addCurve(to: CGPoint(x: 840, y: 171), control1: CGPoint(x: 999, y: 299), control2: CGPoint(x: 946, y: 220))
        p.addCurve(to: CGPoint(x: 667, y: 142), control1: CGPoint(x: 793, y: 149), control2: CGPoint(x: 768, y: 145))
        p.addCurve(to: CGPoint(x: 473, y: 156), control1: CGPoint(x: 578, y: 139), control2: CGPoint(x: 531, y: 142))
        p.addCurve(to: CGPoint(x: 371, y: 163), control1: CGPoint(x: 415, y: 169), control2: CGPoint(x: 392, y: 171))
        p.addCurve(to: CGPoint(x: 285, y: 126), control1: CGPoint(x: 357, y: 157), control2: CGPoint(x: 318, y: 140))
        p.addLine(to: CGPoint(x: 225, y: 101))
        p.addLine(to: CGPoint(x: 219, y: 131))
        p.addCurve(to: CGPoint(x: 182, y: 198), control1: CGPoint(x: 215, y: 148), control2: CGPoint(x: 199, y: 178))
        p.addCurve(to: CGPoint(x: 106, y: 400), control1: CGPoint(x: 124, y: 271), control2: CGPoint(x: 106, y: 319))
        p.addCurve(to: CGPoint(x: 186, y: 629), control1: CGPoint(x: 105, y: 498), control2: CGPoint(x: 129, y: 565))
        p.addCurve(to: CGPoint(x: 702, y: 735), control1: CGPoint(x: 291, y: 745), control2: CGPoint(x: 467, y: 781))
        p.closeSubpath()
        return p
    }()
}


/// 带行内段评气泡的正文段落。使用 UITextView 让气泡参与正常换行，点击命中附件时才打开评论。
struct InlineCommentParagraph: UIViewRepresentable {
    let text: String
    let count: Int
    let fontSize: CGFloat
    let lineSpacing: CGFloat
    let color: UIColor
    let continuation: Bool
    let fullJustify: Bool
    let zhLayout: Bool
    let paragraphEnd: Bool
    let onTextTap: (() -> Void)?
    let onTap: () -> Void
    /// 长按选词后的菜单动作；nil 时不启用选择，正文点击仍交给翻页容器。
    var selection: ReaderTextSelectionActions?
    /// 朗读高亮前缀长度（本段已读字符数）；0 = 不高亮。
    var highlightLength: Int = 0
    /// 高亮的背景色（跟随主题）。
    var highlightColor: UIColor = ReaderAloudHighlightStyle.color
    /// 朗读进度模型：订阅后只改文字底色，不触发重新排版或阅读器整树刷新。
    var aloudHighlight: AloudHighlightModel?
    var aloudChapter: Int?
    /// 分页模式传页号；滚动模式为 nil（匹配 page 0）。
    var aloudPage: Int?
    var aloudBlock: Int?

    @MainActor
    final class Coordinator: NSObject {
        var model: AloudHighlightModel?
        private weak var textView: CommentTextView?
        var chapter: Int?
        var page: Int?
        var block: Int?

        deinit { NotificationCenter.default.removeObserver(self) }

        func subscribe(_ model: AloudHighlightModel?, view: CommentTextView) {
            textView = view
            guard self.model !== model else { return }
            NotificationCenter.default.removeObserver(self)
            self.model = model
            guard let model else { return }
            // 模型只在主线程广播；selector 同步绘制，不排队过期进度。
            NotificationCenter.default.addObserver(self, selector: #selector(progressChanged(_:)),
                name: AloudHighlightModel.changedName, object: model)
        }

        @objc private func progressChanged(_ notification: Notification) {
            guard let model, let view = textView else { return }
            view.applyHighlight(length: currentLength(model: model), color: view.highlightColor)
        }

        /// 当前视图负责的块命中朗读进度时返回已读字符数，否则 0。
        func currentLength(model: AloudHighlightModel) -> Int {
            guard let value = model.value,
                  let chapter, let block,
                  value.chapter == chapter, value.block == block else { return 0 }
            if let page, value.page != page { return 0 }
            return value.length
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    init(text: String, count: Int, fontSize: CGFloat, lineSpacing: CGFloat,
         color: UIColor, continuation: Bool = false, fullJustify: Bool = false,
         zhLayout: Bool = false, paragraphEnd: Bool = true,
         onTextTap: (() -> Void)? = nil,
         selection: ReaderTextSelectionActions? = nil,
         highlightLength: Int = 0,
         highlightColor: UIColor = ReaderAloudHighlightStyle.color,
         aloudHighlight: AloudHighlightModel? = nil,
         aloudChapter: Int? = nil,
         aloudPage: Int? = nil,
         aloudBlock: Int? = nil,
         onTap: @escaping () -> Void) {
        self.text = text
        self.count = count
        self.fontSize = fontSize
        self.lineSpacing = lineSpacing
        self.color = color
        self.continuation = continuation
        self.fullJustify = fullJustify
        self.zhLayout = zhLayout
        self.paragraphEnd = paragraphEnd
        self.onTextTap = onTextTap
        self.selection = selection
        self.highlightLength = highlightLength
        self.highlightColor = highlightColor
        self.aloudHighlight = aloudHighlight
        self.aloudChapter = aloudChapter
        self.aloudPage = aloudPage
        self.aloudBlock = aloudBlock
        self.onTap = onTap
    }

    func makeUIView(context: Context) -> CommentTextView {
        let view = ReaderTextLayout.makeTextView()
        ReaderTextLayout.configure(view)
        view.onBubbleTap = onTap
        view.onTextTap = onTextTap
        view.selectionActions = selection
        view.isSelectable = selection != nil
        view.installTapHandling()
        context.coordinator.chapter = aloudChapter
        context.coordinator.page = aloudPage
        context.coordinator.block = aloudBlock
        context.coordinator.subscribe(aloudHighlight, view: view)
        let initial = aloudHighlight.map { context.coordinator.currentLength(model: $0) } ?? highlightLength
        view.applyHighlight(length: initial, color: highlightColor)
        return view
    }

    func updateUIView(_ view: CommentTextView, context: Context) {
        view.onBubbleTap = onTap
        view.onTextTap = onTextTap
        view.selectionActions = selection
        view.isSelectable = selection != nil
        context.coordinator.chapter = aloudChapter
        context.coordinator.page = aloudPage
        context.coordinator.block = aloudBlock
        context.coordinator.subscribe(aloudHighlight, view: view)
        view.render(text: text, count: count, fontSize: fontSize, lineSpacing: lineSpacing,
                    color: color, continuation: continuation,
                    fullJustify: fullJustify, zhLayout: zhLayout,
                    paragraphEnd: paragraphEnd)
        if let aloudHighlight {
            view.applyHighlight(length: context.coordinator.currentLength(model: aloudHighlight),
                                color: highlightColor)
        } else {
            view.applyHighlight(length: highlightLength, color: highlightColor)
        }
    }

    @available(iOS 16.0, *)
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: CommentTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        return CGSize(width: width, height: ReaderTextLayout.height(of: uiView, width: width))
    }
}

/// 长按选词后的菜单动作。全选与字典由文本视图自己完成，其余交给阅读器。
struct ReaderTextSelectionActions {
    var onCopy: (String) -> Void = { UIPasteboard.general.string = $0 }
    var onReplace: (String) -> Void = { _ in }
    var onBookmark: (String) -> Void = { _ in }
}

final class ReaderTextLayoutManager: NSLayoutManager {
    weak var highlightView: CommentTextView?

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: CGPoint) {
        if let view = highlightView, view.highlightedRange.length > 0 {
            let range = NSIntersectionRange(glyphsToShow, glyphRange(forCharacterRange: view.highlightedRange,
                                                                      actualCharacterRange: nil))
            if range.length > 0 {
                enumerateLineFragments(forGlyphRange: range) { _, _, _, lineGlyphs, _ in
                    let overlap = NSIntersectionRange(range, lineGlyphs)
                    guard overlap.length > 0 else { return }
                    var rect = self.boundingRect(forGlyphRange: overlap, in: view.textContainer)
                    guard !rect.isNull, !rect.isEmpty else { return }
                    rect.origin.x += origin.x
                    rect.origin.y += origin.y
                    rect = rect.insetBy(dx: -2, dy: -1)
                    view.highlightColor.setFill()
                    UIBezierPath(roundedRect: rect, cornerRadius: 4).fill()
                }
            }
        }
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
    }
}

final class CommentTextView: UITextView, UIGestureRecognizerDelegate, UITextViewDelegate {
    var onBubbleTap: (() -> Void)?
    var onTextTap: (() -> Void)?
    var selectionActions: ReaderTextSelectionActions?
    private var bubbleIndex: Int?
    private var lastRenderKey: String?
    private var paragraphTap: UITapGestureRecognizer?
    /// 保留期望前缀；重新测宽/排版时重挂，文本存储本身保持不变。
    private(set) var highlightedRange = NSRange(location: 0, length: 0)
    private var requestedHighlightLength = 0
    private(set) var highlightColor: UIColor = ReaderAloudHighlightStyle.color
    private struct Paragraph {
        let text: String
        let count: Int
        let fontSize: CGFloat
        let lineSpacing: CGFloat
        let color: UIColor
        let continuation: Bool
        let fullJustify: Bool
        let zhLayout: Bool
        let paragraphEnd: Bool
    }
    private var paragraph: Paragraph?
    private var needsTypesetting = false
    private var isTypesetting = false
    private(set) var renderedWidth: CGFloat = 0

    func installTapHandling() {
        if delegate == nil { delegate = self }
        guard paragraphTap == nil else { return }
        let tap = UITapGestureRecognizer(target: self, action: #selector(paragraphTapped(_:)))
        tap.delegate = self
        tap.cancelsTouchesInView = true
        tap.delaysTouchesBegan = false
        tap.delaysTouchesEnded = false
        addGestureRecognizer(tap)
        paragraphTap = tap
    }

    /// 使用附件实际字形区域，不能用“最近字符”判断（会把行尾空白误当气泡）。
    var bubbleRect: CGRect? {
        // SwiftUI 可能探测过另一提议宽度；点击必须恢复到当前屏幕宽度再取字形。
        if bounds.width > 0 { typeset(width: bounds.width) }
        guard let bubbleIndex, bubbleIndex < textStorage.length else { return nil }
        layoutManager.ensureLayout(for: textContainer)
        let glyphs = layoutManager.glyphRange(forCharacterRange: NSRange(location: bubbleIndex, length: 1),
                                             actualCharacterRange: nil)
        guard glyphs.length > 0 else { return nil }
        guard let attachment = textStorage.attribute(.attachment, at: bubbleIndex,
            effectiveRange: nil) as? NSTextAttachment else { return nil }
        let line = layoutManager.lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: nil)
        let origin = layoutManager.location(forGlyphAt: glyphs.location)
        // boundingRect(forGlyphRange:) includes the fixed *line box*, not the
        // actual attachment image. TextKit's attachment glyph origin already
        // incorporates attachment.bounds.origin.y; subtract the image height.
        let rect = CGRect(x: line.minX + origin.x + attachment.bounds.minX,
                          y: line.minY + origin.y - attachment.bounds.height,
                          width: attachment.bounds.width, height: attachment.bounds.height)
        guard rect.width > 0, rect.height > 0 else { return nil }
        return rect.offsetBy(dx: textContainerInset.left, dy: textContainerInset.top)
    }

    func isBubble(at point: CGPoint) -> Bool {
        bubbleRect?.contains(point) == true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // 没有正文回调时，正文点击交还给翻页容器；气泡始终由本组件处理。
        onTextTap != nil || isBubble(at: touch.location(in: self))
    }

    @objc private func paragraphTapped(_ tap: UITapGestureRecognizer) {
        guard tap.state == .ended else { return }
        if isBubble(at: tap.location(in: self)) { onBubbleTap?() }
        else { onTextTap?() }
    }

    // MARK: 长按选词菜单（拷贝 / 全选 / 字典 / 替换 / 书签）

    /// 气泡图片不参与选择，避免「全选」把段评附件算进去。
    private var bubbleAttachmentIndex: Int? {
        guard let bubbleIndex, textStorage.length > 0,
              bubbleIndex >= 0, bubbleIndex < textStorage.length,
              textStorage.attribute(.attachment, at: bubbleIndex, effectiveRange: nil) != nil else { return nil }
        return bubbleIndex
    }

    var selectedPlainText: String {
        guard let range = selectedTextRange, !range.isEmpty else { return "" }
        return text(in: range) ?? ""
    }

    private func selectEverything() {
        if let bubble = bubbleAttachmentIndex {
            selectedRange = NSRange(location: 0, length: bubble)
        } else {
            selectedRange = NSRange(location: 0, length: textStorage.length)
        }
    }

    /// 自定义菜单替换系统菜单：只保留用户要求的五项。
    func textView(_ textView: UITextView, editMenuForTextIn range: NSRange,
                  suggestedActions: [UIMenuElement]) -> UIMenu? {
        guard let selectionActions else { return nil }
        let selected = selectedPlainText
        let copy = UIAction(title: "拷贝") { [weak self] _ in
            guard let self else { return }
            let value = self.selectedPlainText
            guard !value.isEmpty else { return }
            selectionActions.onCopy(value)
            self.selectedRange = NSRange(location: 0, length: 0)
        }
        let selectAll = UIAction(title: "全选") { [weak self] _ in self?.selectEverything() }
        let dictionary = UIAction(title: "字典") { [weak self] _ in
            let value = self?.selectedPlainText ?? ""
            guard !value.isEmpty else { return }
            ReaderDictionaryLookup.present(value)
        }
        let replace = UIAction(title: "替换") { [weak self] _ in
            let value = self?.selectedPlainText ?? ""
            guard !value.isEmpty else { return }
            self?.selectedRange = NSRange(location: 0, length: 0)
            selectionActions.onReplace(value)
        }
        let bookmark = UIAction(title: "书签") { [weak self] _ in
            let value = self?.selectedPlainText ?? ""
            self?.selectedRange = NSRange(location: 0, length: 0)
            selectionActions.onBookmark(value)
        }
        return UIMenu(children: [copy, selectAll, dictionary, replace, bookmark])
    }

    func render(text: String, count: Int, fontSize: CGFloat, lineSpacing: CGFloat,
                color: UIColor, continuation: Bool = false,
                fullJustify: Bool = false, zhLayout: Bool = false,
                paragraphEnd: Bool = true) {
        let key = "\(BubbleStyleRuntime.revision)|\(ReaderFontResolver.identity)|\(text)|\(count)|\(fontSize)|\(lineSpacing)|\(continuation)|\(fullJustify)|\(zhLayout)|\(paragraphEnd)|\(color)"
        guard key != lastRenderKey else { return }
        lastRenderKey = key
        paragraph = Paragraph(text: text, count: count, fontSize: fontSize,
                              lineSpacing: lineSpacing, color: color, continuation: continuation,
                              fullJustify: fullJustify, zhLayout: zhLayout,
                              paragraphEnd: paragraphEnd)
        needsTypesetting = true
        typeset(width: bounds.width > 0 ? bounds.width : renderedWidth)
    }

    private func typeset(width: CGFloat) {
        guard !isTypesetting, let paragraph, width.isFinite, width >= 0,
              needsTypesetting || width != renderedWidth else { return }
        isTypesetting = true
        defer { isTypesetting = false }
        // 先更新缓存，避免设置 attributedText 导致 intrinsicContentSize 重入。
        needsTypesetting = false
        renderedWidth = width
        let result = ReaderTextLayout.attributedText(
            text: paragraph.text, count: paragraph.count, fontSize: paragraph.fontSize,
            lineSpacing: paragraph.lineSpacing, color: paragraph.color,
            continuation: paragraph.continuation, width: width > 0 ? width : nil,
            fullJustify: paragraph.fullJustify, zhLayout: paragraph.zhLayout,
            paragraphEnd: paragraph.paragraphEnd)
        bubbleIndex = paragraph.count > 0 ? result.length - 1 : nil
        attributedText = result
        textContainerInset = .zero
        textContainer.lineFragmentPadding = 0
        textContainer.size = CGSize(width: width, height: .greatestFiniteMagnitude)
        // UITextView 重建存储后重挂临时底色，不修改正文属性或选择范围。
        applyHighlightAttribute()
        invalidateIntrinsicContentSize()
    }

    /// TextKit 临时底色只使显示失效，保留字形、分页和用户选择范围。
    func applyHighlight(length: Int, color: UIColor) {
        let clamped = max(length, 0)
        guard clamped != requestedHighlightLength || !color.isEqual(highlightColor) else { return }
        requestedHighlightLength = clamped
        highlightColor = color
        applyHighlightAttribute()
    }

    private func applyHighlightAttribute() {
        highlightedRange = NSRange(location: 0, length: 0)
        if textStorage.length > 0 {
            layoutManager.invalidateDisplay(forCharacterRange: NSRange(location: 0, length: textStorage.length))
        }
        guard let paragraph, requestedHighlightLength > 0, textStorage.length > 0 else {
            setNeedsDisplay()
            return
        }
        // 范围限定到原文，不把分隔空格和段评附件涂色；Emoji/组合字符不拆开。
        let displayed = ReaderTextLayout.displayText(for: paragraph.text)
        let length = min(displayed.prefix(requestedHighlightLength).utf16.count, textStorage.length)
        guard length > 0 else {
            setNeedsDisplay()
            return
        }
        highlightedRange = NSRange(location: 0, length: length)
        layoutManager.invalidateDisplay(forCharacterRange: NSRange(location: 0, length: textStorage.length))
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        super.draw(rect)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        if size.width.isFinite, size.width > 0 { typeset(width: size.width) }
        let fitted = super.sizeThatFits(size)
        // UITextView 可能临时使用另一宽度进行试排。恢复本次字号/字格对应的容器，
        // 避免屏幕上和段评命中区域仍沿用前一次试排宽度。
        if renderedWidth > 0 {
            // UITextView's probe can leave a finite height from the previous frame.
            // Canonical row measurement must include ALL glyphs when a reused view
            // grows, not just the fragments that fit its previous paragraph.
            textContainer.size = CGSize(width: renderedWidth, height: .greatestFiniteMagnitude)
        }
        // UIKit/SwiftUI 的滚动宿主必须保留同一提议宽度；短段落的 usedRect 不是正文列宽。
        // 这里只改返回尺寸，重复 layoutSubviews 仍由 typeset 的内容/宽度缓存拦截。
        return CGSize(width: size.width.isFinite && size.width > 0 ? size.width : fitted.width,
                      height: fitted.height)
    }

    override func layoutSubviews() {
        if bounds.width > 0 { typeset(width: bounds.width) }
        super.layoutSubviews()
        // The visible frame intentionally ends before final trailing line spacing.
        // Do not let UITextView use that clipped frame as a pagination container;
        // the last glyph line still needs its full fragment to be laid out.
        if renderedWidth > 0 {
            let full = CGSize(width: renderedWidth, height: .greatestFiniteMagnitude)
            if textContainer.size != full { textContainer.size = full }
            layoutManager.ensureLayout(for: textContainer)
        }
    }

    override var intrinsicContentSize: CGSize {
        guard bounds.width > 0 else { return CGSize(width: UIView.noIntrinsicMetric, height: 1) }
        return CGSize(width: UIView.noIntrinsicMetric,
                      height: ReaderTextLayout.height(of: self, width: bounds.width))
    }

}
