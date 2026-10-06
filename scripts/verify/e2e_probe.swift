//
//  e2e_probe.swift
//  scripts/verify
//
//  Linux 本地探针：用**真实书源规则** + 合成响应，跑通 搜索→详情→目录→正文，
//  打印每一步的真实解析结果，用于确定端到端测试里的精确断言值。
//
//  ⚠️ Linux 无 JavaScriptCore，`{{key}}` 不会被求值（macOS/iOS 上会）。
//  因此本探针在跑之前把书源里的 `{{key}}` 做与 CI 等价的文本替换，
//  使 WebBook 内部构造出的 AnalyzeUrl.url 与 CI（真实 JSC）一致。
//  被测的仍是**规则解析**逻辑本身。
//

import Foundation
import LegadoBookSource

let base = "Tests/LegadoWebBookTests/Resources/real/"

func loadSources7() throws -> [BookSource] {
    var all: [BookSource] = []
    all += try LegadoJSON.decoder.decode([BookSource].self,
        from: try Data(contentsOf: URL(fileURLWithPath: base + "real_sources_5.json")))
    for f in ["muli_real_source.json", "qimo_real_source.json"] {
        let d = try Data(contentsOf: URL(fileURLWithPath: base + f))
        // 这两个文件是**单元素 JSON 数组**。
        all += try LegadoJSON.decoder.decode([BookSource].self, from: d)
    }
    return all
}

func subst(_ s: String, key: String, page: Int = 1) -> String {
    s.replacingOccurrences(of: "{{key}}", with: key)
     .replacingOccurrences(of: "{{page-1}}", with: String(page - 1))
     .replacingOccurrences(of: "{{page}}", with: String(page))
}

func line(_ label: String, _ value: String?) { print("   \(label): \(value?.debugDescription ?? "<nil>")") }

func probe(_ name: String, _ source: BookSource, key: String,
           searchBody: String, infoBody: String, tocBody: String, contentBody: String,
           bookURL: String, tocURL: String, contentURL: String) {
    print("\n================ \(name) ================")
    var src = source
    if let v = src.searchUrl { src.searchUrl = subst(v, key: key) }
    if let v = src.exploreUrl { src.exploreUrl = subst(v, key: key) }
    guard let su = src.searchUrl else { print(" no searchUrl"); return }
    print("   searchUrl = \(su)")

    let searchURL = AnalyzeUrl(su, key: key, page: 1, baseUrl: src.bookSourceUrl,
                               source: InMemorySource(key: src.bookSourceUrl),
                               ruleData: FlowRuleData()).url
    print("   resolved  = \(searchURL)")

    var entries: [String: WebBookResponse] = [:]
    entries[searchURL] = WebBookResponse(url: searchURL, status: 200, body: searchBody)
    entries[bookURL] = WebBookResponse(url: bookURL, status: 200, body: infoBody)
    entries[tocURL] = WebBookResponse(url: tocURL, status: 200, body: tocBody)
    entries[contentURL] = WebBookResponse(url: contentURL, status: 200, body: contentBody)
    print("   mock keys = \(Array(entries.keys).sorted())")
    let net = MockWebBookNetwork(entries)
    let opts = WebBookOptions(network: net)
    let sem = DispatchSemaphore(value: 0)

    let srcSnapshot = src
    Task {
        do {
            let books = try await WebBook.searchBookAwait(bookSource: srcSnapshot, key: key, options: opts)
            print("   SEARCH count=\(books.count)")
            for (i, b) in books.enumerated() {
                print("     [\(i)] name=\(b.name.debugDescription) author=\(b.author.debugDescription)")
                print("          url=\(b.bookUrl.debugDescription) kind=\(b.kind?.debugDescription ?? "<nil>")")
                print("          wc=\(b.wordCount?.debugDescription ?? "<nil>") last=\(b.latestChapterTitle?.debugDescription ?? "<nil>")")
            }
            guard var book = books.first.map({ $0.toBook() }) else { sem.signal(); return }
            book.bookUrl = bookURL

            book = try await WebBook.getBookInfoAwait(bookSource: srcSnapshot, book: &book, options: opts)
            // 详情阶段若规则无 tocUrl，会回退到 baseUrl；探针里显式覆盖为合成目录页 URL。
            book.tocUrl = tocURL
            print("   INFO")
            line("name", book.name); line("author", book.author)
            line("kind", book.kind); line("wc", book.wordCount)
            line("intro", book.intro); line("last", book.latestChapterTitle)
            line("tocUrl", book.tocUrl)

            let chapters = try await WebBook.getChapterListAwait(bookSource: srcSnapshot, book: &book, options: opts)
            print("   TOC count=\(chapters.count)")
            for (i, c) in chapters.enumerated() { print("     [\(i)] \(c.title.debugDescription) -> \(c.url)") }

            if let first = chapters.first {
                let content = try await WebBook.getContentAwait(bookSource: srcSnapshot, book: book, bookChapter: first, options: opts)
                print("   CONTENT len=\(content.count)")
                print("     first60=\(String(content.prefix(60)).debugDescription)")
            }
        } catch { print("   ERR \(error)") }
        sem.signal()
    }
    sem.wait()
}

// MARK: - 合成响应（规则真实、数据合成）

let sources = try loadSources7()
print("loaded=\(sources.count)")
func src(_ n: String) -> BookSource { sources.first { $0.bookSourceName == n }! }
let key = "斗罗"

// ── 1. 速读谷（@css；`:eq(n)` 按同级 Element 序号）
// ruleSearch.author = `.itemtxt p:eq(1) a##作者：` → 同级 Element 序号 1 的 <p> 内含作者 <a>
probe("速读谷", src("速读谷"), key: key,
  searchBody: """
  <div class="item">
    <a href="/img/1001.jpg"></a>
    <div class="itemtxt">
      <h3><a href="https://www.shudugu.org/book/1001.html">合成速读之书</a></h3>
      <p><span>玄幻</span></p>
      <p><a href="/author/1">作者：合成作者甲</a></p>
      <ul><li><a href="/c/1.html">第一章 起始</a></li></ul>
    </div>
  </div>
  """,
  infoBody: """
  <div class="item">
    <div class="itemtxt"><h1><a href="/book/1001.html">合成速读之书</a><i>123万字</i></h1></div>
    <div class="itemtxt"><p><span>玄幻</span></p></div>
    <div class="itemtxt"><p><a href="/author/1">作者：合成作者甲</a></p></div>
    <div class="itemtxt"><ul><li><a href="/c/1.html">第一章 起始</a></li></ul></div>
    <div class="des">合成速读简介。</div>
  </div>
  """,
  tocBody: """
  <div id="list"><ul>
    <li><a href="/c/1.html">第一章 起始</a></li>
    <li><a href="/c/2.html">第二章 发展</a></li>
    <li><a href="/c/3.html">第三章 结束</a></li>
  </ul></div>
  """,
  contentBody: """
  <div class="con"><p>速读谷合成正文第一段。</p><p>速读谷合成正文第二段。</p></div>
  """,
  bookURL: "https://www.shudugu.org/book/1001.html",
  tocURL: "https://www.shudugu.org/toc/1001.html",
  contentURL: "https://www.shudugu.org/c/1.html")

// ── 2. 得奇小说网（SwiftSoup 风格 class.item / tag.h1）
probe("📂得奇小说网", src("📂得奇小说网"), key: key,
  searchBody: """
  <div class="item">
    <h3><a href="https://www.deqixs.org/book/2001/">合成得奇之书</a></h3>
    <img src="https://www.deqixs.org/img/2001.jpg">
    <div class="itemtxt">
      <p>简介：合成得奇简介<span>都市</span><span>连载中</span><span>88万字</span></p>
      <p><a href="/author/2">合成作者乙</a></p>
      <ul><li><a href="/c/1.html">第一章 得奇起始</a></li></ul>
    </div>
  </div>
  """,
  infoBody: """
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
  """,
  tocBody: """
  <div id="list">
    <li><a href="/c/1.html">第一章 得奇起始</a></li>
    <li><a href="/c/2.html">第二章 得奇发展</a></li>
  </div>
  """,
  contentBody: """
  <div class="con"><p>得奇合成正文第一段。</p><p>得奇合成正文第二段。</p></div>
  """,
  bookURL: "https://www.deqixs.org/book/2001/",
  tocURL: "https://www.deqixs.org/book/2001/",
  contentURL: "https://www.deqixs.org/c/1.html")

// ── 3. 爱丽丝书屋（原生 XPath；正文规则含 org.jsoup → 第 5 步替代实现）
probe("🌸爱丽丝书屋(免翻)", src("🌸爱丽丝书屋(免翻)"), key: key,
  searchBody: """
  <div class="list-group">
    <div class="list-group-item">
      <h5><a href="/book/3001.html">合成爱丽丝之书<small>连载</small></a></h5>
      <p class="text-muted"><a href="/tag/1">奇幻</a></p>
      <p class="mb-1 text-muted">作者: <a href="/author/3">合成作者丙</a> 1.2万 阅读</p>
      <p class="content-txt">合成爱丽丝简介。</p>
    </div>
  </div>
  """,
  infoBody: """
  <div class="pic"><img src="/img/3001.jpg"><div class="tLJ">合成爱丽丝信息</div></div>
  <div class="box_info"><table><tbody>
    <tr><td><div><p><a href="/author/3">合成作者丙</a><a href="/c/1.html">第一章 爱丽丝起始</a></p></div>
        <div><h1>合成爱丽丝之书</h1></div></td></tr>
    <tr><td><div class="intro">合成爱丽丝简介正文。</div></td></tr>
    <tr><td><p><a href="/tag/1">奇幻</a></p></td></tr>
  </tbody></table></div>
  <div class="book_newchap"><a href="/toc/3001.html">查看所有章节</a></div>
  """,
  tocBody: """
  <ul class="mulu_list">
    <li><a href="/c/1.html">第一章 爱丽丝起始</a></li>
    <li><a href="/c/2.html">第二章 爱丽丝发展</a></li>
  </ul>
  """,
  contentBody: """
  <div class="read-content"><p>爱丽丝合成正文第一段，这是一段足够长的文字用于通过长度校验。</p><p>爱丽丝合成正文第二段，同样足够长。</p></div>
  """,
  bookURL: "https://xn--vcsx64d.alicesw12.xyz/book/3001.html",
  tocURL: "https://xn--vcsx64d.alicesw12.xyz/toc/3001.html",
  contentURL: "https://xn--vcsx64d.alicesw12.xyz/c/1.html")

// ── 4. 淘小说书城（纯 JSONPath）
probe("⚡📂淘小说书城", src("⚡📂淘小说书城"), key: key,
  searchBody: """
  {"code":0,"data":{"bookList":[
    {"authorName":"合成作者丁","title":"合成淘小说之书","coverUrl":"/c/1.jpg",
     "intro":"合成淘小说简介。","categoryName":"科幻","allWords":"66万",
     "sourceName":"tf","sourceId":"4001"}]}}
  """,
  infoBody: """
  {"code":0,"data":{"title":"合成淘小说之书","authorName":"合成作者丁","intro":"合成淘小说简介正文。",
    "categoryName":"科幻","latestChapter":"第一章 淘小说起始","allWords":"66万",
    "sourceId":"4001","coverUrl":"/c/1.jpg"}}
  """,
  tocBody: """
  {"code":0,"data":{"chapters":[
    {"chapterId":"1","chapterTitle":"第一章 淘小说起始"},
    {"chapterId":"2","chapterTitle":"第二章 淘小说发展"}]}}
  """,
  contentBody: """
  {"code":0,"data":{"content":"淘小说合成正文第一段。\n淘小说合成正文第二段。"}}
  """,
  bookURL: "http://betam.taoyuewenhua.com/ajax/or/ty/book?sourceName=tf&sourceId=4001",
  tocURL: "http://betam.taoyuewenhua.com/ajax/or/authopt/ty/chapter_list?sourceName=tf&sourceId=4001&page=0&pageSize=100",
  contentURL: "http://betam.taoyuewenhua.com/ajax/or/authopt/ty/chapter_content?sourceName=tf&sourceId=4001&chapterId=1")

// ── 7. 七猫
probe("七猫小说（qimo）", src("七猫小说（qimo）"), key: key,
  searchBody: """
  {"data":{"books":[{"id":7001,"original_title":"七猫之书","original_author":"合成作者庚",
    "image_link":"/c/1.jpg","intro":"合成七猫简介。","ptags":"言情",
    "words_num":"55万","latest_chapter_title":"第一章 七猫起始"}]}}
  """,
  infoBody: """
  {"data":{"book":{"id":7001,"title":"七猫之书","author":"合成作者庚","image_link":"/c/1.jpg",
    "intro":"合成七猫简介正文。","book_tag_list":[{"title":"言情"}],"words_num":"55万",
    "latest_chapter_title":"第一章 七猫起始","update_time":"1700000000"}}}
  """,
  tocBody: """
  {"data":{"chapter_lists":[{"id":"1","title":"第一章 七猫起始","words":"2000"},
    {"id":"2","title":"第二章 七猫发展","words":"2100"}]}}
  """,
  contentBody: "{\"data\":{\"content\":\"\"}}",
  bookURL: "https://api-bc.wtzw.com/api/v4/book/detail?id=7001",
  tocURL: "https://api-ks.wtzw.com/api/v1/chapter/chapter-list?id=7001",
  contentURL: "https://api-ks.wtzw.com/api/v1/chapter/content?id=1")
