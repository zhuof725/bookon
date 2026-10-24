import Foundation

/// 多分类竖排榜的数据加载。
///
/// 一个板块要同时持有多个分类的书单：切标签时只请求没拿过的那一个，
/// 拿过的留在内存里，来回切不重复走网络。
@MainActor
enum MultiRankLoader {
    /// 已经拿到的分类（键 = 书源 + 分类地址），跨板块共享，
    /// 同一个分类出现在两个板块时不用各拉一遍。
    private static var cache: [String: [DeckItem]] = [:]

    static func cached(sourceUrl: String, kindUrl: String) -> [DeckItem]? {
        cache[key(sourceUrl: sourceUrl, kindUrl: kindUrl)]
    }

    static func store(_ items: [DeckItem], sourceUrl: String, kindUrl: String) {
        cache[key(sourceUrl: sourceUrl, kindUrl: kindUrl)] = items
    }

    private static func key(sourceUrl: String, kindUrl: String) -> String {
        "\(sourceUrl)|\(kindUrl)"
    }

    /// 拉一个分类的书单。失败返回 nil（由界面显示重试）。
    static func load(_ kind: MultiRankKind, source: BookSource) async -> [DeckItem]? {
        if let hit = cached(sourceUrl: source.bookSourceUrl, kindUrl: kind.url) { return hit }
        do {
            let books = try await SourceDiagnostics.explore(source: source, url: kind.url)
            // 封面走 BookCoverLocation，本地书也能显示（与首页板块同一套解析）
            let items = books.map { DeckItem(id: $0.bookUrl,
                                             title: $0.name,
                                             caption: $0.author,
                                             cover: BookCoverLocation.url(for: $0)) }
            store(items, sourceUrl: source.bookSourceUrl, kindUrl: kind.url)
            return items
        } catch {
            return nil
        }
    }

    static func clearCache() { cache.removeAll() }
}
