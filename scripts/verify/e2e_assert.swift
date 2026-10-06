//
//  e2e_assert.swift — 本地断言校验（无 XCTest）：把新 e2e 测试里的**精确断言**跑一遍。
//  Linux 无 XCTest；这里用等价的 if + 计数，确保 CI 上的断言一定成立。
//
import Foundation
import LegadoBookSource

let base = "Tests/LegadoWebBookTests/Resources/real/"
var PASS = 0, FAIL = 0
func check(_ cond: Bool, _ msg: String, file: String = #file, line: Int = #line) {
    if cond { PASS += 1 } else { FAIL += 1; print("  ❌ FAIL: \(msg)  [line \(line)]") }
}
func eq<T: Equatable>(_ a: T, _ b: T, _ msg: String, line: Int = #line) {
    if a == b { PASS += 1 } else { FAIL += 1; print("  ❌ FAIL: \(msg)  期望 \(b), 实际 \(a)  [line \(line)]") }
}

func loadRealSources() throws -> [BookSource] {
    var all = try LegadoJSON.decoder.decode([BookSource].self,
        from: try Data(contentsOf: URL(fileURLWithPath: base + "real_sources_5.json")))
    for f in ["muli_real_source.json", "qimo_real_source.json"] {
        all += try LegadoJSON.decoder.decode([BookSource].self,
            from: try Data(contentsOf: URL(fileURLWithPath: base + f)))
    }
    return all
}
func src(_ n: String) throws -> BookSource {
    guard let s = try loadRealSources().first(where: { $0.bookSourceName == n }) else {
        throw RuleEngineError.unsupported("no source \(n)")
    }
    return s
}

func safeMock(_ pairs: [(String, String)]) -> MockWebBookNetwork {
    var d: [String: WebBookResponse] = [:]
    for (u, b) in pairs { d[u] = WebBookResponse(url: u, status: 200, body: b) }
    return MockWebBookNetwork(d)
}


/// 与 CI 等价：Linux 无 JSC，`{{key}}` 不会被求值；这里做与 CI 相同的文本替换，
/// 使构造出的请求 URL 与 macOS/iOS（真实 JSC）一致。被测仍是规则解析逻辑。
func srcWithKey(_ n: String, key: String) throws -> BookSource {
    var s = try src(n)
    if let v = s.searchUrl {
        s.searchUrl = v.replacingOccurrences(of: "{{key}}", with: key)
                      .replacingOccurrences(of: "{{page-1}}", with: "0")
                      .replacingOccurrences(of: "{{page}}", with: "1")
    }
    return s
}

func run(_ name: String, _ body: @escaping () async throws -> Void) {
    print("\n== \(name) ==")
    let sem = DispatchSemaphore(value: 0)
    Task { do { try await body() } catch { FAIL += 1; print("  ❌ THROW: \(error)") }; sem.signal() }
    sem.wait()
}

// ── 加载器断言 ─
run("加载器：正好 7 个") {
    let all = try loadRealSources()
    let expected: [(String, String)] = [
        ("速读谷", "https://www.shudugu.org"),
        ("📂得奇小说网", "https://www.deqixs.org"),
        ("🌸爱丽丝书屋(免翻)", "https://xn--vcsx64d.alicesw12.xyz/"),
        ("⚡📂淘小说书城", "http://betam.taoyuewenhua.com"),
        ("⚡📂得间小说", "https://wechat.idejian.com##"),
        ("🍅木里番茄0922[GO聚合版]", "http://154.58.233.54:1968"),
        ("七猫小说（qimo）", "https://api-bc.wtzw.com#md"),
    ]
    eq(all.count, 7, "count")
    eq(all.map(\.bookSourceName), expected.map(\.0), "names")
    eq(all.map(\.bookSourceUrl), expected.map(\.1), "urls")
    for s in all { check(!s.bookSourceName.hasPrefix("synthetic_"), "synthetic_ 不应出现: \(s.bookSourceName)") }
}

// ── 特殊 URL 形态 ─
run("特殊 URL 形态") {
    let muli = try src("🍅木里番茄0922[GO聚合版]")
    eq(muli.bookSourceUrl, "http://154.58.233.54:1968", "muli url")
    let u = URL(string: muli.bookSourceUrl)!
    eq(u.scheme, "http", "muli scheme"); eq(u.host, "154.58.233.54", "muli host"); eq(u.port, 1968, "muli port")
    check(u.host!.allSatisfy { $0.isNumber || $0 == "." }, "muli host 应为裸 IP")

    let qimo = try src("七猫小说（qimo）")
    eq(qimo.bookSourceUrl, "https://api-bc.wtzw.com#md", "qimo url")
    check(qimo.bookSourceUrl.hasSuffix("#md"), "qimo #md")

    let alice = try src("🌸爱丽丝书屋(免翻)")
    check(alice.bookSourceUrl.contains("xn--"), "alice punycode")
    check(URL(string: alice.bookSourceUrl)!.host!.hasPrefix("xn--"), "alice host xn--")
}

// ── 速读谷 四阶段 ─
run("速读谷 搜索→详情→目录→正文") {
    let s = try srcWithKey("速读谷", key: "斗罗")
    let searchURL = "https://www.shudugu.org/i/sor.aspx?key=斗罗"
    let bookURL = "https://www.shudugu.org/book/1001.html"
    let tocURL = "https://www.shudugu.org/toc/1001.html"
    let contentURL = "https://www.shudugu.org/c/1.html"
    let searchBody = """
    <div class="item">
      <a href="/img/1001.jpg"></a>
      <div class="itemtxt">
        <h3><a href="https://www.shudugu.org/book/1001.html">合成速读之书</a></h3>
        <p><span>玄幻</span></p>
        <p><a href="/author/1">作者：合成作者甲</a></p>
        <ul><li><a href="/c/1.html">第一章 起始</a></li></ul>
      </div>
    </div>
    """
    let infoBody = """
    <div class="item">
      <div class="itemtxt"><h1><a href="/book/1001.html">合成速读之书</a><i>123万字</i></h1></div>
      <div class="itemtxt"><p><span>玄幻</span></p></div>
      <div class="itemtxt"><p><a href="/author/1">作者：合成作者甲</a></p></div>
      <div class="itemtxt"><ul><li><a href="/c/1.html">第一章 起始</a></li></ul></div>
      <div class="des">合成速读简介。</div>
    </div>
    """
    let tocBody = """
    <div id="list"><ul>
      <li><a href="/c/1.html">第一章 起始</a></li>
      <li><a href="/c/2.html">第二章 发展</a></li>
      <li><a href="/c/3.html">第三章 结束</a></li>
    </ul></div>
    """
    let contentBody = """
    <div class="con"><p>速读谷合成正文第一段。</p><p>速读谷合成正文第二段。</p></div>
    """
    let net = safeMock([
        (searchURL, searchBody), (bookURL, infoBody), (tocURL, tocBody), (contentURL, contentBody),
    ])
    let opts = WebBookOptions(network: net)
    let books = try await WebBook.searchBookAwait(bookSource: s, key: "斗罗", options: opts)
    eq(books.count, 1, "search count")
    eq(books[0].name, "合成速读之书", "search name")
    eq(books[0].bookUrl, bookURL, "search url")
    eq(books[0].kind, "玄幻", "search kind")
    eq(books[0].latestChapterTitle, "第一章 起始", "search last")

    var book = books[0].toBook()
    book.bookUrl = bookURL
    book = try await WebBook.getBookInfoAwait(bookSource: s, book: &book, options: opts)
    eq(book.name, "合成速读之书", "info name")
    eq(book.kind, "玄幻", "info kind")
    eq(book.wordCount, "123万字", "info wc")
    eq(book.intro, "合成速读简介。", "info intro")
    eq(book.latestChapterTitle, "第一章 起始", "info last")

    book.tocUrl = tocURL
    let chapters = try await WebBook.getChapterListAwait(bookSource: s, book: &book, options: opts)
    eq(chapters.count, 3, "toc count")
    eq(chapters.map(\.title), ["第一章 起始", "第二章 发展", "第三章 结束"], "toc titles")
    eq(chapters[0].url, "/c/1.html", "toc url0")

    let content = try await WebBook.getContentAwait(bookSource: s, book: book, bookChapter: chapters[0], options: opts)
    check(content.contains("速读谷合成正文第一段。"), "content p1")
    check(content.contains("速读谷合成正文第二段。"), "content p2")
    eq(String(content.prefix(10)), "速读谷合成正文第一段", "content prefix10")
}

// ── 得奇 四阶段 ─
run("得奇 搜索→详情→目录→正文") {
    let s = try src("📂得奇小说网")
    let searchURL = "https://www.deqixs.org/modules/article/search.php"
    let bookURL = "https://www.deqixs.org/book/2001/"
    let tocURL = "https://www.deqixs.org/book/2001/"
    let contentURL = "https://www.deqixs.org/c/1.html"
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
    let net = safeMock([
        (searchURL, searchBody), (bookURL, infoBody), (tocURL, tocBody), (contentURL, contentBody),
    ])
    let opts = WebBookOptions(network: net)
    let books = try await WebBook.searchBookAwait(bookSource: s, key: "斗罗", options: opts)
    eq(books.count, 1, "search count")
    eq(books[0].name, "合成得奇之书", "name")
    eq(books[0].author, "合成作者乙", "author")
    eq(books[0].bookUrl, bookURL, "url")
    eq(books[0].wordCount, "88万字", "wc")
    eq(books[0].latestChapterTitle, "第一章 得奇起始", "last")

    var book = books[0].toBook(); book.bookUrl = bookURL
    book = try await WebBook.getBookInfoAwait(bookSource: s, book: &book, options: opts)
    eq(book.name, "合成得奇之书", "info name")
    eq(book.author, "合成作者乙", "info author")
    eq(book.wordCount, "88万字", "info wc")

    book.tocUrl = tocURL
    let chapters = try await WebBook.getChapterListAwait(bookSource: s, book: &book, options: opts)
    eq(chapters.count, 2, "toc count")
    eq(chapters.map(\.title), ["第一章 得奇起始", "第二章 得奇发展"], "toc titles")

    let content = try await WebBook.getContentAwait(bookSource: s, book: book, bookChapter: chapters[0], options: opts)
    check(content.contains("得奇合成正文第一段。"), "content p1")
    check(content.contains("得奇合成正文第二段。"), "content p2")
}

// ── 爱丽丝 搜索→详情→目录 ─
run("爱丽丝 搜索→详情→目录") {
    let s = try srcWithKey("🌸爱丽丝书屋(免翻)", key: "斗罗")
    let searchURL = "https://xn--vcsx64d.alicesw12.xyz/search.html?q=斗罗&f=_al"
    let bookURL = "https://xn--vcsx64d.alicesw12.xyz/book/3001.html"
    let tocURL = "https://xn--vcsx64d.alicesw12.xyz/toc/3001.html"
    let searchBody = """
    <div class="list-group">
      <div class="list-group-item">
        <h5><a href="/book/3001.html">合成爱丽丝之书<small>连载</small></a></h5>
        <p class="text-muted"><a href="/tag/1">奇幻</a></p>
        <p class="mb-1 text-muted">作者: <a href="/author/3">合成作者丙</a> 1.2万 阅读</p>
        <p class="content-txt">合成爱丽丝简介。</p>
      </div>
    </div>
    """
    let infoBody = """
    <div class="pic"><img src="/img/3001.jpg"><div class="tLJ">合成爱丽丝信息</div></div>
    <div class="box_info"><table><tbody>
      <tr><td><div><p><a href="/author/3">合成作者丙</a><a href="/c/1.html">第一章 爱丽丝起始</a></p></div>
          <div><h1>合成爱丽丝之书</h1></div></td></tr>
      <tr><td><div class="intro">合成爱丽丝简介正文。</div></td></tr>
      <tr><td><p><a href="/tag/1">奇幻</a></p></td></tr>
    </tbody></table></div>
    <div class="book_newchap"><a href="/toc/3001.html">查看所有章节</a></div>
    """
    let tocBody = """
    <ul class="mulu_list">
      <li><a href="/c/1.html">第一章 爱丽丝起始</a></li>
      <li><a href="/c/2.html">第二章 爱丽丝发展</a></li>
    </ul>
    """
    let net = safeMock([
        (searchURL, searchBody), (bookURL, infoBody), (tocURL, tocBody),
    ])
    let opts = WebBookOptions(network: net)
    let books = try await WebBook.searchBookAwait(bookSource: s, key: "斗罗", options: opts)
    eq(books.count, 1, "search count")
    eq(books[0].name, "合成爱丽丝之书连载", "name")
    eq(books[0].author, "合成作者丙", "author")
    eq(books[0].bookUrl, bookURL, "url")

    var book = books[0].toBook(); book.bookUrl = bookURL
    book = try await WebBook.getBookInfoAwait(bookSource: s, book: &book, options: opts)
    eq(book.author, "合成作者丙", "info author")
    eq(book.name, "合成爱丽丝之书连载", "info name")
    eq(book.latestChapterTitle, "第一章 爱丽丝起始", "info last")

    book.tocUrl = tocURL
    let chapters = try await WebBook.getChapterListAwait(bookSource: s, book: &book, options: opts)
    eq(chapters.count, 2, "toc count")
    eq(chapters.map(\.title), ["第一章 爱丽丝起始", "第二章 爱丽丝发展"], "toc titles")
    eq(chapters[0].url, "/c/1.html", "toc url0")
}

// ── 淘小说 搜索 ─
run("淘小说 搜索") {
    let s = try srcWithKey("⚡📂淘小说书城", key: "斗罗")
    let searchURL = "http://betam.taoyuewenhua.com/ajax/or/authopt/ty/search_books?keywords=斗罗&page=0&pageSize=20&ctype=1"
    let searchBody = """
    {"code":0,"data":{"bookList":[
      {"authorName":"合成作者丁","title":"合成淘小说之书","coverUrl":"/c/1.jpg",
       "intro":"合成淘小说简介。","categoryName":"科幻","allWords":"66万",
       "sourceName":"tf","sourceId":"4001"}]}}
    """
    let net = MockWebBookNetwork([searchURL: WebBookResponse(url: searchURL, status: 200, body: searchBody)])
    let books = try await WebBook.searchBookAwait(bookSource: s, key: "斗罗", options: WebBookOptions(network: net))
    eq(books.count, 1, "search count")
    eq(books[0].name, "合成淘小说之书", "name")
    eq(books[0].author, "合成作者丁", "author")
    eq(books[0].kind, "科幻", "kind")
    eq(books[0].wordCount, "66万", "wc")
}

print("\n=========================")
print("PASS=\(PASS)  FAIL=\(FAIL)")
print("=========================")
if FAIL > 0 { exit(1) }
