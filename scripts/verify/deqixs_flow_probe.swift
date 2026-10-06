//
//  deqixs_flow_probe.swift
//
//  本地（Linux）探针：复刻 WebBookRealSourcesEndToEndTests 里「得奇小说网」的四阶段
//  （搜索 → 详情 → 目录 → 正文），使用与该测试**完全一致**的 mock 构造方式
//  （set(_:_:) 逐个写入，而非字典字面量）。
//
//  为什么单独做这个探针：得奇小说网的详情页与目录页是**同一个 URL**
//  （bookURL == tocURL = https://www.deqixs.org/book/2001/），此前的字典字面量写法
//  会在运行期触发 Swift `Fatal error: Dictionary literal contains duplicate keys`
//  并直接终止进程（CI run 37449176865）。这里验证改成 set(_:_:) 后：
//    1) 不再崩溃；
//    2) 四阶段仍能解析出**精确值**。
//

import Foundation
import LegadoBookSource

var PASS = 0, FAIL = 0
func check(_ cond: Bool, _ msg: String) {
    if cond { PASS += 1 } else { FAIL += 1; print("  [X] \(msg)") }
}
func eq<T: Equatable>(_ a: T, _ b: T, _ msg: String) {
    if a == b { PASS += 1 } else { FAIL += 1; print("  [X] \(msg)  期望 \(b), 实际 \(a)") }
}

let base = "Tests/LegadoWebBookTests/Resources/real/"

func deqixsSource() throws -> BookSource {
    let all = try LegadoJSON.decoder.decode([BookSource].self,
        from: try Data(contentsOf: URL(fileURLWithPath: base + "real_sources_5.json")))
    guard let s = all.first(where: { $0.bookSourceName == "📂得奇小说网" }) else {
        throw RuleEngineError.unsupported("no deqixs source")
    }
    return s
}

let searchBody = """
<div class="item">
  <h3><a href="https://www.deqixs.org/book/2001/">合成得奇之书</a></h3>
  <img src="https://www.deqixs.org/img/2001.jpg">
  <div class="itemtxt">
    <p>简介：合成得奇简介<span>都市</span><span>连载中</span><span>88万字</span></p>
    <p><a href="/author/2">合成作者乙</a></p>
    <ul><li><a href="/c/1.html">第一章 得奇起始</a></li></ul>
  </div>
</div>
"""

let infoBody = """
<div class="item">
  <img src="https://www.deqixs.org/img/2001.jpg">
  <div class="itemtxt">
    <h1><a href="/book/2001/">合成得奇之书</a></h1>
    <p>简介：合成得奇简介<span>都市</span><span>连载中</span><span>88万字</span></p>
    <p><a href="/author/2">合成作者乙</a></p>
    <ul><li><a href="/c/1.html">第一章 得奇起始</a></li></ul>
  </div>
  <div class="des">合成得奇简介正文。</div>
</div>
"""

let tocBody = """
<div id="list">
  <li><a href="/c/1.html">第一章 得奇起始</a></li>
  <li><a href="/c/2.html">第二章 得奇发展</a></li>
</div>
"""

let contentBody = """
<div class="con"><p>得奇合成正文第一段。</p><p>得奇合成正文第二段。</p></div>
"""

@main
struct Probe {
    static func main() async {
        do {
            try await run()
        } catch {
            FAIL += 1
            print("  [X] 抛异常：\(error)")
        }
        print("\nPASS=\(PASS) FAIL=\(FAIL)")
        exit(FAIL == 0 ? 0 : 1)
    }

    static func run() async throws {
        let src = try deqixsSource()
        let searchURL = "https://www.deqixs.org/modules/article/search.php"
        let bookURL = "https://www.deqixs.org/book/2001/"
        let tocURL = "https://www.deqixs.org/book/2001/"   // ← 与 bookURL 相同
        let contentURL = "https://www.deqixs.org/c/1.html"

        // 与单元测试一致的构造方式：set(_:_:) 逐个写入。
        let net = MockWebBookNetwork()
        net.set(searchURL, WebBookResponse(url: searchURL, status: 200, body: searchBody))
        net.set(bookURL, WebBookResponse(url: bookURL, status: 200, body: infoBody))
        net.set(tocURL, WebBookResponse(url: tocURL, status: 200, body: tocBody))
        net.set(contentURL, WebBookResponse(url: contentURL, status: 200, body: contentBody))
        let opts = WebBookOptions(network: net)

        // 搜索
        let books = try await WebBook.searchBookAwait(bookSource: src, key: "斗罗", options: opts)
        eq(books.count, 1, "搜索返回 1 本")
        eq(books.first?.name ?? "", "合成得奇之书", "搜索书名")
        eq(books.first?.author ?? "", "合成作者乙", "搜索作者")
        eq(books.first?.bookUrl ?? "", bookURL, "搜索 bookUrl")
        eq(books.first?.wordCount ?? "", "88万字", "搜索字数")
        eq(books.first?.latestChapterTitle ?? "", "第一章 得奇起始", "搜索最新章节")

        var book = try XCTUnwrapLite(books.first).toBook()
        book.bookUrl = bookURL

        // 详情
        book = try await WebBook.getBookInfoAwait(bookSource: src, book: &book, options: opts)
        eq(book.name, "合成得奇之书", "详情书名")
        eq(book.author, "合成作者乙", "详情作者")
        eq(book.wordCount ?? "", "88万字", "详情字数")

        // 目录
        book.tocUrl = tocURL
        let chapters = try await WebBook.getChapterListAwait(bookSource: src, book: &book, options: opts)
        eq(chapters.count, 2, "目录章数")
        eq(chapters.map(\.title), ["第一章 得奇起始", "第二章 得奇发展"], "目录标题")

        // 正文
        let content = try await WebBook.getContentAwait(bookSource: src, book: book,
                                                        bookChapter: chapters[0], options: opts)
        check(content.contains("得奇合成正文第一段。"), "正文含第一段")
        check(content.contains("得奇合成正文第二段。"), "正文含第二段")
    }
}

enum ProbeError: Error { case nilValue }
func XCTUnwrapLite<T>(_ v: T?) throws -> T {
    guard let v = v else { throw ProbeError.nilValue }
    return v
}
