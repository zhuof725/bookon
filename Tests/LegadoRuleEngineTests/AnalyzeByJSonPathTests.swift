//
//  AnalyzeByJSonPathTests.swift
//  LegadoRuleEngineTests
//
//  AnalyzeByJSonPath 单元测试（@testable）。≥20 用例。
//
//  样本来源标注：
//   - synthetic_lieying_like.json：⚠️ 合成样本（非真实数据），结构参考猎鹰小说网规则。
//   - Resources/real/muli_real_source.json：真实书源（🍅木里番茄），来源：用户提供。
//   - 各内联 JSON：⚠️ 合成样本，仅覆盖具体分支。
//

import XCTest
@testable import LegadoBookSource

final class AnalyzeByJSonPathTests: XCTestCase {

    private func loadResource(_ name: String, subdir: String? = nil) throws -> String {
        // 依次尝试：带子目录 -> 不带子目录 -> 遍历 bundle 资源目录查找同名文件。
        var url: URL? = nil
        if let subdir = subdir {
            url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: subdir)
        }
        if url == nil {
            url = Bundle.module.url(forResource: name, withExtension: "json")
        }
        if url == nil, let resourceURL = Bundle.module.resourceURL {
            // 递归查找（Linux 与 macOS 的资源拷贝目录结构可能不同）。
            if let en = FileManager.default.enumerator(at: resourceURL, includingPropertiesForKeys: nil) {
                for case let f as URL in en where f.lastPathComponent == "\(name).json" {
                    url = f; break
                }
            }
        }
        guard let u = url else { XCTFail("找不到资源 \(name)"); throw NSError(domain: "t", code: 1) }
        return try String(contentsOf: u, encoding: .utf8)
    }

    // ============ 一、猎鹰小说网规则（合成样本） ============

    // 1. bookList "$..books[*]"：递归下降 + 通配，返回列表
    func testLieyingBookListRecursiveWildcard() throws {
        let json = try loadResource("synthetic_lieying_like")
        let a = AnalyzeByJSonPath(json)
        let list = a.getList("$..books[*]")
        XCTAssertEqual(list?.count, 2)
    }
    // 2. 对每本书取 $.title（在单本对象上）
    func testLieyingBookTitle() throws {
        let json = try loadResource("synthetic_lieying_like")
        let a = AnalyzeByJSonPath(json)
        let list = a.getList("$..books[*]")!
        let first = AnalyzeByJSonPath(list[0])
        XCTAssertEqual(first.getString("$.title"), "书一")
        XCTAssertEqual(first.getString("$.author"), "作者一")
    }
    // 3. bookUrl 内嵌规则 "/Book/getChapterListByBookId?bookId={$._id}"
    func testLieyingBookUrlInnerRule() throws {
        let json = try loadResource("synthetic_lieying_like")
        let list = AnalyzeByJSonPath(json).getList("$..books[*]")!
        let first = AnalyzeByJSonPath(list[0])
        let url = first.getString("/Book/getChapterListByBookId?bookId={$._id}")
        XCTAssertEqual(url, "/Book/getChapterListByBookId?bookId=b001")
    }
    // 4. chapterList "$.chapterInfo.chapters.[*]"（.[*] 点后方括号）
    func testLieyingChapterListDotBracket() throws {
        let json = try loadResource("synthetic_lieying_like")
        let toc = try AnalyzeByJSonPath(json).getObject("$.toc")
        let a = AnalyzeByJSonPath(toc)
        let chapters = a.getList("$.chapterInfo.chapters.[*]")
        XCTAssertEqual(chapters?.count, 3)
    }
    // 5. chapterName / chapterUrl 从单章对象取
    func testLieyingChapterFields() throws {
        let json = try loadResource("synthetic_lieying_like")
        let toc = try AnalyzeByJSonPath(json).getObject("$.toc")
        let chapters = AnalyzeByJSonPath(toc).getList("$.chapterInfo.chapters.[*]")!
        let c0 = AnalyzeByJSonPath(chapters[0])
        XCTAssertEqual(c0.getString("$.title"), "第一章")
        XCTAssertEqual(c0.getString("$.link"), "/read/1")
    }
    // 6. content "$.chapter.body"
    func testLieyingContentBody() throws {
        let json = try loadResource("synthetic_lieying_like")
        let content = try AnalyzeByJSonPath(json).getObject("$.content")
        let body = AnalyzeByJSonPath(content).getString("$.chapter.body")
        XCTAssertEqual(body, "正文内容第一段\n正文内容第二段")
    }

    // ============ 二、|| 短路 / && 拼接 / %% 交错 ============

    // 7. || 短路：第一个非空即返回
    func testOrShortCircuit() {
        let json = #"{ "author": "甲", "copyright": "乙" }"#
        let a = AnalyzeByJSonPath(json)
        XCTAssertEqual(a.getString("$.author||$.copyright"), "甲")
    }
    // 8. || 短路：第一个缺失/空，取下一个
    func testOrFallback() {
        let json = #"{ "copyright": "乙", "anchor": "丙" }"#
        let a = AnalyzeByJSonPath(json)
        // $.author 不存在 -> "" -> 跳过；$.copyright -> "乙"
        XCTAssertEqual(a.getString("$.author||$.copyright||$.anchor"), "乙")
    }
    // 9. || 全缺失 -> 空串
    func testOrAllMissing() {
        let json = #"{ "x": 1 }"#
        let a = AnalyzeByJSonPath(json)
        XCTAssertEqual(a.getString("$.author||$.copyright"), "")
    }
    // 10. && 拼接：用 "\n" 连接多个结果
    func testAndJoin() {
        let json = #"{ "a": "1", "b": "2" }"#
        let a = AnalyzeByJSonPath(json)
        XCTAssertEqual(a.getString("$.a&&$.b"), "1\n2")
    }
    // 11. getStringList && 拼接：addAll
    func testStringListAnd() {
        let json = #"{ "a": ["1","2"], "b": ["3"] }"#
        let a = AnalyzeByJSonPath(json)
        XCTAssertEqual(a.getStringList("$.a[*]&&$.b[*]"), ["1", "2", "3"])
    }
    // 12. getStringList %% 交错
    func testStringListPercentInterleave() {
        let json = #"{ "a": ["1","2","3"], "b": ["x","y"] }"#
        let a = AnalyzeByJSonPath(json)
        // %% 交错：a0,b0,a1,b1,a2(b无)
        XCTAssertEqual(a.getStringList("$.a[*]%%$.b[*]"), ["1", "x", "2", "y", "3"])
    }
    // 13. getStringList || 短路
    func testStringListOr() {
        let json = #"{ "a": [], "b": ["有"] }"#
        let a = AnalyzeByJSonPath(json)
        // $.a[*] 空列表 -> temp 空 -> 不加入；$.b[*] -> ["有"]
        XCTAssertEqual(a.getStringList("$.a[*]||$.b[*]"), ["有"])
    }

    // ============ 三、getString 返回 List 用 \n 拼接 / 读取失败返回空 ============

    // 14. getString 命中数组 -> "\n" 拼接
    func testGetStringListJoin() {
        let json = #"{ "arr": ["p","q","r"] }"#
        let a = AnalyzeByJSonPath(json)
        XCTAssertEqual(a.getString("$.arr[*]"), "p\nq\nr")
    }
    // 15. getString 读取失败（路径不存在）-> 空串
    func testGetStringMissingReturnsEmpty() {
        let json = #"{ "a": 1 }"#
        let a = AnalyzeByJSonPath(json)
        XCTAssertEqual(a.getString("$.nope"), "")
    }
    // 16. getString 空规则 -> nil
    func testGetStringEmptyRuleNil() {
        let a = AnalyzeByJSonPath(#"{ "a": 1 }"#)
        XCTAssertNil(a.getString(""))
    }
    // 17. getStringList 空规则 -> 空数组
    func testGetStringListEmptyRule() {
        let a = AnalyzeByJSonPath(#"{ "a": 1 }"#)
        XCTAssertEqual(a.getStringList(""), [])
    }
    // 18. getString 数字标量 -> 整数字符串（无小数点）
    func testGetStringNumber() {
        let a = AnalyzeByJSonPath(#"{ "n": 42 }"#)
        XCTAssertEqual(a.getString("$.n"), "42")
    }
    // 19. getString 布尔标量
    func testGetStringBool() {
        let a = AnalyzeByJSonPath(#"{ "b": true }"#)
        XCTAssertEqual(a.getString("$.b"), "true")
    }
    // 20. getList 读取失败 -> 空数组（异常被吞）
    func testGetListMissingEmpty() {
        let a = AnalyzeByJSonPath(#"{ "a": 1 }"#)
        XCTAssertEqual(a.getList("$.nope[*]")?.count, 0)
    }
    // 21. getObject 命中标量
    func testGetObjectScalar() throws {
        let a = AnalyzeByJSonPath(#"{ "s": "hi" }"#)
        XCTAssertEqual(try a.getObject("$.s"), .string("hi"))
    }
    // 22. 内嵌 {$.x} 组合固定文本
    func testInnerRuleWithText() {
        let a = AnalyzeByJSonPath(#"{ "id": "007" }"#)
        XCTAssertEqual(a.getString("book_{$.id}_end"), "book_007_end")
    }

    // ============ 四、木里番茄真实书源的 || 规则 ============

    // 23. 木里 ruleSearch.author 的 || 链在合成数据上验证短路
    func testMuliAuthorOrChainSyntheticData() {
        // ⚠️ 规则取自真实木里书源；此处用合成 JSON 数据喂给它，验证 || 短路行为。
        let rule = "$.author||$.copyright||$.anchor||$.source"
        let json = #"{ "copyright": "版权方", "anchor": "主播", "source": "来源" }"#
        let a = AnalyzeByJSonPath(json)
        XCTAssertEqual(a.getString(rule), "版权方")
    }
    // 24. 木里真实书源文件可被解析、其 ruleSearch 规则是真实文本
    func testMuliRealSourceLoadsAndRuleIsReal() throws {
        let raw = try loadResource("muli_real_source", subdir: "real")
        // 该文件是真实书源；此处只验证能加载 + 从其 bookList 规则里取到 || 组合的真实规则文本。
        XCTAssertTrue(raw.contains("$..book_data[*]") || raw.contains("$..books[*]"))
    }
    // 25. 木里 bookList "$..book_data[*]" 在合成数据上验证递归通配
    func testMuliBookDataRecursiveSyntheticData() {
        // ⚠️ 规则取自真实木里书源；数据为合成。
        let json = #"{ "resp": { "book_data": [ {"n":1}, {"n":2} ] } }"#
        let a = AnalyzeByJSonPath(json)
        XCTAssertEqual(a.getList("$..book_data[*]")?.count, 2)
    }

    // ============ 五、getList 的 && / || / %% 多段分支 ============

    // 26. getList || 短路（第一个非空即返回）
    func testGetListOr() {
        let json = #"{ "a": [], "b": [ {"x":1} ] }"#
        let a = AnalyzeByJSonPath(json)
        // $.a[*] 空 -> 跳过；$.b[*] -> 1 个
        XCTAssertEqual(a.getList("$.a[*]||$.b[*]")?.count, 1)
    }
    // 27. getList && 拼接（addAll）
    func testGetListAnd() {
        let json = #"{ "a": [1,2], "b": [3] }"#
        let a = AnalyzeByJSonPath(json)
        let r = a.getList("$.a[*]&&$.b[*]")
        XCTAssertEqual(r?.map { $0.stringValue }, ["1", "2", "3"])
    }
    // 28. getList %% 交错
    func testGetListPercentInterleave() {
        let json = #"{ "a": [1,2,3], "b": [7,8] }"#
        let a = AnalyzeByJSonPath(json)
        let r = a.getList("$.a[*]%%$.b[*]")
        // 交错：a0,b0,a1,b1,a2(b无)
        XCTAssertEqual(r?.map { $0.stringValue }, ["1", "7", "2", "8", "3"])
    }
}
