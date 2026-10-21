import Foundation
import SwiftSoup

/// 引擎兼容面回归：书源脚本常用的 Java/Rhino/jQuery 风格 API 必须存在且可用。
///
/// 这些都是批量校验失败日志里真实出现过的报错：
/// - `java.getElements(...).isEmpty is not a function`（Java List 语义）
/// - `Can't find variable: importClass`（Rhino 导入类）
/// - `Packages.org.jsoup.nodes.Document`（jsoup 类型判断）
/// - `J.select('.note').eq is not a function`（jQuery 风格）
enum EngineCompatRegression {
    static func run(_ check: (Bool, String) -> Void) {
        // Java List 语义：java.getElements / java.getStringList 返回的数组要能 isEmpty/toArray/size/get
        check(JSEngine.shared.evalString("java.getStringList('x').isEmpty()") == "true",
              "java.getStringList(...).isEmpty() 可用（Java List 语义）")
        check(JSEngine.shared.evalString("java.getElements('x').isEmpty()") == "true",
              "java.getElements(...).isEmpty() 可用（Java List 语义）")
        check(JSEngine.shared.evalString("java.getStringList('x').toArray().length") == "0",
              "java.getStringList(...).toArray() 可用")
        check(JSEngine.shared.evalString("java.getElements('x').size()") == "0",
              "java.getElements(...).size() 可用")

        // Rhino 导入：importClass / importPackage 要是全局函数
        check(JSEngine.shared.evalString("typeof importClass") == "function", "importClass 是全局函数")
        check(JSEngine.shared.evalString("typeof importPackage") == "function", "importPackage 是全局函数")
        check(JSEngine.shared.evalString("typeof Packages.org.jsoup.nodes.Document") == "function",
              "Packages.org.jsoup.nodes.Document 可用")

        // jQuery 风格：eq / first / last / each / hasClass
        let html = """
        <html><body><ul class="note"><li class="a">一</li><li class="b">二</li></ul>
        <div class="x"><img src="/i.png" class="detail-list-lock"></div></body></html>
        """
        let ar = AnalyzeRule(content: html, baseUrl: "https://example.invalid/", context: RuleContext())
        let eqRule = """
        ul.note@li
        <js>
        JSON.stringify([{t: result.eq(0).text(), f: result.first().text(), l: result.last().text(),
                         c: result.hasClass('a')}])
        </js>
        $[*]
        """
        let eqNodes = ar.getElements(eqRule)
        var eqDict: [String: Any] = [:]
        if let first = eqNodes.first as? [String: Any] { eqDict = first }
        check(eqDict["t"] as? String == "一", "节点集合 eq(0) 可用")
        check(eqDict["f"] as? String == "一", "节点集合 first() 可用")
        check(eqDict["l"] as? String == "二", "节点集合 last() 可用")
        check(eqDict["c"] as? Bool == true, "节点集合 hasClass() 可用")

        // 纯 JS 的目录规则（星星书源）：result 是当前内容原文（不是节点对象）
        let starHTML = """
        <html><body><div class="bookshelf-list"><a href="/book/9197/abc.html">第一章</a>
        <a href="/book/9197/def.html">第二章</a><a href="/">首页</a></div></body></html>
        """
        let starAR = AnalyzeRule(content: starHTML, baseUrl: "https://example.invalid/", context: RuleContext())
        let starRule = """
        <js>
        var html=result;
        var start=html.indexOf('bookshelf-list');
        var section=start>=0?html.substring(start):'';
        JSON.stringify([{n:section.indexOf('abc')>0}])
        </js>
        $[*]
        """
        let starNodes = starAR.getElements(starRule)
        var starDict: [String: Any] = [:]
        if let first = starNodes.first as? [String: Any] { starDict = first }
        check(starDict["n"] as? Bool == true, "纯 JS 目录规则里 result 是内容原文（星星书源形态）")

        // 规则分析：JSON 元素上的裸字段名必须按 JSON 取（原版 modeQualified 的行为）
        let jsonText = "{\"bid\":123,\"ChapterName\":\"第一章\"}"
        let jsonTextAR = AnalyzeRule(content: jsonText, baseUrl: "https://example.invalid/", context: RuleContext())
        check(jsonTextAR.getString("bid") == "123", "JSON 文本上的裸字段名按 JSON 取（数字不变空）")
        check(jsonTextAR.getString("ChapterName") == "第一章", "JSON 文本上的裸字段名按 JSON 取（文本）")
        check(jsonTextAR.getString("@css:p") != nil, "@css: 前缀仍按 CSS 处理")

        // DOM 变更：正文规则常见的 box.select("script").remove() / .addClass()
        let domRule = """
        <js>
        var doc = org.jsoup.Jsoup.parse('<div class="c"><script>x</script><p>正文</p></div>');
        var box = doc.select('div.c');
        box.select('script, style').remove();
        box.addClass('cleaned');
        JSON.stringify([{html: box.html(), cls: box.attr('class')}])
        </js>
        $[*]
        """
        let domNodes = ar.getElements(domRule)
        var domDict: [String: Any] = [:]
        if let first = domNodes.first as? [String: Any] { domDict = first }
        let domHTML = domDict["html"] as? String ?? ""
        check(!domHTML.contains("<script"), "节点集合 remove() 移除元素")
        check(domHTML.contains("正文"), "remove() 之后正文仍在")
        check((domDict["cls"] as? String ?? "").contains("cleaned"), "节点集合 addClass() 生效")

        // 规则尾部的 ##正则##替换 跟在 JS 段后面：正则不能留在 JS 脚本里
        // （否则 JavaScriptCore 直接报 “Invalid character: '#'”）
        let tailRule = ".a@text@js:result + '123'##(\\d+)##[$1]"
        check(ar.getString(tailRule) == "一[123]", "JS 段尾部的 ##正则##替换 拆成独立替换步骤")
        let listTailRule = "ul.note > li@js:result.map(function(e){return e.text();}).join(',')##,##_"
        let listTailNodes = ar.getElements(listTailRule)
        var listTailText = ""
        if let element = listTailNodes.first as? Element { listTailText = (try? element.text()) ?? "" }
        check(listTailText == "一_二", "列表规则尾部的 ##正则##替换 生效")
    }
}
