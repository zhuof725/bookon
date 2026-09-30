//
//  AnalyzeByJSoupTests2.swift
//  LegadoHTMLEngineTests
//
//  AnalyzeByJSoup 单元测试（续）：&&/||/%%、空规则、无匹配、中文/emoji、
//  <?xml 输入、Element 入参、getElements/getString0、真实规则（规则真实/数据合成）。
//
//  ⚠️ 除「真实规则」小节外，本文件全部 HTML 均为合成样本，非真实数据。
//

import XCTest
@testable import LegadoBookSource
import SwiftSoup

final class AnalyzeByJSoupTests2: XCTestCase {

    // MARK: - 七、&& / || / %% 组合

    func testAndJoin() throws {
        let html = "<div class='a'>甲</div><div class='b'>乙</div>"
        let j = try AnalyzeByJSoup(html)
        let r = try j.getStringList("class.a@text&&class.b@text")
        XCTAssertEqual(r, ["甲", "乙"])
    }
    func testOrShortCircuit() throws {
        let html = "<div class='b'>乙</div>"
        let j = try AnalyzeByJSoup(html)
        // class.a 不存在 -> 空；class.b 存在 -> 短路命中
        XCTAssertEqual(try j.getStringList("class.a@text||class.b@text"), ["乙"])
    }
    func testOrFallbackString() throws {
        let html = "<div class='b'>乙</div>"
        let j = try AnalyzeByJSoup(html)
        XCTAssertEqual(try j.getString("class.a@text||class.b@text"), "乙")
    }
    func testPercentInterleave() throws {
        let html = "<div class='a'>A1</div><div class='a'>A2</div><div class='b'>B1</div>"
        let j = try AnalyzeByJSoup(html)
        let r = try j.getStringList("class.a@text%%class.b@text")
        XCTAssertEqual(r, ["A1", "B1", "A2"])
    }
    func testGetElementsAnd() throws {
        let html = "<p class='a'>1</p><p class='b'>2</p>"
        let j = try AnalyzeByJSoup(html)
        let es = try j.getElements("class.a&&class.b")
        XCTAssertEqual(es.size(), 2)
    }
    func testGetElementsOr() throws {
        let html = "<p class='b'>2</p>"
        let j = try AnalyzeByJSoup(html)
        let es = try j.getElements("class.a||class.b")
        XCTAssertEqual(es.size(), 1)
    }
    func testGetElementsPercent() throws {
        let html = "<p class='a'>1</p><p class='a'>1b</p><p class='b'>2</p>"
        let j = try AnalyzeByJSoup(html)
        let es = try j.getElements("class.a%%class.b")
        XCTAssertEqual(es.size(), 3)
    }

    // MARK: - 八、空规则 / 无匹配

    func testEmptyRuleGetStringNil() throws {
        let j = try AnalyzeByJSoup("<div>x</div>")
        XCTAssertNil(try j.getString(""))
    }
    func testEmptyRuleGetStringListEmpty() throws {
        let j = try AnalyzeByJSoup("<div>x</div>")
        XCTAssertEqual(try j.getStringList(""), [])
    }
    func testNoMatchGetStringNil() throws {
        let j = try AnalyzeByJSoup("<div>x</div>")
        XCTAssertNil(try j.getString("class.nope@text"))
    }
    func testNoMatchGetStringListEmpty() throws {
        let j = try AnalyzeByJSoup("<div>x</div>")
        XCTAssertEqual(try j.getStringList("class.nope@text"), [])
    }
    func testNoMatchGetElementsEmpty() throws {
        let j = try AnalyzeByJSoup("<div>x</div>")
        let es = try j.getElements("class.nope")
        XCTAssertEqual(es.size(), 0)
    }
    func testGetString0EmptyWhenNoMatch() throws {
        let j = try AnalyzeByJSoup("<div>x</div>")
        XCTAssertEqual(try j.getString0("class.nope@text"), "")
    }
    func testGetString0FirstOfMultiple() throws {
        let j = try AnalyzeByJSoup("<p class='a'>甲</p><p class='a'>乙</p>")
        XCTAssertEqual(try j.getString0("class.a@text"), "甲")
    }

    // MARK: - 九、中文与 emoji

    func testChineseText() throws {
        let html = "<div class='t'>中文标题：测试</div>"
        let j = try AnalyzeByJSoup(html)
        XCTAssertEqual(try j.getStringList("class.t@text"), ["中文标题：测试"])
    }
    func testEmojiText() throws {
        let html = "<div class='t'>🔥火焰 💧水滴</div>"
        let j = try AnalyzeByJSoup(html)
        XCTAssertEqual(try j.getStringList("class.t@text"), ["🔥火焰 💧水滴"])
    }
    func testEmojiInClassName() throws {
        // class 名含数字/连字符（emoji 通常不合法做 class，这里验证含 emoji 文本节点场景）
        let html = "<ul><li>🍅一</li><li>🍅二</li></ul>"
        let j = try AnalyzeByJSoup(html)
        XCTAssertEqual(try j.getStringList("tag.li@text"), ["🍅一", "🍅二"])
    }

    // MARK: - 十、<?xml 输入

    func testXMLInput() throws {
        let xml = "<?xml version=\"1.0\"?><root><item>甲</item><item>乙</item></root>"
        let j = try AnalyzeByJSoup(xml)
        XCTAssertEqual(try j.getStringList("tag.item@text"), ["甲", "乙"])
    }

    // MARK: - 十一、Element 入参（对应 Kotlin parse(doc: Element)）

    func testElementInput() throws {
        let doc = try SwiftSoup.parse("<div><p class='a'>甲</p></div>")
        guard let el = try doc.select("div").first() else { return XCTFail("select 失败") }
        let j = try AnalyzeByJSoup(el)
        XCTAssertEqual(try j.getStringList("class.a@text"), ["甲"])
    }

    // MARK: - 十二、data()（空规则时取 element.data()）

    func testEmptyElementsRuleUsesElementData() throws {
        // 注意：ruleStr 为空字符串会在 getStringList 开头直接返回 []（对齐 Kotlin
        // `if (ruleStr.isEmpty()) return textS`，不会走到这里）。
        // 要触发 `SourceRule.elementsRule.isEmpty` 分支（-> element.data()），
        // 需要 ruleStr 本身非空、但去掉 "@CSS:" 前缀后为空，如 "@CSS:" 本身。
        let html = "<script>var a=1;</script>"
        let doc = try SwiftSoup.parse(html)
        guard let script = try doc.select("script").first() else { return XCTFail("select 失败") }
        let j = try AnalyzeByJSoup(script)
        let r = try j.getStringList("@CSS:")
        XCTAssertEqual(r, ["var a=1;"])
    }

    // MARK: 回归测试：SwiftSoup getElementsByClass/getElementsByTag 弱引用缓存缺陷规避
    //
    // 背景：SwiftSoup 2.9.6 的 Element.getElementsByClass(_:) / getElementsByTag(_:) 内部用
    // 基于 Weak<Element> 的索引缓存；实测在同一 document 上连续以不同 class/tag 名调用时，
    // 第二次起会因弱引用失效返回空结果（即使目标元素确实存在）。本项目已在
    // ElementsSingle.getElementsSingle 里改用等价的 CSS 选择器（`.className` / `tagName`）
    // 规避，这里用真正会触发该缺陷的「连续两次不同 class 查询」场景做回归测试。
    func testRegressionConsecutiveClassSelectors() throws {
        let html = "<div class='a'>甲</div><div class='b'>乙</div>"
        let j = try AnalyzeByJSoup(html)
        // 依次查询 class.a 再查询 class.b：曾因 Elements.empty() 误用导致第二次查询失败，已修复。
        let r1 = try j.getStringList("class.a@text")
        let r2 = try j.getStringList("class.b@text")
        XCTAssertEqual(r1, ["甲"])
        XCTAssertEqual(r2, ["乙"])
    }
    // 同一个实例连续调用 getResultList 两次，验证第一次调用不会破坏文档供第二次调用使用。
    func testRegressionGetResultListTwiceInSequence() throws {
        let html = "<div class='a'>甲</div><div class='b'>乙</div>"
        let j = try AnalyzeByJSoup(html)
        let r1 = try j.getResultList("class.a@text")
        XCTAssertEqual(r1, ["甲"])
        let r2 = try j.getResultList("class.b@text")
        XCTAssertEqual(r2, ["乙"])
    }
    func testRegressionConsecutiveTagSelectors() throws {
        let html = "<p>P甲</p><span>S乙</span>"
        let j = try AnalyzeByJSoup(html)
        let r1 = try j.getStringList("tag.p@text")
        let r2 = try j.getStringList("tag.span@text")
        XCTAssertEqual(r1, ["P甲"])
        XCTAssertEqual(r2, ["S乙"])
    }

    // MARK: - 十三、真实规则（规则真实、数据合成）—— 🔥小说2016

    // ⚠️ 以下规则文本逐字取自 Resources/real/xiaoshuo2016_rules.json（真实书源『🔥小说2016』）。
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

    // 合成的搜索结果列表页 HTML（结构参照小说2016真实页面：li.clearfix 列表项）。
    // 注意：真实规则 ruleSearch.author 是 "@css:p:eq(2)>a@text"（第 3 个 <p> 的直接子 <a>），
    // 所以合成 HTML 里第 3 个 <p>（下标 2：name 所在 div 不算 p，故第 0 个 p 是占位，
    // 第 1 个是空白, 第 2 个是作者）必须包含一个 <a> 子元素才能匹配；已按此结构构造。
    private let xiaoshuo2016SearchHTML = """
    <html><body>
    <li class="clearfix">
      <div class="name"><a href="/book/1.html">合成书名一</a></div>
      <img src="/cover/1.jpg">
      <p>占位0</p>
      <p>占位1</p>
      <p><a>合成作者一</a></p>
      <p>最新：合成第100章</p>
      <p>玄幻</p>
      <div class="note clearfix"><p>合成简介一</p></div>
    </li>
    <li class="clearfix">
      <div class="name"><a href="/book/2.html">合成书名二</a></div>
      <img src="/cover/2.jpg">
      <p>占位0</p>
      <p>占位1</p>
      <p><a>合成作者二</a></p>
      <p>最新：合成第200章</p>
      <p>都市</p>
      <div class="note clearfix"><p>合成简介二</p></div>
    </li>
    </body></html>
    """

    func testRealRule_Xiaoshuo2016_BookList() throws {
        let rules = try loadRealRules("xiaoshuo2016_rules")
        let j = try AnalyzeByJSoup(xiaoshuo2016SearchHTML)
        let items = try j.getElements(rules["ruleSearch.bookList"]!)
        XCTAssertEqual(items.size(), 2)
    }
    func testRealRule_Xiaoshuo2016_Name() throws {
        let rules = try loadRealRules("xiaoshuo2016_rules")
        let j = try AnalyzeByJSoup(xiaoshuo2016SearchHTML)
        let items = try j.getElements(rules["ruleSearch.bookList"]!)
        let first = try AnalyzeByJSoup(items.get(0))
        XCTAssertEqual(try first.getString(rules["ruleSearch.name"]!), "合成书名一")
    }
    func testRealRule_Xiaoshuo2016_Author() throws {
        let rules = try loadRealRules("xiaoshuo2016_rules")
        let j = try AnalyzeByJSoup(xiaoshuo2016SearchHTML)
        let items = try j.getElements(rules["ruleSearch.bookList"]!)
        let first = try AnalyzeByJSoup(items.get(0))
        XCTAssertEqual(try first.getString(rules["ruleSearch.author"]!), "合成作者一")
    }
    func testRealRule_Xiaoshuo2016_BookUrl() throws {
        let rules = try loadRealRules("xiaoshuo2016_rules")
        let j = try AnalyzeByJSoup(xiaoshuo2016SearchHTML)
        let items = try j.getElements(rules["ruleSearch.bookList"]!)
        let first = try AnalyzeByJSoup(items.get(0))
        XCTAssertEqual(try first.getString(rules["ruleSearch.bookUrl"]!), "/book/1.html")
    }
    func testRealRule_Xiaoshuo2016_CoverUrl() throws {
        let rules = try loadRealRules("xiaoshuo2016_rules")
        let j = try AnalyzeByJSoup(xiaoshuo2016SearchHTML)
        let items = try j.getElements(rules["ruleSearch.bookList"]!)
        let first = try AnalyzeByJSoup(items.get(0))
        XCTAssertEqual(try first.getString(rules["ruleSearch.coverUrl"]!), "/cover/1.jpg")
    }
    func testRealRule_Xiaoshuo2016_LastChapter() throws {
        let rules = try loadRealRules("xiaoshuo2016_rules")
        let j = try AnalyzeByJSoup(xiaoshuo2016SearchHTML)
        let items = try j.getElements(rules["ruleSearch.bookList"]!)
        let first = try AnalyzeByJSoup(items.get(0))
        XCTAssertEqual(try first.getString(rules["ruleSearch.lastChapter"]!), "最新：合成第100章")
    }
    func testRealRule_Xiaoshuo2016_Intro() throws {
        let rules = try loadRealRules("xiaoshuo2016_rules")
        let j = try AnalyzeByJSoup(xiaoshuo2016SearchHTML)
        let items = try j.getElements(rules["ruleSearch.bookList"]!)
        let first = try AnalyzeByJSoup(items.get(0))
        XCTAssertEqual(try first.getString(rules["ruleSearch.intro"]!), "合成简介一")
    }
    func testRealRule_Xiaoshuo2016_Kind() throws {
        let rules = try loadRealRules("xiaoshuo2016_rules")
        let j = try AnalyzeByJSoup(xiaoshuo2016SearchHTML)
        let items = try j.getElements(rules["ruleSearch.bookList"]!)
        let first = try AnalyzeByJSoup(items.get(0))
        // .note_text,p:eq(4) —— 合成 HTML 里第5个 p 是分类段（下标从0数，p:eq(4)即第5个<p>）
        let kind = try first.getString(rules["ruleSearch.kind"]!)
        XCTAssertNotNil(kind)
    }
    func testRealRule_Xiaoshuo2016_ContentTextNodes() throws {
        // ruleContent.content 用 .articleDiv p@textNodes
        let html = "<div class='articleDiv'><p>正文第一段<br>正文第二段</p></div>"
        let rules = try loadRealRules("xiaoshuo2016_rules")
        let j = try AnalyzeByJSoup(html)
        let content = try j.getString(rules["ruleContent.content"]!)
        XCTAssertEqual(content, "正文第一段\n正文第二段")
    }
    func testRealRule_Xiaoshuo2016_SecondBook() throws {
        let rules = try loadRealRules("xiaoshuo2016_rules")
        let j = try AnalyzeByJSoup(xiaoshuo2016SearchHTML)
        let items = try j.getElements(rules["ruleSearch.bookList"]!)
        let second = try AnalyzeByJSoup(items.get(1))
        XCTAssertEqual(try second.getString(rules["ruleSearch.name"]!), "合成书名二")
        XCTAssertEqual(try second.getString(rules["ruleSearch.bookUrl"]!), "/book/2.html")
    }
}
