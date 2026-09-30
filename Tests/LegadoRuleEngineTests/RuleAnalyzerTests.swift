//
//  RuleAnalyzerTests.swift
//  LegadoRuleEngineTests
//
//  RuleAnalyzer 单元测试（@testable）。≥30 用例：
//  && / || / %% 切分；含单双引号、方括号、圆括号、转义符；嵌套 {$.x}；
//  含中文与 emoji；空规则；只有分隔符；首尾空白；括号不平衡（在受控场景）。
//
//  说明：本文件的输入规则均为「合成样本，非真实书源」——用于覆盖切分器分支。
//

import XCTest
@testable import LegadoBookSource

final class RuleAnalyzerTests: XCTestCase {

    // 便捷：切分
    private func split(_ rule: String, _ seps: [String], code: Bool = false) -> [String] {
        RuleAnalyzer(rule, code: code).splitRule(seps)
    }

    // 1. 单分隔符 && 简单切分
    func testSplitAmpSimple() {
        XCTAssertEqual(split("a&&b&&c", ["&&"]), ["a", "b", "c"])
    }
    // 2. || 简单切分
    func testSplitOrSimple() {
        XCTAssertEqual(split("a||b", ["||"]), ["a", "b"])
    }
    // 3. %% 简单切分
    func testSplitPercentSimple() {
        XCTAssertEqual(split("a%%b%%c", ["%%"]), ["a", "b", "c"])
    }
    // 4. 无分隔符：整串作为一段
    func testNoSeparator() {
        XCTAssertEqual(split("abc", ["&&"]), ["abc"])
    }
    // 5. 空规则
    func testEmptyRule() {
        XCTAssertEqual(split("", ["&&"]), [""])
    }
    // 6. 只有一个分隔符
    func testOnlySeparator() {
        XCTAssertEqual(split("&&", ["&&"]), ["", ""])
    }
    // 7. 多分隔符混合（首段匹配 && 与 ||）
    func testMixedSeparators() {
        // 首段匹配任一分隔符：a 之后遇到 && ，elementsType 设为 &&，之后按 && 切
        let r = RuleAnalyzer("a&&b&&c", code: false)
        XCTAssertEqual(r.splitRule("&&", "||"), ["a", "b", "c"])
        XCTAssertEqual(r.elementsType, "&&")
    }
    // 8. 混合分隔符，第一个遇到的是 ||
    func testMixedSeparatorsOrFirst() {
        let r = RuleAnalyzer("a||b&&c", code: false)
        XCTAssertEqual(r.splitRule("&&", "||"), ["a", "b&&c"])
        XCTAssertEqual(r.elementsType, "||")
    }
    // 9. 分隔符在方括号选择器内，不应被切分（规则平衡组）
    func testSeparatorInsideBrackets() {
        // css 选择器里含 && 时不切分（[ ] 平衡组保护）
        XCTAssertEqual(split("a[x&&y]&&b", ["&&"]), ["a[x&&y]", "b"])
    }
    // 10. 分隔符在圆括号选择器内
    func testSeparatorInsideParen() {
        XCTAssertEqual(split("a(x&&y)&&b", ["&&"]), ["a(x&&y)", "b"])
    }
    // 11. 分隔符在嵌套括号内
    func testSeparatorNestedBrackets() {
        XCTAssertEqual(split("a[b[c&&d]e]&&f", ["&&"]), ["a[b[c&&d]e]", "f"])
    }
    // 12. code 模式：单引号内的分隔符不切分
    func testSingleQuoteProtectsSeparatorCode() {
        // code=true 时 chompCodeBalanced 处理引号；把 && 放进 [] 内的引号里
        XCTAssertEqual(split("a['x&&y']&&b", ["&&"], code: true), ["a['x&&y']", "b"])
    }
    // 13. code 模式：双引号内分隔符不切分
    func testDoubleQuoteProtectsSeparatorCode() {
        XCTAssertEqual(split("a[\"x||y\"]||b", ["||"], code: true), ["a[\"x||y\"]", "b"])
    }
    // 14. 首尾空白保留（splitRule 不 trim，trim 由 trim() 单独负责）
    func testLeadingTrailingWhitespacePreserved() {
        XCTAssertEqual(split(" a && b ", ["&&"]), [" a ", " b "])
    }
    // 15. 含中文
    func testChinese() {
        XCTAssertEqual(split("作者&&书名&&简介", ["&&"]), ["作者", "书名", "简介"])
    }
    // 16. 含 emoji（UTF-16 代理对，验证位置不错位）
    func testEmoji() {
        XCTAssertEqual(split("🔥火&&💧水", ["&&"]), ["🔥火", "💧水"])
    }
    // 17. emoji 在选择器括号内且含分隔符
    func testEmojiInBracketWithSeparator() {
        XCTAssertEqual(split("a[🔥&&💧]&&b", ["&&"]), ["a[🔥&&💧]", "b"])
    }
    // 18. 三段 || 全部保留
    func testThreeOr() {
        XCTAssertEqual(split("$.a||$.b||$.c", ["&&", "||"]), ["$.a", "$.b", "$.c"])
    }
    // 19. 连续分隔符产生空段
    func testConsecutiveSeparators() {
        XCTAssertEqual(split("a&&&&b", ["&&"]), ["a", "", "b"])
    }
    // 20. 分隔符在末尾
    func testTrailingSeparator() {
        XCTAssertEqual(split("a&&", ["&&"]), ["a", ""])
    }
    // 21. 分隔符在开头
    func testLeadingSeparator() {
        XCTAssertEqual(split("&&a", ["&&"]), ["", "a"])
    }

    // MARK: innerRule（{$. ... }）

    // 22. 内嵌规则替换：单个 {$.x}
    //     注意：inner="{$." 时 startStep=1 只跳过 '{'，故回调收到的是完整路径 "$.name"
    //     （与 AnalyzeByJSonPath 里 innerRule("{$.") { getString(it) } 需要完整 $. 路径一致）。
    func testInnerRuleSingle() {
        let r = RuleAnalyzer("前{$.name}后", code: true)
        let out = r.innerRule("{$.") { inner in
            XCTAssertEqual(inner, "$.name")
            return "值"
        }
        XCTAssertEqual(out, "前值后")
    }
    // 23. 内嵌规则替换：多个
    func testInnerRuleMultiple() {
        let r = RuleAnalyzer("{$.a}-{$.b}", code: true)
        let out = r.innerRule("{$.") { inner in inner == "$.a" ? "A" : "B" }
        XCTAssertEqual(out, "A-B")
    }
    // 24. 内嵌规则：无内嵌返回空串（startX 未推移）
    func testInnerRuleNone() {
        let r = RuleAnalyzer("没有内嵌", code: true)
        let out = r.innerRule("{$.") { _ in "X" }
        XCTAssertEqual(out, "")
    }
    // 25. 内嵌规则：fr 返回 nil/空 -> 视为不平衡跳过，保持原样普通字串
    func testInnerRuleReturnsNil() {
        let r = RuleAnalyzer("前{$.x}后", code: true)
        let out = r.innerRule("{$.") { _ in nil }
        // fr 返回 nil：该 inner 当普通字串跳过；startX 保持 0 -> 返回 ""
        XCTAssertEqual(out, "")
    }
    // 26. 内嵌规则：内嵌里再含 { } 平衡（startStep=1 只跳过 '{'，故含 "$."）
    func testInnerRuleNestedBraces() {
        let r = RuleAnalyzer("A{$.f({x:1})}B", code: true)
        var captured = ""
        let out = r.innerRule("{$.") { inner in captured = inner; return "R" }
        XCTAssertEqual(captured, "$.f({x:1})")
        XCTAssertEqual(out, "ARB")
    }
    // 27. 内嵌规则（起止字符串重载）
    func testInnerRuleStartEnd() {
        let r = RuleAnalyzer("a<js>code</js>b", code: false)
        let out = r.innerRule("<js>", "</js>") { inner in
            XCTAssertEqual(inner, "code")
            return "[JS]"
        }
        XCTAssertEqual(out, "a[JS]b")
    }
    // 28. 内嵌规则（起止字符串重载）：无匹配返回原串
    func testInnerRuleStartEndNoMatch() {
        let r = RuleAnalyzer("纯文本", code: false)
        let out = r.innerRule("<js>", "</js>") { _ in "X" }
        XCTAssertEqual(out, "纯文本")
    }

    // MARK: trim / reSetPos / elementsType

    // 29. trim 去掉前导 @ 和空白
    func testTrimLeadingAtAndWhitespace() {
        // trim 只处理 pos 处；这里用 innerRule 之外的方式间接验证：切分后仍保留，
        // 但 trim 会把开头的 @ 空白吃掉。直接对首段做 splitRule 前不 trim。
        // 用 splitRule 验证 trim 效果需组合调用，这里单独验证 trim 通过 reSetPos + innerRule 观察。
        let r = RuleAnalyzer("@@@x", code: false)
        r.trim()
        // trim 后 startX 推移到 'x'，innerRule 无内嵌返回 ""，但 reSetPos 会复位；
        // 改为验证 splitRule 从 trim 后位置开始
        let out = r.splitRule("&&")
        XCTAssertEqual(out, ["x"])
    }
    // 30. reSetPos 后可复用解析器
    func testReSetPos() {
        let r = RuleAnalyzer("{$.a}", code: true)
        _ = r.splitRule("&&", "||")   // 单段
        r.reSetPos()
        let out = r.innerRule("{$.") { _ in "V" }
        XCTAssertEqual(out, "V")
    }
    // 31. elementsType 在单段 && 情况下被赋值
    func testElementsTypeSetOnSingleSep() {
        let r = RuleAnalyzer("onlyone", code: false)
        _ = r.splitRule("&&")
        XCTAssertEqual(r.elementsType, "&&")
    }

    // MARK: 括号不平衡（受控）——注意：不平衡会触发 fatalError（对齐 Kotlin 抛 Error）。
    // 这里不直接触发崩溃，而是验证「平衡的括号」能被正确保护，作为不平衡逻辑的对照。
    // 32. 平衡括号对照（作为不平衡分支的边界说明）
    func testBalancedBracketBoundary() {
        XCTAssertEqual(split("a[b(c)d]&&e", ["&&"]), ["a[b(c)d]", "e"])
    }
    // 33. code 模式转义符：\ 后字符被转义，不误判引号
    func testEscapeInCode() {
        // code 模式下 chompCodeBalanced 遇到 ESC 跳过下一个字符
        XCTAssertEqual(split("a[x\\]y]&&b", ["&&"], code: true), ["a[x\\]y]", "b"])
    }
    // 34. 规则模式转义符：引号外 \ 转义下一个字符
    func testEscapeInRuleMode() {
        XCTAssertEqual(split("a(x\\)y)&&b", ["&&"], code: false), ["a(x\\)y)", "b"])
    }
}
