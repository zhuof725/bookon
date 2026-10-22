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

        // 2. 增删与去重
        var config = CustomDiscoverConfig()
        let entryA = CustomDiscoverEntry(sourceUrl: "u1", sourceName: "书源甲",
                                         kindTitle: "热播周榜", kindUrl: "/a", template: .deck)
        config.upsert(entryA)
        check(config.entries.count == 1, "自定义发现：首次添加写入一条")
        var entryADup = entryA
        entryADup.template = .fan
        config.upsert(entryADup)
        check(config.entries.count == 1 && config.entries[0].template == .fan,
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

        // 11. 模板表：八个模板都注册了，且数据源归属正确
        check(DiscoverTemplate.all.count == DiscoverTemplateKind.allCases.count,
              "模板：列表长度等于枚举数量")
        check(DiscoverTemplateKind.allCases.map(\.rawValue)
              == ["badgeGrid", "covers", "rankRow", "waterfall", "curve", "fan", "deck", "history"],
              "模板：八个模板的稳定键")
        for kind in DiscoverTemplateKind.allCases {
            check(DiscoverTemplate.template(for: kind).kind == kind,
                  "模板：\(kind.title) 能按枚举取回")
            check(!kind.title.isEmpty && !kind.detail.isEmpty,
                  "模板：\(kind.rawValue) 有标题和说明")
        }
        check(DiscoverTemplateKind.badgeGrid.dataSource == .bookList
              && DiscoverTemplateKind.covers.dataSource == .bookList
              && DiscoverTemplateKind.rankRow.dataSource == .bookList
              && DiscoverTemplateKind.waterfall.dataSource == .bookList
              && DiscoverTemplateKind.curve.dataSource == .bookList
              && DiscoverTemplateKind.fan.dataSource == .bookList
              && DiscoverTemplateKind.deck.dataSource == .bookList,
              "模板：七种书籍布局都吃书籍列表")
        check(DiscoverTemplateKind.history.dataSource == .readingProgress,
              "模板：继续阅读吃阅读进度")

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
        wide.applyTemplate(.fan)
        check(wide.template == .fan && wide.count == 20,
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
    }
}
