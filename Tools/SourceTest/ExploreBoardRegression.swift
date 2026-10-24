import Foundation

/// 「探索」页纯数据部分：版式归一、标题跟随、编解码宽容、字数/标签整理、
/// 推荐语高亮、板块落盘与 AI 元信息合并。全部离线。
enum ExploreBoardRegression {
    static func run(_ check: (Bool, String) -> Void) throws {
        // 1. 版式
        check(ExploreLayout.normalized("coverGrid") == .coverGrid, "探索：版式解码")
        check(ExploreLayout.normalized("fan") == .bestseller, "探索：未知版式回落")
        check(ExploreLayout.normalized(nil) == .bestseller, "探索：缺版式回落")
        check(ExploreLayout.suggested(forCategory: "畅销精选") == .bestseller, "探索：畅销→精选列表")
        check(ExploreLayout.suggested(forCategory: "品质好书") == .coverGrid, "探索：品质→封面网格")
        check(ExploreLayout.suggested(forCategory: "穿越榜") == .rankColumns, "探索：榜→双列榜单")
        check(ExploreLayout.suggested(forCategory: "新书榜") == .newBookRank, "探索：新书→新书榜")
        check(ExploreLayout.suggested(forCategory: "猜你喜欢") == .forYou, "探索：猜你→猜你喜欢")
        check(ExploreLayout.suggested(forCategory: "轻小说") == .categoryFeed, "探索：普通分类→分类推荐")
        check(ExploreLayout.rankColumns.supportsTabs && !ExploreLayout.bestseller.supportsTabs,
              "探索：只有榜单/新书/分类推荐走顶部标签")

        // 2. 标题与副标题
        let rank = ExploreCategory(sourceURL: "https://s.invalid", url: "/rank", title: "穿越榜")
        let second = ExploreCategory(sourceURL: "https://s.invalid", url: "/sys", title: "系统流榜")
        var board = ExploreBoard(layout: .rankColumns, categories: [rank, second], count: 10)
        check(board.displayTitle == "穿越榜", "探索：标题跟随第一个分类")
        board.title = "  "
        check(board.displayTitle == "穿越榜", "探索：空白自定义标题回退分类名")
        board.title = "  我的榜单  "
        check(board.displayTitle == "我的榜单", "探索：自定义标题去空白")
        let allCategory = ExploreCategory(sourceURL: "https://s.invalid", url: "/all", title: "全部")
        check(ExploreBoard(layout: .newBookRank, categories: [allCategory]).displayTitle == "新书榜",
              "探索：新书榜默认标题不吃「全部」分类名")
        check(board.categories.count == 2 && board.visibleCategories.count == 2, "探索：分类列表")
        check(ExploreBoard(layout: .newBookRank).displaySubtitle == "霸榜好书销量高", "探索：新书榜默认副标题")
        var sub = ExploreBoard(layout: .newBookRank, categories: [rank])
        sub.subtitle = "自定义副标题"
        check(sub.displaySubtitle == "自定义副标题", "探索：自定义副标题优先")
        check(ExploreBoard(layout: .bestseller).displaySubtitle == nil, "探索：不需要副标题的版式不显示")

        // 3. 编解码
        let encoded = try JSONEncoder().encode([board])
        let decoded = try JSONDecoder().decode([ExploreBoard].self, from: encoded)
        check(decoded == [board], "探索：板块编解码往返一致")

        // 4. 宽容解码：缺字段 / 未知版式 / 数量越界
        let legacy = """
        [{"id":"x","layout":"nope","categories":[{"sourceURL":"s","url":"/u","title":"t"}],"count":99}]
        """.data(using: .utf8)!
        let lenient = try JSONDecoder().decode([ExploreBoard].self, from: legacy)
        check(lenient.count == 1 && lenient[0].layout == .bestseller, "探索：未知版式读回畅销精选")
        check(lenient[0].count == 30, "探索：数量钳制到 30")
        check(lenient[0].subtitle.isEmpty && lenient[0].tags.isEmpty && lenient[0].hiddenBookURLs.isEmpty,
              "探索：缺失字段用默认值")

        // 5. 猜你喜欢：点 × 后过滤，重复隐藏只记一次
        let bookA = Book(bookUrl: "b1", name: "一", origin: "o")
        let bookB = Book(bookUrl: "b2", name: "二", origin: "o")
        var forYou = board
        forYou = forYou.hiding(bookURL: "b1")
        forYou = forYou.hiding(bookURL: "b1")
        check(forYou.hiddenBookURLs == ["b1"], "探索：重复隐藏只记一次")
        check(forYou.visibleBooks([bookA, bookB]).map(\.bookUrl) == ["b2"], "探索：隐藏的书不再出现")

        // 6. 字数与标签
        check(ExploreFormat.wordCount("2040000") == "204万字", "探索：纯数字字数换算")
        check(ExploreFormat.wordCount("8500") == "8500字", "探索：不足万字按字显示")
        check(ExploreFormat.wordCount("204万字") == "204万字", "探索：带单位的字数原样显示")
        check(ExploreFormat.wordCount("  ") == nil, "探索：空字数")
        check(ExploreFormat.metaLine(kind: "都市异能", wordCount: "204万字") == "都市异能 · 204万字", "探索：元信息行")
        check(ExploreFormat.metaLine(kind: "  ", wordCount: nil) == nil, "探索：没有元信息不显示空点")
        check(ExploreFormat.tags("求生游戏, 悬疑流，游戏异界、多女主") == ["求生游戏", "悬疑流", "游戏异界", "多女主"],
              "探索：标签分隔符")
        check(ExploreFormat.tagText(["悬疑流", "多女主"]) == "悬疑流、多女主", "探索：标签回写")

        // 7. 推荐语高亮：引号里的片段
        let segments = ExploreReasonFormat.segments("这本“都市”佳作与你的匹配度高达87%！")
        check(segments.count == 3, "探索：推荐语拆成三段")
        check(segments[1].text == "“都市”" && segments[1].highlighted, "探索：引号片段高亮")
        check(segments[0].text == "这本" && !segments[0].highlighted, "探索：普通片段不高亮")
        let jp = ExploreReasonFormat.segments("这本「都市」佳作")
        check(jp.count == 3 && jp[1].text == "「都市」" && jp[1].highlighted, "探索：直角引号也高亮")
        check(ExploreReasonFormat.segments("没有引号") == [ExploreReasonFormat.Segment(text: "没有引号", highlighted: false)],
              "探索：没有引号整段普通")

        // 8. 板块落盘（独立 suite，不碰真实配置）
        let suite = "explore.regression.\(UUID().uuidString)"
        if let defaults = UserDefaults(suiteName: suite) {
            ExploreBoardStore.save([board], to: defaults)
            check(ExploreBoardStore.load(from: defaults) == [board], "探索：板块写入后读回")
            defaults.removePersistentDomain(forName: suite)
        } else {
            check(false, "探索：临时 UserDefaults 可用")
        }
        check(ExploreBoardStore.decode(json: "{\"boards\":[]}")?.isEmpty == true, "探索：配置导入包装格式")
        check(ExploreBoardStore.decode(json: "not json") == nil, "探索：坏 JSON 不崩溃")

        // 9. AI 元信息合并（临时书地址，写完删掉）
        let key = "https://book.invalid/\(UUID().uuidString)"
        let merged = try ExploreMetaStore.merge(json: "{\"\(key)\": {\"tags\": [\"悬疑流\"], \"reason\": \"这本「都市」佳作\"}}")
        check(merged == 1, "探索：AI JSON 合并计数")
        check(ExploreMetaStore.tags(for: key) == ["悬疑流"], "探索：AI 标签写入")
        check(ExploreMetaStore.reason(for: key)?.contains("都市") == true, "探索：AI 推荐语写入")
        ExploreMetaStore.remove(for: key)
        check(ExploreMetaStore.tags(for: key).isEmpty, "探索：AI 元信息可删除")
        do {
            _ = try ExploreMetaStore.merge(json: "[1,2]")
            check(false, "探索：错误结构应抛错")
        } catch {
            check(true, "探索：错误结构抛错")
        }
    }
}
