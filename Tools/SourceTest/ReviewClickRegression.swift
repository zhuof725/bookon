import Foundation

/// 番茄系「知秋段评」的**点击链路**回归。
///
/// 现象：气泡显示正常、点了没反应。三个独立原因，任何一个都会让点击失效：
/// 1. 书源脚本写 `this.cache.getFromMemory(...)` / `this.source.getVariable()`。
///    Rhino 的顶层 `this` 就是全局对象，所以这两个全局必须挂到 globalThis 上；
///    只声明成局部 `var` 时，函数内的 `this` 不是全局对象 → TypeError → 什么都不发生。
/// 2. `ruleContent.imageDecode` 必须在**图片级别、并入段落之前**执行。
///    脚本要从 `src` 里正则提取 createSvg(...) 的参数来算缓存键：
///    `/createSvg2?\('(\d+)','(-?\d+)',(-?\d+),\d+,\d+\)/`。
///    传整章正文会匹配错位置，传剥掉 `,{...}` 选项的 src 会完全匹配不到。
/// 3. 脚本里的 `src` 必须是**这张图片的地址**（原版语义），不是当前内容原文。
///
/// 三个问题任一存在，点击都会静默失败（书源的 try/catch 把异常吞了）。
enum ReviewClickRegression {
    static func run(_ check: (Bool, String) -> Void) {
        // createSvg 放在 loginUrl 里：阅读器点击气泡走的正是 resolveClickURL
        // （内部加载 jsLib + loginUrl 并装 __openBrowser 捕获器）。
        let clickLib = """
        function createSvg(bid, cid, pid, count) {
          let cacheKey = `fq-${bid}-${cid}-${pid}`
          let load = this.cache.getFromMemory(cacheKey)
          if (load != '1') {
            let token = this.source.getVariable()
            if (token == '') {
              this.java.longToast('请先在【登录页】获取共享Token后使用本书源')
            } else {
              this.java.showBrowser('https://fq.example/comment/page?bid=' + bid + '&cid=' + cid + '&pid=' + pid + '&token=' + token, null, null, '{}')
            }
          }
          return 'data:image/svg+xml;base64,SVG'
        }
        """
        var source = BookSource(bookSourceUrl: "https://review-click.example",
                                bookSourceName: "段评点击回归")
        source.loginUrl = clickLib
        let ctx = RuleContext(source: source)

        // MARK: 1) this.cache / this.source 必须是全局对象

        check(JSEngine.shared.evalString("typeof this.cache === 'object' && typeof this.cache.getFromMemory === 'function'",
                                         context: RuleContext(source: source)) == "true",
              "this.cache 在函数内可用（Rhino 顶层 this = 全局对象）")
        check(JSEngine.shared.evalString("typeof this.source === 'object' && typeof this.source.getVariable === 'function'",
                                         context: RuleContext(source: source)) == "true",
              "this.source 在函数内可用")
        check(JSEngine.shared.evalString("(function(){ return this.cache.getFromMemory('__none__'); })()",
                                         context: RuleContext(source: source)) == "",
              "this.cache.getFromMemory 可调用")

        // MARK: 2+3) imageDecode 在图片级别执行，src 是图片地址

        let bid = "7320955143208307774"
        let cid = "7322565597089235518"
        let pid = 12
        let cacheKey = "fq-\(bid)-\(cid)-\(pid)"
        let rawSrc = "data:image/svg+xml;base64,,{\"style\":\"TEXT\",\"type\":\"fqpl\","
            + "\"click\":\"createSvg('\(bid)','\(cid)',\(pid),42,1700000000123)\","
            + "\"js\":\"createSvg('\(bid)','\(cid)',\(pid),42,1700000000123)\"}"
        // 书源真实的 imageDecode 规则
        let decodeRule = """
        try {
          let cinfo = src.replaceAll(" ", "").match(/createSvg2?\\('(\\d+)','(-?\\d+)',(-?\\d+),\\d+,\\d+\\)/)
          let cacheKey = `fq-${cinfo[1]}-${cinfo[2]}-${cinfo[3]}`
          cache.deleteMemory(cacheKey)
        } catch (err) {
          java.log(src + "-" + "Error:" + err)
        }
        result
        """

        // 正文解析时书源写入「已渲染」标记
        _ = JSEngine.shared.evalString("cache.putMemory('\(cacheKey)','1')", context: RuleContext(source: source))
        let marked = JSEngine.shared.evalString("cache.getFromMemory('\(cacheKey)')", context: RuleContext(source: source))
        check(marked == "1", "正文解析后写入「已渲染」标记")

        let content = "　　正文第一段。<img src=\"\(rawSrc)\">"
        let blocks = ContentBlocks.parse(content) { src in
            ImageDecodeRuntime.decode(src, rule: decodeRule, source: source, context: ctx,
                                      baseURL: "https://review-click.example")
        }
        let after = JSEngine.shared.evalString("cache.getFromMemory('\(cacheKey)')", context: RuleContext(source: source)) ?? ""
        check(after.isEmpty, "imageDecode 在图片级别清掉「已渲染」标记（实际 \(after)）")

        // 气泡的数量与点击动作仍然正确
        var count: Int?
        var click: String?
        for block in blocks {
            if case .paragraph(_, let c, let u) = block { count = c; click = u }
        }
        check(count == 42, "imageDecode 之后段评数量仍是 42（实际 \(count.map(String.init) ?? "nil")）")
        check(click?.hasPrefix("js:createSvg(") == true, "点击动作是 js:createSvg(...)")

        // MARK: 点击：执行 createSvg 应能拿到评论页地址
        //
        // 书源的 createSvg 里：标记没被清 → 直接跳过；token 为空 → 只弹提示；
        // 两者都满足才会 java.showBrowser(url)。这里模拟「已有 token」的情况。
        _ = JSEngine.shared.evalString("source.setVariable('TOKEN123')", context: RuleContext(source: source))
        if let got = JSEngine.shared.resolveClickURL(source: source,
                                                     click: "createSvg('\(bid)','\(cid)',\(pid),42,1700000000123)").url {
            check(got.contains("comment/page?bid=\(bid)"), "点击气泡能拿到评论页地址（实际 \(got)）")
        } else {
            check(false, "点击气泡能拿到评论页地址（实际 nil）")
        }

        // 标记未清时点击打不开：引擎应清掉标记后重试一次
        let key = JSEngine.reviewCacheKeys(in: "createSvg('7320955143208307774','7322565597089235518',12,42,1)")
        check(key == ["fq-7320955143208307774-7322565597089235518-12"], "从点击表达式取出「已渲染」标记键")

        // 书源脚本失败时要给出原因，不能点了没反应。
        // （番茄聚合的「本章说」就是这种：它先请求 ms.show 的 forum_id，
        //   那个接口现在对所有人 403，脚本抛错 → 页面根本打不开。）
        let broken = JSEngine.shared.resolveClickURL(source: source, click: "notExistFunction()")
        check(broken.url == nil, "脚本失败时不返回评论页地址")
        check(!(broken.error ?? "").isEmpty, "脚本失败时给出失败原因（实际 \(broken.error ?? "nil")）")

        // 书源自己的接口挂了时（番茄聚合：取 forum_id 那个 403）：
        // 第一次会因 resp.data 是 undefined 当场抛错，评论页开不了。
        // 引擎要用「宽松 JSON」重试一次，让脚本走到 showBrowser —— 页面能打开（内容空就白屏）。
        let brokenLib = """
        function openComment(){
          let resp = JSON.parse('{"Code":10010101007,"Message":"当前接口不支持通过SDK Token直接访问","Success":false}');
          let forum_id = resp['data']['forum_data']['forum_id'];
          this.java.showBrowser('https://c.invalid/viewer?forum_id=' + forum_id, null);
        }
        """
        var brokenSource = BookSource(bookSourceUrl: "https://review-broken.example", bookSourceName: "接口挂了")
        brokenSource.loginUrl = brokenLib
        let brokenResult = JSEngine.shared.resolveClickURL(source: brokenSource, click: "openComment()")
        check(brokenResult.url?.contains("c.invalid/viewer") == true,
              "书源接口挂了时用宽松 JSON 重试，评论页仍能打开（实际 \(brokenResult.url ?? "nil")）")

        // 阅读器的点击诊断要一直记着（不用先跑一次调试），方便用户反馈「点了没反应」。
        check(DebugLog.readerSnapshot().contains("≡段评"),
              "阅读器点击链路诊断一直记录（实际 \(DebugLog.readerSnapshot().isEmpty ? "空" : "有")）")
    }
}
