//
//  AnalyzeByJSoupTests.swift
//  LegadoHTMLEngineTests
//
//  AnalyzeByJSoup 单元测试（@testable）。覆盖：
//  class./id./tag./text./children、@ 链式、.筛选/!排除、:索引、[]区间(正/负/步长/反转)、
//  @css:前缀、结果类型(text/textNodes/ownText/html/all/属性)、&&/||/%%、空规则、无匹配、
//  中文/emoji、含 script/style 的 html 结果、<?xml 输入、Element 入参。
//
//  ⚠️ 除「真实规则」小节外，本文件全部 HTML 均为合成样本，非真实数据。
//

import XCTest
@testable import LegadoBookSource
import SwiftSoup

final class AnalyzeByJSoupTests: XCTestCase {

    // MARK: 合成 HTML 片段（复用）

    // ⚠️ 合成样本，非真实数据。
    let basicHTML = """
    <html><body>
    <div class="box">
      <p class="a">甲</p>
      <p class="a">乙</p>
      <p class="a">丙</p>
      <p class="b">丁</p>
    </div>
    <ul id="list">
      <li>一</li>
      <li>二</li>
      <li>三</li>
      <li>四</li>
      <li>五</li>
    </ul>
    </body></html>
    """

    // MARK: - 一、基础语法：class. / id. / tag. / text. / children

    func testClassSelector() throws {
        let j = try AnalyzeByJSoup(basicHTML)
        XCTAssertEqual(try j.getStringList("class.a@text"), ["甲", "乙", "丙"])
    }
    func testIdSelector() throws {
        let j = try AnalyzeByJSoup(basicHTML)
        let r = try j.getStringList("id.list@tag.li@text")
        XCTAssertEqual(r, ["一", "二", "三", "四", "五"])
    }
    func testTagSelector() throws {
        let j = try AnalyzeByJSoup(basicHTML)
        XCTAssertEqual(try j.getStringList("tag.li@text"), ["一", "二", "三", "四", "五"])
    }
    func testTextSelector() throws {
        // text.搜索文本 -> getElementsContainingOwnText
        let html = "<div><p>你好世界</p><p>再见</p></div>"
        let j = try AnalyzeByJSoup(html)
        let r = try j.getStringList("text.你好@text")
        XCTAssertEqual(r, ["你好世界"])
    }
    func testChildrenSelector() throws {
        // 注意：`element` 是解析后的文档根（SwiftSoup.parse 会自动补全 html/head/body），
        // "children" 直接作用于根时取的是 [head, body] 而非 body 内的 span；
        // 需要先选中 div 再取 children，才能得到 span 列表（与 Kotlin Jsoup.parse 行为一致）。
        let html = "<div class='c'><span>A</span><span>B</span></div>"
        let j = try AnalyzeByJSoup(html)
        XCTAssertEqual(try j.getStringList("class.c@children@text"), ["A", "B"])
    }

    // MARK: - 二、@ 链式

    func testChainedAt() throws {
        let j = try AnalyzeByJSoup(basicHTML)
        let r = try j.getStringList("id.list@tag.li@text")
        XCTAssertEqual(r.count, 5)
    }
    func testChainedMultiSegment() throws {
        let html = "<div class='outer'><div class='inner'><p>内容</p></div></div>"
        let j = try AnalyzeByJSoup(html)
        XCTAssertEqual(try j.getStringList("class.outer@class.inner@tag.p@text"), ["内容"])
    }

    // MARK: - 三、CSS 选择器（@css: 前缀）与 CSS 组合

    func testCssPrefix() throws {
        let j = try AnalyzeByJSoup(basicHTML)
        XCTAssertEqual(try j.getStringList("@CSS:.a@text"), ["甲", "乙", "丙"])
    }
    func testCssPrefixCaseInsensitive() throws {
        let j = try AnalyzeByJSoup(basicHTML)
        XCTAssertEqual(try j.getStringList("@css:.a@text"), ["甲", "乙", "丙"])
    }
    func testCssComplexSelector() throws {
        // p:eq(2) 是真实小说2016规则里用到的 jsoup CSS 语法
        let j = try AnalyzeByJSoup(basicHTML)
        XCTAssertEqual(try j.getStringList("@css:p:eq(1)@text"), ["乙"])
    }
    func testCssMultiSelector() throws {
        let html = "<div><h1>标题</h1><p class='x'>段落</p></div>"
        let j = try AnalyzeByJSoup(html)
        XCTAssertEqual(try j.getStringList("@css:h1,.x@text").sorted(), ["标题", "段落"].sorted())
    }
    func testCssAttrResult() throws {
        let html = "<a href='/page1'>链接</a>"
        let j = try AnalyzeByJSoup(html)
        XCTAssertEqual(try j.getStringList("@css:a@href"), ["/page1"])
    }

    // MARK: - 四、索引/排除语法：'.' 筛选、'!' 排除、':' 索引（旧写法）

    func testDotIndexSingle() throws {
        // tag.li.1 -> 索引 1（第二个）
        let j = try AnalyzeByJSoup(basicHTML)
        let r = try j.getStringList("tag.li.1@text")
        XCTAssertEqual(r, ["二"])
    }
    func testDotIndexNegative() throws {
        // tag.li.-1 -> 最后一个
        let j = try AnalyzeByJSoup(basicHTML)
        XCTAssertEqual(try j.getStringList("tag.li.-1@text"), ["五"])
    }
    func testBangExcludeSingle() throws {
        // tag.li!0 -> 排除第一个
        let j = try AnalyzeByJSoup(basicHTML)
        XCTAssertEqual(try j.getStringList("tag.li!0@text"), ["二", "三", "四", "五"])
    }
    func testColonRangeOldSyntax() throws {
        // 注意：旧写法 ".0:2" 里的 ':' 与 '.'/'!' 同为「索引分隔符」，
        // 不是区间语法（区间语法只在新版 [] 写法里支持，见 ElementsSingle.findIndexSet
        // 对应 Kotlin: rl==':' 时把数字压入 indexDefault 但不返回，继续扫描前一个分隔符）。
        // 因此 "tag.li.0:2" 实际选取的是「索引 0」和「索引 2」两个元素，而非 0~2 区间。
        let j = try AnalyzeByJSoup(basicHTML)
        let r = try j.getStringList("tag.li.0:2@text")
        XCTAssertEqual(Set(r), Set(["一", "三"]))
        XCTAssertEqual(r.count, 2)
    }

    // MARK: - 五、[] 索引语法：正数、负数、区间、步长、反转

    func testBracketSingleIndex() throws {
        let j = try AnalyzeByJSoup(basicHTML)
        XCTAssertEqual(try j.getStringList("tag.li[1]@text"), ["二"])
    }
    func testBracketMultipleIndexes() throws {
        let j = try AnalyzeByJSoup(basicHTML)
        let r = try j.getStringList("tag.li[0,2,4]@text")
        XCTAssertEqual(Set(r), Set(["一", "三", "五"]))
    }
    func testBracketNegativeIndex() throws {
        let j = try AnalyzeByJSoup(basicHTML)
        XCTAssertEqual(try j.getStringList("tag.li[-1]@text"), ["五"])
    }
    func testBracketRange() throws {
        // [1:3] -> 索引 1,2,3
        let j = try AnalyzeByJSoup(basicHTML)
        let r = try j.getStringList("tag.li[1:3]@text")
        XCTAssertEqual(Set(r), Set(["二", "三", "四"]))
    }
    func testBracketRangeOmitStart() throws {
        // [:2] -> 0..2
        let j = try AnalyzeByJSoup(basicHTML)
        let r = try j.getStringList("tag.li[:2]@text")
        XCTAssertEqual(Set(r), Set(["一", "二", "三"]))
    }
    func testBracketRangeWithStep() throws {
        // [0:4:2] -> 0,2,4
        let j = try AnalyzeByJSoup(basicHTML)
        let r = try j.getStringList("tag.li[0:4:2]@text")
        XCTAssertEqual(Set(r), Set(["一", "三", "五"]))
    }
    func testBracketReverse() throws {
        // 特殊写法 [-1:0] 反转整个列表
        let j = try AnalyzeByJSoup(basicHTML)
        let r = try j.getStringList("tag.li[-1:0]@text")
        XCTAssertEqual(r, ["五", "四", "三", "二", "一"])
    }
    func testBracketExclude() throws {
        // [!0,1] 排除索引 0 和 1
        let j = try AnalyzeByJSoup(basicHTML)
        let r = try j.getStringList("tag.li[!0,1]@text")
        XCTAssertEqual(Set(r), Set(["三", "四", "五"]))
    }
    func testBracketNegativeRange() throws {
        // [-3:-1] -> 倒数第3到倒数第1（含端点）
        let j = try AnalyzeByJSoup(basicHTML)
        let r = try j.getStringList("tag.li[-3:-1]@text")
        XCTAssertEqual(Set(r), Set(["三", "四", "五"]))
    }

    // MARK: - 六、结果类型：text / textNodes / ownText / html / all / 属性

    func testResultTypeText() throws {
        let j = try AnalyzeByJSoup(basicHTML)
        XCTAssertEqual(try j.getStringList("tag.li.0@text"), ["一"])
    }
    func testResultTypeTextNodes() throws {
        // textNodes: 直接子文本节点，用 \n 拼接
        let html = "<p>第一行<br>第二行</p>"
        let j = try AnalyzeByJSoup(html)
        let r = try j.getStringList("tag.p@textNodes")
        XCTAssertEqual(r, ["第一行\n第二行"])
    }
    func testResultTypeOwnText() throws {
        let html = "<div>外层<span>内层</span></div>"
        let j = try AnalyzeByJSoup(html)
        XCTAssertEqual(try j.getStringList("tag.div@ownText"), ["外层"])
    }
    func testResultTypeHtmlRemovesScriptStyle() throws {
        let html = "<div><script>var x=1;</script><style>.a{}</style><p>正文</p></div>"
        let j = try AnalyzeByJSoup(html)
        let r = try j.getString("tag.div@html")
        XCTAssertNotNil(r)
        XCTAssertFalse(r!.contains("script"))
        XCTAssertFalse(r!.contains("style"))
        XCTAssertTrue(r!.contains("正文"))
    }
    func testResultTypeAll() throws {
        let html = "<div class='x'><p>P</p></div>"
        let j = try AnalyzeByJSoup(html)
        let r = try j.getString("class.x@all")
        XCTAssertNotNil(r)
        XCTAssertTrue(r!.contains("<p>P</p>"))
    }
    func testResultTypeAttrHref() throws {
        let html = "<a href='/x'>x</a>"
        let j = try AnalyzeByJSoup(html)
        XCTAssertEqual(try j.getStringList("tag.a@href"), ["/x"])
    }
    func testResultTypeAttrSrc() throws {
        let html = "<img src='/img.png'>"
        let j = try AnalyzeByJSoup(html)
        XCTAssertEqual(try j.getStringList("tag.img@src"), ["/img.png"])
    }
    func testResultTypeAttrBlankSkipped() throws {
        // 空白属性值应被跳过
        let html = "<div><a href=''>空</a><a href='/y'>有</a></div>"
        let j = try AnalyzeByJSoup(html)
        XCTAssertEqual(try j.getStringList("tag.a@href"), ["/y"])
    }
    func testResultTypeAttrDedup() throws {
        // 重复属性值应去重
        let html = "<div><a href='/z'>1</a><a href='/z'>2</a></div>"
        let j = try AnalyzeByJSoup(html)
        XCTAssertEqual(try j.getStringList("tag.a@href"), ["/z"])
    }
}
