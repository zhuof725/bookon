import Foundation
import SwiftSoup

/// Offline fixtures only. Run on a host with Swift, JavaScriptCore and SwiftSoup.
/// This file deliberately does not register itself in the shared test runner.
enum JSBridgeRegression {
    static func run(_ check: (Bool, String) -> Void) {
        let original = "<main><h1>Original</h1><a href='/old'>Old</a></main>"
        let replacement = "<main><h1>Replacement</h1><a href='/new'>New</a><a href='/next'>Next</a></main>"
        let explicit = "<section><h1>Explicit</h1><a href='/explicit'>Other</a></section>"
        let baseURL = "https://example.invalid/books/index.html"
        let context = RuleContext()
        let library = "var bridgeLibraryValue = 'library';"
        let rule = AnalyzeRule(content: original, baseUrl: baseURL,
                               jsLib: library, context: context)
        let engine = JSEngine.shared

        let siblingsHTML = "<div id=\"box\"><p class=\"n\">一</p><p class=\"n\">二</p><p class=\"n\">三</p></div>"

        func evaluate(_ script: String) -> Any? {
            engine.eval(script, result: original, baseUrl: baseURL,
                        vars: ["replacementHTML": replacement, "explicitHTML": explicit,
                               "siblingsHTML": siblingsHTML],
                        jsLib: library, rule: rule, ruleInput: rule.content,
                        context: context)
        }
        check(evaluate("""
            var before = java.getString('@css:h1@text');
            var beforeCount = java.getElements('@css:a').length;
            java.setContent(replacementHTML);
            [before, beforeCount, java.getString('@css:h1@text'),
             java.getElements('@css:a').length,
             java.getElement('@css:a').text(), result === replacementHTML].join('|');
            """) as? String == "Original|1|Replacement|2|New|true",
              "setContent switches both string and element queries and preserves result assignment")

        check(evaluate("""
            java.setContent(replacementHTML);
            [java.getString('@css:h1@text', explicitHTML),
             java.getString('@css:h1@text'),
             java.getElements('@css:a').length].join('|');
            """) as? String == "Explicit|Replacement|2",
              "explicit content is queried without replacing current content")

        check(evaluate("""
            [java.getString('@css:h1@text', ''),
             java.getString('@css:h1@text', null),
             java.getString('@css:h1@text', undefined),
             java.getString('@css:h1@text')].join('|');
            """) as? String == "|||Original",
              "only omitted content falls back; empty, null and undefined are explicit empty input")

        check(evaluate("""
            var parsed = Packages.org.jsoup.Jsoup.parse(explicitHTML);
            [parsed.select('h1').text(), parsed.select('a').size(),
             parsed.select('a').get(0).attr('href'),
             parsed.text().indexOf('<') === -1,
             org.jsoup === Packages.org.jsoup,
             org.jsoup.Jsoup.parse(replacementHTML).select('h1').text(),
             java.getString('@css:h1@text')].join('|');
            """) as? String == "Explicit|1|/explicit|true|true|Replacement|Original",
              "Jsoup parses supplied HTML, exposes org alias and does not query or replace original root")

        check(evaluate("""
            java.setContent(org.jsoup.Jsoup.parse(replacementHTML));
            [java.getString('@css:h1@text'),
             java.getString('@css:h1@text', org.jsoup.Jsoup.parse(explicitHTML)),
             java.getString('@css:h1@text')].join('|');
            """) as? String == "Replacement|Explicit|Replacement",
              "native document arguments support current and explicit content")

        check(evaluate("java.setContent(replacementHTML); java.getString('@css:h1@text')") as? String == "Replacement",
              "first evaluation observes its replacement")
        check(evaluate("java.getString('@css:h1@text')") as? String == "Original",
              "second evaluation on same engine and analyzer starts from original content")
        check(rule.getString("@css:h1@text") == "Original",
              "setContent does not mutate supplied analyzer root")

        check(evaluate("""
            java.put('bridgeRegressionValue', 'kept');
            java.setContent(replacementHTML);
            [baseUrl, bridgeLibraryValue, java.get('bridgeRegressionValue'),
             java.getString('@css:a@abs:href', explicitHTML)].join('|');
            """) as? String == "https://example.invalid/books/index.html|library|kept|https://example.invalid/explicit",
              "content switching retains base URL, library and RuleContext")
        check(context.get("bridgeRegressionValue") == "kept",
              "java.put continues writing the supplied RuleContext")

        check(engine.eval("boundAtLibraryLoad", result: original, baseUrl: baseURL,
                          vars: ["key": "fixture"],
                          jsLib: "var boundAtLibraryLoad = [java.getString('@css:h1@text'), baseUrl, key].join('|');",
                          rule: rule, context: context) as? String
              == "Original|https://example.invalid/books/index.html|fixture",
              "query and request bindings are installed before jsLib execution")

        check(engine.evalString("java.setContent('<h1>Standalone</h1>'); java.getString('@css:h1@text')",
                                result: original, baseUrl: baseURL) == "Standalone",
              "content bridge also works without an explicit AnalyzeRule")
        check(engine.evalString("java.getString('@css:h1@text')", result: original,
                                baseUrl: baseURL) == "Original",
              "standalone evaluations do not share content state")

        let returnedNode = evaluate("org.jsoup.Jsoup.parse(explicitHTML).select('section').get(0)")
        check(returnedNode is Element, "JS node return is unwrapped to a native SwiftSoup Element")
        check(returnedNode.map { rule.getString("@css:h1@text", from: $0) } == "Explicit",
              "returned native node remains queryable by AnalyzeRule")

        let returnedList = evaluate("org.jsoup.Jsoup.parse(replacementHTML).select('a')") as? [Any]
        check(returnedList?.count == 2 && returnedList?.allSatisfy { $0 is Element } == true,
              "JS node-list return is unwrapped to native elements")
        check(returnedList?.first.map { rule.getString("text", from: $0) } == "New",
              "native list entry remains queryable by AnalyzeRule")

        let returnedArray = evaluate("org.jsoup.Jsoup.parse(replacementHTML).select('a').toArray()") as? [Any]
        check(returnedArray?.count == 2 && returnedArray?.allSatisfy { $0 is Element } == true,
              "JS array return recursively unwraps node wrappers")

        let pipeline = rule.getElements("@js:org.jsoup.Jsoup.parse('<article><h1>Pipeline</h1></article>').select('article')")
        check(pipeline.count == 1 && pipeline.first is Element,
              "AnalyzeRule JS pipeline receives native elements")
        check(pipeline.first.map { rule.getString("@css:h1@text", from: $0) } == "Pipeline",
              "subsequent rule query uses the JS-returned document rather than original response")

        // Legado 书源脚本常用顶层 return 结束（发现/登录脚本）；求值必须能执行并拿到返回值。
        check(engine.evalString("var a = 2;\nreturn 'r' + a;", jsLib: library, context: context) == "r2",
              "顶层 return 脚本可执行并返回结果")
        // 括号/字符串/属性里的 return 不是顶层 return，不能改变包裹方式。
        check(engine.evalString("var f = function(){ return 'x' }; f()", jsLib: library, context: context) == "x",
              "函数体内的 return 不触发函数体包裹")
        check(engine.evalString("var s = 'a return b'; s", jsLib: library, context: context) == "a return b",
              "字符串里的 return 不触发函数体包裹")
        check(engine.evalString("var list = [1,2,3];\nreturn list;", jsLib: library, context: context) == "1\n2\n3",
              "顶层 return 数组按多值返回")
        // 顶层 return 脚本的副作用仍要落在同一脚本上下文的变量上。
        check(engine.evalString("var q = 5; return q * 2;", jsLib: library, context: context) == "10",
              "顶层 return 脚本内语句先于 return 执行")
        // 没有 return 的脚本保持原有「最后一个表达式即结果」语义。
        check(engine.evalString("var z = 7; z + 1", jsLib: library, context: context) == "8",
              "无 return 的脚本仍按完成值返回")
        // 大灰狼书源：详情简介脚本读 book.readConfig.useReplaceRule 并调用 book.setUseReplaceRule(false)，
        // 缺这两个成员会让整段脚本抛错、简介只剩半截。
        check(engine.evalString("String(book.readConfig.useReplaceRule) + '|' + String(book.setUseReplaceRule(false))",
                                jsLib: library, context: context) == "false|",
              "book 暴露 readConfig 与 setUseReplaceRule，脚本不再抛错")
        check(engine.evalString("String(book.readConfig == null)", jsLib: library, context: context) == "false",
              "book.readConfig 默认可读")

        // 平台探测：书源用它区分运行环境。
        //   苹果  -> try { java.deviceID(); return '苹果' } catch {}
        //   改版  -> try { if (typeof java.reLoginView === 'function') return '改版' } catch {}
        //   轻阅读 -> try { java.qread(); return '轻阅读' } catch {}
        // 三者只有「苹果」分支会输出 <div rs-native><comment onPress=...>（可点段评）。
        // 所以普通规则 JS 里必须：有 deviceID、没有 reLoginView、没有 qread。
        check(engine.evalString("""
            var env = (function(){
                try { java.qread(); return '轻阅读'; } catch (e) {}
                try { if (typeof java.reLoginView === 'function') return '改版'; } catch (e) {}
                try { java.deviceID(); return '苹果'; } catch (e) {}
                if (typeof source.loginUi === 'function') return '安卓';
                return '未知';
            })();
            return env;
            """, jsLib: library, context: context) == "苹果",
              "普通规则 JS 的平台探测应判定为「苹果」（有 deviceID，无 reLoginView/qread）")
        check(engine.evalString("typeof java.qread", jsLib: library, context: context) == "undefined",
              "java.qread 不存在：书源用它探测「轻阅读」，提供会让分支错乱")
        check(engine.evalString("typeof java.reLoginView", jsLib: library, context: context) == "undefined",
              "普通规则 JS 里没有 java.reLoginView（Legado 只在登录弹窗作用域提供）")

        // jQuery 风格的 next()/prev()：书源里常写 `select('.item').next().text()`
        // 遍历兄弟节点。这两条路径用的是不同的桥（JSNodeBridge 单体 vs
        // JSNodeListBridge 集合），实现各自独立，必须分别覆盖。
        // 注意：java.getElements 的 JS 绑定只接受一个参数，第二个 content 参数
        // 会被静默忽略——必须先用 setContent 切换内容再查询。
        check(evaluate("""
            java.setContent(siblingsHTML);
            var list = java.getElements('@css:p.n');
            [list.first().next().text(), list.last().prev().text(),
             list.eq(1).next().text(), list.eq(0).prev() == null].join('|');
            """) as? String == "二|二|三|true",
              "集合 next/prev 按兄弟节点前进后退，首元素 prev 为 null")

        // 空集合是真实风险点：`elements.first` 为 nil 时，`try? ...?.nextElementSibling()`
        // 是双重可选链，必须安全退化成 null；如果被误当成元素构造，JS 侧会拿到
        // 一个「存在但什么都取不到」的假节点，书源就会静默拿到空正文。
        check(evaluate("""
            java.setContent(siblingsHTML);
            var empty = java.getElements('@css:nothing-here');
            [empty.length, empty.first() == null, empty.next() == null, empty.prev() == null].join('|');
            """) as? String == "0|true|true|true",
              "空集合的 first/next/prev 返回 null，不构造假节点")
    }
}
