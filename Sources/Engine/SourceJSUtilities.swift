import Foundation

/// Legado JsExtensions 里与文本/HTML 相关的小工具：htmlFormat、toNumChapter。
enum SourceJSUtilities {
    /// 原版 `HtmlFormatter.formatKeepImg` 的常用子集：
    /// 保留 `<img>`（相对地址按当前页补全），`<br>` / `</p>` 变换行，其余标签去掉。
    static func htmlFormat(_ html: String, baseUrl: String?) -> String {
        var text = html
        text = text.replacingOccurrences(of: "<!--[\\s\\S]*?-->", with: "",
                                         options: [.regularExpression])
        text = text.replacingOccurrences(of: "<script\\b[^>]*>[\\s\\S]*?</script>", with: "",
                                         options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "<style\\b[^>]*>[\\s\\S]*?</style>", with: "",
                                         options: [.regularExpression, .caseInsensitive])
        // 图片先换成占位符，等去标签、解实体之后再放回来，否则会被 <[^>]+> 一起删掉。
        var images: [String] = []
        if let re = RegexLog.compile("<img\\b[^>]*>", options: [.caseInsensitive]) {
            while true {
                let ns = text as NSString
                guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { break }
                let tag = ns.substring(with: m.range)
                let src = attribute("src", in: tag) ?? ""
                let resolved = resolve(src, base: baseUrl)
                let token = "\u{E000}\(images.count)\u{E001}"
                images.append(resolved.isEmpty ? "" : "<img src=\"\(resolved)\">")
                text = ns.replacingCharacters(in: m.range, with: token)
            }
        }
        text = text.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "</p\\s*>", with: "\n", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "</div\\s*>", with: "\n", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        text = decodeEntities(text)
        for (index, image) in images.enumerated() {
            text = text.replacingOccurrences(of: "\u{E000}\(index)\u{E001}", with: image)
        }
        text = text.replacingOccurrences(of: "[ \\t]+\\n", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        guard let re = try? NSRegularExpression(
            pattern: "\\b\(name)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s>]+))",
            options: [.caseInsensitive]) else { return nil }
        let ns = tag as NSString
        guard let m = re.firstMatch(in: tag, range: NSRange(location: 0, length: ns.length)) else { return nil }
        for i in 1...3 where m.range(at: i).location != NSNotFound {
            return ns.substring(with: m.range(at: i))
        }
        return nil
    }

    private static func resolve(_ src: String, base: String?) -> String {
        let s = src.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty || s.hasPrefix("data:") || s.hasPrefix("http://") || s.hasPrefix("https://") { return s }
        guard let base, let b = URL(string: base) else { return s }
        return URL(string: s, relativeTo: b)?.absoluteString ?? s
    }

    private static func decodeEntities(_ text: String) -> String {
        var t = text
        for (entity, value) in [("&nbsp;", " "), ("&ensp;", " "), ("&emsp;", " "), ("&shy;", ""),
                                ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
                                ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'")] {
            t = t.replacingOccurrences(of: entity, with: value)
        }
        return t
    }

    /// 原版 `toNumChapter`：把「第 + 中文数字 + 章」里的数字转成阿拉伯数字。
    static func toNumChapter(_ text: String) -> String {
        guard let re = try? NSRegularExpression(pattern: "(第)([0-9零〇一二三四五六七八九十百千万两]+)(章)") else {
            return text
        }
        let ns = text as NSString
        let matches = re.matches(in: text, range: NSRange(location: 0, length: ns.length))
        var result = text
        for m in matches.reversed() {
            let raw = ns.substring(with: m.range(at: 2))
            guard let value = chineseNumber(raw) else { continue }
            result = (result as NSString).replacingCharacters(in: m.range(at: 2), with: "\(value)")
        }
        return result
    }

    static func chineseNumber(_ text: String) -> Int? {
        let s = text.trimmingCharacters(in: .whitespaces)
        if s.isEmpty { return nil }
        if let v = Int(s) { return v }
        let digits: [Character: Int] = ["零": 0, "〇": 0, "一": 1, "二": 2, "两": 2, "三": 3,
                                        "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9]
        let units: [Character: Int] = ["十": 10, "百": 100, "千": 1000, "万": 10000]
        // 「一〇二」这种逐位写法
        if s.allSatisfy({ digits[$0] != nil }) {
            var v = 0
            for ch in s { v = v * 10 + (digits[ch] ?? 0) }
            return v
        }
        var total = 0, section = 0, number = 0
        for ch in s {
            if let d = digits[ch] {
                number = d
            } else if let unit = units[ch] {
                if unit == 10000 {
                    section = (section + max(number, 1)) * unit
                    total += section
                    section = 0
                } else {
                    section += max(number, 1) * unit
                }
                number = 0
            } else {
                return nil
            }
        }
        return total + section + number
    }
}
