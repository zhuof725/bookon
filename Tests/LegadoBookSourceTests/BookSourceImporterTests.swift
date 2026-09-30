//
//  BookSourceImporterTests.swift
//  LegadoBookSourceTests
//
//  验收测试：
//    1. 用 test_bookSources.json（4 个真实书源）做 decode → encode → decode，结果必须一致。
//    2. 前 3 个书源的规则字段是「JSON 字符串」形式，第 4 个是「对象」形式，两种都要测通过。
//    3. 宽松解码 property wrapper（Int/Int64/Bool/String）覆盖测试。
//    4. BookSourceImporter 逐条容错测试。
//

import XCTest
@testable import LegadoBookSource

final class BookSourceImporterTests: XCTestCase {

    // MARK: 载入测试资源

    func loadTestJSONData() throws -> Data {
        guard let url = Bundle.module.url(forResource: "test_bookSources", withExtension: "json") else {
            XCTFail("找不到 test_bookSources.json 资源")
            throw NSError(domain: "test", code: 1)
        }
        return try Data(contentsOf: url)
    }

    // MARK: 验收 1 + 2：decode → encode → decode 一致性（含字符串 / 对象两种规则形式）

    func testRoundTripConsistency() throws {
        let data = try loadTestJSONData()

        // 第一次导入
        let result1 = try BookSourceImporter.importSources(fromData: data)
        XCTAssertTrue(result1.failures.isEmpty,
                      "第一次导入不应有失败：\(result1.failures.map { $0.reason })")
        XCTAssertEqual(result1.successes.count, 6, "应成功导入 6 个书源")

        // encode
        let encoded = try LegadoJSON.encoder.encode(result1.successes)

        // 第二次导入（decode encode 后的结果）
        let result2 = try BookSourceImporter.importSources(fromData: encoded)
        XCTAssertTrue(result2.failures.isEmpty,
                      "第二次导入不应有失败：\(result2.failures.map { $0.reason })")
        XCTAssertEqual(result2.successes.count, 6)

        // 逐个书源比对 decode → encode → decode 的一致性
        for i in 0..<6 {
            let a = result1.successes[i]
            let b = result2.successes[i]
            assertBookSourceEqual(a, b, index: i)
        }
    }

    // MARK: 验收 2：确认前 3 个是字符串形式、第 4 个是对象形式，且都解出了规则

    func testMixedRuleFormsDecodeCorrectly() throws {
        let data = try loadTestJSONData()

        // 原始 JSON 里各书源 ruleSearch 的类型（字符串 or 对象）
        let raw = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]
        XCTAssertTrue(raw[0]["ruleSearch"] is String, "书源0 ruleSearch 应为 JSON 字符串形式")
        XCTAssertTrue(raw[1]["ruleSearch"] is String, "书源1 ruleSearch 应为 JSON 字符串形式")
        XCTAssertTrue(raw[2]["ruleSearch"] is String, "书源2 ruleSearch 应为 JSON 字符串形式")
        XCTAssertTrue(raw[3]["ruleSearch"] is [String: Any], "书源3 ruleSearch 应为对象形式")
        XCTAssertTrue(raw[4]["ruleReview"] is [String: Any], "书源4 ruleReview 应为对象形式")
        XCTAssertTrue(raw[5]["ruleReview"] is String, "书源5 ruleReview 应为 JSON 字符串形式")

        let result = try BookSourceImporter.importSources(fromData: data)
        let sources = result.successes

        // 书源0（🔥小说2016，字符串形式）：ruleSearch 里的字段应被正确解出
        let s0 = sources[0]
        XCTAssertEqual(s0.bookSourceName, "🔥小说2016")
        XCTAssertEqual(s0.ruleSearch?.author, "@css:p:eq(2)>a@text")
        XCTAssertEqual(s0.ruleSearch?.bookList, "@css:li.clearfix")
        XCTAssertEqual(s0.ruleSearch?.name, "@css:.name@text")
        XCTAssertEqual(s0.ruleBookInfo?.name, "##:book_name\"[^\"]+\"([^\"]*)##$1###")
        XCTAssertEqual(s0.ruleToc?.chapterName, "$2")
        XCTAssertNotNil(s0.ruleContent?.content)
        // ruleExplore 是 "{}"（空对象字符串），应解出一个所有字段为 nil 的 ExploreRule
        XCTAssertNotNil(s0.ruleExplore)
        XCTAssertNil(s0.ruleExplore?.bookList)

        // 书源1（采墨阁，字符串形式，XPath）
        let s1 = sources[1]
        XCTAssertEqual(s1.bookSourceName, "🔥采墨阁手机版")
        XCTAssertEqual(s1.ruleSearch?.bookList, "//*[@id=\"sitebox\"]/dl")
        XCTAssertEqual(s1.ruleBookInfo?.tocUrl, "//a[text()=\"阅读\"]/@href")

        // 书源2（猎鹰小说网，字符串形式，JSON path）
        let s2 = sources[2]
        XCTAssertEqual(s2.bookSourceName, "猎鹰小说网")
        XCTAssertEqual(s2.ruleSearch?.author, "$.author")
        XCTAssertEqual(s2.ruleContent?.content, "$.chapter.body")

        // 书源3（消消乐听书，对象形式）
        let s3 = sources[3]
        XCTAssertEqual(s3.bookSourceName, "消消乐听书")
        XCTAssertEqual(s3.bookSourceType, 1)
        XCTAssertEqual(s3.ruleSearch?.author, "$.author")
        XCTAssertEqual(s3.ruleSearch?.bookList, "$.content.content")
        XCTAssertEqual(s3.ruleToc?.chapterName, "$.chapterTitle")
        XCTAssertNotNil(s3.ruleContent?.payAction)
    }

    // MARK: 验收：编码后规则字段统一为对象形式（而非 JSON 字符串）

    func testRulesEncodeAsObject() throws {
        let data = try loadTestJSONData()
        let result = try BookSourceImporter.importSources(fromData: data)
        let encoded = try LegadoJSON.encoder.encode(result.successes)
        let reparsed = try JSONSerialization.jsonObject(with: encoded) as! [[String: Any]]

        for (i, obj) in reparsed.enumerated() {
            if let rs = obj["ruleSearch"] {
                XCTAssertTrue(rs is [String: Any],
                              "编码后书源\(i) 的 ruleSearch 应为对象，而非字符串")
            }
        }
    }

    // MARK: 验收 3：ruleReview 对象形式与字符串形式，各字段 decode/encode 一致

    func testReviewRuleBothForms() throws {
        let data = try loadTestJSONData()
        let result = try BookSourceImporter.importSources(fromData: data)
        XCTAssertTrue(result.failures.isEmpty)
        let sources = result.successes

        // 书源4：对象形式；书源5：字符串形式。两者内容一致，应解出相等的 ReviewRule。
        let objForm = sources[4]
        let strForm = sources[5]
        XCTAssertEqual(objForm.bookSourceName, "段评测试-对象")
        XCTAssertEqual(strForm.bookSourceName, "段评测试-字符串")

        let ro = try XCTUnwrap(objForm.ruleReview, "对象形式应解出 ruleReview")
        let rs = try XCTUnwrap(strForm.ruleReview, "字符串形式应解出 ruleReview")

        // 逐字段断言（对象形式）
        XCTAssertEqual(ro.reviewUrl, "/review?bookUrl={{bookUrl}}&chapterIndex={{chapterIndex}}")
        XCTAssertEqual(ro.avatarRule, "$.data.list[*].avatar")
        XCTAssertEqual(ro.contentRule, "$.data.list[*].content")
        XCTAssertEqual(ro.postTimeRule, "$.data.list[*].createTime")
        XCTAssertEqual(ro.reviewQuoteUrl, "/reviewQuote?id={$.id}")
        XCTAssertEqual(ro.voteUpUrl, "/voteUp?id={$.id}")
        XCTAssertEqual(ro.voteDownUrl, "/voteDown?id={$.id}")
        XCTAssertEqual(ro.postReviewUrl, "/postReview,{\"method\":\"POST\",\"body\":\"content={{content}}\"}")
        XCTAssertEqual(ro.postQuoteUrl, "/postQuote,{\"method\":\"POST\",\"body\":\"content={{content}}\"}")
        XCTAssertEqual(ro.deleteUrl, "/deleteReview?id={$.id}")

        // 两种形式解出的 ReviewRule 应完全相等
        XCTAssertEqual(ro, rs, "对象形式与字符串形式解出的 ReviewRule 应一致")

        // decode → encode → decode 后 ReviewRule 仍一致
        let encoded = try LegadoJSON.encoder.encode(sources)
        let result2 = try BookSourceImporter.importSources(fromData: encoded)
        XCTAssertEqual(result2.successes[4].ruleReview, ro)
        XCTAssertEqual(result2.successes[5].ruleReview, rs)

        // 编码后两者的 ruleReview 都应为对象形式（统一输出对象）
        let reparsed = try JSONSerialization.jsonObject(with: encoded) as! [[String: Any]]
        XCTAssertTrue(reparsed[4]["ruleReview"] is [String: Any], "编码后书源4 ruleReview 应为对象")
        XCTAssertTrue(reparsed[5]["ruleReview"] is [String: Any], "编码后书源5 ruleReview 应为对象")
    }

    // MARK: 内层 JSON 字符串解析失败 -> 置 nil 且记录 warning

    func testMalformedRuleStringProducesWarningNotError() throws {
        // ruleSearch 是一个语法错误的 JSON 字符串（缺右括号）。
        let json = #"""
        {
          "bookSourceUrl": "https://warn.example.com",
          "bookSourceName": "警告测试",
          "ruleSearch": "{ \"name\": \"$.name\" "
        }
        """#
        let result = try BookSourceImporter.importSources(fromJSONString: json)
        // 书源整体应导入成功（容错），只是 ruleSearch 被置空。
        XCTAssertEqual(result.successes.count, 1, "坏规则不应导致整条书源失败")
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertNil(result.successes.first?.ruleSearch, "解析失败的规则字段应被置空")
        // 应记录一条警告
        XCTAssertFalse(result.warnings.isEmpty, "应记录内层解析失败的警告")
        let w = try XCTUnwrap(result.warnings.first)
        XCTAssertEqual(w.field, "ruleSearch", "警告应指明是 ruleSearch 字段")
        XCTAssertTrue(w.message.contains("内层解析失败") || w.message.contains("置空"),
                      "警告信息应说明字段被置空：\(w.message)")
    }

    // MARK: 问题2c-情况1：值是「字符串」但内层二次解析失败 -> 警告(内层解析失败) + 书源仍成功

    func testRuleStringInnerParseFailureWarning() throws {
        // ruleSearch 是字符串但内层 JSON 语法错误；同一书源其它规则(ruleContent)为合法对象。
        let json = #"""
        {
          "bookSourceUrl": "https://case-string.example.com",
          "bookSourceName": "字符串内层失败",
          "ruleSearch": "{ \"name\": \"$.name\" ",
          "ruleContent": { "content": "$.body" }
        }
        """#
        let result = try BookSourceImporter.importSources(fromJSONString: json)
        XCTAssertEqual(result.successes.count, 1, "书源本身应成功导入")
        XCTAssertTrue(result.failures.isEmpty)
        let src = try XCTUnwrap(result.successes.first)
        XCTAssertNil(src.ruleSearch, "解析失败的 ruleSearch 应置空")
        XCTAssertEqual(src.ruleContent?.content, "$.body", "其它规则不受影响")

        let w = try XCTUnwrap(result.warnings.first(where: { $0.field == "ruleSearch" }))
        XCTAssertTrue(w.message.contains("(JSON 字符串)内层解析失败"),
                      "字符串分支应报『内层解析失败』：\(w.message)")
    }

    // MARK: 问题2c-情况2：值是「对象」但解码失败 -> 警告(是对象但解码失败) + 书源仍成功
    //
    // 说明：本移植所有规则字段都用宽松 wrapper，正常对象几乎不会解码失败。
    // 为可靠触发「对象解码失败」，用一个自定义严格类型 + StringOrObject 单独构造场景。

    private struct StrictRule: Codable, Equatable {
        let requiredInt: Int   // 非宽松，缺失/类型不符会抛错
    }

    private struct StrictHolder: Codable {
        @StringOrObject<StrictRule> var rule: StrictRule?
    }

    func testRuleObjectDecodeFailureWarning() throws {
        // rule 是对象，但缺少必需字段 requiredInt -> 对象解码应失败。
        let json = #"{ "rule": { "somethingElse": 1 } }"#
        let collector = DecodingWarningCollector()
        let decoder = LegadoJSON.decoder(collectingWarningsInto: collector)
        let holder = try decoder.decode(StrictHolder.self, from: Data(json.utf8))
        XCTAssertNil(holder.rule, "对象解码失败后应置空")
        let w = try XCTUnwrap(collector.warnings.first)
        XCTAssertTrue(w.message.contains("是对象但解码失败"),
                      "对象分支应报『是对象但解码失败』：\(w.message)")
    }

    // MARK: 问题2c-情况3：值既不是对象也不是字符串（数字/数组/布尔）-> 保持原有警告

    func testRuleNeitherObjectNorStringWarning() throws {
        // ruleSearch 写成数字；ruleToc 写成数组；ruleContent 是合法对象(不受影响)。
        let json = #"""
        {
          "bookSourceUrl": "https://case-neither.example.com",
          "bookSourceName": "既非对象也非字符串",
          "ruleSearch": 12345,
          "ruleToc": [1, 2, 3],
          "ruleContent": { "content": "$.body" }
        }
        """#
        let result = try BookSourceImporter.importSources(fromJSONString: json)
        XCTAssertEqual(result.successes.count, 1, "书源本身应成功导入")
        XCTAssertTrue(result.failures.isEmpty)
        let src = try XCTUnwrap(result.successes.first)
        XCTAssertNil(src.ruleSearch)
        XCTAssertNil(src.ruleToc)
        XCTAssertEqual(src.ruleContent?.content, "$.body", "其它规则不受影响")

        let wSearch = try XCTUnwrap(result.warnings.first(where: { $0.field == "ruleSearch" }))
        XCTAssertTrue(wSearch.message.contains("既不是对象也不是字符串"),
                      "数字应报『既不是对象也不是字符串』：\(wSearch.message)")
        let wToc = try XCTUnwrap(result.warnings.first(where: { $0.field == "ruleToc" }))
        XCTAssertTrue(wToc.message.contains("既不是对象也不是字符串"),
                      "数组应报『既不是对象也不是字符串』：\(wToc.message)")
    }

    // MARK: 问题2b：字符串二次解析复用同一 collector，内层更深一层的警告不丢失
    //
    // 构造：外层 holder 里有一个 StringOrObject<Nested>，值是「JSON 字符串」；
    // 该字符串内层又有一个 StringOrObject<StrictRule>，其值是「对象但解码失败」。
    // 期望：内层这条警告能被外层同一个 collector 收集到。

    private struct Nested: Codable {
        @StringOrObject<StrictRule> var inner: StrictRule?
    }
    private struct OuterHolder: Codable {
        @StringOrObject<Nested> var outer: Nested?
    }

    func testNestedStringWarningPropagatesToSameCollector() throws {
        // outer 是字符串；其内容里的 inner 是对象但缺必需字段。
        let innerJSON = #"{ "inner": { "wrong": 1 } }"#
        // 把 innerJSON 作为字符串放进 outer
        let outerObject: [String: Any] = ["outer": innerJSON]
        let data = try JSONSerialization.data(withJSONObject: outerObject)

        let collector = DecodingWarningCollector()
        let decoder = LegadoJSON.decoder(collectingWarningsInto: collector)
        let holder = try decoder.decode(OuterHolder.self, from: data)
        // inner 解码失败 -> nil；outer 因此得到一个 inner=nil 的 Nested（外层解析本身成功）
        XCTAssertNotNil(holder.outer)
        XCTAssertNil(holder.outer?.inner)
        // 内层「是对象但解码失败」这条警告应出现在同一个 collector 中
        XCTAssertTrue(collector.warnings.contains(where: { $0.message.contains("是对象但解码失败") }),
                      "内层警告应传播到外层同一 collector：\(collector.warnings.map { $0.message })")
    }

    // MARK: 正常导入不产生警告

    func testCleanImportHasNoWarnings() throws {
        let data = try loadTestJSONData()
        let result = try BookSourceImporter.importSources(fromData: data)
        XCTAssertTrue(result.warnings.isEmpty, "合法书源导入不应产生警告：\(result.warnings)")
    }

    // MARK: 宽松解码：Int / Int64 / Bool / String 类型不统一时的容错

    func testLenientScalarDecoding() throws {
        // 数字写成字符串、布尔写成 0/1、字符串写成数字
        let json = """
        {
          "bookSourceUrl": "https://example.com",
          "bookSourceName": 12345,
          "bookSourceType": "1",
          "customOrder": "7",
          "enabled": 0,
          "enabledExplore": 1,
          "respondTime": "5000",
          "lastUpdateTime": 1630656684531,
          "weight": "3"
        }
        """
        let src = try LegadoJSON.decoder.decode(BookSource.self, from: Data(json.utf8))
        XCTAssertEqual(src.bookSourceName, "12345", "数字应被宽松解码为字符串")
        XCTAssertEqual(src.bookSourceType, 1, "字符串 \"1\" 应被解码为 Int 1")
        XCTAssertEqual(src.customOrder, 7)
        XCTAssertEqual(src.enabled, false, "0 应解码为 false")
        XCTAssertEqual(src.enabledExplore, true, "1 应解码为 true")
        XCTAssertEqual(src.respondTime, 5000, "字符串 \"5000\" 应解码为 Int64")
        XCTAssertEqual(src.weight, 3)
    }

    // MARK: 缺字段用默认值，不报错

    func testMissingFieldsUseDefaults() throws {
        let json = #"{"bookSourceUrl": "https://a.com", "bookSourceName": "A"}"#
        let src = try LegadoJSON.decoder.decode(BookSource.self, from: Data(json.utf8))
        XCTAssertEqual(src.bookSourceType, 0)
        XCTAssertEqual(src.customOrder, 0)
        XCTAssertEqual(src.enabled, true)
        XCTAssertEqual(src.enabledExplore, true)
        XCTAssertEqual(src.respondTime, 180000)
        XCTAssertEqual(src.eventListener, false)
        XCTAssertEqual(src.customButton, false)
        XCTAssertNil(src.ruleSearch)
        XCTAssertNil(src.bookSourceGroup)
    }

    // MARK: 导入器逐条容错：坏书源不影响好书源

    func testImporterPartialFailureIsolation() throws {
        // 第 2 个元素不是对象（是数字），应被隔离为失败，其余成功。
        let json = """
        [
          {"bookSourceUrl": "https://a.com", "bookSourceName": "A"},
          12345,
          {"bookSourceUrl": "https://c.com", "bookSourceName": "C"}
        ]
        """
        let result = try BookSourceImporter.importSources(fromJSONString: json)
        XCTAssertEqual(result.successes.count, 2, "两个合法书源应成功")
        XCTAssertEqual(result.failures.count, 1, "一个非法书源应记录为失败")
        XCTAssertEqual(result.failures.first?.index, 1)
    }

    // MARK: 单个书源对象输入

    func testImportSingleObject() throws {
        let json = #"{"bookSourceUrl": "https://a.com", "bookSourceName": "A"}"#
        let result = try BookSourceImporter.importSources(fromJSONString: json)
        XCTAssertEqual(result.successes.count, 1)
        XCTAssertTrue(result.failures.isEmpty)
        XCTAssertEqual(result.successes.first?.bookSourceName, "A")
    }

    // MARK: 辅助：逐字段比较两个 BookSource（用于 round-trip 一致性）

    private func assertBookSourceEqual(_ a: BookSource, _ b: BookSource, index: Int,
                                       file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.bookSourceUrl, b.bookSourceUrl, "书源\(index) bookSourceUrl", file: file, line: line)
        XCTAssertEqual(a.bookSourceName, b.bookSourceName, "书源\(index) bookSourceName", file: file, line: line)
        XCTAssertEqual(a.bookSourceGroup, b.bookSourceGroup, "书源\(index) bookSourceGroup", file: file, line: line)
        XCTAssertEqual(a.bookSourceType, b.bookSourceType, "书源\(index) bookSourceType", file: file, line: line)
        XCTAssertEqual(a.bookUrlPattern, b.bookUrlPattern, "书源\(index) bookUrlPattern", file: file, line: line)
        XCTAssertEqual(a.customOrder, b.customOrder, "书源\(index) customOrder", file: file, line: line)
        XCTAssertEqual(a.enabled, b.enabled, "书源\(index) enabled", file: file, line: line)
        XCTAssertEqual(a.enabledExplore, b.enabledExplore, "书源\(index) enabledExplore", file: file, line: line)
        XCTAssertEqual(a.jsLib, b.jsLib, "书源\(index) jsLib", file: file, line: line)
        XCTAssertEqual(a.enabledCookieJar, b.enabledCookieJar, "书源\(index) enabledCookieJar", file: file, line: line)
        XCTAssertEqual(a.concurrentRate, b.concurrentRate, "书源\(index) concurrentRate", file: file, line: line)
        XCTAssertEqual(a.header, b.header, "书源\(index) header", file: file, line: line)
        XCTAssertEqual(a.loginUrl, b.loginUrl, "书源\(index) loginUrl", file: file, line: line)
        XCTAssertEqual(a.loginUi, b.loginUi, "书源\(index) loginUi", file: file, line: line)
        XCTAssertEqual(a.loginCheckJs, b.loginCheckJs, "书源\(index) loginCheckJs", file: file, line: line)
        XCTAssertEqual(a.coverDecodeJs, b.coverDecodeJs, "书源\(index) coverDecodeJs", file: file, line: line)
        XCTAssertEqual(a.bookSourceComment, b.bookSourceComment, "书源\(index) bookSourceComment", file: file, line: line)
        XCTAssertEqual(a.variableComment, b.variableComment, "书源\(index) variableComment", file: file, line: line)
        XCTAssertEqual(a.lastUpdateTime, b.lastUpdateTime, "书源\(index) lastUpdateTime", file: file, line: line)
        XCTAssertEqual(a.respondTime, b.respondTime, "书源\(index) respondTime", file: file, line: line)
        XCTAssertEqual(a.weight, b.weight, "书源\(index) weight", file: file, line: line)
        XCTAssertEqual(a.exploreUrl, b.exploreUrl, "书源\(index) exploreUrl", file: file, line: line)
        XCTAssertEqual(a.exploreScreen, b.exploreScreen, "书源\(index) exploreScreen", file: file, line: line)
        XCTAssertEqual(a.searchUrl, b.searchUrl, "书源\(index) searchUrl", file: file, line: line)
        XCTAssertEqual(a.eventListener, b.eventListener, "书源\(index) eventListener", file: file, line: line)
        XCTAssertEqual(a.customButton, b.customButton, "书源\(index) customButton", file: file, line: line)
        // 规则字段
        XCTAssertEqual(a.ruleSearch, b.ruleSearch, "书源\(index) ruleSearch", file: file, line: line)
        XCTAssertEqual(a.ruleExplore, b.ruleExplore, "书源\(index) ruleExplore", file: file, line: line)
        XCTAssertEqual(a.ruleBookInfo, b.ruleBookInfo, "书源\(index) ruleBookInfo", file: file, line: line)
        XCTAssertEqual(a.ruleToc, b.ruleToc, "书源\(index) ruleToc", file: file, line: line)
        XCTAssertEqual(a.ruleContent, b.ruleContent, "书源\(index) ruleContent", file: file, line: line)
        XCTAssertEqual(a.ruleReview, b.ruleReview, "书源\(index) ruleReview", file: file, line: line)
    }
}
