import Foundation

/// 运行时字段（concurrentRate / loginCheckJs / coverDecodeJs）、XPath 相对路径、正则诊断。
enum SourceRuntimeRegression {
    static func run(_ check: (Bool, String) -> Void) throws {
        // MARK: concurrentRate 解析
        let rate = SourceRateLimiter.parse
        check(rate("10/1000")?.limit == 10 && rate("10/1000")?.interval == 1_000_000_000,
              "concurrentRate：次数/毫秒")
        check(rate("800")?.limit == 1 && rate("800")?.interval == 800_000_000,
              "concurrentRate：毫秒间隔")
        check(rate("0") == nil && rate("") == nil && rate(nil) == nil, "concurrentRate：0/空不限流")

        // MARK: loginCheckJs
        var source = BookSource(bookSourceUrl: "https://login-check.example", bookSourceName: "登录检查")
        let response = HTTPResponseData(body: "unauthorized", url: "https://login-check.example/book/1", code: 401)
        source.loginCheckJs = "result.code === 401 ? 'need-login' : result"
        let rewritten = WebBook.applyLoginCheck(source: source, response: response)
        check(rewritten.body == "need-login", "loginCheckJs：返回字符串可重写正文")
        check(rewritten.code == 401, "loginCheckJs：保留原 HTTP 状态")
        source.loginCheckJs = "result"
        check(WebBook.applyLoginCheck(source: source, response: response).body == "unauthorized",
              "loginCheckJs：返回 result 原样通过")
        source.loginCheckJs = "throw new Error('boom')"
        check(WebBook.applyLoginCheck(source: source, response: response).body == "unauthorized",
              "loginCheckJs：脚本抛错时保留原响应")

        // MARK: coverDecodeJs（字节数组输入/输出）
        let bytes = SourceImageDecoder.bytes(from: [0, 255, NSNumber(value: 128), 1] as [Any])
        check(bytes == Data([0, 255, 128, 1]), "coverDecodeJs：JS 数字数组转字节")
        check(SourceImageDecoder.bytes(from: ["0": 1, "1": 2] as [String: Any]) == Data([1, 2]),
              "coverDecodeJs：数字键对象转字节")

        // MARK: callBackJs
        var callBack = BookSource(bookSourceUrl: "https://callback.example", bookSourceName: "回调")
        callBack.eventListener = true
        callBack.ruleContent = ContentRule()
        callBack.ruleContent?.callBackJs = "java.put('evt', event)"
        SourceCallBack.fire(SourceCallBack.addBookShelf, source: callBack, book: nil)
        check(RuleContext(source: callBack).get("evt") == "addBookShelf", "callBackJs：事件名传入脚本")
        var disabled = callBack
        disabled.eventListener = false
        _ = RuleContext(source: disabled).put("evt", "")
        SourceCallBack.fire(SourceCallBack.delBookShelf, source: disabled, book: nil)
        check(RuleContext(source: disabled).get("evt").isEmpty, "callBackJs：eventListener=false 不执行")

        // MARK: 网络重试（只重传输错误，不按状态码重发）
        check(AnalyzeUrl.retryableError(URLError(.timedOut)), "重试：超时可重发")
        check(AnalyzeUrl.retryableError(URLError(.networkConnectionLost)), "重试：连接被重置可重发")
        check(!AnalyzeUrl.retryableError(URLError(.userAuthenticationRequired)), "重试：鉴权错误不重发")
        check(AnalyzeUrl.idempotentMethods == ["GET", "HEAD"], "重试：只覆盖幂等方法")

        // MARK: 正则诊断
        RegexLog.reset()
        check(RegexLog.compile("[") == nil, "正则诊断：非法正则返回 nil")
        check(RegexLog.recentIssues().contains { $0.contains("正则编译失败") }, "正则诊断：记录失败原因")
        check(RegexLog.compile("\\d+") != nil, "正则诊断：合法正则正常编译")

        // MARK: XPath 相对路径（JsoupXpath 常用写法）
        let ar = AnalyzeRule(content: "<html><body></body></html>", baseUrl: "https://xpath.example/")
        let ul = """
        <ul class="list"><li class="hot" data-id="1">第一</li><li data-id="2">第二</li><li class="hot" data-id="3">第三</li></ul>
        """
        check(ar.getString("/li[2]/text()", from: ul) == "第二", "XPath：/tag[n]")
        check(ar.getString("/li[last()]/text()", from: ul) == "第三", "XPath：last()")
        check(ar.getString("/li[contains(@class,'hot')]/@data-id", from: ul) == "1\n3",
              "XPath：contains(@class)")
        check(ar.getString("/li[@data-id='2']/text()", from: ul) == "第二", "XPath：属性谓词")
        check(ar.getElements("/li/@data-id", from: ul).count == 3, "XPath：属性轴列表")
        check(ar.getString("/li[1]/@data-id", from: ul) == "1", "XPath：谓词 + 属性")
        let root = """
        <div id="root"><div class="box"><span>A</span><span>B</span></div><select><option value="v1">一</option><option value="v2">二</option></select></div>
        """
        check(ar.getString("/div/span[2]/text()", from: root) == "B", "XPath：嵌套路径")
        check(ar.getString("/select/option[2]/@value", from: root) == "v2", "XPath：option 片段")
        check(ar.getString("/option[1]/text()", from: "<option value=\"v1\">一</option>") == "一",
              "XPath：字符串片段 /text()")
        check(ar.getString("/@value", from: "<option value=\"v1\">一</option>") == "v1",
              "XPath：字符串片段 /@attr")
        let doc = AnalyzeRule(content: "<html><body>" + ul + root + "</body></html>", baseUrl: "https://xpath.example/")
        check(doc.getString("//li[last()]/text()") == "第三", "XPath：绝对路径 last()")
        check(doc.getString("//div[@id='root']//span[1]/text()") == "A", "XPath：绝对路径后代")
    }
}
