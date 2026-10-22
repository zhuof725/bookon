import Foundation

/// 登录表单：loginUi 解析、字段顺序/类型、已保存值优先、loginUrl 分类、脚本执行与 toast。离线。
enum LoginFormRegression {
    private static func src(_ extra: [String: Any]) throws -> BookSource {
        var o: [String: Any] = ["bookSourceUrl": "https://login-form.invalid", "bookSourceName": "form"]
        for (k, v) in extra { o[k] = v }
        return try JSONDecoder().decode(BookSource.self, from: JSONSerialization.data(withJSONObject: o))
    }

    static func run(_ check: (Bool, String) -> Void) throws {
        let ui = "[{name:'账号',type:'text',default:'u0'},{name:'密码',type:'password'},{name:'登录',type:'button',action:'go()'},{name:'官网',type:'button',action:'https://a.invalid/'},]"
        let f = SourceLoginForm.parseFields(ui)
        check(f.map(\.name) == ["账号", "密码", "登录", "官网"], "登录表单：字段保持原顺序（宽松 JSON）")
        check(f.map(\.kind) == [.text, .password, .button, .button], "登录表单：type 映射")
        check(f[0].defaultValue == "u0" && f[2].action == "go()", "登录表单：default 与 action")

        // 并排布局：style.layout_flexBasisPercent 0.45 与其他项同排，1 或缺失独占整行。
        let grid = SourceLoginForm.parseFields("""
        [{name:'邮箱',type:'text'},{name:'密码',type:'password'},\
        {name:'登录',type:'button',action:'a()',style:{layout_flexGrow:1,layout_flexBasisPercent:0.45}},\
        {name:'注册',type:'button',action:'b()',style:{layout_flexBasisPercent:0.45}},\
        {name:'单独',type:'button',action:'c()',style:{layout_flexBasisPercent:1}},\
        {name:'宽',type:'button',action:'d()'},\
        {name:'左',type:'button',action:'e()',style:{layout_flexBasisPercent:0.45}},\
        {name:'右',type:'button',action:'f()',style:{layout_flexBasisPercent:0.45}}]
        """)
        check(grid.count == 8 && grid[2].basisPercent < 1 && grid[2].basisPercent > 0,
              "登录表单：并排比例被解析")
        let rows = SourceLoginForm.layoutRows(grid)
        check(rows.map { $0.map(\.name) } == [["邮箱"], ["密码"], ["登录", "注册"], ["单独"], ["宽"], ["左", "右"]],
              "登录表单：按并排比例分行且保持顺序")
        check(SourceLoginForm.layoutRows([]).isEmpty, "登录表单：空表单没有行")
        let odd = SourceLoginForm.parseFields("[{name:'a',type:'button',style:{layout_flexBasisPercent:0.45}}]")
        check(SourceLoginForm.layoutRows(odd).map { $0.map(\.name) } == [["a"]],
              "登录表单：落单的并排项自占一行（整行拉伸）")
        check(SourceLoginForm.layoutRows([
            LoginField(id: 0, name: "t", kind: .text, defaultValue: "", action: ""),
            LoginField(id: 1, name: "b", kind: .button, defaultValue: "", action: "", basisPercent: 0.45)
        ]).map { $0.map(\.name) } == [["t"], ["b"]],
              "登录表单：输入框与按钮互不并排")
        check(SourceLoginForm.parseFields("").isEmpty && SourceLoginForm.parseFields("not json").isEmpty
              && SourceLoginForm.parseFields("{\"a\":1}").isEmpty && SourceLoginForm.parseFields(nil).isEmpty, "登录表单：非法或空输入得到空表单")
        check(SourceLoginForm.parseFields("[{type:'text'},{name:'x'}]").map(\.name) == ["x"], "登录表单：缺 name 的项被忽略")

        let vals = SourceLoginForm.initialValues(fields: f, saved: ["账号": "saved"])
        check(vals["账号"] == "saved" && vals["密码"] == "" && vals["登录"] == nil, "登录表单：已保存值优先于 default，按钮不取值")
        check(SourceLoginForm.encode(["b": "2", "a": "1"]) == "{\"a\":\"1\",\"b\":\"2\"}", "登录表单：保存 JSON 键有序")

        // 开关（type:'toggle'）：番茄聚合这类面板书源用开关控制段评/章评/播放器等。
        // 没有 toggle 类型时它会退化成输入框 —— 用户看到的是能敲字的方框，不是开关。
        let toggleUI = "[{name:'段评开关',type:'toggle',chars:['🔳','✅'],default:'🔳',action:'toggleParaComments()'},"
            + "{name:'播放器开关',type:'toggle',chars:['🔳','✅'],default:'✅'},{name:'账号',type:'text'}]"
        let tf = SourceLoginForm.parseFields(toggleUI)
        check(tf.map(\.kind) == [.toggle, .toggle, .text], "登录表单：toggle 认成开关而不是输入框")
        check(tf[0].options == ["🔳", "✅"], "登录表单：开关的 chars 作为开/关文字")
        check(tf[0].toggleValue(on: true) == "✅" && tf[0].toggleValue(on: false) == "🔳",
              "登录表单：开关写回 chars 里的文字（书源 login() 按 '✅' 判断开）")
        check(tf[0].toggleIsOn(value: "✅") && !tf[0].toggleIsOn(value: "🔳"), "登录表单：按值判断开关状态")
        check(tf[1].toggleIsOn(value: nil) && tf[1].toggleIsOn(value: ""),
              "登录表单：没有已保存值时按 default 判断开关状态")
        check(!tf[0].toggleIsOn(value: nil), "登录表单：default 为关时开关是关的")
        let tvals = SourceLoginForm.initialValues(fields: tf, saved: [:])
        check(tvals["段评开关"] == "🔳" && tvals["播放器开关"] == "✅", "登录表单：开关的默认值进入表单值")
        check(tvals["账号"] == "", "登录表单：开关与输入框一起进入表单值")

        // 确认按钮要调用书源的 login()（表单值写进源变量全靠这一步），但只在真有该函数时调。
        check(SourceLoginForm.hasLoginFunction("function login(){return 1}"), "登录表单：识别 login() 函数")
        check(SourceLoginForm.hasLoginFunction("var login = function(){}"), "登录表单：识别 login = function")
        check(SourceLoginForm.hasLoginFunction("window.login = function(){}"), "登录表单：识别 window.login")
        check(!SourceLoginForm.hasLoginFunction("// 这里只是登录页的注释"), "登录表单：注释里提到 login 不算有 login()")
        check(!SourceLoginForm.hasLoginFunction("function loginPage(){}"), "登录表单：loginPage 不算 login()")
        check(!SourceLoginForm.hasLoginFunction(nil) && !SourceLoginForm.hasLoginFunction(""), "登录表单：没有脚本时没有 login()")

        // <js> 形式的 loginUi 需要先求值
        let jsUi = "<js>JSON.stringify([{name:'检查',type:'button',action:'check()'}])</js>"
        let resolved = SourceLoginForm.resolveUiText(jsUi) { JSEngine.shared.evalString($0) }
        check(SourceLoginForm.parseFields(resolved).map(\.name) == ["检查"], "登录表单：<js> 形式的 loginUi 先求值再解析")
        check(SourceLoginForm.resolveUiText("[{name:'a'}]") { _ in nil } == "[{name:'a'}]", "登录表单：普通文本原样返回")

        // loginUrl 分类
        check(SourceLoginForm.loginScript("function login(){}") != nil, "loginUrl：函数库被识别为脚本")
        check(SourceLoginForm.loginScript("https://a.invalid/login") == nil && SourceLoginForm.loginScript("/") == nil, "loginUrl：网址和路径不是脚本")
        let web = try src(["loginUrl": "https://a.invalid/login"])
        let rel = try src(["loginUrl": "/user/login"])
        let none = try src([:])
        let uiOnly = try src(["loginUi": "[{name:'a'}]"])
        check(SourceLoginForm.loginPageURL(web) == "https://a.invalid/login", "loginUrl：绝对网址作为网页登录")
        check(SourceLoginForm.loginPageURL(rel) == "https://login-form.invalid/user/login", "loginUrl：相对路径按书源地址补全")
        check(SourceLoginForm.hasLogin(web) && SourceLoginForm.hasLogin(uiOnly) && !SourceLoginForm.hasLogin(none), "登录入口显示条件")

        // 脚本执行：toast 出口 + 读取表单保存的值 + 错误返回
        let s = try src(["bookSourceUrl": "https://login-run-\(UUID().uuidString.lowercased()).invalid"])
        var toasts: [String] = []
        ToastCenter.setHandler { toasts.append($0) }
        defer { ToastCenter.setHandler(nil) }
        let lib = "function hello(){java.toast('hi-'+source.getLoginInfoMap().user);return 'done';}function boom(){throw new Error('bad');}"
        JSEngine.loginStore.putLoginInfo(s.bookSourceUrl, SourceLoginForm.encode(["user": "u1"]))
        defer { JSEngine.loginStore.removeLoginInfo(s.bookSourceUrl) }
        if case .success(let r) = JSEngine.shared.runLoginScript(source: s, library: lib, call: "hello()") {
            check(r == "done" && toasts == ["hi-u1"], "登录脚本：执行函数、toast 出口、读到表单保存的值")
        } else { check(false, "登录脚本：执行函数") }
        if case .failure(let e) = JSEngine.shared.runLoginScript(source: s, library: lib, call: "boom()") {
            check(e.message.contains("bad"), "登录脚本：异常以 failure 返回")
        } else { check(false, "登录脚本：异常应返回 failure") }
        var opened: [String] = []
        ToastCenter.setBrowserHandler { u, _ in opened.append(u) }
        defer { ToastCenter.setBrowserHandler(nil) }
        _ = JSEngine.shared.runLoginScript(source: s, library: "function o(){java.startBrowser('https://b.invalid/','t');}", call: "o()")
        check(opened == ["https://b.invalid/"], "登录脚本：java.startBrowser 通过出口打开网址")
        // 用户后台等按钮用 startBrowserAwait 打开页面：http(s) 必须真的跳转，
        // 不能退化成一次静默请求（那样的页面用户根本看不到）。
        opened.removeAll()
        _ = JSEngine.shared.runLoginScript(source: s,
            library: "function uc(){java.startBrowserAwait('https://c.invalid/user_center','用户中心');}",
            call: "uc()")
        check(opened == ["https://c.invalid/user_center"], "登录脚本：startBrowserAwait 的 http 地址跳转内置浏览器")
        opened.removeAll()
        _ = JSEngine.shared.runLoginScript(source: s,
            library: "function uc2(){java.startBrowserAwait('data:text/html;base64,PGgxPjQ8L2gxPg==','本地页',false);}",
            call: "uc2()")
        // 含遇見书源：loginUi 是 `@js: result = YuJianLoginUi(this)`，而 YuJianLoginUi 定义在
        // loginUrl（登录函数库）里。求值 loginUi 必须同时加载 loginUrl，否则 Can't find variable。
        let fixtures = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Tools/SourceTest/Fixtures")
        let yujianURL = fixtures.appendingPathComponent("yujian-source.json")
        let yujian = try JSONDecoder().decode(BookSource.self, from: Data(contentsOf: yujianURL))
        let yjUI = SourceLoginForm.resolveUiText(yujian.loginUi) { js in
            JSEngine.shared.evalString(js, jsLib: yujian.jsLib,
                                       loginLib: SourceLoginForm.loginScript(yujian.loginUrl),
                                       context: RuleContext(source: yujian))
        }
        let yjFields = SourceLoginForm.parseFields(yjUI)
        check(yjFields.count == 12 && yjFields.allSatisfy { $0.kind == .button },
              "含遇見登录界面：loginUi 脚本依赖 loginUrl 函数库求值（12 个按钮）")
        check(yjFields.contains { $0.name.contains("同步登入狀態") }
              && yjFields.contains { $0.name.contains("開啟網頁登入") },
              "含遇見登录界面：网页登录/同步按钮被解析出来")
        // 只加载 jsLib 不加载 loginUrl 时应当失败（这正是这次的真实现象）。
        let yjBroken = SourceLoginForm.resolveUiText(yujian.loginUi) { js in
            JSEngine.shared.evalString(js, jsLib: yujian.jsLib, context: RuleContext(source: yujian))
        }
        check(SourceLoginForm.parseFields(yjBroken).isEmpty,
              "含遇見登录界面：缺 loginUrl 函数库时求值失败（与修复前一致）")

        check(opened.isEmpty, "登录脚本：startBrowserAwait 的 data 页仍走请求通道，不当作网页跳转")

        // 含遇見书源登录脚本用到的桥：java.upLoginData / java.reLoginView / java.webViewCookieManager
        var savedJSON: String?
        ToastCenter.setHandler { _ in }
        JSEngine.loginStore.putLoginInfo(s.bookSourceUrl, SourceLoginForm.encode(["old": "1"]))
        defer { JSEngine.loginStore.removeLoginInfo(s.bookSourceUrl) }
        let bridgeLib = """
        function saveMap(){java.upLoginData({username:'u',readerToken:'t',n:3});java.reLoginView();return source.getLoginInfoMap().username;}
        function saveHashMap(){var m=new Packages.java.util.HashMap();m.put('k','v');java.upLoginData(m);return source.getLoginInfoMap().k;}
        function cookieWrite(){var cm=java.webViewCookieManager();cm.setCookie('https://login-run.invalid/','reader.token=abc; path=/; max-age=2592000');
            cm.getInstance().setCookie('https://login-run.invalid/','tmp=1; Max-Age=0');return java.webViewCookieManager().getInstance().getCookie('https://login-run.invalid/');}
        """
        if case .success(let r) = JSEngine.shared.runLoginScript(source: s, library: bridgeLib, call: "saveMap()") {
            savedJSON = JSEngine.loginStore.getLoginInfo(s.bookSourceUrl)
            check(r == "u" && savedJSON?.contains("\"username\":\"u\"") == true && savedJSON?.contains("\"old\":\"1\"") == true,
                  "登录桥：upLoginData 合并进登录信息且不覆盖已有键、reLoginView 可调用")
        } else { check(false, "登录桥：upLoginData + reLoginView 执行成功") }
        if case .success(let r) = JSEngine.shared.runLoginScript(source: s, library: bridgeLib, call: "saveHashMap()") {
            check(r == "v", "登录桥：upLoginData 接受 java.util.HashMap 写法")
        } else { check(false, "登录桥：HashMap 写法执行成功") }
        if case .success(let r) = JSEngine.shared.runLoginScript(source: s, library: bridgeLib, call: "cookieWrite()") {
            check(r.contains("reader.token=abc") && !r.contains("tmp=1"), "登录桥：webViewCookieManager 写入/过期删除 Cookie")
        } else { check(false, "登录桥：webViewCookieManager 执行成功") }
    }
}
