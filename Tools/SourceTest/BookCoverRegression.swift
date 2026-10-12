import Foundation

/// 离线封面回归：真实柒默规则 + 合成 API body，经 WebBook/AnalyzeRule 解析。
/// 1043123456 / 1043999999 都是测试 ID，不代表用户《青山》的真实 BookId。
/// 只验证元数据解析和 Book Codable 落盘，不请求 API/图片，不冒充 UI 或 HTTP 集成测试。
enum BookCoverRegression {
    static func run(_ check: (Bool, String) -> Void) {
        do {
            try qimoShelfRoundTrip(check)
            try compatibleRules(check)
        } catch {
            check(false, "BookCoverRegression 构造或落盘失败：\(error)")
        }
    }

    /// 与 AppStore 相同的 [Book] JSON 形状；必须真的写入文件再读，不能只在内存 encode/decode。
    private static func roundTrip(_ book: Book, at file: URL) throws -> Book {
        try JSONEncoder().encode([book]).write(to: file, options: .atomic)
        let books = try JSONDecoder().decode([Book].self, from: Data(contentsOf: file))
        guard books.count == 1 else {
            throw NSError(domain: "BookCoverRegression", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "书架 JSON 应包含一本合成书"])
        }
        return books[0]
    }

    private static func qimoShelfRoundTrip(_ check: (Bool, String) -> Void) throws {
        var source = try QimoSourceRegression.loadFixture()
        // 隔离 RuleContext 的进程级变量；搜索/详情规则和签名库保持 fixture 原样。
        source.bookSourceUrl += "#cover-regression-" + UUID().uuidString
        guard let searchRule = source.ruleSearch, let infoRule = source.ruleBookInfo else {
            check(false, "柒默封面：真实 fixture 必须包含搜索和详情规则")
            return
        }
        check(searchRule.coverUrl == "https://bookcover.yuewen.com/qdbimg/349573/{{$.ItemData.BookId}}/600"
              && infoRule.coverUrl == "https://bookcover.yuewen.com/qdbimg/349573/{{$.Data.BookId}}/600",
              "柒默封面：使用真实搜索/详情模板，不以手写规则代替")
        let searchURL = "https://druidv6.if.qidian.com/argus/api/v2/booksearch/searchbooks"
        let detailURL = "https://druidv6.if.qidian.com/argus/api/v2/bookdetail/get?bookId=1043123456"
        let goodCover = "https://bookcover.yuewen.com/qdbimg/349573/1043123456/600"
        let newCover = "https://bookcover.yuewen.com/qdbimg/349573/1043999999/600"
        let searchBody = #"{"Status":0,"Data":{"CardList":[{"Body":[{"ItemType":1,"ItemData":{"BookId":9,"BookName":"不应选中的合成卡片"}},{"ItemType":0,"ItemData":{"BookId":1043123456,"BookName":"封面回归合成书","AuthorName":"搜索合成作者","Description":"搜索简介","CategoryName":"合成分类"}}]}]}}"#
        let books = WebBook.parseBookList(source: source, body: searchBody, baseUrl: searchURL, rule: searchRule)
        check(books.count == 1, "柒默封面：真实 CardList/ItemType 规则取得唯一合成书")
        guard let searched = books.first else { return }
        check(searched.name == "封面回归合成书" && searched.coverUrl == goodCover,
              "柒默封面：首次搜索取得完整封面 URL")
        // 签名中有时间/随机数，只断言稳定的请求地址，不快照签名或真正 fetch。
        let request = AnalyzeUrl(rawUrl: searched.bookUrl, baseUrl: source.bookSourceUrl,
                                 sourceHeader: source.header, context: RuleContext(source: source, book: searched), jsLib: source.jsLib)
        check(request.url == detailURL, "柒默封面：搜索所得书籍地址包含合成 BookId")
        func detail(_ book: Book, _ body: String) -> Book {
            WebBook.parseBookInfo(source: source, book: book, body: body, url: detailURL,
                                  context: RuleContext(source: source, book: book))
        }
        // 搜索为数字 ID，详情为字符串 ID；两种正常 API 表示都必须工作。
        let detailBody = #"{"Status":0,"Data":{"BookId":"1043123456","BookName":"封面回归合成书","Author":"详情合成作者","Description":"详情简介","CategoryName":"合成分类","FreshManSimple":{"IsInBlackList":0},"WordsCnt":12345,"LastVipUpdateChapterName":"合成最新章"}}"#
        var shelfBook = detail(searched, detailBody)
        check(shelfBook.coverUrl == goodCover && shelfBook.author == "详情合成作者" && shelfBook.wordCount == "12345",
              "柒默封面：首次详情成功解析，封面与其他字段都有值")
        shelfBook.durChapterIndex = 7
        shelfBook.durChapterPos = 96
        shelfBook.durChapterTitle = "合成第八章"
        shelfBook.addedAt = Date(timeIntervalSince1970: 1_700_000_000)
        shelfBook.lastReadAt = Date(timeIntervalSince1970: 1_700_000_100)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("BookCoverRegression-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("bookshelf.json")
        let restored = try roundTrip(shelfBook, at: file)
        check(restored == shelfBook && restored.coverUrl == goodCover,
              "柒默封面：加入书架并 JSON 落盘回读，完整 Book 与 good cover 不丢失")

        let missingDataBody = #"{"Status":0}"#
        let legacy = AnalyzeRule(content: missingDataBody, baseUrl: detailURL, jsLib: source.jsLib,
                                 context: RuleContext(source: source, book: restored)).getString(infoRule.coverUrl)
        check(legacy == "https://bookcover.yuewen.com/qdbimg/349573//600",
              "柒默封面根因对照：普通 getString 仍生成缺 BookId 的非空 URL")
        check(detail(restored, missingDataBody).coverUrl == goodCover,
              "柒默封面根因对照：同一 body 经 WebBook 保留持久化 good cover，不采用旧模板结果")

        let validUpdate = #"{"Status":0,"Data":{"BookId":"1043999999","BookName":"封面回归合成书","Author":"更新合成作者"}}"#
        let refreshed = detail(restored, validUpdate)
        check(refreshed.coverUrl == newCover && refreshed.author == "更新合成作者",
              "柒默封面：已有旧图时，有效的新封面仍然更新，不能冻结所有详情")
        let refreshedReload = try roundTrip(refreshed, at: file)
        check(refreshedReload.coverUrl == newCover, "柒默封面：有效新封面也可落盘回读")

        // 这些是解析层 body 用例，不声称验证 HTTP 状态码拦截或业务 Status 拦截。
        // 每个 case 都从同一份已回读的 good Book 开始，防止前一失败污染后一断言。
        let invalidBodies: [(String, String)] = [
            ("Data=null", #"{"Status":0,"Data":null}"#),
            ("缺失 Data", #"{"Status":0}"#),
            ("缺失 BookId", #"{"Data":{"BookName":"封面回归合成书"}}"#),
            ("BookId 为空串", #"{"Data":{"BookId":""}}"#),
            ("BookId 仅空白", #"{"Data":{"BookId":" \t "}}"#),
            ("BookId 为 JSON null", #"{"Data":{"BookId":null}}"#),
            ("BookId 为 null 字符串", #"{"Data":{"BookId":"null"}}"#),
            ("BookId 为 undefined 字符串", #"{"Data":{"BookId":"undefined"}}"#),
            ("空响应", ""),
            ("401 风格 JSON 错误体", #"{"Status":401,"Message":"Synthetic unauthorized","Data":null}"#),
            ("502 风格 HTML 错误体", "<html><body><h1>502 Synthetic Bad Gateway</h1></body></html>")
        ]
        for (label, body) in invalidBodies {
            let updated = detail(restored, body)
            check(updated.coverUrl == goodCover,
                  "柒默封面：\(label) 保留落盘旧图，实际 \(updated.coverUrl ?? "<nil>")")
            check(updated.bookUrl == restored.bookUrl && updated.origin == restored.origin
                  && updated.durChapterIndex == 7 && updated.durChapterPos == 96 && updated.durChapterTitle == "合成第八章",
                  "柒默封面：\(label) 不改变书籍身份或阅读进度")
            let reopened = try roundTrip(updated, at: file)
            check(reopened.coverUrl == goodCover, "柒默封面：\(label) 后再次落盘回读仍是旧图")
            var withoutCover = restored
            withoutCover.coverUrl = nil
            check(detail(withoutCover, body).coverUrl == nil,
                  "柒默封面：\(label) 且无旧图时为 nil，不制造缺 ID 的非空 URL")
        }
        let missingSearchID = #"{"Data":{"CardList":[{"Body":[{"ItemType":0,"ItemData":{"BookName":"缺 ID 合成书"}}]}]}}"#
        let missing = WebBook.parseBookList(source: source, body: missingSearchID, baseUrl: searchURL, rule: searchRule)
        check(missing.count == 1 && missing.first?.coverUrl == nil,
              "柒默封面：搜索缺 BookId、无旧图时同样不得生成伪封面")
    }

    private static func compatibleRules(_ check: (Bool, String) -> Void) throws {
        let base = "https://cover-rules.invalid/books/42/detail.html"
        let oldCover = "https://cover-rules.invalid/old.jpg"
        func source(_ coverRule: String, initRule: String? = nil) throws -> BookSource {
            var info: [String: String] = ["coverUrl": coverRule]
            if let initRule = initRule { info["init"] = initRule }
            let json: [String: Any] = [
                "bookSourceUrl": "https://cover-rules.invalid/#" + UUID().uuidString,
                "bookSourceName": "Cover compatibility regression", "ruleBookInfo": info
            ]
            return try JSONDecoder().decode(BookSource.self, from: JSONSerialization.data(withJSONObject: json))
        }
        func parse(_ source: BookSource, _ body: String, old: String?) -> Book {
            var book = Book(bookUrl: base, name: "合成兼容书", origin: source.bookSourceUrl)
            book.coverUrl = old
            return WebBook.parseBookInfo(source: source, book: book, body: body, url: base,
                                         context: RuleContext(source: source, book: book))
        }
        let valid: [(String, String, String, String)] = [
            ("CSS 根相对图", "@css:img.cover@src", "<img class='cover' src='/covers/relative.jpg'>",
             "https://cover-rules.invalid/covers/relative.jpg"),
            ("CSS 目录相对图", "@css:img.cover@data-src", "<img class='cover' data-src='../images/relative.jpg'>",
             "https://cover-rules.invalid/books/images/relative.jpg"),
            ("JSON 协议相对图", "$.cover", #"{"cover":"//cdn.cover-rules.invalid/a.jpg"}"#,
             "https://cdn.cover-rules.invalid/a.jpg"),
            ("CSS 备用选择器", "@css:img.missing@src||@css:img.cover@src", "<img class='cover' src='/covers/fallback.jpg'>",
             "https://cover-rules.invalid/covers/fallback.jpg"),
            ("合法 URL 含 null 子串及双斜杠路径", "$.cover", #"{"cover":"https://cdn.cover-rules.invalid/covers//null-is-a-slug.jpg"}"#,
             "https://cdn.cover-rules.invalid/covers//null-is-a-slug.jpg"),
            ("JS 固定图", "@js:'https://cdn.cover-rules.invalid/static.jpg'", "{}",
             "https://cdn.cover-rules.invalid/static.jpg"),
            ("JS 嵌入空字段但显式备用图", "@js:(function(){var id='{{$.id}}';return id ? 'https://cdn.cover-rules.invalid/'+id+'.jpg' : 'https://cdn.cover-rules.invalid/fallback.jpg'})()", "{}",
             "https://cdn.cover-rules.invalid/fallback.jpg"),
            ("模板后 JS 接收空结果并选备用图", "https://cdn.cover-rules.invalid/{{$.id}}.jpg@js:result || 'https://cdn.cover-rules.invalid/fallback.jpg'", "{}",
             "https://cdn.cover-rules.invalid/fallback.jpg"),
            ("模板后 JS 保留有效主图", "https://cdn.cover-rules.invalid/{{$.id}}.jpg@js:result || 'https://cdn.cover-rules.invalid/fallback.jpg'", #"{"id":"42"}"#,
             "https://cdn.cover-rules.invalid/42.jpg"),
            ("模板表达式自行提供备用 ID", "https://cdn.cover-rules.invalid/{{java.getString('$.id') || 'default'}}.jpg", "{}",
             "https://cdn.cover-rules.invalid/default.jpg"),
            ("可选 query 字段缺失", "https://cdn.cover-rules.invalid/{{$.id}}.jpg?token={{$.token}}", #"{"id":"42"}"#,
             "https://cdn.cover-rules.invalid/42.jpg?token="),
            ("可选 query 为 JSON null", "https://cdn.cover-rules.invalid/{{$.id}}.jpg?token={{$.token}}", #"{"id":"42","token":null}"#,
             "https://cdn.cover-rules.invalid/42.jpg?token="),
            ("可选 fragment 为空", "https://cdn.cover-rules.invalid/{{$.id}}.jpg#{{$.fragment}}", #"{"id":"42"}"#,
             "https://cdn.cover-rules.invalid/42.jpg#"),
            ("可选请求 options 字段为空", #"https://cdn.cover-rules.invalid/{{$.id}}.jpg,{"headers":{"X-Optional":"{{$.token}}"}}"#, #"{"id":"42"}"#,
             #"https://cdn.cover-rules.invalid/42.jpg,{"headers":{"X-Optional":""}}"#)
        ]
        for (label, rule, body, expected) in valid {
            let src = try source(rule)
            for old in [nil, oldCover] as [String?] {
                let result = parse(src, body, old: old)
                check(result.coverUrl == expected,
                      "封面兼容：\(label)，\(old == nil ? "无旧图" : "替换旧图")，实际 \(result.coverUrl ?? "<nil>")")
            }
        }
        let invalid: [(String, String, String)] = [
            ("CSS 缺图", "@css:img.cover@src", "<html></html>"),
            ("JSON 空 cover", "$.cover", #"{"cover":""}"#),
            ("JSON null cover", "$.cover", #"{"cover":null}"#),
            ("必需相对路径模板缺 ID", "/covers/{{$.id}}.jpg", "{}"),
            ("模板内三元问号不是 query 边界", "https://cdn.cover-rules.invalid/{{true ? '' : 'unused'}}.jpg", "{}"),
            ("路径逗号不是 options 边界", "https://cdn.cover-rules.invalid/a,b/{{$.id}}.jpg", "{}")
        ]
        for (label, rule, body) in invalid {
            let src = try source(rule)
            for old in [nil, oldCover] as [String?] {
                check(parse(src, body, old: old).coverUrl == old,
                      "封面缺值：\(label)，保留原有 \(old ?? "nil")")
            }
        }
        let scoped = try source("https://cdn.cover-rules.invalid/{{$.id}}.jpg", initRule: "$.Data")
        check(parse(scoped, #"{"id":"outside","Data":{"id":"inside"}}"#, old: oldCover).coverUrl
              == "https://cdn.cover-rules.invalid/inside.jpg", "封面 init：依赖从解析后的子对象取值")
        check(parse(scoped, #"{"id":"outside","Data":{}}"#, old: oldCover).coverUrl == oldCover,
              "封面 init：子对象缺 ID 不借用原响应顶层 ID")

        // intro 在 cover 之前，toc 在 cover 之后，同一个 AnalyzeRule 的普通字段都不能被封面模式污染。
        var scopedMode = try source("https://cdn.cover-rules.invalid/{{$.missing}}.jpg")
        scopedMode.ruleBookInfo?.intro = "https://metadata.invalid/{{$.missing}}/intro"
        scopedMode.ruleBookInfo?.tocUrl = "https://metadata.invalid/{{$.missing}}/toc"
        let ordinary = parse(scopedMode, "{}", old: oldCover)
        check(ordinary.intro == "https://metadata.invalid//intro" && ordinary.tocUrl == "https://metadata.invalid//toc",
              "封面模式仅作用于 cover：前后的普通模板字段继续允许空值")
    }
}
