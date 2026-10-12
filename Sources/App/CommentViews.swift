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
            let data: Data?
            if meta.contains(";base64") {
                var p = payload.replacingOccurrences(of: "\\s", with: "", options: .regularExpression)
                while p.count % 4 != 0 { p += "=" }
                data = Data(base64Encoded: p)
            } else { data = payload.removingPercentEncoding?.data(using: .utf8) }
            guard let d = data else { return }
            if meta.contains("svg") {
                svgHTML = "<html><head><meta name='viewport' content='width=device-width,initial-scale=1'><style>body{margin:0;background:transparent}svg{width:100%;height:auto}</style></head><body>" + (String(data: d, encoding: .utf8) ?? "") + "</body></html>"
            } else { image = UIImage(data: d) }
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
        let scale = max(fontSize, 1) / 23
        return CGRect(x: 0, y: -4 * scale, width: 109 / 3 * scale, height: 85 / 3 * scale)
    }

    /// The 3px inset is INSIDE the image; no extra quarter-em separator.
    static func image(count: Int, fontSize: CGFloat, color: UIColor) -> UIImage {
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

    init(text: String, count: Int, fontSize: CGFloat, lineSpacing: CGFloat,
         color: UIColor, continuation: Bool = false, fullJustify: Bool = false,
         zhLayout: Bool = false, paragraphEnd: Bool = true,
         onTextTap: (() -> Void)? = nil,
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
        self.onTap = onTap
    }

    func makeUIView(context: Context) -> CommentTextView {
        let view = ReaderTextLayout.makeTextView()
        ReaderTextLayout.configure(view)
        view.onBubbleTap = onTap
        view.onTextTap = onTextTap
        view.installTapHandling()
        return view
    }

    func updateUIView(_ view: CommentTextView, context: Context) {
        view.onBubbleTap = onTap
        view.onTextTap = onTextTap
        view.render(text: text, count: count, fontSize: fontSize, lineSpacing: lineSpacing,
                    color: color, continuation: continuation,
                    fullJustify: fullJustify, zhLayout: zhLayout,
                    paragraphEnd: paragraphEnd)
    }

    @available(iOS 16.0, *)
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: CommentTextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        return CGSize(width: width, height: ReaderTextLayout.height(of: uiView, width: width))
    }
}

final class CommentTextView: UITextView, UIGestureRecognizerDelegate {
    var onBubbleTap: (() -> Void)?
    var onTextTap: (() -> Void)?
    private var bubbleIndex: Int?
    private var lastRenderKey: String?
    private var paragraphTap: UITapGestureRecognizer?
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

    func render(text: String, count: Int, fontSize: CGFloat, lineSpacing: CGFloat,
                color: UIColor, continuation: Bool = false,
                fullJustify: Bool = false, zhLayout: Bool = false,
                paragraphEnd: Bool = true) {
        let key = "\(ReaderFontResolver.identity)|\(text)|\(count)|\(fontSize)|\(lineSpacing)|\(continuation)|\(fullJustify)|\(zhLayout)|\(paragraphEnd)|\(color)"
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
        invalidateIntrinsicContentSize()
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
