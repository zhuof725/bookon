import Foundation

/// 正文形态诊断：需要 WebBook 的段落归一规则，所以与 DebugLog 核心分开。
/// （ReaderHarness 只编译 DebugLog.swift，不能连带依赖整个引擎。）
extension DebugLog {
    /// 只统计形态，不记录正文内容：用于判断正文是解码失败、编码错误还是确实为空。
    static func shape(_ text: String) -> String {
        let scalars = Array(text.unicodeScalars)
        let total = max(scalars.count, 1)
        let han = scalars.filter { (0x4E00...0x9FFF).contains($0.value) }.count
        let replacement = scalars.filter { $0.value == 0xFFFD }.count
        let ascii = scalars.filter { $0.value < 0x80 }.count
        let latin = scalars.filter { (0x80...0xFF).contains($0.value) }.count
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let base64 = trimmed.range(of: "^[A-Za-z0-9+/]+={0,2}$", options: .regularExpression) != nil
        let innerPad = trimmed.dropLast(2).contains("=")
        let boundaries = paragraphBoundaryShape(text)
        let recovered = WebBook.normalizeParagraphBoundaries(text).components(separatedBy: "\n").count - 1
        let images = text.components(separatedBy: "<img").count - 1
        let divs = text.components(separatedBy: "<div").count - 1
        let comments = text.components(separatedBy: "<comment").count - 1
        return "汉字 \(han)/\(total)，替换字符 \(replacement)，ASCII \(ascii)，Latin1 \(latin)，base64 形态 \(base64 ? "是" : "否")，内部含 = \(innerPad ? "是" : "否")，换行 \(text.components(separatedBy: "\n").count - 1)，全角空格 \(text.filter { $0 == "\u{3000}" }.count)"
            + "，段界候选 \(boundaries.candidates)（句末标点 \(boundaries.afterMark)／闭引号 \(boundaries.afterQuote)／汉字 \(boundaries.afterHan)／行首 \(boundaries.afterLineStart)／其他 \(boundaries.afterOther)）"
            + "，标签 img \(images)/div \(divs)/comment \(comments)，还原后换行 \(recovered)"
    }

    /// 只统计「全角空格前一个字符属于哪一类」，不输出任何正文片段。
    /// 用于判断段落边界是否是我们支持的形态（句末标点/闭引号 + U+3000）。
    private static func paragraphBoundaryShape(_ text: String) -> (candidates: Int, afterMark: Int, afterQuote: Int, afterHan: Int, afterLineStart: Int, afterOther: Int) {
        let marks: Set<Character> = ["。", "！", "？", "!", "?", "…"]
        let closers: Set<Character> = ["”", "’", "」", "』", "》", "〉", "】", "〕", "〗", "〙", "〛", "\"", "'", ")", "]", "}"]
        let characters = Array(text)
        var candidates = 0, afterMark = 0, afterQuote = 0, afterHan = 0, afterLineStart = 0, afterOther = 0
        for (index, character) in characters.enumerated() where character == "\u{3000}" {
            guard index > 0 else { afterLineStart += 1; continue }
            let previous = characters[index - 1]
            if marks.contains(previous) {
                afterMark += 1; candidates += 1
            } else if closers.contains(previous) {
                afterQuote += 1; candidates += 1
            } else if previous == "\n" {
                afterLineStart += 1
            } else if previous.unicodeScalars.first.map({ (0x4E00...0x9FFF).contains($0.value) }) == true {
                afterHan += 1
            } else {
                afterOther += 1
            }
        }
        return (candidates, afterMark, afterQuote, afterHan, afterLineStart, afterOther)
    }
}
