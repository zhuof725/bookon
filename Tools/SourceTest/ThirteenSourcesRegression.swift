import Foundation
import SwiftSoup

/// 13 个网页书源适配的离线回归（不联网）：
/// - `class.a b` 多类名选择器（po18 目录规则 `class.lb fk@tag.li!-1`）
/// - 相对 XPath `/text()` `/@value` `/a/@href`（耽美小说目录规则）
/// - `source.key` 与 Jsoup `Elements.select` 链（群小说 searchUrl）
/// - 首访只下发会话 Cookie 的错误页识别（三八小说）
enum ThirteenSourcesRegression {
    static func run(_ check: (Bool, String) -> Void) throws {
        // 1) po18：<ul class="lb fk"> + class.lb fk@tag.li!-1
        let toc = """
        <html><body><div class="desc"><a href="/113/113652_1_1/" class="dise r2">倒序</a></div>
        <ul class="lb fk">
          <li><a href="/113/113652/29027638.html" class="xbk">死神先生</a></li>
          <li><a href="/113/113652/29027639.html" class="xbk">奇怪的客户</a></li>
          <li><a class="last tb">本页章节列表结束！</a></li>
        </ul></body></html>
        """
        let po18 = AnalyzeRule(content: toc, baseUrl: "https://m.po18co.com/113/113652/")
        let nodes = po18.getElements("class.lb fk@tag.li!-1")
        check(nodes.count == 2, "po18：class.lb fk 多类名选择 + !-1 排除末项")
        if nodes.count == 2 {
            check(po18.getString("tag.a@text", from: nodes[0]) == "死神先生", "po18：章节标题")
            check(po18.getString("tag.a@href", from: nodes[1]) == "/113/113652/29027639.html", "po18：章节地址")
        }
        check(po18.getElements("class.lb@tag.li").count == 3, "po18：单类名 class.lb 仍匹配全部 li")
        if let body = try? SwiftSoup.parse(toc).body() {
            check(AnalyzeRule.classElements(body, "lb missing").isEmpty,
                  "多类名要求同时命中，缺失的类名返回空")
        }

        // 2) 耽美小说：<option> 目录 + 相对 XPath
        let optionTOC = """
        <html><body><select name="titleselect">
        <option value="/chuanyuechongsheng/36457_0.html" selected>第一章 系统</option>
        <option value="/chuanyuechongsheng/36457_1.html">第二章 任务</option>
        </select></body></html>
        """
        let bl = AnalyzeRule(content: optionTOC, baseUrl: "https://m.blxsw.cc/chuanyuechongsheng/36457.html")
        let opts = bl.getElements("//option")
        check(opts.count == 2, "耽美小说：//option 返回 2 个节点")
        if opts.count == 2 {
            print("DEBUG option0=\(opts[0])")
            print("DEBUG option1=\(opts[1])")
            print("DEBUG text0=[\(bl.getString("/text()", from: opts[0]))]")
            print("DEBUG value1=[\(bl.getString("/@value", from: opts[1]))]")
            check(bl.getString("/text()", from: opts[0]) == "第一章 系统", "耽美小说：相对 XPath /text()")
            check(bl.getString("/@value", from: opts[1]) == "/chuanyuechongsheng/36457_1.html", "耽美小说：相对 XPath /@value")
        }
        let frag = AnalyzeRule(content: "<div></div>", baseUrl: "https://e.invalid/")
        check(frag.getString("/a/@href", from: "<div><a href=\"/a/1\">甲</a><a href=\"/a/2\">乙</a></div>") == "/a/1\n/a/2",
              "相对 XPath /a/@href 返回全部属性")
        check(frag.getString("/a[2]/text()", from: "<div><a>甲</a><a>乙</a></div>") == "乙", "相对 XPath [n] 索引")
        check(frag.getString("/a[@class='x']/@href", from: "<div><a class=\"x\" href=\"/x\">甲</a><a href=\"/y\">乙</a></div>") == "/x",
              "相对 XPath 属性谓词")
        // 绝对 XPath 不受影响
        check(frag.getString("//a/@href", from: "<div><a href=\"/a/1\">甲</a></div>") == "/a/1", "绝对 XPath //a/@href 不退化")

        // 3) 群小说 searchUrl：source.key + Jsoup Elements.select 链
        let sourceJSON = "{\"bookSourceName\":\"群小说\",\"bookSourceUrl\":\"https://www.qunxs.com\",\"bookSourceType\":0}"
        guard let sourceData = sourceJSON.data(using: .utf8),
              let qun = try? JSONDecoder().decode(BookSource.self, from: sourceData) else {
            check(false, "群小说：书源 JSON 解析")
            return
        }
        check(JSEngine.shared.evalString("source.key", context: RuleContext(source: qun)) == "https://www.qunxs.com",
              "source.key 映射 Java getKey()")
        let jsoupChain = """
        var html = '<form action="/e/search/index.php"><input name="_token" value="abc"></form>';
        var form = org.jsoup.Jsoup.parse(html).select('form');
        form.attr('action') + '|' + form.select('[name=_token]').attr('value');
        """
        check(JSEngine.shared.evalString(jsoupChain) == "/e/search/index.php|abc", "Jsoup Elements.select 链取 _token")
        let groupURL = """
        var form = org.jsoup.Jsoup.parse('<form action="/search.php"></form>').select('form');
        form.attr('action') + ',{"body":"keyword={{key}}","method":"POST"}';
        """
        let rendered = AnalyzeUrl.evalUrlJS("@js:" + groupURL, key: "测试", page: 1, baseUrl: "https://www.qunxs.com")
        check(rendered == "/search.php,{\"body\":\"keyword={{key}}\",\"method\":\"POST\"}",
              "URL 脚本结果保留待替换的 {{key}}")
        check(AnalyzeUrl.substitute(rendered, key: "测试", page: 1) == "/search.php,{\"body\":\"keyword=测试\",\"method\":\"POST\"}",
              "随后由模板替换填入关键词")

        // 4) 三八小说：首访错误页识别
        check(WebViewSupport.isSessionCookieErrorPage("<html><body>错误提示 找不到您要搜索的内容，请重新搜索！</body></html>", status: 200),
              "识别三八小说首访错误页")
        check(!WebViewSupport.isSessionCookieErrorPage("<html><body>搜索结果 共 20 本</body></html>", status: 200),
              "正常页面不触发 Cookie 重试")
        check(!WebViewSupport.isSessionCookieErrorPage("错误提示", status: 500), "非 2xx 不走 Cookie 重试")
    }
}
