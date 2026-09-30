//
//  RuleAnalyzerTests.swift
//  LegadoRuleEngineTests
//
//  RuleAnalyzer 单元测试（@testable）。≥30 用例：
//  && / || / %% 切分；含单引号、双引号、方括号、圆括号、转义符；嵌套 {$.x}；
//  含中文和 emoji；空规则；只有分隔符；首尾空白；括号不平衡（抛 RuleEngineError）。
//
//  说明：本文件的输入规则均为「合成样本，非真实数据」——用于覆盖切分器分支。
//

import XCTest
@testable import LegadoBookSource

final class RuleAnalyzerTests: XCTestCase {

    // 便捷：切分（现在会 throws）
    private func split(_ rule: String, _ seps: [String], code: Bool = false) throws -> [String] {
        try RuleAnalyzer(rule, code: code).splitRule(seps)
    }

    // 1. 单分隔符 && 简单切分
    func testSplitAmpSimple() throws {
        XCTAssertEqual(try split("a&&b&&c", ["&&"]), ["a", "b", "c"])
    }
    // 2. || 简单切分
    func testSplitOrSimple() throws {
        XCTAssertEqual(try split("a||b", ["||"]), ["a", "b"])
    }
    // 3. %% 简单切分
    func testSplitPercentSimple() throws {
        XCTAssertEqual(try split("a%%b%%c", ["%%"]), ["a", "b", "c"])
    }
    // 4. 无分隔符：整串作为一段
    func testNoSeparator() throws {
        XCTAssertEqual(try split("abc", ["&&"]), ["abc"])
    }
    // 5. 空规则
    func testEmptyRule() throws {
        XCTAssertEqual(try split("", ["&&"]), [""])
    }
    // 6. 只有一个分隔符
    func testOnlySeparator() throws {
        XCTAssertEqual(try split("&&", ["&&"]), ["", ""])
    }
    // 7. 多分隔符混合（首段匹配 && 与 ||）
    func testMixedSeparators() throws {
        let r = RuleAnalyzer("a&&b&&c", code: false)
        XCTAssertEqual(try r.splitRule("&&", "||"), ["a", "b", "c"])
        XCTAssertEqual(r.elementsType, "&&")
    }
    // 8. 混合分隔符，第一个遇到的是 ||
    func testMixedSeparatorsOrFirst() throws {
        let r = RuleAnalyzer("a||b&&c", code: false)
        XCTAssertEqual(try r.splitRule("&&", "||"), ["a", "b&&c"])
        XCTAssertEqual(r.elementsType, "||")
    }
    // 9. 分隔符在方括号选择器内，不应被切分（规则平衡组）
    func testSeparatorInsideBrackets() throws {
        XCTAssertEqual(try split("a[x&&y]&&b", ["&&"]), ["a[x&&y]", "b"])
    }
    // 10. 分隔符在圆括号选择器内
    func testSeparatorInsideParen() throws {
        XCTAssertEqual(try split("a(x&&y)&&b", ["&&"]), ["a(x&&y)", "b"])
    }
    // 11. 分隔符在嵌套括号内
    func testSeparatorNestedBrackets() throws {
        XCTAssertEqual(try split("a[b[c&&d]e]&&f", ["&&"]), ["a[b[c&&d]e]", "f"])
    }
    // 12. code 模式：单引号内的分隔符不切分
    func testSingleQuoteProtectsSeparatorCode() throws {
        XCTAssertEqual(try split("a['x&&y']&&b", ["&&"], code: true), ["a['x&&y']", "b"])
    }
    // 13. code 模式：双引号内分隔符不切分
    func testDoubleQuoteProtectsSeparatorCode() throws {
        XCTAssertEqual(try split("a[\"x||y\"]||b", ["||"], code: true), ["a[\"x||y\"]", "b"])
    }
    // 14. 首尾空白保留（splitRule 不 trim）
    func testLeadingTrailingWhitespacePreserved() throws {
        XCTAssertEqual(try split(" a && b ", ["&&"]), [" a ", " b "])
    }
    // 15. 含中文
    func testChinese() throws {
        XCTAssertEqual(try split("作者&&书名&&简介", ["&&"]), ["作者", "书名", "简介"])
    }
    // 16. 含 emoji（UTF-16 代理对，验证位置不错位）
    func testEmoji() throws {
        XCTAssertEqual(try split("🔥火&&💧水", ["&&"]), ["🔥火", "💧水"])
    }
    // 17. emoji 在选择器括号内且含分隔符
    func testEmojiInBracketWithSeparator() throws {
        XCTAssertEqual(try split("a[🔥&&💧]&&b", ["&&"]), ["a[🔥&&💧]", "b"])
    }
    // 18. 三段 || 全部保留
    func testThreeOr() throws {
        XCTAssertEqual(try split("$.a||$.b||$.c", ["&&", "||"]), ["$.a", "$.b", "$.c"])
    }
    // 19. 连续分隔符产生空段
    func testConsecutiveSeparators() throws {
        XCTAssertEqual(try split("a&&&&b", ["&&"]), ["a", "", "b"])
    }
    // 20. 分隔符在末尾
    func testTrailingSeparator() throws {
        XCTAssertEqual(try split("a&&", ["&&"]), ["a", ""])
    }
    // 21. 分隔符在开头
    func testLeadingSeparator() throws {
        XCTAssertEqual(try split("&&a", ["&&"]), ["", "a"])
    }

    // MARK: innerRule（{$. ... }）

    // 22. 内嵌规则替换：单个 {$.x}（inner="{$." startStep=1 只跳过 '{'，回调收到 "$.name"）
    func testInnerRuleSingle() throws {
        let r = RuleAnalyzer("前{$.name}后", code: true)
        let out = try r.innerRule("{$.") { inner in
            XCTAssertEqual(inner, "$.name")
            return "值"
        }
        XCTAssertEqual(out, "前值后")
    }
    // 23. 内嵌规则替换：多个
    func testInnerRuleMultiple() throws {
        let r = RuleAnalyzer("{$.a}-{$.b}", code: true)
        let out = try r.innerRule("{$.") { inner in inner == "$.a" ? "A" : "B" }
        XCTAssertEqual(out, "A-B")
    }
    // 24. 内嵌规则：无内嵌返回空串（startX 未推移）
    func testInnerRuleNone() throws {
        let r = RuleAnalyzer("没有内嵌", code: true)
        let out = try r.innerRule("{$.") { _ in "X" }
        XCTAssertEqual(out, "")
    }
    // 25. 内嵌规则：fr 返回 nil/空 -> 当普通字串跳过
    func testInnerRuleReturnsNil() throws {
        let r = RuleAnalyzer("前{$.x}后", code: true)
        let out = try r.innerRule("{$.") { _ in nil }
        XCTAssertEqual(out, "")
    }
    // 26. 内嵌规则：内嵌里再含 { } 平衡
    func testInnerRuleNestedBraces() throws {
        let r = RuleAnalyzer("A{$.f({x:1})}B", code: true)
        var captured = ""
        let out = try r.innerRule("{$.") { inner in captured = inner; return "R" }
        XCTAssertEqual(captured, "$.f({x:1})")
        XCTAssertEqual(out, "ARB")
    }
    // 27. 内嵌规则（起止字符串重载）
    func testInnerRuleStartEnd() throws {
        let r = RuleAnalyzer("a<js>code</js>b", code: false)
        let out = try r.innerRule("<js>", "</js>") { inner in
            XCTAssertEqual(inner, "code")
            return "[JS]"
        }
        XCTAssertEqual(out, "a[JS]b")
    }
    // 28. 内嵌规则（起止字符串重载）：无匹配返回原串
    func testInnerRuleStartEndNoMatch() throws {
        let r = RuleAnalyzer("纯文本", code: false)
        let out = try r.innerRule("<js>", "</js>") { _ in "X" }
        XCTAssertEqual(out, "纯文本")
    }
    // 29. 内嵌规则（起止字符串重载）：fr 返回 nil -> 对齐 Kotlin，拼接字面量 "null"
    func testInnerRuleStartEndReturnsNilAppendsNullLiteral() throws {
        let r = RuleAnalyzer("a<js>code</js>b", code: false)
        let out = try r.innerRule("<js>", "</js>") { _ in nil }
        // Kotlin: st.append(前缀 + frv)，frv 为 null 时字符串拼接得到 "null"
        XCTAssertEqual(out, "anullb")
    }

    // MARK: trim / reSetPos / elementsType

    // 30. trim 去掉前导 @ 和空白
    func testTrimLeadingAtAndWhitespace() throws {
        let r = RuleAnalyzer("@@@x", code: false)
        try r.trim()
        XCTAssertEqual(try r.splitRule("&&"), ["x"])
    }
    // 31. reSetPos 后可复用解析器
    func testReSetPos() throws {
        let r = RuleAnalyzer("{$.a}", code: true)
        _ = try r.splitRule("&&", "||")   // 单段
        r.reSetPos()
        let out = try r.innerRule("{$.") { _ in "V" }
        XCTAssertEqual(out, "V")
    }
    // 32. elementsType 在单段 && 情况下被赋值
    func testElementsTypeSetOnSingleSep() throws {
        let r = RuleAnalyzer("onlyone", code: false)
        _ = try r.splitRule("&&")
        XCTAssertEqual(r.elementsType, "&&")
    }
    // 33. 平衡括号对照
    func testBalancedBracketBoundary() throws {
        XCTAssertEqual(try split("a[b(c)d]&&e", ["&&"]), ["a[b(c)d]", "e"])
    }
    // 34. code 模式转义符：\ 后字符被转义，不误判引号
    func testEscapeInCode() throws {
        XCTAssertEqual(try split("a[x\\]y]&&b", ["&&"], code: true), ["a[x\\]y]", "b"])
    }
    // 35. 规则模式转义符：引号外 \ 转义下一个字符
    func testEscapeInRuleMode() throws {
        XCTAssertEqual(try split("a(x\\)y)&&b", ["&&"], code: false), ["a(x\\)y)", "b"])
    }

    // MARK: 调试用例（临时）：排查 JSoup &&/||/%% 组合失效问题
    func testDebugJSoupAndSplit() throws {
        let r = RuleAnalyzer("class.a@text&&class.b@text", code: false)
        let parts = try r.splitRule("&&", "||", "%%")
        XCTAssertEqual(parts, ["class.a@text", "class.b@text"], "实际切分结果：\(parts)，elementsType=\(r.elementsType)")
    }

    // MARK: 抛错点（第 1 点：崩溃收敛为 RuleEngineError）

    // 36. 括号不平衡（首段匹配）-> 抛 RuleEngineError.unbalanced
    func testUnbalancedBracketThrows() {
        let r = RuleAnalyzer("a[b&&c", code: false)  // '[' 未闭合
        XCTAssertThrowsError(try r.splitRule("&&")) { error in
            guard case RuleEngineError.unbalanced = error else {
                return XCTFail("应抛 RuleEngineError.unbalanced，实际：\(error)")
            }
        }
    }
    // 37. 括号不平衡（圆括号）-> 抛 RuleEngineError.unbalanced
    func testUnbalancedParenThrows() {
        let r = RuleAnalyzer("a(b&&c", code: false)
        XCTAssertThrowsError(try r.splitRule("&&")) { error in
            guard case RuleEngineError.unbalanced = error else {
                return XCTFail("应抛 RuleEngineError.unbalanced，实际：\(error)")
            }
        }
    }
    // 38. trim 越界 -> 抛 RuleEngineError.indexOutOfBounds
    //     纯 "@" 串：trim 吃掉所有 @ 后 pos 越界。
    func testTrimOutOfBoundsThrows() {
        let r = RuleAnalyzer("@@@", code: false)
        XCTAssertThrowsError(try r.trim()) { error in
            guard case RuleEngineError.indexOutOfBounds = error else {
                return XCTFail("应抛 RuleEngineError.indexOutOfBounds，实际：\(error)")
            }
        }
    }
}
