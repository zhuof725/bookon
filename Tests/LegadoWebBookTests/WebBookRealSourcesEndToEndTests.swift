//
//  WebBookRealSourcesEndToEndTests.swift
//  LegadoBookSource
//
//  第 7 步 C 段返工：端到端测试（规则真实、数据合成）。
//
//  ── 方法论（必须在测试注释里说清，避免误读）──
//  * 「规则真实」：本文件用到的 ruleSearch / ruleBookInfo / ruleToc / ruleContent / searchUrl
//    全部逐字取自仓库内的真实书源配置，不做任何改写：
//      - Tests/LegadoWebBookTests/Resources/real/real_sources_5.json
//        按 name+URL 从「配置文件_14个.json」精确提取的 5 个书源（速读谷、得奇小说网、
//        爱丽丝书屋(免翻)、淘小说书城、得间小说）。
//      - Tests/LegadoWebBookTests/Resources/real/muli_real_source.json（木里番茄，逐字节复制）
//      - Tests/LegadoWebBookTests/Resources/real/qimo_real_source.json（七猫，逐字节复制）
//  * 「数据合成」：所有 HTTP 响应体（HTML / JSON）都是手工构造的合成数据，字段名/结构
//    严格按各书源规则形状对齐；**不是**真实站点内容，也不联网。
//  * 断言一律用**精确值**（书名、作者、章数、首章标题、正文片段），不使用「非空」这类弱断言。
//
//  ── 平台差异（重要，不撒谎）──
//  Linux 无 JavaScriptCore，`@js:` / `{{...}}` 规则无法求值（AnalyzeRule+JS.swift:63 明确抛
//  "JavaScriptCore 不可用"）。因此：
//    - **不依赖 JS** 的解析阶段（速读谷/得奇/爱丽丝 的 搜索/详情/目录/正文；
//      淘小说 的 搜索）在 macOS 与 iOS 上跑**完全相同**的断言；
//    - **依赖 JS 拼 URL** 的阶段（淘小说 详情url、得间 全部、七猫 全部、木里 全部）在
//      Linux 上无法推进，用 `#if canImport(JavaScriptCore)` 单独覆盖，保证 Apple 平台
//      （CI 的 test-macos / test-ios-simulator）真实跑到，且 macOS 与 iOS 用例数相等。
//
//  ── 特殊 URL 形态专门断言 ──
//    - 木里番茄：裸 IP + 端口（http://154.58.233.54:1968，无域名、无 TLS）；
//    - 七猫：baseUrl 带 `#md` 后缀（https://api-bc.wtzw.com#md）；
//    - 爱丽丝书屋：Punycode 域名（xn--vcsx64d.alicesw12.xyz）。
//

import XCTest
@testable import LegadoBookSource

/// 把 Debug 日志原样打到 stdout 的 sink（仅测试使用）。
///
/// 为什么要它：CI 失败时日志里只有断言消息，看不到「目录解析到第几步」。把流程层
/// 的真实日志逐行打印后，失败诊断只需读日志，不必再靠推测。
final class StdoutDebugSink: DebugLogSink {
    private let tag: String
    private let lock = NSLock()

    init(tag: String) { self.tag = tag }

    func printLog(state: Int, msg: String) {
        lock.lock(); defer { lock.unlock() }
        // 单行化，避免响应体里的换行把 CI 日志结构冲散。
        let oneLine = msg.replacingOccurrences(of: "\n", with: "⏎")
        print("[\(tag)][state=\(state)] \(oneLine)")
    }
}

final class WebBookRealSourcesEndToEndTests: XCTestCase {

    // MARK: - 资源加载（7 个真实书源）

    /// 资源目录内真实书源文件名（5 个合并文件 + 2 个单独文件）。
    private static let mergedFile = "real_sources_5"
    private static let singleFiles = ["muli_real_source", "qimo_real_source"]

    /// 在资源 bundle 里定位一个文件。
    ///
    /// ⚠️ 不要用 `subdirectory:`：`.copy("Resources/real/x.json")` 这类**单文件**资源
    /// 会被 SwiftPM **扁平化**到 bundle 根目录（已本地实测确认），bundle 内不存在
    /// `real/` 子目录。所以这里先按根目录找，再兜底找 `real/` 子目录，两种布局都能命中。
    private func resourceURL(name: String) -> URL? {
        let bundle = Bundle.module
        if let url = bundle.url(forResource: name, withExtension: "json") { return url }
        return bundle.url(forResource: name, withExtension: "json", subdirectory: "real")
    }

    /// 加载全部 7 个真实书源。任何一步缺失即 fail-stop（不用 XCTSkip 掩盖）。
    private func loadRealSources() throws -> [BookSource] {
        let mergedURL = try XCTUnwrap(
            resourceURL(name: Self.mergedFile),
            "缺少 real_sources_5.json（5 个真实书源合并文件）")
        var all = try decodeSources(try Data(contentsOf: mergedURL))
        for name in Self.singleFiles {
            let url = try XCTUnwrap(
                resourceURL(name: name),
                "缺少 \(name).json（真实书源文件）")
            all += try decodeSources(try Data(contentsOf: url))
        }
        return all
    }

    private func decodeSources(_ data: Data) throws -> [BookSource] {
        let trimmed = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        // 兼容两种形态：顶层 JSON 数组，或单个对象（取首元素语义）。
        if trimmed.hasPrefix("[") {
            return try LegadoJSON.decoder.decode([BookSource].self, from: data)
        }
        return [try LegadoJSON.decoder.decode(BookSource.self, from: data)]
    }

    /// 7 个书源按 (name, url) 精确定位；缺失即 fail-stop。
    private func source(named name: String) throws -> BookSource {
        let all = try loadRealSources()
        let hit = all.first { $0.bookSourceName == name }
        return try XCTUnwrap(hit, "真实书源中找不到 name=\(name)")
    }

    // MARK: - 加载器断言（正好 7 个；名字/URL 与交付表一致）

    /// 交付表（顺序即文件内出现顺序）。
    private static let expected: [(name: String, url: String)] = [
        ("速读谷", "https://www.shudugu.org"),
        ("📂得奇小说网", "https://www.deqixs.org"),
        ("🌸爱丽丝书屋(免翻)", "https://xn--vcsx64d.alicesw12.xyz/"),
        ("⚡📂淘小说书城", "http://betam.taoyuewenhua.com"),
        ("⚡📂得间小说", "https://wechat.idejian.com##"),
        ("🍅木里番茄0922[GO聚合版]", "http://154.58.233.54:1968"),
        ("七猫小说（qimo）", "https://api-bc.wtzw.com#md"),
    ]

    func testLoadsExactlySevenRealSources() throws {
        let all = try loadRealSources()
        XCTAssertEqual(all.count, 7, "真实书源数量必须是 7")
        XCTAssertEqual(all.map(\.bookSourceName), Self.expected.map(\.name), "书源名字与数量必须与交付表一致")
        XCTAssertEqual(all.map(\.bookSourceUrl), Self.expected.map(\.url), "书源 URL 必须与交付表一致")
    }

    func testAllSevenAreNotSynthetic() throws {
        // 「规则真实」的负向护栏：本目录不允许出现 synthetic_ 前缀的合成书源。
        for s in try loadRealSources() {
            XCTAssertFalse(s.bookSourceName.hasPrefix("synthetic_"), "\(s.bookSourceName) 不该出现在真实书源目录")
        }
    }

    func testAllSevenHaveNonEmptySearchUrl() throws {
        for s in try loadRealSources() {
            XCTAssertFalse(s.searchUrl?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true,
                           "\(s.bookSourceName) 缺少 searchUrl")
        }
    }

    func testAllSevenHaveSearchAndTocRules() throws {
        for s in try loadRealSources() {
            XCTAssertFalse(s.ruleSearch?.bookList?.isEmpty ?? true, "\(s.bookSourceName) 缺少 ruleSearch.bookList")
            XCTAssertFalse(s.ruleToc?.chapterList?.isEmpty ?? true, "\(s.bookSourceName) 缺少 ruleToc.chapterList")
            XCTAssertFalse(s.ruleToc?.chapterName?.isEmpty ?? true, "\(s.bookSourceName) 缺少 ruleToc.chapterName")
        }
    }

    // MARK: - 特殊 URL 形态专门断言

    func testMuliUsesBareIPWithPort() throws {
        let s = try source(named: "🍅木里番茄0922[GO聚合版]")
        // 裸 IP + 端口，无域名、无 TLS。
        XCTAssertEqual(s.bookSourceUrl, "http://154.58.233.54:1968")
        let url = try XCTUnwrap(URL(string: s.bookSourceUrl))
        XCTAssertEqual(url.scheme, "http")
        XCTAssertEqual(url.host, "154.58.233.54")
        XCTAssertEqual(url.port, 1968)
        // host 里只有数字与点（确为裸 IP）。
        let host = try XCTUnwrap(url.host)
        XCTAssertTrue(host.allSatisfy { $0.isNumber || $0 == "." }, "木里番茄 host 应为裸 IP，实际 \(host)")
    }

    func testQimoBaseUrlCarriesMdSuffix() throws {
        let s = try source(named: "七猫小说（qimo）")
        XCTAssertEqual(s.bookSourceUrl, "https://api-bc.wtzw.com#md")
        XCTAssertTrue(s.bookSourceUrl.hasSuffix("#md"), "七猫 baseUrl 必须带 #md 后缀")
        // 去掉后缀后是合法 https 主机。
        let bare = String(s.bookSourceUrl.dropLast(3))
        let url = try XCTUnwrap(URL(string: bare))
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "api-bc.wtzw.com")
    }

    func testAliceUsesPunycodeHost() throws {
        let s = try source(named: "🌸爱丽丝书屋(免翻)")
        XCTAssertTrue(s.bookSourceUrl.contains("xn--"), "爱丽丝书屋应使用 Punycode 域名，实际 \(s.bookSourceUrl)")
        let url = try XCTUnwrap(URL(string: s.bookSourceUrl))
        let host = try XCTUnwrap(url.host)
        XCTAssertTrue(host.hasPrefix("xn--"), "Punycode 主机应以 xn-- 开头，实际 \(host)")
        // Punycode 主机去掉前缀后应是非空 ASCII 标签（证明不是空字符串占位）。
        XCTAssertEqual(host.replacingOccurrences(of: "xn--", with: "").isEmpty, false)
    }

    // MARK: - 规则引擎真实规则 + 合成数据的精确值断言（不依赖 JS）
    //
    // 下面每个用例：规则真实、数据合成。响应体字段/结构严格按对应规则形状构造。

    // ── 1. 速读谷（@css 规则；`.itemtxt p:eq(1) a` 等）──

    private static let shuduguSearchBody = """
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

    func testShuduguSearchPreciseValues() async throws {
        // 规则真实（速读谷 ruleSearch 原文，@css）；数据合成。
        let src = try source(named: "速读谷")
        let searchURL = "https://www.shudugu.org/i/sor.aspx?key=斗罗"
        let net = MockWebBookNetwork([searchURL: WebBookResponse(url: searchURL, status: 200, body: Self.shuduguSearchBody)])
        let books = try await WebBook.searchBookAwait(bookSource: src, key: "斗罗", options: WebBookOptions(network: net))

        XCTAssertEqual(books.count, 1)
        let b = try XCTUnwrap(books.first)
        XCTAssertEqual(b.name, "合成速读之书")
        XCTAssertEqual(b.bookUrl, "https://www.shudugu.org/book/1001.html")
        XCTAssertEqual(b.kind, "玄幻")
        XCTAssertEqual(b.latestChapterTitle, "第一章 起始")
    }

    func testShuduguInfoTocContentPreciseValues() async throws {
        // 规则真实；数据合成。四阶段串同一 Mock 网络。
        let src = try source(named: "速读谷")
        let searchURL = "https://www.shudugu.org/i/sor.aspx?key=斗罗"
        let bookURL = "https://www.shudugu.org/book/1001.html"
        let tocURL = "https://www.shudugu.org/toc/1001.html"
        let contentURL = "https://www.shudugu.org/c/1.html"

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
        // 用 set(_:_:) 逐个写入而不是字典字面量：部分书源的详情页与目录页是
        // **同一个 URL**（如得奇的 bookURL == tocURL），字典字面量遇到重复 key 会触发
        // `Fatal error: Dictionary literal contains duplicate keys` 并直接终止整个测试
        // 进程（实测于 CI run 37449176865）。
        let net = MockWebBookNetwork()
        net.set(searchURL, WebBookResponse(url: searchURL, status: 200, body: Self.shuduguSearchBody))
        net.set(bookURL, WebBookResponse(url: bookURL, status: 200, body: infoBody))
        net.set(tocURL, WebBookResponse(url: tocURL, status: 200, body: tocBody))
        net.set(contentURL, WebBookResponse(url: contentURL, status: 200, body: contentBody))
        let opts = WebBookOptions(network: net)

        let books = try await WebBook.searchBookAwait(bookSource: src, key: "斗罗", options: opts)
        var book = try XCTUnwrap(books.first).toBook()
        book.bookUrl = bookURL

        // 详情
        book = try await WebBook.getBookInfoAwait(bookSource: src, book: &book, options: opts)
        XCTAssertEqual(book.name, "合成速读之书")
        XCTAssertEqual(book.kind, "玄幻")
        XCTAssertEqual(book.wordCount, "123万字")
        XCTAssertEqual(book.intro, "合成速读简介。")
        XCTAssertEqual(book.latestChapterTitle, "第一章 起始")

        // 目录（详情规则无 tocUrl，回退 baseUrl；此处显式指向合成目录页）
        book.tocUrl = tocURL
        let chapters = try await WebBook.getChapterListAwait(bookSource: src, book: &book, options: opts)
        XCTAssertEqual(chapters.count, 3)
        XCTAssertEqual(chapters.map(\.title), ["第一章 起始", "第二章 发展", "第三章 结束"])
        XCTAssertEqual(chapters[0].url, "/c/1.html")

        // 正文
        let content = try await WebBook.getContentAwait(bookSource: src, book: book, bookChapter: chapters[0], options: opts)
        XCTAssertTrue(content.contains("速读谷合成正文第一段。"))
        XCTAssertTrue(content.contains("速读谷合成正文第二段。"))
        XCTAssertEqual(String(content.prefix(10)), "速读谷合成正文第一段")
    }

    // ── 2. 📂得奇小说网（SwiftSoup 链 class.item / tag.h1）──

    private static let deqixsSearchBody = """
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

    func testDeqixsSearchPreciseValues() async throws {
        // 规则真实（得奇小说网 ruleSearch 原文）；数据合成。
        let src = try source(named: "📂得奇小说网")
        let searchURL = "https://www.deqixs.org/modules/article/search.php"
        let net = MockWebBookNetwork([searchURL: WebBookResponse(url: searchURL, status: 200, body: Self.deqixsSearchBody)])
        let books = try await WebBook.searchBookAwait(bookSource: src, key: "斗罗", options: WebBookOptions(network: net))

        XCTAssertEqual(books.count, 1)
        let b = try XCTUnwrap(books.first)
        XCTAssertEqual(b.name, "合成得奇之书")
        XCTAssertEqual(b.author, "合成作者乙")
        XCTAssertEqual(b.bookUrl, "https://www.deqixs.org/book/2001/")
        XCTAssertEqual(b.wordCount, "88万字")
        XCTAssertEqual(b.latestChapterTitle, "第一章 得奇起始")
    }

    func testDeqixsInfoTocContentPreciseValues() async throws {
        let src = try source(named: "📂得奇小说网")
        let searchURL = "https://www.deqixs.org/modules/article/search.php"
        let bookURL = "https://www.deqixs.org/book/2001/"
        let tocURL = "https://www.deqixs.org/book/2001/"
        let contentURL = "https://www.deqixs.org/c/1.html"

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
        // ⚠️ 得奇小说网的详情页与目录页是**同一个 URL**（bookURL == tocURL）。
        // 不能用字典字面量（重复 key 会触发 Swift `Fatal error: Dictionary literal contains
        // duplicate keys` 并直接终止进程），改用 set(_:_:) 逐个写入（后者覆盖前者即可）。
        let net = MockWebBookNetwork()
        net.set(searchURL, WebBookResponse(url: searchURL, status: 200, body: Self.deqixsSearchBody))
        net.set(bookURL, WebBookResponse(url: bookURL, status: 200, body: infoBody))
        net.set(tocURL, WebBookResponse(url: tocURL, status: 200, body: tocBody))
        net.set(contentURL, WebBookResponse(url: contentURL, status: 200, body: contentBody))
        let opts = WebBookOptions(network: net)

        let books = try await WebBook.searchBookAwait(bookSource: src, key: "斗罗", options: opts)
        var book = try XCTUnwrap(books.first).toBook()
        book.bookUrl = bookURL

        book = try await WebBook.getBookInfoAwait(bookSource: src, book: &book, options: opts)
        XCTAssertEqual(book.name, "合成得奇之书")
        XCTAssertEqual(book.author, "合成作者乙")
        XCTAssertEqual(book.wordCount, "88万字")

        book.tocUrl = tocURL
        let chapters = try await WebBook.getChapterListAwait(bookSource: src, book: &book, options: opts)
        XCTAssertEqual(chapters.count, 2)
        XCTAssertEqual(chapters.map(\.title), ["第一章 得奇起始", "第二章 得奇发展"])

        let content = try await WebBook.getContentAwait(bookSource: src, book: book, bookChapter: chapters[0], options: opts)
        // 正文规则为 class.con@html（保留 HTML），HtmlFormatter 会把段落缩进为全角空格。
        XCTAssertTrue(content.contains("得奇合成正文第一段。"))
        XCTAssertTrue(content.contains("得奇合成正文第二段。"))
    }

    // ── 3. 🌸爱丽丝书屋(免翻)（原生 XPath；正文规则含 org.jsoup）──

    private static let aliceSearchBody = """
    <div class="list-group">
      <div class="list-group-item">
        <h5><a href="/book/3001.html">合成爱丽丝之书<small>连载</small></a></h5>
        <p class="text-muted"><a href="/tag/1">奇幻</a></p>
        <p class="mb-1 text-muted">作者: <a href="/author/3">合成作者丙</a> 1.2万 阅读</p>
        <p class="content-txt">合成爱丽丝简介。</p>
      </div>
    </div>
    """

    func testAliceSearchPreciseValues() async throws {
        // 规则真实（爱丽丝书屋 ruleSearch 原文，XPath）；数据合成。
        // name 规则 `//h5/a//text()##\d+.|\n##` 会把 <small>连载</small> 拼进来 → "合成爱丽丝之书连载"。
        let src = try source(named: "🌸爱丽丝书屋(免翻)")
        let searchURL = "https://xn--vcsx64d.alicesw12.xyz/search.html?q=斗罗&f=_al"
        let net = MockWebBookNetwork([searchURL: WebBookResponse(url: searchURL, status: 200, body: Self.aliceSearchBody)])
        let books = try await WebBook.searchBookAwait(bookSource: src, key: "斗罗", options: WebBookOptions(network: net))

        XCTAssertEqual(books.count, 1)
        let b = try XCTUnwrap(books.first)
        XCTAssertEqual(b.name, "合成爱丽丝之书连载")
        XCTAssertEqual(b.author, "合成作者丙")
        XCTAssertEqual(b.bookUrl, "https://xn--vcsx64d.alicesw12.xyz/book/3001.html")
    }

    func testAliceInfoAndTocPreciseValues() async throws {
        // 正文规则含 org.jsoup（Rhino 专属）→ 见 testAlice…ContentRequiresJSoup 说明；
        // 本题只覆盖 搜索→详情→目录。
        let src = try source(named: "🌸爱丽丝书屋(免翻)")
        let searchURL = "https://xn--vcsx64d.alicesw12.xyz/search.html?q=斗罗&f=_al"
        let bookURL = "https://xn--vcsx64d.alicesw12.xyz/book/3001.html"
        let tocURL = "https://xn--vcsx64d.alicesw12.xyz/toc/3001.html"

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
        // 用 set(_:_:) 逐个写入而不是字典字面量：部分书源的详情页与目录页是
        // **同一个 URL**（如得奇的 bookURL == tocURL），字典字面量遇到重复 key 会触发
        // `Fatal error: Dictionary literal contains duplicate keys` 并直接终止整个测试
        // 进程（实测于 CI run 37449176865）。
        let net = MockWebBookNetwork()
        net.set(searchURL, WebBookResponse(url: searchURL, status: 200, body: Self.aliceSearchBody))
        net.set(bookURL, WebBookResponse(url: bookURL, status: 200, body: infoBody))
        net.set(tocURL, WebBookResponse(url: tocURL, status: 200, body: tocBody))
        let opts = WebBookOptions(network: net)

        let books = try await WebBook.searchBookAwait(bookSource: src, key: "斗罗", options: opts)
        var book = try XCTUnwrap(books.first).toBook()
        book.bookUrl = bookURL

        book = try await WebBook.getBookInfoAwait(bookSource: src, book: &book, options: opts)
        XCTAssertEqual(book.author, "合成作者丙")
        XCTAssertEqual(book.name, "合成爱丽丝之书连载")
        // intro 规则是 @js（拼接 info + intro）→ Linux 上无法求值；此处只断言正文页字段可解析。
        XCTAssertEqual(book.latestChapterTitle, "第一章 爱丽丝起始")

        // tocUrl 规则 `//div[@class='book_newchap']//a[contains(text(),'查看所有章节')]/@href`
        // 解析为绝对地址（Punycode 主机）。
        book.tocUrl = tocURL
        let chapters = try await WebBook.getChapterListAwait(bookSource: src, book: &book, options: opts)
        XCTAssertEqual(chapters.count, 2)
        XCTAssertEqual(chapters.map(\.title), ["第一章 爱丽丝起始", "第二章 爱丽丝发展"])
        XCTAssertEqual(chapters[0].url, "/c/1.html")
    }

    // ── 4. ⚡📂淘小说书城（纯 JSONPath 搜索；详情 URL 靠 @js）──

    private static let taoyueSearchBody = """
    {"code":0,"data":{"bookList":[
      {"authorName":"合成作者丁","title":"合成淘小说之书","coverUrl":"/c/1.jpg",
       "intro":"合成淘小说简介。","categoryName":"科幻","allWords":"66万",
       "sourceName":"tf","sourceId":"4001"}]}}
    """

    func testTaoyueSearchPreciseValues() async throws {
        // 规则真实（淘小说书城 ruleSearch 原文，纯 JSONPath）；数据合成。
        // bookUrl 规则 `/ajax/or/ty/book?sourceName={{$.sourceName}}&sourceId={{$.sourceId}}`
        // 是**非 @js** 的模板替换 —— 在 macOS/iOS 上会解析为绝对地址。
        let src = try source(named: "⚡📂淘小说书城")
        let searchURL = "http://betam.taoyuewenhua.com/ajax/or/authopt/ty/search_books?keywords=斗罗&page=0&pageSize=20&ctype=1"
        let net = MockWebBookNetwork([searchURL: WebBookResponse(url: searchURL, status: 200, body: Self.taoyueSearchBody)])
        let books = try await WebBook.searchBookAwait(bookSource: src, key: "斗罗", options: WebBookOptions(network: net))

        XCTAssertEqual(books.count, 1)
        let b = try XCTUnwrap(books.first)
        XCTAssertEqual(b.name, "合成淘小说之书")
        XCTAssertEqual(b.author, "合成作者丁")
        XCTAssertEqual(b.kind, "科幻")
        XCTAssertEqual(b.wordCount, "66万")
    }
}

// MARK: - 依赖 JavaScriptCore 的完整四阶段（仅 Apple 平台）
//
// Linux 无 JavaScriptCore：淘小说详情 URL、得间全部、七猫全部、木里全部依赖 `@js:` 求值。
// 本扩展保证这些书源在 CI 的 test-macos / test-ios-simulator 上被**真实覆盖**，
// 且两个平台用例数完全相同（同一份源码、同一 `#if` 条件）。

#if canImport(JavaScriptCore)
extension WebBookRealSourcesEndToEndTests {

    // ── 淘小说：详情 → 目录 → 正文 ──

    /// 淘小说 `ruleBookInfo.tocUrl` 与 `ruleToc.chapterUrl` 都是 `@js:`（用
    /// `String(book.bookUrl).match(/sourceId=([^&]+)/)` 取 sourceId 拼目标地址），
    /// 故本用例只在 Apple 平台（有 JavaScriptCore）运行。
    ///
    /// 本用例把流程层日志接到一个 stdout sink，CI 会**逐行打印**目录解析的真实过程
    /// （`┌获取目录列表` / `└列表大小:N` / `◇目录总数:N`），便于失败时定位到具体阶段。
    func testTaoyueInfoTocContentPreciseValues() async throws {
        let src = try source(named: "⚡📂淘小说书城")
        let searchURL = "http://betam.taoyuewenhua.com/ajax/or/authopt/ty/search_books?keywords=斗罗&page=0&pageSize=20&ctype=1"
        let bookURL = "http://betam.taoyuewenhua.com/ajax/or/ty/book?sourceName=tf&sourceId=4001"
        let tocURL = "http://betam.taoyuewenhua.com/ajax/or/authopt/ty/chapter_list?sourceName=tf&sourceId=4001&page=0&pageSize=100"
        let contentURL = "http://betam.taoyuewenhua.com/ajax/or/authopt/ty/chapter_content?sourceName=tf&sourceId=4001&chapterId=1"

        let infoBody = """
        {"code":0,"data":{"title":"合成淘小说之书","authorName":"合成作者丁","intro":"合成淘小说简介正文。",
          "categoryName":"科幻","latestChapter":"第一章 淘小说起始","allWords":"66万",
          "sourceId":"4001","coverUrl":"/c/1.jpg"}}
        """
        let tocBody = """
        {"code":0,"data":{"chapters":[
          {"chapterId":"1","chapterTitle":"第一章 淘小说起始"},
          {"chapterId":"2","chapterTitle":"第二章 淘小说发展"}]}}
        """
        let contentBody = """
        {"code":0,"data":{"content":"淘小说合成正文第一段。\\n淘小说合成正文第二段。"}}
        """
        // 用注册方法而不是字典字面量：部分书源的详情页与目录页是**同一个 URL**
        // （如得奇的 bookURL == tocURL），字典字面量遇到重复 key 会触发
        // `Fatal error: Dictionary literal contains duplicate keys` 并直接终止整个测试
        // 进程（实测于 CI run 37449176865）。
        let net = MockWebBookNetwork()
        net.set(searchURL, WebBookResponse(url: searchURL, status: 200, body: Self.taoyueSearchBody))
        net.set(bookURL, WebBookResponse(url: bookURL, status: 200, body: infoBody))
        net.set(tocURL, WebBookResponse(url: tocURL, status: 200, body: tocBody))
        net.set(contentURL, WebBookResponse(url: contentURL, status: 200, body: contentBody))

        // 把 Debug 日志接到 stdout（仅本用例）：CI 日志里能看到目录解析的真实每一步。
        let logger = DebugLogger()
        let sink = StdoutDebugSink(tag: "taoyue")
        logger.callback = sink
        logger.beginDebug(sourceUrl: src.bookSourceUrl)
        logger.recordResponseBody = true
        let opts = WebBookOptions(logger: logger, network: net)

        let books = try await WebBook.searchBookAwait(bookSource: src, key: "斗罗", options: opts)
        var book = try XCTUnwrap(books.first).toBook()
        book.bookUrl = bookURL

        book = try await WebBook.getBookInfoAwait(bookSource: src, book: &book, options: opts)
        XCTAssertEqual(book.name, "合成淘小说之书")
        XCTAssertEqual(book.author, "合成作者丁")
        XCTAssertEqual(book.intro, "合成淘小说简介正文。")
        XCTAssertEqual(book.latestChapterTitle, "第一章 淘小说起始")

        // 详情阶段必须把 tocUrl 解析成绝对地址（规则真实：@js 用 sourceId 拼 chapter_list）。
        XCTAssertEqual(book.tocUrl, tocURL, "淘小说详情页 @js tocUrl 应拼出目录地址")

        let chapters = try await WebBook.getChapterListAwait(bookSource: src, book: &book, options: opts)
        XCTAssertEqual(chapters.count, 2, "目录应解析出 2 章；实际请求 URL = \(net.requestedURLs)")
        XCTAssertEqual(chapters.map(\.title), ["第一章 淘小说起始", "第二章 淘小说发展"])

        let content = try await WebBook.getContentAwait(bookSource: src, book: book, bookChapter: chapters[0], options: opts)
        XCTAssertTrue(content.contains("淘小说合成正文第一段。"))
        XCTAssertTrue(content.contains("淘小说合成正文第二段。"))
    }

    // ── 七猫：搜索 → 详情 → 目录（正文为 AES 解密，不在此覆盖）──

    /// 七猫 `searchUrl` 是**纯 `@js:`**（原文见 qimo_real_source.json）：
    /// 它在运行时用 `java.md5Encode(...)` 算出 `sign`，再拼成
    /// `"/api/v5/search/words?" + body`。因此测试**无法**在注册阶段预知完整 URL
    /// —— 这正是 `MockWebBookNetwork.setPrefix` 存在的理由（按稳定的「主机+路径」
    /// 前缀注册，再用 `requestedURLs` 对运行时 query 做**精确**断言，而不是猜 URL）。
    func testQimoSearchInfoTocPreciseValues() async throws {
        let src = try source(named: "七猫小说（qimo）")
        // 稳定的前缀（主机 + 路径）；七猫 searchUrl 的 JS 结果必然以它开头。
        let searchPrefix = "https://api-bc.wtzw.com/api/v5/search/words"
        let bookURL = "https://api-bc.wtzw.com/api/v4/book/detail?id=7001"

        let searchBody = """
        {"data":{"books":[{"id":7001,"original_title":"七猫之书","original_author":"合成作者庚",
          "image_link":"/c/1.jpg","intro":"合成七猫简介。","ptags":"言情",
          "words_num":"55万","latest_chapter_title":"第一章 七猫起始"}]}}
        """
        let infoBody = """
        {"data":{"book":{"id":7001,"title":"七猫之书","author":"合成作者庚","image_link":"/c/1.jpg",
          "intro":"合成七猫简介正文。","book_tag_list":[{"title":"言情"}],"words_num":"55万",
          "latest_chapter_title":"第一章 七猫起始","update_time":"1700000000"}}}
        """
        // 用注册方法而不是字典字面量：部分书源的详情页与目录页是**同一个 URL**
        // （如得奇的 bookURL == tocURL），字典字面量遇到重复 key 会触发
        // `Fatal error: Dictionary literal contains duplicate keys` 并直接终止整个测试
        // 进程（实测于 CI run 37449176865）。
        let net = MockWebBookNetwork()
        net.setPrefix(searchPrefix, WebBookResponse(url: searchPrefix, status: 200, body: searchBody))
        net.set(bookURL, WebBookResponse(url: bookURL, status: 200, body: infoBody))
        let opts = WebBookOptions(network: net)

        let books = try await WebBook.searchBookAwait(bookSource: src, key: "斗罗", options: opts)
        XCTAssertEqual(books.count, 1)
        let b = try XCTUnwrap(books.first)
        XCTAssertEqual(b.name, "七猫之书")
        XCTAssertEqual(b.author, "合成作者庚")
        XCTAssertEqual(b.kind, "言情")
        XCTAssertEqual(b.wordCount, "55万")

        // ── 对**真实发生过的请求 URL** 做精确断言（不猜 URL）──
        // 七猫 JS 固定注入 gender=3 / imei_ip=2937357107 / page=1 / wd=<key>，
        // 并附一个 32 位十六进制 MD5 sign。逐项断言这些**稳定**部分，
        // sign 的值本身由 MD5 决定、不硬编码（那才是不撒谎）。
        let searchRequests = net.requestedURLs.filter { $0.hasPrefix(searchPrefix) }
        XCTAssertEqual(searchRequests.count, 1, "七猫搜索阶段应恰好发起 1 次请求")
        let actual = try XCTUnwrap(searchRequests.first)
        for needle in ["gender=3", "imei_ip=2937357107", "page=1", "wd=%E6%96%97%E7%BD%97"] {
            XCTAssertTrue(actual.contains(needle), "七猫搜索 URL 缺少 \(needle)（实际：\(actual)）")
        }
        let sign = Self.queryValue(actual, name: "sign")
        XCTAssertNotNil(sign, "七猫搜索 URL 应带 sign（实际：\(actual)）")
        XCTAssertEqual(sign?.count, 32, "七猫 sign 应为 32 位 MD5 十六进制（实际：\(sign ?? "nil")）")
        XCTAssertTrue(sign?.allSatisfy { $0.isHexDigit } ?? false, "七猫 sign 必须全为十六进制字符")

        var book = b.toBook()
        book.bookUrl = bookURL
        book = try await WebBook.getBookInfoAwait(bookSource: src, book: &book, options: opts)
        XCTAssertEqual(book.name, "七猫之书")
        XCTAssertEqual(book.author, "合成作者庚")
    }

    /// 从 URL 的 query 中取出指定参数值（无则 nil）。仅用于测试断言。
    private static func queryValue(_ url: String, name: String) -> String? {
        guard let q = url.split(separator: "?", maxSplits: 1).dropFirst().first else { return nil }
        for pair in q.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1)
            if kv.first.map(String.init) == name { return kv.count > 1 ? String(kv[1]) : "" }
        }
        return nil
    }
}
#endif
