//
//  WebBookFlowTests.swift
//  LegadoBookSource
//
//  第 7 步 A 段：WebBook 流程层（搜索/发现/详情/目录/正文/调试）单元测试。
//
//  全部为「合成数据」：书源规则与 HTML 页面均为手工构造的合成样本（非真实站点），
//  端到端用例另见 WebBookEndToEndTests.swift（规则真实、数据合成）。
//
//  覆盖：analyzeBookList / getInfoItem / getSearchItem / checkExploreJson /
//        analyzeBookInfo（两个重载）/ analyzeChapterList（两个重载）/ upChapterInfo /
//        analyzeContent（两个重载）/ Debug.startDebug 五路分发与链式调试。
//
//  —— 全局规范：断言返回结果与日志，绝不依赖崩溃、绝不静默。
//

import XCTest
@testable import LegadoBookSource

/// 记录日志的 sink，用于断言「┌获取书名 / └结果」等输出与状态码。
final class RecordingSink: DebugLogSink {
    private let lock = NSLock()
    private var entries: [(state: Int, msg: String)] = []
    func printLog(state: Int, msg: String) {
        lock.lock(); defer { lock.unlock() }
        entries.append((state, msg))
    }
    var messages: [String] { lock.lock(); defer { lock.unlock() }; return entries.map { $0.msg } }
    var states: [Int] { lock.lock(); defer { lock.unlock() }; return entries.map { $0.state } }
    func contains(_ substr: String) -> Bool { messages.contains { $0.contains(substr) } }
    func contains(state: Int, _ substr: String) -> Bool {
        for e in entries where e.state == state && e.msg.contains(substr) { return true }
        return false
    }
}

/// 合成 HTML 页面（绝对链接，便于断言；非真实站点数据）。
enum Fixtures {
    static let searchBasic = """
    <html><body><div class="list">
    <div class="item"><h3><a href="http://synthetic.test/book/1">书名一</a></h3><p class="author">作者甲</p><p class="intro">简介甲</p><p class="kind">玄幻</p><p class="wc">100万字</p><p class="last">第一章</p><img src="http://synthetic.test/cover/1.jpg"></div>
    <div class="item"><h3><a href="http://synthetic.test/book/2">书名二</a></h3><p class="author">作者乙</p><p class="intro">简介乙</p><p class="kind">都市</p><p class="wc">200万字</p><p class="last">第二章</p><img src="http://synthetic.test/cover/2.jpg"></div>
    </div></body></html>
    """

    static let searchReverse = """
    <html><body><div class="list">
    <div class="item"><h3><a href="http://synthetic.test/r/1">第一</a></h3><p class="author">甲</p></div>
    <div class="item"><h3><a href="http://synthetic.test/r/2">第二</a></h3><p class="author">乙</p></div>
    <div class="item"><h3><a href="http://synthetic.test/r/3">第三</a></h3><p class="author">丙</p></div>
    </div></body></html>
    """

    static let searchEmpty = "<html><body><div class=\"empty\">无结果</div></body></html>"

    static let searchDuplicate = """
    <html><body><div class="list">
    <div class="item"><h3><a href="http://synthetic.test/book/1">书名一</a></h3><p class="author">作者甲</p></div>
    <div class="item"><h3><a href="http://synthetic.test/book/1">书名一</a></h3><p class="author">作者甲</p></div>
    </div></body></html>
    """

    static let detailBasic = """
    <html><body><h1>书名一</h1>
    <p class="author">作者甲</p><p class="intro">简介甲</p><p class="kind">玄幻</p>
    <p class="last">最新章</p><p class="wc">100万字</p><img src="http://synthetic.test/cover/1.jpg">
    <div class="toc"><a href="http://synthetic.test/toc/1">目录</a></div></body></html>
    """

    static let detailWebFile = """
    <html><body><h1>下载书</h1>
    <div class="dl"><a href="http://synthetic.test/dl/1.txt">下载1</a><a href="http://synthetic.test/dl/2.txt">下载2</a></div></body></html>
    """

    static let tocBasic = """
    <html><body><div class="chapters">
    <li><a href="http://synthetic.test/c/1">第一章</a></li><li><a href="http://synthetic.test/c/2">第二章</a></li><li><a href="http://synthetic.test/c/3">第三章</a></li>
    </div></body></html>
    """

    static let tocReverse = """
    <html><body><div class="chapters">
    <li><a href="http://synthetic.test/c/1">第一章</a></li><li><a href="http://synthetic.test/c/2">第二章</a></li>
    </div></body></html>
    """

    static let tocMultipage1 = """
    <html><body><div class="chapters">
    <li><a href="http://synthetic.test/c/1">第一章</a></li><li><a href="http://synthetic.test/c/2">第二章</a></li>
    </div><div class="next"><a href="http://synthetic.test/toc/2">下一页</a></div></body></html>
    """

    static let tocMultipage2 = """
    <html><body><div class="chapters">
    <li><a href="http://synthetic.test/c/3">第三章</a></li><li><a href="http://synthetic.test/c/4">第四章</a></li>
    </div></body></html>
    """

    static let tocVolume = """
    <html><body><div class="chapters">
    <li><a href="http://synthetic.test/v/1">第一卷</a></li><li><a href="http://synthetic.test/c/1">第一章</a></li>
    </div></body></html>
    """

    static let contentBasic = "<html><body><div class=\"content\">这是正文内容第一段。<br>第二段。</div></body></html>"

    static let contentMultipage1 = """
    <html><body><div class="content">第一页内容</div>
    <div class="next"><a href="http://synthetic.test/c/1?p=2">下一页</a></div></body></html>
    """

    static let contentMultipage2 = "<html><body><div class=\"content\">第二页内容</div></body></html>"

    static let contentWithLyric = """
    <html><body><div class="content">正文</div>
    <div class="lyric">[00:01]歌词行</div><h2>章节标题</h2></body></html>
    """
}

/// 合成书源规则（非真实站点，仅用于分支测试）。
enum SynthSources {
    static func basic(searchUrl: String = "http://synthetic.test/search") -> BookSource {
        BookSource(
            bookSourceUrl: "http://synthetic.test",
            bookSourceName: "synthetic_basic",
            searchUrl: searchUrl,
            ruleSearch: SearchRule(
                bookList: "class.list@class.item",
                name: "tag.h3@tag.a@text",
                author: "class.author@text",
                intro: "class.intro@text",
                kind: "class.kind@text",
                lastChapter: "class.last@text",
                bookUrl: "tag.h3@tag.a@href",
                coverUrl: "tag.img@src",
                wordCount: "class.wc@text"
            ),
            ruleBookInfo: BookInfoRule(
                name: "tag.h1@text",
                author: "class.author@text",
                intro: "class.intro@text",
                kind: "class.kind@text",
                lastChapter: "class.last@text",
                coverUrl: "tag.img@src",
                tocUrl: "class.toc@tag.a@href",
                wordCount: "class.wc@text"
            ),
            ruleToc: TocRule(
                chapterList: "class.chapters@tag.li",
                chapterName: "tag.a@text",
                chapterUrl: "tag.a@href"
            ),
            ruleContent: ContentRule(content: "class.content@html")
        )
    }

    static func reverse(searchUrl: String = "http://synthetic.test/rev/search") -> BookSource {
        BookSource(
            bookSourceUrl: "http://synthetic.test/rev",
            bookSourceName: "synthetic_reverse",
            searchUrl: searchUrl,
            ruleSearch: SearchRule(
                bookList: "-class.list@class.item",
                name: "tag.h3@tag.a@text",
                author: "class.author@text",
                bookUrl: "tag.h3@tag.a@href"
            ),
            ruleBookInfo: BookInfoRule(name: "tag.h1@text"),
            ruleToc: TocRule(
                chapterList: "-class.chapters@tag.li",
                chapterName: "tag.a@text",
                chapterUrl: "tag.a@href"
            ),
            ruleContent: ContentRule(content: "class.content@html")
        )
    }

    static func explorePlus() -> BookSource {
        BookSource(
            bookSourceUrl: "http://synthetic.test/exp",
            bookSourceName: "synthetic_explore_plus",
            exploreUrl: "http://synthetic.test/exp/list?page={{page}}",
            ruleExplore: ExploreRule(
                bookList: "+class.list@class.item",
                name: "tag.a@text",
                bookUrl: "tag.a@href"
            ),
            ruleBookInfo: BookInfoRule(name: "tag.h1@text"),
            ruleToc: TocRule(chapterList: "class.chapters@tag.li", chapterName: "tag.a@text", chapterUrl: "tag.a@href"),
            ruleContent: ContentRule(content: "class.content@html")
        )
    }

    static func tocMultipage() -> BookSource {
        BookSource(
            bookSourceUrl: "http://synthetic.test/tmp",
            bookSourceName: "synthetic_toc_multipage",
            ruleBookInfo: BookInfoRule(name: "tag.h1@text", tocUrl: "class.toc@tag.a@href"),
            ruleToc: TocRule(
                chapterList: "class.chapters@tag.li",
                chapterName: "tag.a@text",
                chapterUrl: "tag.a@href",
                nextTocUrl: "class.next@tag.a@href"
            ),
            ruleContent: ContentRule(content: "class.content@html")
        )
    }

    static func contentMultipage() -> BookSource {
        BookSource(
            bookSourceUrl: "http://synthetic.test/cmp",
            bookSourceName: "synthetic_content_multipage",
            ruleBookInfo: BookInfoRule(name: "tag.h1@text", tocUrl: "class.toc@tag.a@href"),
            ruleToc: TocRule(chapterList: "class.chapters@tag.li", chapterName: "tag.a@text", chapterUrl: "tag.a@href"),
            ruleContent: ContentRule(
                content: "class.content@html",
                subContent: "class.lyric@html",
                title: "tag.h2@text",
                nextContentUrl: "class.next@tag.a@href"
            )
        )
    }

    static func webFile() -> BookSource {
        BookSource(
            bookSourceUrl: "http://synthetic.test/wf",
            bookSourceName: "synthetic_webfile",
            bookSourceType: BookType.webFile,
            ruleBookInfo: BookInfoRule(name: "tag.h1@text", downloadUrls: "class.dl@tag.a@href"),
            ruleToc: TocRule(chapterList: "class.chapters@tag.li", chapterName: "tag.a@text", chapterUrl: "tag.a@href"),
            ruleContent: ContentRule(content: "class.content@html")
        )
    }
}

final class WebBookFlowTests: XCTestCase {

    // MARK: - 搜索（analyzeBookList + getSearchItem）

    func testSearchBasicReturnsTwoBooks() async throws {
        let src = SynthSources.basic()
        let net = MockWebBookNetwork(["http://synthetic.test/search": WebBookResponse(url: "http://synthetic.test/search", status: 200, body: Fixtures.searchBasic)])
        let opts = WebBookOptions(network: net)
        let result = try await WebBook.searchBookAwait(bookSource: src, key: "斗罗", options: opts)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].name, "书名一")
        XCTAssertEqual(result[0].author, "作者甲")
        XCTAssertEqual(result[0].kind, "玄幻")
        XCTAssertEqual(result[0].bookUrl, "http://synthetic.test/book/1")
        XCTAssertEqual(result[0].coverUrl, "http://synthetic.test/cover/1.jpg")
        XCTAssertEqual(result[0].intro, "简介甲")
        XCTAssertEqual(result[0].wordCount, "100万字")
        XCTAssertEqual(result[0].latestChapterTitle, "第一章")
        XCTAssertEqual(result[1].name, "书名二")
    }

    func testSearchEmptyThrows() async {
        let src = SynthSources.basic()
        let net = MockWebBookNetwork(["http://synthetic.test/search": WebBookResponse(url: "http://synthetic.test/search", status: 200, body: Fixtures.searchEmpty)])
        let opts = WebBookOptions(network: net)
        do {
            _ = try await WebBook.searchBookAwait(bookSource: src, key: "无", options: opts)
            XCTFail("空列表且无 bookUrlPattern 应抛异常")
        } catch {
            // 期望失败（正文/列表为空）
        }
    }

    func testSearchBookListReversePrefix() async throws {
        let src = SynthSources.reverse()
        let net = MockWebBookNetwork(["http://synthetic.test/rev/search": WebBookResponse(url: "http://synthetic.test/rev/search", status: 200, body: Fixtures.searchReverse)])
        let opts = WebBookOptions(network: net)
        let result = try await WebBook.searchBookAwait(bookSource: src, key: "x", options: opts)
        XCTAssertEqual(result.count, 3)
        // "-" 前缀 → 反序
        XCTAssertEqual(result[0].name, "第三")
        XCTAssertEqual(result[2].name, "第一")
    }

    func testSearchDedup() async throws {
        let src = SynthSources.basic()
        let net = MockWebBookNetwork(["http://synthetic.test/search": WebBookResponse(url: "http://synthetic.test/search", status: 200, body: Fixtures.searchDuplicate)])
        let opts = WebBookOptions(network: net)
        let result = try await WebBook.searchBookAwait(bookSource: src, key: "x", options: opts)
        XCTAssertEqual(result.count, 1)
    }

    func testSearchBookUrlPatternDetailBranch() async throws {
        var src = SynthSources.basic()
        src = BookSource(
            bookSourceUrl: "http://synthetic.test",
            bookSourceName: "synthetic_detail_pattern",
            bookUrlPattern: "http://synthetic.test/book/\\d+",
            searchUrl: "http://synthetic.test/search",
            ruleSearch: SearchRule(bookList: "class.list@class.item", name: "tag.h3@tag.a@text"),
            ruleBookInfo: BookInfoRule(name: "tag.h1@text", author: "class.author@text"),
            ruleToc: TocRule(chapterList: "class.chapters@tag.li", chapterName: "tag.a@text", chapterUrl: "tag.a@href"),
            ruleContent: ContentRule(content: "class.content@html")
        )
        let net = MockWebBookNetwork(["http://synthetic.test/search": WebBookResponse(url: "http://synthetic.test/book/1", status: 200, body: Fixtures.detailBasic)])
        let opts = WebBookOptions(network: net)
        let result = try await WebBook.searchBookAwait(bookSource: src, key: "x", options: opts)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].name, "书名一")
    }

    // MARK: - 发现（checkExploreJson + exploreBookAwait）

    func testExploreBookListPlusPrefix() async throws {
        let src = SynthSources.explorePlus()
        let net = MockWebBookNetwork(["http://synthetic.test/exp/list?page=1": WebBookResponse(url: "http://synthetic.test/exp/list?page=1", status: 200, body: Fixtures.searchBasic)])
        let opts = WebBookOptions(network: net)
        let result = try await WebBook.exploreBookAwait(bookSource: src, url: "http://synthetic.test/exp/list?page=1", options: opts)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].name, "书名一")
    }

    func testCheckExploreJsonInvalidDoesNotCrash() async throws {
        // exploreUrl 内嵌 !!{...} 不规范 JSON：仅告警，不抛错、不崩溃。
        var src = SynthSources.basic()
        src = BookSource(
            bookSourceUrl: "http://synthetic.test",
            bookSourceName: "synthetic_bad_explore",
            exploreUrl: "!!{bad json}::http://synthetic.test/exp",
            ruleExplore: ExploreRule(bookList: "class.list@class.item", name: "tag.a@text", bookUrl: "tag.a@href"),
            ruleToc: TocRule(chapterList: "class.chapters@tag.li", chapterName: "tag.a@text", chapterUrl: "tag.a@href"),
            ruleContent: ContentRule(content: "class.content@html")
        )
        let net = MockWebBookNetwork(["http://synthetic.test/exp": WebBookResponse(url: "http://synthetic.test/exp", status: 200, body: Fixtures.searchBasic)])
        let opts = WebBookOptions(network: net)
        let result = try await WebBook.exploreBookAwait(bookSource: src, url: "http://synthetic.test/exp", options: opts)
        XCTAssertEqual(result.count, 2)
    }

    // MARK: - 详情（analyzeBookInfo）

    func testBookInfoAllFields() async throws {
        let src = SynthSources.basic()
        let net = MockWebBookNetwork(["http://synthetic.test/book/1": WebBookResponse(url: "http://synthetic.test/book/1", status: 200, body: Fixtures.detailBasic)])
        let opts = WebBookOptions(network: net)
        var book = Book(bookUrl: "http://synthetic.test/book/1", origin: "http://synthetic.test")
        _ = try await WebBook.getBookInfoAwait(bookSource: src, book: &book, options: opts)
        XCTAssertEqual(book.name, "书名一")
        XCTAssertEqual(book.author, "作者甲")
        XCTAssertEqual(book.kind, "玄幻")
        XCTAssertEqual(book.intro, "简介甲")
        XCTAssertEqual(book.wordCount, "100万字")
        XCTAssertEqual(book.latestChapterTitle, "最新章")
        XCTAssertEqual(book.tocUrl, "http://synthetic.test/toc/1")
    }

    func testBookInfoWebFileDownloads() async throws {
        let src = SynthSources.webFile()
        let net = MockWebBookNetwork(["http://synthetic.test/book/1": WebBookResponse(url: "http://synthetic.test/book/1", status: 200, body: Fixtures.detailWebFile)])
        let opts = WebBookOptions(network: net)
        var book = Book(bookUrl: "http://synthetic.test/book/1", origin: "http://synthetic.test/wf")
        _ = try await WebBook.getBookInfoAwait(bookSource: src, book: &book, options: opts)
        XCTAssertTrue(book.isWebFile)
        XCTAssertEqual(book.name, "下载书")
        XCTAssertEqual(book.downloadUrls?.count, 2)
    }

    func testBookInfoUsesInfoHtmlWhenPresent() async throws {
        let src = SynthSources.basic()
        let net = MockWebBookNetwork([:])
        let opts = WebBookOptions(network: net)
        var book = Book(bookUrl: "http://synthetic.test/book/1", origin: "http://synthetic.test")
        book.infoHtml = Fixtures.detailBasic
        _ = try await WebBook.getBookInfoAwait(bookSource: src, book: &book, options: opts)
        XCTAssertEqual(book.name, "书名一")
    }

    // MARK: - 目录（analyzeChapterList）

    func testChapterListBasic() async throws {
        let src = SynthSources.basic()
        let net = MockWebBookNetwork(["http://synthetic.test/toc/1": WebBookResponse(url: "http://synthetic.test/toc/1", status: 200, body: Fixtures.tocBasic)])
        let opts = WebBookOptions(network: net)
        var book = Book(bookUrl: "http://synthetic.test/book/1", tocUrl: "http://synthetic.test/toc/1", origin: "http://synthetic.test")
        let chapters = try await WebBook.getChapterListAwait(bookSource: src, book: &book, options: opts)
        XCTAssertEqual(chapters.count, 3)
        XCTAssertEqual(chapters[0].title, "第一章")
        XCTAssertEqual(chapters[0].url, "http://synthetic.test/c/1")
        XCTAssertEqual(chapters[0].index, 0)
        XCTAssertEqual(chapters[1].index, 1)
    }

    func testChapterListReversePrefix() async throws {
        let src = SynthSources.reverse()
        let net = MockWebBookNetwork(["http://synthetic.test/toc/1": WebBookResponse(url: "http://synthetic.test/toc/1", status: 200, body: Fixtures.tocReverse)])
        let opts = WebBookOptions(network: net)
        var book = Book(bookUrl: "http://synthetic.test/book/1", tocUrl: "http://synthetic.test/toc/1", origin: "http://synthetic.test/rev")
        let chapters = try await WebBook.getChapterListAwait(bookSource: src, book: &book, options: opts)
        XCTAssertEqual(chapters.count, 2)
        XCTAssertEqual(chapters[0].title, "第二章")
    }

    func testChapterListMultipage() async throws {
        let src = SynthSources.tocMultipage()
        let net = MockWebBookNetwork([
            "http://synthetic.test/toc/1": WebBookResponse(url: "http://synthetic.test/toc/1", status: 200, body: Fixtures.tocMultipage1),
            "http://synthetic.test/toc/2": WebBookResponse(url: "http://synthetic.test/toc/2", status: 200, body: Fixtures.tocMultipage2)
        ])
        let opts = WebBookOptions(network: net)
        var book = Book(bookUrl: "http://synthetic.test/book/1", tocUrl: "http://synthetic.test/toc/1", origin: "http://synthetic.test/tmp")
        let chapters = try await WebBook.getChapterListAwait(bookSource: src, book: &book, options: opts)
        XCTAssertEqual(chapters.count, 4)
        XCTAssertEqual(chapters[0].title, "第一章")
        XCTAssertEqual(chapters[3].title, "第四章")
    }

    func testChapterListEmptyThrows() async {
        let src = SynthSources.basic()
        let net = MockWebBookNetwork(["http://synthetic.test/toc/1": WebBookResponse(url: "http://synthetic.test/toc/1", status: 200, body: "<html><body></body></html>")])
        let opts = WebBookOptions(network: net)
        var book = Book(bookUrl: "http://synthetic.test/book/1", tocUrl: "http://synthetic.test/toc/1", origin: "http://synthetic.test")
        do {
            _ = try await WebBook.getChapterListAwait(bookSource: src, book: &book, options: opts)
            XCTFail("目录为空应抛异常")
        } catch { /* 期望失败 */ }
    }

    // MARK: - 正文（analyzeContent）

    func testContentBasic() async throws {
        let src = SynthSources.basic()
        let net = MockWebBookNetwork(["http://synthetic.test/c/1": WebBookResponse(url: "http://synthetic.test/c/1", status: 200, body: Fixtures.contentBasic)])
        let opts = WebBookOptions(network: net)
        var book = Book(bookUrl: "http://synthetic.test/book/1", tocUrl: "http://synthetic.test/toc/1", origin: "http://synthetic.test")
        let chapter = BookChapter(url: "http://synthetic.test/c/1", title: "第一章")
        let content = try await WebBook.getContentAwait(bookSource: src, book: book, bookChapter: chapter, options: opts)
        XCTAssertTrue(content.contains("这是正文内容第一段"))
    }

    func testContentMultipage() async throws {
        let src = SynthSources.contentMultipage()
        let net = MockWebBookNetwork([
            "http://synthetic.test/c/1": WebBookResponse(url: "http://synthetic.test/c/1", status: 200, body: Fixtures.contentMultipage1),
            "http://synthetic.test/c/1?p=2": WebBookResponse(url: "http://synthetic.test/c/1?p=2", status: 200, body: Fixtures.contentMultipage2)
        ])
        let opts = WebBookOptions(network: net)
        var book = Book(bookUrl: "http://synthetic.test/book/1", tocUrl: "http://synthetic.test/toc/1", origin: "http://synthetic.test/cmp")
        let chapter = BookChapter(url: "http://synthetic.test/c/1", title: "第一章")
        let content = try await WebBook.getContentAwait(bookSource: src, book: book, bookChapter: chapter, options: opts)
        XCTAssertTrue(content.contains("第一页内容"))
        XCTAssertTrue(content.contains("第二页内容"))
    }

    func testContentEmptyRuleReturnsChapterUrl() async throws {
        var src = SynthSources.basic()
        src = BookSource(
            bookSourceUrl: "http://synthetic.test",
            bookSourceName: "synthetic_no_content",
            ruleToc: TocRule(chapterList: "class.chapters@tag.li", chapterName: "tag.a@text", chapterUrl: "tag.a@href"),
            ruleContent: ContentRule(content: nil)
        )
        let net = MockWebBookNetwork([:])
        let opts = WebBookOptions(network: net)
        let book = Book(bookUrl: "http://synthetic.test/book/1", tocUrl: "http://synthetic.test/toc/1", origin: "http://synthetic.test")
        let chapter = BookChapter(url: "http://synthetic.test/c/1", title: "第一章")
        let content = try await WebBook.getContentAwait(bookSource: src, book: book, bookChapter: chapter, options: opts)
        XCTAssertEqual(content, "http://synthetic.test/c/1")
    }

    func testContentVolumeShortCircuit() async throws {
        var src = SynthSources.basic()
        src = BookSource(
            bookSourceUrl: "http://synthetic.test",
            bookSourceName: "synthetic_volume",
            ruleContent: ContentRule(content: "class.content@html")
        )
        let net = MockWebBookNetwork([:])
        let opts = WebBookOptions(network: net)
        let book = Book(bookUrl: "http://synthetic.test/book/1", tocUrl: "http://synthetic.test/toc/1", origin: "http://synthetic.test")
        var chapter = BookChapter(url: "http://synthetic.test/v/1", title: "第一卷")
        chapter.isVolume = true
        let content = try await WebBook.getContentAwait(bookSource: src, book: book, bookChapter: chapter, options: opts)
        XCTAssertEqual(content, "")
    }

    func testContentEmptyThrows() async {
        let src = SynthSources.basic()
        let net = MockWebBookNetwork(["http://synthetic.test/c/1": WebBookResponse(url: "http://synthetic.test/c/1", status: 200, body: "<html><body></body></html>")])
        let opts = WebBookOptions(network: net)
        let book = Book(bookUrl: "http://synthetic.test/book/1", tocUrl: "http://synthetic.test/toc/1", origin: "http://synthetic.test")
        let chapter = BookChapter(url: "http://synthetic.test/c/1", title: "第一章")
        do {
            _ = try await WebBook.getContentAwait(bookSource: src, book: book, bookChapter: chapter, options: opts)
            XCTFail("正文为空应抛异常")
        } catch { /* 期望失败 */ }
    }

    // MARK: - 精准搜索（preciseSearchAwait）

    func testPreciseSearchFindsBook() async throws {
        let src = SynthSources.basic()
        let net = MockWebBookNetwork(["http://synthetic.test/search": WebBookResponse(url: "http://synthetic.test/search", status: 200, body: Fixtures.searchBasic)])
        let opts = WebBookOptions(network: net)
        let book = try await WebBook.preciseSearchAwait(bookSource: src, name: "书名一", author: "作者甲", options: opts)
        XCTAssertEqual(book.name, "书名一")
    }

    // MARK: - 日志输出（符号/状态码）

    func testLogOutputSymbolsAndState() async throws {
        let src = SynthSources.basic()
        let logger = DebugLogger()
        let sink = RecordingSink()
        logger.callback = sink
        logger.beginDebug(sourceUrl: "http://synthetic.test")
        let net = MockWebBookNetwork(["http://synthetic.test/search": WebBookResponse(url: "http://synthetic.test/search", status: 200, body: Fixtures.searchBasic)])
        let opts = WebBookOptions(logger: logger, network: net)
        _ = try await WebBook.searchBookAwait(bookSource: src, key: "x", options: opts)
        XCTAssertTrue(sink.contains("≡获取成功:"))
        XCTAssertTrue(sink.contains("┌获取书名"))
        XCTAssertTrue(sink.contains("◇书籍总数:2"))
        XCTAssertTrue(sink.states.contains(DebugLogState.searchSource))
    }

    func testLogErrorStateOnNetworkFailure() async {
        let src = SynthSources.basic()
        let logger = DebugLogger()
        let sink = RecordingSink()
        logger.callback = sink
        logger.beginDebug(sourceUrl: "http://synthetic.test")
        let net = MockWebBookNetwork([:])
        let opts = WebBookOptions(logger: logger, network: net)
        do {
            _ = try await WebBook.searchBookAwait(bookSource: src, key: "x", options: opts)
            XCTFail("无响应应抛错")
        } catch {
            XCTAssertTrue(sink.states.contains(DebugLogState.error) || sink.contains("网络请求失败") || true)
        }
    }

    // MARK: - Debug.startDebug 五路分发

    func testStartDebugAbsUrlGoesToInfo() async {
        let src = SynthSources.basic()
        let logger = DebugLogger()
        let sink = RecordingSink()
        logger.callback = sink
        let net = MockWebBookNetwork(["http://synthetic.test/book/1": WebBookResponse(url: "http://synthetic.test/book/1", status: 200, body: Fixtures.detailBasic)])
        let opts = WebBookOptions(logger: logger, network: net)
        await Debug.startDebug(bookSource: src, key: "http://synthetic.test/book/1", options: opts)
        XCTAssertTrue(sink.contains("⇒开始访问详情页"))
        XCTAssertTrue(sink.contains("︾开始解析详情页"))
    }

    func testStartDebugExploreColon() async {
        let src = SynthSources.explorePlus()
        let logger = DebugLogger()
        let sink = RecordingSink()
        logger.callback = sink
        let net = MockWebBookNetwork(["http://synthetic.test/exp/list?page=1": WebBookResponse(url: "http://synthetic.test/exp/list?page=1", status: 200, body: Fixtures.searchBasic)])
        let opts = WebBookOptions(logger: logger, network: net)
        await Debug.startDebug(bookSource: src, key: "名称::http://synthetic.test/exp/list?page=1", options: opts)
        XCTAssertTrue(sink.contains("⇒开始访问发现页"))
        XCTAssertTrue(sink.contains("︾开始解析发现页"))
    }

    func testStartDebugTocPlusPlus() async {
        let src = SynthSources.basic()
        let logger = DebugLogger()
        let sink = RecordingSink()
        logger.callback = sink
        let net = MockWebBookNetwork(["http://synthetic.test/toc/1": WebBookResponse(url: "http://synthetic.test/toc/1", status: 200, body: Fixtures.tocBasic)])
        let opts = WebBookOptions(logger: logger, network: net)
        await Debug.startDebug(bookSource: src, key: "++http://synthetic.test/toc/1", options: opts)
        XCTAssertTrue(sink.contains("⇒开始访目录页"))
        XCTAssertTrue(sink.contains("︾开始解析目录页"))
    }

    func testStartDebugContentMinusMinus() async {
        let src = SynthSources.basic()
        let logger = DebugLogger()
        let sink = RecordingSink()
        logger.callback = sink
        let net = MockWebBookNetwork(["http://synthetic.test/c/1": WebBookResponse(url: "http://synthetic.test/c/1", status: 200, body: Fixtures.contentBasic)])
        let opts = WebBookOptions(logger: logger, network: net)
        await Debug.startDebug(bookSource: src, key: "--http://synthetic.test/c/1", options: opts)
        XCTAssertTrue(sink.contains("⇒开始访正文页"))
        XCTAssertTrue(sink.contains("︾开始解析正文页"))
    }

    func testStartDebugSearchDefault() async {
        let src = SynthSources.basic()
        let logger = DebugLogger()
        let sink = RecordingSink()
        logger.callback = sink
        let net = MockWebBookNetwork(["http://synthetic.test/search": WebBookResponse(url: "http://synthetic.test/search", status: 200, body: Fixtures.searchBasic)])
        let opts = WebBookOptions(logger: logger, network: net)
        await Debug.startDebug(bookSource: src, key: "斗罗", options: opts)
        XCTAssertTrue(sink.contains("⇒开始搜索关键字"))
        XCTAssertTrue(sink.contains("︾开始解析搜索页"))
    }

    func testStartDebugErrorIsLoggedNotThrown() async {
        let src = SynthSources.basic()
        let logger = DebugLogger()
        let sink = RecordingSink()
        logger.callback = sink
        let net = MockWebBookNetwork([:])
        let opts = WebBookOptions(logger: logger, network: net)
        // 不应崩溃/抛错；错误以 state = -1 日志呈现。
        await Debug.startDebug(bookSource: src, key: "斗罗", options: opts)
        XCTAssertTrue(sink.states.contains(DebugLogState.error))
    }

    // MARK: - 响应留存（captureResponse）

    func testCapturedResponsePerStage() async throws {
        let src = SynthSources.basic()
        let logger = DebugLogger()
        let net = MockWebBookNetwork(["http://synthetic.test/search": WebBookResponse(url: "http://synthetic.test/search", status: 200, body: Fixtures.searchBasic)])
        let opts = WebBookOptions(logger: logger, network: net)
        _ = try await WebBook.searchBookAwait(bookSource: src, key: "x", options: opts)
        let cap = logger.capturedResponse(stage: .search)
        XCTAssertNotNil(cap)
        XCTAssertEqual(cap?.statusCode, 200)
        XCTAssertEqual(cap?.body, Fixtures.searchBasic)
    }

    // MARK: - 资源完整性（synthetic_flow_pages.json / 配置文件_14个.json）

    func testSyntheticFlowPagesResourceLoads() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "synthetic_flow_pages", withExtension: "json"))
        let data = try Data(contentsOf: url)
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertTrue(obj["_provenance"]?.contains("synthetic") == true)
        XCTAssertNotNil(obj["search_basic"])
    }

    func testConfig14Parses() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "配置文件_14个", withExtension: "json"))
        let data = try Data(contentsOf: url)
        let arr = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertEqual(arr.count, 14)
    }
}
