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
        XCTAssertEqual(result1.successes.count, 4, "应成功导入 4 个书源")

        // encode
        let encoded = try LegadoJSON.encoder.encode(result1.successes)

        // 第二次导入（decode encode 后的结果）
        let result2 = try BookSourceImporter.importSources(fromData: encoded)
        XCTAssertTrue(result2.failures.isEmpty,
                      "第二次导入不应有失败：\(result2.failures.map { $0.reason })")
        XCTAssertEqual(result2.successes.count, 4)

        // 逐个书源比对 decode → encode → decode 的一致性
        for i in 0..<4 {
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
