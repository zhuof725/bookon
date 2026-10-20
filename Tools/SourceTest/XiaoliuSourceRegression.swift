import Foundation

/// 小六项目番茄书源（服务器聚合源）的兼容性回归。
///
/// 这个源踩到的坑都不是它自己的问题，而是我们引擎与原版的差异：
/// 1. searchUrl 里 `{{cookie.removeCookie(source.getKey())}}` 的 key 是中文书源名，
///    原版 CookieStore 按“子域名字符串”处理，不会抛错；我们之前抛 CookieError，
///    把整段 searchUrl 脚本打死，搜索变成空地址（NSURLErrorDomain -1000）。
/// 2. 登录脚本读 `cookie.getKey('fanqienovel.com','sessionid')`，传的是裸域名；
///    原版 getSubDomain 会把它当作该域名的键，我们必须补 https:// 才能命中网页登录的 Cookie。
/// 3. loginUi 的 type 写成 `button文字关闭` / `text文字关闭`，按前缀归类才是按钮/输入框。
/// 4. 源变量（source.getVariable/setVariable/putVariable）必须和编辑书源里的「源变量」共用一份存储。
enum XiaoliuSourceRegression {
    static func run(_ check: (Bool, String) -> Void) async throws {
        let fixture = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Tools/SourceTest/Fixtures/xiaoliu-fanqie-source.json")
        guard let data = try? Data(contentsOf: fixture) else {
            check(false, "小六番茄书源：夹具可用")
            return
        }
        // 导出的是数组；也容许单个对象。
        func decode(_ data: Data) -> BookSource? {
            if let list = try? JSONDecoder().decode([BookSource].self, from: data) { return list.first }
            return try? JSONDecoder().decode(BookSource.self, from: data)
        }
        guard let source = decode(data) else {
            check(false, "小六番茄书源：夹具能解码成 BookSource")
            return
        }
        check(source.bookSourceUrl == "小六项目番茄书源",
              "小六番茄书源：bookSourceUrl 确实不是 URL（中文名），实际 \(source.bookSourceUrl)")

        // MARK: 登录面板：type 带后缀也要认得出按钮

        let ui = SourceLoginForm.resolveUiText(source.loginUi) { js in
            JSEngine.shared.evalString(js, jsLib: source.jsLib,
                                       loginLib: SourceLoginForm.loginScript(source.loginUrl),
                                       context: RuleContext(source: source))
        }
        let fields = SourceLoginForm.parseFields(ui)
        check(!fields.isEmpty, "小六番茄书源：登录面板被解析出控件")
        if let queryMode = fields.first(where: { $0.name == "查询模式" }) {
            check(queryMode.kind == .button, "登录面板：button文字关闭 被当成按钮")
            check(!queryMode.action.isEmpty, "登录面板：查询模式 带可执行动作")
        } else {
            check(false, "登录面板：找到「查询模式」")
        }
        if let token = fields.first(where: { $0.name == "手动登录Token" }) {
            check(token.kind == .text, "登录面板：text文字关闭 被当成输入框")
        } else {
            check(false, "登录面板：找到「手动登录Token」")
        }

        // MARK: Cookie 桥：非 URL 不抛异常、裸域名能查到

        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        guard let jar = config.httpCookieStorage else {
            check(false, "小六番茄书源：Cookie 桥需要私有存储")
            return
        }
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        _ = jar
        let engine = JSEngine(session: session, responseTimeout: 5)

        // 关键回归：原版这里是无害的 no-op，绝不能抛 CookieError 打断脚本。
        check(engine.evalString("""
            (function(){try {
                cookie.removeCookie('小六项目番茄书源');
                cookie.setCookie('小六项目番茄书源','a=b');
                cookie.replaceCookie('小六项目番茄书源','a=b');
                return true;
            } catch(e) { return false; }})();
            """) == "true", "Cookie 桥：中文书源名作为地址不抛异常（原版是无害 no-op）")

        // 原版书源会用 key 清 Cookie，再整段拼搜索地址；异常会让地址变空。
        check(engine.evalString("""
            (function(){
                var host = 'xiaoliu-' + String(Math.random()).slice(2) + '.invalid';
                cookie.removeCookie(host);
                return 'still alive';
            })();
            """) == "still alive", "Cookie 桥：清 Cookie 后脚本继续执行")

        let bareHost = "xiaoliu-" + UUID().uuidString.lowercased() + ".invalid"
        let fullURL = "https://" + bareHost + "/reader"
        check(engine.evalString("""
            (function(u, h){
                cookie.setCookie(u, 'sessionid=abc123');
                return cookie.getKey(h, 'sessionid');
            })();
            """, vars: ["u": fullURL, "h": bareHost]) == "abc123",
              "Cookie 桥：裸域名（fanqienovel.com 这种写法）能读到整地址写入的 Cookie")

        // MARK: 源变量与「编辑书源」共用一份存储

        let varContext = RuleContext(source: source)
        _ = engine.evalString("source.setVariable('{\"module\":\"3\"}')", context: varContext)
        check(SourceVariable.get(source.bookSourceUrl) == "{\"module\":\"3\"}",
              "源变量：脚本 setVariable 与编辑书源读的是同一份存储")
        SourceVariable.set("{\"module\":\"13\"}", for: source.bookSourceUrl)
        check(engine.evalString("source.getVariable()", context: varContext) == "{\"module\":\"13\"}",
              "源变量：编辑书源保存后脚本 getVariable 立即读到新值")
        check(engine.evalString("source.putVariable('{\"module\":\"7\"}'); source.getVariable()",
                                context: varContext) == "{\"module\":\"7\"}",
              "源变量：putVariable 与 setVariable 是同一份存储（原版两者等价）")
        // 恢复夹具默认，避免影响其它用例。
        SourceVariable.set("", for: source.bookSourceUrl)
        check(engine.evalString("String(source.getVariable())", context: varContext) == "",
              "源变量：清空后脚本读到空串")

        // MARK: 搜索地址能真正生成（Cookie 不再打断脚本）

        let context = RuleContext(source: source)
        let request = AnalyzeUrl(rawUrl: source.searchUrl ?? "", key: "系统", page: 1,
                                 baseUrl: source.bookSourceUrl, sourceHeader: source.header,
                                 context: context, jsLib: source.jsLib)
        check(request.url.hasPrefix("https://fqapi.lxqteam.dpdns.org:8080/api/search?key="),
              "搜索地址由书源 JS 生成（\(request.url.prefix(70))）")
        check(request.url.contains("tab_type=3"), "搜索地址默认走小说模式 tab_type=3")
        check(request.url.contains("offset=0"), "搜索地址第一页 offset=0")
        check(request.url.contains("系统") || request.url.contains("%E7%B3%BB%E7%BB%9F"),
              "搜索地址完成关键词替换与编码")

        // 书源自己的配置：登录面板「📦初始化源变量📦」写的就是这份 JSON。
        SourceVariable.set("{\"server\":\"https://example.invalid\",\"module\":\"13\"}",
                           for: source.bookSourceUrl)
        let custom = AnalyzeUrl(rawUrl: source.searchUrl ?? "", key: "系统", page: 2,
                                baseUrl: source.bookSourceUrl, sourceHeader: source.header,
                                context: context, jsLib: source.jsLib)
        check(custom.url.hasPrefix("https://example.invalid/api/search?key="),
              "源变量里的 server 生效（\(custom.url.prefix(60))）")
        check(custom.url.contains("offset=10"), "第二页 offset 按 10 递增")
        check(custom.url.contains("short=1"), "module=13（短篇）追加 short=1")
        SourceVariable.set("", for: source.bookSourceUrl)

        // MARK: 混合规则 `$.book_id <js>base64</js> data:;base64,{{result}}`
        // 上一段 JS 返回的字符串不能被当成 HTML 文档再序列化成 <html>…（详情链接曾变成 data:;base64,<html>）。
        let mixed = "$.book_id\n<js>java.base64Encode(result)</js>\ndata:;base64,{{result}},{\"type\":\"番茄\"}"
        let item: [String: Any] = ["book_id": "7552067105378536473", "name": "慈航市"]
        let rule = AnalyzeRule(content: item, baseUrl: source.bookSourceUrl,
                               jsLib: source.jsLib, context: RuleContext(source: source))
        let bookUrl = rule.getString(mixed)
        check(bookUrl == "data:;base64,NzU1MjA2NzEwNTM3ODUzNjQ3Mw==,{\"type\":\"番茄\"}",
              "混合规则：{{result}} 取上一段 JS 的原字符串（实际 \(bookUrl.prefix(80))）")
        check(rule.getString(source.ruleSearch?.bookUrl) == bookUrl,
              "混合规则：书源真实 bookUrl 规则得到 data: 链接")
        check(rule.getString(source.ruleToc?.chapterUrl, from: ["item_id": "7552070380790219289"])
              == "data:;base64,NzU1MjA3MDM4MDc5MDIxOTI4OQ==,{\"type\":\"番茄\"}",
              "混合规则：章节链接同样得到 data: 链接")
    }
}
