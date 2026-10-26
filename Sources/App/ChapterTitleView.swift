import SwiftUI
import UIKit

/// 章节标题不截断；分页器和阅读视图使用同一套测量方式。
/// 样式来自 `ReadSettings.chapterTitleCSS`（一小段 CSS，解析见 `ChapterTitleStyle`）。
enum ChapterTitleLayout {
    static func baseFontSize(_ fontSize: CGFloat) -> CGFloat { max(fontSize + 2, 20) }

    static func resolvedFontSize(_ fontSize: CGFloat, style: ChapterTitleStyle) -> CGFloat {
        if let absolute = style.fontSize { return max(CGFloat(absolute), 8) }
        if let scale = style.fontScale { return max(baseFontSize(fontSize) * CGFloat(scale), 8) }
        return baseFontSize(fontSize)
    }

    static func uiWeight(_ value: Int) -> UIFont.Weight {
        switch value {
        case ..<250: return .ultraLight
        case ..<350: return .light
        case ..<450: return .regular
        case ..<550: return .medium
        case ..<650: return .semibold
        default: return .bold
        }
    }

    static func font(size: CGFloat, style: ChapterTitleStyle) -> UIFont {
        let base = ReaderFontResolver.chapterFont(size: size)
        let wantsItalic = style.italic == true
        guard style.fontWeight != nil || wantsItalic else { return base }
        var traits = base.fontDescriptor.symbolicTraits
        if wantsItalic { traits.insert(.traitItalic) }
        if let weight = style.fontWeight {
            switch weight {
            case 700...: traits.insert(.traitBold)
            case ..<400: traits.remove(.traitBold)
            default: break
            }
        }
        guard let descriptor = base.fontDescriptor.withSymbolicTraits(traits) else { return base }
        return UIFont(descriptor: descriptor, size: size)
    }

    /// 内边距：上 = padding-top + margin-top（margin 也算进盒子里，背景/边框才连续）。
    static func insets(_ style: ChapterTitleStyle) -> UIEdgeInsets {
        let horizontal = CGFloat(style.paddingHorizontal ?? 0)
        let top = CGFloat((style.paddingTop ?? 0) + (style.marginTop ?? 0))
        let bottom = CGFloat(style.paddingBottom ?? 0)
        return UIEdgeInsets(top: top, left: horizontal, bottom: bottom, right: horizontal)
    }

    static func text(_ title: String, style: ChapterTitleStyle) -> String {
        switch style.transform {
        case .uppercase: return title.uppercased()
        case .lowercase: return title.lowercased()
        case .capitalize: return title.capitalized
        default: return title
        }
    }

    static func resolvedColor(_ base: UIColor, style: ChapterTitleStyle) -> UIColor {
        guard var css = style.color else { return base }
        if let opacity = style.opacity { css.alpha *= opacity }
        return UIColor(red: CGFloat(css.red), green: CGFloat(css.green), blue: CGFloat(css.blue), alpha: CGFloat(css.alpha))
    }

    static func attributed(title: String, fontSize: CGFloat, color: UIColor,
                           style: ChapterTitleStyle) -> NSAttributedString {
        let size = resolvedFontSize(fontSize, style: style)
        let paragraph = NSMutableParagraphStyle()
        if let alignment = style.alignment {
            switch alignment {
            case .left: paragraph.alignment = .left
            case .center: paragraph.alignment = .center
            case .right: paragraph.alignment = .right
            case .justify: paragraph.alignment = .justified
            }
        } else {
            paragraph.alignment = .center
        }
        if let lineHeight = style.lineHeight, lineHeight > 0 {
            paragraph.lineHeightMultiple = CGFloat(min(max(lineHeight, 0.6), 4))
        }
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font(size: size, style: style),
            .foregroundColor: resolvedColor(color, style: style),
            .paragraphStyle: paragraph
        ]
        if let spacing = style.letterSpacing { attributes[.kern] = CGFloat(spacing) }
        if style.underline == true { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        if style.strikethrough == true { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
        return NSAttributedString(string: text(title, style: style), attributes: attributes)
    }

    /// 文字本身的高度（不含内边距）。
    static func textHeight(title: String, fontSize: CGFloat, width: CGFloat,
                           style: ChapterTitleStyle) -> CGFloat {
        guard !title.isEmpty else { return 0 }
        let label = UILabel()
        label.numberOfLines = 0
        label.attributedText = attributed(title: title, fontSize: fontSize, color: .black, style: style)
        return ceil(label.sizeThatFits(CGSize(width: max(width, 1), height: .greatestFiniteMagnitude)).height)
    }

    static func height(title: String, fontSize: CGFloat, width: CGFloat,
                       style: ChapterTitleStyle = .empty) -> CGFloat {
        guard !title.isEmpty else { return 0 }
        let insets = insets(style)
        return textHeight(title: title, fontSize: fontSize, width: width - insets.left - insets.right, style: style)
            + insets.top + insets.bottom
    }

    /// 标题下方的基础留白（不含样式的 margin-bottom）。
    static func bottomSpacing(fontSize: CGFloat, style: ChapterTitleStyle = .empty) -> CGFloat {
        max(fontSize * 0.8, 14) + CGFloat(style.marginBottom ?? 0)
    }

    static func label(title: String, fontSize: CGFloat, color: UIColor) -> UILabel {
        let label = UILabel()
        label.numberOfLines = 0
        label.textAlignment = .center
        label.font = ReaderFontResolver.chapterFont(size: max(fontSize + 2, 20))
        label.textColor = color
        label.text = title
        return label
    }
}

/// 章节标题容器：内边距 + 背景色 + 下边框都由它画，文字按 CSS 排版。
final class ChapterTitleBox: UIView {
    private let label = UILabel()
    private let border = UIView()
    private var style = ChapterTitleStyle.empty
    private var baseColor: UIColor = .black

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.numberOfLines = 0
        label.isUserInteractionEnabled = false
        addSubview(label)
        border.isUserInteractionEnabled = false
        addSubview(border)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(title: String, fontSize: CGFloat, color: UIColor, style: ChapterTitleStyle) {
        self.style = style
        baseColor = color
        label.attributedText = ChapterTitleLayout.attributed(title: title, fontSize: fontSize,
                                                             color: color, style: style)
        backgroundColor = style.background.map {
            UIColor(red: CGFloat($0.red), green: CGFloat($0.green), blue: CGFloat($0.blue), alpha: CGFloat($0.alpha))
        }
        border.isHidden = !style.hasBorder
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let insets = ChapterTitleLayout.insets(style)
        label.frame = CGRect(x: insets.left, y: insets.top,
                             width: max(bounds.width - insets.left - insets.right, 1),
                             height: max(bounds.height - insets.top - insets.bottom, 1))
        if style.hasBorder {
            let width = max(CGFloat(style.borderBottomWidth ?? 1), 0.5)
            border.frame = CGRect(x: insets.left, y: bounds.height - width,
                                  width: label.frame.width, height: width)
            let color = style.borderBottomColor?.uiColor
                ?? ChapterTitleLayout.resolvedColor(baseColor, style: style).withAlphaComponent(0.25)
            border.backgroundColor = color
        }
    }
}

extension ChapterTitleStyle.Color {
    var uiColor: UIColor {
        UIColor(red: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: CGFloat(alpha))
    }
}

struct ChapterTitleView: UIViewRepresentable {
    let title: String
    let fontSize: CGFloat
    let color: UIColor
    var style: ChapterTitleStyle = .empty

    func makeUIView(context: Context) -> ChapterTitleBox {
        let box = ChapterTitleBox()
        box.isUserInteractionEnabled = false
        box.accessibilityIdentifier = "chapter-title"
        box.configure(title: title, fontSize: fontSize, color: color, style: style)
        return box
    }

    func updateUIView(_ box: ChapterTitleBox, context: Context) {
        box.configure(title: title, fontSize: fontSize, color: color, style: style)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: ChapterTitleBox, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        return CGSize(width: width, height: ChapterTitleLayout.height(title: title, fontSize: fontSize,
                                                                      width: width, style: style))
    }
}
