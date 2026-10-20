import Foundation

/// 聚合书源搜索探针：走真实 WebBook.search，并单独验证 java.ajax 链路。
enum SearchProbe {
    static func run(file: String, key: String) async throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: file))
        let sources = try JSONDecoder().decode([BookSource].self, from: data)
        guard let s = sources.first else { print("书源为空"); return }
        print("书源: \(s.bookSourceName) jsLib=\(s.jsLib?.count ?? 0)")
        let context = RuleContext(source: s)

        // 1) 直接测 java.ajax 的底层 connectNative：不带书源 options，纯地址。
        let plain = "https://v1.qingtian618.com/search?title=\(key)&tab=小说&source=全部&page=1&disabled_sources=0"
        let bridge = JavaBridge(context: context)
        let r1 = bridge.connectNative(plain + ",{\"method\":\"GET\",\"headers\":{\"cookie\":\"qttoken=;deviceId=test;\",\"Content-Type\":\"application/json\"},\"body\":\"{}\"}")
        print("A) 带options: \(r1.map { "code=\($0.code) len=\($0.body.count)" } ?? "nil")")
        if r1 == nil {
            // 逐步拆：只加 method、只加 headers、只加 body
            for (label, opt) in [("仅method", "{\"method\":\"GET\"}"),
                                 ("仅headers", "{\"headers\":{\"cookie\":\"qttoken=;deviceId=test;\"}}"),
                                 ("仅body", "{\"body\":\"{}\"}"),
                                 ("method+body", "{\"method\":\"GET\",\"body\":\"{}\"}")] {
                let r = bridge.connectNative(plain + "," + opt)
                print("A-\(label): \(r.map { "code=\($0.code) len=\($0.body.count)" } ?? "nil")")
            }
        }
        let r2 = bridge.connectNative(plain)
        print("B) 纯地址:   \(r2.map { "code=\($0.code) len=\($0.body.count)" } ?? "nil")")

        // 2) 书源 request() 完整链路（jsLib 里的 request(url)）
        let lib = s.jsLib ?? ""
        if !lib.isEmpty {
            let probe = "globalThis.__probeUrl=function(u){return request(u)};"
            _ = JSEngine.shared.eval(probe, baseUrl: s.bookSourceUrl, jsLib: lib, context: context)
            let out = JSEngine.shared.eval("__probeUrl('/search?title=${encodeURIComponent(key)}&tab=${encodeURIComponent('小说')}&source=${encodeURIComponent('全部')}&page=1&disabled_sources=0')",
                                           baseUrl: s.bookSourceUrl, vars: ["key": key], jsLib: lib, context: context)
            let str = (out as? String) ?? ""
            print("C) request(): len=\(str.count) 开头=\(String(str.prefix(120)))")
        }

        // 3) 完整搜索
        let t0 = Date()
        let books = (try? await WebBook.search(source: s, key: key)) ?? []
        print("搜索耗时 \(String(format: "%.1f", Date().timeIntervalSince(t0)))s，结果 \(books.count) 条")
        for b in books.prefix(3) {
            print("  \(b.name) | \(b.author) | \(String(b.bookUrl.prefix(90)))")
        }
        print("PROBE-DONE")
    }
}
