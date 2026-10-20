import Foundation

/// 发现页探针：打印每个书源的发现分类，并抓取第一个分类的书单（验证 exploreUrl/ruleExplore）。
enum ExploreProbe {
    static func run(file: String, key: String) async throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: file))
        let sources = try JSONDecoder().decode([BookSource].self, from: data)
        print("共 \(sources.count) 个书源")
        for s in sources {
            let kinds = SourceDiagnostics.exploreKinds(source: s)
            print("==== \(s.bookSourceName)  分类 \(kinds.count) 项")
            for k in kinds.prefix(8) {
                print("  - \(k.title) | \(k.url ?? "-") | type=\(k.type ?? "-")")
            }
            if let error = DiscoverCatalog.kindError(kinds) { print("  ✗ \(error)") }
            guard let first = kinds.first(where: { !($0.url ?? "").isEmpty }) else {
                print("  （没有可浏览的分类）")
                print("")
                continue
            }
            do {
                let books = try await SourceDiagnostics.explore(source: s, url: first.url ?? "", page: 1)
                print("  首个分类「\(first.title)」: \(books.count) 本")
                for b in books.prefix(3) {
                    print("    \(b.name) / \(b.author) / \(String(b.bookUrl.prefix(90)))")
                }
            } catch {
                print("  首个分类「\(first.title)」失败: \(error)")
            }
            print("")
        }
        print("EXPLORE-PROBE-DONE")
    }
}
