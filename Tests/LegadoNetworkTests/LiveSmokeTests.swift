//
//  LiveSmokeTests.swift
//  LegadoNetworkTests
//
//  第 6 步 6B：对仓库内真实书源配置做一次「真实网络」冒烟：
//  用 AnalyzeUrl 解析搜索结果 URL（关键字「斗罗」），再用 URLSessionHTTPClient 真实请求，
//  输出一份文本报告到 artifact 目录。
//
//  该测试**依赖真实外网**，因此：
//    - 仅当环境变量 LEGADO_LIVE_SMOKE=1 时执行，否则静默跳过（不影响 CI 主链路）；
//    - 单个书源失败**不算失败**（只记录到报告），整体始终 pass ——
//      失败判定交给报告阅读者，避免外网站点抖动把 CI 变红。
//
//  书源来源：Tests/LegadoNetworkTests/Resources/配置文件_7个.json（测试 target 自带副本）。
//  说明：README 第 4 步曾提到 `配置文件_14个.json`（14 个书源），该文件未随仓库保存，
//  仓库内实际存在的是 7 个书源的配置，本冒烟以实际文件为准。
//

import XCTest
@testable import LegadoBookSource

final class LiveSmokeTests: XCTestCase {

    private static let searchKeyword = "斗罗"

    /// 报告输出目录（CI 里用 LEGADO_LIVE_SMOKE_OUT 指向 artifact 收集目录）。
    private func reportURL() -> URL {
        let env = ProcessInfo.processInfo.environment
        if let dir = env["LEGADO_LIVE_SMOKE_OUT"], !dir.isEmpty {
            return URL(fileURLWithPath: dir).appendingPathComponent("live_smoke_report.txt")
        }
        return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("live_smoke_report.txt")
    }

    private func locateSourceFile() -> URL? {
        // 1) 测试 target 自带的资源
        if let u = Bundle.module.url(forResource: "配置文件_7个", withExtension: "json") { return u }
        // 2) 源码树相对路径（本地 swift test 时 cwd 为包根）
        let candidates = [
            "Tests/LegadoAnalyzeRuleTests/Resources/配置文件_7个.json",
            "../Tests/LegadoAnalyzeRuleTests/Resources/配置文件_7个.json",
        ]
        for c in candidates {
            let u = URL(fileURLWithPath: c)
            if FileManager.default.fileExists(atPath: u.path) { return u }
        }
        return nil
    }

    func testLiveSearchSmoke() async throws {
        guard ProcessInfo.processInfo.environment["LEGADO_LIVE_SMOKE"] == "1" else {
            throw XCTSkip("未设置 LEGADO_LIVE_SMOKE=1，跳过真实网络冒烟（该测试需要外网）。")
        }
        guard let file = locateSourceFile(),
              let data = try? Data(contentsOf: file),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            // 刻意不失败：冒烟缺输入时只报错到报告。
            try writeReport(["live-smoke: 未找到书源配置文件，跳过。"])
            return
        }

        var lines: [String] = []
        lines.append("=== legado live-smoke（真实网络）===")
        lines.append("关键字: \(Self.searchKeyword)")
        lines.append("书源文件: \(file.path)（共 \(raw.count) 个书源）")
        lines.append("时间: \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("")

        // 用内存实现构造真实客户端（冒烟不需要落盘 Cookie）。
        let cache = CacheManager(storage: MemoryCacheStorage())
        let store = CookieStore(persistence: MemoryCookiePersistence(), cache: cache)
        let client = URLSessionHTTPClient(cookieStore: store, cookieManagerCache: cache)
        let environment = AnalyzeUrlEnvironment()

        var okCount = 0
        var failCount = 0

        for item in raw {
            let name = (item["bookSourceName"] as? String) ?? "<未命名>"
            let searchUrl = (item["searchUrl"] as? String) ?? ""
            lines.append("--- 书源: \(name) ---")
            guard !searchUrl.isEmpty else {
                lines.append("  [skip] searchUrl 为空")
                failCount += 1
                lines.append("")
                continue
            }
            do {
                let analyzeUrl = AnalyzeUrl(searchUrl, key: Self.searchKeyword, page: 1,
                                            baseUrl: (item["bookSourceUrl"] as? String) ?? "",
                                            environment: environment)
                lines.append("  解析后 URL: \(analyzeUrl.url)")
                lines.append("  method: \(analyzeUrl.method.rawValue)")

                var request = analyzeUrl.buildRequest()
                request.callTimeout = 20_000
                request.readTimeout = 20_000

                let start = Date()
                let response = try await client.execute(request)
                let elapsed = Int(Date().timeIntervalSince(start) * 1000)
                lines.append("  HTTP: \(response.status) \(response.message ?? "")  (\(elapsed) ms)")
                lines.append("  Content-Type: \(response.header("Content-Type") ?? "-")")
                lines.append("  响应字节: \(response.body.count)")
                let preview = String(decoding: response.body.prefix(200), as: UTF8.self)
                    .replacingOccurrences(of: "\n", with: " ")
                lines.append("  预览: \(preview)")
                if (200...399).contains(response.status) { okCount += 1 } else { failCount += 1 }
            } catch {
                lines.append("  [fail] \(error)")
                failCount += 1
            }
            lines.append("")
        }

        lines.append("=== 汇总 ===")
        lines.append("成功(2xx/3xx): \(okCount)  失败: \(failCount)  合计: \(raw.count)")
        try writeReport(lines)

        // 冒烟本身不因外网站点失败而 fail（按用户要求：失败不算 CI 失败）。
        XCTAssertEqual(okCount + failCount, raw.count)
    }

    private func writeReport(_ lines: [String]) throws {
        let out = reportURL()
        try? FileManager.default.createDirectory(at: out.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        let text = lines.joined(separator: "\n") + "\n"
        try text.write(to: out, atomically: true, encoding: .utf8)
        // 同时打到 stderr，方便在 CI 日志里直接看到。
        FileHandle.standardError.write(Data(text.utf8))
    }
}
