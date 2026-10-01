//
//  GoldenComparisonTests.swift
//  LegadoHTMLEngineTests
//
//  用 CI 的 `golden` job 生成的对照数据（真实 jsoup 1.16.2 + JsoupXpath 2.5.3 跑出的结果）
//  逐条比较本项目 Swift 实现的输出。不一致的用例不静默放过：失败信息包含
//  「规则 / 输入(HTML) / Java 结果 / Swift 结果」。
//
//  golden 数据由 scripts/golden（Java/Maven 项目）生成，CI 里由 `golden` job 产出为 artifact，
//  test-macos / test-ios-simulator 在 `swift build` 之前下载到 Resources/golden/ 目录，
//  随 SwiftPM 资源一起打进测试 App Bundle（iOS 模拟器沙盒里也能读到）。
//  每条 golden 结果里直接内嵌了用到的 HTML 全文，不依赖仓库里其它路径。
//  本地未跑过 golden job 时该目录为空，这里会跳过（不是误报失败）；
//  但 CI 的两个测试 job 都 `needs: golden`，所以 CI 里一定会真的跑到这些比较。
//

import XCTest
@testable import LegadoBookSource

final class GoldenComparisonTests: XCTestCase {

    // MARK: - Golden JSON 模型（与 scripts/golden/src/main/java/golden/Main.java 的输出对应）

    struct GoldenOutput: Decodable {
        let cssResults: [CssResult]?
        let xpathResults: [XPathResult]?
    }
    struct CssResult: Decodable {
        let name: String
        let rule: String
        let htmlKey: String
        let html: String
        let elementsCount: Int?
        let getString: String?
        let getStringList: [String]?
        let getString0: String?
        let error: String?
    }
    struct XPathResult: Decodable {
        let name: String
        let rule: String
        let htmlKey: String
        let html: String
        let elementsCount: Int?
        let getString: String?
        let getStringList: [String]?
        let error: String?
    }

    // MARK: - 定位 golden 目录（Resources/golden，由 CI 的 golden job 产出下载而来）

    private func goldenDirectory() -> URL? {
        guard let resourceURL = Bundle.module.resourceURL else { return nil }
        let golden = resourceURL.appendingPathComponent("golden")
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: golden.path, isDirectory: &isDir), isDir.boolValue {
            return golden
        }
        // 兜底：递归搜索（不同平台/SwiftPM 版本打包资源的目录结构可能不同）。
        if let en = FileManager.default.enumerator(at: resourceURL, includingPropertiesForKeys: nil) {
            for case let f as URL in en where f.lastPathComponent == "golden" && f.hasDirectoryPath {
                return f
            }
        }
        return nil
    }

    private func goldenFiles() -> [URL] {
        guard let dir = goldenDirectory() else { return [] }
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return []
        }
        return files.filter { $0.pathExtension == "json" }
    }

    /// 是否在 CI 环境中运行。GitHub Actions 对所有 job 都会设置 `CI=true` 和 `GITHUB_ACTIONS=true`。
    /// CI 环境下 golden 数据缺失/为空必须判为测试失败，不允许用 XCTSkip 静默跳过——
    /// 因为 CI 的 test-macos/test-ios-simulator 两个 job 都 `needs: golden`，正常情况下
    /// golden 数据必然存在；如果缺失，说明 artifact 下载/打包环节出了问题，必须暴露出来，
    /// 而不是被 XCTSkip 掩盖成"看起来绿色"的假通过。只有在本地开发环境（没跑 golden job）
    /// 时才允许跳过。
    private func isRunningInCI() -> Bool {
        let env = ProcessInfo.processInfo.environment
        // 多个信号任一命中即判定为 CI：GitHub Actions 对所有 job（含 xcodebuild 在
        // iOS 模拟器里启动的测试进程）通常会设置这些变量，但环境变量透传到模拟器
        // 测试进程在不同 Xcode/模拟器版本上可能有差异，这里用多个变量兜底提高可靠性。
        let ciSignals = ["CI", "GITHUB_ACTIONS", "GITHUB_WORKFLOW", "GITHUB_RUN_ID", "RUNNER_OS"]
        for key in ciSignals {
            if let v = env[key], !v.isEmpty { return true }
        }
        return false
    }

    /// 统一处理"没有可比较用例"的情况：CI 下必须 XCTFail（不允许跳过），本地允许 XCTSkip。
    private func failOrSkipWhenNoGoldenData(_ reason: String) throws {
        if isRunningInCI() {
            XCTFail("CI 环境下 golden 对照数据缺失或为空，视为失败（不允许静默跳过）：\(reason)")
            return
        }
        throw XCTSkip("\(reason)（本地未跑 golden job，CI 的 test-macos/test-ios-simulator 均 needs: golden，会真正执行此比较）。")
    }

    // MARK: - 主测试：逐个 golden 文件、逐条用例比较

    func testAllGoldenCssCases() throws {
        let files = goldenFiles()
        if files.isEmpty {
            try failOrSkipWhenNoGoldenData("未找到 golden 目录")
            return
        }
        var comparedAny = false
        var failures: [String] = []

        for fileURL in files {
            let baseName = fileURL.deletingPathExtension().lastPathComponent
            guard let data = try? Data(contentsOf: fileURL),
                  let output = try? JSONDecoder().decode(GoldenOutput.self, from: data),
                  let cssResults = output.cssResults else { continue }

            for result in cssResults {
                comparedAny = true
                let html = result.html
                do {
                    let j = try AnalyzeByJSoup(html)
                    let swiftElementsCount = try j.getElements(result.rule).size()
                    let swiftGetString = try j.getString(result.rule)
                    let swiftGetStringList = try j.getStringList(result.rule)
                    let swiftGetString0 = try j.getString0(result.rule)

                    if let javaCount = result.elementsCount, javaCount != swiftElementsCount {
                        failures.append("""
                        [CSS:\(baseName)/\(result.name)] elementsCount 不一致
                          规则: \(result.rule)
                          输入(HTML key=\(result.htmlKey)): \(html)
                          Java 结果: \(javaCount)
                          Swift 结果: \(swiftElementsCount)
                        """)
                    }
                    if result.getString != swiftGetString {
                        failures.append("""
                        [CSS:\(baseName)/\(result.name)] getString 不一致
                          规则: \(result.rule)
                          输入(HTML key=\(result.htmlKey)): \(html)
                          Java 结果: \(String(describing: result.getString))
                          Swift 结果: \(String(describing: swiftGetString))
                        """)
                    }
                    if let javaList = result.getStringList, javaList != swiftGetStringList {
                        failures.append("""
                        [CSS:\(baseName)/\(result.name)] getStringList 不一致
                          规则: \(result.rule)
                          输入(HTML key=\(result.htmlKey)): \(html)
                          Java 结果: \(javaList)
                          Swift 结果: \(swiftGetStringList)
                        """)
                    }
                    if let javaS0 = result.getString0, javaS0 != swiftGetString0 {
                        failures.append("""
                        [CSS:\(baseName)/\(result.name)] getString0 不一致
                          规则: \(result.rule)
                          输入(HTML key=\(result.htmlKey)): \(html)
                          Java 结果: \(javaS0)
                          Swift 结果: \(swiftGetString0)
                        """)
                    }
                } catch {
                    if result.error == nil {
                        failures.append("""
                        [CSS:\(baseName)/\(result.name)] Swift 抛错但 Java 未报错
                          规则: \(result.rule)
                          输入(HTML key=\(result.htmlKey)): \(html)
                          Java 结果: 无错误
                          Swift 结果: 抛出 \(error)
                        """)
                    }
                }
            }
        }

        if !comparedAny {
            try failOrSkipWhenNoGoldenData("golden 目录存在但没有可比较的 CSS 用例")
            return
        }
        if !failures.isEmpty {
            XCTFail("发现 \(failures.count) 处 CSS golden 不一致：\n\n" + failures.joined(separator: "\n\n"))
        }
    }

    /// 已知、已在 README「与 Kotlin 已知差异」表逐条记录、确认无法对齐的用例
    /// （标记为 `name/field` 跳过，仍会跑 Swift 代码，只是不拿这条的结果做强一致性断言）。
    /// 不是"隐藏失败"：每一条都有 README 对应条目可查，且仍计入下方「已知差异清单」打印。
    /// 已修复，当前为空：此前这里登记过 `xpathPercentInterleave`（getString 对 %% 的处理）
    /// 与 `xpath_real_caimoge/realBookList`（void 元素 outerHtml 自闭合格式）两组差异，
    /// 现均已修复（见 README「XPath 引擎已知差异」表与 `SwiftSoupVoidElementFix`），
    /// golden 对照不再需要跳过任何用例。
    private let knownDivergences: Set<String> = []

    func testAllGoldenXPathCases() throws {
        let files = goldenFiles()
        if files.isEmpty {
            try failOrSkipWhenNoGoldenData("未找到 golden 目录")
            return
        }
        var comparedAny = false
        var failures: [String] = []

        for fileURL in files {
            let baseName = fileURL.deletingPathExtension().lastPathComponent
            guard let data = try? Data(contentsOf: fileURL),
                  let output = try? JSONDecoder().decode(GoldenOutput.self, from: data),
                  let xpathResults = output.xpathResults else { continue }

            for result in xpathResults {
                comparedAny = true
                let html = result.html
                do {
                    let x = try AnalyzeByXPath(html)
                    // 注意：golden 生成器（Java）里 getElements 对 XPath 解析失败的情况统一吞异常返回
                    // null（约定 elementsCount=-1），用来表达"这条语法不受 JsoupXpath 支持"。
                    // Swift 侧 getElements 按 Kotlin 原始签名是 throws 的（语法错误会向上传播，
                    // 对齐 Kotlin AnalyzeByXPath.getResult 不吞异常的真实行为）。
                    // 两者在"语法不支持"这件事上结论一致，只是表达方式不同（-1 哨兵值 vs 抛错），
                    // 这里统一按 "Swift 抛错 == Java 返回 -1" 处理，不算不一致。
                    var swiftElementsCount = -1
                    var swiftThrew = false
                    do {
                        let swiftElements = try x.getElements(result.rule)
                        swiftElementsCount = swiftElements?.count ?? -1
                    } catch {
                        swiftThrew = true
                    }
                    let swiftGetString = try? x.getString(result.rule)
                    let swiftGetStringList = (try? x.getStringList(result.rule)) ?? []

                    if swiftThrew {
                        // Swift 抛错，视为与 Java 的 -1/nil/[] 等价，仅当 Java 结果看起来「成功」
                        // （elementsCount 不是 -1 或为 nil 以外的正常值）时才算不一致。
                        if let javaCount = result.elementsCount, javaCount >= 0 {
                            failures.append("""
                            [XPath:\(baseName)/\(result.name)] Swift 抛错但 Java 有效（count=\(javaCount)）
                              规则: \(result.rule)
                              输入(HTML key=\(result.htmlKey)): \(html)
                              Java 结果: elementsCount=\(javaCount)
                              Swift 结果: 抛出异常（不支持该语法）
                            """)
                        }
                        continue
                    }

                    if let javaCount = result.elementsCount, javaCount != swiftElementsCount,
                       !knownDivergences.contains("\(baseName)/\(result.name)/elementsCount") {
                        failures.append("""
                        [XPath:\(baseName)/\(result.name)] elementsCount 不一致
                          规则: \(result.rule)
                          输入(HTML key=\(result.htmlKey)): \(html)
                          Java 结果: \(javaCount)
                          Swift 结果: \(swiftElementsCount)
                        """)
                    }
                    if result.getString != swiftGetString,
                       !knownDivergences.contains("\(baseName)/\(result.name)/getString") {
                        failures.append("""
                        [XPath:\(baseName)/\(result.name)] getString 不一致
                          规则: \(result.rule)
                          输入(HTML key=\(result.htmlKey)): \(html)
                          Java 结果: \(String(describing: result.getString))
                          Swift 结果: \(String(describing: swiftGetString))
                        """)
                    }
                    if let javaList = result.getStringList, javaList != swiftGetStringList,
                       !knownDivergences.contains("\(baseName)/\(result.name)/getStringList") {
                        failures.append("""
                        [XPath:\(baseName)/\(result.name)] getStringList 不一致
                          规则: \(result.rule)
                          输入(HTML key=\(result.htmlKey)): \(html)
                          Java 结果: \(javaList)
                          Swift 结果: \(swiftGetStringList)
                        """)
                    }
                } catch {
                    if result.error == nil {
                        failures.append("""
                        [XPath:\(baseName)/\(result.name)] Swift 抛错但 Java 未报错
                          规则: \(result.rule)
                          输入(HTML key=\(result.htmlKey)): \(html)
                          Java 结果: 无错误
                          Swift 结果: 抛出 \(error)
                        """)
                    }
                }
            }
        }

        if !comparedAny {
            try failOrSkipWhenNoGoldenData("golden 目录存在但没有可比较的 XPath 用例")
            return
        }
        if !failures.isEmpty {
            XCTFail("发现 \(failures.count) 处 XPath golden 不一致：\n\n" + failures.joined(separator: "\n\n"))
        }
    }
}
