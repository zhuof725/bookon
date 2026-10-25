import Foundation

/// 「探索」页的板块版式：六种参考版式，各对应一种把 `[Book]` 排成卡片的方式。
///
/// 纯枚举 + 纯函数放在 Engine，SourceTest 可以离线回归；真正的视图在 App 层。
enum ExploreLayout: String, Codable, CaseIterable, Identifiable {
    /// 畅销精选：大封面列表，书名 + 简介 + 分类字数 + 标签。
    case bestseller
    /// 品质好书：四列封面，书名 + 分类。
    case coverGrid
    /// 双列榜单：顶部标签切换分类，下面是双列排名。
    case rankColumns
    /// 新书榜：标题旁副标题，顶部筛选胶囊，带封面与徽标的双列榜单。
    case newBookRank
    /// 分类推荐：顶部标签 + 一句推荐语 + 双列书单。
    case categoryFeed
    /// 猜你喜欢：每本书一张卡，推荐理由 + 关闭按钮。
    case forYou

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bestseller: return "畅销精选"
        case .coverGrid: return "品质好书"
        case .rankColumns: return "双列榜单"
        case .newBookRank: return "新书榜"
        case .categoryFeed: return "分类推荐"
        case .forYou: return "猜你喜欢"
        }
    }

    var detail: String {
        switch self {
        case .bestseller: return "大封面列表：书名、简介、分类字数与标签"
        case .coverGrid: return "四列封面，书名 + 分类"
        case .rankColumns: return "顶部标签切换分类，双列排名"
        case .newBookRank: return "顶部筛选胶囊，带封面与徽标的双列榜单"
        case .categoryFeed: return "顶部标签，一句推荐语，双列书单"
        case .forYou: return "每本书一张卡：推荐理由 + 关闭按钮"
        }
    }

    /// 设置页里的图标名（SF Symbol）。
    var symbol: String {
        switch self {
        case .bestseller: return "list.bullet.rectangle"
        case .coverGrid: return "square.grid.2x2"
        case .rankColumns: return "list.number"
        case .newBookRank: return "chart.bar.doc.horizontal"
        case .categoryFeed: return "rectangle.grid.2x2"
        case .forYou: return "heart.text.square"
        }
    }

    /// 这种版式把多个分类显示成顶部标签 / 筛选胶囊。
    var supportsTabs: Bool {
        switch self {
        case .rankColumns, .newBookRank, .categoryFeed: return true
        case .bestseller, .coverGrid, .forYou: return false
        }
    }

    /// 这种版式会显示副标题（推荐语）。
    var usesSubtitle: Bool {
        switch self {
        case .newBookRank, .categoryFeed, .forYou: return true
        default: return false
        }
    }

    var defaultCount: Int {
        switch self {
        case .bestseller: return 3
        case .coverGrid: return 4
        case .rankColumns, .newBookRank: return 10
        case .categoryFeed: return 6
        case .forYou: return 4
        }
    }

    /// 默认副标题（用户没填时显示）；nil 表示这种版式不需要副标题。
    var placeholderSubtitle: String? {
        switch self {
        case .newBookRank: return "霸榜好书销量高"
        case .categoryFeed: return "根据你感兴趣的分类推荐"
        case .forYou: return "按你的口味推荐"
        default: return nil
        }
    }

    /// 解码容错：未知版式回落到畅销精选，不让一条坏配置拖垮整页。
    static func normalized(_ raw: String?) -> ExploreLayout {
        guard let raw, !raw.isEmpty else { return .bestseller }
        return ExploreLayout(rawValue: raw) ?? .bestseller
    }

    /// 按书源分类名猜一个合适的版式（「全部添加」时用）。
    static func suggested(forCategory title: String) -> ExploreLayout {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.contains("猜你") || name.contains("喜欢") || name.contains("为你") {
            return .forYou
        }
        if name.contains("新书") || name.contains("新作") || name.contains("潜力") {
            return .newBookRank
        }
        if name.contains("畅销") || name.contains("热销") || name.contains("精选") || name.contains("口碑") {
            return .bestseller
        }
        if name.contains("榜") || name.contains("排行") || name.contains("排名") || name.contains("风云") {
            return .rankColumns
        }
        if name.contains("品质") || name.contains("好评") || name.contains("经典") || name.contains("完本") {
            return .coverGrid
        }
        return .categoryFeed
    }
}

/// 一个书源发现分类的引用。板块保存的是分类地址而不是书单，刷新时重新取。
struct ExploreCategory: Codable, Hashable, Identifiable {
    var sourceURL: String
    var url: String
    var title: String

    init(sourceURL: String, url: String, title: String) {
        self.sourceURL = sourceURL
        self.url = url
        self.title = title
    }

    /// 同一地址可能出现在不同书源里，id 必须带上书源地址。
    var id: String { sourceURL + "\u{1F}" + url }
    /// 书单缓存键（与 `DiscoverBlockCache` 用 source+url 的规则一致）。
    var key: String { id }

    var isEmpty: Bool {
        url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private enum CodingKeys: String, CodingKey { case sourceURL, url, title }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sourceURL = (try? c.decode(String.self, forKey: .sourceURL)) ?? ""
        url = (try? c.decode(String.self, forKey: .url)) ?? ""
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
    }
}

/// 「探索」页的一张板块卡片。
///
/// 一张卡 = 一个或多个书源发现分类 + 一种版式。带标签的版式把 `categories`
/// 的第 2 个起显示成顶部标签；其它版式只用第一个分类。
struct ExploreBoard: Codable, Hashable, Identifiable {
    var id: String
    /// 自定义标题；留空时跟随第一个分类名。
    var title: String
    /// 副标题 / 推荐语；留空时用版式的默认文案。
    var subtitle: String
    var layout: ExploreLayout
    var categories: [ExploreCategory]
    /// 展示数量（不是全部书单的数量，「更多」里是完整列表）。
    var count: Int
    /// 兜底标签：书本身没有 AI 写入的标签时，用这些标签显示。
    var tags: [String]
    /// 「猜你喜欢」里点 × 隐藏掉的书。
    var hiddenBookURLs: [String]

    init(id: String = UUID().uuidString,
         title: String = "",
         subtitle: String = "",
         layout: ExploreLayout = .bestseller,
         categories: [ExploreCategory] = [],
         count: Int? = nil,
         tags: [String] = [],
         hiddenBookURLs: [String] = []) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.layout = layout
        self.categories = categories
        self.count = min(max(count ?? layout.defaultCount, 1), 30)
        self.tags = tags
        self.hiddenBookURLs = hiddenBookURLs
    }

    var displayTitle: String {
        let custom = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty { return custom }
        // 新书榜的分类是筛选胶囊（第一个常是「全部」），标题不该跟着第一个分类走。
        if layout == .newBookRank { return layout.title }
        if let first = categories.first, !first.title.isEmpty { return first.title }
        return layout.title
    }

    /// 副标题：用户填的优先，否则用版式默认文案；再没有就不显示。
    var displaySubtitle: String? {
        let custom = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty { return custom }
        return layout.placeholderSubtitle
    }

    /// 真正能加载的分类（去掉空地址）。
    var visibleCategories: [ExploreCategory] {
        categories.filter { !$0.isEmpty }
    }

    /// 「更多」的目标：第一个分类。
    var moreCategory: ExploreCategory? { visibleCategories.first }

    func visibleBooks(_ books: [Book]) -> [Book] {
        guard !hiddenBookURLs.isEmpty else { return books }
        let hidden = Set(hiddenBookURLs)
        return books.filter { !hidden.contains($0.bookUrl) }
    }

    func hiding(bookURL: String) -> ExploreBoard {
        var copy = self
        if !copy.hiddenBookURLs.contains(bookURL) {
            copy.hiddenBookURLs.append(bookURL)
        }
        return copy
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, subtitle, layout, categories, count, tags, hiddenBookURLs
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        subtitle = (try? c.decode(String.self, forKey: .subtitle)) ?? ""
        layout = ExploreLayout.normalized(try? c.decode(String.self, forKey: .layout))
        categories = (try? c.decode([ExploreCategory].self, forKey: .categories)) ?? []
        let stored = (try? c.decode(Int.self, forKey: .count)) ?? layout.defaultCount
        count = min(max(stored, 1), 30)
        tags = (try? c.decode([String].self, forKey: .tags)) ?? []
        hiddenBookURLs = (try? c.decode([String].self, forKey: .hiddenBookURLs)) ?? []
    }
}

/// 板块配置的落盘：UserDefaults 里一段 JSON，顺序即页面顺序。
enum ExploreBoardStore {
    static let defaultsKey = "explore.boards.v1"

    static func load(from defaults: UserDefaults = .standard) -> [ExploreBoard] {
        guard let data = defaults.data(forKey: defaultsKey) else { return [] }
        guard var boards = try? JSONDecoder().decode([ExploreBoard].self, from: data) else { return [] }
        // 旧版本重复呈现编辑页时可能把同一份草稿（同 id）存了多次；
        // 读回时修掉重复 id，两张卡才能各显示各的。
        return uniqueIDs(boards)
    }

    /// 修掉重复 id：同一个 id 的第二张起换成新 UUID。
    static func uniqueIDs(_ boards: [ExploreBoard]) -> [ExploreBoard] {
        var seen = Set<String>()
        var result: [ExploreBoard] = []
        result.reserveCapacity(boards.count)
        for var board in boards {
            if seen.contains(board.id) { board.id = UUID().uuidString }
            seen.insert(board.id)
            result.append(board)
        }
        return result
    }

    static func save(_ boards: [ExploreBoard], to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(boards) else { return }
        defaults.set(data, forKey: defaultsKey)
    }

    /// 把剪贴板/文件里的配置读进来：接受整段 `[...]`，也接受 `{"boards":[...]}`。
    static func decode(json: String) -> [ExploreBoard]? {
        let text = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = text.data(using: .utf8) else { return nil }
        if let boards = try? JSONDecoder().decode([ExploreBoard].self, from: data) {
            return boards
        }
        return (try? JSONDecoder().decode(ExploreBoardFile.self, from: data))?.boards
    }
}

/// 配置文件外层包装：`{"boards":[...]}`。
private struct ExploreBoardFile: Codable {
    var boards: [ExploreBoard]
}

/// 探索页的文本整理：分类字数、标签、元信息行。
enum ExploreFormat {
    /// 书源里的字数可能是 "204万字"、"2040000"、"2040千字" 等，统一成一行能读的文本。
    static func wordCount(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        // 纯数字：按字换算成 万字。
        if text.allSatisfy({ $0.isNumber }), let value = Int(text) {
            if value >= 10_000 {
                let wan = Double(value) / 10_000
                return wan >= 100 ? "\(Int(wan.rounded()))万字"
                    : String(format: "%.1f万字", wan).replacingOccurrences(of: ".0万字", with: "万字")
            }
            return "\(value)字"
        }
        return text
    }

    /// "都市异能 · 204万字"；其中之一缺失时不留下孤零零的点。
    static func metaLine(kind: String?, wordCount raw: String?) -> String? {
        let kindText = (kind ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let countText = wordCount(raw)
        let parts = [kindText, countText].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// 用户输入的标签："求生游戏, 悬疑流，游戏异界" → ["求生游戏", "悬疑流", "游戏异界"]。
    static func tags(_ raw: String) -> [String] {
        raw.split(whereSeparator: { ",，、|/".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func tagText(_ tags: [String]) -> String {
        tags.joined(separator: "、")
    }
}
