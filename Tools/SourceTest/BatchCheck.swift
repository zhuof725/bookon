import Foundation

/// 命令行批量校验（对齐原版「校验书源」）：
/// SourceTest --check-batch <sources.json> [关键词] [超时秒] [并发] [数量上限]
enum BatchCheckCLI {
    static func run(file: String, keyword: String, timeout: Double, concurrency: Int, limit: Int) async {
        guard let data = FileManager.default.contents(atPath: file) else {
            print("无法读取 \(file)")
            return
        }
        let decoded: [BookSource]
        do {
            decoded = try JSONDecoder().decode([BookSource].self, from: data)
        } catch {
            print("书源解析失败: \(error)")
            return
        }
        var list = decoded.filter { !$0.bookSourceName.contains("魔丸") && $0.isEnabled }
        if limit > 0 { list = Array(list.prefix(limit)) }
        if list.isEmpty {
            print("没有可校验的书源（全部禁用或列表为空）")
            return
        }
        var options = SourceCheck.Options()
        options.keyword = keyword
        options.timeout = timeout
        options.concurrency = max(1, concurrency)
        print("批量校验 \(list.count) 个书源（共 \(decoded.count) 个，跳过禁用/魔丸）")
        print(options.summary)

        var done = 0
        let results = await SourceCheck.runAll(
            list,
            options: options,
            onStart: { s in
                print("→ \(s.bookSourceName) \(s.bookSourceUrl)")
            },
            onResult: { r in
                done += 1
                let state = r.cancelled ? "取消" : (r.success ? "成功" : "失败")
                print("[\(done)/\(list.count)] \(state) \(r.respondTime)ms \(r.name) — \(r.message)")
                if !r.groups.isEmpty {
                    print("        失效分组: \(r.groups.joined(separator: ","))")
                }
            }
        )

        let ok = results.filter { $0.success }.count
        let bad = results.filter { !$0.success && !$0.cancelled }.count
        print("BATCH SUMMARY: 成功 \(ok) / 失败 \(bad) / 共 \(results.count)")
        var counts: [String: Int] = [:]
        for r in results {
            for g in r.groups { counts[g, default: 0] += 1 }
        }
        if !counts.isEmpty {
            let line = counts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
            print("失效分组汇总: \(line)")
        }
    }
}
