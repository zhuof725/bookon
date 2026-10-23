import Foundation

/// 「发现」板块的展示模板库。
///
/// 一个模板 = 一种把 `[Book]` 排成板块的视觉方式。页面（或任何调用方）
/// 只需要拿着 `DiscoverTemplateKind` 去 `DiscoverTemplate` 里取，不需要知道具体实现。
/// 纯枚举 + 纯函数放在 Engine，方便 SourceTest 离线回归；真正的视图在 App 层。
enum DiscoverTemplateKind: String, Codable, CaseIterable, Identifiable {
    // ── 版式线（Apple Books 风格）：白卡 + 大圆角 + 留白优先 ──
    /// 一张大卡讲清一本书：左封面，右大标题 + 作者。
    case largeCard
    /// 整卡封面色铺底，小封面 + 白书名。
    case compactCard
    /// 三列网格，封面撑满列宽。
    case threeColumn
    /// 两行横向轮播，一屏两倍展示量。
    case dualRow
    /// 固定列表：小封面 + 分隔线，像设置页。
    case fixedList
    /// 图文大卡：大封面 + 简介 + 胶囊按钮。
    case featureCard
    /// 更新信息流：蓝色「更新」+ 章节 + 相对时间。
    case updateFeed

    // ── 原 3D / 视觉线 ──
    /// 两列大封面 + 左下角序号药丸。
    case badgeGrid
    /// 一行横滑大封面。
    case covers
    /// 竖排榜单：大号斜体数字 + 小封面。
    case rankRow
    /// 错位瀑布流：双列不等高。
    case waterfall
    /// 弧形走廊：卡片沿弧线排开，中间最大最亮。
    case curve
    /// 卡片堆叠：中央卡在前，左右各两张向后旋转压暗。
    case deck
    /// 继续阅读：大图 + 进度条 + 最后阅读时间。
    case history

    var id: String { rawValue }

    /// 新增模板统一排在前面，旧的保持原顺序，历史配置不受影响。
    var title: String {
        switch self {
        case .largeCard: return "大型阅读卡片"
        case .compactCard: return "精简阅读卡片"
        case .threeColumn: return "三列书架"
        case .dualRow: return "双行横向轮播"
        case .fixedList: return "固定列表"
        case .featureCard: return "图文大卡"
        case .updateFeed: return "更新信息流"
        case .badgeGrid: return "大封面"
        case .covers: return "横滑封面"
        case .rankRow: return "竖排榜单"
        case .waterfall: return "错位瀑布"
        case .curve: return "弧形走廊"
        case .deck: return "卡片堆叠"
        case .history: return "继续阅读"
        }
    }

    var detail: String {
        switch self {
        case .largeCard: return "一张白卡讲一本书：大封面 + 大标题"
        case .compactCard: return "封面色铺底，小封面 + 白书名"
        case .threeColumn: return "三列网格，封面撑满列宽"
        case .dualRow: return "两行横向轮播，一屏两倍书"
        case .fixedList: return "小封面 + 分隔线，像设置页"
        case .featureCard: return "大封面 + 简介 + 胶囊按钮"
        case .updateFeed: return "蓝色更新标签 + 章节 + 时间"
        case .badgeGrid: return "两列封面，左下角带序号"
        case .covers: return "一行大封面左右滑动"
        case .rankRow: return "大号斜体排名 + 小封面"
        case .waterfall: return "双列不等高，大小卡错落排下去"
        case .curve: return "卡片沿弧线排开，中间最大最亮"
        case .deck: return "中央卡在前完整显示，两侧向后压暗"
        case .history: return "大图铺满 + 进度条 + 最后阅读时间"
        }
    }

    /// 这个模板吃什么数据。
    var dataSource: DiscoverTemplateDataSource {
        switch self {
        case .history: return .readingProgress
        default: return .bookList
        }
    }

    /// 卡片型（本身是翻看交互，按实际数量自己排），其余是列表型（一直往下铺）。
    var isCardStage: Bool {
        switch self {
        case .curve, .deck: return true
        default: return false
        }
    }

    /// 展示库里的分组归属。
    var family: DiscoverTemplateFamily {
        switch self {
        case .largeCard, .compactCard, .threeColumn, .dualRow,
             .fixedList, .featureCard, .updateFeed:
            return .layout
        case .badgeGrid, .covers, .rankRow, .waterfall, .curve, .deck:
            return .visual
        case .history:
            return .record
        }
    }

    /// 解码容错：未知模板回落卡片堆叠，不让一条坏配置拖垮整页。
    /// `fan`（扇形展开）已下线，老配置落到最接近的弧形走廊。
    static func normalized(_ raw: String?) -> DiscoverTemplateKind {
        guard let raw else { return .deck }
        if raw == "fan" { return .curve }
        return DiscoverTemplateKind(rawValue: raw) ?? .deck
    }
}

/// 模板需要的数据来源。列表模板从书源发现分类取书，记录模板从书架进度取。
enum DiscoverTemplateDataSource: String, Codable {
    /// 书源发现分类返回的书籍列表。
    case bookList
    /// 书架里每本书的阅读进度。
    case readingProgress
}

/// 展示库里的分组：同组成员排在一起，说明也按组写。
enum DiscoverTemplateFamily: String, CaseIterable, Identifiable {
    /// 版式线：白卡 + 大圆角 + 留白优先。
    case layout
    /// 视觉线：封面主导的 3D / 大图排布。
    case visual
    /// 记录线：吃书架阅读进度。
    case record

    var id: String { rawValue }

    var title: String {
        switch self {
        case .layout: return "版式"
        case .visual: return "视觉"
        case .record: return "阅读记录"
        }
    }

    var detail: String {
        switch self {
        case .layout: return "白卡 + 大圆角 + 留白优先，像原生书城的推荐位"
        case .visual: return "封面主导：网格、横滑、榜单、3D 排布"
        case .record: return "用书架里的阅读进度铺成板块"
        }
    }

    /// 这一组里的模板，顺序沿用枚举顺序。
    var templates: [DiscoverTemplate] {
        DiscoverTemplate.all.filter { $0.kind.family == self }
    }
}

/// 模板的静态描述：给设置界面用，不依赖任何视图类型。
struct DiscoverTemplate: Identifiable, Hashable {
    let kind: DiscoverTemplateKind
    /// 设置界面里显示的最大/最小显示数量。
    let minCount: Int
    let maxCount: Int
    let defaultCount: Int

    var id: String { kind.rawValue }
    var title: String { kind.title }
    var detail: String { kind.detail }

    /// 所有模板的数量上限统一 20，下限 1。
    static let countCeiling = 20
    static let countFloor = 1
    /// 「全部」页用的不限数量标记。
    static let unlimited = Int.max

    static let all: [DiscoverTemplate] = DiscoverTemplateKind.allCases.map { kind in
        DiscoverTemplate(kind: kind,
                         minCount: countFloor,
                         maxCount: countCeiling,
                         defaultCount: countCeiling)
    }

    static func template(for kind: DiscoverTemplateKind) -> DiscoverTemplate {
        all.first { $0.kind == kind }
            ?? DiscoverTemplate(kind: kind,
                                minCount: countFloor,
                                maxCount: countCeiling,
                                defaultCount: countCeiling)
    }

    /// 把外部传入的数量钳制到模板允许的范围（1...20）。
    /// 传 `unlimited` 时原样返回，用于「全部」页。
    func clampedCount(_ value: Int) -> Int {
        if value == DiscoverTemplate.unlimited { return value }
        return min(max(value, minCount), maxCount)
    }

    /// 是否不限数量。
    static func isUnlimited(_ value: Int) -> Bool { value == unlimited }
}

// MARK: - 配置

/// 一个板块 = 某书源的某个发现分类 + 用一个模板渲染。
struct CustomDiscoverEntry: Codable, Hashable, Identifiable {
    var sourceUrl: String
    /// 书源名快照：书源暂时不可用时仍能显示标题。
    var sourceName: String
    var kindTitle: String
    var kindUrl: String
    var template: DiscoverTemplateKind
    /// 这个板块展示多少条
    var count: Int
    /// 卡片宽度倍率：瀑布流以外的大封面/横滑按这个缩放。1 = 默认
    var scale: Double
    /// 卡片圆角
    var corner: Double
    /// 大封面序号角标是否显示
    var showNumber: Bool

    var id: String { Self.makeID(sourceUrl: sourceUrl, kindUrl: kindUrl) }

    init(sourceUrl: String,
         sourceName: String,
         kindTitle: String,
         kindUrl: String,
         template: DiscoverTemplateKind = .deck,
         count: Int = DiscoverTemplate.countCeiling,
         scale: Double = 1,
         corner: Double = 8,
         showNumber: Bool = true) {
        self.sourceUrl = sourceUrl
        self.sourceName = sourceName
        self.kindTitle = kindTitle
        self.kindUrl = kindUrl
        self.template = template
        self.count = count
        self.scale = scale
        self.corner = corner
        self.showNumber = showNumber
    }

    enum CodingKeys: String, CodingKey {
        case sourceUrl, sourceName, kindTitle, kindUrl, template, count, scale, corner, showNumber
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sourceUrl = (try? c.decode(String.self, forKey: .sourceUrl)) ?? ""
        sourceName = (try? c.decodeIfPresent(String.self, forKey: .sourceName)) ?? ""
        kindTitle = (try? c.decodeIfPresent(String.self, forKey: .kindTitle)) ?? ""
        kindUrl = (try? c.decodeIfPresent(String.self, forKey: .kindUrl)) ?? ""
        template = DiscoverTemplateKind.normalized(try? c.decodeIfPresent(String.self, forKey: .template))
        count = DiscoverTemplate.template(for: template)
            .clampedCount((try? c.decodeIfPresent(Int.self, forKey: .count)) ?? DiscoverTemplate.countCeiling)
        let s = (try? c.decodeIfPresent(Double.self, forKey: .scale)) ?? 1
        scale = s.isFinite ? min(max(s, 0.6), 1.6) : 1
        let r = (try? c.decodeIfPresent(Double.self, forKey: .corner)) ?? 8
        corner = r.isFinite ? min(max(r, 0), 20) : 8
        showNumber = (try? c.decodeIfPresent(Bool.self, forKey: .showNumber)) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(sourceUrl, forKey: .sourceUrl)
        try c.encode(sourceName, forKey: .sourceName)
        try c.encode(kindTitle, forKey: .kindTitle)
        try c.encode(kindUrl, forKey: .kindUrl)
        try c.encode(template.rawValue, forKey: .template)
        try c.encode(count, forKey: .count)
        try c.encode(scale, forKey: .scale)
        try c.encode(corner, forKey: .corner)
        try c.encode(showNumber, forKey: .showNumber)
    }

    /// 书源 + 分类决定唯一性（同一分类重复添加只保留第一次那条）。
    static func makeID(sourceUrl: String, kindUrl: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in "\(sourceUrl)|\(kindUrl)".utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }

    /// 板块标题：只显示分类名，不拼书源名。
    /// 分类名为空时才回落到书源名，避免出现一条没有标题的板块。
    var boardTitle: String {
        let kind = kindTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !kind.isEmpty { return kind }
        return sourceName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 换模板时把 count 一起钳到新模板允许的范围。
    mutating func applyTemplate(_ kind: DiscoverTemplateKind) {
        template = kind
        count = DiscoverTemplate.template(for: kind).clampedCount(count)
    }
}

/// 首页配置：顶部分类（轮播）+ 板块顺序。
struct CustomDiscoverConfig: Codable, Hashable {
    /// 顶部分类标题。为空时自动用「全部」+ 板块里出现过的书源名。
    var categories: [String]
    var entries: [CustomDiscoverEntry]

    /// 轮播数据源：某个书源的某个发现分类。三者都为空表示没配。
    var carouselSourceUrl: String
    var carouselKindTitle: String
    var carouselKindUrl: String
    /// 是否隐藏轮播图
    var carouselHidden: Bool
    /// 轮播用哪个模板渲染。老配置读不到就用大卡片。
    var carouselTemplate: DiscoverTemplateKind

    init(categories: [String] = [],
         entries: [CustomDiscoverEntry] = [],
         carouselSourceUrl: String = "",
         carouselKindTitle: String = "",
         carouselKindUrl: String = "",
         carouselHidden: Bool = false,
         carouselTemplate: DiscoverTemplateKind = .largeCard) {
        self.categories = categories
        self.entries = entries
        self.carouselSourceUrl = carouselSourceUrl
        self.carouselKindTitle = carouselKindTitle
        self.carouselKindUrl = carouselKindUrl
        self.carouselHidden = carouselHidden
        self.carouselTemplate = carouselTemplate
    }

    private enum CodingKeys: String, CodingKey {
        case categories, entries
        case carouselSourceUrl, carouselKindTitle, carouselKindUrl, carouselHidden
        case carouselTemplate
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        categories = (try? c.decodeIfPresent([String].self, forKey: .categories)) ?? []
        entries = (try? c.decodeIfPresent([CustomDiscoverEntry].self, forKey: .entries)) ?? []
        carouselSourceUrl = (try? c.decodeIfPresent(String.self, forKey: .carouselSourceUrl)) ?? ""
        carouselKindTitle = (try? c.decodeIfPresent(String.self, forKey: .carouselKindTitle)) ?? ""
        carouselKindUrl = (try? c.decodeIfPresent(String.self, forKey: .carouselKindUrl)) ?? ""
        carouselHidden = (try? c.decodeIfPresent(Bool.self, forKey: .carouselHidden)) ?? false
        var template = DiscoverTemplateKind.normalized(
            try? c.decodeIfPresent(String.self, forKey: .carouselTemplate))
        // 轮播只吃书籍列表；记录模板不适用于轮播，兜底回大卡片。
        if template.dataSource != .bookList { template = .largeCard }
        carouselTemplate = template
    }

    /// 轮播是否已配置且未关闭。
    var hasCarousel: Bool {
        !carouselHidden && !carouselSourceUrl.isEmpty && !carouselKindUrl.isEmpty
    }

    /// 轮播实际用哪个模板：记录模板吃不到书籍列表，统一兜底回大卡片。
    var effectiveCarouselTemplate: DiscoverTemplateKind {
        carouselTemplate.dataSource == .bookList ? carouselTemplate : .largeCard
    }

    var isEmpty: Bool { entries.isEmpty }

    /// 实际要显示的分类标签。
    ///
    /// 规则：配置里手动写过的分类优先；没写时按板块里出现过的书源名自动生成，
    /// 前面永远有「全部」。
    var effectiveCategories: [String] {
        let manual = categories
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !manual.isEmpty { return manual }
        var seen = Set<String>()
        var auto: [String] = []
        for entry in entries {
            let name = entry.sourceName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, seen.insert(name).inserted else { continue }
            auto.append(name)
        }
        return auto.isEmpty ? [] : auto
    }

    /// 某个分类下要显示的板块。
    ///
    /// 「全部」返回所有板块；其余按书源名匹配，匹配不到就返回全部（分类名是手写时）。
    func entries(inCategory category: String) -> [CustomDiscoverEntry] {
        let key = category.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, key != Self.allCategory else { return entries }
        let matched = entries.filter {
            $0.sourceName.trimmingCharacters(in: .whitespacesAndNewlines) == key
        }
        return matched.isEmpty ? entries : matched
    }

    static let allCategory = "全部"

    /// 一次性把条目按分类分好：`分类名 → 条目`。
    ///
    /// `entries(inCategory:)` 每调一次就遍历一遍全部条目，分类多了就是 O(分类数 × 条目数)；
    /// 首页每次重建都会用到所有分类，所以在这里一次分完。
    func entriesByCategory() -> [String: [CustomDiscoverEntry]] {
        var grouped: [String: [CustomDiscoverEntry]] = [:]
        for entry in entries {
            let name = entry.sourceName.trimmingCharacters(in: .whitespacesAndNewlines)
            grouped[name, default: []].append(entry)
        }
        // 「全部」包含所有条目；没匹配到任何分类的条目也归到这里，
        // 避免手写了一个不存在的分类名就看不到东西。
        grouped[Self.allCategory] = entries
        return grouped
    }

    /// 仍然可用的板块：书源存在（启用与否不拦，用户明确挑过）且分类地址非空。
    func visibleEntries(from sources: [BookSource]) -> [CustomDiscoverEntry] {
        let available = Set(DiscoverCatalog.explorableSources(sources).map(\.bookSourceUrl))
        return entries.filter { entry in
            guard !entry.kindUrl.isEmpty else { return false }
            // 不依赖书源的板块（继续阅读）直接放行
            if entry.sourceUrl.isEmpty { return true }
            return available.contains(entry.sourceUrl)
        }
    }

    /// 追加板块：同一书源同一分类只留一条（重复添加时覆盖模板与数量）。
    mutating func upsert(_ entry: CustomDiscoverEntry) {
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index].template = entry.template
            entries[index].count = entry.count
            entries[index].kindTitle = entry.kindTitle
            entries[index].sourceName = entry.sourceName
            entries[index].scale = entry.scale
            entries[index].corner = entry.corner
            entries[index].showNumber = entry.showNumber
        } else {
            entries.append(entry)
        }
    }

    mutating func remove(id: String) {
        entries.removeAll { $0.id == id }
    }

    /// 列表拖拽排序（对应 SwiftUI 的 onMove）。
    mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        var list = entries
        let moving = source.sorted().map { list[$0] }
        for index in source.sorted(by: >) where list.indices.contains(index) {
            list.remove(at: index)
        }
        var target = destination
        for index in source.sorted() where index < destination { target -= 1 }
        target = min(max(target, 0), list.count)
        list.insert(contentsOf: moving, at: target)
        entries = list
    }

    /// 写回书源列表里最新的名字（书源改名后标题跟着变）。
    mutating func refreshNames(from sources: [BookSource]) {
        let names = Dictionary(sources.map { ($0.bookSourceUrl, $0.bookSourceName) },
                               uniquingKeysWith: { first, _ in first })
        for index in entries.indices {
            if let name = names[entries[index].sourceUrl], !name.isEmpty {
                entries[index].sourceName = name
            }
        }
    }
}

/// 配置落盘：Documents/customDiscover.json。
/// 与书源同目录，走 iCloud/文件共享备份时一起带走。
enum CustomDiscoverStore {
    static let fileName = "customDiscover.json"

    static var fileURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent(fileName)
    }

    static func load(from url: URL? = nil) -> CustomDiscoverConfig {
        guard let file = url ?? Optional(fileURL),
              let data = try? Data(contentsOf: file) else { return CustomDiscoverConfig() }
        return decode(data)
    }

    /// 解码失败一律当作空配置，绝不让坏文件卡住整个「发现」页。
    static func decode(_ data: Data) -> CustomDiscoverConfig {
        (try? JSONDecoder().decode(CustomDiscoverConfig.self, from: data)) ?? CustomDiscoverConfig()
    }

    static func encode(_ config: CustomDiscoverConfig) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(config)
    }

    @discardableResult
    static func save(_ config: CustomDiscoverConfig, to url: URL? = nil) -> Bool {
        guard let data = encode(config) else { return false }
        do {
            try data.write(to: url ?? fileURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}
