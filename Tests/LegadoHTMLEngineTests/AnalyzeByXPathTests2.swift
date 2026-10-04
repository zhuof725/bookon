//
//  AnalyzeByXPathTests2.swift
//  LegadoHTMLEngineTests
//
//  第 3 步收尾新增：联合运算符 `|`、not()、字符串函数（string/count/concat/substring/
//  substring-before/substring-after/string-length）、contains/starts-with 的 text()/. 参数、
//  多重谓词 `[...][...]`。
//
//  ⚠️ 本文件全部 HTML 均为合成样本，非真实数据。
//

import XCTest
@testable import LegadoBookSource

final class AnalyzeByXPathTests2: XCTestCase {

    // MARK: - 一、联合运算符 `|`

    func testUnionTwoDifferentPaths() throws {
        let html = "<div><h1>标题</h1><p>段落一</p><p>段落二</p></div>"
        let x = try AnalyzeByXPath(html)
        let r = try x.getStringList("//h1/text()|//p/text()")
        XCTAssertEqual(r, ["标题", "段落一", "段落二"])
    }
    // ⚠️ 与 Kotlin 已知差异（已用 golden 对照真实 JsoupXpath 2.5.3 验证）：标准 XPath `|`
    // 应该去重+按文档顺序排列，但真实 JsoupXpath 的实现既不去重也不按文档顺序重排，
    // 而是"分支书写顺序 + 分支内命中顺序"直接拼接。本移植复刻这一真实行为（而非标准规范），
    // 详见 README「与 Kotlin 已知差异」表。
    func testUnionDoesNotDedupSamePath() throws {
        // 同一路径 | 自己：真实 JsoupXpath 不去重，结果翻倍
        let html = "<div><p>甲</p><p>乙</p></div>"
        let x = try AnalyzeByXPath(html)
        let els = try x.getElements("//p|//p")
        XCTAssertEqual(els?.count, 4)
    }
    func testUnionConcatenatesByBranchOrderNotDocumentOrder() throws {
        // 联合结果按「分支书写顺序」拼接，不按文档顺序重排（真实 JsoupXpath 行为）
        let html = "<ul><li class='a'>1</li><li class='b'>2</li><li class='a'>3</li></ul>"
        let x = try AnalyzeByXPath(html)
        // 先写 class=b 分支，再写 class=a 分支；结果是 b 分支命中(2) 后跟 a 分支命中(1,3)
        let r = try x.getStringList("//li[@class='b']/text()|//li[@class='a']/text()")
        XCTAssertEqual(r, ["2", "1", "3"])
    }
    func testUnionWithAndCombo() throws {
        // `|` 与规则引擎的 && 组合：|` 在切分后的单个子规则内部生效
        let html = "<div><h1>标题</h1><p>段落一</p><p>段落二</p></div>"
        let x = try AnalyzeByXPath(html)
        let r = try x.getString("//h1/text()&&//h1/text()|//p/text()")
        XCTAssertEqual(r, "标题\n标题\n段落一\n段落二")
    }
    func testUnionWithOrCombo() throws {
        let html = "<div><h1>标题</h1><p>段落一</p><p>段落二</p></div>"
        let x = try AnalyzeByXPath(html)
        // 第一段 //nonexist/text() 为空 -> || 继续第二段 //h1/text()|//p/text()
        let r = try x.getStringList("//nonexist/text()||//h1/text()|//p/text()")
        XCTAssertEqual(r, ["标题", "段落一", "段落二"])
    }
    // 说明：getString/getStringList 的 && / || 由 RuleAnalyzer 在 AnalyzeByXPath 层面切分，
    // 但 %% 只在 getStringList/getElements 里支持（getString 对应 Kotlin 原版只识别 &&/||，
    // 这是 Kotlin 原始签名的设计，不是本移植遗漏，故不测 getString 对 %% 的组合，只测 getStringList）。
    func testUnionWithPercentComboViaGetStringList() throws {
        let html = "<ul><li class='a'>1</li><li class='b'>2</li><li class='a'>3</li></ul>"
        let x = try AnalyzeByXPath(html)
        // 左规则: [1,3]；右规则(含 | 联合，真实 JsoupXpath 不去重): [2,2]
        // %% 交错：左[0]=1,右[0]=2, 左[1]=3,右[1]=2
        let r = try x.getStringList("//li[@class='a']/text()%%//li[@class='b']/text()|//li[@class='b']/text()")
        XCTAssertEqual(r, ["1", "2", "3", "2"])
    }

    // MARK: - 二、not()

    func testNotFunctionBasic() throws {
        let html = "<ul><li class='skip'>跳过</li><li>保留一</li><li>保留二</li></ul>"
        let x = try AnalyzeByXPath(html)
        let r = try x.getStringList("//li[not(@class='skip')]/text()")
        XCTAssertEqual(r, ["保留一", "保留二"])
    }
    func testNotFunctionAttrExists() throws {
        let html = "<div><a href='/x'>有</a><a>无</a></div>"
        let x = try AnalyzeByXPath(html)
        let r = try x.getStringList("//a[not(@href)]/text()")
        XCTAssertEqual(r, ["无"])
    }
    // ⚠️ 与 Kotlin 已知差异（已用 golden 对照真实 JsoupXpath 2.5.3 验证）：
    // `not(...)` 或函数比较与 `and`/`or` 组合在真实 JsoupXpath 里不生效（返回空），
    // 本移植对齐这一行为：遇到该组合抛 RuleEngineError.invalidXPath（不支持），
    // 经 AnalyzeByXPath 吞异常后返回空值，结果与 Java 一致（而不是按标准 XPath 语义算出结果）。
    func testNotFunctionCombinedWithAndIsUnsupported() throws {
        let html = "<ul><li class='skip'>跳过</li><li>保留一</li><li>保留二</li></ul>"
        let x = try AnalyzeByXPath(html)
        let r = try x.getStringList("//li[not(@class='skip') and position()=2]/text()")
        XCTAssertEqual(r, [], "真实 JsoupXpath 不支持 not()+and 组合，应返回空")
    }

    // MARK: - 三、string()
    //
    // ⚠️ 与 Kotlin 已知差异（已用 golden 对照真实 JsoupXpath 2.5.3 验证）：
    // 尽管 JsoupXpath 官方文档未明确排除 string()，但实测它完全不被支持
    // （顶层调用与谓词内比较均不生效，真实结果为空/未命中）。本移植对齐该行为：
    // 不解析 string()，遇到时抛不支持语法，由上层吞异常返回空值。

    func testStringFunctionOnElementIsUnsupported() throws {
        // 顶层 string() 解析即失败（抛错），对齐 Kotlin getString 不吞异常的真实行为
        // （Kotlin `getResult(rule)?.let{}` 的 `?.` 只处理 null，不捕获异常）。
        let html = "<div id='x'>纯文本值</div>"
        let x = try AnalyzeByXPath(html)
        XCTAssertThrowsError(try x.getString("string(//div[@id='x'])"))
    }
    func testStringFunctionOnAttrIsUnsupported() throws {
        let html = "<div id='x'>纯文本值</div>"
        let x = try AnalyzeByXPath(html)
        XCTAssertThrowsError(try x.getString("string(//div/@id)"))
    }
    func testStringFunctionInPredicateIsUnsupported() throws {
        // 真实 JsoupXpath 对谓词内 string() 比较是硬性解析失败（而非"解析通过但不命中"），
        // 本项目对齐：抛 RuleEngineError.invalidXPath。
        let html = "<div id='x'>纯文本值</div>"
        let x = try AnalyzeByXPath(html)
        XCTAssertThrowsError(try x.getStringList("//div[string(@id)='x']/text()")) { error in
            guard case RuleEngineError.invalidXPath = error else {
                return XCTFail("应抛 RuleEngineError.invalidXPath，实际：\(error)")
            }
        }
    }

    // MARK: - 四、count()

    func testCountFunctionOnList() throws {
        let html = "<ul><li>1</li><li>2</li><li>3</li></ul>"
        let x = try AnalyzeByXPath(html)
        XCTAssertEqual(try x.getString("count(//li)"), "3")
    }
    func testCountFunctionZeroWhenNoMatch() throws {
        let html = "<ul><li>1</li></ul>"
        let x = try AnalyzeByXPath(html)
        XCTAssertEqual(try x.getString("count(//nonexist)"), "0")
    }
    // ⚠️ 与 Kotlin 已知差异（已用 golden 对照真实 JsoupXpath 2.5.3 验证）：
    // count() 顶层调用可用（上面两个用例），但谓词内比较 `[count(...)=n]` 不生效。
    func testCountFunctionInPredicateIsUnsupported() throws {
        let html = "<ul id='u'><li>1</li><li>2</li><li>3</li></ul>"
        let x = try AnalyzeByXPath(html)
        let r = try x.getStringList("//ul[count(li)=3]/@id")
        XCTAssertEqual(r, [], "真实 JsoupXpath 谓词内 count() 比较不生效，应返回空")
    }

    // MARK: - 五、concat()

    func testConcatTwoAttrs() throws {
        let html = "<div data-a='甲' data-b='乙'></div>"
        let x = try AnalyzeByXPath(html)
        XCTAssertEqual(try x.getString("concat(//div/@data-a,//div/@data-b)"), "甲乙")
    }
    func testConcatWithLiteral() throws {
        let html = "<div data-a='甲' data-b='乙'></div>"
        let x = try AnalyzeByXPath(html)
        XCTAssertEqual(try x.getString("concat(//div/@data-a,'-',//div/@data-b)"), "甲-乙")
    }
    func testConcatInPredicate() throws {
        let html = "<div data-a='甲' data-b='乙'></div>"
        let x = try AnalyzeByXPath(html)
        let r = try x.getStringList("//div[concat(@data-a,@data-b)='甲乙']/@data-a")
        XCTAssertEqual(r, ["甲"])
    }

    // MARK: - 六、substring()

    func testSubstringBasic() throws {
        let html = "<p>HelloWorld</p>"
        let x = try AnalyzeByXPath(html)
        XCTAssertEqual(try x.getString("substring(//p/text(),1,5)"), "Hello")
    }
    // ⚠️ 与 Kotlin 已知差异（已用 golden 对照真实 JsoupXpath 2.5.3 验证）：
    // 两参数形式 substring(s, start)（不给长度）不被真实 JsoupXpath 支持，返回 nil；
    // 只有三参数形式可用。本移植对齐该行为。
    func testSubstringNoLengthIsUnsupported() throws {
        let html = "<p>HelloWorld</p>"
        let x = try AnalyzeByXPath(html)
        XCTAssertThrowsError(try x.getString("substring(//p/text(),6)"), "真实 JsoupXpath 不支持两参数 substring()")
    }
    func testSubstringInPredicate() throws {
        let html = "<p>HelloWorld</p>"
        let x = try AnalyzeByXPath(html)
        let r = try x.getStringList("//p[substring(text(),1,5)='Hello']/text()")
        XCTAssertEqual(r, ["HelloWorld"])
    }

    // MARK: - 七、substring-before() / substring-after()

    func testSubstringBeforeBasic() throws {
        let html = "<p>2024-01-15</p>"
        let x = try AnalyzeByXPath(html)
        XCTAssertEqual(try x.getString("substring-before(//p/text(),'-01-')"), "2024")
    }
    // ⚠️ 与 Kotlin 已知差异（已用 golden 对照真实 JsoupXpath 2.5.3 验证）：
    // W3C XPath 1.0 规范里分隔符不存在时应返回空串，但真实 JsoupXpath 返回原字符串
    // （非规范行为，是其自身实现偏差）。本移植复刻真实行为。
    func testSubstringBeforeNoMatchReturnsOriginal() throws {
        let html = "<p>2024-01-15</p>"
        let x = try AnalyzeByXPath(html)
        XCTAssertEqual(try x.getString("substring-before(//p/text(),'ZZZ')"), "2024-01-15")
    }
    func testSubstringAfterBasic() throws {
        let html = "<p>2024-01-15</p>"
        let x = try AnalyzeByXPath(html)
        XCTAssertEqual(try x.getString("substring-after(//p/text(),'2024-')"), "01-15")
    }
    func testSubstringAfterNoMatch() throws {
        let html = "<p>2024-01-15</p>"
        let x = try AnalyzeByXPath(html)
        XCTAssertEqual(try x.getString("substring-after(//p/text(),'ZZZ')"), "")
    }
    func testSubstringBeforeAfterInPredicate() throws {
        let html = "<p>2024-01-15</p>"
        let x = try AnalyzeByXPath(html)
        let r = try x.getStringList("//p[substring-after(text(),'2024-')='01-15']/text()")
        XCTAssertEqual(r, ["2024-01-15"])
    }

    // MARK: - 八、string-length()

    func testStringLengthBasic() throws {
        let html = "<p>12345</p>"
        let x = try AnalyzeByXPath(html)
        XCTAssertEqual(try x.getString("string-length(//p/text())"), "5")
    }
    func testStringLengthZeroWhenMissing() throws {
        let html = "<p>x</p>"
        let x = try AnalyzeByXPath(html)
        XCTAssertEqual(try x.getString("string-length(//nonexist)"), "0")
    }
    // ⚠️ 与 Kotlin 已知差异（已用 golden 对照真实 JsoupXpath 2.5.3 验证）：
    // string-length() 顶层调用可用（上面两个用例），但谓词内比较不生效。
    func testStringLengthInPredicateIsUnsupported() throws {
        let html = "<p>12345</p>"
        let x = try AnalyzeByXPath(html)
        let r = try x.getStringList("//p[string-length(text())=5]/text()")
        XCTAssertEqual(r, [], "真实 JsoupXpath 谓词内 string-length() 比较不生效，应返回空")
    }

    // MARK: - 九、contains()/starts-with() 的 text() / . 参数形式

    func testContainsWithTextArg() throws {
        let html = "<div><p>含有关键字的段落</p><p>无关内容</p></div>"
        let x = try AnalyzeByXPath(html)
        let r = try x.getStringList("//p[contains(text(),'关键字')]/text()")
        XCTAssertEqual(r, ["含有关键字的段落"])
    }
    func testContainsWithDotArg() throws {
        let html = "<div><p>含有关键字的段落</p><p>无关内容</p></div>"
        let x = try AnalyzeByXPath(html)
        let r = try x.getStringList("//p[contains(.,'关键字')]/text()")
        XCTAssertEqual(r, ["含有关键字的段落"])
    }
    func testStartsWithTextArg() throws {
        let html = "<div><p>前缀开始的内容</p><p>其它内容</p></div>"
        let x = try AnalyzeByXPath(html)
        let r = try x.getStringList("//p[starts-with(text(),'前缀')]/text()")
        XCTAssertEqual(r, ["前缀开始的内容"])
    }

    // MARK: - 十、多重谓词 `[...][...]`（先过滤再取位置，标准 XPath 语义）

    func testMultiPredicatePositionThenAttr() throws {
        // //li[1][@id]：先取第 1 个 li，再判断它是否有 @id
        let html = "<ul><li id='a'>1</li><li>2</li><li id='c'>3</li></ul>"
        let x = try AnalyzeByXPath(html)
        let r = try x.getStringList("//li[1][@id]/text()")
        XCTAssertEqual(r, ["1"])  // 第1个li有id -> 保留
    }
    func testMultiPredicatePositionThenAttrNoMatch() throws {
        // //li[2][@id]：第2个li没有id -> 空
        let html = "<ul><li id='a'>1</li><li>2</li><li id='c'>3</li></ul>"
        let x = try AnalyzeByXPath(html)
        let r = try x.getStringList("//li[2][@id]/text()")
        XCTAssertEqual(r, [])
    }
    func testMultiPredicateAttrThenPosition() throws {
        // //li[@id][1]：先筛选出有 @id 的 li（第1个和第3个），再取其中第1个 -> 结果是原文档的第1个li
        let html = "<ul><li>1</li><li id='b'>2</li><li id='c'>3</li></ul>"
        let x = try AnalyzeByXPath(html)
        let r = try x.getStringList("//li[@id][1]/text()")
        XCTAssertEqual(r, ["2"])  // 筛选后集合 = [li(id=b), li(id=c)]，取第1个 = li(id=b)
    }
    func testMultiPredicateAttrThenPositionSecond() throws {
        let html = "<ul><li>1</li><li id='b'>2</li><li id='c'>3</li></ul>"
        let x = try AnalyzeByXPath(html)
        let r = try x.getStringList("//li[@id][2]/text()")
        XCTAssertEqual(r, ["3"])  // 筛选后集合第2个 = li(id=c)
    }
    func testMultiPredicateDemonstratesOrderMatters() throws {
        // 用同一份 HTML 验证 [1][@id] 与 [@id][1] 语义不同（谓词顺序影响结果，标准 XPath 行为）
        let html = "<ul><li>1</li><li id='b'>2</li><li id='c'>3</li></ul>"
        let x = try AnalyzeByXPath(html)
        // [1][@id]: 先取第1个(无id的"1")，再判断有无@id -> 无 -> 空
        let r1 = try x.getStringList("//li[1][@id]/text()")
        // [@id][1]: 先筛选出有id的[2,3]，再取第1个 -> "2"
        let r2 = try x.getStringList("//li[@id][1]/text()")
        XCTAssertEqual(r1, [])
        XCTAssertEqual(r2, ["2"])
    }
    func testTriplePredicate() throws {
        let html = "<ul><li class='x' id='p1'>1</li><li class='x'>2</li><li class='x' id='p3'>3</li><li>4</li></ul>"
        let x = try AnalyzeByXPath(html)
        let r = try x.getStringList("//li[@class='x'][@id][1]/text()")
        XCTAssertEqual(r, ["1"])  // class=x 的有[1,2,3]；有id的有[1,3]；取第1个=1
    }
    func testTriplePredicateLast() throws {
        let html = "<ul><li class='x' id='p1'>1</li><li class='x'>2</li><li class='x' id='p3'>3</li><li>4</li></ul>"
        let x = try AnalyzeByXPath(html)
        let r = try x.getStringList("//li[@class='x'][@id][last()]/text()")
        XCTAssertEqual(r, ["3"])
    }
}
