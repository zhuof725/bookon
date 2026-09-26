import Foundation

enum TxtParser {

    // MARK: - Encoding

    static func decode(_ data: Data) -> String {
        // BOM checks
        if data.count >= 3, data[0] == 0xEF, data[1] == 0xBB, data[2] == 0xBF {
            return String(data: data.dropFirst(3), encoding: .utf8) ?? ""
        }
        if data.count >= 2, data[0] == 0xFF, data[1] == 0xFE {
            return String(data: data, encoding: .utf16LittleEndian) ?? ""
        }
        if data.count >= 2, data[0] == 0xFE, data[1] == 0xFF {
            return String(data: data, encoding: .utf16BigEndian) ?? ""
        }
        if let s = String(data: data, encoding: .utf8) { return s }
        let gb18030 = CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
        if let s = String(data: data, encoding: String.Encoding(rawValue: gb18030)) { return s }
        let big5 = CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.big5.rawValue))
        if let s = String(data: data, encoding: String.Encoding(rawValue: big5)) { return s }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - Chapter rules (adapted from Legado default TOC rules)

    private static let patterns: [String] = [
        // 第X章/节/回/卷/集/部/篇 ...
        #"^[ \t　]{0,4}(?:序章|楔子|正文(?!完|结)|终章|后记|尾声|番外|第?\s{0,4}[\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]{1,6}\s{0,4}(?:[章节回集卷部篇折]|[章节回集卷部篇折]\s{0,2}[^\n]{0,30}))[^\n]{0,30}$"#,
        // Chapter 1 / CHAPTER ONE
        #"^[ \t　]{0,4}(?:[Cc][Hh][Aa][Pp][Tt][Ee][Rr]|[Ss][Ee][Cc][Tt][Ii][Oo][Nn]|[Pp][Aa][Rr][Tt])\s{0,4}[\dIVXivx]{1,6}[^\n]{0,30}$"#,
        // 1. / 1、/ （1） 标题
        #"^[ \t　]{0,4}(?:[(（]?\d{1,4}[)）.、]\s{0,4})[^\n\d]{1,30}$"#
    ]

    static func splitChapters(_ text: String) -> [Chapter] {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)

        for pattern in patterns {
            guard let re = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { continue }
            let matches = re.matches(in: text, options: [], range: full)
            // need a reasonable number of hits and average length not absurd
            if matches.count >= 3 && ns.length / matches.count < 60_000 {
                return build(from: matches.map { $0.range }, in: ns)
            }
        }
        return splitByLength(ns)
    }

    private static func build(from ranges: [NSRange], in ns: NSString) -> [Chapter] {
        var chapters: [Chapter] = []
        var idx = 0
        if let first = ranges.first, first.location > 0 {
            let preface = ns.substring(with: NSRange(location: 0, length: first.location))
            if preface.trimmingCharacters(in: .whitespacesAndNewlines).count > 20 {
                chapters.append(Chapter(index: idx, title: "前言", start: 0, end: first.location))
                idx += 1
            }
        }
        for (i, r) in ranges.enumerated() {
            let end = i + 1 < ranges.count ? ranges[i + 1].location : ns.length
            let title = ns.substring(with: r).trimmingCharacters(in: .whitespacesAndNewlines)
            chapters.append(Chapter(index: idx, title: title, start: r.location, end: end))
            idx += 1
        }
        return chapters
    }

    private static func splitByLength(_ ns: NSString, size: Int = 8000) -> [Chapter] {
        var chapters: [Chapter] = []
        var pos = 0, idx = 0
        while pos < ns.length {
            var end = min(pos + size, ns.length)
            if end < ns.length {
                // move to next newline so we don't cut a paragraph
                let search = ns.range(of: "\n", options: [], range: NSRange(location: end, length: ns.length - end))
                if search.location != NSNotFound { end = search.location + 1 }
            }
            chapters.append(Chapter(index: idx, title: "第 \(idx + 1) 节", start: pos, end: end))
            pos = end
            idx += 1
        }
        return chapters
    }

    /// Chapter body with title line removed and blank lines collapsed.
    static func content(of chapter: Chapter, in text: NSString) -> String {
        let raw = text.substring(with: NSRange(location: chapter.start, length: chapter.end - chapter.start))
        var lines = raw.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if let first = lines.first, first == chapter.title { lines.removeFirst() }
        return lines.map { "　　" + $0 }.joined(separator: "\n")
    }

    /// Try to extract "title" and "author" from a file name like 《书名》作者：xx.txt
    static func meta(fromFileName name: String) -> (String, String) {
        var base = (name as NSString).deletingPathExtension
        var author = ""
        if let r = base.range(of: #"作者[:：]\s*"#, options: .regularExpression) {
            author = String(base[r.upperBound...]).trimmingCharacters(in: .whitespaces)
            base = String(base[..<r.lowerBound])
        }
        base = base.replacingOccurrences(of: "《", with: "").replacingOccurrences(of: "》", with: "")
        return (base.trimmingCharacters(in: .whitespacesAndNewlines), author)
    }
}
