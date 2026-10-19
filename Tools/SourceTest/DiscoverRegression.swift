import Foundation

/// 「发现」页数据整理：可发现书源过滤、分组、域名、分类切节、头像色。
/// 全部离线：夹具 + 纯函数 + 本地执行发现规则里的 @js。
enum DiscoverRegression {
    static func run(_ check: (Bool, String) -> Void) throws {
        let dir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Tools/SourceTest/Fixtures")

        // 1. 过滤：只保留启用 + 启用发现 + 有发现地址的书源
        var enabled = BookSource(bookSourceUrl: "https://a.invalid", bookSourceName: "启用发现")
        enabled.exploreUrl = "/explore"
        var disabled = BookSource(bookSourceUrl: "https://b.invalid", bookSourceName: "停用")
        disabled.exploreUrl = "/explore"
        disabled.enabled = false
        var exploreOff = BookSource(bookSourceUrl: "https://c.invalid", bookSourceName: "关了发现")
        exploreOff.exploreUrl = "/explore"
        exploreOff.enabledExplore = false
        var noExplore = BookSource(bookSourceUrl: "https://d.invalid", bookSourceName: "没有发现")
        noExplore.searchUrl = "/s"
        let picked = DiscoverCatalog.explorableSources([enabled, disabled, exploreOff, noExplore])
        check(picked.count == 1 && picked[0].bookSourceName == "启用发现", "发现：只保留启用且配置了发现地址的书源")
        check(DiscoverCatalog.explorableSources([noExplore]).isEmpty, "发现：没有发现地址不参与")
        var blank = enabled
        blank.exploreUrl = "   "
        check(DiscoverCatalog.explorableSources([blank]).isEmpty, "发现：空白发现地址不参与")

        // 2. 分组：顺序 + 默认分组置底
        var g1 = enabled
        g1.bookSourceGroup = "源仓库,漫画 书源"
        var g2 = BookSource(bookSourceUrl: "https://e.invalid", bookSourceName: "乙")
        g2.exploreUrl = "/e"
        g2.bookSourceGroup = "常规"
        var g3 = BookSource(bookSourceUrl: "https://f.invalid", bookSourceName: "丙")
        g3.exploreUrl = "/f"
        let sections = DiscoverCatalog.sections([g1, g2, g3])
        check(sections.count == 3 && sections[0].name == "源仓库" && sections[1].name == "常规"
              && sections[2].name == BookSource.defaultGroupName, "发现：分组顺序与默认分组置底")
        check(sections[2].sources.map(\.bookSourceName) == ["丙"], "发现：默认分组内容")
        check(DiscoverCatalog.sources(inGroup: "常规", from: [g1, g2, g3]).map(\.bookSourceName) == ["乙"],
              "发现：分组内书源")

        // 3. 域名
        check(DiscoverCatalog.displayDomain("https://comic.mkzcdn.com") == "comic.mkzcdn.com", "发现：域名")
        check(DiscoverCatalog.displayDomain("https://a.b.c/list?q=1#f") == "a.b.c", "发现：带路径只取主机")
        check(DiscoverCatalog.displayDomain("comic.mkzcdn.com/x") == "comic.mkzcdn.com", "发现：缺协议头")
        check(DiscoverCatalog.displayDomain("") == "", "发现：空地址")

        // 4. 类型标签
        var manga = g1
        manga.bookSourceType = 2
        check(manga.discoverTypeLabel == "图片" && enabled.discoverTypeLabel == nil, "发现：类型标签（文本不显示）")

        // 5. 头像色稳定且确定
        check(DiscoverCatalog.avatarHue(for: "武芊漫画") == DiscoverCatalog.avatarHue(for: "武芊漫画"), "发现：头像色稳定")
        check((0..<1).contains(DiscoverCatalog.avatarHue(for: "Bing")), "发现：头像色范围")

        // 6. 分类切节纯函数
        let mixed = [SourceDiagnostics.ExploreKind(title: "头条", url: "/t"),
                     SourceDiagnostics.ExploreKind(title: "推荐", url: nil),
                     SourceDiagnostics.ExploreKind(title: "全部", url: "/a"),
                     SourceDiagnostics.ExploreKind(title: "修真", url: "/b"),
                     SourceDiagnostics.ExploreKind(title: "空标题组", url: nil)]
        let cut = DiscoverCatalog.kindSections(mixed)
        check(cut.count == 2 && cut[0].header == nil && cut[0].items.count == 1
              && cut[1].header == "推荐" && cut[1].items.count == 2, "发现：分类切节（无网址作小节标题、空小节丢弃）")

        // 7. 真实夹具：武芊漫画（离线执行发现 @js）
        let list = try JSONDecoder().decode([BookSource].self,
                                            from: Data(contentsOf: dir.appendingPathComponent("manga-wuqian.json")))
        guard let wuqian = list.first(where: { $0.bookSourceName == "武芊漫画" }) else {
            check(false, "发现：武芊漫画夹具可解码")
            return
        }
        check(DiscoverCatalog.explorableSources(list).contains { $0.bookSourceName == "武芊漫画" }, "发现：武芊漫画可发现")
        check(DiscoverCatalog.sources(inGroup: "源仓库", from: list).contains { $0.bookSourceName == "武芊漫画" },
              "发现：武芊漫画归到源仓库分组")
        let kinds = SourceDiagnostics.exploreKinds(source: wuqian)
        check(kinds.count == 74, "发现：武芊漫画分类数量 74（2 顶部 + 3×24）")
        let grouped = DiscoverCatalog.kindSections(kinds)
        check(grouped.count == 4, "发现：切出 4 段（顶部 + 推荐/最热/最新）")
        check(grouped.first?.header == nil && grouped.first?.items.count == 2, "发现：顶部 2 个入口无标题")
        check(grouped[1].header == "推荐" && grouped[1].items.count == 23
              && grouped[1].items.first?.title == "全部", "发现：推荐组 23 个分类，首个为全部")
        check(grouped[3].header == "最新" && grouped[3].items.allSatisfy { !($0.url ?? "").isEmpty },
              "发现：最新组全部带网址")
        check(grouped[1].items.allSatisfy { ($0.url ?? "").contains("page_num={{page}}") },
              "发现：分类网址保留 {{page}} 供加载更多")
        check(DiscoverCatalog.kindError([SourceDiagnostics.ExploreKind(title: "ERROR:发现脚本执行失败", url: nil)]) != nil,
              "发现：脚本错误识别")
    }
}
