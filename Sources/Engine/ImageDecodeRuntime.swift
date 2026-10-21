import Foundation

/// `ruleContent.imageDecode`：原版对正文里的每张图片求值一次，
/// 脚本里 `src` 是图片地址，返回值是替换后的地址（多数书源只是借它做副作用，
/// 例如番茄系段评用它清理「已经展示过气泡」的内存标记）。
enum ImageDecodeRuntime {
    static func apply(_ block: ContentBlock, rule: String, source: BookSource,
                      context: RuleContext, baseURL: String) -> ContentBlock {
        func decode(_ src: String) -> String {
            guard !src.isEmpty else { return src }
            if let out = JSEngine.shared.evalString(rule, result: src, baseUrl: baseURL,
                                                    jsLib: source.jsLib, context: context),
               !out.isEmpty {
                return out
            }
            return src
        }
        switch block {
        case .inlineBubble(let src, let count, let click):
            return .inlineBubble(src: decode(src), count: count, clickURL: click)
        case .image(let src, let click):
            return .image(src: decode(src), clickURL: click)
        default:
            return block
        }
    }
}
