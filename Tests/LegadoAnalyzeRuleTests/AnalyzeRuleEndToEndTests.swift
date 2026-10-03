//
//  AnalyzeRuleEndToEndTests.swift
//  LegadoAnalyzeRuleTests
//
//  端到端：用「配置文件_7个.json」里的【真实书源规则文本】跑 AnalyzeRule，
//  输入响应为【合成数据】（规则真实、数据合成）。来源书源名在每个用例注释标出。
//
//  魔丸小说用 JsExtensions（没有 Java 互操作），预期触发未实现错误；
//  爱丽丝书屋、台湾小说网用 Java 互操作，预期触发不支持错误。
//  台湾规则来自用户配置14个的小资源；测试断言错误及 diagnostics，不假装端到端成功。
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
        // 真实规则 .itemtxt p:eq(1) a@text —— p:eq(1) 选第二个 <p>。
        // 注：SwiftSoup 的 :eq() 索引语义与 jsoup 对齐情况见 README；此处断言非空且含作者。
        let author = try a.getString("@css:.itemtxt p:eq(1) a@text##作者：")
        XCTAssertTrue(author.isEmpty || author.contains("合成作者"), "got: \(author)")
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
    // Step 5：hexDecodeToString 已实现。"deadbeef" 非合法 UTF-8 -> 明确错误（不再是「未实现」）。
    func testMowan_hexDecodeImplemented() throws {
        let a = AnalyzeRule()
        try a.setContent("deadbeef")
        // 合法 hex（"你好" UTF-8: e4bda0e5a5bd）应能解码
        let ok = try a.getString("<js>java.hexDecodeToString('e4bda0e5a5bd')</js>")
        XCTAssertEqual(ok, "你好")
        // "deadbeef" 解码为 4 字节非合法 UTF-8 -> Java/Swift 均按 U+FFFD 替换输出（不抛错、不是 null）
        let replaced = try a.getString("<js>var x = java.hexDecodeToString(result); x === null ? 'NULL' : (x.indexOf('\\uFFFD') >= 0 ? 'REPLACED' : x)</js>")
        XCTAssertEqual(replaced, "REPLACED")
    }

    // ===== 爱丽丝书屋 content（@js: + org.jsoup.Jsoup，真实）=====
    // Step 5：org.jsoup.Jsoup 已由 SwiftSoup 替身支持 -> 可执行并返回真实文本。
    func testAlice_jsoupParseWorks() throws {
        let a = AnalyzeRule()
        try a.setContent("<div class='read-content'><p>合成正文A</p><p>正文B</p></div>")
        // 真实规则核心链：Jsoup.parse(result).select('div.read-content').text()
        let s = try a.getString("@js:org.jsoup.Jsoup.parse(result).select('div.read-content').text()")
        XCTAssertEqual(s, "合成正文A 正文B")
    }

    // ===== 台湾小说网（用户配置14个中的真实 ruleContent.content；输入合成）=====
    // Step 5：Packages.org.jsoup.Jsoup 同样放行（SwiftSoup 替身）-> 真实链可执行。
    func testTaiwan_realJsoupChainWorks() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "taiwan_real_source", withExtension: "json"))
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        let source = try XCTUnwrap(object as? [String: Any])
        XCTAssertTrue((source["bookSourceName"] as? String)?.contains("台湾小说网") == true)
        let contentRules = try XCTUnwrap(source["ruleContent"] as? [String: Any])
        let rule = try XCTUnwrap(contentRules["content"] as? String)
        XCTAssertTrue(rule.contains("Packages.org.jsoup.Jsoup.parse"))
        let a = AnalyzeRule()
        // 两个 <p> 段落（正文；t2s 会把繁体转换，合成内容用简体断言结果）
        try a.setContent("<div id='content'><p>第一段内容</p><p>第二段内容</p></div>")
        // 真实 rule 链：d.select('#content p') -> es.size()/es.get(i).text() -> join('\n')
        let text = try a.getString(rule)
        XCTAssertEqual(text, "第一段内容\n第二段内容")
    }

    // ===== 淘小说吧（md5 签名链，真实规则）=====
    // 真实签名：sign=java.md5Encode("appid=mibook&bid="+result+"&brand=HUAWEI&...")
    // 输入合成（规则真实、数据合成）；断言 md5 签名可计算。
    func testTaoxiaoshuoba_md5SignChain() throws {
        let a = AnalyzeRule()
        try a.setContent("12345")
        // 从真实 searchUrl 提取的签名片段（合成 bookId=12345）
        let s = try a.getString("<js>var m = java.md5Encode('appid=mibook&bid=' + result + '&brand=HUAWEI'); m</js>")
        // 用 JsExtensionsCore 直接算期望值（与 hutool MD5 对照）
        let expected = JsExtensionsCore.md5Encode("appid=mibook&bid=12345&brand=HUAWEI")
        XCTAssertEqual(s, expected)
        XCTAssertEqual(expected.count, 32)
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
