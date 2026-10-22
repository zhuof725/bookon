import Foundation

/// 正文块：文字段落，或段评气泡/图片。从书源正文规则的输出解析而来。
/// 书源（如柒默的 iOS 版）在段落末尾输出 `<comment count="N" onClick="java.startBrowser('URL')"/>`，
/// 章末评论或精选评论则是 `<img src="data:image/svg+xml;base64,…" onClick="java.startBrowser('URL')"/>`。
enum ContentBlock: Equatable {
    case paragraph(text: String, commentCount: Int, commentURL: String?)
    /// 行内小图（书源 `style:"text"` 的气泡图）：按文字大小显示在上一段末尾。
    /// src 是 data: 或网址；count 是气泡里的数字（从 SVG 文本里读出，读不到为 nil）。
    /// rawSrc 是书源原始的 src（含 `,{...}` 选项）：imageDecode 脚本要从里面取参数
    /// （番茄系段评的正则匹配 createSvg(...)），去掉选项就匹配不到了。
    case inlineBubble(src: String, count: Int?, clickURL: String?, rawSrc: String?)
    /// rawSrc 同 inlineBubble：书源原始 src（含选项），供 imageDecode 使用。
    case image(src: String, clickURL: String?, rawSrc: String?)
    /// 书源用 SVG 画的「热评」卡片，改用原生卡片显示：label 为红色标签文字，text 为评论内容。
    case hotComment(label: String, text: String, clickURL: String?)
    /// 章末「本章说」评论汇总：标题、右侧计数文字，以及若干条 用户名/正文/点赞数。
    case chapterComments(title: String, count: String, items: [ChapterCommentItem], clickURL: String?)
}

struct ChapterCommentItem: Equatable {
    var user: String
    var text: String
    var likes: String
}

enum ContentBlocks {
    /// 把规则输出拆成有序块。普通文本（没有任何评论标签）得到只含 paragraph 的块，与原来的 cleanText 逐行一致。
    ///
    /// - Parameter imageDecode: 原版 `ruleContent.imageDecode` 的执行入口。必须在**图片级别**、
    ///   **并入段落之前**执行：原版是对每张图片单独跑一次脚本，脚本里的 `src` 是这张图片的原始地址。
    ///   番茄系段评的脚本要靠它清掉「已渲染」标记（否则点击气泡会被跳过），
    ///   而它只从 `src` 里正则提取参数 —— 传整章正文会匹配错，传剥掉选项的 src 会匹配不到。
    static func parse(_ raw: String, imageDecode: ((String) -> String)? = nil) -> [ContentBlock] {
        var text = raw
        text = text.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "</(p|div)>", with: "\n", options: [.regularExpression, .caseInsensitive])
        var blocks: [ContentBlock] = []
        for line in text.components(separatedBy: .newlines) {
            appendLine(line, into: &blocks, imageDecode: imageDecode)
        }
        return mergeInlineBubbles(blocks)
    }

    /// 把行内气泡并入它前面的段落（count 与点击目标取自气泡）。前面不是段落时，丢弃该气泡。
    static func mergeInlineBubbles(_ blocks: [ContentBlock]) -> [ContentBlock] {
        var out: [ContentBlock] = []
        for b in blocks {
            if case .inlineBubble(_, let count, let click, _) = b {
                if case .paragraph(let t, let c, let u)? = out.last {
                    out[out.count - 1] = .paragraph(text: t, commentCount: count ?? max(c, 1), commentURL: click ?? u)
                }
            } else {
                out.append(b)
            }
        }
        return out
    }

    private static let tagPattern = try! NSRegularExpression(pattern: "<(comment|img)\\b[^>]*?/?>", options: [.caseInsensitive])

    private static func appendLine(_ line: String, into blocks: inout [ContentBlock],
                                   imageDecode: ((String) -> String)? = nil) {
        let ns = line as NSString
        let matches = tagPattern.matches(in: line, range: NSRange(location: 0, length: ns.length))
        var cursor = 0
        var pendingText = ""
        var pendingCount = 0
        var pendingURL: String?
        func flush() {
            let t = clean(pendingText)
            if !t.isEmpty || pendingCount > 0 {
                if t.isEmpty && pendingCount > 0, case .paragraph(let prev, let c, let u)? = blocks.last, c == 0, u == nil {
                    blocks[blocks.count - 1] = .paragraph(text: prev, commentCount: pendingCount, commentURL: pendingURL)
                } else if !t.isEmpty {
                    blocks.append(.paragraph(text: t, commentCount: pendingCount, commentURL: pendingURL))
                }
            }
            pendingText = ""; pendingCount = 0; pendingURL = nil
        }
        for m in matches {
            pendingText += ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor))
            cursor = m.range.location + m.range.length
            let tag = ns.substring(with: m.range)
            let name = ns.substring(with: m.range(at: 1)).lowercased()
            if name == "comment" {
                pendingCount = Int(attribute("count", in: tag) ?? "") ?? 0
                pendingURL = clickURL(in: tag)
            } else {
                // 图片是独立块：先结束当前段落。
                flush()
                if let src = imgSrc(in: tag), !src.isEmpty {
                    let clean = stripOptions(src)
                    let opts = srcOptions(src)
                    let click = clickURL(in: tag) ?? optionClick(in: src) ?? clickFromOptions(opts)
                    // imageDecode 对**原始 src**（含 ,{...} 选项）执行，脚本里的 src 就是它。
                    let decoded = imageDecode?(src) ?? clean
                    if opts["style"]?.lowercased() == "text" {
                        // 书源要求按文字大小行内显示：接到上一段末尾，而不是单独成大图。
                        // 条数：SVG 里的数字可能是封顶值（番茄聚合 >99 一律画 99），
                        // 真实条数从回调里取（见 commentCount）。
                        let svg = svgText(decoded)
                        let svgCount = svg.map { svgTexts($0).compactMap { Int($0) }.first } ?? nil
                        blocks.append(.inlineBubble(src: decoded,
                                                    count: commentCount(svgCount: svgCount, click: click,
                                                                        payloadIsSVG: svg?.contains("<svg") == true),
                                                    clickURL: click,
                                                    rawSrc: src == clean ? nil : src))
                    } else if let svg = svgText(decoded), let native = nativeBlock(fromSVG: svg, click: click) {
                        blocks.append(native)
                    } else if let svg = svgText(decoded), !(opts["js"] ?? "").isEmpty,
                              let badge = jsBubbleBlock(fromSVG: svg, click: click) {
                        // 书源用 js 动态生成的评论气泡（番茄系章评/书评/段评）：
                        // src 的 base64 本来是空的，真实图形要靠 js 生成；认得出来就渲染成原生卡片，
                        // 认不出来时那张 base64 为空的图就是一片乱码。
                        blocks.append(badge)
                    } else {
                        blocks.append(.image(src: decoded, clickURL: click, rawSrc: src == clean ? nil : src))
                    }
                }
            }
        }
        pendingText += ns.substring(from: cursor)
        flush()
    }

    private static func clean(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        for (e, d) in [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&amp;", "&")] {
            t = t.replacingOccurrences(of: e, with: d)
        }
        return t.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{3000}")))
    }

    /// img 的 src。书源常把选项对象直接拼在 src 里且不转义引号：
    /// `src="data:…base64,XXX,{"style":"text","click":"showCmt('1')"}"`，
    /// 书山用的是 JS 字面量写法：`src="data:…base64,XXX,{'js':'showCmt("1","2","3","4")','style':'TEXT'}"`。
    /// 普通属性解析会在第一个引号处截断，这里识别 `,{` 后的选项对象，读到它的 `}` 为止。
    static func imgSrc(in tag: String) -> String? {
        guard let r = tag.range(of: "\\bsrc\\s*=\\s*\"", options: [.regularExpression, .caseInsensitive]) else {
            return attribute("src", in: tag)
        }
        let rest = tag[r.upperBound...]
        guard let q = rest.firstIndex(of: "\"") else { return nil }
        let first = String(rest[..<q])
        if let marker = first.range(of: ",{"), let end = rest.range(of: "}\"", range: marker.lowerBound..<rest.endIndex) {
            return String(rest[..<end.lowerBound]) + "}"
        }
        return first
    }

    static func attribute(_ name: String, in tag: String) -> String? {
        let pattern = "\\b" + name + "\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)')"
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let m = re.firstMatch(in: tag, range: NSRange(location: 0, length: (tag as NSString).length)) else { return nil }
        for i in 1...2 where m.range(at: i).location != NSNotFound {
            return (tag as NSString).substring(with: m.range(at: i))
        }
        return nil
    }

    /// onClick / onPress="java.startBrowser('https://…')" -> https://…
    /// 书山的 iOS 分支用 onPress="java.showReadingBrowser('…','xx段评')"。
    static func clickURL(in tag: String) -> String? {
        guard let click = attribute("onClick", in: tag) ?? attribute("onPress", in: tag) else { return nil }
        return urlInCall(click)
    }

    static func urlInCall(_ call: String) -> String? {
        let pattern = "(?:startBrowser(?:Await)?|showBrowser|showReadingBrowser|startBrowserDp)\\(\\s*['\"]([^'\"]+)['\"]"
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: call, range: NSRange(location: 0, length: (call as NSString).length)) else { return nil }
        return (call as NSString).substring(with: m.range(at: 1))
    }

    /// src 后面可能带 `,{"type":..,"click":"java.startBrowser('…')"}` 选项（Android 版）。
    static func stripOptions(_ src: String) -> String {
        if let r = src.range(of: ",{") { return String(src[..<r.lowerBound]) }
        return src
    }

    /// src 后面 `,{"style":"text","type":"qd","click":"showCmt('1','2','3','4')"}` 的键值（字符串值）。
    /// 也支持书山的 JS 字面量写法 `,{'js':'showCmt("1","2","3","4")','style':'TEXT'}`。
    static func srcOptions(_ src: String) -> [String: String] {
        guard let r = src.range(of: ",{") else { return [:] }
        let json = String(src[src.index(after: r.lowerBound)...])
        if let d = json.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
            return o.reduce(into: [:]) { $0[$1.key] = "\($1.value)" }
        }
        var out: [String: String] = [:]
        // 书源常写成 {"style":"text","click":"showCmt('1')"} 里含未转义引号的写法：退回逐键提取。
        for key in ["style", "type", "click", "js", "onClick"] {
            if let re = try? NSRegularExpression(pattern: "\"" + key + "\"\\s*:\\s*\"(.*?)\"(?:\\s*[,}])"),
               let m = re.firstMatch(in: json, range: NSRange(location: 0, length: (json as NSString).length)) {
                out[key] = (json as NSString).substring(with: m.range(at: 1))
            }
        }
        for (key, value) in jsLiteralOptions(json) where out[key] == nil { out[key] = value }
        return out
    }

    /// JS 对象字面量选项：键与值用单引号，值里可能有另一种引号
    /// （`{'js':'showCmt("1","2")','style':'TEXT'}`）。单引号不是合法 JSON，逐键提取。
    static func jsLiteralOptions(_ json: String) -> [String: String] {
        var body = json.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.hasPrefix("{") { body.removeFirst() }
        if body.hasSuffix("}") { body.removeLast() }
        var out: [String: String] = [:]
        for key in ["style", "type", "click", "js", "onClick"] {
            let patterns = ["[\"']" + key + "[\"']\\s*:\\s*'([^']*)'",
                            "[\"']" + key + "[\"']\\s*:\\s*\"([^\"]*)\""]
            for pattern in patterns {
                guard let re = try? NSRegularExpression(pattern: pattern),
                      let m = re.firstMatch(in: body, range: NSRange(location: 0, length: (body as NSString).length)),
                      m.range(at: 1).location != NSNotFound else { continue }
                out[key] = (body as NSString).substring(with: m.range(at: 1))
                break
            }
        }
        return out
    }

    /// click 是 JS 调用（如 showCmt('书','章','段','数')）时，不是网址；留给调用方按书源执行。
    /// 书山把回调键写成 `js`（未改版客户端）或 `click`（改版客户端），两者都认。
    /// 番茄系「知秋段评」的气泡：`src` 的 base64 部分是空的，真正的段评数量写在点击表达式里：
    ///   createSvg('bid','cid',pid,count,nanoTime)
    /// 只从 SVG 文本取数字会拿不到，结果一律显示 1。这里按参数位置取第 4 个。
    static func countFromClick(_ click: String?) -> Int? {
        guard let click, !click.isEmpty else { return nil }
        let pattern = "createSvg[0-9]*\\(\\s*['\"]([^'\"]*)['\"]\\s*,\\s*['\"]([^'\"]*)['\"]\\s*,"
            + "\\s*(-?\\d+)\\s*,\\s*(\\d+)"
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let m = re.firstMatch(in: click, range: NSRange(location: 0, length: (click as NSString).length)),
              let r = Range(m.range(at: 4), in: click) else { return nil }
        return Int(click[r])
    }

    /// showCmt(...) 的第 4 个参数：番茄聚合里是段评条数，
    /// 但书山的 showCmt(bid, cid, para, date) 第 4 个参数是时间戳后 6 位（日期片段），
    /// 两者长得一样，只能靠「SVG 里的数字是否被封顶」来判断能不能用。
    static func showCmtCount(_ click: String?) -> Int? {
        guard let click, !click.isEmpty else { return nil }
        let pattern = "showCmt\\(\\s*['\"]?[^,'\")]*['\"]?\\s*,\\s*['\"]?[^,'\")]*['\"]?\\s*,"
            + "\\s*['\"]?[^,'\")]*['\"]?\\s*,\\s*['\"]?(\\d+)['\"]?"
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let m = re.firstMatch(in: click, range: NSRange(location: 0, length: (click as NSString).length)),
              let r = Range(m.range(at: 1), in: click) else { return nil }
        return Int(click[r])
    }

    /// 段评条数：
    /// 1. createSvg 系列的第 4 个参数就是条数（知秋段评的 SVG 里根本没有数字，只能靠它）。
    /// 2. showCmt 系列的第 4 个参数有两种含义：
    ///    - 番茄聚合：条数。SVG 里画的是封顶值（>99 一律 99），真实条数只有回调里有；
    ///      书源把气泡换成「气泡社区」的图（取图接口没登录时返回一段 JSON）时，
    ///      SVG 里根本没有数字，条数也只能从回调里取。
    ///    - 书山：日期片段（时间戳后 6 位）。它画的是一个正常 SVG（<svg…>），
    ///      所以「图不是 SVG」这个条件能把它挡在外面；另外要求 4 位以内。
    /// 3. 其余情况用 SVG 里的数字。
    static func commentCount(svgCount: Int?, click: String?, payloadIsSVG: Bool = true) -> Int? {
        if let n = countFromClick(click) { return n }
        if let n = showCmtCount(click), n < 10000 {
            if svgCount == 99, n > 99 { return n }              // 画的是封顶值 99 → 真实条数
            if svgCount == nil, !payloadIsSVG { return n }      // 图被换成了别的东西（气泡社区取图失败）
        }
        return svgCount
    }

    static func clickFromOptions(_ opts: [String: String]) -> String? {
        guard let c = opts["click"] ?? opts["js"] ?? opts["onClick"], !c.isEmpty else { return nil }
        if let u = urlInCall(c) { return u }
        return "js:" + c
    }

    static func optionClick(in src: String) -> String? {
        guard src.contains(",{") else { return nil }
        return urlInCall(src)
    }

    // MARK: - SVG 评论卡片 -> 原生块

    /// 解出 data:image/svg+xml 的 SVG 文本；不是 SVG 返回 nil。
    /// base64 的 payload 只取第一个「,」之前的部分：书源常在地址后面接 `,{...}` 选项，
    /// 混进 base64 里会解不出来（段评气泡的条数就是这么丢的）。
    static func svgText(_ src: String) -> String? {
        guard src.hasPrefix("data:"), let comma = src.firstIndex(of: ",") else { return nil }
        let meta = src[..<comma].lowercased()
        guard meta.contains("svg") else { return nil }
        var payload = String(src[src.index(after: comma)...])
        if meta.contains(";base64") {
            if let cut = payload.firstIndex(of: ",") { payload = String(payload[..<cut]) }
            var p = payload.replacingOccurrences(of: "\\s", with: "", options: .regularExpression)
            while p.count % 4 != 0 { p += "=" }
            guard let d = Data(base64Encoded: p) else { return nil }
            return String(data: d, encoding: .utf8)
        }
        return payload.removingPercentEncoding
    }

    private static func xmlUnescape(_ s: String) -> String {
        var t = s
        for (e, d) in [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&apos;", "'"), ("&amp;", "&")] {
            t = t.replacingOccurrences(of: e, with: d)
        }
        return t
    }

    /// SVG 里所有 <text> 的内容，保持出现顺序。
    static func svgTexts(_ svg: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: "<text\\b[^>]*>([^<]*)</text>", options: [.caseInsensitive]) else { return [] }
        let ns = svg as NSString
        return re.matches(in: svg, range: NSRange(location: 0, length: ns.length)).map {
            xmlUnescape(ns.substring(with: $0.range(at: 1))).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// 书源把「标签 + 一行评论」的卡片都画成 SVG：起点用「热评」，番茄/大灰狼用「神评论」。
    private static let hotCommentLabels: Set<String> = ["热评", "神评论", "精选评论", "精彩评论"]

    /// 识别书源生成的两类评论 SVG：热评（标签+一行）与「本章说」汇总。其他 SVG 返回 nil，仍按图片显示。
    /// SVG 里只有一个数字时，表示这是「评论条数」气泡（番茄系的章评/书评）。
    /// 只对「由书源选项里的 js 动态生成」的气泡生效：这类气泡的 base64 本来是空的，
    /// 不转成卡片就只能显示坏图。按点击表达式里的 cid/pid 区分章评还是书评。
    static func countBadge(fromSVG svg: String, click: String?) -> ContentBlock? {
        let texts = svgTexts(svg)
        guard texts.count == 1, let n = Int(texts[0].trimmingCharacters(in: .whitespaces)), n > 0 else { return nil }
        return .chapterComments(title: commentKind(click), count: String(n), items: [], clickURL: click)
    }

    /// 从点击表达式判断评论层级：pid = -1 且 cid = -1 是书评，pid = -1 是章评，其余是段评。
    static func commentKind(_ click: String?) -> String {
        guard let click else { return "评论" }
        let pattern = "createSvg[0-9]*\\(\\s*['\"](\\d+)['\"]\\s*,\\s*['\"](-?\\d+)['\"]\\s*,\\s*(-?\\d+)"
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: click, range: NSRange(location: 0, length: (click as NSString).length)),
              let cidRange = Range(m.range(at: 2), in: click),
              let pidRange = Range(m.range(at: 3), in: click) else { return "评论" }
        let cid = Int(click[cidRange]) ?? 0
        let pid = Int(click[pidRange]) ?? 0
        if pid == -1 { return cid == -1 ? "书评" : "章评" }
        return "段评"
    }

    // MARK: - 番茄系「本章讨论 / 本书讨论」条

    /// 章评/书评条上的标题文字。
    static let discussionTitles: Set<String> = ["本章说", "本章讨论", "本书讨论", "本章评论", "本书评论"]

    /// 番茄系章评/书评：书源把整条画成一张 SVG ——「本章讨论 | 条数 | 〉」。
    /// 三个 <text>，既不是「标签+一行」的热评，也不是只画一个数字的气泡，
    /// 之前认不出来 → 落回图片分支 → 显示成 base64 乱码。
    static func discussionBlock(fromSVG svg: String, click: String?) -> ContentBlock? {
        let texts = svgTexts(svg)
        guard let title = texts.first(where: { discussionTitles.contains($0) }) else { return nil }
        guard let count = texts.first(where: { Int($0.trimmingCharacters(in: .whitespaces)) != nil }) else { return nil }
        return .chapterComments(title: title, count: count, items: [], clickURL: click)
    }

    /// 书源选项里的 js 动态生成的评论气泡 → 原生卡片。
    /// - 只画一个数字：评论条数气泡（段评/章评）。
    /// - 「本章讨论 / 本书讨论 + 条数」：章末/书末的讨论条。
    /// - 都不认得，但点击表达式说明是章评/书评：按参数里的条数兜底。
    static func jsBubbleBlock(fromSVG svg: String, click: String?) -> ContentBlock? {
        if let badge = countBadge(fromSVG: svg, click: click) { return badge }
        if let disc = discussionBlock(fromSVG: svg, click: click) { return disc }
        let kind = commentKind(click)
        if kind == "章评" || kind == "书评", let n = countFromClick(click) {
            return .chapterComments(title: kind, count: String(n), items: [], clickURL: click)
        }
        return nil
    }

    /// SVG 根元素的宽高比（高/宽），用于按原比例显示。取不到返回 nil。
    /// 优先用 width/height 属性；没有就用 viewBox（番茄聚合的章评条只有 viewBox）。
    static func svgAspectRatio(_ svg: String) -> Double? {
        guard let re = try? NSRegularExpression(pattern: "<svg\\b[^>]*>", options: [.caseInsensitive]),
              let m = re.firstMatch(in: svg, range: NSRange(location: 0, length: (svg as NSString).length)) else { return nil }
        let tag = (svg as NSString).substring(with: m.range)
        var w = svgLength(in: tag, name: "width")
        var h = svgLength(in: tag, name: "height")
        if w == nil || h == nil {
            // viewBox="0 0 1024 150" → 宽高取后两个数。
            if let re2 = try? NSRegularExpression(pattern: "\\bviewBox\\s*=\\s*\"([^\"]+)\""),
               let m2 = re2.firstMatch(in: tag, range: NSRange(location: 0, length: (tag as NSString).length)),
               let r = Range(m2.range(at: 1), in: tag) {
                let parts = tag[r].split(separator: " ").compactMap { Double($0) }
                if parts.count >= 4 {
                    w = w ?? parts[2]
                    h = h ?? parts[3]
                }
            }
        }
        guard let ww = w, let hh = h, ww > 0, hh > 0 else { return nil }
        return hh / ww
    }

    private static func svgLength(in tag: String, name: String) -> Double? {
        guard let re = try? NSRegularExpression(pattern: "\\b" + name + "\\s*=\\s*\"?([0-9.]+)"),
              let m = re.firstMatch(in: tag, range: NSRange(location: 0, length: (tag as NSString).length)),
              let r = Range(m.range(at: 1), in: tag) else { return nil }
        return Double(tag[r])
    }

    static func nativeBlock(fromSVG svg: String, click: String?) -> ContentBlock? {
        let texts = svgTexts(svg)
        if texts.count == 2, Self.hotCommentLabels.contains(texts[0]) {
            return .hotComment(label: texts[0], text: texts[1], clickURL: click)
        }
        if texts.count >= 2, Self.discussionTitles.contains(texts[0]) {
            // 后面是 用户名、(点赞数 在图形里)、正文行… 的重复；书源把正文按行切成多个 <text>。
            // 这里只可靠地得到标题和计数；条目不再还原，点击进入评论页查看。
            // 认成原生卡片还有两个好处：条数能显示出来，而且是文字控件（比 SVG 图片好点）。
            return .chapterComments(title: texts[0], count: texts[1], items: [], clickURL: click)
        }
        return nil
    }

    /// 阅读缓存/兼容用：把块还原成与原来 cleanText 一致的纯文本（评论标记丢弃）。
    static func plainText(_ blocks: [ContentBlock]) -> String {
        blocks.compactMap { b -> String? in
            if case .paragraph(let t, _, _) = b { return "\u{3000}\u{3000}" + t }
            return nil
        }.joined(separator: "\n")
    }
}
