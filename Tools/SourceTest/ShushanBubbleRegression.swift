import Foundation

/// 书山聚合的段评气泡适配：气泡是书源自己生成的 SVG（data:image/svg+xml;base64…），
/// 选项写成 JS 字面量 `,{'js':'showCmt("书","章","段","日期")','style':'TEXT'}`。
/// 这里直接用书源自己的 createSvg 生成气泡，再走本应用的正文分块，断言：
/// 行内气泡带出评论数、点击回调保留为书源函数调用、不会被当成大图。
enum ShushanBubbleRegression {
    static func run(_ check: (Bool, String) -> Void) throws {
        let fixture = URL(fileURLWithPath: "Tools/SourceTest/Fixtures/shushan-aggregate-v5.63.json")
        let sources = try JSONDecoder().decode([BookSource].self, from: Data(contentsOf: fixture))
        guard let source = sources.first else {
            check(false, "书山 fixture 可读取")
            return
        }
        let context = RuleContext(source: source)
        func evaluate(_ script: String) -> String {
            JSEngine.shared.evalString(script, jsLib: source.jsLib, context: context) ?? ""
        }

        // 1. 书源自己生成的气泡（未改版客户端 + Android 分支 = 我们这一侧拿到的形态）。
        let bubble = evaluate("createSvg.call(this, 12, '#666666', 'bid1', 'cid1', 3, 'fq')")
        check(bubble.hasPrefix("<img src=\"data:image/svg+xml;base64,"),
              "书源生成行内气泡 img 标签（\(bubble.prefix(40))）")
        check(bubble.contains("'style':'TEXT'") && bubble.contains("showCmt("),
              "气泡选项是 JS 字面量且带 showCmt 回调")

        // 2. src 不能被回调里的引号截断，选项要能解析出来。
        let src = ContentBlocks.imgSrc(in: bubble) ?? ""
        check(src.contains("base64,") && src.hasSuffix("}"), "img src 读到选项对象结尾（长度 \(src.count)）")
        let options = ContentBlocks.srcOptions(src)
        check(options["style"] == "TEXT", "解析出 style=TEXT（实际 \(options["style"] ?? "nil")）")
        let callback = options["js"] ?? options["click"]
        check(callback?.hasPrefix("showCmt(\"bid1\",\"cid1\",\"3\",") == true,
              "解析出 showCmt 回调（实际 \(callback ?? "nil")）")

        // 3. 整行分块：气泡并入上一段，带出评论数与点击回调，不产生图片块。
        let line = "第一段内容。" + bubble
        let blocks = ContentBlocks.parse(line)
        check(blocks.count == 1, "气泡不产生额外块（实际 \(blocks.count)）")
        guard case .paragraph(let text, let count, let url)? = blocks.first else {
            check(false, "行内气泡并入段落")
            return
        }
        check(text == "第一段内容。", "段落文本不被气泡污染（实际 \(text)）")
        check(count == 12, "段落带出评论数 12（实际 \(count)）")
        check(url?.hasPrefix("js:showCmt(\"bid1\",\"cid1\",\"3\",") == true,
              "点击回调保留为书源函数调用（实际 \(url ?? "nil")）")

        // 4. 段落文本里也带其它气泡时，两段互不影响。
        let twoLines = ["第一段。" + bubble, "第二段。" + bubble].joined(separator: "\n")
        let twoBlocks = ContentBlocks.parse(twoLines)
        check(twoBlocks.count == 2, "两个段评气泡仍是两段（实际 \(twoBlocks.count)）")

        // 5. 图片样式（FULL）：按图片块处理，但点击回调仍要保留。
        let full = "<img src=\"data:image/svg+xml;base64,\(Data("<svg xmlns=\"http://www.w3.org/2000/svg\"><text>7</text></svg>".utf8).base64EncodedString()),{'click':'showCmt(\"b\",\"c\",\"1\",\"2\")','style':'FULL'}\">"
        let fullBlocks = ContentBlocks.parse("正文。" + full)
        check(fullBlocks.count == 2, "FULL 样式气泡单独成块（实际 \(fullBlocks.count)）")
        if case .image(_, let click, _)? = fullBlocks.last {
            check(click?.hasPrefix("js:showCmt(") == true, "FULL 样式气泡保留点击回调（实际 \(click ?? "nil")）")
        } else {
            check(false, "FULL 样式气泡解析为图片块")
        }

        // 6. iOS 分支的 comment 标签（onPress + showReadingBrowser）也要能拿到网址。
        let iosTag = "<comment count=\"12\" onPress=\"java.showReadingBrowser('https://example.invalid/c','番茄段评')\">"
        let iosBlocks = ContentBlocks.parse("第一段。" + iosTag)
        if case .paragraph(let iosText, let iosCount, let iosURL)? = iosBlocks.first {
            check(iosText == "第一段。" && iosCount == 12, "onPress 形式气泡带出评论数（实际 \(iosCount)）")
            check(iosURL == "https://example.invalid/c", "showReadingBrowser 网址被识别（实际 \(iosURL ?? "nil")）")
        } else {
            check(false, "onPress 形式气泡解析为段落")
        }
    }
}
