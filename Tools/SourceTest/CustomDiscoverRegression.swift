import Foundation

/// 自定义发现配置的离线回归：增删、去重、排序、解码容错、书目可见性。
/// 全部纯函数，不联网。
enum CustomDiscoverRegression {
    static func run(_ check: (Bool, String) -> Void) throws {
        // 1. 解码容错：坏 JSON / 缺字段一律回落空配置
        check(CustomDiscoverStore.decode(Data("not json".utf8)).entries.isEmpty,
              "自定义发现：坏 JSON 回落空配置")
        check(CustomDiscoverStore.decode(Data("{}".utf8)).entries.isEmpty,
              "自定义发现：空对象回落空配置")
        let partial = Data(#"{"entries":[{"sourceUrl":"u1","kindUrl":"/a"}]}"#.utf8)
        let decoded = CustomDiscoverStore.decode(partial)
        check(decoded.entries.count == 1
              && decoded.entries[0].template == .deck
              && decoded.entries[0].sourceName == "",
              "自定义发现：缺 template 回落卡片堆叠，缺书名不崩")

        // 1.1 已下线的扇形展开不能让老配置变空板块
        check(DiscoverTemplateKind.normalized("fan") == .curve,
              "模板：扇形展开的旧配置迁移到弧形走廊")
        check(DiscoverTemplateKind.normalized(nil) == .deck,
              "模板：缺模板键回落卡片堆叠")
        check(DiscoverTemplateKind.normalized("notATemplate") == .deck,
              "模板：未知模板回落卡片堆叠")
        let fanJSON = Data(#"{"entries":[{"sourceUrl":"u1","kindUrl":"/a","template":"fan"}]}"#.utf8)
        let fanConfig = CustomDiscoverStore.decode(fanJSON)
        check(fanConfig.entries.count == 1 && fanConfig.entries[0].template == .curve,
              "模板：扇形展开的老配置能正常读成弧形走廊")

        // 2. 增删与去重
        var config = CustomDiscoverConfig()
        let entryA = CustomDiscoverEntry(sourceUrl: "u1", sourceName: "书源甲",
                                         kindTitle: "热播周榜", kindUrl: "/a", template: .deck)
        config.upsert(entryA)
        check(config.entries.count == 1, "自定义发现：首次添加写入一条")
        var entryADup = entryA
        entryADup.template = .curve
        config.upsert(entryADup)
        check(config.entries.count == 1 && config.entries[0].template == .curve,
              "自定义发现：同一书源同一分类重复添加只更新模板")
        let entryB = CustomDiscoverEntry(sourceUrl: "u2", sourceName: "书源乙",
                                         kindTitle: "月票榜", kindUrl: "/b", template: .curve)
        config.upsert(entryB)
        check(config.entries.map(\.kindTitle) == ["热播周榜", "月票榜"],
              "自定义发现：不同分类追加到末尾")
        check(entryA.id == entryADup.id && entryA.id != entryB.id,
              "自定义发现：条目 id 由书源 + 分类地址决定")

        // 3. 拖拽排序（onMove 语义）
        let third = CustomDiscoverEntry(sourceUrl: "u3", sourceName: "书源丙",
                                        kindTitle: "新书榜", kindUrl: "/c")
        config.upsert(third)
        var moving = config
        moving.move(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        check(moving.entries.map(\.kindTitle) == ["新书榜", "热播周榜", "月票榜"],
              "自定义发现：末项拖到最前")
        var movingDown = config
        movingDown.move(fromOffsets: IndexSet(integer: 0), toOffset: 3)
        check(movingDown.entries.map(\.kindTitle) == ["月票榜", "新书榜", "热播周榜"],
              "自定义发现：首项拖到最后")
        var movingSame = config
        movingSame.move(fromOffsets: IndexSet(integer: 1), toOffset: 1)
        check(movingSame.entries.map(\.kindTitle) == config.entries.map(\.kindTitle),
              "自定义发现：原地拖动顺序不变")

        // 4. 删除
        var deleting = config
        deleting.remove(id: entryB.id)
        check(deleting.entries.map(\.kindTitle) == ["热播周榜", "新书榜"],
              "自定义发现：按 id 删除")

        // 5. 可见性：书源被删 / 没配发现地址 / 分类地址为空 都不显示
        //    此刻 config 含三条：u1(热播周榜) / u2(月票榜) / u3(新书榜)
        var live = BookSource(bookSourceUrl: "u1", bookSourceName: "书源甲")
        live.exploreUrl = "/explore"
        // u2 有书源但发现地址是空白 → 不参与发现
        var noExplore = BookSource(bookSourceUrl: "u2", bookSourceName: "书源乙")
        noExplore.exploreUrl = "  "
        // u3 干脆不在书源列表里（已删除）
        var hidden = config
        hidden.upsert(CustomDiscoverEntry(sourceUrl: "ghost", sourceName: "已删除",
                                          kindTitle: "幽灵", kindUrl: "/g"))
        hidden.upsert(CustomDiscoverEntry(sourceUrl: "u1", sourceName: "书源甲",
                                          kindTitle: "空地址", kindUrl: ""))
        let visible = hidden.visibleEntries(from: [live, noExplore])
        // 只剩 u1 的「热播周榜」：幽灵源不在列表、u1 的空地址条目不显示、
        // u2 发现地址是空白、u3 不在书源列表
        check(visible.map(\.kindTitle) == ["热播周榜"],
              "自定义发现：书源不存在、未配发现地址、分类地址为空都不显示")
        // 补上 u2（给了正常发现地址）后，「月票榜」应该回来
        noExplore.exploreUrl = "/explore"
        let visible2 = hidden.visibleEntries(from: [live, noExplore])
        check(visible2.map(\.kindTitle) == ["热播周榜", "月票榜"],
              "自定义发现：补上发现地址后条目恢复显示")
        check(!visible2.contains { $0.kindTitle == "新书榜" },
              "自定义发现：书源已删除的条目仍然隐藏")

        // 6. 书源改名后标题跟着变
        var renamed = config
        var renamedSource = live
        renamedSource.bookSourceName = "书源甲（新）"
        renamed.refreshNames(from: [renamedSource])
        check(renamed.entries.first?.sourceName == "书源甲（新）",
              "自定义发现：书源改名后板块标题同步")

        // 7. 板块标题：只显示分类名，不拼书源名
        check(entryA.boardTitle == "热播周榜", "自定义发现：标题只用分类名")
        var sameName = entryA
        sameName.sourceName = "热播周榜"
        check(sameName.boardTitle == "热播周榜", "自定义发现：书源名与分类同名时仍只显示一个")
        var emptyKind = entryA
        emptyKind.kindTitle = "  "
        check(emptyKind.boardTitle == "书源甲", "自定义发现：分类名为空才回落到书源名")

        // 8. 顶部分类：手写优先，未写时按书源名自动生成
        var catConfig = CustomDiscoverConfig(categories: ["起点", "番茄"], entries: [entryA, entryB])
        check(catConfig.effectiveCategories == ["起点", "番茄"], "分类：手写标题按原顺序")
        catConfig.categories = []
        check(catConfig.effectiveCategories == ["书源甲", "书源乙"],
              "分类：未配置时按板块里出现过的书源名生成")
        catConfig.categories = ["  ", ""]
        check(catConfig.effectiveCategories == ["书源甲", "书源乙"],
              "分类：全空白等于没配置")

        // 分类筛选板块
        var screen = CustomDiscoverConfig(categories: [], entries: [entryA, entryB, third])
        check(screen.entries(inCategory: CustomDiscoverConfig.allCategory).count == 3,
              "分类：「全部」返回所有板块")
        check(screen.entries(inCategory: "书源甲").map(\.kindTitle) == ["热播周榜"],
              "分类：按书源名筛出对应板块")
        check(screen.entries(inCategory: "不存在的源").count == 3,
              "分类：匹配不到时退回全量，避免空白页")
        check(screen.entries(inCategory: "  ").count == 3, "分类：空标题当全部处理")

        // 9. 外观参数默认值与钳制
        check(entryA.scale == 1 && entryA.corner == 8 && entryA.showNumber,
              "外观：默认 1x / 8 圆角 / 显示序号")
        let weird = Data(#"{"entries":[{"sourceUrl":"u","kindUrl":"/k","scale":99,"corner":-5}]}"#.utf8)
        let w = CustomDiscoverStore.decode(weird)
        check(w.entries[0].scale == 1.6, "外观：过大倍率钳到 1.6")
        check(w.entries[0].corner == 0, "外观：负圆角钳到 0")
        let weird2 = Data(#"{"entries":[{"sourceUrl":"u","kindUrl":"/k","scale":0.1,"corner":99}]}"#.utf8)
        let w2 = CustomDiscoverStore.decode(weird2)
        check(w2.entries[0].scale == 0.6, "外观：过小倍率钳到 0.6")
        check(w2.entries[0].corner == 20, "外观：过大圆角钳到 20")

        // 9. 落盘往返
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("custom-discover-\(UUID().uuidString).json")
        check(CustomDiscoverStore.save(config, to: tmp), "自定义发现：写盘成功")
        let reloaded = CustomDiscoverStore.load(from: tmp)
        check(reloaded.entries.map(\.id) == config.entries.map(\.id),
              "自定义发现：写盘后读回条目一致")
        check(reloaded.entries.map(\.template) == config.entries.map(\.template),
              "自定义发现：写盘后读回模板一致")
        try? FileManager.default.removeItem(at: tmp)

        // 10. 数量上限不写死，但空配置要能被识别
        check(CustomDiscoverConfig().isEmpty, "自定义发现：空配置可识别")
        check(!config.isEmpty, "自定义发现：有板块不是空配置")

        // 11. 模板表：十四个模板都注册了，且数据源归属正确
        check(DiscoverTemplate.all.count == DiscoverTemplateKind.allCases.count,
              "模板：列表长度等于枚举数量")
        check(DiscoverTemplateKind.allCases.map(\.rawValue)
              == ["largeCard", "compactCard", "threeColumn", "dualRow", "fixedList",
                  "featureCard", "updateFeed",
                  "badgeGrid", "covers", "rankRow", "waterfall", "curve", "deck", "history"],
              "模板：十四个模板的稳定键")
        for kind in DiscoverTemplateKind.allCases {
            check(DiscoverTemplate.template(for: kind).kind == kind,
                  "模板：\(kind.title) 能按枚举取回")
            check(!kind.title.isEmpty && !kind.detail.isEmpty,
                  "模板：\(kind.rawValue) 有标题和说明")
        }
        check(DiscoverTemplateKind.largeCard.dataSource == .bookList
              && DiscoverTemplateKind.compactCard.dataSource == .bookList
              && DiscoverTemplateKind.threeColumn.dataSource == .bookList
              && DiscoverTemplateKind.dualRow.dataSource == .bookList
              && DiscoverTemplateKind.fixedList.dataSource == .bookList
              && DiscoverTemplateKind.featureCard.dataSource == .bookList
              && DiscoverTemplateKind.updateFeed.dataSource == .bookList,
              "模板：七种新版式都吃书籍列表")
        check(DiscoverTemplateKind.badgeGrid.dataSource == .bookList
              && DiscoverTemplateKind.covers.dataSource == .bookList
              && DiscoverTemplateKind.rankRow.dataSource == .bookList
              && DiscoverTemplateKind.waterfall.dataSource == .bookList
              && DiscoverTemplateKind.curve.dataSource == .bookList
              && DiscoverTemplateKind.deck.dataSource == .bookList,
              "模板：六种书籍布局都吃书籍列表")
        check(DiscoverTemplateKind.history.dataSource == .readingProgress,
              "模板：继续阅读吃阅读进度")

        // 11.1 展示库分组：三组都能列全，不重不漏
        let families = DiscoverTemplateFamily.allCases
        check(families.map(\.title) == ["版式", "视觉", "阅读记录"],
              "展示库：三组按固定顺序排列")
        check(families.allSatisfy { !$0.detail.isEmpty }, "展示库：每组都有说明")
        let groupedKinds = families.flatMap { $0.templates }
        check(groupedKinds.count == DiscoverTemplate.all.count,
              "展示库：分组覆盖全部模板")
        check(Set(groupedKinds.map(\.kind)) == Set(DiscoverTemplateKind.allCases),
              "展示库：分组不重复、不遗漏任何模板")
        check(DiscoverTemplateFamily.record.templates.map(\.kind) == [.history],
              "展示库：阅读记录组只有继续阅读")
        check(families.reduce(0) { $0 + $1.templates.count } == DiscoverTemplate.all.count,
              "展示库：各组模板数之和等于总数")

        // 12. 数量钳制：上限统一 20，下限统一 1
        let curve = DiscoverTemplate.template(for: .curve)
        check(curve.maxCount == 20 && curve.minCount == 1, "模板：上限 20、下限 1")
        for template in DiscoverTemplate.all {
            check(template.maxCount == DiscoverTemplate.countCeiling,
                  "模板：\(template.title) 上限也是 20")
        }
        for template in DiscoverTemplate.all {
            check(template.defaultCount == 20, "模板：\(template.title) 默认显示 20")
        }
        check(curve.clampedCount(0) == 1, "模板：数量低于下限钳到 1")
        check(curve.clampedCount(999) == 20, "模板：数量高于上限钳到 20")
        check(curve.clampedCount(20) == 20, "模板：正好 20 不受影响")
        check(curve.clampedCount(6) == 6, "模板：范围内原样返回")
        check(curve.clampedCount(DiscoverTemplate.unlimited) == DiscoverTemplate.unlimited,
              "模板：unlimited 不被钳制（「全部」页不限数量）")
        check(DiscoverTemplate.isUnlimited(DiscoverTemplate.unlimited),
              "模板：isUnlimited 能识别不限数量")
        check(!DiscoverTemplate.isUnlimited(20), "模板：20 不是 unlimited")

        // 13. 换模板：数量不再被强行改（上下限统一 20）
        var wide = CustomDiscoverEntry(sourceUrl: "u1", sourceName: "甲",
                                       kindTitle: "榜", kindUrl: "/a",
                                       template: .curve, count: 20)
        wide.applyTemplate(.waterfall)
        check(wide.template == .waterfall && wide.count == 20,
              "模板：统一上限后换模板不改数量")
        wide.count = 999
        wide.applyTemplate(.deck)
        check(wide.count == 20, "模板：越界数量在换模板时被钳回 20")

        // 14. 解码：未知模板回落 + 数量越界被钳制
        let badTemplate = Data(#"{"entries":[{"sourceUrl":"u","kindUrl":"/k","template":"nope","count":999}]}"#.utf8)
        let bad = CustomDiscoverStore.decode(badTemplate)
        check(bad.entries.count == 1
              && bad.entries[0].template == .deck
              && bad.entries[0].count == 20,
              "模板：未知模板回落卡片堆叠，数量越界被钳到 20")

        // 15. 旧配置兼容：之前的 badgeGrid / covers / rankRow 仍能读
        let legacy = Data(#"{"entries":[{"sourceUrl":"u","kindUrl":"/a","style":"badgeGrid"},{"sourceUrl":"u","kindUrl":"/b","style":"covers"},{"sourceUrl":"u","kindUrl":"/c","style":"rankRow"}]}"#.utf8)
        let legacyConfig = CustomDiscoverStore.decode(legacy)
        check(legacyConfig.entries.count == 3, "模板：旧字段 style 不会导致整条丢失")
        check(legacyConfig.entries.allSatisfy { $0.template == .deck },
              "模板：旧字段读不出时回落卡片堆叠")

        // 16. 不依赖书源的板块（继续阅读）不能被书源过滤丢掉
        let historyEntry = CustomDiscoverEntry(sourceUrl: "", sourceName: "书架",
                                               kindTitle: "继续阅读",
                                               kindUrl: "history://shelf",
                                               template: .history)
        let withHistory = CustomDiscoverConfig(categories: [], entries: [historyEntry, entryA])
        let kept = withHistory.visibleEntries(from: [live])
        check(kept.map(\.template) == [.history, .deck],
              "分类：继续阅读板块来源为空也保留")
        check(!kept.isEmpty && kept.contains { $0.template == .history },
              "分类：继续阅读不会被书源过滤掉")

        // 17. 分类与轮播同序
        let ordered = CustomDiscoverConfig(categories: ["甲", "乙", "丙"], entries: [])
        check(ordered.effectiveCategories == ["甲", "乙", "丙"],
              "分类：轮播页与分类同序（手写顺序即轮播顺序）")

        // 18. 一次性分组：与逐分类过滤结果一致
        var grouped = CustomDiscoverConfig(categories: [], entries: [entryA, entryB, third])
        let byCategory = grouped.entriesByCategory()
        check(byCategory[CustomDiscoverConfig.allCategory]?.count == 3,
              "分组：「全部」包含所有条目")
        check(byCategory["书源甲"]?.count == 1 && byCategory["书源乙"]?.count == 1,
              "分组：按书源名各自归组")
        // 和逐个调用 entries(inCategory:) 的结果对齐
        for name in ["书源甲", "书源乙", "书源丙"] {
            let fast = Set(byCategory[name]?.map(\.id) ?? [])
            let slow = Set(grouped.entries(inCategory: name).map(\.id))
            check(fast == slow, "分组：\(name) 与逐分类过滤结果一致")
        }
        // 不存在的分类在分组字典里没有键，调用方靠回退兜底
        check(byCategory["不存在的源"] == nil, "分组：未出现的分类不产生键")

        // 19. 轮播数据源：配置了书源+分类才算启用
        var carouselConfig = CustomDiscoverConfig()
        check(!carouselConfig.hasCarousel, "轮播：默认未配置")
        carouselConfig.carouselSourceUrl = "u1"
        carouselConfig.carouselKindTitle = "热播周榜"
        carouselConfig.carouselKindUrl = "/a"
        check(carouselConfig.hasCarousel, "轮播：书源+分类都填了才启用")
        carouselConfig.carouselHidden = true
        check(!carouselConfig.hasCarousel, "轮播：关掉开关即视为未配置")
        carouselConfig.carouselHidden = false
        carouselConfig.carouselKindUrl = ""
        check(!carouselConfig.hasCarousel, "轮播：缺分类地址不启用")

        // 19.1 轮播模板：默认大卡片，记录模板读不进来，写盘能往返
        check(CustomDiscoverConfig().carouselTemplate == .largeCard,
              "轮播模板：默认大型阅读卡片")
        check(CustomDiscoverConfig().effectiveCarouselTemplate == .largeCard,
              "轮播模板：默认就是可用的书籍模板")
        var templateConfig = CustomDiscoverConfig()
        templateConfig.carouselTemplate = .history
        check(templateConfig.effectiveCarouselTemplate == .largeCard,
              "轮播模板：记录模板回落大卡片（轮播只吃书籍列表）")
        templateConfig.carouselTemplate = .threeColumn
        check(templateConfig.effectiveCarouselTemplate == .threeColumn,
              "轮播模板：书籍模板原样使用")
        let oldCarouselJSON = Data(#"{"carouselSourceUrl":"u1","carouselKindUrl":"/a"}"#.utf8)
        let oldCarouselConfig = CustomDiscoverStore.decode(oldCarouselJSON)
        check(oldCarouselConfig.carouselTemplate == .largeCard,
              "轮播模板：老配置没有该字段时回落到大卡片")
        let retiredJSON = Data(#"{"carouselSourceUrl":"u1","carouselKindUrl":"/a","carouselTemplate":"fan"}"#.utf8)
        check(CustomDiscoverStore.decode(retiredJSON).carouselTemplate == .curve,
              "轮播模板：已下线的扇形迁移到弧形走廊")
        let recordJSON = Data(#"{"carouselTemplate":"history"}"#.utf8)
        check(CustomDiscoverStore.decode(recordJSON).carouselTemplate == .largeCard,
              "轮播模板：配置里写了记录模板也会被纠正回大卡片")

        // 20. 轮播字段能落盘往返
        let carouselTmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("carousel-\(UUID().uuidString).json")
        var saveConfig = CustomDiscoverConfig(entries: [entryA])
        saveConfig.carouselSourceUrl = "u1"
        saveConfig.carouselKindTitle = "热播周榜"
        saveConfig.carouselKindUrl = "/a"
        saveConfig.carouselTemplate = .threeColumn
        check(CustomDiscoverStore.save(saveConfig, to: carouselTmp), "轮播：写盘成功")
        let reloadedCarousel = CustomDiscoverStore.load(from: carouselTmp)
        check(reloadedCarousel.carouselTemplate == .threeColumn,
              "轮播模板：写盘后读回一致")
        check(reloadedCarousel.carouselSourceUrl == "u1"
              && reloadedCarousel.carouselKindTitle == "热播周榜"
              && reloadedCarousel.carouselKindUrl == "/a",
              "轮播：写盘后读回一致")
        try? FileManager.default.removeItem(at: carouselTmp)

        // 21. 预览素材：书目都是公版，封面配色稳定
        check(DiscoverPreviewCatalog.samples.count >= 20, "预览：内置至少 20 本示例书")
        check(Set(DiscoverPreviewCatalog.samples.map(\.title)).count
              == DiscoverPreviewCatalog.samples.count, "预览：书名不重复")
        check(DiscoverPreviewCatalog.samples.allSatisfy {
            !$0.title.isEmpty && !$0.author.isEmpty && !$0.kind.isEmpty
        }, "预览：每本都有书名/作者/分类")
        // 同一本书的配色必须每次都一样（用稳定哈希，不用 hashValue）
        let colorA = DiscoverPreviewCover.colors(for: "西游记")
        let colorB = DiscoverPreviewCover.colors(for: "西游记")
        check(colorA.start == colorB.start && colorA.end == colorB.end,
              "预览：封面配色对同一本书稳定")
        let colorC = DiscoverPreviewCover.colors(for: "红楼梦")
        check(colorA.start != colorC.start || colorA.end != colorC.end,
              "预览：不同书取到不同配色")
        check(DiscoverPreviewCover.colors(for: "西游记").start.count == 6,
              "预览：配色是 6 位十六进制")
        let orbsA = DiscoverPreviewCover.orbs(for: "西游记")
        check(orbsA.count == 3, "预览：每本书三个装饰圆")
        check(orbsA.allSatisfy { $0.x >= 0 && $0.x <= 1 && $0.y >= 0 && $0.y <= 1 },
              "预览：装饰圆坐标在 0...1")
        check(DiscoverPreviewCatalog.cards(count: 5).count == 5, "预览：可只取前 N 张卡片")
        let sampleCards = DiscoverPreviewCatalog.cards(count: 3)
        check(sampleCards.allSatisfy { $0.cover?.scheme == "preview" },
              "预览：卡片带自绘封面地址，不联网")
        check(DiscoverPreviewCatalog.previewURL(for: "西游记")?.scheme == "preview"
              && DiscoverPreviewCatalog.previewURL(for: "西游记")?.query?.contains("title=") == true,
              "预览：封面地址能带上书名")
        check(sampleCards.map(\.title) == DiscoverPreviewCatalog.samples.prefix(3).map(\.title),
              "预览：卡片顺序与书目一致")

        // 22. 缩略图素材够用：每种模板都要能取到至少 6 本
        check(DiscoverPreviewCatalog.heroSamples(count: 6).count == 6,
              "预览：模板缩略图能取到 6 本示例")
        check(DiscoverPreviewCatalog.heroSamples(count: 2).count == 2,
              "预览：可按需只取 2 本")
        // 装饰圆半径在合理区间，太大会糊住封面
        for sample in DiscoverPreviewCatalog.samples {
            let orbs = DiscoverPreviewCover.orbs(for: sample.title)
            check(orbs.allSatisfy { $0.r > 0.05 && $0.r < 0.25 },
                  "预览：\(sample.title) 装饰圆半径合理")
        }

        // 23. 多页面：默认一页、增删切、落盘往返、老格式迁移
        var book = CustomDiscoverPages()
        check(book.pages.count == 1, "页面：默认只有一个页面")
        check(book.current.id == book.pages[0].id, "页面：默认选中第一页")
        check(book.current.name == "空白页面", "页面：默认名字")
        check(book.current.componentCount == 0, "页面：默认没有组件")

        let firstID = book.currentID
        let added = book.addPage()
        check(book.pages.count == 2, "页面：能添加页面")
        check(book.currentID == added.id, "页面：添加后自动切到新页")
        check(book.pages.filter { $0.name == added.name }.count == 1,
              "页面：同名会自动加序号")

        book.setCurrent(firstID)
        check(book.currentID == firstID, "页面：能切回原来的页")
        book.setCurrent("不存在的 id")
        check(book.currentID == firstID, "页面：切到不存在的 id 不生效")

        // 每页的配置是独立的
        var cfgA = CustomDiscoverConfig()
        cfgA.upsert(CustomDiscoverEntry(sourceUrl: "u1", sourceName: "甲",
                                        kindTitle: "榜", kindUrl: "/a"))
        book.saveCurrentConfig(cfgA)
        check(book.current.componentCount == 1, "页面：组件写回当前页")
        check(book.pages.first { $0.id == added.id }?.componentCount == 0,
              "页面：另一页不受影响")

        // 不能删到一页都不剩
        book.removePage(added.id)
        check(book.pages.count == 1, "页面：能删除页面")
        book.removePage(firstID)
        check(book.pages.count == 1, "页面：最后一页不能删")

        // 落盘往返
        let pagesTmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pages-\(UUID().uuidString).json")
        check(CustomDiscoverStore.savePages(book, to: pagesTmp), "页面：写盘成功")
        let reloadedPages = CustomDiscoverStore.loadPages(from: pagesTmp)
        check(reloadedPages.pages.count == book.pages.count, "页面：读回页数一致")
        check(reloadedPages.currentID == book.currentID, "页面：读回当前页一致")
        check(reloadedPages.currentConfig.entries.count == 1, "页面：读回组件一致")
        try? FileManager.default.removeItem(at: pagesTmp)

        // 老格式（顶层就是一份 config）会被包成单个页面
        let legacyData = Data(#"{"entries":[{"sourceUrl":"u1","kindUrl":"/a"}],"carouselHidden":true}"#.utf8)
        let migrated = CustomDiscoverStore.decodePages(legacyData)
        check(migrated.pages.count == 1, "页面：老格式迁移成单页")
        check(migrated.current.componentCount == 1, "页面：老配置的板块保留")
        check(migrated.current.config.carouselHidden, "页面：老配置的轮播开关保留")

        // 坏数据不崩
        check(CustomDiscoverStore.decodePages(Data("not json".utf8)).pages.count == 1,
              "页面：坏 JSON 回落单页")
    }
}
