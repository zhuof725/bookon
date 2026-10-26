import Foundation

/// 章节标题 CSS 样式解析（离线）：属性、单位、颜色、简写、坏值容错。
enum ChapterTitleStyleRegression {
    static func run(_ check: (Bool, String) -> Void) throws {
        let empty = ChapterTitleStyle.parse("")
        check(empty.isEmpty, "标题样式：空串 = 默认样式")

        let basic = ChapterTitleStyle.parse("font-size: 24px; color: #333; text-align: left")
        check(basic.fontSize == 24, "标题样式：font-size px（实际 \(String(describing: basic.fontSize))）")
        check(basic.alignment == .left, "标题样式：text-align left")
        if let color = basic.color {
            check(abs(color.red - 0.2) < 0.01 && abs(color.alpha - 1) < 0.01,
                  "标题样式：#333 解析（实际 \(color)）")
        } else {
            check(false, "标题样式：#333 解析（无颜色）")
        }

        let rgba = ChapterTitleStyle.parse("color: rgba(10, 20, 30, 0.5); background-color: transparent")
        check(rgba.color?.alpha == 0.5, "标题样式：rgba 透明度")
        check(rgba.background == .clear, "标题样式：transparent 背景")

        let hex4 = ChapterTitleStyle.parse("border-bottom: 1px solid #8883")
        check(hex4.borderBottomWidth == 1, "标题样式：border-bottom 宽度")
        check(abs((hex4.borderBottomColor?.alpha ?? 0) - 0.2) < 0.02, "标题样式：#8883 四位十六进制透明度")

        let box = ChapterTitleStyle.parse("padding: 8px 16px; margin: 12px 0 0 0")
        check(box.paddingTop == 8 && box.paddingBottom == 8, "标题样式：padding 两值简写")
        check(box.paddingHorizontal == 16, "标题样式：padding 左右")
        check(box.marginTop == 12 && box.marginBottom == 0, "标题样式：margin 四值简写")

        let relative = ChapterTitleStyle.parse("font-size: 1.5em; line-height: 150%")
        check(relative.fontScale == 1.5 && relative.fontSize == nil, "标题样式：em 相对字号")
        check(relative.lineHeight == 1.5, "标题样式：行高百分比")

        let weights = ChapterTitleStyle.parse("font-weight: bold; font-style: italic")
        check(weights.fontWeight == 700 && weights.italic == true, "标题样式：粗体 + 斜体")
        check(ChapterTitleStyle.parse("font-weight: 300").fontWeight == 300, "标题样式：数字字重")
        check(ChapterTitleStyle.parse("font-weight: 900").fontWeight == 900, "标题样式：最大字重")

        let decorations = ChapterTitleStyle.parse("text-decoration: none")
        check(decorations.underline == false && decorations.strikethrough == false, "标题样式：text-decoration none")

        let important = ChapterTitleStyle.parse("/* 注释 */ color: red !important; letter-spacing: 2px")
        check(important.color != nil, "标题样式：去注释 + !important")
        check(important.letterSpacing == 2, "标题样式：letter-spacing")

        let broken = ChapterTitleStyle.parse("font-size: あ; color: ???; 不知道: 1; padding")
        check(broken.isEmpty, "标题样式：坏值全部忽略，不崩")

        let transform = ChapterTitleStyle.parse("text-transform: uppercase; opacity: 0.6")
        check(transform.transform == .uppercase && transform.opacity == 0.6, "标题样式：大小写与透明度")

        // 直接粘一段带选择器的 CSS（常见于从 GitHub 上抄来的规则）：
        // 只取花括号里的声明，不能把选择器后面的第一条属性吃掉。
        let selected = ChapterTitleStyle.parse(".chapter-title { color: #fff; background: #000; }")
        check(selected.color?.red == 1 && selected.color?.green == 1, "标题样式：带选择器的规则取到 color")
        check(selected.background != nil && selected.background?.red == 0, "标题样式：带选择器的规则取到 background")

        let fullWidth = ChapterTitleStyle.parse("color：#fff；font-size：22px；")
        check(fullWidth.color?.red == 1, "标题样式：全角冒号/分号")
        check(fullWidth.fontSize == 22, "标题样式：全角冒号下的 font-size")

        // 声明顺序无关 + 后写的覆盖前面的。
        let ordered = ChapterTitleStyle.parse("color: #000; text-align: right; color: #fff")
        check(ordered.alignment == .right, "标题样式：属性顺序无关")
        check(ordered.color?.red == 1, "标题样式：后写覆盖前写")
    }
}
