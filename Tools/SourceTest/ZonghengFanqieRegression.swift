import Foundation

/// 纵横中文网 + 番茄畅听（v2）两个书源的兼容性回归。
///
/// 这两个源代表了 Legado 规则的两类极端写法，跑通它们等于验证了引擎的通用能力：
/// - **纵横**：全 JSON 接口 + `URL,{method:POST,body:...}` 后缀写法 + `{$.id}` 模板拼 body。
///   规则里的 body 是 `k=v` 表单串，引擎按「body 不以 `{` 开头 → 表单」发送，
///   与站点实际要求一致（用 JSON 发同一端点会返回 `code:-999`）。
/// - **番茄畅听 v2**：125 KB jsLib、签名头、`<js>` 块尾部接 `$[*]` 链式路径、
///   `subContent` 字幕、`customButton` 长按翻页。这里只验证纯本地可判定的部分
///   （规则切分、LRC 解析、音色探测），联网部分交给 CI 的在线用例。
enum ZonghengFanqieRegression {
    static func run(_ check: (Bool, String) -> Void) async throws {
        // MARK: 0) JS 兼容细节（番茄详情面板 / 音频正文依赖）

        // JSON 结果交给 JS：既保留对象属性，也让 String()/JSON.parse 拿到 JSON 文本。
        let payload: [String: Any] = ["data": [["main_url": "https://audio.example/1.mp3"]]]
        let js = "[String(result).indexOf('main_url') >= 0, JSON.parse(result).data[0].main_url, result.data[0].main_url].join('|')"
        let jsOut = JSEngine.shared.evalString(js, result: payload) ?? ""
        check(jsOut == "true|https://audio.example/1.mp3|https://audio.example/1.mp3",
              "JS result：String()/JSON.parse/对象属性一致（实际 \(jsOut)）")

        // java.connect(url, headers)：第二个参数是请求头（playinfo 必须带签名头）。
        let server = try TTSHarnessServer.start()
        defer { server.stop() }
        let echo = #"{"data":[{"main_url":"https://audio.example/x.mp3"}]}"#
        server.enqueue(status: 200, headers: ["Content-Type": "application/json"], body: Data(echo.utf8))
        let connectJS = "String(java.connect('\(server.origin)/play?item_id=1', JSON.stringify({'X-Test-Header':'yes'})).body())"
        let fetched = JSEngine.shared.evalString(connectJS) ?? ""
        check(fetched.contains("main_url"), "java.connect(url, headers)：拿到响应体（实际 \(fetched.prefix(80))）")
        let report = server.report()
        let headerValue = report?.headers.first { $0.key.lowercased() == "x-test-header" }?.value
        check(headerValue == "yes", "java.connect(url, headers)：请求头已带上（实际 \(report?.headers ?? [:])）")

        // MARK: 1) 两个夹具都能被 BookSource 解码

        // MARK: 0.5) 目录请求要沿用详情请求的 POST 后缀
        //
        // 纵横的目录接口只接受 POST：bookUrl 里的 `,{"method":"POST","body":"bookId=…"}`
        // 一旦在详情解析时被换成「响应网址」，抓目录就退化成 GET → 404 → 目录 0 章。
        let tocServer = try TTSHarnessServer.start()
        defer { tocServer.stop() }
        let detailJSON = #"{"code":0,"result":{"chapterList":[{"tome":{"bookId":4242},"chapterViewList":[{"bookId":4242,"chapterId":11,"chapterName":"第1章","level":0}]}]}}"#
        let listJSON = #"{"code":0,"result":{"chapterList":[{"tome":{"bookId":4242},"chapterViewList":[{"bookId":4242,"chapterId":11,"chapterName":"第1章","wordNums":100,"createTime":"2024-01-01","level":0},{"bookId":4242,"chapterId":12,"chapterName":"第2章","wordNums":100,"createTime":"2024-01-01","level":1}]}]}}"#
        let loopJSON = """
        {"bookSourceUrl":"\(tocServer.origin)","bookSourceName":"纵横回环","ruleBookInfo":{},
         "ruleToc":{"chapterList":"result.chapterList[*].chapterViewList[*]","chapterName":"chapterName",
                    "chapterUrl":"\(tocServer.origin)/chapter/{$.bookId}/{$.chapterId}.html","isVip":"level"},
         "ruleContent":{"content":".content@p@text"}}
        """
        let loopSource = try JSONDecoder().decode(BookSource.self, from: Data(loopJSON.utf8))
        let rawBookURL = tocServer.origin + #"/chapterlist,{"method":"POST","body":"bookId=4242"}"#
        let detailBook = Book(bookUrl: rawBookURL, name: "我的江湖往事", origin: tocServer.origin)
        tocServer.enqueue(status: 200, headers: ["Content-Type": "application/json"], body: Data(detailJSON.utf8))
        let info = try await WebBook.bookInfo(source: loopSource, book: detailBook)
        check(info.tocUrl == rawBookURL, "详情解析保留目录请求的 POST 后缀（实际 \(info.tocUrl ?? "nil")）")
        tocServer.enqueue(status: 200, headers: ["Content-Type": "application/json"], body: Data(listJSON.utf8))
        let loopChapters = try await WebBook.chapters(source: loopSource, book: info)
        check(loopChapters.count == 2, "纵横式 POST 目录能解析出章节（实际 \(loopChapters.count)）")
        let tocReport = tocServer.report()
        check(tocReport?.method == "POST", "目录请求沿用 POST（实际 \(tocReport?.method ?? "-")）")
        check(String(data: tocReport?.body ?? Data(), encoding: .utf8)?.contains("bookId=4242") == true,
              "目录请求带 bookId body")
        check(loopChapters.first?.url == "\(tocServer.origin)/chapter/4242/11.html",
              "目录章节地址模板（实际 \(loopChapters.first?.url ?? "-")）")
        check(loopChapters.first?.isVip == false && loopChapters.last?.isVip == true, "目录 isVip：level 0/1")

        // 旧书架记录：tocUrl 是丢掉 POST 后缀的响应网址，抓目录时按 bookUrl 自愈。
        var legacyBook = info
        legacyBook.tocUrl = "\(tocServer.origin)/chapterlist"
        tocServer.enqueue(status: 200, headers: ["Content-Type": "application/json"], body: Data(listJSON.utf8))
        let healedChapters = try await WebBook.chapters(source: loopSource, book: legacyBook)
        check(healedChapters.count == 2 && tocServer.report()?.method == "POST",
              "旧记录丢失 POST 后缀时按 bookUrl 自愈（实际 \(healedChapters.count) 章）")

        let dir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let files = ["Tools/SourceTest/Fixtures/zongheng-source.json",
                     "Tools/SourceTest/Fixtures/fanqie-changting-v2.json"]
        var sources: [BookSource] = []
        for file in files {
            let url = dir.appendingPathComponent(file)
            guard let data = try? Data(contentsOf: url) else {
                check(false, "\(file) 夹具可读")
                return
            }
            guard let list = try? JSONDecoder().decode([BookSource].self, from: data),
                  let first = list.first else {
                check(false, "\(file) 可解码为 BookSource")
                return
            }
            sources.append(first)
        }
        check(sources.count == 2, "两个书源夹具都能解码，实际 \(sources.count)")

        // 同一份番茄书源必须能「整条导入」：导入器曾经先转字典再用
        // JSONSerialization 写回，subContent 里的 \u0000 分隔符被改写，整条被判坏数据。
        let fanqieText = try String(contentsOf: dir.appendingPathComponent(files[1]), encoding: .utf8)
        let imported = try SourceImportParser.parse(fanqieText)
        check(imported.report.imported == 1 && imported.report.failed == 0,
              "导入器：番茄畅听 v2 整条导入（失败原因：\(imported.report.failures.first ?? "-")）")
        check(imported.sources.first?.ruleContent?.subContent?.contains("\u{0}") == true,
              "导入器：subContent 里的 \\u0000 分隔符保留")

        let zongheng = sources[0]
        let fanqie = sources[1]
        check(zongheng.bookSourceType == 0, "纵横是文字源（type 0），实际 \(zongheng.bookSourceType ?? -1)")
        check(fanqie.bookSourceType == 1, "番茄畅听是音频源（type 1），实际 \(fanqie.bookSourceType ?? -1)")
        check(!(fanqie.jsLib ?? "").isEmpty, "番茄 jsLib 已保留（签名/音色都靠它）")

        // MARK: 2) 纵横：JSON 路径取字段

        let zItem: [String: Any] = [
            "bookId": 672340,
            "name": "<font color=\"RED\">剑来</font>",
            "coverUrl": "/cover/dc/c7/abc.jpeg",
            "authorName": "烽火戏诸侯",
            "totalWord": "1234567",
            "serialStatus": 1,
            // kind 规则是 `{{a&&b&&c&&d&&e}}` 全真才输出，五个字段缺一不可。
            "cateFineName": "武侠仙侠",
            "tomeName": "第一卷 笼中雀",
            "catePName": "玄幻",
            "keyword": "剑来",
            "updateTime": "2026-10-24"
        ]
        let zRule = AnalyzeRule(content: zItem, baseUrl: zongheng.bookSourceUrl)
        guard let zSearch = zongheng.ruleSearch else {
            check(false, "纵横 ruleSearch 存在")
            return
        }
        check(zRule.getString(zSearch.name) == "剑来",
              "纵横搜索书名去掉 <font> 高亮，实际 \(zRule.getString(zSearch.name))")
        check(zRule.getString(zSearch.author) == "烽火戏诸侯",
              "纵横搜索作者，实际 \(zRule.getString(zSearch.author))")

        // `{{$.a}}{{$.b}}` 拼接 + @js 后处理：连载1完结 → 完结
        let kind = zRule.getString(zSearch.kind)
        check(!kind.contains("连载1完结") && !kind.contains("连载0完结"),
              "纵横 kind 的拼接结果被 @js 规整，实际 \(kind)")

        // MARK: 3) 纵横：POST 后缀写法里的 {$.bookId} 模板

        guard let bookUrlRule = zSearch.bookUrl else {
            check(false, "纵横 ruleSearch.bookUrl 存在")
            return
        }
        let built = zRule.getString(bookUrlRule)
        check(built.contains("method") && built.contains("POST"),
              "纵横 bookUrl 是 POST 后缀写法，实际 \(built.prefix(80))")
        check(built.contains("bookId=672340"),
              "纵横 bookUrl 的 {$.bookId} 模板已替换，实际 \(built.prefix(120))")

        // MARK: 4) 番茄：`<js>` 块 + 尾部 `$[*]` 链式切分

        guard let toc = fanqie.ruleToc, let chapterList = toc.chapterList else {
            check(false, "番茄 ruleToc.chapterList 存在")
            return
        }
        check(chapterList.lowercased().contains("<js>"),
              "番茄目录规则是 <js> 脚本")
        check(chapterList.hasSuffix("$[*]"),
              "番茄目录规则尾部接 $[*] 路径（依赖 js 块的返回值继续求值）")

        // MARK: 5) LRC 字幕解析（番茄 subContent 的输出格式）

        let lrc = """
        [ar:某作者]
        [00:00.00]第一章 开端
        [00:03.50]第一句台词。
        [00:07.25][00:12.00]重复出现的一句。
        [01:02.75]最后一句。
        """
        let lines = LyricTimeline.parse(lrc)
        // 5 行：首行标题行也是有效字幕；`[00:07.25][00:12.00]` 展开成两行；`[ar:]` 元信息丢弃。
        check(lines.count == 5, "LRC 解析出 5 行（多时间戳展开、元信息丢弃），实际 \(lines.count)")
        check(lines.contains { abs($0.time - 3.5) < 0.001 },
              "LRC 有 3.5s 那条（排序后首行是 0s 的标题行）")
        check(lines.first?.time == 0,
              "LRC 首行是 0s 的标题行，实际 \(lines.first?.time ?? -1)")
        check(lines.contains { abs($0.time - 12.0) < 0.001 },
              "同一行的第二个时间戳也展开")

        // 字面量 \n 的 LRC 也要能拆开（有的书源这样输出）
        let escaped = LyricTimeline.parse("[00:01.00]甲\\n[00:05.00]乙")
        check(escaped.count == 2, "字面量 \\n 的 LRC 也能拆行，实际 \(escaped.count)")

        // 字幕对齐到段落：段落文字能在字幕里找到起点
        let paragraphs = ["第一句台词。", "重复出现的一句。", "最后一句。"]
        if let bounds = LyricTimeline.boundaries(lines: lines, paragraphs: paragraphs, duration: 90) {
            check(bounds.count == paragraphs.count + 1,
                  "边界数 = 段落数 + 1，实际 \(bounds.count)")
            check(abs((bounds.last ?? -1) - 90) < 0.01,
                  "末个边界是总时长，实际 \(bounds.last ?? -1)")
            check(abs((bounds.first ?? -1) - 3.5) < 0.01,
                  "首个边界是字幕首句的真实起点 3.5s，实际 \(bounds.first ?? -1)")
            check(zip(bounds, bounds.dropFirst()).allSatisfy { $0 <= $1 },
                  "边界单调不减")
        } else {
            check(false, "字幕能对齐到段落")
        }

        // 完全不相关的字幕应拒绝（交给停顿估算），不能给出假时间轴
        let unrelated = LyricTimeline.parse("[00:01.00]完全无关的内容\n[00:02.00]另一句无关的话")
        check(LyricTimeline.boundaries(lines: unrelated ?? [], paragraphs: paragraphs, duration: 90) == nil,
              "对不上的字幕返回 nil（退回停顿估算）")

        // MARK: 6) 番茄 v2 的音色是「运行时拉取」而非静态表

        // v2 的音色表不在脚本里：`SourceTone` 现在识别 `toneinfo + fanqieSignHeaders`，
        // 按当前书动态取音色（`groups(source:book:)`；静态探测只看能力，不发请求）。
        check(SourceTone.hasTones(source: fanqie),
              "番茄 v2 的音色表按运行时 toneinfo 识别")
        check((fanqie.jsLib ?? "").contains("toneinfo") || (fanqie.ruleToc?.chapterList ?? "").contains("toneinfo"),
              "番茄 v2 用 toneinfo 接口拉音色，而不是静态音色表")

        // MARK: 7) 长按事件名与原版一致

        check(SourceCallBack.longClickCustomButton == "longClickCustomButton",
              "长按事件名与 Legado 一致")
    }
}
