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
        // 嵌套对象键值直取后，其 stringValue 为 map 的 String(describing:)（含 name/n）
        let s = try a.getString("info")
        XCTAssertTrue(s.contains("name"))
        XCTAssertTrue(s.contains("n"))
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

    func testJsObject_getElements_noSpecialKeyBranch() throws {
        // Kotlin getElements 对 NativeObject 不做键值直取，而是把它当普通 content 进入调度。
        // content 是 jsObject，规则 "chapters" 会被当作 CSS/默认规则作用在其 stringValue 上，
        // 合成对象字符串化后不是 HTML，JSoup 选不到元素 -> 返回空列表（不崩溃）。
        let a = AnalyzeRule()
        _ = try a.setContent(.jsObject(["chapters": .stringList(["c1", "c2"])]))
        let els = try a.getElements("chapters")
        // 如实固定：不走键值直取，返回空（而非 [c1, c2]）。
        XCTAssertTrue(els.isEmpty)
    }

    func testJsonObject_getElement_noSpecialKeyBranch() throws {
        let a = AnalyzeRule()
        _ = try a.setContent(.jsonObject(["k": .string("v")]))
        // getElement 对 jsonObject 同样无键值直取分支，走默认 JSoup 调度，选不到元素。
        let el = try a.getElement("k")
        // 结果是 .elements([]) 空集合（不崩溃）；断言其为空或 null。
        if let el = el, case .elements(let es) = el {
            XCTAssertTrue(es.isEmpty)
        } else {
            // 也接受 nil / .null
            XCTAssertTrue(el == nil || el!.isNull)
        }
    }

    // MARK: - contentEquals 近似（Kotlin 引用判等 vs 本移植 stringValue 近似）边界

    // 边界 1：两个内容不同的 jsObject，stringValue 不同 -> contentEquals 判为不同（与 Kotlin 一致：
    //         不同实例、不同内容，引用判等也为 false）。通过「换 content 后解析器重建」间接验证。
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
