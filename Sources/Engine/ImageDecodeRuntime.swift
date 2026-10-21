import Foundation

/// `ruleContent.imageDecode`：原版对正文里的每张图片求值一次，
/// 脚本里 `src` 是图片地址，返回值是替换后的地址（多数书源只是借它做副作用，
/// 例如番茄系段评用它清理「已经展示过气泡」的内存标记）。
enum ImageDecodeRuntime {
    /// 对一张图片执行 imageDecode 规则。脚本里 `src` = 这张图片的原始地址
    /// （含 `,{...}` 选项），返回值是替换后的地址；脚本报错时保留原地址。
    static func decode(_ src: String, rule: String, source: BookSource,
                       context: RuleContext, baseURL: String) -> String {
        guard !src.isEmpty else { return src }
        // srcOverride 让脚本里的 `src` = 这张图片的地址（原版语义）。
        if let out = JSEngine.shared.evalString(rule, result: src, baseUrl: baseURL,
                                                jsLib: source.jsLib, context: context,
                                                srcOverride: src),
           !out.isEmpty {
            return out
        }
        return src
    }

    /// 兼容旧调用：对已经解析好的块再跑一次规则。
    static func apply(_ block: ContentBlock, rule: String, source: BookSource,
                      context: RuleContext, baseURL: String) -> ContentBlock {
        switch block {
        case .inlineBubble(let src, let count, let click, let raw):
            let target = raw ?? src
            return .inlineBubble(src: decode(target, rule: rule, source: source, context: context, baseURL: baseURL),
                                 count: count, clickURL: click, rawSrc: raw)
        case .image(let src, let click, let raw):
            let target = raw ?? src
            return .image(src: decode(target, rule: rule, source: source, context: context, baseURL: baseURL),
                          clickURL: click, rawSrc: raw)
        default:
            return block
        }
    }
}
