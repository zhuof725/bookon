//
//  PublicAPITests.swift
//  LegadoBookSourcePublicAPITests
//
//  这是一个「纯 public 接口」测试 target：使用普通的 `import LegadoBookSource`，
//  绝不使用 @testable。目的是验证对外 API 的可见性完整——如果任何需要对外
//  暴露的类型 / init / 属性 / 静态成员 / 协议成员 / property wrapper 漏了 public，
//  本 target 会编译失败。
//
//  覆盖：
//    - 通过 public 接口导入 test_bookSources.json、读取 BookSource 及六个 rule 的全部字段、
//      导出后再导入并比较（decode → encode → decode 一致性）。
//    - 手动用 public init 构造每一个模型类型各一个实例。
//

import XCTest
import LegadoBookSource   // 注意：不是 @testable

final class PublicAPITests: XCTestCase {

    // MARK: 资源加载（public 接口）

    private func loadJSONData(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json") else {
            XCTFail("找不到资源 \(name).json")
            throw NSError(domain: "test", code: 1)
        }
        return try Data(contentsOf: url)
    }

    // MARK: 通过 public 接口完成 导入 → 读全部字段 → 导出 → 再导入 → 比较

    func testPublicImportReadExportReimport() throws {
        let data = try loadJSONData("test_bookSources")

        // 导入（public: BookSourceImporter.importSources / BookSourceImportResult）
        let result = try BookSourceImporter.importSources(fromData: data)
        XCTAssertTrue(result.failures.isEmpty, "导入不应失败：\(result.failures.map { $0.reason })")
        XCTAssertEqual(result.successes.count, 6)

        // 读取每个 BookSource 的全部 public 字段（只要能访问即证明 public 完整）
        for src in result.successes {
            readAllBookSourceFields(src)
        }

        // 导出（public: exportSources）
        let exported = try BookSourceImporter.exportSources(result.successes, pretty: false)
        XCTAssertFalse(exported.isEmpty)

        // 再导入
        let result2 = try BookSourceImporter.importSources(fromJSONString: exported)
        XCTAssertTrue(result2.failures.isEmpty)
        XCTAssertEqual(result2.successes.count, 6)

        // 比较（BookSource: Equatable(按 url) + 各 rule Equatable 逐字段）
        for i in 0..<result.successes.count {
            let a = result.successes[i]
            let b = result2.successes[i]
            XCTAssertEqual(a, b, "书源#\(i) url 相等性")
            XCTAssertEqual(a.ruleSearch, b.ruleSearch, "书源#\(i) ruleSearch")
            XCTAssertEqual(a.ruleExplore, b.ruleExplore, "书源#\(i) ruleExplore")
            XCTAssertEqual(a.ruleBookInfo, b.ruleBookInfo, "书源#\(i) ruleBookInfo")
            XCTAssertEqual(a.ruleToc, b.ruleToc, "书源#\(i) ruleToc")
            XCTAssertEqual(a.ruleContent, b.ruleContent, "书源#\(i) ruleContent")
            XCTAssertEqual(a.ruleReview, b.ruleReview, "书源#\(i) ruleReview")
        }
    }

    /// 逐一读取 BookSource 与其六个 rule 的每个 public 属性。
    /// 只要这里能编译并读取，就说明相关属性都 public。
    private func readAllBookSourceFields(_ s: BookSource) {
        // BookSource 全部字段
        _ = s.bookSourceUrl
        _ = s.bookSourceName
        _ = s.bookSourceGroup
        _ = s.bookSourceType
        _ = s.bookUrlPattern
        _ = s.customOrder
        _ = s.enabled
        _ = s.enabledExplore
        _ = s.jsLib
        _ = s.enabledCookieJar
        _ = s.concurrentRate
        _ = s.header
        _ = s.loginUrl
        _ = s.loginUi
        _ = s.loginCheckJs
        _ = s.coverDecodeJs
        _ = s.bookSourceComment
        _ = s.variableComment
        _ = s.lastUpdateTime
        _ = s.respondTime
        _ = s.weight
        _ = s.exploreUrl
        _ = s.exploreScreen
        _ = s.searchUrl
        _ = s.eventListener
        _ = s.customButton

        // 六个 rule 的全部字段
        if let r = s.ruleSearch {
            _ = r.checkKeyWord; _ = r.bookList; _ = r.name; _ = r.author; _ = r.intro
            _ = r.kind; _ = r.lastChapter; _ = r.updateTime; _ = r.bookUrl; _ = r.coverUrl; _ = r.wordCount
        }
        if let r = s.ruleExplore {
            _ = r.bookList; _ = r.name; _ = r.author; _ = r.intro; _ = r.kind
            _ = r.lastChapter; _ = r.updateTime; _ = r.bookUrl; _ = r.coverUrl; _ = r.wordCount
        }
        if let r = s.ruleBookInfo {
            _ = r.`init`; _ = r.name; _ = r.author; _ = r.intro; _ = r.kind; _ = r.lastChapter
            _ = r.updateTime; _ = r.coverUrl; _ = r.tocUrl; _ = r.wordCount; _ = r.canReName; _ = r.downloadUrls
        }
        if let r = s.ruleToc {
            _ = r.preUpdateJs; _ = r.chapterList; _ = r.chapterName; _ = r.chapterUrl; _ = r.formatJs
            _ = r.isVolume; _ = r.isVip; _ = r.isPay; _ = r.updateTime; _ = r.nextTocUrl
        }
        if let r = s.ruleContent {
            _ = r.content; _ = r.subContent; _ = r.title; _ = r.nextContentUrl; _ = r.webJs
            _ = r.sourceRegex; _ = r.replaceRegex; _ = r.imageStyle; _ = r.imageDecode; _ = r.payAction; _ = r.callBackJs
        }
        if let r = s.ruleReview {
            _ = r.reviewUrl; _ = r.avatarRule; _ = r.contentRule; _ = r.postTimeRule; _ = r.reviewQuoteUrl
            _ = r.voteUpUrl; _ = r.voteDownUrl; _ = r.postReviewUrl; _ = r.postQuoteUrl; _ = r.deleteUrl
        }

        // BaseSource 协议成员（通过协议类型访问，验证协议成员可见）
        let base: BaseSource = s
        _ = base.concurrentRate
        _ = base.loginUrl
        _ = base.loginUi
        _ = base.header
        _ = base.enabledCookieJar
        _ = base.jsLib
        _ = base.getTag()
        _ = base.getKey()
    }

    // MARK: 手动用 public init 构造每个类型各一个实例

    func testPublicInitializersCompileAndWork() throws {
        // 各 rule
        let searchRule = SearchRule(
            checkKeyWord: "校验", bookList: "$.list", name: "$.name", author: "$.author",
            intro: "$.intro", kind: "$.kind", lastChapter: "$.last", updateTime: "$.time",
            bookUrl: "$.url", coverUrl: "$.cover", wordCount: "$.wc"
        )
        let exploreRule = ExploreRule(
            bookList: "$.list", name: "$.name", author: "$.author", intro: "$.intro",
            kind: "$.kind", lastChapter: "$.last", updateTime: "$.time",
            bookUrl: "$.url", coverUrl: "$.cover", wordCount: "$.wc"
        )
        let bookInfoRule = BookInfoRule(
            init: "@js:1", name: "$.name", author: "$.author", intro: "$.intro",
            kind: "$.kind", lastChapter: "$.last", updateTime: "$.time",
            coverUrl: "$.cover", tocUrl: "$.toc", wordCount: "$.wc",
            canReName: "true", downloadUrls: "$.dl"
        )
        let tocRule = TocRule(
            preUpdateJs: "js", chapterList: "$.chs", chapterName: "$.name", chapterUrl: "$.url",
            formatJs: "js", isVolume: "false", isVip: "false", isPay: "false",
            updateTime: "$.time", nextTocUrl: "$.next"
        )
        let contentRule = ContentRule(
            content: "$.body", subContent: "$.sub", title: "$.title", nextContentUrl: "$.next",
            webJs: "js", sourceRegex: "re", replaceRegex: "re", imageStyle: "FULL",
            imageDecode: "js", payAction: "js", callBackJs: "js"
        )
        let reviewRule = ReviewRule(
            reviewUrl: "$.review", avatarRule: "$.avatar", contentRule: "$.content",
            postTimeRule: "$.time", reviewQuoteUrl: "$.quote", voteUpUrl: "$.up",
            voteDownUrl: "$.down", postReviewUrl: "$.post", postQuoteUrl: "$.pq", deleteUrl: "$.del"
        )

        // ExploreKind / RowUi / FlexChildStyle
        let flex = FlexChildStyle(
            layout_flexGrow: 1, layout_flexShrink: 0, layout_alignSelf: "center",
            layout_flexBasisPercent: 0.5, layout_wrapBefore: true, layout_justifySelf: "center"
        )
        _ = FlexChildStyle.defaultStyle
        // 注意：ExploreKind / RowUi 里嵌套的 `Type` 常量命名空间与 Swift 的
        // 元类型 `.Type` 语法冲突，无法在模块外用 `ExploreKind.Type.url` 引用；
        // 这里直接用其对应的字符串字面量（与常量值一致）传入 public init。
        let exploreKind = ExploreKind(
            title: "分类", url: "/u", type: "url", action: nil,
            chars: ["a", nil], default: "d", viewName: "v", style: flex
        )
        _ = exploreKind.styleOrDefault()
        let rowUi = RowUi(
            name: "手机号", type: "text", action: nil,
            chars: ["x", nil], default: "d", viewName: "v", style: flex
        )
        _ = rowUi.styleOrDefault()

        // BookSource（用上面所有 rule）
        let bookSource = BookSource(
            bookSourceUrl: "https://example.com",
            bookSourceName: "示例书源",
            bookSourceGroup: "分组",
            bookSourceType: BookSourceType.default,
            bookUrlPattern: "pattern",
            customOrder: 1,
            enabled: true,
            enabledExplore: true,
            jsLib: "lib",
            enabledCookieJar: true,
            concurrentRate: "1",
            header: "{}",
            loginUrl: "url",
            loginUi: "[]",
            loginCheckJs: "js",
            coverDecodeJs: "js",
            bookSourceComment: "注释",
            variableComment: "变量说明",
            lastUpdateTime: 123,
            respondTime: 180000,
            weight: 5,
            exploreUrl: "url",
            exploreScreen: "screen",
            ruleExplore: exploreRule,
            searchUrl: "url",
            ruleSearch: searchRule,
            ruleBookInfo: bookInfoRule,
            ruleToc: tocRule,
            ruleContent: contentRule,
            ruleReview: reviewRule,
            eventListener: true,
            customButton: true
        )
        XCTAssertEqual(bookSource.bookSourceName, "示例书源")
        XCTAssertEqual(bookSource.ruleReview?.reviewUrl, "$.review")

        // ReadConfig（内嵌 public struct）
        let readConfig = Book.ReadConfig(
            reverseToc: true, pageAnim: 1, reSegment: true, imageStyle: "FULL",
            useReplaceRule: true, delTag: 3, ttsEngine: "e", splitLongChapter: false,
            readSimulating: true, startDate: "2024-01-01", startChapter: 2, dailyChapters: 5,
            openCredits: 1, closeCredits: 1, playMode: 1, playSpeed: 1.5
        )

        // Book
        let book = Book(
            bookUrl: "https://b.com/1",
            tocUrl: "https://b.com/toc",
            origin: BookType.localTag,
            originName: "源名",
            name: "书名",
            author: "作者",
            kind: "分类",
            customTag: "标签",
            coverUrl: "cover",
            customCoverUrl: "ccover",
            intro: "简介",
            customIntro: "cintro",
            charset: "UTF-8",
            type: BookType.text,
            group: 0,
            latestChapterTitle: "最新章",
            latestChapterTime: 0,
            lastCheckTime: 0,
            lastCheckCount: 0,
            totalChapterNum: 100,
            durChapterTitle: "当前章",
            durChapterIndex: 1,
            durVolumeIndex: 0,
            chapterInVolumeIndex: 0,
            durChapterPos: 0,
            durChapterTime: 0,
            wordCount: "10万",
            canUpdate: true,
            order: 0,
            originOrder: 0,
            variable: "{}",
            readConfig: readConfig,
            syncTime: 0
        )
        XCTAssertEqual(book.name, "书名")
        _ = Book.Const.imgStyleFull

        // BookChapter
        let chapter = BookChapter(
            url: "https://b.com/c1",
            title: "第一章",
            isVolume: false,
            baseUrl: "https://b.com",
            bookUrl: "https://b.com/1",
            index: 0,
            isVip: false,
            isPay: false,
            resourceUrl: nil,
            tag: "tag",
            wordCount: "3000",
            start: 0,
            end: 100,
            startFragmentId: nil,
            endFragmentId: nil,
            variable: "{}",
            imgUrl: nil
        )
        XCTAssertEqual(chapter.title, "第一章")

        // SearchBook
        let searchBook = SearchBook(
            bookUrl: "https://b.com/1",
            origin: "https://example.com",
            originName: "示例书源",
            type: BookType.text,
            name: "书名",
            author: "作者",
            kind: "分类",
            coverUrl: "cover",
            intro: "简介",
            wordCount: "10万",
            latestChapterTitle: "最新章",
            tocUrl: "https://b.com/toc",
            time: 0,
            variable: "{}",
            originOrder: 0,
            chapterWordCountText: "3000",
            chapterWordCount: 3000,
            respondTime: 100
        )
        XCTAssertEqual(searchBook.name, "书名")

        // 通过协议扩展的 public 方法
        _ = book.getKindList()
        _ = searchBook.getKindList()

        // 编码/解码往返（public: LegadoJSON）
        let encoded = try LegadoJSON.encoder.encode(bookSource)
        let decoded = try LegadoJSON.decoder.decode(BookSource.self, from: encoded)
        XCTAssertEqual(decoded.ruleContent, contentRule)
        XCTAssertEqual(decoded.ruleToc, tocRule)
    }

    // MARK: 真实书源往返（木里番茄，真实文件；注意：该书源不含 ruleReview 结构化字段）

    func testRealSourceRoundTrip() throws {
        let data = try loadJSONData("muli_real_source")
        let r1 = try BookSourceImporter.importSources(fromData: data)
        XCTAssertTrue(r1.failures.isEmpty, "真实书源导入不应失败：\(r1.failures.map { $0.reason })")
        XCTAssertEqual(r1.successes.count, 1)

        let exported = try BookSourceImporter.exportSources(r1.successes)
        let r2 = try BookSourceImporter.importSources(fromJSONString: exported)
        XCTAssertEqual(r2.successes.count, 1)

        let a = r1.successes[0]
        let b = r2.successes[0]
        XCTAssertEqual(a.ruleSearch, b.ruleSearch)
        XCTAssertEqual(a.ruleContent, b.ruleContent)
        XCTAssertEqual(a.ruleToc, b.ruleToc)
        XCTAssertEqual(a.ruleBookInfo, b.ruleBookInfo)
        XCTAssertEqual(a.ruleExplore, b.ruleExplore)
        // 该真实书源不含 ruleReview（段评由 ruleContent.callBackJs 的 JS 实现），故应为 nil。
        XCTAssertNil(a.ruleReview)
        XCTAssertNil(b.ruleReview)
    }
}
