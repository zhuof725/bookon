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

        // 3b. 卡片副标题：分组优先，缺省显示域名
        var titled = enabled
        titled.bookSourceGroup = "源仓库,漫画 书源"
        check(DiscoverCatalog.cardSubtitle(titled) == "源仓库,漫画 书源", "发现：卡片副标题显示分组原串")
        var blankGroup = enabled
        blankGroup.bookSourceGroup = "   "
        check(DiscoverCatalog.cardSubtitle(blankGroup) == "a.invalid", "发现：空白分组回落域名")
        check(DiscoverCatalog.cardSubtitle(enabled) == "a.invalid", "发现：无分组显示域名")

        // 3c. 排列方式偏好：存储值与显示名
        check(SourceListLayout(rawValue: "grid") == SourceListLayout.grid
              && SourceListLayout(rawValue: "list") == SourceListLayout.list
              && SourceListLayout(rawValue: "wat") == nil, "排列方式：存储值")
        check(SourceListLayout.grid.title == "网格" && SourceListLayout.list.title == "列表", "排列方式：显示名")

        // 3d. 发现控件解析（书山聚合扩展）：type/action/chars/default/布局百分比
        let controlRule = """
        [{"title":"☃关键词","type":"text","style":{"layout_flexGrow":1,"layout_flexBasisPercent":0.6}},
         {"title":"源站","type":"select","chars":["A站","B站"],"default":"A站","action":"(function(){ setConfigs.call(this,{source:'A'}); })()","style":{"layout_flexBasisPercent":0.4}},
         {"title":"推荐","url":"/rec"}]
        """
        let controlKinds = SourceDiagnostics.parseExploreKinds(controlRule)
        check(controlKinds.count == 3, "发现：控件数组解析数量")
        check(controlKinds[0].type == "text" && controlKinds[0].url == nil, "发现：text 控件识别")
        check(controlKinds[1].type == "select" && controlKinds[1].chars == ["A站", "B站"]
              && controlKinds[1].defaultValue == "A站" && (controlKinds[1].action ?? "").contains("setConfigs"),
              "发现：select 控件字段")
        check(abs((controlKinds[1].flexBasis ?? 0) - 0.4) < 0.0001, "发现：控件布局百分比")
        check(controlKinds[2].type == nil && controlKinds[2].url == "/rec", "发现：普通分类保持原样")
        let controlSections = DiscoverCatalog.kindSections(controlKinds)
        check(controlSections.count == 1 && controlSections[0].items.map(\.title) == ["推荐"],
              "发现：控件不进入分类小节")
        check(DiscoverCatalog.isRankingTitle("个性推荐") && DiscoverCatalog.isRankingTitle("巅峰榜单")
              && DiscoverCatalog.isRankingTitle("热搜榜"), "发现：榜单分类识别")
        check(!DiscoverCatalog.isRankingTitle("猜你喜欢") && !DiscoverCatalog.isRankingTitle("西方奇幻"),
              "发现：普通分类识别")

        // 3d-2. 控件标题清洗：书源标题带图标与说明，界面只显示名称
        check(DiscoverCatalog.controlTitle("☃关键词💭：书名/作者") == "关键词",
              "发现：控件标题取冒号前并去图标（实际 \(DiscoverCatalog.controlTitle("☃关键词💭：书名/作者"))）")
        check(DiscoverCatalog.controlTitle("晋江标签") == "晋江标签", "发现：无修饰的控件标题原样保留")
        check(DiscoverCatalog.controlTitle("🏷 言情") == "言情", "发现：控件标题去 emoji 与空格")
        check(DiscoverCatalog.controlTitle("性别 ♂ 男频") == "性别 男频",
              "发现：控件标题保留词间空格（实际 \(DiscoverCatalog.controlTitle("性别 ♂ 男频"))）")
        check(DiscoverCatalog.controlTitle("源站") == "源站", "发现：短标题不改动")
        check(DiscoverCatalog.controlTitle("🔍搜索") == "搜索", "发现：按钮标题去图标")
        check(!DiscoverCatalog.controlTitle("💭").isEmpty, "发现：纯图标标题回落为原串不返回空")

        // 3d-3. 控件集合：三类控件分开放，值取默认；重复标题只留一条
        let controlSet = SourceControlSet(kinds: [
            SourceDiagnostics.ExploreKind(title: "☃关键词💭：书名/作者", url: nil, type: "text"),
            SourceDiagnostics.ExploreKind(title: "🔍搜索", url: nil, type: "button"),
            SourceDiagnostics.ExploreKind(title: "性别", url: nil, type: "select",
                                          chars: ["♂️男频", "♀️女频"], defaultValue: "♀️女频"),
            SourceDiagnostics.ExploreKind(title: "性别", url: nil, type: "select",
                                          chars: ["♂️男频", "♀️女频"], defaultValue: "♀️女频"),
            SourceDiagnostics.ExploreKind(title: "我的书架", url: "/shelf")
        ])
        check(controlSet.texts.count == 1 && controlSet.buttons.count == 1,
              "控件：输入与按钮各一条")
        check(controlSet.selects.count == 1, "控件：重复标题只留一条")
        check(controlSet.values["性别"] == "♀️女频", "控件：下拉默认值取书源给的 default")
        check(controlSet.keyword.isEmpty, "控件：没有输入时关键词为空")
        check(SourceControlSet(kinds: []).isEmpty, "控件：没有控件时为空集")
        check(SourceControlSet.isRefreshOnly(SourceDiagnostics.ExploreKind(
                title: "🔁", url: nil, type: "button", action: "java.refreshExplore()")),
              "控件：纯刷新按钮识别")
        check(!SourceControlSet.isRefreshOnly(SourceDiagnostics.ExploreKind(
                title: "性别", url: nil, type: "select",
                action: "setConfigs.call(this,{gender:'boy'}); java.refreshExplore()")),
              "控件：写配置的下拉不算纯刷新")

        // 3d-4. 可选取分类分组：控件项去掉，分组标题保留
        let mixedKinds = [
            SourceDiagnostics.ExploreKind(title: "☃关键词", url: nil, type: "text"),
            SourceDiagnostics.ExploreKind(title: "性别", url: nil, type: "select", chars: ["男", "女"]),
            SourceDiagnostics.ExploreKind(title: "男频榜单", url: nil),
            SourceDiagnostics.ExploreKind(title: "月票榜单", url: "/a"),
            SourceDiagnostics.ExploreKind(title: "畅销榜单", url: "/b"),
            SourceDiagnostics.ExploreKind(title: "女频榜单", url: nil),
            SourceDiagnostics.ExploreKind(title: "月票榜单", url: "/c")
        ]
        let selectable = DiscoverCatalog.selectableKindSections(mixedKinds)
        check(selectable.count == 2, "可选取分类：切成两组")
        check(selectable[0].header == "男频榜单" && selectable[0].items.count == 2,
              "可选取分类：控件项不进网格")
        check(selectable[1].header == "女频榜单" && selectable[1].items.count == 1,
              "可选取分类：同名分类分属不同组")
        check(selectable.flatMap(\.items).allSatisfy { !($0.url ?? "").isEmpty },
              "可选取分类：全部带网址")
        check(DiscoverCatalog.isDecorativeControlTitle("██████ 男 生 ██████"), "发现：装饰性控件标题识别")
        check(DiscoverCatalog.isDecorativeControlTitle("■■■■■■■■ 男 生 ■■■■■■■■"), "发现：真实七猫横幅识别")
        check(DiscoverCatalog.isDecorativeControlTitle("████████████████"), "发现：纯方块横幅识别")
        check(DiscoverCatalog.isDecorativeControlTitle("■□●○◆◇★☆"), "发现：其它填充符识别")
        check(!DiscoverCatalog.isDecorativeControlTitle("性别") && !DiscoverCatalog.isDecorativeControlTitle("源站")
              && !DiscoverCatalog.isDecorativeControlTitle("段评图标")
              && !DiscoverCatalog.isDecorativeControlTitle("性别 ♂ 男频"), "发现：正常控件标题保留")
        let bannerKinds = [
            SourceDiagnostics.ExploreKind(title: "■■■■■■■■ 男 生 ■■■■■■■■", url: nil),
            SourceDiagnostics.ExploreKind(title: "都市人生", url: "/a"),
            SourceDiagnostics.ExploreKind(title: "异术超能", url: "/b")
        ]
        check(DiscoverCatalog.kindSections(bannerKinds).count == 1
              && DiscoverCatalog.kindSections(bannerKinds).first?.header == nil
              && DiscoverCatalog.kindSections(bannerKinds).first?.items.count == 2,
              "发现：装饰横幅不渲染为分类标题")

        // 3e. 发现设置：关键词解析、样式判定、列数钳制
        check(DiscoverSettings.keywords(from: nil) == DiscoverSettings.defaultKeywords, "设置：默认关键词")
        check(DiscoverSettings.keywords(from: " ,榜, 排行 ") == ["榜", "排行"], "设置：关键词解析去空")
        check(DiscoverSettings.keywords(from: "玄幻") == ["玄幻"], "设置：自定义关键词")
        check(DiscoverSettings.usesVerticalStyle(index: 0, title: "巅峰榜单", mode: .keyword, keywords: ["榜"]), "设置：关键词命中竖排")
        check(!DiscoverSettings.usesVerticalStyle(index: 0, title: "猜你喜欢", mode: .keyword, keywords: ["榜"]), "设置：未命中横滑")
        check(DiscoverSettings.usesVerticalStyle(index: 0, title: "猜你喜欢", mode: .vertical, keywords: []), "设置：全部竖排")
        check(!DiscoverSettings.usesVerticalStyle(index: 0, title: "巅峰榜单", mode: .horizontal, keywords: ["榜"]), "设置：全部横滑")
        check(DiscoverSettings.usesVerticalStyle(index: 0, title: "任意", mode: .cycle, keywords: [], cycleVertical: 1, cycleHorizontal: 1)
              && !DiscoverSettings.usesVerticalStyle(index: 1, title: "任意", mode: .cycle, keywords: [], cycleVertical: 1, cycleHorizontal: 1)
              && DiscoverSettings.usesVerticalStyle(index: 2, title: "任意", mode: .cycle, keywords: [], cycleVertical: 1, cycleHorizontal: 1), "设置：循环顺序 1+1")
        check(DiscoverSettings.usesVerticalStyle(index: 0, title: "任意", mode: .cycle, keywords: [], cycleVertical: 2, cycleHorizontal: 1)
              && DiscoverSettings.usesVerticalStyle(index: 1, title: "任意", mode: .cycle, keywords: [], cycleVertical: 2, cycleHorizontal: 1)
              && !DiscoverSettings.usesVerticalStyle(index: 2, title: "任意", mode: .cycle, keywords: [], cycleVertical: 2, cycleHorizontal: 1), "设置：循环顺序 2+1")
        check(!DiscoverSettings.usesVerticalStyle(index: 5, title: "任意", mode: .cycle, keywords: [], cycleVertical: 0, cycleHorizontal: 2),
              "设置：循环全横滑")
        check(DiscoverSettings.usesVerticalStyle(index: 5, title: "任意", mode: .cycle, keywords: [], cycleVertical: 3, cycleHorizontal: 0),
              "设置：循环全竖排")
        check(DiscoverSettings.clampedColumns(1) == 2 && DiscoverSettings.clampedColumns(9) == 5
              && DiscoverSettings.clampedColumns(3) == 3, "设置：列数钳制 2...5")
        check(DiscoverSettings.RankingMode(rawValue: "cycle") == DiscoverSettings.RankingMode.cycle
              && DiscoverSettings.RankingMode(rawValue: "keyword") == DiscoverSettings.RankingMode.keyword
              && DiscoverSettings.PageLayout(rawValue: "list") == DiscoverSettings.PageLayout.list, "设置：枚举存储值")

        // 3f. 缓存往返：板块书单与发现分类（真实文件读写）
        DiscoverBlockCache.clear()
        DiscoverKindsCache.clear()
        let cacheSource = "https://cache.test/source"
        let cacheURL = "/list?page=1"
        var cacheBook = Book(bookUrl: "https://book.test/1", name: "缓存测试书", author: "作者",
                             origin: cacheSource)
        cacheBook.intro = "简介"
        DiscoverBlockCache.store(source: cacheSource, url: cacheURL, books: [cacheBook])
        let cachedBooks = DiscoverBlockCache.cached(source: cacheSource, url: cacheURL)
        check(cachedBooks?.count == 1 && cachedBooks?.first?.name == "缓存测试书"
              && cachedBooks?.first?.intro == "简介", "缓存：板块书单往返")
        check(DiscoverBlockCache.cached(source: cacheSource, url: cacheURL,
                                        now: Date().addingTimeInterval(400 * 86400)) == nil,
              "缓存：过期后为空")
        let cacheKinds = [SourceDiagnostics.ExploreKind(title: "推荐", url: "/rec"),
                          SourceDiagnostics.ExploreKind(title: "性别", url: nil, type: "select",
                                                        chars: ["男", "女"], defaultValue: "男")]
        DiscoverKindsCache.store(source: cacheSource, kinds: cacheKinds)
        check(DiscoverKindsCache.cached(source: cacheSource) == cacheKinds, "缓存：发现分类往返")
        DiscoverBlockCache.clear()
        DiscoverKindsCache.clear()
        check(DiscoverBlockCache.cached(source: cacheSource, url: cacheURL) == nil
              && DiscoverKindsCache.cached(source: cacheSource) == nil, "缓存：清理后为空")

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
        check(kinds.count == 77, "发现：武芊漫画分类数量 77（实际 \(kinds.count)）")
        let grouped = DiscoverCatalog.kindSections(kinds)
        check(grouped.count == 4, "发现：切出 4 段（顶部 + 推荐/最热/最新）")
        check(grouped.first?.header == nil && grouped.first?.items.count == 2, "发现：顶部 2 个入口无标题")
        check(grouped[1].header == "推荐" && grouped[1].items.count == 24
              && grouped[1].items.first?.title == "全部",
              "发现：推荐组 24 个分类（实际 \(grouped[1].items.count)），首个为全部")
        check(grouped[3].header == "最新" && grouped[3].items.allSatisfy { !($0.url ?? "").isEmpty },
              "发现：最新组全部带网址")
        check(grouped[1].items.allSatisfy { ($0.url ?? "").contains("page_num={{page}}") },
              "发现：分类网址保留 {{page}} 供加载更多")
        check(DiscoverCatalog.kindError([SourceDiagnostics.ExploreKind(title: "ERROR:发现脚本执行失败", url: nil)]) != nil,
              "发现：脚本错误识别")
    }
}
