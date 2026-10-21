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
        // 原版把书源原始的 src（含 `,{...}` 选项）交给 imageDecode 脚本。
        // 番茄系段评的脚本要从中正则提取 createSvg(...) 的参数来定位缓存键，
        // 去掉选项就匹配不到 → 标记没被清掉 → 点击被跳过。
        switch block {
        case .inlineBubble(let src, let count, let click, let raw):
            let target = raw ?? src
            return .inlineBubble(src: decode(target), count: count, clickURL: click, rawSrc: raw)
        case .image(let src, let click, let raw):
            let target = raw ?? src
            return .image(src: decode(target), clickURL: click, rawSrc: raw)
        default:
            return block
        }
    }
}
