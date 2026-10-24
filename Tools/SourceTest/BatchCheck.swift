import Foundation

/// 命令行批量校验（对齐原版「校验书源」）：
/// SourceTest --check-batch <sources.json> [关键词] [超时秒] [并发] [数量上限]
///
/// 结果文件（可用环境变量 CHECK_OUT_DIR 指定目录，默认当前目录）：
/// - passed-sources.json  校验通过（搜索 → 详情 → 目录 → 正文 全部成功）的书源，保留原始 JSON 字段
/// - failed-sources.json  校验失败的书源，附带失败原因 / 失效分组 / 耗时
/// - check-results.json   每个书源的完整校验结果明细
/// - skipped-sources.json 未参与校验的书源（禁用 / 魔丸等）
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
        // 原始 JSON（保留书源全部字段，导出时原样写回）
        let rawObjects: [[String: Any]] = {
            guard let obj = try? JSONSerialization.jsonObject(with: data),
                  let arr = obj as? [[String: Any]] else { return [] }
            return arr
        }()
        var rawByURL: [String: [String: Any]] = [:]
        for obj in rawObjects {
            if let url = obj["bookSourceUrl"] as? String { rawByURL[url] = obj }
        }

        let enabled = decoded.filter { !$0.bookSourceName.contains("魔丸") && $0.isEnabled }
        let list = limit > 0 ? Array(enabled.prefix(limit)) : enabled
        let checkedURLs = Set(list.map { $0.bookSourceUrl })
        let skipped = decoded.filter { !checkedURLs.contains($0.bookSourceUrl) }
        if list.isEmpty {
            print("没有可校验的书源（全部禁用或列表为空）")
            return
        }
        var options = SourceCheck.Options()
        options.keyword = keyword
        options.timeout = timeout
        options.concurrency = max(1, concurrency)
        print("批量校验 \(list.count) 个书源（共 \(decoded.count) 个，跳过禁用/魔丸 \(skipped.count) 个）")
        print(options.summary)

        let counter = TestConcurrencyState()
        let results = await SourceCheck.runAll(
            list,
            options: options,
            onStart: { s in
                print("→ \(s.bookSourceName) \(s.bookSourceUrl)")
            },
            onResult: { r in
                counter.markResult()
                let done = counter.results
                let state = r.cancelled ? "取消" : (r.success ? "成功" : "失败")
                print("[\(done)/\(list.count)] \(state) \(r.respondTime)ms \(r.name) — \(r.message)")
                if !r.groups.isEmpty {
                    print("        失效分组: \(r.groups.joined(separator: ","))")
                }
            }
        )

        let ok = results.filter { $0.success }.count
        let bad = results.filter { !$0.success && !$0.cancelled }.count
        let cancelled = results.filter { $0.cancelled }.count
        print("BATCH SUMMARY: 成功 \(ok) / 失败 \(bad) / 取消 \(cancelled) / 共 \(results.count)")
        var counts: [String: Int] = [:]
        for r in results {
            for g in r.groups { counts[g, default: 0] += 1 }
        }
        if !counts.isEmpty {
            let line = counts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
            print("失效分组汇总: \(line)")
        }

        // ── 导出结果 ────────────────────────────────────────────────
        let outDir = ProcessInfo.processInfo.environment["CHECK_OUT_DIR"] ?? "."
        try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

        func originalObject(_ source: BookSource) -> [String: Any] {
            var obj = rawByURL[source.bookSourceUrl] ?? [:]
            if obj.isEmpty {
                // 兜底：没有原始 JSON 时用模型编码
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                if let d = try? encoder.encode(source),
                   let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                    obj = o
                }
            }
            return obj
        }

        var passed: [[String: Any]] = []
        var failed: [[String: Any]] = []
        var details: [[String: Any]] = []

        for r in results {
            var obj = originalObject(r.updatedSource)
            obj["checkSuccess"] = r.success
            obj["checkMessage"] = r.message
            obj["checkGroups"] = r.groups
            obj["checkRespondTime"] = r.respondTime
            if !r.success {
                obj["checkReason"] = r.message.hasPrefix("校验失败:") ? String(r.message.dropFirst("校验失败:".count)) : r.message
                if let g = r.group { obj["checkGroup"] = g }
                failed.append(obj)
            } else {
                passed.append(obj)
            }
            var detail: [String: Any] = [
                "name": r.name,
                "bookSourceUrl": r.bookSourceUrl,
                "success": r.success,
                "cancelled": r.cancelled,
                "message": r.message,
                "groups": r.groups,
                "respondTime": r.respondTime,
            ]
            detail["group"] = r.group ?? ""
            details.append(detail)
        }

        var skippedObjects: [[String: Any]] = []
        for s in skipped {
            var obj = originalObject(s)
            obj["checkSkipped"] = true
            obj["checkSkipReason"] = s.isEnabled ? "名称含魔丸（历史兼容跳过）" : "书源已禁用"
            skippedObjects.append(obj)
        }

        writeJSON(passed, to: "\(outDir)/passed-sources.json")
        writeJSON(failed, to: "\(outDir)/failed-sources.json")
        writeJSON(details, to: "\(outDir)/check-results.json")
        writeJSON(skippedObjects, to: "\(outDir)/skipped-sources.json")
        print("结果已导出: \(outDir)/passed-sources.json (\(passed.count)) / failed-sources.json (\(failed.count)) / check-results.json (\(details.count))")
    }

    /// 写 JSON 数组（顶层为数组，无需 .fragmentsAllowed）。
    private static func writeJSON(_ objects: [[String: Any]], to path: String) {
        guard !objects.isEmpty else {
            // 空数组也要生成文件，避免下游合并脚本读不到文件
            FileManager.default.createFile(atPath: path, contents: Data("[]".utf8))
            return
        }
        guard let data = try? JSONSerialization.data(withJSONObject: objects, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: URL(fileURLWithPath: path))
    }
}
