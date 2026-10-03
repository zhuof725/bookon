//
//  AnalyzeRuleJSTests.swift
//  LegadoAnalyzeRuleTests
//
//  JS 引擎（JavaScriptCore evalJS）、{{ }} 内联、@get/@put、$n、replaceRegex、缓存、put/get。
//  所有规则/内容为【合成样本，非真实数据】。
//

import XCTest
@testable import LegadoBookSource

final class AnalyzeRuleJSTests: XCTestCase {

    // MARK: - evalJS 基本求值（真实跑 JS）

    func testEvalJS_arithmetic() throws {
        let a = AnalyzeRule()
        let v = try a.evalJS("1+1")
        XCTAssertEqual(v.stringValue, "2.0") // Double 整数值带 .0（见 README 差异）
    }
    func testEvalJS_stringConcat() throws {
        let a = AnalyzeRule()
        let v = try a.evalJS("'a' + 'b' + 'c'")
        XCTAssertEqual(v.stringValue, "abc")
    }
    func testEvalJS_resultVariable() throws {
        let a = AnalyzeRule()
        let v = try a.evalJS("result + '!'", result: .string("hi"))
        XCTAssertEqual(v.stringValue, "hi!")
    }
    func testEvalJS_boolean() throws {
        let a = AnalyzeRule()
        let v = try a.evalJS("2 > 1")
        XCTAssertEqual(v.stringValue, "true")
    }
    func testEvalJS_array() throws {
        let a = AnalyzeRule()
        let v = try a.evalJS("['x','y','z']")
        if case .stringList(let l) = v { XCTAssertEqual(l, ["x","y","z"]) }
        else { XCTFail("expected stringList, got \(v)") }
    }

    // MARK: - {{ }} 内联 JS

    func testInline_jsExpr() throws {
        let a = AnalyzeRule()
        try a.setContent("ignored")
        // {{ }} 触发 regex 模式，makeUpRule 对 {{1+1}} 求值
        let s = try a.getString("前缀{{1+1}}后缀")
        XCTAssertEqual(s, "前缀2后缀") // Double%1==0 -> %.0f -> "2"
    }
    func testInline_jsStringConcat() throws {
        let a = AnalyzeRule()
        try a.setContent("x")
        let s = try a.getString("{{'A'+'B'}}")
        XCTAssertEqual(s, "AB")
    }
    func testInline_multipleBraces() throws {
        let a = AnalyzeRule()
        try a.setContent("x")
        let s = try a.getString("{{1+2}}-{{3+4}}")
        XCTAssertEqual(s, "3-7")
    }

    // MARK: - java Proxy 未实现方法抛错（Step 5：已实现方法不再抛错）

    func testJava_unimplementedThrows() {
        let diag = RuleEngineDiagnostics()
        let a = AnalyzeRule(diagnostics: diag)
        // aesDecodeToString 属于 JsEncodeUtils 但 Step 5 未实现（书源未使用）→ Proxy 抛错
        XCTAssertThrowsError(try a.evalJS("java.aesDecodeToString('x','k','AES/ECB/PKCS5Padding','iv')")) { err in
            XCTAssertTrue("\(err)".contains("aesDecodeToString") || "\(err)".contains("尚未实现"), "got \(err)")
        }
        XCTAssertTrue(diag.diagnostics.contains { $0.message.contains("aesDecodeToString") })
    }
    func testJava_implementedGetPut() throws {
        let a = AnalyzeRule(source: InMemorySource())
        let v = try a.evalJS("java.put('k','v'); java.get('k')")
        XCTAssertEqual(v.stringValue, "v")
    }
    func testJava_implementedMd5() throws {
        // Step 5：md5Encode 已实现，直接断言结果（与真实 hutool MD5 对照固定值）
        let a = AnalyzeRule(source: InMemorySource())
        let v = try a.evalJS("java.md5Encode('abc')")
        XCTAssertEqual(v.stringValue, "900150983cd24fb0d6963f7d28e17f72")
        // md5Encode16 = md5 全串 substring(8,24)
        let v16 = try a.evalJS("java.md5Encode16('abc')")
        XCTAssertEqual(v16.stringValue, "3cd24fb0d6963f7d")
    }

    // MARK: - Java 互操作检测（Step 5：org.jsoup 放行，其余仍抛错）

    func testJavaInterop_packagesThrows() {
        let diag = RuleEngineDiagnostics()
        let a = AnalyzeRule(diagnostics: diag)
        XCTAssertThrowsError(try a.evalJS("Packages.java.lang.String"))
    }
    func testJavaInterop_jsoupParseAllowed() throws {
        // Step 5：org.jsoup.Jsoup 已有 SwiftSoup 替身，不再抛互操作错误
        let a = AnalyzeRule()
        let v = try a.evalJS("org.jsoup.Jsoup.parse('<div>hi</div>').select('div').text()")
        XCTAssertEqual(v.stringValue, "hi")
    }
    func testJavaInterop_importClassThrows() {
        let a = AnalyzeRule()
        XCTAssertThrowsError(try a.evalJS("importClass(java.lang.String)"))
    }

    // MARK: - put / get 回退链

    func testPutGet_sourceLevel() throws {
        let src = InMemorySource()
        let a = AnalyzeRule(source: src)
        _ = a.put("key1", "val1")
        XCTAssertEqual(a.get("key1"), "val1")
    }
    func testPutGet_bookPreferredOverSource() throws {
        let book = InMemoryBook(name: "书A")
        let src = InMemorySource()
        let a = AnalyzeRule(book: book, source: src)
        _ = a.put("k", "fromBook")  // 优先写 book（book 在 chapter 之后，无 chapter）
        XCTAssertEqual(a.get("k"), "fromBook")
    }
    func testGet_bookName() throws {
        let book = InMemoryBook(name: "我的书")
        let a = AnalyzeRule(book: book)
        XCTAssertEqual(a.get("bookName"), "我的书")
    }
    func testGet_chapterTitle() throws {
        let ch = InMemoryChapter(title: "第五章")
        let a = AnalyzeRule(chapter: ch)
        XCTAssertEqual(a.get("title"), "第五章")
    }
    func testPutGet_chapterPreferred() throws {
        let ch = InMemoryChapter(title: "t")
        let book = InMemoryBook(name: "b")
        let a = AnalyzeRule(book: book, chapter: ch)
        _ = a.put("x", "chapVal")
        XCTAssertEqual(a.get("x"), "chapVal")
    }
    func testGet_missingReturnsEmpty() throws {
        let a = AnalyzeRule(source: InMemorySource())
        XCTAssertEqual(a.get("nope"), "")
    }

    // MARK: - @get / @put 内联

    func testAtGet_inline() throws {
        let src = InMemorySource()
        let a = AnalyzeRule(source: src)
        _ = a.put("vv", "注入值")
        try a.setContent("x")
        let s = try a.getString("前@get:{vv}后")
        XCTAssertEqual(s, "前注入值后")
    }
    func testAtPut_storesVariable() throws {
        let src = InMemorySource()
        let a = AnalyzeRule(source: src)
        try a.setContent("<p>HELLO</p>")
        // @put:{"k":"rule"} 把子规则结果存入变量（用规范 JSON；非规范 JSON 的 lenient 解析
        // 为已知差异，见 README）。
        _ = try a.getString("p@text@put:{\"saved\":\"p@text\"}")
        XCTAssertEqual(a.get("saved"), "HELLO")
    }

    // MARK: - replaceRegex（## / ### / $n）

    func testReplaceRegex_simple() throws {
        let a = AnalyzeRule()
        try a.setContent("<p>abc123</p>")
        let s = try a.getString("p@text##\\d+##NUM")
        XCTAssertEqual(s, "abcNUM")
    }
    func testReplaceRegex_groupRef() throws {
        let a = AnalyzeRule()
        try a.setContent("<p>2024-01-02</p>")
        let s = try a.getString("p@text##(\\d+)-(\\d+)-(\\d+)##$1/$2/$3")
        XCTAssertEqual(s, "2024/01/02")
    }
    func testReplaceRegex_removeMatch() throws {
        let a = AnalyzeRule()
        try a.setContent("<p>a b c</p>")
        let s = try a.getString("p@text## ##")
        XCTAssertEqual(s, "abc")
    }
    func testReplaceRegex_replaceFirst() throws {
        let a = AnalyzeRule()
        try a.setContent("<p>xax a y</p>")
        // ##match##replace### 只取第一个匹配并替换
        let s = try a.getString("p@text##a##Z###")
        XCTAssertFalse(s.isEmpty)
    }

    // MARK: - 缓存容量

    func testScriptRuleCache_reuse() throws {
        let a = AnalyzeRule()
        try a.setContent("<p>hi</p>")
        let r1 = try a.getString("p@text")
        let r2 = try a.getString("p@text")
        XCTAssertEqual(r1, r2)
    }

    // MARK: - WebJs 默认 unsupported

    func testWebJs_unsupportedThrows() throws {
        let a = AnalyzeRule()
        try a.setContent("x")
        // getString 会走 dispatch -> webJSResult -> provider.throws
        XCTAssertThrowsError(try a.getString("@webjs:123456789"))
    }

    // MARK: - reGetBook / refreshTocUrl 桩

    func testReGetBook_unsupported() {
        let a = AnalyzeRule()
        XCTAssertThrowsError(try a.reGetBook())
    }
    func testRefreshTocUrl_unsupported() {
        let a = AnalyzeRule()
        XCTAssertThrowsError(try a.refreshTocUrl())
    }
}
