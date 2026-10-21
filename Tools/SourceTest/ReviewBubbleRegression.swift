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
            + "\"click\":\"createSvg('7320955143208307774','fbd8bb1c82df7',12,42,1700000000123)\","
            + "\"js\":\"createSvg('7320955143208307774','fbd8bb1c82df7',12,42,1700000000123)\"}"
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

        // MARK: imageDecode 必须拿到书源原始的 src（含 ,{...} 选项）
        //
        // 书源的 imageDecode 规则要从 src 里正则提取 createSvg(...) 的参数来算缓存键。
        // 我们此前先把 `,{...}` 选项剥掉再交给脚本 → 正则匹配不到 → 脚本内部 try/catch
        // 把异常吞掉 → 缓存标记没被清掉 → 点击气泡时被 getFromMemory 判定为已处理而跳过。
        let source = BookSource(bookSourceUrl: "https://review-bubble.example", bookSourceName: "段评回归")
        let ctx = RuleContext(source: source)
        // 正文解析时书源写入「已渲染」标记
        _ = JSEngine.shared.evalString("cache.putMemory('fq-7320955143208307774-fbd8bb1c82df7-12','1')",
                                       context: RuleContext(source: source))
        let marked = JSEngine.shared.evalString("cache.getFromMemory('fq-7320955143208307774-fbd8bb1c82df7-12')",
                                                context: RuleContext(source: source))
        check(marked == "1", "正文解析后写入「已渲染」标记")

        // 端到端：解析时按图片级别执行 imageDecode → 标记应被清掉
        let decoded = ContentBlocks.parse(line) { src in
            ImageDecodeRuntime.decode(src, rule: decodeRule, source: source, context: ctx,
                                      baseURL: "https://review-bubble.example")
        }
        let after = JSEngine.shared.evalString("cache.getFromMemory('fq-7320955143208307774-fbd8bb1c82df7-12')",
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
    }
}
