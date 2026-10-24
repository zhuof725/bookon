import Foundation

/// 书源批量校验（对齐原版「校验书源」）的离线断言：分组读写、注释清理、搜索/发现/详情/目录/正文
/// 各步的失效分组与消息、超时归类、取消不改写、并发上限、响应耗时。全部用注入钩子，不访问网络。
enum SourceCheckRegression {
    static func run(_ check: (Bool, String) -> Void) async {
        func makeSource(_ json: String) -> BookSource {
            guard let s = try? JSONDecoder().decode(BookSource.self, from: Data(json.utf8)) else {
                print("FAIL: 书源 JSON 构造失败")
                exit(1)
            }
            return s
        }

        // MARK: 分组与注释（与原版 BookSource 行为一致）

        var groups = makeSource(#"{"bookSourceUrl":"https://g.invalid/1","bookSourceName":"分组测试","bookSourceGroup":"玄幻,今日"}"#)
        groups.addGroup("失效A;今日")
        check(Set(groups.sourceGroupNames) == Set(["玄幻", "今日", "失效A"]),
              "addGroup 并集去重（实际 \(groups.sourceGroupNames)）")
        groups.addGroup("校验超时，失效B")
        check(Set(groups.invalidGroupNames) == Set(["失效A", "校验超时", "失效B"]),
              "invalidGroupNames 只含失效/校验超时（实际 \(groups.invalidGroupNames)）")
        groups.removeGroup("失效A")
        check(!groups.sourceGroupNames.contains("失效A") && groups.sourceGroupNames.contains("玄幻"),
              "removeGroup 只删指定分组")
        groups.removeInvalidGroups()
        check(Set(groups.sourceGroupNames) == Set(["玄幻", "今日"]),
              "removeInvalidGroups 清掉全部失效标记（实际 \(groups.sourceGroupNames)）")

        var comment = makeSource(#"{"bookSourceUrl":"https://c.invalid","bookSourceName":"注释测试","bookSourceComment":"原作者备注"}"#)
        comment.addErrorComment("搜索失效")
        comment.addErrorComment("网站失效:超时")
        check(comment.bookSourceComment == "// Error: 网站失效:超时\n\n// Error: 搜索失效\n\n原作者备注",
              "错误注释前插且保留原作者备注（实际 \(comment.bookSourceComment ?? "nil")）")
        comment.removeErrorComment()
        check(comment.bookSourceComment == "原作者备注", "清除错误注释保留普通注释")

        // MARK: 书源列表分组
        let gA = makeSource(#"{"bookSourceUrl":"https://s.invalid/a","bookSourceName":"A","bookSourceGroup":"常规,精品"}"#)
        let gB = makeSource(#"{"bookSourceUrl":"https://s.invalid/b","bookSourceName":"B"}"#)
        let gC = makeSource(#"{"bookSourceUrl":"https://s.invalid/c","bookSourceName":"C","bookSourceGroup":"常规"}"#)
        let gD = makeSource(#"{"bookSourceUrl":"https://s.invalid/d","bookSourceName":"D","bookSourceGroup":"漫画"}"#)
        let sections = BookSource.groupedSections([gA, gB, gC, gD])
        check(sections.map(\.name) == ["常规", "漫画", "默认分组"], "分组按出现顺序，默认分组在最后（实际 \(sections.map(\.name))）")
        check(sections.first?.sources.map(\.bookSourceName) == ["A", "C"], "按第一个分组名归类且保持原顺序")
        check(sections.last?.sources.map(\.bookSourceName) == ["B"], "无分组归入默认分组")

        // MARK: 关键词

        let kwCustom = makeSource(#"{"bookSourceUrl":"https://k.invalid/1","bookSourceName":"关键词","searchUrl":"https://k.invalid/s","ruleSearch":{"checkKeyWord":"自定义词"}}"#)
        check(kwCustom.checkKeyword(fallback: "我的") == "自定义词", "checkKeyWord 普通词生效")
        let kwHTTP = makeSource(#"{"bookSourceUrl":"https://k.invalid/2","bookSourceName":"关键词","ruleSearch":{"checkKeyWord":"http://x"}}"#)
        check(kwHTTP.checkKeyword(fallback: "我的") == "我的", "checkKeyWord 是链接时不使用")
        let kwOps = makeSource(#"{"bookSourceUrl":"https://k.invalid/3","bookSourceName":"关键词","ruleSearch":{"checkKeyWord":"标题::网址"}}"#)
        check(kwOps.checkKeyword(fallback: "我的") == "我的", "checkKeyWord 是发现语法时不使用")
        let kwToc = makeSource(#"{"bookSourceUrl":"https://k.invalid/4","bookSourceName":"关键词","ruleSearch":{"checkKeyWord":"++网址"}}"#)
        check(kwToc.checkKeyword(fallback: "我的") == "我的", "checkKeyWord 是目录语法时不使用")
        let kwNone = makeSource(#"{"bookSourceUrl":"https://k.invalid/5","bookSourceName":"关键词"}"#)
        check(kwNone.checkKeyword(fallback: "我的") == "我的", "没有 checkKeyWord 用默认关键词")

        var summaryOptions = SourceCheck.Options()
        check(summaryOptions.summary == "校验超时：180秒\n校验项目： 搜索 发现 详情 目录 正文",
              "设置摘要与原版文案一致（实际 \(summaryOptions.summary)）")

        // MARK: 通过源：搜索 → 详情 → 目录 → 正文

        let happy = makeSource(#"{"bookSourceUrl":"https://happy.invalid","bookSourceName":"通过源","searchUrl":"https://happy.invalid/s","ruleSearch":{"bookList":"$.[*]"},"ruleBookInfo":{"name":"$.name"},"ruleToc":{"chapterList":"$.[*]"},"ruleContent":{"content":"$.text"}}"#)
        let book = Book(bookUrl: "https://happy.invalid/b/1", name: "测试书", author: "作者", origin: "https://happy.invalid")
        let chapters = [BookChapter(url: "https://happy.invalid/c/1", title: "第1章", index: 0),
                        BookChapter(url: "https://happy.invalid/c/2", title: "第2章", index: 1)]

        var calls: [String] = []
        var keywords: [String] = []
        let liveHooks = SourceCheck.Hooks(
            search: { _, key in calls.append("search"); keywords.append(key); return [book] },
            explore: { _, _ in calls.append("explore"); return [] },
            bookInfo: { _, b in calls.append("bookInfo"); var b = b; b.tocUrl = "https://happy.invalid/toc"; return b },
            chapters: { _, _ in calls.append("chapters"); return chapters },
            content: { _, _, _, _ in calls.append("content"); return "正文内容" },
            domainReachable: { _ in calls.append("domain"); return true }
        )
        var options = SourceCheck.Options()
        options.timeout = 5
        options.concurrency = 1

        let r1 = await SourceCheck.checkOne(happy, options: options, hooks: liveHooks)
        check(r1.success && r1.message == "校验成功", "通过源整体成功（实际 \(r1.message)）")
        check(r1.groups.isEmpty && r1.group == nil, "通过源没有失效分组")
        check(calls == ["search", "bookInfo", "chapters", "content"],
              "校验顺序 搜索→详情→目录→正文（实际 \(calls)）")
        check(keywords == ["我的"], "没有 checkKeyWord 时用默认关键词发起搜索（实际 \(keywords)）")
        check(r1.respondTime >= 0 && r1.updatedSource.respondTime == r1.respondTime,
              "响应耗时写回书源")
        check(r1.updatedSource.bookSourceComment == nil, "成功源不写错误注释")

        let r1b = await SourceCheck.checkOne(kwCustom, options: options, hooks: liveHooks)
        check(r1b.success && keywords.last == "自定义词", "checkKeyWord 用于校验关键词（实际 \(keywords.last ?? "nil")）")

        var dirty = happy
        dirty.bookSourceGroup = "玄幻,搜索失效"
        dirty.bookSourceComment = "// Error: 旧的\n\n备注"
        let r2 = await SourceCheck.checkOne(dirty, options: options, hooks: liveHooks)
        check(r2.success, "带旧失效分组的源复查可恢复成功（实际 \(r2.message)）")
        check(r2.updatedSource.sourceGroupNames == ["玄幻"], "复查成功清掉旧失效分组（实际 \(r2.updatedSource.sourceGroupNames)）")
        check(r2.updatedSource.bookSourceComment == "备注", "复查成功清掉旧错误注释")

        // MARK: 各步骤失败的分组与消息

        var emptyCalls = 0
        let emptyHooks = SourceCheck.Hooks(
            search: { _, _ in emptyCalls += 1; return [] },
            explore: { _, _ in [] },
            bookInfo: { _, b in b },
            chapters: { _, _ in chapters },
            content: { _, _, _, _ in "正文" },
            domainReachable: { _ in true }
        )
        let r3 = await SourceCheck.checkOne(happy, options: options, hooks: emptyHooks)
        check(!r3.success && r3.groups == ["搜索失效"], "搜索为空记“搜索失效”（实际 \(r3.groups)）")
        check(r3.message == "校验失败:搜索失效", "失败消息是失效分组名（实际 \(r3.message)）")
        check(r3.updatedSource.bookSourceGroup == "搜索失效", "失效分组写回书源")
        check(r3.updatedSource.bookSourceComment == "// Error: 搜索失效", "失败写入错误注释")
        check(emptyCalls == 1, "搜索失败后不再继续详情")

        let noTocHooks = SourceCheck.Hooks(
            search: { _, _ in [book] }, explore: { _, _ in [] },
            bookInfo: { _, b in var b = b; b.tocUrl = "t"; return b },
            chapters: { _, _ in [] },
            content: { _, _, _, _ in "正文" },
            domainReachable: { _ in true }
        )
        let r4 = await SourceCheck.checkOne(happy, options: options, hooks: noTocHooks)
        check(!r4.success && r4.groups == ["搜索目录失效"], "目录为空记“搜索目录失效”（实际 \(r4.groups)）")

        let emptyContentHooks = SourceCheck.Hooks(
            search: { _, _ in [book] }, explore: { _, _ in [] },
            bookInfo: { _, b in var b = b; b.tocUrl = "t"; return b },
            chapters: { _, _ in chapters },
            content: { _, _, _, _ in "   " },
            domainReachable: { _ in true }
        )
        let r5 = await SourceCheck.checkOne(happy, options: options, hooks: emptyContentHooks)
        check(!r5.success && r5.groups == ["搜索正文失效"], "正文为空记“搜索正文失效”（实际 \(r5.groups)）")

        let throwContentHooks = SourceCheck.Hooks(
            search: { _, _ in [book] }, explore: { _, _ in [] },
            bookInfo: { _, b in var b = b; b.tocUrl = "t"; return b },
            chapters: { _, _ in chapters },
            content: { _, _, _, _ in throw URLError(.cannotConnectToHost) },
            domainReachable: { _ in true }
        )
        let r6 = await SourceCheck.checkOne(happy, options: options, hooks: throwContentHooks)
        check(!r6.success && r6.group == "网站失效" && r6.groups == ["网站失效"],
              "正文网络错误归“网站失效”（实际 \(r6.message)）")

        // MARK: 超时与取消

        let slowHooks = SourceCheck.Hooks(
            search: { _, _ in
                try? await Task.sleep(nanoseconds: 500_000_000)
                return [book]
            },
            explore: { _, _ in [] },
            bookInfo: { _, b in b },
            chapters: { _, _ in chapters },
            content: { _, _, _, _ in "正文" },
            domainReachable: { _ in true }
        )
        var fastOptions = options
        fastOptions.timeout = 0.15
        let timeoutStart = Date()
        let r7 = await SourceCheck.checkOne(happy, options: fastOptions, hooks: slowHooks)
        check(!r7.success && r7.group == "校验超时" && r7.groups.contains("校验超时"),
              "超时归“校验超时”（实际 \(r7.message)）")
        check(Date().timeIntervalSince(timeoutStart) < 3, "超时在限时附近返回")

        var cancelOptions = options
        cancelOptions.timeout = 5
        let running = Task { await SourceCheck.checkOne(happy, options: cancelOptions, hooks: slowHooks) }
        try? await Task.sleep(nanoseconds: 80_000_000)
        running.cancel()
        let r8 = await running.value
        check(r8.cancelled, "用户停止：结果标记已取消（实际 \(r8.message)）")
        check(r8.updatedSource.sourceGroupNames == happy.sourceGroupNames, "取消不改写分组")
        check(r8.updatedSource.bookSourceComment == happy.bookSourceComment, "取消不写错误注释")
        check(r8.updatedSource.respondTime == happy.respondTime, "取消不写响应耗时")

        // MARK: 发现分支

        let discSource = makeSource(#"{"bookSourceUrl":"https://d.invalid","bookSourceName":"发现源","exploreUrl":"玄幻::/rank?p={{page}}","searchUrl":"https://d.invalid/s"}"#)
        var discOptions = options
        discOptions.checkSearch = false
        var exploreCount = 0
        let discHooks = SourceCheck.Hooks(
            search: { _, _ in [book] }, explore: { _, url in exploreCount += 1; _ = url; return [book] },
            bookInfo: { _, b in var b = b; b.tocUrl = "t"; return b },
            chapters: { _, _ in chapters },
            content: { _, _, _, _ in "正文" },
            domainReachable: { _ in true }
        )
        let r9 = await SourceCheck.checkOne(discSource, options: discOptions, hooks: discHooks)
        check(r9.success && exploreCount == 1, "发现规则校验走发现页（实际 \(r9.message)）")

        let discEmptyHooks = SourceCheck.Hooks(
            search: { _, _ in [book] }, explore: { _, _ in [] },
            bookInfo: { _, b in b }, chapters: { _, _ in chapters },
            content: { _, _, _, _ in "正文" }, domainReachable: { _ in true }
        )
        let r10 = await SourceCheck.checkOne(discSource, options: discOptions, hooks: discEmptyHooks)
        check(!r10.success && r10.groups == ["发现失效"], "发现页为空记“发现失效”（实际 \(r10.groups)）")

        let discBadRule = makeSource(#"{"bookSourceUrl":"https://d.invalid/2","bookSourceName":"发现源","exploreUrl":"只有标题"}"#)
        let r11 = await SourceCheck.checkOne(discBadRule, options: discOptions, hooks: discHooks)
        check(r11.success && r11.updatedSource.sourceGroupNames == ["发现规则为空"],
              "发现规则没有网址只留分组，与原版一样不算失效（实际 \(r11.message)）")

        let discNoChapterHooks = SourceCheck.Hooks(
            search: { _, _ in [book] }, explore: { _, _ in [book] },
            bookInfo: { _, b in var b = b; b.tocUrl = "t"; return b },
            chapters: { _, _ in [] },
            content: { _, _, _, _ in "正文" }, domainReachable: { _ in true }
        )
        let r12 = await SourceCheck.checkOne(discSource, options: discOptions, hooks: discNoChapterHooks)
        check(!r12.success && r12.groups == ["发现目录失效"], "发现分支目录失败记“发现目录失效”（实际 \(r12.groups)）")

        // MARK: 设置开关与源类型

        var noInfoOptions = options
        noInfoOptions.checkInfo = false
        var infoCalled = 0
        let noInfoHooks = SourceCheck.Hooks(
            search: { _, _ in [book] }, explore: { _, _ in [] },
            bookInfo: { _, b in infoCalled += 1; return b },
            chapters: { _, _ in infoCalled += 1; return chapters },
            content: { _, _, _, _ in infoCalled += 1; return "正文" },
            domainReachable: { _ in true }
        )
        let r13 = await SourceCheck.checkOne(happy, options: noInfoOptions, hooks: noInfoHooks)
        check(r13.success && infoCalled == 0, "关闭详情后不再请求详情/目录/正文")

        let fileSource = makeSource(#"{"bookSourceUrl":"https://file.invalid","bookSourceName":"下载源","bookSourceType":3,"searchUrl":"https://file.invalid/s"}"#)
        var fileTocCalled = false
        let fileHooks = SourceCheck.Hooks(
            search: { _, _ in [book] }, explore: { _, _ in [] },
            bookInfo: { _, b in b },
            chapters: { _, _ in fileTocCalled = true; return chapters },
            content: { _, _, _, _ in fileTocCalled = true; return "正文" },
            domainReachable: { _ in true }
        )
        let r14 = await SourceCheck.checkOne(fileSource, options: options, hooks: fileHooks)
        check(r14.success && !fileTocCalled, "bookSourceType=3 只校验搜索与详情")

        let noSearchSource = makeSource(#"{"bookSourceUrl":"https://ns.invalid","bookSourceName":"无搜索","exploreUrl":"玄幻::/x"}"#)
        let r15 = await SourceCheck.checkOne(noSearchSource, options: options, hooks: discEmptyHooks)
        check(r15.updatedSource.sourceGroupNames == ["搜索链接规则为空", "发现失效"],
              "空搜索链接只留分组，不单独判失败（实际 \(r15.updatedSource.sourceGroupNames)）")
        check(r15.message == "校验失败:发现失效", "空搜索链接不进入失败消息（实际 \(r15.message)）")

        // MARK: 域名校验

        var domainOptions = options
        domainOptions.checkDomain = true
        var domainProbe = 0
        let domainHooksTrue = SourceCheck.Hooks(
            search: { _, _ in [book] }, explore: { _, _ in [] },
            bookInfo: { _, b in b }, chapters: { _, _ in chapters },
            content: { _, _, _, _ in "正文" },
            domainReachable: { _ in domainProbe += 1; return true }
        )
        let nonHTTP = makeSource(#"{"bookSourceUrl":"书山聚合","bookSourceName":"非网址源"}"#)
        let r16 = await SourceCheck.checkOne(nonHTTP, options: domainOptions, hooks: domainHooksTrue)
        check(!r16.success && r16.groups == ["域名失效"] && domainProbe == 0,
              "源地址不是 http 记“域名失效”且不探测（实际 \(r16.groups)）")
        check(r16.message == "校验失败:源地址不是http链接", "非 http 消息与原版一致（实际 \(r16.message)）")

        let deadSource = makeSource(#"{"bookSourceUrl":"https://dead.invalid","bookSourceName":"不可达"}"#)
        let domainHooksFalse = SourceCheck.Hooks(
            search: { _, _ in [book] }, explore: { _, _ in [] },
            bookInfo: { _, b in b }, chapters: { _, _ in chapters },
            content: { _, _, _, _ in "正文" },
            domainReachable: { _ in false }
        )
        let r17 = await SourceCheck.checkOne(deadSource, options: domainOptions, hooks: domainHooksFalse)
        check(!r17.success && r17.groups == ["域名失效"] && r17.message == "校验失败:源地址不可访问",
              "不可达记“域名失效”（实际 \(r17.message)）")

        var reachableOptions = domainOptions
        reachableOptions.checkSearch = false
        reachableOptions.checkDiscovery = false
        let r18 = await SourceCheck.checkOne(deadSource, options: reachableOptions, hooks: domainHooksTrue)
        check(r18.success && r18.groups.isEmpty, "域名可达且无校验项时判成功（实际 \(r18.message)）")

        // MARK: 批量并发与进度

        var concOptions = options
        concOptions.concurrency = 2
        let many = (0..<5).map { i in
            makeSource("{\"bookSourceUrl\":\"https://many.invalid/\(i)\",\"bookSourceName\":\"源\(i)\",\"searchUrl\":\"https://many.invalid/s\"}")
        }
        let state = TestConcurrencyState()
        let concHooks = SourceCheck.Hooks(
            search: { _, _ in
                state.enter()
                try? await Task.sleep(nanoseconds: 100_000_000)
                state.leave()
                return [book]
            },
            explore: { _, _ in [] },
            bookInfo: { _, b in var b = b; b.tocUrl = "t"; return b },
            chapters: { _, _ in chapters },
            content: { _, _, _, _ in "正文" },
            domainReachable: { _ in true }
        )
        let batch = await SourceCheck.runAll(many, options: concOptions, hooks: concHooks,
                                             onStart: { _ in state.markStart() },
                                             onResult: { _ in state.markResult() })
        let peak = state.peak
        let starts = state.starts
        let results = state.results
        check(batch.count == 5 && batch.allSatisfy { $0.success }, "runAll 全部完成且成功")
        check(results == 5 && starts == 5, "onStart/onResult 覆盖每个书源（实际 \(starts)/\(results)）")
        check(peak <= 2, "并发不超过配置上限（峰值 \(peak)）")
        check(peak >= 2, "并发按配置并行（峰值 \(peak)）")
        check(batch.allSatisfy { $0.updatedSource.respondTime != nil }, "每个书源都写响应耗时")
    }
}
