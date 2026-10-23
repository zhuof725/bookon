import Foundation

// MARK: - 一个首页页面

/// 一个首页页面：自己的名字、图标、轮播和板块列表。
///
/// 一个页面 = 以前的一整份 `CustomDiscoverConfig`。以前只有一份配置，
/// 现在可以有多份，靠 `id` 区分，`CustomDiscoverConfig` 仍然是页面内部的形态，
/// 这样老配置、老回归、老渲染代码全都不用动。
struct CustomDiscoverPage: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    /// 页面上显示的表情/符号图标。
    var icon: String
    var config: CustomDiscoverConfig

    init(id: String = UUID().uuidString,
         name: String = "空白页面",
         icon: String = "📄",
         config: CustomDiscoverConfig = CustomDiscoverConfig()) {
        self.id = id
        self.name = name
        self.icon = icon
        self.config = config
    }

    private enum CodingKeys: String, CodingKey { case id, name, icon, config }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? UUID().uuidString
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? "空白页面"
        icon = (try? c.decodeIfPresent(String.self, forKey: .icon)) ?? "📄"
        config = (try? c.decodeIfPresent(CustomDiscoverConfig.self, forKey: .config))
            ?? CustomDiscoverConfig()
    }

    /// 组件数：页面上有几个板块。
    var componentCount: Int { config.entries.count }
}

// MARK: - 全部页面

/// 多页面容器。「页面管理」里加/删页面，首页顶部切换当前页。
///
/// 落盘还是 `customDiscover.json`：
///  - 新格式整份写 `pages`；
///  - 同时把当前页的 `config` 平铺到顶层，老版本 App 读到的仍是原来那份配置，
///    不会因为升级过文件就读不出来。
struct CustomDiscoverPages: Codable, Hashable {
    var pages: [CustomDiscoverPage]
    /// 当前显示的页面 id。
    var currentID: String

    init(pages: [CustomDiscoverPage] = [CustomDiscoverPage()],
         currentID: String? = nil) {
        self.pages = pages.isEmpty ? [CustomDiscoverPage()] : pages
        self.currentID = currentID ?? self.pages[0].id
    }

    private enum CodingKeys: String, CodingKey { case pages, currentID }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let decoded = (try? c.decodeIfPresent([CustomDiscoverPage].self, forKey: .pages)) ?? []
        if decoded.isEmpty {
            // 老格式：没有 pages 字段，顶层就是一份 config。
            let legacy = (try? CustomDiscoverConfig(from: decoder)) ?? CustomDiscoverConfig()
            pages = [CustomDiscoverPage(id: "home", name: "首页", icon: "🏠", config: legacy)]
            currentID = "home"
        } else {
            pages = decoded
            let stored = (try? c.decodeIfPresent(String.self, forKey: .currentID)) ?? nil
            // 存的那个 id 可能已经被删了，认不出来就回到第一页
            if let stored, pages.contains(where: { $0.id == stored }) {
                currentID = stored
            } else {
                currentID = pages[0].id
            }
        }
    }

    // MARK: 取用

    var current: CustomDiscoverPage {
        pages.first { $0.id == currentID } ?? pages[0]
    }

    var currentConfig: CustomDiscoverConfig { current.config }

    /// 当前页在数组里的下标。
    var currentIndex: Int {
        pages.firstIndex { $0.id == currentID } ?? 0
    }

    // MARK: 改

    mutating func setCurrent(_ id: String) {
        guard pages.contains(where: { $0.id == id }) else { return }
        currentID = id
    }

    mutating func update(_ page: CustomDiscoverPage) {
        guard let index = pages.firstIndex(where: { $0.id == page.id }) else { return }
        pages[index] = page
    }

    /// 把当前页的配置写回去（首页渲染、编辑页保存都走这里）。
    mutating func saveCurrentConfig(_ config: CustomDiscoverConfig) {
        guard let index = pages.firstIndex(where: { $0.id == currentID }) else { return }
        pages[index].config = config
    }

    /// 添加一个空白自定义页面并切过去。
    @discardableResult
    mutating func addPage(name: String = "空白页面", icon: String = "📄") -> CustomDiscoverPage {
        // 同名时补个序号，避免页面切换里两行一模一样
        var title = name
        var suffix = 2
        while pages.contains(where: { $0.name == title }) {
            title = "\(name) \(suffix)"
            suffix += 1
        }
        let page = CustomDiscoverPage(name: title, icon: icon)
        pages.append(page)
        currentID = page.id
        return page
    }

    mutating func removePage(_ id: String) {
        // 至少留一个页面，否则首页会没有内容可画
        guard pages.count > 1, pages.contains(where: { $0.id == id }) else { return }
        pages.removeAll { $0.id == id }
        if currentID == id { currentID = pages[0].id }
    }

    /// 拖拽排序（`Array.move(fromOffsets:toOffset:)` 是 SwiftUI 的扩展，
    /// Engine 层不依赖 SwiftUI，这里手写一份等价逻辑）。
    mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.sorted().compactMap { pages.indices.contains($0) ? pages[$0] : nil }
        for index in source.sorted(by: >) where pages.indices.contains(index) {
            pages.remove(at: index)
        }
        var target = destination
        for index in source.sorted() where index < destination { target -= 1 }
        target = min(max(target, 0), pages.count)
        pages.insert(contentsOf: moving, at: target)
    }
}
