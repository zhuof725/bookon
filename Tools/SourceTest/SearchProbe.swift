import Foundation

/// 聚合书源搜索探针：走真实 WebBook.search，打印每个环节的日志与结果。
enum SearchProbe {
    static func run(file: String, key: String) async throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: file))
        let sources = try JSONDecoder().decode([BookSource].self, from: data)
        guard let s = sources.first else { print("书源为空"); return }
        print("书源: \(s.bookSourceName) jsLib=\(s.jsLib?.count ?? 0)")
        let t0 = Date()
        let books = (try? await WebBook.search(source: s, key: key)) ?? []
        print("搜索耗时 \(String(format: "%.1f", Date().timeIntervalSince(t0)))s，结果 \(books.count) 条")
        for b in books.prefix(3) {
            print("  \(b.name) | \(b.author) | \(String(b.bookUrl.prefix(90)))")
        }
        print("PROBE-DONE")
    }
}
