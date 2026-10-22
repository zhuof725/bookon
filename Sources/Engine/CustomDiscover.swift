import Foundation

/// 「发现」板块的展示模板库。
///
/// 一个模板 = 一种把 `[Book]` 排成板块的视觉方式。页面（或任何调用方）
/// 只需要拿着 `DiscoverTemplateKind` 去 `DiscoverTemplate` 里取，不需要知道具体实现。
/// 纯枚举 + 纯函数放在 Engine，方便 SourceTest 离线回归；真正的视图在 App 层。
enum DiscoverTemplateKind: String, Codable, CaseIterable, Identifiable {
    /// 两列大封面 + 左下角大号序号。
    case badgeGrid
    /// 一行横滑封面。
    case covers
    /// 竖排排名横条（序号徽章 + 封面 + 书名 / 简介）。
    case rankRow
    /// 错位瀑布流：双列不等高，每列按自己的高度往下排。
    case waterfall
    /// 弧形走廊：卡片沿弧线排开，中间最大最亮。
    case curve
    /// 扇形展开：以底边为轴心摊开，像手里捏着一叠牌。
    case fan
    /// 卡片堆叠：中央卡在前，左右各两张向后旋转压暗。
    case deck
    /// 继续阅读：大图 + 进度条 + 最后阅读时间。
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .badgeGrid: return "大封面"
        case .covers: return "横滑封面"
        case .rankRow: return "竖排榜单"
        case .waterfall: return "错位瀑布"
        case .curve: return "弧形走廊"
        case .fan: return "扇形展开"
        case .deck: return "卡片堆叠"
        case .history: return "继续阅读"
        }
    }

    var detail: String {
        switch self {
        case .badgeGrid: return "两列封面，左下角带 01 / 02 序号"
        case .covers: return "一行封面左右滑动"
        case .rankRow: return "每行一本，带排名徽章与简介"
        case .waterfall: return "双列不等高，大小卡错落排下去"
        case .curve: return "卡片沿弧线排开，中间最大最亮"
        case .fan: return "以底边为轴心扇形摊开"
        case .deck: return "中央卡在前完整显示，两侧向后压暗"
        case .history: return "大图铺满 + 进度条 + 最后阅读时间"
        }
    }

    /// 这个模板吃什么数据。
    var dataSource: DiscoverTemplateDataSource {
        switch self {
        case .badgeGrid, .covers, .rankRow, .waterfall, .curve, .fan, .deck: return .bookList
        case .history: return .readingProgress
        }
    }

    /// 解码容错：未知模板回落卡片堆叠，不让一条坏配置拖垮整页。
    static func normalized(_ raw: String?) -> DiscoverTemplateKind {
        guard let raw, let value = DiscoverTemplateKind(rawValue: raw) else { return .deck }
        return value
    }
}

/// 模板需要的数据来源。列表模板从书源发现分类取书，记录模板从书架进度取。
enum DiscoverTemplateDataSource: String, Codable {
    /// 书源发现分类返回的书籍列表。
    case bookList
    /// 书架里每本书的阅读进度。
    case readingProgress
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
        return DiscoverTemplate(kind: kind,
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

    var id: String { Self.makeID(sourceUrl: sourceUrl, kindUrl: kindUrl) }

    init(sourceUrl: String,
         sourceName: String,
         kindTitle: String,
         kindUrl: String,
         template: DiscoverTemplateKind = .deck,
         count: Int = DiscoverTemplate.countCeiling) {
        self.sourceUrl = sourceUrl
        self.sourceName = sourceName
        self.kindTitle = kindTitle
        self.kindUrl = kindUrl
        self.template = template
        self.count = count
    }

    enum CodingKeys: String, CodingKey {
        case sourceUrl, sourceName, kindTitle, kindUrl, template, count
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
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(sourceUrl, forKey: .sourceUrl)
        try c.encode(sourceName, forKey: .sourceName)
        try c.encode(kindTitle, forKey: .kindTitle)
        try c.encode(kindUrl, forKey: .kindUrl)
        try c.encode(template.rawValue, forKey: .template)
        try c.encode(count, forKey: .count)
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

/// 页面配置：顶部轮播的书源 + 板块顺序。
struct CustomDiscoverConfig: Codable, Hashable {
    /// 顶部轮播的书源地址，顺序即翻页顺序。为空时回落到板块里出现过的书源。
    var carouselSourceUrls: [String]
    var entries: [CustomDiscoverEntry]

    init(carouselSourceUrls: [String] = [], entries: [CustomDiscoverEntry] = []) {
        self.carouselSourceUrls = carouselSourceUrls
        self.entries = entries
    }

    private enum CodingKeys: String, CodingKey { case carouselSourceUrls, entries }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        carouselSourceUrls = (try? c.decodeIfPresent([String].self, forKey: .carouselSourceUrls)) ?? []
        entries = (try? c.decodeIfPresent([CustomDiscoverEntry].self, forKey: .entries)) ?? []
    }

    var isEmpty: Bool { entries.isEmpty }

    /// 参与轮播的书源：配置顺序优先；没配置时用板块里第一次出现的书源。
    func carouselSources(from sources: [BookSource]) -> [BookSource] {
        let byURL = Dictionary(sources.map { ($0.bookSourceUrl, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<String>()
        var out: [BookSource] = []
        for url in carouselSourceUrls {
            guard let source = byURL[url], seen.insert(url).inserted else { continue }
            out.append(source)
        }
        if !out.isEmpty { return out }
        for entry in entries where seen.insert(entry.sourceUrl).inserted {
            if let source = byURL[entry.sourceUrl] { out.append(source) }
        }
        return out
    }

    /// 仍然可用的板块：书源存在（启用与否不拦，用户明确挑过）且分类地址非空。
    func visibleEntries(from sources: [BookSource]) -> [CustomDiscoverEntry] {
        let available = Set(DiscoverCatalog.explorableSources(sources).map(\.bookSourceUrl))
        return entries.filter { !$0.kindUrl.isEmpty && available.contains($0.sourceUrl) }
    }

    /// 追加板块：同一书源同一分类只留一条（重复添加时覆盖模板与数量）。
    mutating func upsert(_ entry: CustomDiscoverEntry) {
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index].template = entry.template
            entries[index].count = entry.count
            entries[index].kindTitle = entry.kindTitle
            entries[index].sourceName = entry.sourceName
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
