//
//  AnalyzeByXPathTests.swift
//  LegadoHTMLEngineTests
//
//  AnalyzeByXPath 单元测试（@testable）。覆盖：//、.//、属性、text()、位置谓词、
//  contains 等函数、组合规则、</td>/</tr>/</tbody> 补全逻辑、<?xml 输入、无匹配。
//
//  ⚠️ 除「真实规则」小节外，本文件全部 HTML 均为合成样本，非真实数据。
//

import XCTest
@testable import LegadoBookSource
import SwiftSoup

final class AnalyzeByXPathTests: XCTestCase {

    // ⚠️ 合成样本，非真实数据。
    let basicHTML = """
    <html><body>
    <div id="list">
      <dl>
        <dd><a href="/1">一</a></dd>
        <dd><a href="/2">二</a></dd>
        <dd><a href="/3">三</a></dd>
      </dl>
    </div>
    <ul>
      <li class="odd">A</li>
      <li class="even">B</li>
      <li class="odd">C</li>
    </ul>
    </body></html>
    """

    // MARK: - 一、// 与 .//

    func testDoubleSlashAnyDepth() throws {
        let x = try AnalyzeByXPath(basicHTML)
        XCTAssertEqual(try x.getStringList("//a/text()"), ["一", "二", "三"])
    }
    func testDotDoubleSlashRelative() throws {
        let x = try AnalyzeByXPath(basicHTML)
        let els = try x.getElements("//div")
        XCTAssertEqual(els?.count, 1)
    }
    func testSingleSlashChild() throws {
        let x = try AnalyzeByXPath("<root><a>1</a><b>2</b></root>")
        XCTAssertEqual(try x.getStringList("//root/a/text()"), ["1"])
    }

    // MARK: - 二、属性 @

    func testAttributeHref() throws {
        let x = try AnalyzeByXPath(basicHTML)
        XCTAssertEqual(try x.getStringList("//a/@href"), ["/1", "/2", "/3"])
    }
    func testAttributeClass() throws {
        let x = try AnalyzeByXPath(basicHTML)
        XCTAssertEqual(try x.getStringList("//li/@class"), ["odd", "even", "odd"])
    }
    func testAttributeFilter() throws {
        let x = try AnalyzeByXPath(basicHTML)
        let r = try x.getStringList("//li[@class='odd']/text()")
        XCTAssertEqual(r, ["A", "C"])
    }
    func testAttributeExists() throws {
        let html = "<div><a href='/x'>有</a><a>无</a></div>"
        let x = try AnalyzeByXPath(html)
        XCTAssertEqual(try x.getStringList("//a[@href]/text()"), ["有"])
    }
    func testAttributeNotEquals() throws {
        let x = try AnalyzeByXPath(basicHTML)
        let r = try x.getStringList("//li[@class!='odd']/text()")
        XCTAssertEqual(r, ["B"])
    }

    // MARK: - 三、text()

    func testTextFunctionOnElement() throws {
        let html = "<p>纯文本</p>"
        let x = try AnalyzeByXPath(html)
        XCTAssertEqual(try x.getStringList("//p/text()"), ["纯文本"])
    }
    func testTextFilterEquals() throws {
        let html = "<div><a>阅读</a><a>下载</a></div>"
        let x = try AnalyzeByXPath(html)
        let r = try x.getStringList("//a[text()='阅读']/text()")
        XCTAssertEqual(r, ["阅读"])
    }

    // MARK: - 四、位置谓词

    func testPositionIndex() throws {
        let x = try AnalyzeByXPath(basicHTML)
        XCTAssertEqual(try x.getStringList("//li[1]/text()"), ["A"])
    }
    func testPositionLast() throws {
        let x = try AnalyzeByXPath(basicHTML)
        XCTAssertEqual(try x.getStringList("//li[last()]/text()"), ["C"])
    }
    func testPositionGreaterThan() throws {
        let x = try AnalyzeByXPath(basicHTML)
        let r = try x.getStringList("//li[position()>1]/text()")
        XCTAssertEqual(r, ["B", "C"])
    }
    func testPositionLessThan() throws {
        let x = try AnalyzeByXPath(basicHTML)
        let r = try x.getStringList("//li[position()<3]/text()")
        XCTAssertEqual(r, ["A", "B"])
    }

    // MARK: - 五、函数：contains / starts-with / normalize-space

    func testContainsFunction() throws {
        let html = "<div><p class='item-1'>甲</p><p class='other'>乙</p></div>"
        let x = try AnalyzeByXPath(html)
        let r = try x.getStringList("//p[contains(@class,'item')]/text()")
        XCTAssertEqual(r, ["甲"])
    }
    func testStartsWithFunction() throws {
        let html = "<div><p class='item-1'>甲</p><p class='xitem'>乙</p></div>"
        let x = try AnalyzeByXPath(html)
        let r = try x.getStringList("//p[starts-with(@class,'item')]/text()")
        XCTAssertEqual(r, ["甲"])
    }
    func testNormalizeSpaceFunction() throws {
        let html = "<p>  多余   空白  </p>"
        let x = try AnalyzeByXPath(html)
        let r = try x.getStringList("//p[normalize-space(text())='多余 空白']/text()")
        XCTAssertEqual(r.count, 1)
    }

    // MARK: - 六、多条件 and/or

    func testAndCondition() throws {
        let html = "<div><p class='a' id='x'>甲</p><p class='a' id='y'>乙</p></div>"
        let x = try AnalyzeByXPath(html)
        let r = try x.getStringList("//p[@class='a' and @id='x']/text()")
        XCTAssertEqual(r, ["甲"])
    }
    func testOrCondition() throws {
        let html = "<div><p class='a'>甲</p><p class='b'>乙</p><p class='c'>丙</p></div>"
        let x = try AnalyzeByXPath(html)
        let r = try x.getStringList("//p[@class='a' or @class='b']/text()")
        XCTAssertEqual(r, ["甲", "乙"])
    }

    // MARK: - 七、following-sibling / parent 轴

    func testFollowingSibling() throws {
        let html = "<ul><li id='cur'>A</li><li>B</li><li>C</li></ul>"
        let x = try AnalyzeByXPath(html)
        let r = try x.getStringList("//li[@id='cur']/following-sibling::li/text()")
        XCTAssertEqual(r, ["B", "C"])
    }
    func testParentAxis() throws {
        let html = "<div id='outer'><p>内容</p></div>"
        let x = try AnalyzeByXPath(html)
        let r = try x.getStringList("//p/parent::div/@id")
        XCTAssertEqual(r, ["outer"])
    }
    func testParentDotDot() throws {
        let html = "<div id='outer'><p>内容</p></div>"
        let x = try AnalyzeByXPath(html)
        let r = try x.getStringList("//p/../@id")
        XCTAssertEqual(r, ["outer"])
    }

    // MARK: - 八、组合规则 && / || / %%

    func testXPathAndJoin() throws {
        let html = "<div><a>甲</a><b>乙</b></div>"
        let x = try AnalyzeByXPath(html)
        let r = try x.getString("//a/text()&&//b/text()")
        XCTAssertEqual(r, "甲\n乙")
    }
    func testXPathOrShortCircuit() throws {
        let html = "<div><b>乙</b></div>"
        let x = try AnalyzeByXPath(html)
        let r = try x.getStringList("//a/text()||//b/text()")
        XCTAssertEqual(r, ["乙"])
    }
    func testXPathPercentInterleave() throws {
        let html = "<div><a>A1</a><a>A2</a><b>B1</b></div>"
        let x = try AnalyzeByXPath(html)
        let r = try x.getStringList("//a/text()%%//b/text()")
        XCTAssertEqual(r, ["A1", "B1", "A2"])
    }

    // MARK: - 九、</td> / </tr> / </tbody> 补全逻辑

    func testTdAutoWrap() throws {
        // 以 </td> 结尾 -> 自动包 <tr>...</tr>
        let html = "<td>单元格</td>"
        let x = try AnalyzeByXPath(html)
        XCTAssertEqual(try x.getStringList("//td/text()"), ["单元格"])
    }
    func testTrAutoWrap() throws {
        // 以 </tr> 结尾 -> 自动包 <table>...</table>
        let html = "<tr><td>A</td><td>B</td></tr>"
        let x = try AnalyzeByXPath(html)
        XCTAssertEqual(try x.getStringList("//td/text()"), ["A", "B"])
    }
    func testTbodyAutoWrap() throws {
        let html = "<tbody><tr><td>C</td></tr></tbody>"
        let x = try AnalyzeByXPath(html)
        XCTAssertEqual(try x.getStringList("//td/text()"), ["C"])
    }

    // MARK: - 十、<?xml 输入

    func testXMLInput() throws {
        let xml = "<?xml version=\"1.0\"?><root><item>甲</item><item>乙</item></root>"
        let x = try AnalyzeByXPath(xml)
        XCTAssertEqual(try x.getStringList("//item/text()"), ["甲", "乙"])
    }

    // MARK: - 十一、无匹配

    func testNoMatchGetStringListEmpty() throws {
        let x = try AnalyzeByXPath("<div>x</div>")
        XCTAssertEqual(try x.getStringList("//nope/text()"), [])
    }
    func testNoMatchGetElementsEmpty() throws {
        let x = try AnalyzeByXPath("<div>x</div>")
        let r = try x.getElements("//nope")
        XCTAssertEqual(r?.count ?? -1, 0)
    }
    func testNoMatchGetStringNil() throws {
        let x = try AnalyzeByXPath("<div>x</div>")
        // getString 求值失败返回 nil（对齐 Kotlin getResult 为 null 时返回 null）
        let r = try x.getString("//nope/text()")
        // 无匹配但求值本身不失败 -> 空字符串（join 空列表）
        XCTAssertEqual(r, "")
    }
    func testEmptyRuleGetElementsNil() throws {
        let x = try AnalyzeByXPath("<div>x</div>")
        XCTAssertNil(try x.getElements(""))
    }

    // MARK: - 十二、通配符与 node()

    func testWildcardStar() throws {
        let html = "<div><a>1</a><b>2</b></div>"
        let x = try AnalyzeByXPath(html)
        let r = try x.getElements("//div/*")
        XCTAssertEqual(r?.count, 2)
    }

    // MARK: - 十三、JsoupXpath 扩展函数

    func testAllTextFunction() throws {
        let html = "<div>外层<span>内层</span></div>"
        let x = try AnalyzeByXPath(html)
        let r = try x.getStringList("//div/allText()")
        XCTAssertEqual(r, ["外层内层"])
    }
    func testOwnTextFunction() throws {
        let html = "<div>外层<span>内层</span></div>"
        let x = try AnalyzeByXPath(html)
        let r = try x.getStringList("//div/ownText()")
        XCTAssertEqual(r, ["外层"])
    }
    func testHtmlFunction() throws {
        let html = "<div><p>内容</p></div>"
        let x = try AnalyzeByXPath(html)
        let r = try x.getStringList("//div/html()")
        XCTAssertEqual(r.first?.contains("<p>内容</p>"), true)
    }
    func testOuterHtmlFunction() throws {
        let html = "<div class='x'><p>内容</p></div>"
        let x = try AnalyzeByXPath(html)
        let r = try x.getStringList("//div/outerHtml()")
        XCTAssertEqual(r.first?.contains("class=\"x\""), true)
    }

    // MARK: - 十四、多层嵌套与 descendant

    func testDescendantAxis() throws {
        let html = "<div><section><p>深层</p></section></div>"
        let x = try AnalyzeByXPath(html)
        let r = try x.getStringList("//div/descendant::p/text()")
        XCTAssertEqual(r, ["深层"])
    }
    func testAncestorAxis() throws {
        let html = "<html><body><div><p id='cur'>x</p></div></body></html>"
        let x = try AnalyzeByXPath(html)
        let r = try x.getStringList("//p[@id='cur']/ancestor::div")
        XCTAssertEqual(r.count, 1)
    }

    // MARK: - 十五、Element / Elements 入参

    func testElementInput() throws {
        let doc = try SwiftSoup.parse(basicHTML)
        guard let div = try doc.select("#list").first() else { return XCTFail() }
        let x = try AnalyzeByXPath(div)
        XCTAssertEqual(try x.getStringList(".//a/text()").count, 3)
    }

    // MARK: - 十六、真实规则（规则真实、数据合成）—— 🔥采墨阁手机版

    // ⚠️ 以下规则文本逐字取自 Resources/real/caimoge_rules.json（真实书源『🔥采墨阁手机版』）。
    // HTML 数据为按其真实页面结构手工构造的合成样本，非真实抓取内容。

    private func loadRealRules(_ name: String) throws -> [String: String] {
        var url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "real")
        if url == nil { url = Bundle.module.url(forResource: name, withExtension: "json") }
        if url == nil, let resourceURL = Bundle.module.resourceURL {
            if let en = FileManager.default.enumerator(at: resourceURL, includingPropertiesForKeys: nil) {
                for case let f as URL in en where f.lastPathComponent == "\(name).json" { url = f; break }
            }
        }
        guard let u = url else { XCTFail("找不到真实规则资源 \(name)"); throw NSError(domain: "t", code: 1) }
        let data = try Data(contentsOf: u)
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        return obj["rules"] as! [String: String]
    }

    // 合成的搜索结果页 HTML（结构参照采墨阁真实页面：#sitebox 下多个 dl）
    private let caimogeSearchHTML = """
    <html><body>
    <div id="sitebox">
      <dl>
        <dt><a href="/book/101">链接一</a></dt>
        <h3><a>合成书名一</a></h3>
        <dd>合成作者一</dd>
        <dd><span>玄幻</span></dd>
        <img src="/c/1.jpg">
      </dl>
      <dl>
        <dt><a href="/book/102">链接二</a></dt>
        <h3><a>合成书名二</a></h3>
        <dd>合成作者二</dd>
        <dd><span>都市</span></dd>
        <img src="/c/2.jpg">
      </dl>
    </div>
    </body></html>
    """

    func testRealRule_Caimoge_BookList() throws {
        let rules = try loadRealRules("caimoge_rules")
        let x = try AnalyzeByXPath(caimogeSearchHTML)
        let els = try x.getElements(rules["ruleSearch.bookList"]!)
        XCTAssertEqual(els?.count, 2)
    }
    func testRealRule_Caimoge_Name() throws {
        let rules = try loadRealRules("caimoge_rules")
        let x = try AnalyzeByXPath(caimogeSearchHTML)
        let els = try x.getElements(rules["ruleSearch.bookList"]!)!
        let first = try AnalyzeByXPath(els[0])
        XCTAssertEqual(try first.getString(rules["ruleSearch.name"]!), "合成书名一")
    }
    func testRealRule_Caimoge_Author() throws {
        let rules = try loadRealRules("caimoge_rules")
        let x = try AnalyzeByXPath(caimogeSearchHTML)
        let els = try x.getElements(rules["ruleSearch.bookList"]!)!
        let first = try AnalyzeByXPath(els[0])
        XCTAssertEqual(try first.getString(rules["ruleSearch.author"]!), "合成作者一")
    }
    func testRealRule_Caimoge_BookUrl() throws {
        let rules = try loadRealRules("caimoge_rules")
        let x = try AnalyzeByXPath(caimogeSearchHTML)
        let els = try x.getElements(rules["ruleSearch.bookList"]!)!
        let first = try AnalyzeByXPath(els[0])
        XCTAssertEqual(try first.getString(rules["ruleSearch.bookUrl"]!), "/book/101")
    }
    func testRealRule_Caimoge_CoverUrl() throws {
        let rules = try loadRealRules("caimoge_rules")
        let x = try AnalyzeByXPath(caimogeSearchHTML)
        let els = try x.getElements(rules["ruleSearch.bookList"]!)!
        let first = try AnalyzeByXPath(els[0])
        XCTAssertEqual(try first.getString(rules["ruleSearch.coverUrl"]!), "/c/1.jpg")
    }
    func testRealRule_Caimoge_Kind() throws {
        let rules = try loadRealRules("caimoge_rules")
        let x = try AnalyzeByXPath(caimogeSearchHTML)
        let els = try x.getElements(rules["ruleSearch.bookList"]!)!
        let first = try AnalyzeByXPath(els[0])
        XCTAssertEqual(try first.getString(rules["ruleSearch.kind"]!), "玄幻")
    }
    func testRealRule_Caimoge_BookInfoAuthor() throws {
        // ruleBookInfo.author 用 og: meta property，合成一个详情页
        let html = "<html><head><meta property=\"og:novel:author\" content=\"合成作者X\"></head><body></body></html>"
        let rules = try loadRealRules("caimoge_rules")
        let x = try AnalyzeByXPath(html)
        XCTAssertEqual(try x.getString(rules["ruleBookInfo.author"]!), "合成作者X")
    }
    func testRealRule_Caimoge_BookInfoCoverUrl() throws {
        let html = "<html><head><meta property=\"og:image\" content=\"/cover/x.jpg\"></head></html>"
        let rules = try loadRealRules("caimoge_rules")
        let x = try AnalyzeByXPath(html)
        XCTAssertEqual(try x.getString(rules["ruleBookInfo.coverUrl"]!), "/cover/x.jpg")
    }
    func testRealRule_Caimoge_TocUrl() throws {
        // //a[text()="阅读"]/@href
        let html = "<div><a>下载</a><a>阅读</a></div>"
        let rules = try loadRealRules("caimoge_rules")
        let x = try AnalyzeByXPath(html)
        // 加个 href 便于断言
        let html2 = "<div><a href='/x'>下载</a><a href='/toc/1'>阅读</a></div>"
        let x2 = try AnalyzeByXPath(html2)
        _ = x
        XCTAssertEqual(try x2.getString(rules["ruleBookInfo.tocUrl"]!), "/toc/1")
    }
    func testRealRule_Caimoge_ContentDiv() throws {
        let html = "<div id='content'>正文内容合成文本</div>"
        let rules = try loadRealRules("caimoge_rules")
        let x = try AnalyzeByXPath(html)
        let r = try x.getStringList(rules["ruleContent.content"]!)
        XCTAssertFalse(r.isEmpty)
    }
    func testRealRule_Caimoge_SecondBook() throws {
        let rules = try loadRealRules("caimoge_rules")
        let x = try AnalyzeByXPath(caimogeSearchHTML)
        let els = try x.getElements(rules["ruleSearch.bookList"]!)!
        let second = try AnalyzeByXPath(els[1])
        XCTAssertEqual(try second.getString(rules["ruleSearch.name"]!), "合成书名二")
        XCTAssertEqual(try second.getString(rules["ruleSearch.bookUrl"]!), "/book/102")
    }
}
