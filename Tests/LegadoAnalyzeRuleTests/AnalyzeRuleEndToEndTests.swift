//
//  AnalyzeRuleEndToEndTests.swift
//  LegadoAnalyzeRuleTests
//
//  端到端：用「配置文件_7个.json」里的【真实书源规则文本】跑 AnalyzeRule，
//  输入响应为【合成数据】（规则真实、数据合成）。来源书源名在每个用例注释标出。
//
//  含 <js>/Java 互操作的真实规则（魔丸小说、爱丽丝书屋）预期触发「未实现 / 不支持」错误，
//  测试断言该错误行为，不假装成功。
//

import XCTest
@testable import LegadoBookSource

final class AnalyzeRuleEndToEndTests: XCTestCase {

    // ===== 淘小说书城（JSON 规则，真实）=====
    // 规则真实：search.bookList=$.data.bookList[*]  name=$.title  info.author=$.data.authorName
    // 数据合成。
    func testTaoxiaoshuo_jsonRules() throws {
        let synthetic = """
        {"data":{"bookList":[{"title":"合成书1","authorName":"合成作者A"},
                             {"title":"合成书2","authorName":"合成作者B"}]}}
        """
        let a = AnalyzeRule()
        try a.setContent(synthetic)
        let names = try a.getStringList("$.data.bookList[*].title")
        XCTAssertEqual(names, ["合成书1", "合成书2"])
        let author = try a.getString("$.data.bookList[0].authorName")
        XCTAssertEqual(author, "合成作者A")
    }
    // content.content 带 ## 正则清洗（真实规则）
    func testTaoxiaoshuo_contentReplaceRegex() throws {
        let synthetic = """
        {"data":{"content":"正文内容。本章未完待续\\n\\n\\n"}}
        """
        let a = AnalyzeRule()
        try a.setContent(synthetic)
        let c = try a.getString("$.data.content##本章未完.*|请收藏.*|看书.*|本章节未.*|\\n{3,}")
        XCTAssertTrue(c.contains("正文内容"))
        XCTAssertFalse(c.contains("本章未完"))
    }

    // ===== 速读谷（CSS 规则，真实）=====
    // 规则真实：bookList=@css:.item  name=@css:.itemtxt h3 a@text  toc.chapterList=@css:#list ul li
    func testShudugu_cssRules() throws {
        let html = """
        <div class="item"><div class="itemtxt"><h3><a>合成标题</a></h3>
          <p>a</p><p><a>合成作者</a></p></div></div>
        """
        let a = AnalyzeRule()
        try a.setContent(html)
        XCTAssertEqual(try a.getString("@css:.itemtxt h3 a@text"), "合成标题")
        XCTAssertEqual(try a.getString("@css:.itemtxt p:eq(1) a@text##作者："), "合成作者")
    }
    func testShudugu_tocList() throws {
        let html = """
        <div id="list"><ul>
          <li><a href="/1">章1</a></li><li><a href="/2">章2</a></li>
        </ul></div>
        """
        let a = AnalyzeRule()
        try a.setContent(html)
        let els = try a.getElements("@css:#list ul li")
        XCTAssertEqual(els.count, 2)
    }

    // ===== 得奇小说网（CSS class. 语法，真实）=====
    // name=tag.h1@tag.a@text||tag.h3@tag.a@text
    func testDeqi_classAndOr() throws {
        let html = "<div class=\"item\"><h3><a>标题B</a></h3></div>"
        let a = AnalyzeRule()
        try a.setContent(html)
        let s = try a.getString("tag.h1@tag.a@text||tag.h3@tag.a@text")
        XCTAssertEqual(s, "标题B")
    }

    // ===== 笔趣阁345（CSS 属性选择 + 正文正则，真实）=====
    func testBiquge345_authorAttr() throws {
        let html = "<meta property=\"og:novel:author\" content=\"合成作者C\">"
        let a = AnalyzeRule()
        try a.setContent(html)
        XCTAssertEqual(try a.getString("[property=\"og:novel:author\"]@content"), "合成作者C")
    }

    // ===== 爱丽丝书屋（XPath 规则，真实）=====
    // search.bookList=//div[@class='list-group']/div[@class='list-group-item']
    func testAlice_xpathList() throws {
        let html = """
        <div class="list-group">
          <div class="list-group-item"><h5><a>1.合成书名</a></h5></div>
          <div class="list-group-item"><h5><a>2.合成书名二</a></h5></div>
        </div>
        """
        let a = AnalyzeRule()
        try a.setContent(html)
        let els = try a.getElements("//div[@class='list-group']/div[@class='list-group-item']")
        XCTAssertEqual(els.count, 2)
    }

    // ===== 魔丸小说（<js> 规则 + java.hexDecodeToString/ajax，真实）=====
    // 预期：toc/content 的 <js> 调用 java.hexDecodeToString（JsExtensions 未实现）-> 抛错。
    func testMowan_jsUnimplementedThrows() throws {
        let diag = RuleEngineDiagnostics()
        let a = AnalyzeRule(diagnostics: diag)
        try a.setContent("deadbeef")
        // 简化版真实 toc 规则片段：let url = java.hexDecodeToString(result);
        XCTAssertThrowsError(try a.getString("<js>let url = java.hexDecodeToString(result); url</js>")) { err in
            XCTAssertTrue("\(err)".contains("hexDecodeToString") || "\(err)".contains("尚未实现"), "got \(err)")
        }
    }

    // ===== 爱丽丝书屋 content（@js: + org.jsoup.Jsoup Java 互操作，真实）=====
    // 预期：Java 互操作在 JavaScriptCore 不支持 -> 抛错 + 记 diagnostics。
    func testAlice_jsoupInteropThrows() throws {
        let diag = RuleEngineDiagnostics()
        let a = AnalyzeRule(diagnostics: diag)
        try a.setContent("<div>x</div>")
        XCTAssertThrowsError(try a.getString("@js:var doc = org.jsoup.Jsoup.parse(result); doc"))
        XCTAssertTrue(diag.diagnostics.contains { $0.message.contains("org.jsoup") || $0.message.contains("互操作") })
    }

    // ===== 得间小说（class./body. 组合语法，真实）=====
    func testDejian_bodyBooks() throws {
        // body.books 对应 Jsoup 的 body 下 class=books；此处用近似合成结构
        let html = "<body><div class=\"books\"><span class=\"bookName\">合成书</span></div></body>"
        let a = AnalyzeRule()
        try a.setContent(html)
        let s = try a.getString(".bookName@text")
        XCTAssertEqual(s, "合成书")
    }

    // 7 个书源配置可被 JSON 解析（基本完整性）
    func testConfigFileParses() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "配置文件_7个", withExtension: "json"))
        let data = try Data(contentsOf: url)
        let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        XCTAssertEqual(arr?.count, 7)
    }
}
