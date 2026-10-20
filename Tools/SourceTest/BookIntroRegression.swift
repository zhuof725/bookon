import Foundation

/// 简介规则兼容性回归：`<useweb>`（CSS/HTML 简介）、`<usehtml>`、`<md>` 与原版一致。
///
/// 番茄系聚合源（番茄🍅（沐凡）等）的 ruleBookInfo.intro 返回整段 HTML，
/// 外层用 `<useweb>` 包裹（原版注释：「支持使用浏览器渲染」）。
/// 原版 BookInfo 对这三种标记**原样保留**，只有普通简介才走 HtmlFormatter.formatIntro 归一；
/// 之前我们无条件 displayIntro，把 `<div style=…>`/`<svg>` 全抹平了。
enum BookIntroRegression {
    static func run(_ check: (Bool, String) -> Void) async throws {
        // MARK: 形态判定

        let web = "<useweb><div style=\"color:inherit\"><p>正文</p></div></useweb>"
        check(BookIntro.normalized(web) == web, "useweb：详情解析原样保留")
        check(BookIntro.normalized("  \n" + web + "  ") == web, "useweb：前导空白按 trimStart 处理")
        check(BookIntro.parse(web)?.kind == .web, "useweb：识别为 WebView 渲染")
        check(BookIntro.parse(web)?.body == "<div style=\"color:inherit\"><p>正文</p></div>",
              "useweb：去掉包裹标签（实际 \(BookIntro.parse(web)?.body ?? "nil")）")
        check(BookIntro.parse(web)?.plainText == "正文", "useweb：列表用纯文本")

        let html = "<usehtml><p style=\"text-align:end\">右对齐</p></usehtml>"
        check(BookIntro.parse(html)?.kind == .html, "usehtml：识别为 HTML")
        check(BookIntro.parse(html)?.body == "<p style=\"text-align:end\">右对齐</p>",
              "usehtml：去掉包裹标签")
        let action = "<usehtml><p>右</p><button>点我@onclick:java.toast(\"Hello\")</button></usehtml>"
        check(BookIntro.parse(action)?.renderBody.contains("@onclick") == false,
              "usehtml：按钮动作源码不显示")
        check(BookIntro.parse(action)?.renderBody.contains("点我") == true,
              "usehtml：按钮文字保留")

        let md = "<md># 标题\n正文</md>"
        check(BookIntro.parse(md)?.kind == .markdown, "md：识别为 Markdown")
        check(BookIntro.normalized(md) == md, "md：详情解析原样保留")

        // 普通简介仍按原版归一（换行、实体、去标签）
        check(BookIntro.normalized("<p>第一段</p><br>第二段 &amp; 结尾") == "第一段\n第二段 & 结尾",
              "普通简介：归一成纯文本（实际 \(BookIntro.normalized("<p>第一段</p><br>第二段 &amp; 结尾") ?? "nil")）")
        check(BookIntro.parse("纯文本简介")?.kind == .text, "纯文本：不做富文本渲染")
        check(BookIntro.normalized("   ") == nil, "空白简介：nil")

        // MARK: 真实书源的 intro 规则走完整详情解析

        let fixture = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Tools/SourceTest/Fixtures/mufan-fanqie-source.json")
        guard let data = try? Data(contentsOf: fixture),
              let sources = try? JSONDecoder().decode([BookSource].self, from: data),
              let source = sources.first, source.ruleBookInfo?.intro != nil else {
            check(false, "沐凡书源：夹具可用且 ruleBookInfo.intro 存在")
            return
        }
        let book = Book(bookUrl: "https://fqaggregate.de5.net/api/detail?book_id=7208454824847739938&ys_module=3",
                        name: "开局激活神豪系统，获得无限黑卡", origin: source.bookSourceUrl)
        let parsed = WebBook.parseBookInfo(source: source, book: book,
                                           body: Self.detailJSON, url: book.bookUrl,
                                           context: RuleContext(source: source))
        let intro = parsed.intro ?? ""
        if !intro.hasPrefix("<useweb>") {
            print("  诊断：intro 前 120 字 = \(String(intro.prefix(120)))")
        }
        check(intro.hasPrefix("<useweb>"), "沐凡：richIntro 简介保留 useweb 包裹")
        check(intro.contains("作品简介") && intro.contains("作品数据") && intro.contains("题材标签"),
              "沐凡：简介包含各分区（实际长度 \(intro.count)）")
        if let parsedIntro = BookIntro.parse(intro) {
            check(parsedIntro.kind == .web, "沐凡：按 WebView 渲染")
            check(parsedIntro.body.contains("<section") && parsedIntro.body.contains("style="),
                  "沐凡：正文保留内联 CSS")
            check(!parsedIntro.body.lowercased().contains("<useweb>")
                  && !parsedIntro.body.lowercased().contains("</useweb>"),
                  "沐凡：正文已去掉包裹标签")
        } else {
            check(false, "沐凡：简介可解析")
        }
    }

    /// 与真实详情接口同形的响应（int 字段尽量用字符串，和上游一致）。
    static let detailJSON = """
    {"code":0,"msg":"ok","data":{"book_id":"7208454824847739938","book_name":"开局激活神豪系统，获得无限黑卡",\
    "author":"怒目金刚","abstract":"【神豪】+【系统】+【异能】+【无敌】+【装逼打脸】+【无脑爽文】\\n大一新生秦川，获得超级神豪系统，随机触发任务。",\
    "creation_status":"1","word_number":"5362106","score":"8.4","sub_info":"4万人在读","serial_count":"2588",\
    "last_chapter_title":"第2588章 原则上同意","create_time":"2023-03-09 16:06:16","last_chapter_update_time":"1760846400",\
    "category":"都市脑洞","tags":"都市,系统,神豪","role":"秦川,苏小妍","source":"番茄小说",\
    "copyright":"番茄小说授权发行","copyright_info":"本书的数字版权由 番茄小说 提供并授权发行","book_search_visible":"true",\
    "author_info":{"user_name":"怒目金刚","description":"关注我，掌握书籍最新动态"},"tones":["清朗","甜美女声"],\
    "ys_module":3}}
    """
}
