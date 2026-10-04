//
//  AnalyzeRulePublicAPITests.swift
//  LegadoAnalyzeRulePublicAPITests
//
//  纯 public 接口测试（普通 import，非 @testable）：验证对外 API 可见性完整。
//  只用 public 符号；不触碰 internal。
//

import XCTest
import LegadoBookSource

final class AnalyzeRulePublicAPITests: XCTestCase {

    func testPublic_init() {
        let a = AnalyzeRule()
        XCTAssertNotNil(a)
    }

    func testPublic_initWithDeps() {
        let a = AnalyzeRule(
            ruleData: InMemoryRuleData(),
            book: InMemoryBook(name: "b"),
            chapter: InMemoryChapter(title: "t"),
            source: InMemorySource(),
            cookieStore: InMemoryCookieStore(),
            cacheManager: InMemoryCacheManager(),
            ajaxProvider: UnsupportedAjaxProvider(),
            webJSProvider: UnsupportedWebJSProvider(),
            diagnostics: RuleEngineDiagnostics()
        )
        XCTAssertNotNil(a)
    }

    func testPublic_getStringCss() throws {
        let a = AnalyzeRule()
        _ = try a.setContent("<p>hi</p>")
        XCTAssertEqual(try a.getString("p@text"), "hi")
    }

    func testPublic_getStringList() throws {
        let a = AnalyzeRule()
        _ = try a.setContent("<ul><li>a</li><li>b</li></ul>")
        XCTAssertEqual(try a.getStringList("li@text"), ["a", "b"])
    }

    func testPublic_getElements() throws {
        let a = AnalyzeRule()
        _ = try a.setContent("<ul><li>a</li><li>b</li></ul>")
        XCTAssertEqual(try a.getElements("li").count, 2)
    }

    func testPublic_putGet() {
        let a = AnalyzeRule(source: InMemorySource())
        _ = a.put("k", "v")
        XCTAssertEqual(a.get("k"), "v")
    }

    func testPublic_evalJS() throws {
        let a = AnalyzeRule()
        XCTAssertEqual(try a.evalJS("1+2").stringValue, "3.0")
    }

    func testPublic_splitSourceRule() throws {
        let a = AnalyzeRule()
        let list = try a.splitSourceRule("@XPath://a")
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list[0].mode, .xPath)
    }

    func testPublic_setBaseUrlRedirect() throws {
        let a = AnalyzeRule()
        _ = a.setBaseUrl("http://a.com")
        _ = a.setRedirectUrl("http://a.com/x")
        _ = try a.setContent("<a href=\"/y\">link</a>", baseUrl: "http://a.com")
        XCTAssertEqual(try a.getString("a@href", isUrl: true), "http://a.com/y")
    }

    func testPublic_ruleValueStringValue() {
        XCTAssertEqual(RuleValue.string("x").stringValue, "x")
        XCTAssertEqual(RuleValue.stringList(["a","b"]).stringValue, "[\"a\", \"b\"]")
        XCTAssertTrue(RuleValue.null.isNull)
    }

    func testPublic_networkUtils() {
        XCTAssertEqual(NetworkUtils.getBaseUrl("http://a.com/x"), "http://a.com")
        XCTAssertTrue(NetworkUtils.isAbsUrl("https://a.com"))
        XCTAssertTrue(NetworkUtils.isDataUrl("data:x;base64,AA"))
        XCTAssertEqual(NetworkUtils.getAbsoluteURL("http://a.com/b/c", "/x"), "http://a.com/x")
    }

    func testPublic_modeEnum() {
        let modes: [Mode] = [.xPath, .json, .default, .js, .regex, .webJs]
        XCTAssertEqual(modes.count, 6)
    }

    func testPublic_errorCases() {
        let e: RuleEngineError = .unsupported("x")
        XCTAssertNotNil(e.errorDescription)
    }
}
