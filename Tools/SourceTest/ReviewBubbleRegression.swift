import Foundation

/// 番茄系「知秋段评」气泡回归。
///
/// 书源在段落末尾插入的占位图是：
///   `<img src="data:image/svg+xml;base64,,{"style":"TEXT","type":"fqpl",
///          "click":"createSvg('1','2',3,42,1700000000)","js":"..."}">`
/// base64 是空的，段评数量写在 createSvg 的第 4 个参数里。
/// 之前只从 SVG 文本取数字 → 读不到 → 一律显示 1（数量不对）。
enum ReviewBubbleRegression {
    /// 书源真实的 imageDecode 规则（只匹配 createSvg 的参数，用它算缓存键）。
    static let decodeRule = """
    try {
      let cinfo = src.replaceAll(" ", "").match(/createSvg2?\\('(\\d+)','(-?\\d+)',(-?\\d+),\\d+,\\d+\\)/)
      let cacheKey = `fq-${cinfo[1]}-${cinfo[2]}-${cinfo[3]}`
      cache.deleteMemory(cacheKey)
    } catch (err) {
      java.log(src + "-" + "Error:" + err)
    }
    result
    """

    static func run(_ check: (Bool, String) -> Void) {
        let src = "data:image/svg+xml;base64,,{\"style\":\"TEXT\",\"type\":\"fqpl\","
            + "\"click\":\"createSvg('7320955143208307774','7322565597089235518',12,42,1700000000123)\","
            + "\"js\":\"createSvg('7320955143208307774','7322565597089235518',12,42,1700000000123)\"}"
        let line = "　　正文第一段。"
            + "<img src=\"" + src + "\">"
        let blocks = ContentBlocks.parse(line)
        var count: Int?
        var click: String?
        for block in blocks {
            if case .paragraph(_, let c, let u) = block { count = c; click = u }
        }
        check(count == 42, "段评数量从 createSvg(...) 参数解析（实际 \(count.map(String.init) ?? "nil")）")
        check(click?.hasPrefix("js:createSvg(") == true, "点击动作转成 js: 调用（实际 \(click ?? "nil")）")

        // SVG 里有真实数字时仍以 SVG 为准（普通气泡源）
        let svg = "<svg xmlns=\"http://www.w3.org/2000/svg\"><text>7</text></svg>"
        let b64 = Data(svg.utf8).base64EncodedString()
        let normal = "段落。\n<img src=\"data:image/svg+xml;base64,\(b64),{\"style\":\"text\",\"onClick\":\"java.startBrowser('https://x/y')\"}\">"
        var normalCount: Int?
        for block in ContentBlocks.parse(normal) {
            if case .paragraph(_, let c, _) = block { normalCount = c }
        }
        check(normalCount == 7, "普通 SVG 气泡仍按 SVG 文本取数（实际 \(normalCount.map(String.init) ?? "nil")）")

        check(ContentBlocks.countFromClick("createSvg('a','b',1,999,2)") == 999, "三位数段评数量")
        check(ContentBlocks.countFromClick("showCmt('a')") == nil, "非 createSvg 调用不猜测数量")
        // 番茄聚合的段评气泡：showCmt('书','章','段','条数')，第 4 个参数才是真实条数。
        // 它的 SVG 里只画了封顶后的数字（>99 一律画 99），真实条数只有回调里才有。
        check(ContentBlocks.showCmtCount("showCmt('7208454824847739938','7208456691589841412','0','205')") == 205,
              "showCmt 回调里的第 4 个参数是段评条数")
        check(ContentBlocks.showCmtCount("showCmt('a','b','c')") == nil, "showCmt 参数不够时不猜数量")
        // 书山的 showCmt 第 4 个参数是日期片段（时间戳后 6 位），不能当条数用。
        check(ContentBlocks.commentCount(svgCount: 12, click: "showCmt(\"bid1\",\"cid1\",\"3\",\"186989\")") == 12,
              "书山的 showCmt 日期片段不会被当成条数")

        // MARK: imageDecode 必须拿到书源原始的 src（含 ,{...} 选项）
        //
        // 书源的 imageDecode 规则要从 src 里正则提取 createSvg(...) 的参数来算缓存键。
        // 我们此前先把 `,{...}` 选项剥掉再交给脚本 → 正则匹配不到 → 脚本内部 try/catch
        // 把异常吞掉 → 缓存标记没被清掉 → 点击气泡时被 getFromMemory 判定为已处理而跳过。
        let source = BookSource(bookSourceUrl: "https://review-bubble.example", bookSourceName: "段评回归")
        let ctx = RuleContext(source: source)
        // 正文解析时书源写入「已渲染」标记
        _ = JSEngine.shared.evalString("cache.putMemory('fq-7320955143208307774-7322565597089235518-12','1')",
                                       context: RuleContext(source: source))
        let marked = JSEngine.shared.evalString("cache.getFromMemory('fq-7320955143208307774-7322565597089235518-12')",
                                                context: RuleContext(source: source))
        check(marked == "1", "正文解析后写入「已渲染」标记")

        // 端到端：解析时按图片级别执行 imageDecode → 标记应被清掉
        let decoded = ContentBlocks.parse(line) { src in
            ImageDecodeRuntime.decode(src, rule: decodeRule, source: source, context: ctx,
                                      baseURL: "https://review-bubble.example")
        }
        let after = JSEngine.shared.evalString("cache.getFromMemory('fq-7320955143208307774-7322565597089235518-12')",
                                               context: RuleContext(source: source)) ?? ""
        check(after.isEmpty, "imageDecode 清掉「已渲染」标记（点击气泡不再被跳过）（实际 \(after)）")
        // 气泡本身仍要保留数量与点击动作
        var count2: Int?
        var click2: String?
        for block in decoded {
            if case .paragraph(_, let c, let u) = block { count2 = c; click2 = u }
        }
        check(count2 == 42, "imageDecode 之后段评数量仍是 42（实际 \(count2.map(String.init) ?? "nil")）")
        check(click2?.hasPrefix("js:createSvg(") == true, "imageDecode 之后点击动作仍是 js:createSvg(...)")

        // 章评/书评：只画一个数字的 SVG → 原生评论卡片
        let badgeSVG = "<svg width=\"1000\" height=\"800\"><rect x=\"150\" y=\"150\" width=\"665\" height=\"525\" rx=\"175\" ry=\"175\" fill=\"none\" stroke=\"#FF0000\"/><text x=\"480\" y=\"535\" font-size=\"297.5\" fill=\"#FF0000\">42</text></svg>"
        if case .chapterComments(let title, let count, _, let badgeClick)? = ContentBlocks.countBadge(fromSVG: badgeSVG, click: "createSvg2('7320955143208307774','7322565597089235518',-1,42,1)") {
            check(title == "章评", "章评气泡标题（实际 \(title)）")
            check(count == "42", "章评气泡条数（实际 \(count)）")
            check(badgeClick != nil, "章评气泡带点击目标")
        } else {
            check(false, "只含一个数字的 SVG 识别为评论卡片")
        }
        check(ContentBlocks.commentKind("createSvg2('1','-1',-1,3,1)") == "书评", "cid/pid 均为 -1 判定为书评")
        check(ContentBlocks.commentKind("createSvg2('1','2',-1,3,1)") == "章评", "pid 为 -1 判定为章评")
        check(ContentBlocks.commentKind("createSvg('1','2',3,4,1)") == "段评", "其余判定为段评")

        // MARK: 章评/书评条（番茄系 createSvg2）：SVG 是「本章讨论 | 条数 | 〉」
        //
        // 书源把整条画成一张 SVG（base64 编码的 data URI）。
        // 之前认不出这张图 → 落回图片分支 → 渲染时把 base64 原文当正文显示（满屏乱码）。
        let discussionSVG = "<svg width=\"1000\" height=\"120\" xmlns=\"http://www.w3.org/2000/svg\">"
            + "<rect width=\"1000\" height=\"120\" fill=\"#A9A9A9\" rx=\"15\" />"
            + "<text x=\"100\" y=\"75\" font-family=\"Arial\" font-size=\"48\" fill=\"#000000\" text-anchor=\"start\">本章讨论</text>"
            + "<g transform=\"translate(850, 60)\"><rect x=\"-40\" y=\"-30\" width=\"80\" height=\"60\" rx=\"20\" ry=\"20\" stroke=\"#000000\" stroke-width=\"2\" fill=\"none\" />"
            + "<text x=\"0\" y=\"12\" font-family=\"Arial\" font-size=\"36\" fill=\"#000000\" text-anchor=\"middle\"\n      dominant-baseline=\"middle\">42</text></g>"
            + "<text x=\"965\" y=\"75\" font-family=\"Arial\" font-size=\"36\" fill=\"#000000\" text-anchor=\"middle\">〉</text></svg>"
        if case .chapterComments(let dTitle, let dCount, _, let dClick)? = ContentBlocks.discussionBlock(fromSVG: discussionSVG, click: "js:createSvg2('7320955143208307774','7322565597089235518',-1,42,1)") {
            check(dTitle == "本章讨论", "章评条标题（实际 \(dTitle)）")
            check(dCount == "42", "章评条条数（实际 \(dCount)）")
            check(dClick != nil, "章评条带点击目标")
        } else {
            check(false, "「本章讨论」SVG 识别为章评卡片")
        }
        let ratio = ContentBlocks.svgAspectRatio(discussionSVG) ?? 0
        check(abs(ratio - 0.12) < 0.001, "章评条 SVG 宽高比（1000x120）")
        // 只有 viewBox 的 SVG（番茄聚合的章评条）也要能算出比例
        let viewBoxSVG = "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 1024 150\"><rect width=\"1024\" height=\"150\"/></svg>"
        let vbRatio = ContentBlocks.svgAspectRatio(viewBoxSVG) ?? 0
        check(abs(vbRatio - 150.0 / 1024.0) < 0.001, "只有 viewBox 的 SVG 也能算出宽高比")
        // base64 的 SVG data URI 必须能解出 SVG 文本；解不出就只剩 base64 原文（乱码）。
        let b64SVG = Data(discussionSVG.utf8).base64EncodedString()
        let svgURI = "data:image/svg+xml;base64," + b64SVG
        check(ContentBlocks.svgText(svgURI) == discussionSVG, "base64 的 SVG data URI 解出 SVG 文本")
        check(ContentBlocks.svgText(svgURI)?.contains("<svg") == true, "解出的是 SVG 而不是 base64 原文")

        // 端到端：正文末尾的章评条（FULL 样式 + js 选项）→ 原生评论卡片，不能落回图片分支
        let chapterSrc = "data:image/svg+xml;base64,,{\"style\":\"FULL\",\"type\":\"fqpl\","
            + "\"click\":\"createSvg2('7320955143208307774','7322565597089235518',-1,42,1700000000123)\","
            + "\"js\":\"createSvg2('7320955143208307774','7322565597089235518',-1,42,1700000000123)\"}"
        let chapterLine = "正文最后一段。" + "<img src=\"" + chapterSrc + "\">"
        let chapterBlocks = ContentBlocks.parse(chapterLine) { _ in svgURI }
        var cardTitle: String?
        var cardCount: String?
        var fellBackToImage = false
        for block in chapterBlocks {
            if case .chapterComments(let t, let c, _, _) = block { cardTitle = t; cardCount = c }
            if case .image(_, _, _) = block { fellBackToImage = true }
        }
        check(cardTitle == "本章讨论" && cardCount == "42",
              "章评条渲染成原生卡片（实际 \(cardTitle ?? "nil")/\(cardCount ?? "nil")）")
        check(!fellBackToImage, "章评条不再落回图片分支")

        // 番茄聚合的段评气泡：SVG 里画的是封顶数字（>99 一律 99），真实条数在回调第 4 个参数。
        let cappedSVG = "<svg viewBox=\"5 14 45 36\" xmlns=\"http://www.w3.org/2000/svg\" width=\"180\" height=\"144\">"
            + "<path d=\"M44 48 Q48 48 48 44 L48 20 Z\" fill=\"none\" stroke=\"#A9A9A9\"/>"
            + "<text x=\"32\" y=\"38\" text-anchor=\"middle\" font-size=\"18\">99</text></svg>"
        let cappedURI = "data:image/svg+xml;base64," + Data(cappedSVG.utf8).base64EncodedString()
        let cappedSrc = cappedURI + ",{\"style\":\"text\",\"type\":\"bubble\","
            + "\"click\":\"showCmt('7208454824847739938','7208456691589841412','0','205')\"}"
        let cappedLine = "这一段有段评。" + "<img src=\"" + cappedSrc + "\">"
        var cappedCount: Int?
        for block in ContentBlocks.parse(cappedLine) {
            if case .paragraph(_, let c, _) = block { cappedCount = c }
        }
        check(cappedCount == 205,
              "段评条数用回调里的真实值而不是 SVG 里封顶的 99（实际 \(cappedCount.map(String.init) ?? "nil")）")
    }
}
