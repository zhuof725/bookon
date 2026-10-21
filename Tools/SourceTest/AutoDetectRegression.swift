import Foundation
import SwiftSoup

/// 「不改书源也能用」的自动识别兜底回归。
/// 站点改版后规则整段失效（目录链接没了、章节列表换 class、正文容器改名），
/// 引擎要能从页面通用特征里把内容找回来。
enum AutoDetectRegression {
    static func run(_ check: (Bool, String) -> Void) {
        let detail = """
        <html><head>
        <meta property="og:novel:book_name" content="测试书名">
        <meta property="og:novel:author" content="测试作者">
        <meta property="og:description" content="这是一段测试简介。">
        <meta property="og:image" content="/cover.jpg">
        <meta property="og:novel:category" content="玄幻">
        <meta property="og:novel:latest_chapter_name" content="第9章 大结局">
        </head><body>
        <div class="book"><a href="/novel/1.html">测试书名</a></div>
        <a href="/other/chapters/id/1.html"><span>查看目录</span></a>
        </body></html>
        """
        guard let doc = try? SwiftSoup.parse(detail, "https://example.invalid/novel/1.html") else {
            check(false, "详情页解析"); return
        }
        check(AutoDetect.metaName(doc) == "测试书名", "og: 书名")
        check(AutoDetect.metaAuthor(doc) == "测试作者", "og: 作者")
        check(AutoDetect.metaCover(doc) == "/cover.jpg", "og: 封面")
        check(AutoDetect.metaKind(doc) == "玄幻", "og: 分类")
        check(AutoDetect.metaLastChapter(doc) == "第9章 大结局", "og: 最新章节")
        check(AutoDetect.tocLink(in: doc, baseUrl: "https://example.invalid/novel/1.html")
                == "https://example.invalid/other/chapters/id/1.html", "自动识别目录链接")

        // 目录页：站点把 mulu_list 换成了 section-list
        var tocHTML = "<html><body><div class=\"nav\"><a href=\"/\">首页</a><a href=\"/p/2\">下一页</a></div><ul class=\"section-list\">"
        for i in 1...12 {
            tocHTML += "<li><a href=\"/book/1/c\(i).html\">第\(i)章 标题\(i)</a></li>"
        }
        tocHTML += "</ul></body></html>"
        guard let tocDoc = try? SwiftSoup.parse(tocHTML, "https://example.invalid/other/chapters/id/1.html") else {
            check(false, "目录页解析"); return
        }
        let chapters = AutoDetect.chapters(in: tocDoc, baseUrl: "https://example.invalid/other/chapters/id/1.html")
        check(chapters.count == 12, "自动识别章节列表（实际 \(chapters.count)）")
        check(chapters.first?.title == "第1章 标题1", "章节标题正确")
        check(chapters.first?.url == "https://example.invalid/book/1/c1.html", "章节地址转绝对路径")

        // 正文页：正文容器换了名字，且页面里有大量导航链接
        var contentHTML = "<html><body><div class=\"nav\">"
        for i in 0..<20 { contentHTML += "<a href=\"/n/\(i)\">导航\(i)</a>" }
        contentHTML += "</div><div class=\"content_txt\">"
        for i in 0..<12 { contentHTML += "<p>这是正文第\(i)段，内容需要足够长才会被识别为正文容器。</p>" }
        contentHTML += "</div></body></html>"
        guard let contentDoc = try? SwiftSoup.parse(contentHTML, "https://example.invalid/book/1/c1.html") else {
            check(false, "正文页解析"); return
        }
        let text = AutoDetect.content(in: contentDoc)
        check(text.contains("这是正文第0段"), "自动识别正文容器")
        check(!text.contains("导航0"), "不会把导航当正文")

        // 端到端：规则全空时，详情页仍能从 og: meta 补齐
        var source = BookSource(bookSourceUrl: "https://example.invalid", bookSourceName: "自动识别测试")
        source.ruleBookInfo = BookInfoRule()
        var book = Book(bookUrl: "https://example.invalid/novel/1.html", name: "", origin: source.bookSourceUrl)
        book.originName = source.bookSourceName
        let parsed = WebBook.parseBookInfo(source: source, book: book, body: detail,
                                           url: "https://example.invalid/novel/1.html",
                                           context: RuleContext(source: source))
        check(parsed.name == "测试书名", "规则为空时书名由 og: meta 补齐（实际 \(parsed.name)）")
        check(parsed.author == "测试作者", "规则为空时作者由 og: meta 补齐")
        check(parsed.tocUrl == "https://example.invalid/other/chapters/id/1.html", "规则为空时目录链接自动识别")
    }
}
