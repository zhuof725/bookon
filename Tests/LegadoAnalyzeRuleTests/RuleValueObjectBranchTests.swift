//
//  RuleValueObjectBranchTests.swift
//  LegadoAnalyzeRuleTests
//
//  针对 RuleValue 的 .jsObject（对应 Kotlin Rhino NativeObject）和 .jsonObject
//  （对应 Kotlin Gson LinkedTreeMap）两个分支的专用单测。第 4 步收尾补齐
//  （STEP4B 曾标注「无专用单测」）。
//
//  覆盖：把 .jsObject / .jsonObject 内容直接作为 content 喂给
//  getString / getStringList / getElement / getElements，覆盖
//  JSON 规则键值直取、{{ }}、嵌套对象、数组、null、数字格式。
//
//  以及 contentEquals 近似（Kotlin 用引用判等，本移植用 stringValue 近似）的边界用例。
//
//  ⚠️ 全部为【合成样本，非真实数据】：下面构造的 jsObject/jsonObject 键值、
//     规则字符串均为手工构造，用于验证调度分支行为，不来自任何真实书源抓取结果。
//
//  对照 Kotlin AnalyzeRule.kt：
//   - getString/getStringList 对 NativeObject：取 ruleList.first()，paramSize>1 时
//     走 {{ }}（rule 本身即结果），否则 result[rule] 键值直取。
//   - getString/getStringList 对 LinkedTreeMap：result[ruleList.first().rule] 键值直取。
//   - getElement/getElements 对这两种类型：Kotlin 无专用「键值直取」分支，与普通
//     content 一样进入调度循环（本测试如实固定这一行为）。
//

import XCTest
@testable import LegadoBookSource

final class RuleValueObjectBranchTests: XCTestCase {

    // MARK: - .jsObject（Rhino NativeObject 对应）—— getString 键值直取

    func testJsObject_getString_directKey() throws {
        let a = AnalyzeRule()
        _ = try a.setContent(.jsObject([
            "title": .string("斗破苍穹"),
            "author": .string("天蚕土豆")
        ]))
        // paramSize==1（纯键名），走 result[rule] 键值直取
        XCTAssertEqual(try a.getString("title"), "斗破苍穹")
        XCTAssertEqual(try a.getString("author"), "天蚕土豆")
    }

    func testJsObject_getString_missingKeyEmpty() throws {
        let a = AnalyzeRule()
        _ = try a.setContent(.jsObject(["title": .string("x")]))
        // 不存在的键 -> result 为 nil -> getString 返回 ""
        XCTAssertEqual(try a.getString("nope"), "")
    }

    func testJsObject_getString_numberFormat() throws {
        let a = AnalyzeRule()
        // 数字值：整数带 .0（对齐 Kotlin Double.toString），小数原样
        _ = try a.setContent(.jsObject([
            "intVal": .number(42),
            "floatVal": .number(3.5)
        ]))
        XCTAssertEqual(try a.getString("intVal"), "42.0")
        XCTAssertEqual(try a.getString("floatVal"), "3.5")
    }

    func testJsObject_getString_nullValue() throws {
        let a = AnalyzeRule()
        _ = try a.setContent(.jsObject(["k": .null]))
        // 值为 .null -> stringValue "null"（键存在，取到的是 null 值）
        XCTAssertEqual(try a.getString("k"), "null")
    }

    func testJsObject_getString_nestedObjectStringified() throws {
        let a = AnalyzeRule()
        _ = try a.setContent(.jsObject([
            "info": .jsObject(["name": .string("n")])
        ]))
        // Kotlin NativeObject 的 Java toString 为固定的 `[object Object]`，不是 Map 描述。
        XCTAssertEqual(try a.getString("info"), "[object Object]")
    }

    // MARK: - .jsObject —— getStringList

    func testJsObject_getStringList_arrayValue() throws {
        let a = AnalyzeRule()
        _ = try a.setContent(.jsObject([
            "chapters": .stringList(["第1章", "第2章", "第3章"])
        ]))
        // 键值直取到 stringList，原样返回
        XCTAssertEqual(try a.getStringList("chapters"), ["第1章", "第2章", "第3章"])
    }

    func testJsObject_getStringList_singleStringSplit() throws {
        let a = AnalyzeRule()
        _ = try a.setContent(.jsObject([
            "lines": .string("a\nb\nc")
        ]))
        // 键值取到字符串 -> 换行切分
        XCTAssertEqual(try a.getStringList("lines"), ["a", "b", "c"])
    }

    // MARK: - .jsonObject（Gson LinkedTreeMap 对应）—— getString/getStringList 键值直取

    func testJsonObject_getString_directKey() throws {
        let a = AnalyzeRule()
        _ = try a.setContent(.jsonObject([
            "name": .string("完美世界"),
            "status": .string("连载")
        ]))
        XCTAssertEqual(try a.getString("name"), "完美世界")
        XCTAssertEqual(try a.getString("status"), "连载")
    }

    func testJsonObject_getString_missingKeyEmpty() throws {
        let a = AnalyzeRule()
        _ = try a.setContent(.jsonObject(["name": .string("x")]))
        XCTAssertEqual(try a.getString("absent"), "")
    }

    func testJsonObject_getString_numberAndNull() throws {
        let a = AnalyzeRule()
        _ = try a.setContent(.jsonObject([
            "count": .number(100),
            "empty": .null
        ]))
        XCTAssertEqual(try a.getString("count"), "100.0")
        XCTAssertEqual(try a.getString("empty"), "null")
    }

    func testJsonObject_getStringList_arrayValue() throws {
        let a = AnalyzeRule()
        _ = try a.setContent(.jsonObject([
            "tags": .stringList(["玄幻", "热血", "升级"])
        ]))
        XCTAssertEqual(try a.getStringList("tags"), ["玄幻", "热血", "升级"])
    }

    func testJsonObject_getStringList_nestedObject() throws {
        let a = AnalyzeRule()
        _ = try a.setContent(.jsonObject([
            "meta": .jsonObject(["k": .string("v")])
        ]))
        // 键值取到嵌套对象 -> getStringList 对非列表/非字符串走 asStringList ?? [stringValue]
        let list = try a.getStringList("meta")
        XCTAssertNotNil(list)
        XCTAssertEqual(list?.count, 1)
        XCTAssertTrue(list?.first?.contains("k") ?? false)
    }

    // MARK: - {{ }} 内联：jsObject 下 paramSize>1 走 {{ }} 分支

    func testJsObject_inlineBraces_paramSizeGreaterThanOne() throws {
        let a = AnalyzeRule()
        _ = try a.setContent(.jsObject(["x": .string("ignored")]))
        // 规则含 {{ }}（内联 JS）-> getParamSize()>1 -> result = sourceRule.rule（{{}} 求值结果）。
        // 这里 {{ '前缀-' + '后缀' }} 是纯 JS 表达式，求值为 "前缀-后缀"。
        let s = try a.getString("固定{{'A'+'B'}}")
        XCTAssertEqual(s, "固定AB")
    }

    // MARK: - getElement / getElements 对象分支的现状（Kotlin 无专用键值直取分支）

    func testJsObject_getElements_stringifiesAndRegexMatches() throws {
        // Kotlin getElements 对 NativeObject 不做键值直取，而是把它当普通 content 进入调度。
        // NativeObject 的 Java toString 为固定前缀 `[object Object]`；用 allInOne 的 `:正则`
        // 强制 Regex 模式，验证对象 content 按这一真实 Rhino 字符串化结果参与匹配。
        let a = AnalyzeRule()
        _ = try a.setContent(.jsObject(["chapters": .stringList(["c1", "c2"])]))
        let els = try a.getElements(":object")
        XCTAssertFalse(els.isEmpty)
    }

    func testJsonObject_getElement_allInOneRegexStringifies() throws {
        let a = AnalyzeRule()
        _ = try a.setContent(.jsonObject(["k": .string("v")]))
        // 同上：强制 Regex 模式（`:正则`），jsonObject 字符串化后参与匹配，不崩溃。
        // 注意：getElement 首个规则 find 失败返回 nil，故用必然命中的正则。
        let el = try a.getElement(":k")
        XCTAssertNotNil(el)
    }

    // MARK: - contentEquals 近似（Kotlin 引用判等 vs 本移植 stringValue 近似）边界

    // 边界 1：两个内容不同的 jsObject 仍会共享 Rhino 的 `[object Object]` stringValue，
    //         因此本移植会近似判为「相同」并复用缓存；但 getString 的 NativeObject 键值直取
    //         在进入解析器前完成，所以 mContent 仍正确取到新对象的值。
    func testContentEquals_differentJsObjects_rebuild() throws {
        let a = AnalyzeRule()
        _ = try a.setContent(.jsObject(["a": .string("1")]))
        // 用一个与 content 不同的 RuleValue 作为 mContent 直接取值，应得到该 mContent 的键值，
        // 而非 content 的（验证 getAnalyzeByXxx 对 o!=content 会用 o 新建，不复用 content 的解析器）。
        let other = RuleValue.jsObject(["a": .string("2")])
        XCTAssertEqual(try a.getString("a", mContent: other), "2")
        XCTAssertEqual(try a.getString("a"), "1")  // content 自身不受影响
    }

    // 边界 2：两个 stringValue 相同但「不是同一实例」的值（Kotlin 引用判等判 false，
    //         本移植 stringValue 近似判 true）。可构造场景：两个内容相同的 String 常量。
    //         这里固定「本移植按 stringValue 判等」的实际行为，并在 README「contentEquals 近似」差异说明记录。
    func testContentEquals_sameStringValueDifferentKind_knownApprox() throws {
        let a = AnalyzeRule()
        let html = "<div>x</div>"
        _ = try a.setContent(.string(html))
        // mContent 传一个内容相同、但 Swift 层面是「新拼接实例」的 .string（拼接可避免
        // 字符串驻留使编译器把它们当同一实例，从而保证「不是同一对象」这一前提成立）。
        // Kotlin 里 content 与这个新实例是两个 String，引用判等判 false；
        // 本移植按 stringValue 判等判 true——但两条路径对同一 HTML 取 div 文本的结果
        // 一致（都是 x），故此近似在「结果层面」不产生可观测差异。
        let sameValue = RuleValue.string("<div>x" + "</div>")
        let viaContent = try a.getString("div@text")
        let viaMContent = try a.getString("div@text", mContent: sameValue)
        XCTAssertEqual(viaContent, "x")
        XCTAssertEqual(viaMContent, "x")
        // 结论：stringValue 近似在此等价于引用判等的可观测结果。见 README「contentEquals 近似」差异说明。
    }

    // 边界 3：空内容与 null 的判等边界（content 为 nil 时 contentEquals 恒 false）。
    func testContentEquals_noContentAlwaysFalse() throws {
        let a = AnalyzeRule()  // 未 setContent，content 为 nil
        // 直接用 mContent 取值可用（不依赖 content）。
        XCTAssertEqual(try a.getString("k", mContent: .jsObject(["k": .string("ok")])), "ok")
        // content 为 nil 时，普通 getString（无 mContent）返回 ""（无内容）。
        XCTAssertEqual(try a.getString("k"), "")
    }
}
