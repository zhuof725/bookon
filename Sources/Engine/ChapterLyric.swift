import Foundation

/// 书源字幕（`ruleContent.subContent`）的执行入口。
///
/// Legado 里 subContent 是给听书用的「副文」规则：番茄这类源会把整章音频的
/// 逐句时间戳拉下来，输出 LRC 文本。原版拿到后交给播放页做逐句高亮。
/// 没有这个规则的书源返回 nil，调用方退回本地停顿估算。
enum ChapterLyric {
    /// 执行 subContent，返回 LRC 原文（可能为空串）。
    /// - Parameter content: 章节目录页/正文请求拿到的原始内容，作为规则求值的 `result`。
    static func load(source: BookSource?, book: Book, chapter: BookChapter,
                     content: String? = nil) -> String? {
        guard let source,
              let rule = source.ruleContent?.subContent?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rule.isEmpty else { return nil }
        // 字幕规则通常自带 @js:，它要访问 chapter/book 变量，需要完整上下文。
        let context = RuleContext(source: source, book: book, chapter: chapter)
        let ar = AnalyzeRule(content: content ?? chapter.url, baseUrl: chapter.url,
                             jsLib: source.jsLib, context: context)
        let text = ar.getString(rule).trimmingCharacters(in: .whitespacesAndNewlines)
        // 只在求值出错时报错：空结果本身是合法情况（这本书没有字幕）。
        if let error = JSEngine.lastError, !error.isEmpty {
            DebugLog.add("◇subContent 执行失败：\(error)")
            return nil
        }
        return text.isEmpty ? nil : text
    }
}
