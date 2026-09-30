//
//  AnalyzeByJSonPathTests.swift
//  LegadoRuleEngineTests
//
//  AnalyzeByJSonPath 单元测试（@testable）。≥20 用例。
//
//  样本来源标注：
//   - synthetic_lieying_like.json：⚠️ 合成样本（非真实数据），结构参考猎鹰小说网规则。
//   - Resources/real/muli_real_source.json：真实书源（🍅木里番茄），来源：用户提供。
//   - Resources/real/qimo_real_source.json：真实书源（七猫小说），来源：用户提供。
//   - 各内联 JSON：⚠️ 合成样本，仅覆盖具体分支。
//

import XCTest
@testable import LegadoBookSource

final class AnalyzeByJSonPathTests: XCTestCase {

    private func loadResource(_ name: String, subdir: String? = nil) throws -> String {
        var url: URL? = nil
        if let subdir = subdir {
            url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: subdir)
        }
        if url == nil { url = Bundle.module.url(forResource: name, withExtension: "json") }
        if url == nil, let resourceURL = Bundle.module.resourceURL {
            if let en = FileManager.default.enumerator(at: resourceURL, includingPropertiesForKeys: nil) {
                for case let f as URL in en where f.lastPathComponent == "\(name).json" { url = f; break }
            }
        }
        guard let u = url else { XCTFail("找不到资源 \(name)"); throw NSError(domain: "t", code: 1) }
        return try String(contentsOf: u, encoding: .utf8)
    }

    // ============ 一、猎鹰小说网规则（合成样本） ============

    func testLieyingBookListRecursiveWildcard() throws {
        let json = try loadResource("synthetic_lieying_like")
        let a = AnalyzeByJSonPath(json)
        let list = try a.getList("$..books[*]")
        XCTAssertEqual(list?.count, 2)
    }
    func testLieyingBookTitle() throws {
        let json = try loadResource("synthetic_lieying_like")
        let list = try AnalyzeByJSonPath(json).getList("$..books[*]")!
        let first = AnalyzeByJSonPath(list[0])
        XCTAssertEqual(try first.getString("$.title"), "书一")
        XCTAssertEqual(try first.getString("$.author"), "作者一")
    }
    func testLieyingBookUrlInnerRule() throws {
        let json = try loadResource("synthetic_lieying_like")
        let list = try AnalyzeByJSonPath(json).getList("$..books[*]")!
        let first = AnalyzeByJSonPath(list[0])
        let url = try first.getString("/Book/getChapterListByBookId?bookId={$._id}")
        XCTAssertEqual(url, "/Book/getChapterListByBookId?bookId=b001")
    }
    func testLieyingChapterListDotBracket() throws {
        let json = try loadResource("synthetic_lieying_like")
        let toc = try AnalyzeByJSonPath(json).getObject("$.toc")
        let chapters = try AnalyzeByJSonPath(toc).getList("$.chapterInfo.chapters.[*]")
        XCTAssertEqual(chapters?.count, 3)
    }
    func testLieyingChapterFields() throws {
        let json = try loadResource("synthetic_lieying_like")
        let toc = try AnalyzeByJSonPath(json).getObject("$.toc")
        let chapters = try AnalyzeByJSonPath(toc).getList("$.chapterInfo.chapters.[*]")!
        let c0 = AnalyzeByJSonPath(chapters[0])
        XCTAssertEqual(try c0.getString("$.title"), "第一章")
        XCTAssertEqual(try c0.getString("$.link"), "/read/1")
    }
    func testLieyingContentBody() throws {
        let json = try loadResource("synthetic_lieying_like")
        let content = try AnalyzeByJSonPath(json).getObject("$.content")
        let body = try AnalyzeByJSonPath(content).getString("$.chapter.body")
        XCTAssertEqual(body, "正文内容第一段\n正文内容第二段")
    }

    // ============ 二、|| 短路 / && 拼接 / %% 交错 ============

    func testOrShortCircuit() throws {
        let a = AnalyzeByJSonPath(#"{ "author": "甲", "copyright": "乙" }"#)
        XCTAssertEqual(try a.getString("$.author||$.copyright"), "甲")
    }
    func testOrFallback() throws {
        let a = AnalyzeByJSonPath(#"{ "copyright": "乙", "anchor": "丙" }"#)
        XCTAssertEqual(try a.getString("$.author||$.copyright||$.anchor"), "乙")
    }
    func testOrAllMissing() throws {
        let a = AnalyzeByJSonPath(#"{ "x": 1 }"#)
        XCTAssertEqual(try a.getString("$.author||$.copyright"), "")
    }
    func testAndJoin() throws {
        let a = AnalyzeByJSonPath(#"{ "a": "1", "b": "2" }"#)
        XCTAssertEqual(try a.getString("$.a&&$.b"), "1\n2")
    }
    func testStringListAnd() throws {
        let a = AnalyzeByJSonPath(#"{ "a": ["1","2"], "b": ["3"] }"#)
        XCTAssertEqual(try a.getStringList("$.a[*]&&$.b[*]"), ["1", "2", "3"])
    }
    func testStringListPercentInterleave() throws {
        let a = AnalyzeByJSonPath(#"{ "a": ["1","2","3"], "b": ["x","y"] }"#)
        XCTAssertEqual(try a.getStringList("$.a[*]%%$.b[*]"), ["1", "x", "2", "y", "3"])
    }
    func testStringListOr() throws {
        let a = AnalyzeByJSonPath(#"{ "a": [], "b": ["有"] }"#)
        XCTAssertEqual(try a.getStringList("$.a[*]||$.b[*]"), ["有"])
    }

    // ============ 三、getString 返回 List 用 \n 拼接 / 读取失败返回空 ============

    func testGetStringListJoin() throws {
        let a = AnalyzeByJSonPath(#"{ "arr": ["p","q","r"] }"#)
        XCTAssertEqual(try a.getString("$.arr[*]"), "p\nq\nr")
    }
    func testGetStringMissingReturnsEmpty() throws {
        let a = AnalyzeByJSonPath(#"{ "a": 1 }"#)
        XCTAssertEqual(try a.getString("$.nope"), "")
    }
    func testGetStringEmptyRuleNil() throws {
        let a = AnalyzeByJSonPath(#"{ "a": 1 }"#)
        XCTAssertNil(try a.getString(""))
    }
    func testGetStringListEmptyRule() throws {
        let a = AnalyzeByJSonPath(#"{ "a": 1 }"#)
        XCTAssertEqual(try a.getStringList(""), [])
    }
    func testGetStringBool() throws {
        let a = AnalyzeByJSonPath(#"{ "b": true }"#)
        XCTAssertEqual(try a.getString("$.b"), "true")
    }
    func testGetListMissingEmpty() throws {
        let a = AnalyzeByJSonPath(#"{ "a": 1 }"#)
        XCTAssertEqual(try a.getList("$.nope[*]")?.count, 0)
    }
    func testGetObjectScalar() throws {
        let a = AnalyzeByJSonPath(#"{ "s": "hi" }"#)
        XCTAssertEqual(try a.getObject("$.s"), .string("hi"))
    }
    func testInnerRuleWithText() throws {
        let a = AnalyzeByJSonPath(#"{ "id": "007" }"#)
        XCTAssertEqual(try a.getString("book_{$.id}_end"), "book_007_end")
    }

    // ============ 四、木里番茄真实书源的 || 规则 ============

    func testMuliAuthorOrChainSyntheticData() throws {
        // ⚠️ 规则取自真实木里书源；此处用合成 JSON 数据喂给它，验证 || 短路行为。
        let rule = "$.author||$.copyright||$.anchor||$.source"
        let a = AnalyzeByJSonPath(#"{ "copyright": "版权方", "anchor": "主播", "source": "来源" }"#)
        XCTAssertEqual(try a.getString(rule), "版权方")
    }
    func testMuliRealSourceLoadsAndRuleIsReal() throws {
        let raw = try loadResource("muli_real_source", subdir: "real")
        XCTAssertTrue(raw.contains("$..book_data[*]") || raw.contains("$..books[*]"))
    }
    func testMuliBookDataRecursiveSyntheticData() throws {
        let a = AnalyzeByJSonPath(#"{ "resp": { "book_data": [ {"n":1}, {"n":2} ] } }"#)
        XCTAssertEqual(try a.getList("$..book_data[*]")?.count, 2)
    }

    // ============ 五、getList 的 && / || / %% 多段分支 ============

    func testGetListOr() throws {
        let a = AnalyzeByJSonPath(#"{ "a": [], "b": [ {"x":1} ] }"#)
        XCTAssertEqual(try a.getList("$.a[*]||$.b[*]")?.count, 1)
    }
    func testGetListAnd() throws {
        let a = AnalyzeByJSonPath(#"{ "a": [1,2], "b": [3] }"#)
        let r = try a.getList("$.a[*]&&$.b[*]")
        XCTAssertEqual(r?.map { $0.stringValue }, ["1", "2", "3"])
    }
    func testGetListPercentInterleave() throws {
        let a = AnalyzeByJSonPath(#"{ "a": [1,2,3], "b": [7,8] }"#)
        let r = try a.getList("$.a[*]%%$.b[*]")
        XCTAssertEqual(r?.map { $0.stringValue }, ["1", "7", "2", "8", "3"])
    }

    // ============ 六、数字精度：整数/小数区别、大整数、负数、科学计数法 ============

    // 19 位整数原样输出（不经 Double 丢精度）
    func testBigIntegerExact() throws {
        let a = AnalyzeByJSonPath(#"{ "id": 7143038691944959011 }"#)
        XCTAssertEqual(try a.getString("$.id"), "7143038691944959011")
    }
    // 1.0 输出 "1.0"（保留小数点，对齐 Java Double.toString）
    func testDoubleOnePointZero() throws {
        let a = AnalyzeByJSonPath(#"{ "v": 1.0 }"#)
        XCTAssertEqual(try a.getString("$.v"), "1.0")
    }
    // 1.5 输出 "1.5"
    func testDoubleOnePointFive() throws {
        let a = AnalyzeByJSonPath(#"{ "v": 1.5 }"#)
        XCTAssertEqual(try a.getString("$.v"), "1.5")
    }
    // 整数字面量输出整数（无 ".0"）
    func testIntegerNoDecimal() throws {
        let a = AnalyzeByJSonPath(#"{ "v": 42 }"#)
        XCTAssertEqual(try a.getString("$.v"), "42")
    }
    // 负数
    func testNegativeNumber() throws {
        let a = AnalyzeByJSonPath(#"{ "v": -123 }"#)
        XCTAssertEqual(try a.getString("$.v"), "-123")
    }
    // 大整数（接近 Int64 上限）
    func testLargeInteger() throws {
        let a = AnalyzeByJSonPath(#"{ "v": 9223372036854775807 }"#)  // Int64.max
        XCTAssertEqual(try a.getString("$.v"), "9223372036854775807")
    }
    // 科学计数法 -> Double（1e3 = 1000.0）
    func testScientificNotation() throws {
        let a = AnalyzeByJSonPath(#"{ "v": 1e3 }"#)
        XCTAssertEqual(try a.getString("$.v"), "1000.0")
    }

    // ============ 七、对象键顺序保持（Jayway/json-smart 有序） ============

    // $.obj.* 的结果顺序等于 JSON 文本顺序
    func testObjectWildcardKeyOrder() throws {
        let a = AnalyzeByJSonPath(#"{ "obj": { "z": "1", "a": "2", "m": "3" } }"#)
        // 文本顺序 z,a,m -> 值 1,2,3
        XCTAssertEqual(try a.getStringList("$.obj.*"), ["1", "2", "3"])
    }
    // $..* 递归顺序也按文本顺序（这里用嵌套对象验证顶层键顺序）
    func testRecursiveWildcardKeyOrder() throws {
        // 顶层 b,a 两个字符串键；$..* 先纳入根，再按文本顺序 b、a
        let a = AnalyzeByJSonPath(#"{ "b": "B", "a": "A" }"#)
        let list = try a.getStringList("$..*")
        // 递归：根对象(其 stringValue 为紧凑 JSON) + "B" + "A"
        // 只断言标量部分的相对顺序：B 在 A 前
        let idxB = list.firstIndex(of: "B")
        let idxA = list.firstIndex(of: "A")
        XCTAssertNotNil(idxB); XCTAssertNotNil(idxA)
        XCTAssertLessThan(idxB!, idxA!)
    }
    // getObject 的紧凑输出保持键顺序
    func testGetObjectCompactKeyOrder() throws {
        let a = AnalyzeByJSonPath(#"{ "root": { "z": 1, "a": 2 } }"#)
        let obj = try a.getObject("$.root")
        XCTAssertEqual(obj.stringValue, #"{"z":1,"a":2}"#)
    }

    // ============ 八、切分器错误向上传播（第 1 点） ============

    // getString 遇到括号不平衡的规则 -> 抛 RuleEngineError（不再吞、不崩溃）
    func testGetStringPropagatesUnbalanced() {
        let a = AnalyzeByJSonPath(#"{ "a": 1 }"#)
        XCTAssertThrowsError(try a.getString("$.a[&&$.b")) { error in
            guard case RuleEngineError.unbalanced = error else {
                return XCTFail("应抛 RuleEngineError.unbalanced，实际：\(error)")
            }
        }
    }
    // getList 同样传播
    func testGetListPropagatesUnbalanced() {
        let a = AnalyzeByJSonPath(#"{ "a": 1 }"#)
        XCTAssertThrowsError(try a.getList("$.a(&&$.b")) { error in
            guard case RuleEngineError.unbalanced = error else {
                return XCTFail("应抛 RuleEngineError.unbalanced，实际：\(error)")
            }
        }
    }

    // ============ 九、诊断收集器：ctx.read 失败被吞但记录 ============

    func testDiagnosticsRecordedOnReadFailure() throws {
        let diag = RuleEngineDiagnostics()
        let a = AnalyzeByJSonPath(#"{ "a": 1 }"#, diagnostics: diag)
        _ = try a.getString("$.nope")   // 读取失败，返回空
        XCTAssertFalse(diag.diagnostics.isEmpty)
        XCTAssertEqual(diag.diagnostics.first?.source, "AnalyzeByJSonPath.getString")
    }

    // ============ 十、七猫小说 真实书源的 JSON 规则（≥5） ============
    // ⚠️ 规则取自真实七猫书源（Resources/real/qimo_real_source.json）；数据为按其规则形状构造的合成 JSON。

    // 构造一份贴合七猫规则形状的合成数据
    private let qimoSearchJSON = #"""
    { "data": { "books": [
        { "id": 111, "original_author": "作者甲", "original_title": "书名甲", "image_link": "http://c/1", "intro": "简介甲", "ptags": "玄幻", "words_num": "12万" },
        { "id": 222, "original_author": "作者乙", "original_title": "书名乙", "image_link": "http://c/2", "intro": "简介乙", "ptags": "都市", "words_num": "8万" }
    ] } }
    """#

    // 1. 真实规则 ruleSearch.bookList = "data.books"（无 $ 前缀，Jayway 容忍）
    func testQimoBookList() throws {
        let a = AnalyzeByJSonPath(qimoSearchJSON)
        let list = try a.getList("data.books")
        XCTAssertEqual(list?.count, 2)
    }
    // 2. 真实规则 ruleSearch.name = "original_title"
    func testQimoName() throws {
        let list = try AnalyzeByJSonPath(qimoSearchJSON).getList("data.books")!
        let first = AnalyzeByJSonPath(list[0])
        XCTAssertEqual(try first.getString("original_title"), "书名甲")
    }
    // 3. 真实规则 ruleSearch.author = "original_author"
    func testQimoAuthor() throws {
        let list = try AnalyzeByJSonPath(qimoSearchJSON).getList("data.books")!
        let second = AnalyzeByJSonPath(list[1])
        XCTAssertEqual(try second.getString("original_author"), "作者乙")
    }
    // 4. 真实规则 ruleSearch.kind = "ptags" / coverUrl = "image_link" / wordCount = "words_num"
    func testQimoOtherSearchFields() throws {
        let list = try AnalyzeByJSonPath(qimoSearchJSON).getList("data.books")!
        let first = AnalyzeByJSonPath(list[0])
        XCTAssertEqual(try first.getString("ptags"), "玄幻")
        XCTAssertEqual(try first.getString("image_link"), "http://c/1")
        XCTAssertEqual(try first.getString("words_num"), "12万")
    }
    // 5. 真实规则 ruleToc.chapterList = "data.chapter_lists"，chapterName = "title"，chapterUrl = "id"
    func testQimoTocRules() throws {
        let tocJSON = #"{ "data": { "chapter_lists": [ {"id": 1, "title": "第1章"}, {"id": 2, "title": "第2章"} ] } }"#
        let a = AnalyzeByJSonPath(tocJSON)
        let chapters = try a.getList("data.chapter_lists")!
        XCTAssertEqual(chapters.count, 2)
        let c0 = AnalyzeByJSonPath(chapters[0])
        XCTAssertEqual(try c0.getString("title"), "第1章")
        XCTAssertEqual(try c0.getString("id"), "1")
    }
    // 6. 真实规则 ruleBookInfo.kind = "book_tag_list[*].title"（数组通配 + 子字段）
    func testQimoBookInfoTagList() throws {
        let infoJSON = #"{ "book_tag_list": [ {"title": "标签1"}, {"title": "标签2"} ] }"#
        let a = AnalyzeByJSonPath(infoJSON)
        // getString 命中列表 -> "\n" 拼接
        XCTAssertEqual(try a.getString("book_tag_list[*].title"), "标签1\n标签2")
    }
    // 7. 真实书源文件能加载且规则文本真实
    func testQimoRealFileLoads() throws {
        let raw = try loadResource("qimo_real_source", subdir: "real")
        XCTAssertTrue(raw.contains("data.books"))
        XCTAssertTrue(raw.contains("original_author"))
    }
}
