//
//  RealJsNetworkProviderTests.swift
//  LegadoNetworkTests
//
//  第 6 步 6B：RealJsNetworkExtensionsProvider / RealAjaxProvider 的真实网络/文件测试。
//
//  复用 URLSessionHTTPClientTests.swift 的 LocalScriptedServer（NWListener + 脚本化路由），
//  按真实 URLSessionHTTPClient 走本地回环请求；JS 可见对象（get/post/head 的
//  Connection.Response 替身、connect 的 StrResponse 替身、ajaxAll 数组）通过 AnalyzeRule.evalJS
//  （真实 JavaScriptCore + JSJavaBridge + JsExtensionsRuntime 的完整链路）断言。
//
//  覆盖：ajax 成功/失败/非 2xx/type=data 分支、get/head/post 的 JS 对象方法与 headers 传参、
//  不跟随重定向（js 重定向拦截）、cookies()/cookieKey()、connect 成功/失败/header JSON、
//  ajaxAll 多 URL 与顺序、ajaxAll 失败抛错、cacheFile 落盘与二次命中、downloadFile 内容与大小、
//  未实现方法仍抛 unsupported 的回归、java.get 单参仍为变量读取、AnalyzeRule 默认 provider 接线。
//

import XCTest
import Foundation
@testable import LegadoBookSource

final class RealJsNetworkProviderTests: XCTestCase {

    private var servers: [LocalScriptedServer] = []
    private var tempDirs: [URL] = []

    override func tearDown() {
        for server in servers { server.stop() }
        servers.removeAll()
        for dir in tempDirs { try? FileManager.default.removeItem(at: dir) }
        tempDirs.removeAll()
        super.tearDown()
    }

    // MARK: - 工具

    private func startServer(handlers: [String: LocalScriptedServer.Handler],
                             defaultHandler: LocalScriptedServer.Handler? = nil) throws -> LocalScriptedServer {
        let server = try LocalScriptedServer(handlers: handlers, defaultHandler: defaultHandler)
        try server.start()
        servers.append(server)
        return server
    }

    private func url(_ path: String, _ server: LocalScriptedServer) -> String {
        return "http://127.0.0.1:\(server.port)\(path)"
    }

    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("legado-js-net-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tempDirs.append(dir)
        return dir
    }

    /// 真实客户端（每次全新 CookieStore/CacheManager，互不串扰）。
    private func makeRealClient() -> URLSessionHTTPClient {
        let cache = CacheManager(storage: MemoryCacheStorage())
        let store = CookieStore(persistence: MemoryCookiePersistence(), cache: cache)
        return URLSessionHTTPClient(cookieStore: store, cookieManagerCache: cache)
    }

    private func makeProvider(cacheDirectory: URL? = nil,
                              cacheManager: CacheManagerProtocol = InMemoryCacheManager(),
                              diagnostics: RuleEngineDiagnostics? = nil) -> RealJsNetworkExtensionsProvider {
        return RealJsNetworkExtensionsProvider(client: makeRealClient(),
                                               cacheManager: cacheManager,
                                               cacheDirectory: cacheDirectory ?? makeTempDir(),
                                               diagnostics: diagnostics)
    }

    /// 通过真实 JS 引擎（evalJS）执行 JS 片段：完整链路 java 桥 → JsExtensionsRuntime → provider。
    private func makeRule(provider: RealJsNetworkExtensionsProvider,
                          ajaxProvider: AjaxProvider) -> AnalyzeRule {
        return AnalyzeRule(ajaxProvider: ajaxProvider,
                           jsNetworkProvider: provider,
                           diagnostics: RuleEngineDiagnostics())
    }

    private func okBody(_ text: String) -> LocalScriptedServer.Response {
        return LocalScriptedServer.Response(status: 200, reason: "OK",
                                            headers: [("Content-Type", "text/plain; charset=utf-8")],
                                            body: Data(text.utf8))
    }

    // MARK: - 1. ajax：成功返回 body

    func testAjaxReturnsBodyOnSuccess() async throws {
        let server = try startServer(handlers: [
            "/hello": { _ in
                LocalScriptedServer.Response(status: 200, reason: "OK",
                                             headers: [("Content-Type", "text/plain")],
                                             body: Data("hello-body".utf8))
            }
        ])
        let urlStr = url("/hello", server)
        let provider = RealAjaxProvider(client: makeRealClient())
        let body = provider.ajax(urlStr)
        XCTAssertEqual(body, "hello-body")
    }

    // MARK: - 2. ajax：失败返回错误串（对齐 getOrElse { stackTraceStr }，不抛异常）

    func testAjaxReturnsErrorStringOnConnectionFailure() {
        let provider = RealAjaxProvider(client: makeRealClient())
        let body = provider.ajax("http://127.0.0.1:1/refused")
        XCTAssertNotNil(body)
        XCTAssertTrue(body?.hasPrefix("ajax(http://127.0.0.1:1/refused) error") == true,
                      "失败应返回 ajax(url) error\\n... 错误串，实际：\(body ?? "nil")")
    }

    // MARK: - 3. ajax：非 2xx 也返回 body（Kotlin getStrResponse 不看状态码）

    func testAjaxReturnsBodyEvenOnNon2xx() async throws {
        let server = try startServer(handlers: [
            "/err": { _ in
                LocalScriptedServer.Response(status: 500, reason: "Server Error",
                                             headers: [("Content-Type", "text/plain")],
                                             body: Data("boom".utf8))
            }
        ])
        let provider = RealAjaxProvider(client: makeRealClient())
        let body = provider.ajax(url("/err", server))
        XCTAssertEqual(body, "boom")
        XCTAssertEqual(server.requests.count, 1)
    }

    // MARK: - 4. ajax：type != null（data: URI + url option）返回字节的十六进制串

    func testAjaxDataUriTypeReturnsHex() throws {
        let provider = RealAjaxProvider(client: makeRealClient())
        // base64 "aGVsbG8=" = "hello"；,{"type":"json"} 提供 url option 的 type。
        let urlStr = "data:text/plain;base64,aGVsbG8=,{\"type\":\"json\"}"
        let body = provider.ajax(urlStr)
        XCTAssertEqual(body, "68656c6c6f", "type!=null 时应返回字节的十六进制串（对齐 getStrResponseAwait）")
    }

    // MARK: - 5. get：JS 可见 Connection.Response 替身（body/statusCode/statusMessage/header/headers/url）

    func testGetThroughJSEngineBodyStatusMessageHeader() async throws {
        let server = try startServer(handlers: [
            "/hello": { _ in
                LocalScriptedServer.Response(status: 200, reason: "OK",
                                             headers: [("Content-Type", "text/plain; charset=utf-8"),
                                                       ("X-Test", "hello")],
                                             body: Data("hello-body".utf8))
            }
        ])
        let target = url("/hello", server)
        let rule = makeRule(provider: makeProvider(), ajaxProvider: RealAjaxProvider(client: makeRealClient()))
        let v = try rule.evalJS("""
        var r = java.get('\(target)', {});
        [r.body(), r.statusCode(), r.statusMessage(), r.header('X-Test'), r.header('x-test'),
         r.headers()['X-Test'][0], r.headers().get('x-test')[0],
         r.contentType().indexOf('text/plain') === 0, r.url()].join('|')
        """)
        XCTAssertEqual(v.stringValue, "hello-body|200|OK|hello|hello|hello|hello|true|\(target)")
        XCTAssertEqual(server.requests.count, 1)
    }

    // MARK: - 6. get：JS headers 对象（JSON 桥接）真实到达服务器

    func testGetHeadersObjectReachesServer() async throws {
        let server = try startServer(handlers: [
            "/h": { _ in self.okBody("ok") }
        ])
        let rule = makeRule(provider: makeProvider(), ajaxProvider: RealAjaxProvider(client: makeRealClient()))
        let v = try rule.evalJS("""
        var r = java.get('\(url("/h", server))', {"X-Custom": "abc", "Referer": "http://a.b/"});
        r.body()
        """)
        XCTAssertEqual(v.stringValue, "ok")
        XCTAssertEqual(server.requests.count, 1)
        XCTAssertEqual(server.requests.first?.header("X-Custom"), "abc")
        XCTAssertEqual(server.requests.first?.header("Referer"), "http://a.b/")
    }

    // MARK: - 7. get：cookies()/cookieKey() 从 Set-Cookie 解析

    func testGetCookiesAndCookieKey() async throws {
        let server = try startServer(handlers: [
            "/c": { _ in
                LocalScriptedServer.Response(status: 200, reason: "OK",
                                             headers: [("Set-Cookie", "sid=abc123; Path=/; HttpOnly"),
                                                       ("Set-Cookie", "theme=dark")],
                                             body: Data("c".utf8))
            }
        ])
        let rule = makeRule(provider: makeProvider(), ajaxProvider: RealAjaxProvider(client: makeRealClient()))
        let v = try rule.evalJS("""
        var r = java.get('\(url("/c", server))', {});
        [r.cookies()['sid'], r.cookieKey('sid'), r.cookies()['theme'], r.cookies().get('sid'), r.cookieKey('nope')].join('|')
        """)
        XCTAssertEqual(v.stringValue, "abc123|abc123|dark|abc123|")
    }

    // MARK: - 8. head：JS 对象（无 body）

    func testHeadThroughJSEngine() async throws {
        let server = try startServer(handlers: [
            "/h": { _ in
                LocalScriptedServer.Response(status: 200, reason: "OK",
                                             headers: [("X-Head", "yes")],
                                             body: Data())
            }
        ])
        let rule = makeRule(provider: makeProvider(), ajaxProvider: RealAjaxProvider(client: makeRealClient()))
        let v = try rule.evalJS("""
        var r = java.head('\(url("/h", server))', {});
        [r.statusCode(), r.header('X-Head'), r.body().length].join('|')
        """)
        XCTAssertEqual(v.stringValue, "200|yes|0")
        XCTAssertEqual(server.requests.first?.method, "HEAD")
    }

    // MARK: - 9. post：body 与 Content-Type 到达服务器

    func testPostThroughJSEngineBodyAndContentType() async throws {
        let server = try startServer(handlers: [
            "/p": { req in
                self.okBody("got:" + (String(data: req.body, encoding: .utf8) ?? ""))
            }
        ])
        let rule = makeRule(provider: makeProvider(), ajaxProvider: RealAjaxProvider(client: makeRealClient()))
        let v = try rule.evalJS("""
        var r = java.post('\(url("/p", server))', 'a=1', {"Content-Type": "application/x-www-form-urlencoded"});
        [r.body(), r.statusCode()].join('|')
        """)
        XCTAssertEqual(v.stringValue, "got:a=1|200")
        XCTAssertEqual(server.requests.first?.method, "POST")
        XCTAssertEqual(server.requests.first?.body, Data("a=1".utf8))
        XCTAssertEqual(server.requests.first?.header("Content-Type"), "application/x-www-form-urlencoded")
    }

    // MARK: - 10. get：不跟随重定向（js 重定向拦截语义），3xx 原样返回

    func testGetDoesNotFollowRedirect() async throws {
        let server = try startServer(handlers: [
            "/start": { _ in
                LocalScriptedServer.Response(status: 302, reason: "Found",
                                             headers: [("Location", "/next")],
                                             body: Data())
            },
            "/next": { _ in self.okBody("next-page") }
        ])
        let rule = makeRule(provider: makeProvider(), ajaxProvider: RealAjaxProvider(client: makeRealClient()))
        let v = try rule.evalJS("""
        var r = java.get('\(url("/start", server))', {});
        [r.statusCode(), r.header('Location'), r.body()].join('|')
        """)
        XCTAssertEqual(v.stringValue, "302|/next|")
        XCTAssertEqual(server.requests.count, 1, "followRedirects(false)：不应产生第二跳请求")
        XCTAssertEqual(server.requests.first?.path, "/start")
    }

    // MARK: - 11. post：不跟随重定向（301/302 原样返回，不转 GET）

    func testPostDoesNotFollowRedirect() async throws {
        let server = try startServer(handlers: [
            "/p": { _ in
                LocalScriptedServer.Response(status: 301, reason: "Moved",
                                             headers: [("Location", "/moved")],
                                             body: Data())
            }
        ])
        let rule = makeRule(provider: makeProvider(), ajaxProvider: RealAjaxProvider(client: makeRealClient()))
        let v = try rule.evalJS("""
        var r = java.post('\(url("/p", server))', 'x=1', {});
        [r.statusCode(), r.header('Location')].join('|')
        """)
        XCTAssertEqual(v.stringValue, "301|/moved")
        XCTAssertEqual(server.requests.count, 1)
        XCTAssertEqual(server.requests.first?.method, "POST")
    }

    // MARK: - 12. connect：StrResponse 替身方法（body/code/message/callTime/url）

    func testConnectStrResponseMethodsJS() async throws {
        let server = try startServer(handlers: [
            "/hello": { _ in
                LocalScriptedServer.Response(status: 200, reason: "OK",
                                             headers: [("Content-Type", "text/plain")],
                                             body: Data("hello-body".utf8))
            }
        ])
        let target = url("/hello", server)
        let rule = makeRule(provider: makeProvider(), ajaxProvider: RealAjaxProvider(client: makeRealClient()))
        let v = try rule.evalJS("""
        var r = java.connect('\(target)');
        [r.body(), r.code(), r.message(), (r.callTime() >= 0), r.url(), (r.toString().indexOf('Response{') === 0)].join('|')
        """)
        XCTAssertEqual(v.stringValue, "hello-body|200|OK|true|\(target)|true")
    }

    // MARK: - 13. connect：失败返回错误体 StrResponse（code 200/callTime 0，对齐 Kotlin 构造器）

    func testConnectFailureReturnsErrorStrResponse() throws {
        let rule = makeRule(provider: makeProvider(), ajaxProvider: RealAjaxProvider(client: makeRealClient()))
        let v = try rule.evalJS("""
        var r = java.connect('http://127.0.0.1:1/refused');
        [r.code(), r.callTime(), (r.body().indexOf('HTTPError') >= 0)].join('|')
        """)
        XCTAssertEqual(v.stringValue, "200|0|true",
                       "对齐 Kotlin StrResponse(url, stackTraceStr)：raw 固定 200 OK、callTime 0")
    }

    // MARK: - 14. connect：header JSON 字符串与 callTimeout 参数

    func testConnectHeaderJSONAndTimeout() async throws {
        let server = try startServer(handlers: [
            "/h": { _ in self.okBody("with-header") }
        ])
        let rule = makeRule(provider: makeProvider(), ajaxProvider: RealAjaxProvider(client: makeRealClient()))
        let v = try rule.evalJS("""
        var r = java.connect('\(url("/h", server))', '{"X-A": "1"}', 5000);
        [r.body(), r.code()].join('|')
        """)
        XCTAssertEqual(v.stringValue, "with-header|200")
        XCTAssertEqual(server.requests.first?.header("X-A"), "1")
        XCTAssertEqual(server.requests.count, 1)
    }

    // MARK: - 15. ajaxAll：多 URL 并发且顺序与输入一致

    func testAjaxAllMultipleUrlsJS() async throws {
        let server = try startServer(handlers: [
            "/a": { _ in self.okBody("body-A") },
            "/b": { _ in self.okBody("body-B") },
            "/c": { _ in self.okBody("body-C") }
        ])
        let rule = makeRule(provider: makeProvider(), ajaxProvider: RealAjaxProvider(client: makeRealClient()))
        let v = try rule.evalJS("""
        var arr = java.ajaxAll(['\(url("/a", server))', '\(url("/b", server))', '\(url("/c", server))']);
        [arr.length, arr[0].body(), arr[1].body(), arr[2].body(), (arr[0].callTime() >= 0)].join('|')
        """)
        XCTAssertEqual(v.stringValue, "3|body-A|body-B|body-C|true")
        XCTAssertEqual(server.requests.count, 3)
    }

    // MARK: - 16. ajaxAll：任一 URL 失败整体抛错（对齐 Kotlin isTest=false 语义）

    func testAjaxAllFailureThrowsJS() async throws {
        let server = try startServer(handlers: [
            "/a": { _ in self.okBody("body-A") }
        ])
        let rule = makeRule(provider: makeProvider(), ajaxProvider: RealAjaxProvider(client: makeRealClient()))
        XCTAssertThrowsError(try rule.evalJS("""
        java.ajaxAll(['\(url("/a", server))', 'http://127.0.0.1:1/refused'])
        """))
    }

    // MARK: - 17. cacheFile：首次下载落盘，二次读取命中缓存（不再发请求）

    func testCacheFileDownloadsThenServesFromCache() async throws {
        let server = try startServer(handlers: [
            "/js": { _ in self.okBody("var a = 1;") }
        ])
        let target = url("/js", server)
        let cacheDir = makeTempDir()
        let cacheManager = InMemoryCacheManager()
        let provider = makeProvider(cacheDirectory: cacheDir, cacheManager: cacheManager)

        let first = try provider.invoke(method: "cacheFile", arguments: [target])
        XCTAssertEqual(first, "var a = 1;")
        XCTAssertEqual(server.requests.count, 1)

        // 落盘文件名 = md5Encode16(url).js
        let md5 = JsExtensionsCore.md5Encode16(target)
        let fileURL = cacheDir.appendingPathComponent(md5 + ".js")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        // Kotlin: CacheManager.put(key, path, saveTime) → get(key) 返回相对路径
        XCTAssertEqual(cacheManager.get(md5), "/" + md5 + ".js")

        let second = try provider.invoke(method: "cacheFile", arguments: [target])
        XCTAssertEqual(second, "var a = 1;")
        XCTAssertEqual(server.requests.count, 1, "二次调用应命中缓存，不再发请求")
    }

    // MARK: - 18. cacheFile：真实 CacheManager（带 saveTime 的 put）路径

    func testCacheFileWithRealCacheManager() async throws {
        let server = try startServer(handlers: [
            "/js2": { _ in self.okBody("console.log(2)") }
        ])
        let target = url("/js2", server)
        let provider = makeProvider(cacheDirectory: makeTempDir(),
                                    cacheManager: CacheManager(storage: MemoryCacheStorage()))
        let first = try provider.invoke(method: "cacheFile", arguments: [target, "60"])
        XCTAssertEqual(first, "console.log(2)")
        let second = try provider.invoke(method: "cacheFile", arguments: [target, "60"])
        XCTAssertEqual(second, "console.log(2)")
        XCTAssertEqual(server.requests.count, 1)
    }

    // MARK: - 19. downloadFile：落盘字节与返回的相对路径

    func testDownloadFileWritesFileAndReturnsRelativePath() async throws {
        let payload = "download-body-中文"
        let server = try startServer(handlers: [
            "/d.js": { _ in self.okBody(payload) }
        ])
        let target = url("/d.js", server)
        let cacheDir = makeTempDir()
        let provider = makeProvider(cacheDirectory: cacheDir)
        let path = try provider.invoke(method: "downloadFile", arguments: [target])
        let md5 = JsExtensionsCore.md5Encode16(target)
        XCTAssertEqual(path, "/" + md5 + ".js")
        let data = try Data(contentsOf: cacheDir.appendingPathComponent(md5 + ".js"))
        XCTAssertEqual(String(decoding: data, as: UTF8.self), payload)
    }

    // MARK: - 20. downloadFile：大小与内容逐字节一致 + 无后缀 URL 落到 ".ext"

    func testDownloadFileContentSizeAndDefaultSuffix() async throws {
        var payload = ""
        for i in 0..<70000 { payload.append(Character(UnicodeScalar(UInt8(65 + (i % 26))))) }
        let server = try startServer(handlers: [
            "/big": { _ in
                LocalScriptedServer.Response(status: 200, reason: "OK",
                                             headers: [("Content-Type", "application/octet-stream")],
                                             body: Data(payload.utf8))
            }
        ])
        let target = url("/big", server)
        let cacheDir = makeTempDir()
        let provider = makeProvider(cacheDirectory: cacheDir)
        let path = try provider.invoke(method: "downloadFile", arguments: [target])
        let md5 = JsExtensionsCore.md5Encode16(target)
        XCTAssertEqual(path, "/" + md5 + ".ext", "无合法后缀（/big）→ UrlUtil.getSuffix 的 \"ext\"")
        let data = try Data(contentsOf: cacheDir.appendingPathComponent(md5 + ".ext"))
        XCTAssertEqual(data.count, payload.utf8.count)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), payload)
        XCTAssertEqual(server.requests.count, 1)
    }

    // MARK: - 21. 未实现的方法仍然抛 unsupported（Real provider / Unsupported provider / JS Proxy）

    func testUnsupportedMethodsStillThrow() throws {
        let provider = makeProvider()
        XCTAssertThrowsError(try provider.invoke(method: "unzipFile", arguments: ["x"])) { error in
            guard let ruleError = error as? RuleEngineError, case .unsupported = ruleError else {
                return XCTFail("应为 unsupported，实际 \(error)")
            }
        }
        // 默认 Unsupported 实现保持不变（既有定义未改动，回归）
        XCTAssertThrowsError(try UnsupportedJsNetworkExtensionsProvider().invoke(method: "get", arguments: ["http://x/"])) { error in
            guard let ruleError = error as? RuleEngineError, case .unsupported = ruleError else {
                return XCTFail("应为 unsupported，实际 \(error)")
            }
        }
        // JS Proxy：未实现方法调用抛 JS 错误
        let rule = makeRule(provider: provider, ajaxProvider: RealAjaxProvider(client: makeRealClient()))
        XCTAssertThrowsError(try rule.evalJS("java.unzipFile('x')"))
    }

    // MARK: - 22. java.get 单参仍是变量读取（重载决议回归）

    func testJavaGetOneArgStaysVariableGetter() throws {
        let rule = makeRule(provider: makeProvider(), ajaxProvider: RealAjaxProvider(client: makeRealClient()))
        let v = try rule.evalJS("java.put('k1','v1'); java.get('k1')")
        XCTAssertEqual(v.stringValue, "v1")
    }

    // MARK: - 23. java.ajax 全链路（AnalyzeRule.ajax → AjaxProvider）+ AnalyzeRule 默认 provider 接线

    func testAjaxViaAnalyzeRuleAndDefaultProviderWiring() async throws {
        let server = try startServer(handlers: [
            "/hello": { _ in self.okBody("via-js-ajax") }
        ])
        let rule = makeRule(provider: makeProvider(), ajaxProvider: RealAjaxProvider(client: makeRealClient()))
        let v = try rule.evalJS("java.ajax('\(url("/hello", server))')")
        XCTAssertEqual(v.stringValue, "via-js-ajax")

        // 默认 provider：真实实现（第 6 步 6B 起）；Unsupported 仍可显式注入覆盖。
        let defaultRule = AnalyzeRule()
        XCTAssertTrue(defaultRule.ajaxProviderValue is RealAjaxProvider)
        XCTAssertTrue(defaultRule.jsNetworkProviderValue is RealJsNetworkExtensionsProvider)
        let overridden = AnalyzeRule(ajaxProvider: UnsupportedAjaxProvider(),
                                     jsNetworkProvider: UnsupportedJsNetworkExtensionsProvider())
        XCTAssertTrue(overridden.ajaxProviderValue is UnsupportedAjaxProvider)
        XCTAssertTrue(overridden.jsNetworkProviderValue is UnsupportedJsNetworkExtensionsProvider)
    }
}
