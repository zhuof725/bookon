//
//  AnalyzeRuleDispatchTests.swift
//  LegadoAnalyzeRuleTests
//
//  getString / getStringList / getElement(s) 调度测试。
//  所有 HTML/JSON 为【合成样本，非真实数据】。
//

import XCTest
import SwiftSoup
@testable import LegadoBookSource

final class AnalyzeRuleDispatchTests: XCTestCase {

    private let sampleHTML = """
    <html><body>
      <div class="book">
        <h1 class="title">测试书名</h1>
        <p class="author">作者甲</p>
        <ul class="chapters">
          <li><a href="/c/1">第一章</a></li>
          <li><a href="/c/2">第二章</a></li>
          <li><a href="/c/3">第三章</a></li>
        </ul>
      </div>
    </body></html>
    """

    private let sampleJSON = """
    {"data":{"name":"JSON书名","author":"作者乙","tags":["玄幻","都市"]},
     "list":[{"t":"章1"},{"t":"章2"}]}
    """

    private func htmlRule(_ base: String? = nil) throws -> AnalyzeRule {
        let a = AnalyzeRule()
        try a.setContent(sampleHTML, baseUrl: base)
        return a
    }
    private func jsonRule() throws -> AnalyzeRule {
        let a = AnalyzeRule()
        try a.setContent(sampleJSON)
        return a
    }

    // MARK: - setContent / isJSON 自动判定

    func testSetContent_htmlNotJson() throws {
        let a = try htmlRule()
        // HTML 内容下 $. 规则不会被当 JSON（isJSON=false），而是按字面/默认
        let list = try a.splitSourceRule("$.data.name")
        XCTAssertEqual(list[0].mode, .json) // $. 前缀始终 JSON
    }
    func testSetContent_jsonAutoDetect() throws {
        let a = try jsonRule()
        // isJSON=true 时普通规则也走 JSON
        let list = try a.splitSourceRule("data.name")
        XCTAssertEqual(list[0].mode, .json)
    }
    func testSetContent_nilThrows() {
        let a = AnalyzeRule()
        XCTAssertThrowsError(try a.setContent(nil))
    }
    func testSetContent_emptyStringIsNotJSON() throws {
        let a = AnalyzeRule()
        try a.setContent("plain text")
        let list = try a.splitSourceRule("foo")
        XCTAssertEqual(list[0].mode, .default)
    }

    // MARK: - getString（CSS / Default）

    func testGetString_cssTitle() throws {
        let a = try htmlRule()
        // 注：class=title 的元素是 <h1>（非 div），故用 .title 或 h1.title（对齐 CSS 语义）
        XCTAssertEqual(try a.getString(".title@text"), "测试书名")
    }
    func testGetString_cssAuthor() throws {
        let a = try htmlRule()
        XCTAssertEqual(try a.getString(".author@text"), "作者甲")
    }
    func testGetString_emptyRuleReturnsEmpty() throws {
        let a = try htmlRule()
        XCTAssertEqual(try a.getString(""), "")
        XCTAssertEqual(try a.getString(nil), "")
    }
    func testGetString_noContent() throws {
        let a = AnalyzeRule()
        XCTAssertEqual(try a.getString("div@text"), "")
    }

    // MARK: - getString（XPath）

    func testGetString_xpathTitle() throws {
        let a = try htmlRule()
        let s = try a.getString("@XPath://h1/text()")
        XCTAssertTrue(s.contains("测试书名"), "got: \(s)")
    }

    // MARK: - getString（JSON）

    func testGetString_jsonName() throws {
        let a = try jsonRule()
        XCTAssertEqual(try a.getString("$.data.name"), "JSON书名")
    }
    func testGetString_jsonAuthor() throws {
        let a = try jsonRule()
        XCTAssertEqual(try a.getString("@Json:$.data.author"), "作者乙")
    }

    // MARK: - getStringList

    func testGetStringList_cssChapters() throws {
        let a = try htmlRule()
        let list = try a.getStringList("ul.chapters li a@text")
        XCTAssertEqual(list, ["第一章", "第二章", "第三章"])
    }
    func testGetStringList_jsonTags() throws {
        let a = try jsonRule()
        let list = try a.getStringList("$.data.tags")
        XCTAssertEqual(list, ["玄幻", "都市"])
    }
    func testGetStringList_emptyRuleNil() throws {
        let a = try htmlRule()
        XCTAssertNil(try a.getStringList(""))
        XCTAssertNil(try a.getStringList(nil))
    }
    func testGetStringList_stringSplitByNewline() throws {
        // getStringList 对最终为 String 的结果按 "\n" 切分。用 JS 返回多行字符串验证。
        let a = AnalyzeRule()
        try a.setContent("x")
        let list = try a.getStringList("{{'x\\ny\\nz'}}")
        XCTAssertEqual(list, ["x", "y", "z"])
    }

    // MARK: - isUrl 绝对地址拼接

    func testGetString_isUrlAbsolute() throws {
        let a = try htmlRule("http://example.com/book/1")
        _ = a.setRedirectUrl("http://example.com/book/1")
        let url = try a.getString("ul.chapters li a@href", isUrl: true)
        XCTAssertEqual(url, "http://example.com/c/1")
    }
    func testGetStringList_isUrlAbsolute() throws {
        let a = try htmlRule("http://example.com/book/1")
        _ = a.setRedirectUrl("http://example.com/book/1")
        let urls = try a.getStringList("ul.chapters li a@href", isUrl: true)
        XCTAssertEqual(urls, ["http://example.com/c/1", "http://example.com/c/2", "http://example.com/c/3"])
    }
    func testGetString_isUrlBlankReturnsBaseUrl() throws {
        let a = try htmlRule("http://example.com/x")
        let url = try a.getString("div.nonexistent@text", isUrl: true)
        XCTAssertEqual(url, "http://example.com/x")
    }

    // MARK: - getElement / getElements

    func testGetElement_css() throws {
        let a = try htmlRule()
        let el = try a.getElement("div.book")
        XCTAssertNotNil(el)
    }
    func testGetElements_cssList() throws {
        let a = try htmlRule()
        let els = try a.getElements("ul.chapters li")
        XCTAssertEqual(els.count, 3)
    }
    func testGetElements_empty() throws {
        let a = try htmlRule()
        let els = try a.getElements("div.nonexistent")
        XCTAssertEqual(els.count, 0)
    }

    // MARK: - unescape HTML

    func testGetString_unescapeHtml4() throws {
        let a = AnalyzeRule()
        try a.setContent("<p>A&amp;B&lt;C&gt;D &#65; &#x42;</p>")
        let s = try a.getString("p@text")
        XCTAssertEqual(s, "A&B<C>D A B")
    }
    func testGetString_noUnescapeWhenFlagOff() throws {
        // 注：SwiftSoup（同 jsoup）的 text() 已对实体解码，故 @text 规则下内容已是 "A&B"。
        // 用含裸 & 但不经 JSoup 解码的场景验证 unescape 开关：content 为纯字符串 + 正则直出。
        let a = AnalyzeRule()
        try a.setContent("x")
        // {{ }} 返回字符串 "A&amp;B"；unescape=false 不还原
        let off = try a.getString("{{'A&amp;B'}}", unescape: false)
        XCTAssertEqual(off, "A&amp;B")
        let on = try a.getString("{{'A&amp;B'}}", unescape: true)
        XCTAssertEqual(on, "A&B")
    }
}
