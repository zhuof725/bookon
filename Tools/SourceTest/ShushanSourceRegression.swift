import Foundation

/// 聚合源（书山聚合 v5.63）兼容性回归。
///
/// 只验证离线可确定的部分：规则字段是否完整保留、书源脚本使用的 JS 接口是否都存在、
/// `@js:` 请求头与 JS 搜索地址能否解析成真实请求、以及 `book` 变量作用域。
/// 不断言任何真实接口内容，也不访问网络或登录。
enum ShushanSourceRegression {
    static func run(_ check: (Bool, String) -> Void) throws {
        let fixtures = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Tools/SourceTest/Fixtures")
        let data = try Data(contentsOf: fixtures.appendingPathComponent("shushan-aggregate-v5.63.json"))
        let text = String(decoding: data, as: UTF8.self)
        // 与 AppStore.importSources 一致：数组与单对象两种导出形式都要能解析。
        let decoded = try JSONDecoder().decode([BookSource].self, from: data)
        guard let source = decoded.first else {
            check(false, "聚合源样例可解析")
            return
        }

        check(source.bookSourceName == "📚书山聚合" && source.bookSourceUrl == "书山聚合",
              "聚合源名称与非网址标识可导入")
        check(source.jsLib?.isEmpty == false && source.searchUrl?.hasPrefix("<js>") == true,
              "聚合源保留函数库与 JS 搜索地址")
        check(source.header?.hasPrefix("@js:") == true, "聚合源请求头是 JS 规则")
        check(source.exploreUrl?.isEmpty == false && source.ruleExplore?.bookList?.hasPrefix("<js>") == true,
              "聚合源保留发现规则（本应用暂无发现入口）")
        check(source.ruleContent?.subContent != nil && source.ruleContent?.payAction != nil
              && source.ruleContent?.callBackJs != nil, "正文规则保留 subContent/payAction/callBackJs")
        check(source.ruleToc?.isPay != nil && source.ruleToc?.chapterList?.hasPrefix("<js>") == true,
              "目录规则保留 isPay 与 JS 章节列表")
        check(source.loginUi?.isEmpty == false && source.loginUrl?.isEmpty == false,
              "登录表单与登录脚本已保留")

        // 段落边界恢复对所有书源生效：无换行正文里「句末标点/闭引号 + U+3000」就是段界。
        let noNewlines = "迷迷糊糊中，林七夜做了一个梦。　梦中他回到了半年前。　“嗷！”　林七夜醒了。"
        let fixed = WebBook.normalizeParagraphBoundaries(noNewlines)
        check(fixed == "迷迷糊糊中，林七夜做了一个梦。\n梦中他回到了半年前。\n“嗷！”\n林七夜醒了。",
              "无换行正文的句末标点/闭引号全角空格还原为段落")
        // 段界还原在唯一入口对所有书源生效，函数不再接收书源，也就不存在按源名的分支。
        check(WebBook.normalizeParagraphBoundaries(noNewlines) == fixed
              && WebBook.normalizeParagraphBoundaries(fixed) == fixed,
              "段界还原与书源无关且幂等（再跑一次不再变化）")
        check(WebBook.recoverParagraphBoundaries(in: noNewlines).components(separatedBy: "\n").count == 4,
              "任意书源的同一形态正文都还原出四段")
        let normalParagraphs = "普通行内空格　仍保留，逗号后　也不拆。"
        check(WebBook.normalizeParagraphBoundaries(normalParagraphs) == normalParagraphs,
              "句中全角空格不误拆")
        let existingNewlines = "第一段。　原样保留\n第二段。　也原样保留"
        check(WebBook.normalizeParagraphBoundaries(existingNewlines) == existingNewlines,
              "已有换行且每行不足两处段界时保持原样")
        let mixedLines = "整段无换行。　仍要拆开。　这里也是。\n第二行。　只有一处段界。"
        check(WebBook.normalizeParagraphBoundaries(mixedLines) == "整段无换行。\n仍要拆开。\n这里也是。\n第二行。　只有一处段界。",
              "多行正文逐行判断：命中两处才拆，单处保持")

        let book = Book(bookUrl: "https://v1.vossc.com/book/1", name: "示例书籍", origin: source.bookSourceUrl)
        let chapter = BookChapter(url: "https://v1.vossc.com/chapter/1", title: "第一章", index: 0)
        let context = RuleContext(source: source, book: book, chapter: chapter)

        // 脚本里用到的每个 java/source/book/chapter/cache/cookie 成员都必须存在，
        // 否则书源会在运行中抛 TypeError。
        let used = members(in: text)
        check(used.count > 40, "提取到书源使用的 JS 接口清单（\(used.count) 个）")
        let probe = used.map { "if (typeof \($0) === 'undefined') missing.push('\($0)');" }.joined(separator: "\n")
        let script = "var missing=[];\n" + probe + "\nmissing.join(',')"
        let missing = JSEngine.shared.evalString(script, jsLib: source.jsLib, context: context) ?? "EVALUATION_FAILED"
        // java.deviceID 是刻意不提供的：Legado/阅读Sigma 也没有它，
        // 书源用「它不存在」来判断自己运行在 Android 分支，否则正文会被逐行包成 rs-native。
        let intentionallyAbsent: Set<String> = ["java.deviceID"]
        let missingSet = Set(missing.split(separator: ",").map(String.init))
        check(missingSet.subtracting(intentionallyAbsent).isEmpty,
              "书源使用的 JS 接口全部可用（缺失：\(missingSet.subtracting(intentionallyAbsent))）")
        check(missingSet.contains("java.deviceID"), "deviceID 属于刻意不提供的接口（书源用 try/catch 探测）")
        check(JSEngine.shared.evalString("typeof java.deviceID", jsLib: source.jsLib, context: context) == "undefined",
              "deviceID 未定义，书源判定为 Android 分支")
        let wrapped = JSEngine.shared.evalString("wrapContentForIOS.call(this, '第一行\\n第二行')",
                                                 jsLib: source.jsLib, context: context) ?? ""
        check(wrapped == "第一行\n第二行" && !wrapped.contains("rs-native"),
              "正文不再被逐行包成 rs-native div（\(wrapped.prefix(24))）")

        check(JSEngine.shared.evalString("let source = 'local'; [source, globalSource()].join('|')",
            jsLib: "function globalSource(){return source.bookSourceUrl;}", context: context) == "local|书山聚合",
            "规则局部source不改变函数库的全局source绑定")
        let items: [[String: Any]] = [
            ["title": "合成甲", "author": "测试作者", "source": "测试站", "book_url": "book-a", "cover": "", "desc": "简介"],
            ["title": "合成乙", "author": "测试作者", "source": "测试站", "book_url": "book-b", "cover": "", "desc": "简介"]
        ]
        let response = String(decoding: try JSONSerialization.data(withJSONObject: ["data": items]), as: UTF8.self)
        let books = WebBook.parseBookList(source: source, body: response, baseUrl: "https://fixture.invalid/search", rule: source.ruleSearch!)
        check(books.count == 2 && Set(books.map(\.bookUrl)).count == 2
              && books.allSatisfy { $0.bookUrl.hasPrefix("data:detailsUrl;base64,") },
              "真实搜索规则生成两个不同data详情地址，不能回退到搜索页")

        // 请求头规则必须解析成真实字段，而不是把脚本原文当字段名。
        let headers = AnalyzeUrl.headerFields(source.header, key: "斗罗大陆", page: 1,
                                              baseUrl: source.bookSourceUrl, context: context, jsLib: source.jsLib)
        check(headers["X-Novel-Token"] == "SHUSAN_READ_2025", "JS 请求头解析为 JSON 字段")
        check(headers["User-Agent"]?.isEmpty == false, "JS 请求头包含 WebView UA")
        check(headers["X-Api-Key"] != nil, "JS 请求头保留登录密钥字段（未登录为空）")
        check(!headers.keys.contains("@js:"), "请求头不把脚本原文当作字段名")

        // 完整请求构建：JS 生成地址 → 模板替换 → 合并请求头。
        let request = AnalyzeUrl(rawUrl: source.searchUrl ?? "", key: "斗罗大陆", page: 1,
                                 baseUrl: source.bookSourceUrl, sourceHeader: source.header,
                                 context: context, jsLib: source.jsLib)
        check(request.url.hasPrefix("https://v1.vossc.com/search?login=search"),
              "搜索地址由书源 JS 生成（\(request.url.prefix(60))）")
        check(request.url.contains("page=1"), "搜索地址完成页码替换")
        check(request.url.contains("斗罗大陆") || request.url.contains("%E6%96%97%E7%BD%97%E5%A4%A7%E9%99%86"),
              "搜索地址完成关键词替换与编码")
        check(request.headers["X-Novel-Token"] == "SHUSAN_READ_2025", "搜索请求携带书源自定义请求头")

        // 书源用 try/catch 探测魔改版 API，未知 Java 包必须抛错并被捕获。
        check(JSEngine.shared.evalString(
            "try{new Packages.io.legato.kazusa.utils.TimeoutCancellationException('');1}catch(e){0}",
            jsLib: source.jsLib, context: context) == "0", "未知 Java 包访问被 try/catch 捕获")

        // book 变量按书籍隔离，且不与规则变量互相覆盖。
        let bookA = Book(bookUrl: "https://v1.vossc.com/book/A", name: "甲", origin: source.bookSourceUrl)
        let bookB = Book(bookUrl: "https://v1.vossc.com/book/B", name: "乙", origin: source.bookSourceUrl)
        let contextA = RuleContext(source: source, book: bookA)
        check(JSEngine.shared.evalString("book.putVariable('custom','开启段评'); book.getVariable('custom')",
                                         context: contextA) == "开启段评", "book 变量同书可读回")
        check(JSEngine.shared.evalString("book.getVariable('custom')",
                                         context: RuleContext(source: source, book: bookA)) == "开启段评",
              "书籍变量跨上下文保留")
        check(JSEngine.shared.evalString("book.getVariable('custom')",
                                         context: RuleContext(source: source, book: bookB)) == "",
              "不同书籍不共享书籍变量")
        check(JSEngine.shared.evalString("java.put('custom','规则变量'); book.getVariable('custom')",
                                         context: contextA) == "开启段评", "规则变量与书籍变量互不覆盖")
        check(JSEngine.shared.evalString("java.put('custom','规则变量'); java.get('custom')",
                                         context: contextA) == "规则变量", "规则变量仍按作用域读写")
        check(JSEngine.shared.evalString("source.loginUi.length > 0", context: context) == "true",
              "脚本可读取书源登录界面定义")

        // 登录按钮必须有可执行脚本：脚本库常以 // 注释开头，不能当成网址路径。
        let library = SourceLoginForm.loginScript(source.loginUrl)
        check(library != nil && library!.contains("function login"),
              "注释开头的登录脚本库不会被判成网址")
        check(SourceLoginForm.isWebPath("/login"), "单行路径仍按网页登录处理")
        check(!SourceLoginForm.isWebPath(library ?? ""), "路径判定不吞掉多行脚本库")
        check(SourceLoginForm.loginScript("/login") == nil, "单行路径不当作脚本")
        check(SourceLoginForm.loginPageURL(source) == nil, "脚本库书源没有网页登录地址")

        // loginUi 里每个按钮的动作函数都应该在脚本库里；缺失时至少要有失败回传。
        var uiActions: [String] = []
        if let uiData = source.loginUi?.data(using: .utf8),
           let fields = try? JSONSerialization.jsonObject(with: uiData) as? [[String: Any]] {
            uiActions = fields.compactMap { $0["action"] as? String }
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        check(uiActions.count >= 20, "提取到登录按钮动作清单（\(uiActions.count) 个）")
        let identifierPattern = "^([A-Za-z_$][A-Za-z0-9_$]*)\\s*\\("
        let identifiers = uiActions.compactMap { action -> String? in
            guard let re = try? NSRegularExpression(pattern: identifierPattern),
                  let match = re.firstMatch(in: action, range: NSRange(action.startIndex..., in: action)),
                  let range = Range(match.range(at: 1), in: action) else { return nil }
            return String(action[range])
        }
        let typeChecks = identifiers.map { "if (typeof \($0) !== 'function') missing.push('\($0)');" }.joined(separator: "\n")
        let missingActions = JSEngine.shared.evalString("var missing=[];\n" + typeChecks + "\nmissing.join(',')",
                                                        jsLib: library, context: context) ?? ""
        check(missingActions.isEmpty, "登录按钮动作函数齐全（缺失：\(missingActions)）")
        if let first = identifiers.first, missingActions.contains(first),
           let unknownAction = uiActions.first(where: { $0.hasPrefix(first) }) {
            let call = JSEngine.shared.runLoginScript(source: source, library: library ?? "",
                                                      call: unknownAction, formValues: [:])
            if case .failure = call { check(true, "缺失动作给出失败回传") }
            else { check(false, "缺失动作必须有失败回传") }
        }
    }

    /// 提取书源文本里出现的 `命名空间.成员`，用于校验引擎接口覆盖度。
    static func members(in text: String) -> [String] {
        let pattern = "\\b(java|source|book|chapter|cache|cookie)\\.([A-Za-z_$][A-Za-z0-9_$]*)"
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        var seen = Set<String>()
        for match in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            seen.insert(ns.substring(with: match.range))
        }
        return seen.sorted()
    }
}
