import SwiftUI
import UIKit

/// 本章说的原生卡片：标题 + 条数 + 评论条目（用户名、正文、点赞）。
/// 书源把整卡画成 SVG 时，解析出的条目在这里按阅读主题重排；
/// 解析不出条目就只显示标题和条数的紧凑入口条。
struct ChapterCommentsCard: View {
    let title: String
    let count: String
    let items: [ChapterCommentItem]
    let fontSize: CGFloat
    let foreground: Color
    let background: Color
    let onTap: () -> Void

    /// 正文最多展示 3 条，完整列表点进评论页看。
    static let inlineItemLimit = 3

    private var visibleItems: [ChapterCommentItem] {
        Array(items.prefix(Self.inlineItemLimit))
    }

    private var isDarkPaper: Bool {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard UIColor(background).getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return false }
        return red * 0.2126 + green * 0.7152 + blue * 0.0722 < 0.5
    }

    private var bodyFont: CGFloat { max(fontSize - 2, 12) }
    private var userFont: CGFloat { max(fontSize - 3, 11) }
    private var titleFont: CGFloat { max(fontSize - 2, 12) }
    private var countFont: CGFloat { max(fontSize - 3, 11) }

    var body: some View {
        VStack(alignment: .leading, spacing: visibleItems.isEmpty ? 0 : max(10, fontSize * 0.55)) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(.system(size: titleFont, weight: .bold))
                    .foregroundStyle(foreground)
                Spacer(minLength: 6)
                Text(count)
                    .font(.system(size: countFont))
                    .foregroundStyle(foreground.opacity(0.65))
                    .lineLimit(1)
            }
            ForEach(Array(visibleItems.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: max(4, fontSize * 0.2)) {
                    HStack(alignment: .center, spacing: 8) {
                        Text(item.user)
                            .font(.system(size: userFont, weight: .semibold))
                            .foregroundStyle(foreground)
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        if !item.likes.isEmpty {
                            HStack(spacing: 3) {
                                Image(systemName: "hand.thumbsup")
                                    .font(.system(size: max(userFont - 3, 9)))
                                Text(item.likes)
                                    .font(.system(size: max(userFont - 1, 10)))
                                    .monospacedDigit()
                            }
                            .foregroundStyle(foreground.opacity(0.75))
                            .padding(.horizontal, 9).padding(.vertical, 3)
                            .background(Capsule().fill(foreground.opacity(isDarkPaper ? 0.16 : 0.10)))
                        }
                    }
                    Text(item.text)
                        .font(.system(size: bodyFont))
                        .foregroundStyle(foreground.opacity(0.92))
                        .lineSpacing(2)
                        .lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(isDarkPaper ? 0.06 : 0.5))
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(foreground.opacity(isDarkPaper ? 0 : 0.045))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .combine)
        .accessibilityHint("打开本章说")
    }

    /// 分页器用的高度：与上面的字体、间距、4 行上限保持一致。
    static func height(items: [ChapterCommentItem], fontSize: CGFloat, width: CGFloat) -> CGFloat {
        let f = max(fontSize, 1)
        let innerWidth = max(width - 28, 40)
        let header = max(f - 2, 12) * 1.35
        let padding: CGFloat = 24
        let visible = items.prefix(inlineItemLimit)
        guard !visible.isEmpty else { return header + padding }
        let body = max(f - 2, 12)
        let user = max(f - 3, 11)
        let gap = max(10, f * 0.55)
        var total = header + padding
        for item in visible {
            let userRow = user * 1.4 + max(4, f * 0.2)
            let textHeight = measure(item.text, font: body, width: innerWidth)
            let lineHeight = body * 1.32
            let lines = min(4, max(1, Int(ceil(textHeight / lineHeight))))
            total += userRow + CGFloat(lines) * lineHeight + gap
        }
        return total + 4
    }

    private static func measure(_ text: String, font: CGFloat, width: CGFloat) -> CGFloat {
        let uiFont = UIFont.systemFont(ofSize: font)
        let rect = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: uiFont],
            context: nil)
        return ceil(rect.height)
    }
}
