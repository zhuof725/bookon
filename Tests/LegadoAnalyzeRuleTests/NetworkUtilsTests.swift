//
//  NetworkUtilsTests.swift
//  LegadoAnalyzeRuleTests
//
//  NetworkUtils（getAbsoluteURL / getBaseUrl / isAbsUrl / isDataUrl）、JavaURL 相对解析、
//  unescapeHtml4 的合成单测。
//
//  ⚠️ URL 相对解析与 unescapeHtml4 的「与 java.net.URL / commons-text 完全对齐」由
//     C 部分 golden 最终验证；本文件为【合成样本自测】，断言的是本移植对算法的理解。
//

import XCTest
@testable import LegadoBookSource

final class NetworkUtilsTests: XCTestCase {

    // MARK: - isAbsUrl / isDataUrl

    func testIsAbsUrl() {
        XCTAssertTrue(NetworkUtils.isAbsUrl("http://a.com"))
        XCTAssertTrue(NetworkUtils.isAbsUrl("HTTPS://a.com"))
        XCTAssertFalse(NetworkUtils.isAbsUrl("/path"))
        XCTAssertFalse(NetworkUtils.isAbsUrl("ftp://a"))
    }
    func testIsDataUrl() {
        XCTAssertTrue(NetworkUtils.isDataUrl("data:image/png;base64,AAAA"))
        XCTAssertFalse(NetworkUtils.isDataUrl("data:image/png,AAAA"))
        XCTAssertFalse(NetworkUtils.isDataUrl("http://a"))
    }

    // MARK: - getBaseUrl

    func testGetBaseUrl() {
        XCTAssertEqual(NetworkUtils.getBaseUrl("http://a.com/b/c"), "http://a.com")
        XCTAssertEqual(NetworkUtils.getBaseUrl("https://x.com"), "https://x.com")
        XCTAssertEqual(NetworkUtils.getBaseUrl("https://x.com/"), "https://x.com")
        XCTAssertNil(NetworkUtils.getBaseUrl("ftp://x"))
        XCTAssertNil(NetworkUtils.getBaseUrl(nil))
    }

    // MARK: - getAbsoluteURL（基础）

    func testAbs_absoluteReturnedAsIs() {
        XCTAssertEqual(NetworkUtils.getAbsoluteURL("http://a.com", "http://b.com/x"), "http://b.com/x")
    }
    func testAbs_nilBaseReturnsTrimmed() {
        XCTAssertEqual(NetworkUtils.getAbsoluteURL(nil, "  /x  "), "/x")
        XCTAssertEqual(NetworkUtils.getAbsoluteURL("", "  rel  "), "rel")
    }
    func testAbs_dataUrlReturnedAsIs() {
        let d = "data:img;base64,AA"
        XCTAssertEqual(NetworkUtils.getAbsoluteURL("http://a.com", d), d)
    }
    func testAbs_javascriptReturnsEmpty() {
        XCTAssertEqual(NetworkUtils.getAbsoluteURL("http://a.com", "javascript:void(0)"), "")
    }
    func testAbs_absoluteRootPath() {
        XCTAssertEqual(NetworkUtils.getAbsoluteURL("http://a.com/b/c", "/x/y"), "http://a.com/x/y")
    }
    func testAbs_relativePath() {
        XCTAssertEqual(NetworkUtils.getAbsoluteURL("http://a.com/b/c.html", "d.html"), "http://a.com/b/d.html")
    }
    func testAbs_dotDot() {
        XCTAssertEqual(NetworkUtils.getAbsoluteURL("http://a.com/b/c/d.html", "../x.html"), "http://a.com/b/x.html")
    }
    func testAbs_dotSlash() {
        XCTAssertEqual(NetworkUtils.getAbsoluteURL("http://a.com/b/c.html", "./x.html"), "http://a.com/b/x.html")
    }
    func testAbs_queryOnly() {
        XCTAssertEqual(NetworkUtils.getAbsoluteURL("http://a.com/b/c.html", "?k=v"), "http://a.com/b/c.html?k=v")
    }
    func testAbs_protocolRelative() {
        XCTAssertEqual(NetworkUtils.getAbsoluteURL("http://a.com/b", "//cdn.com/x.js"), "http://cdn.com/x.js")
    }
    func testAbs_substringBeforeComma() {
        // base 含逗号：取逗号前
        XCTAssertEqual(NetworkUtils.getAbsoluteURL("http://a.com/b/,extra", "x.html"), "http://a.com/b/x.html")
    }

    // MARK: - JavaURL parse

    func testParse_basic() {
        let u = JavaURL.parse("http://a.com:8080/p/q?x=1#frag")
        XCTAssertEqual(u?.scheme, "http")
        XCTAssertEqual(u?.authority, "a.com:8080")
        XCTAssertEqual(u?.path, "/p/q")
        XCTAssertEqual(u?.query, "x=1")
        XCTAssertEqual(u?.ref, "frag")
    }
    func testParse_invalidReturnsNil() {
        XCTAssertNil(JavaURL.parse("not a url"))
        XCTAssertNil(JavaURL.parse("/only/path"))
    }

    // MARK: - unescapeHtml4

    func testUnescape_basic() {
        XCTAssertEqual(HtmlUnescape.unescapeHtml4("A&amp;B"), "A&B")
        XCTAssertEqual(HtmlUnescape.unescapeHtml4("&lt;tag&gt;"), "<tag>")
        XCTAssertEqual(HtmlUnescape.unescapeHtml4("&quot;x&quot;"), "\"x\"")
    }
    func testUnescape_numericDecimal() {
        XCTAssertEqual(HtmlUnescape.unescapeHtml4("&#65;&#66;"), "AB")
    }
    func testUnescape_numericHex() {
        XCTAssertEqual(HtmlUnescape.unescapeHtml4("&#x41;&#X42;"), "AB")
    }
    func testUnescape_named() {
        XCTAssertEqual(HtmlUnescape.unescapeHtml4("&nbsp;"), "\u{00A0}")
        XCTAssertEqual(HtmlUnescape.unescapeHtml4("&copy;"), "©")
        XCTAssertEqual(HtmlUnescape.unescapeHtml4("&mdash;"), "—")
    }
    func testUnescape_noSemicolonNotDecoded() {
        // commons-text 对无分号命名实体不还原
        XCTAssertEqual(HtmlUnescape.unescapeHtml4("A&ampB"), "A&ampB")
    }
    func testUnescape_unknownKept() {
        XCTAssertEqual(HtmlUnescape.unescapeHtml4("&notanentity;"), "&notanentity;")
    }
    func testUnescape_noAmpFastPath() {
        XCTAssertEqual(HtmlUnescape.unescapeHtml4("no entities here"), "no entities here")
    }
    func testUnescape_mixed() {
        XCTAssertEqual(HtmlUnescape.unescapeHtml4("x &amp; y &#8364; z"), "x & y € z")
    }

    // MARK: - RegexTemplate Java->ICU

    func testTemplate_groupRef() {
        XCTAssertEqual(RegexTemplate.javaToICU("$1-$2"), "$1-$2")
    }
    func testTemplate_literalDollar() {
        XCTAssertEqual(RegexTemplate.javaToICU("price\\$5"), "price\\$5")
    }
    func testTemplate_bareDollarEscaped() {
        // $ 后非数字 -> 需转义
        XCTAssertEqual(RegexTemplate.javaToICU("a$b"), "a\\$b")
    }

    // MARK: - splitNotBlank

    func testSplitNotBlank() {
        XCTAssertEqual(LegadoStringUtils.splitNotBlank("a && b &&  c ", ["&&"]), ["a", "b", "c"])
        XCTAssertEqual(LegadoStringUtils.splitNotBlank("x,, y", [","]), ["x", "y"])
    }
}
