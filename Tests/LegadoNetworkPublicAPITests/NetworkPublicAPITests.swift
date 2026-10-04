//
//  NetworkPublicAPITests.swift
//  LegadoNetworkPublicAPITests
//
//  第 6 步 6A：网络层对外 API 的**纯 public 接口**测试（普通 import，非 @testable），
//  验证公开面完整可用、语义稳定。合成输入，不依赖任何 golden。
//

import XCTest
import LegadoBookSource

final class NetworkPublicAPITests: XCTestCase {

    // 1. AnalyzeUrl 基本解析：绝对 url
    func testParseAbsoluteUrl() {
        let a = AnalyzeUrl("https://www.example.com/search?q=1")
        XCTAssertEqual(a.url, "https://www.example.com/search?q=1")
        XCTAssertEqual(a.urlNoQuery, "https://www.example.com/search")
        XCTAssertEqual(a.getTag(), nil)
        XCTAssertFalse(a.isPost())
    }

    // 2. 相对 url + baseUrl
    func testRelativeUrlWithBase() {
        let a = AnalyzeUrl("/book/1.html", baseUrl: "https://www.example.com/list/")
        XCTAssertEqual(a.url, "https://www.example.com/book/1.html")
    }

    // 3. UrlOption 的 method 解析（POST）
    func testPostMethodFromUrlOption() {
        let a = AnalyzeUrl("https://www.example.com/api, {\"method\":\"POST\",\"body\":\"a=1&b=2\"}")
        XCTAssertTrue(a.isPost())
        XCTAssertEqual(a.encodedForm, "a=1&b=2")
        let req = a.buildRequest()
        XCTAssertEqual(req.method, .post)
        XCTAssertEqual(req.contentType, "application/x-www-form-urlencoded")
        XCTAssertEqual(req.body, Data("a=1&b=2".utf8))
    }

    // 4. UrlOption headers 合并（后覆盖先，源 header 在前）
    func testHeaderMergeOrder() {
        let a = AnalyzeUrl("https://www.example.com/, {\"headers\":{\"X-B\":\"2\",\"X-A\":\"1\"}}",
                           headerMapF: [("X-A", "0"), ("X-C", "3")])
        let req = a.buildRequest()
        let names = req.headers.map { $0.0 }
        XCTAssertEqual(names, ["X-A", "X-C", "X-B"])
        XCTAssertEqual(req.header("X-A"), "1")
    }

    // 5. GET 的 query 编码（含中文与空格）
    func testGetQueryEncoding() {
        let a = AnalyzeUrl("https://www.example.com/search?key=中文 x")
        let req = a.buildRequest()
        XCTAssertEqual(req.url, "https://www.example.com/search?key=%E4%B8%AD%E6%96%87%20x")
        XCTAssertEqual(req.method, .get)
        XCTAssertNil(req.body)
    }

    // 6. 静态 encodeParams（公开测试钩子）
    func testEncodeParamsPublic() {
        XCTAssertEqual(AnalyzeUrl.encodeParams("a=1&b=2", charset: nil, isQuery: false), "a=1&b=2")
        XCTAssertEqual(AnalyzeUrl.encodeParams("a=中 文", charset: nil, isQuery: false), "a=%E4%B8%AD+%E6%96%87")
        XCTAssertEqual(AnalyzeUrl.encodeParams("", charset: nil, isQuery: false), "")
    }

    // 7. NetworkUtils 的编码判定
    func testEncodedQueryFormFlags() {
        XCTAssertTrue(NetworkUtils.encodedQuery("a=1&b=2"))
        XCTAssertTrue(NetworkUtils.encodedQuery("a=%41"))
        XCTAssertFalse(NetworkUtils.encodedQuery("a=中"))
        XCTAssertTrue(NetworkUtils.encodedForm("a%41"))
        XCTAssertFalse(NetworkUtils.encodedForm("a 1"))
    }

    // 8. escape（EncoderUtils.escape）
    func testEscape() {
        XCTAssertEqual(AnalyzeUrl.escape("abc"), "abc")
        XCTAssertEqual(AnalyzeUrl.escape("a b"), "a%20b")
        XCTAssertEqual(AnalyzeUrl.escape("中"), "%u4e2d")
    }

    // 9. getSubDomain
    func testGetSubDomain() {
        XCTAssertEqual(NetworkUtils.getSubDomain("https://www.twkan.cc/book/1"), "twkan.cc")
        XCTAssertEqual(NetworkUtils.getSubDomain("http://127.0.0.1:8080/x"), "127.0.0.1")
        XCTAssertEqual(NetworkUtils.getSubDomain("https://a.b.c.example.com/x"), "example.com")
    }

    // 10. UrlOption 解析（宽松回退）
    func testUrlOptionLenientFallback() {
        let strict = UrlOption.parseStrict("{\"method\":\"POST\"}")
        XCTAssertEqual(strict?.getMethod(), "POST")
        // 单引号在严格模式失败、宽松模式成功
        let option = UrlOption.parse("{'method':'HEAD'}")
        XCTAssertEqual(option?.getMethod(), "HEAD")
        XCTAssertEqual(option?.usedLenientFallback, true)
    }

    // 11. data URI
    func testDataUri() {
        let a = AnalyzeUrl("data:text/plain;base64,aGVsbG8=")
        XCTAssertEqual(a.getByteArrayIfDataUri(), Data("hello".utf8))
        let b = AnalyzeUrl("https://example.com/")
        XCTAssertNil(b.getByteArrayIfDataUri())
    }

    // 12. buildRequest 的 HEAD
    func testHeadRequest() {
        let a = AnalyzeUrl("https://www.example.com/x?y=1, {\"method\":\"head\"}")
        let req = a.buildRequest()
        XCTAssertEqual(req.method, .head)
        XCTAssertEqual(req.url, "https://www.example.com/x?y=1")
        XCTAssertNil(req.body)
    }

    // 13. Cookie 合并工具
    func testCookieMerge() {
        XCTAssertEqual(CookieMerge.mergeCookies(["a=1; b=2", "b=3"]) ?? "", "a=1; b=3")
        XCTAssertNil(CookieMerge.mergeCookies([nil, nil]))
        XCTAssertEqual(CookieMerge.mapToCookie([("a", "1")]), "a=1")
    }

    // 14. rate limiter 公开构造（无限速时直接放行）
    func testRateLimiterPublicSurface() async {
        let limiter = ConcurrentRateLimiter(concurrentRate: nil, key: "k")
        let record = await limiter.getConcurrentRecord()
        XCTAssertNil(record)
    }

    // 15. HTTPRequest/HTTPResponse 公开字段
    func testHTTPModelsPublicSurface() {
        let req = HTTPRequest(url: "https://x/", method: .get, headers: [("A", "1")])
        XCTAssertEqual(req.header("a"), "1")
        let resp = HTTPResponse(url: "https://x/", status: 200,
                                headers: [("Set-Cookie", "a=1"), ("Set-Cookie", "b=2")],
                                body: Data("ok".utf8))
        XCTAssertEqual(resp.headerValues("Set-Cookie"), ["a=1", "b=2"])
        XCTAssertEqual(resp.status, 200)
    }

    // 16. 速率 "次数/毫秒" 的新建语义（公开面）
    func testRateLimiterBareAndSlash() async throws {
        let store = ConcurrentRecordStore()
        let clock = SystemRateLimitClock()
        let a = ConcurrentRateLimiter(concurrentRate: "3/60000", key: "k1", store: store, clock: clock)
        let record = try await a.fetchStart()
        XCTAssertEqual(record?.accessLimit, 3)
        XCTAssertEqual(record?.interval, 60000)
    }
}
