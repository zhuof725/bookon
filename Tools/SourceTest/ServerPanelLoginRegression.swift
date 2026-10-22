import Foundation

/// 重生聚合（chongsheng.dpdns.org）这类「服务器聚合」书源的登录面板适配回归。离线：
/// 面板由 loginUi 脚本求值得到，登录走 /auth/login（账号密码）或 APIKey（写 Cookie），
/// 面板按钮依赖 source.refreshExplore / java.postDelayed 等桥，且面板会随变量重绘。
enum ServerPanelLoginRegression {
    private static func src(_ extra: [String: Any]) throws -> BookSource {
        var o: [String: Any] = [
            "bookSourceUrl": "https://chongsheng.dpdns.org",
            "bookSourceName": "重生聚合",
            "jsLib": "var SRV_BASE='https://chongsheng.dpdns.org';function srvBase(){return SRV_BASE;}",
            "loginUrl": """
            function srvP_keep(){try{java.put('syState',JSON.stringify({aggMode:'fanqie'}));}catch(e){}return true;}
            function srvP_activateClick(){
              var opts=JSON.stringify({method:'POST',body:JSON.stringify({username:'u',password:'p'}),headers:{'Content-Type':'application/json'}});
              var raw=String(java.ajax('https://chongsheng.dpdns.org/auth/login',opts));
              java.upLoginData({'账号':'u','已登录':'1'});
              return raw;
            }
            function srvP_userCenter(){java.startBrowser('https://chongsheng.dpdns.org/panel','用户中心');return true;}
            function srvP_webPage(w){java.showBrowser('https://chongsheng.dpdns.org/src/'+w,null,'pre');return true;}
            function srvP_saveKey(){cookie.setCookie('https://chongsheng.dpdns.org','loomproxy_apikey=lp_x; path=/');return true;}
            function srvKindPage(k){java.put('syState',JSON.stringify({aggKind:String(k||'')}));source.refreshExplore();return true;}
            function srvPanel(){return [{name:'登录',type:'button',action:'srvP_activateClick()'}];}
            """,
            "loginUi": "@js:JSON.stringify(srvPanel())"
        ]
        for (k, v) in extra { o[k] = v }
        return try JSONDecoder().decode(BookSource.self, from: JSONSerialization.data(withJSONObject: o))
    }

    static func run(_ check: (Bool, String) -> Void) throws {
        // 面板 loginUi 依赖 loginUrl 里的函数：与含遇見书源同一条路径。
        let source = try src([:])
        let text = SourceLoginForm.resolveUiText(source.loginUi) { js in
            JSEngine.shared.evalString(js, jsLib: source.jsLib,
                                       loginLib: SourceLoginForm.loginScript(source.loginUrl),
                                       context: RuleContext(source: source))
        }
        let fields = SourceLoginForm.parseFields(text)
        check(fields.count == 1 && fields[0].name == "登录" && fields[0].kind == .button,
              "服务器聚合书源：loginUi 脚本面板被解析出来")

        // 真实书源（重生聚合 v2.0.2）离线跑一遍：面板必须能求值出按钮，
        // 否则用户在登录页只会看到「没有可用登录配置」。
        let fixture = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Tools/SourceTest/Fixtures/chongsheng-aggregate-v2.0.2.json")
        // 导出的书源是数组；也容许单个对象。
        func decodeSource(_ data: Data) -> BookSource? {
            if let list = try? JSONDecoder().decode([BookSource].self, from: data) { return list.first }
            return try? JSONDecoder().decode(BookSource.self, from: data)
        }
        if FileManager.default.fileExists(atPath: fixture.path),
           let data = try? Data(contentsOf: fixture),
           let real = decodeSource(data) {
            let ui = SourceLoginForm.resolveUiText(real.loginUi) { js in
                JSEngine.shared.evalString(js, jsLib: real.jsLib,
                                           loginLib: SourceLoginForm.loginScript(real.loginUrl),
                                           context: RuleContext(source: real))
            }
            let realFields = SourceLoginForm.parseFields(ui)
            check(!realFields.isEmpty, "重生聚合书源：真实 loginUi 面板被解析出按钮")
            check(realFields.contains { $0.name == "账号" } && realFields.contains { $0.name == "密码" },
                  "重生聚合书源：账号/密码输入框在面板里")
            check(realFields.contains { $0.name.contains("用户中心") },
                  "重生聚合书源：用户中心按钮在面板里")
            check(realFields.contains { $0.kind == .select },
                  "重生聚合书源：select 项（气泡大小）被解析")
            check(realFields.allSatisfy { !$0.title.isEmpty },
                  "重生聚合书源：每个按钮都有显示名")
            // 面板状态行里的 ❌/✅ 文案由脚本给出，说明脚本真的跑通了。
            check(realFields.contains { $0.title.contains("尚未登录") || $0.title.contains("已登录") },
                  "重生聚合书源：面板状态行由脚本求值得到")
        } else {
            check(false, "重生聚合书源：夹具可用")
        }

        // 面板里的 select（气泡大小 / 平台）与动态按钮名（viewName）必须支持。
        let rich = SourceLoginForm.parseFields("""
        [{name:'气泡大小',type:'select',chars:['TEXT','text'],default:'text'},
         {name:'cust:tadu',viewName:"'✅ 塔读小说'",type:'button',action:"srvP_custToggle('tadu')"},
         {name:'custNone',viewName:"'🔳 全不选'",type:'button',action:'srvP_custAll(0)'}]
        """)
        check(rich[0].kind == .select && rich[0].options == ["TEXT", "text"],
              "登录表单：select 的选项被解析")
        check(rich[1].title == "✅ 塔读小说" && rich[2].title == "🔳 全不选",
              "登录表单：viewName 作为按钮显示名（去掉 JS 引号）")
        check(rich[1].name == "cust:tadu" && rich[2].name == "custNone",
              "登录表单：取值键仍是 name，不受 viewName 影响")
        check(SourceLoginForm.initialValues(fields: rich, saved: [:])["气泡大小"] == "text",
              "登录表单：select 缺省回落 default")
        check(SourceLoginForm.initialValues(fields: rich, saved: ["气泡大小": "TEXT"])["气泡大小"] == "TEXT",
              "登录表单：已保存的 select 值优先")

        // 缺失桥：java.postDelayed / java.getSource / java.openUrl / source.refreshExplore。
        let key = "https://chongsheng-run-\(UUID().uuidString.lowercased()).invalid"
        let s = try src(["bookSourceUrl": key])
        defer { JSEngine.loginStore.removeLoginInfo(key) }
        let lib = SourceLoginForm.loginScript(s.loginUrl) ?? ""
        var opened: [String] = []
        ToastCenter.setBrowserHandler { u, _, _ in opened.append(u) }
        defer { ToastCenter.setBrowserHandler(nil) }
        ToastCenter.setHandler { _ in }
        defer { ToastCenter.setHandler(nil) }

        if case .success = JSEngine.shared.runLoginScript(source: s, library: lib, call: "srvP_userCenter()") {
            check(opened == ["https://chongsheng.dpdns.org/panel"],
                  "登录桥：面板「用户中心」打开书源站点（java.startBrowser）")
        } else { check(false, "登录桥：面板「用户中心」可执行") }
        opened.removeAll()
        if case .success = JSEngine.shared.runLoginScript(source: s, library: lib, call: "srvP_webPage('help')") {
            check(opened == ["https://chongsheng.dpdns.org/src/help"],
                  "登录桥：java.showBrowser 打开使用说明页")
        } else { check(false, "登录桥：java.showBrowser 可执行") }

        // java.postDelayed：延迟回调排进 __delayedQueue，由原生在求值结束后 drain；
        // 每次 runLoginScript 都是新的 JSContext，所以调用与读取必须在同一次求值里。
        let delayedLib = """
        function later(){var seen=0;java.postDelayed(function(){seen=1;},1);return 'ok'+seen;}
        """
        if case .success(let r) = JSEngine.shared.runLoginScript(source: s, library: delayedLib, call: "later()") {
            check(r == "ok0", "登录桥：java.postDelayed 不阻塞脚本返回（回调延后执行），实际 \(r)")
        } else { check(false, "登录桥：java.postDelayed 可执行") }
        let drainLib = """
        function later2(){var seen=0;java.postDelayed(function(){seen=1;},1);
            java.put('sy_drain','');return used();}
        function used(){var v='';java.postDelayed(function(){v='done';},1);return v;}
        """
        if case .success(let r) = JSEngine.shared.runLoginScript(source: s, library: drainLib, call: "later2()") {
            check(r == "", "登录桥：延迟回调在脚本返回后才执行，实际 \(r)")
        } else { check(false, "登录桥：延迟回调可排队") }
        // 回调真正执行过：回调里写入书源变量，下次求值能读到。
        let drainRunLib = """
        function queueIt(){java.postDelayed(function(){java.put('sy_delayed','yes');},1);return 'queued';}
        """
        _ = JSEngine.shared.runLoginScript(source: s, library: drainRunLib, call: "queueIt()")
        let seenValue = JSEngine.shared.evalString("String(java.get('sy_delayed')||'')",
                                                   jsLib: s.jsLib, context: RuleContext(source: s)) ?? ""
        check(seenValue == "yes", "登录桥：java.postDelayed 的回调在脚本结束后被执行（面板刷新依赖它）")

        // source.refreshExplore()：书源刷新发现页，缺失时脚本会抛错（面板模式切换按钮全依赖它）。
        if case .success = JSEngine.shared.runLoginScript(source: s, library: lib, call: "srvKindPage('audio')") {
            check(true, "登录桥：source.refreshExplore 可调用（模式切换不再报错）")
        } else { check(false, "登录桥：source.refreshExplore 可调用") }
        check(JavaBridge.store.get("syState")?.contains("aggKind") == true
              || JSEngine.shared.evalString("String(java.get('syState')||'')",
                                            jsLib: s.jsLib, context: RuleContext(source: s))?.contains("aggKind") == true,
              "登录桥：模式切换把配置写进书源变量")

        // java.getSource()：聚合书源用 java.getSource() 兜底取 source 对象。
        let srcLib = "function hasSrc(){var o=java.getSource();return o&&o.bookSourceUrl?o.bookSourceUrl:'';}"
        if case .success(let r) = JSEngine.shared.runLoginScript(source: s, library: srcLib, call: "hasSrc()") {
            check(r == key, "登录桥：java.getSource() 返回当前书源")
        } else { check(false, "登录桥：java.getSource 可执行") }

        // 登录：java.ajax(url, 选项JSON) 的第二个参数必须生效（POST + body + headers）。
        JSEngine.loginStore.putLoginInfo(key, SourceLoginForm.encode(["账号": "u", "密码": "p"]))
        if case .success = JSEngine.shared.runLoginScript(source: s, library: lib, call: "srvP_activateClick()") {
            let saved = JSEngine.loginStore.getLoginInfo(key) ?? ""
            check(saved.contains("\"账号\":\"u\"") && saved.contains("\"已登录\":\"1\""),
                  "登录桥：upLoginData 把登录结果写回登录信息")
        } else { check(false, "登录桥：聚合书源登录脚本可执行") }

        // APIKey：写 Cookie 后下一次取数不带 api_key 参数。
        if case .success = JSEngine.shared.runLoginScript(source: s, library: lib, call: "srvP_saveKey()") {
            check(true, "登录桥：APIKey 保存脚本（cookie.setCookie）可执行")
        } else { check(false, "登录桥：APIKey 保存脚本可执行") }
    }
}
