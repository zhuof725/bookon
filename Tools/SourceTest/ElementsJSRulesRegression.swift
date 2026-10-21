import Foundation

/// 规则 JS 里的「元素集合」语义回归。
///
/// 原版(Rhino)里，**元素规则**（bookList/chapterList 这类 list 规则）的 JS 段拿到的是
/// Elements 集合，书源普遍写：
///   result.select('a').toArray()  /  result[0].outerHtml()  /  result.size()  /  result.attr('href')
/// 之前我们把元素结果摊平成字符串数组，脚本里 `result.toArray is not a function` 直接报错，
/// 导致一批书源（完本小说网、笔趣阁biquge365 等）目录解析失败。
enum ElementsJSRulesRegression {
    static func run(_ check: (Bool, String) -> Void) {
        let html = """
        <html><body>
        <ol id="c"><li><a href="/b/1.html">第一章</a></li><li><a href="/b/2.html">第二章</a></li></ol>
        </body></html>
        """
        let ar = AnalyzeRule(content: html, baseUrl: "https://example.invalid/", context: RuleContext())

        // 完本小说网的目录规则形态：元素规则 + JS 段（用 result.select(...).toArray() 重组）+ JSON 尾段
        let rule = """
        ol > li
        <js>
        JSON.stringify(result.select('a').toArray().map(e => ({url: e.attr('href'), title: e.text()})))
        </js>
        $[*]
        """
        let nodes = ar.getElements(rule)
        check(nodes.count == 2, "规则 JS：result.select(...).toArray() 重组出 2 条（Rhino Elements 语义）")
        if nodes.count == 2 {
            let first = nodes[0] as? [String: Any] ?? [:]
            let second = nodes[1] as? [String: Any] ?? [:]
            check(first["url"] as? String == "/b/1.html", "规则 JS：重组出的地址正确")
            check(second["title"] as? String == "第二章", "规则 JS：重组出的标题正确")
        }

        // 集合方法：size / length / 下标 / text / attr
        let probe = """
        ol > li > a
        <js>
        JSON.stringify([{n: result.size(), len: result.length, first: result[0].outerHtml(),
                         href: result.attr('href'), text: result.text()}])
        </js>
        $[*]
        """
        let probeNodes = ar.getElements(probe)
        var probeDict: [String: Any] = [:]
        if let first = probeNodes.first as? [String: Any] { probeDict = first }
        check(probeDict["n"] as? Int == 2, "规则 JS：result.size() 可用")
        check(probeDict["len"] as? Int == 2, "规则 JS：result.length 可用")
        check((probeDict["first"] as? String)?.contains("/b/1.html") == true, "规则 JS：result[0].outerHtml() 可用")
        check(probeDict["href"] as? String == "/b/1.html", "规则 JS：result.attr('href') 可用")
        check((probeDict["text"] as? String)?.contains("第一章") == true, "规则 JS：result.text() 可用")

        // src 始终是字符串（当前内容原文）
        check(ar.getString("<js>typeof src</js>") == "string", "规则 JS：src 是字符串")
        check(ar.getString("<js>src.indexOf('第二章') > 0</js>") == "true", "规则 JS：src 是当前内容原文")

        // JSON 规则的结果仍是普通数组，不受元素集合改动影响
        let json = "{\"list\":[{\"t\":\"甲\"},{\"t\":\"乙\"}]}"
        let jar = AnalyzeRule(content: json, baseUrl: "https://example.invalid/", context: RuleContext())
        check(jar.getString("$.list[0].t") == "甲", "JSON 规则取值不变")
        check(jar.getStringList("$.list[*].t") == ["甲", "乙"], "JSON 规则结果仍是数组")
        check(jar.getStringList("$.list[*].t\n<js>result.length</js>").first == "2", "JSON 规则结果仍是数组（JS 段可见 length）")
        check(jar.getStringList("$.list[*].t\n<js>result.toArray().length</js>").first == "2", "JSON 规则结果也能 toArray()")
    }
}
