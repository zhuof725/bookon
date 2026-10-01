//
//  UtilGoldenComparisonTests.swift
//  LegadoHTMLEngineTests
//
//  第 4 步 C：用真实 Java 库生成的 golden 对照数据逐条比较工具函数：
//   - getAbsoluteURL（对照真实 java.net.URL，经 Kotlin NetworkUtils 调度）
//   - unescapeHtml4（对照真实 commons-text 1.13.1）
//   - replaceRegex（对照 Kotlin AnalyzeRule.replaceRegex 语义，真实 java.util.regex）
//   - AnalyzeByRegex.getElement/getElements（对照真实 Java 正则）
//   - JSONPath getString/getStringList（对照真实 Jayway JsonPath 2.10.0，json-smart）
//
//  失败信息含「规则/输入/Java结果/Swift结果」。CI 下 golden 缺失必须 fail（不许 XCTSkip）。
//  golden 数据由 scripts/golden（Java/Maven）产出，CI 的 golden job 下载到 Resources/golden。
//

import XCTest
@testable import LegadoBookSource

final class UtilGoldenComparisonTests: XCTestCase {

    // MARK: - golden 定位（复用 GoldenComparisonTests 的策略）

    private func goldenDirectory() -> URL? {
        guard let resourceURL = Bundle.module.resourceURL else { return nil }
        let golden = resourceURL.appendingPathComponent("golden")
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: golden.path, isDirectory: &isDir), isDir.boolValue {
            return golden
        }
        if let en = FileManager.default.enumerator(at: resourceURL, includingPropertiesForKeys: nil) {
            for case let f as URL in en where f.lastPathComponent == "golden" && f.hasDirectoryPath {
                return f
            }
        }
        return nil
    }

    private func goldenFiles() -> [URL] {
        guard let dir = goldenDirectory() else { return [] }
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }
        return files.filter { $0.pathExtension == "json" }
    }

    private func isRunningInCI() -> Bool {
        let env = ProcessInfo.processInfo.environment
        for key in ["CI", "GITHUB_ACTIONS", "GITHUB_WORKFLOW", "GITHUB_RUN_ID", "RUNNER_OS"] {
            if let v = env[key], !v.isEmpty { return true }
        }
        return false
    }

    private func failOrSkipWhenNoGoldenData(_ reason: String) throws {
        if isRunningInCI() {
            XCTFail("CI 环境下 golden 对照数据缺失或为空，视为失败（不允许静默跳过）：\(reason)")
            return
        }
        throw XCTSkip("\(reason)（本地未跑 golden job）。")
    }

    // MARK: - golden JSON 模型

    private struct Envelope: Decodable {
        let urlResults: [UrlResult]?
        let unescapeResults: [UnescapeResult]?
        let regexReplaceResults: [RegexReplaceResult]?
        let regexAnalyzeResults: [RegexAnalyzeResult]?
        let jsonPathResults: [JsonPathResult]?
    }
    private struct UrlResult: Decodable { let name: String; let base: String?; let relative: String; let result: String }
    private struct UnescapeResult: Decodable { let name: String; let input: String; let result: String }
    private struct RegexReplaceResult: Decodable {
        let name: String; let input: String; let regex: String; let replacement: String
        let replaceFirst: Bool; let result: String
    }
    private struct RegexAnalyzeResult: Decodable {
        let name: String; let res: String; let regs: [String]
        let getElement: [String?]?        // 可能含 null
        let getElementError: String?
        let getElements: [[String]]
        let getElementsError: String?
    }
    private struct JsonPathResult: Decodable {
        let name: String; let rule: String; let docKey: String; let json: String
        let getString: String?; let getStringList: [String]; let threw: Bool
    }

    private func decodeAll() -> [(String, Envelope)] {
        var out: [(String, Envelope)] = []
        for fileURL in goldenFiles() {
            let baseName = fileURL.deletingPathExtension().lastPathComponent
            guard let data = try? Data(contentsOf: fileURL),
                  let env = try? JSONDecoder().decode(Envelope.self, from: data) else { continue }
            out.append((baseName, env))
        }
        return out
    }

    // MARK: - getAbsoluteURL

    func testGoldenGetAbsoluteURL() throws {
        let files = goldenFiles()
        if files.isEmpty { try failOrSkipWhenNoGoldenData("未找到 golden 目录"); return }
        var compared = false
        var failures: [String] = []
        for (baseName, env) in decodeAll() {
            guard let cases = env.urlResults else { continue }
            for c in cases {
                compared = true
                let swift = NetworkUtils.getAbsoluteURL(c.base, c.relative)
                if swift != c.result && !knownURLDivergences.contains("\(c.name)") {
                    failures.append("""
                    [URL:\(baseName)/\(c.name)]
                      base: \(String(describing: c.base))
                      relative: \(c.relative)
                      Java 结果: \(c.result)
                      Swift 结果: \(swift)
                    """)
                }
            }
        }
        if !compared { try failOrSkipWhenNoGoldenData("无 URL 用例"); return }
        if !failures.isEmpty { XCTFail("发现 \(failures.count) 处 getAbsoluteURL 不一致：\n\n" + failures.joined(separator: "\n\n")) }
    }
    private let knownURLDivergences: Set<String> = []

    // MARK: - unescapeHtml4

    func testGoldenUnescapeHtml4() throws {
        let files = goldenFiles()
        if files.isEmpty { try failOrSkipWhenNoGoldenData("未找到 golden 目录"); return }
        var compared = false
        var failures: [String] = []
        for (baseName, env) in decodeAll() {
            guard let cases = env.unescapeResults else { continue }
            for c in cases {
                compared = true
                let swift = HtmlUnescape.unescapeHtml4(c.input)
                if swift != c.result && !knownUnescapeDivergences.contains("\(c.name)") {
                    failures.append("""
                    [Unescape:\(baseName)/\(c.name)]
                      输入: \(c.input)
                      Java 结果: \(c.result)
                      Swift 结果: \(swift)
                    """)
                }
            }
        }
        if !compared { try failOrSkipWhenNoGoldenData("无 unescape 用例"); return }
        if !failures.isEmpty { XCTFail("发现 \(failures.count) 处 unescapeHtml4 不一致：\n\n" + failures.joined(separator: "\n\n")) }
    }
    private let knownUnescapeDivergences: Set<String> = []

    // MARK: - replaceRegex（复刻 AnalyzeRule.replaceRegex 的核心正则替换逻辑）

    /// 与 Sources/.../AnalyzeRule+Rules.swift 的 replaceRegex 行为一致（独立实现以免驱动整个 AnalyzeRule）。
    private func swiftReplaceRegex(_ result: String, _ replaceRegexStr: String, _ replacement: String, _ replaceFirst: Bool) -> String {
        if replaceRegexStr.isEmpty { return result }
        let regex = try? NSRegularExpression(pattern: replaceRegexStr)
        if replaceFirst {
            if let regex = regex {
                let ns = result as NSString
                if let m = regex.firstMatch(in: result, range: NSRange(location: 0, length: ns.length)) {
                    let g0 = ns.substring(with: m.range)
                    let g0ns = g0 as NSString
                    let template = RegexTemplate.javaToICU(replacement)
                    if let m2 = regex.firstMatch(in: g0, range: NSRange(location: 0, length: g0ns.length)) {
                        let replaced = regex.replacementString(for: m2, in: g0, offset: 0, template: template)
                        return g0ns.replacingCharacters(in: m2.range, with: replaced)
                    }
                    return g0
                } else {
                    return ""
                }
            }
            return replacement
        } else {
            if let regex = regex {
                let ns = result as NSString
                let template = RegexTemplate.javaToICU(replacement)
                return regex.stringByReplacingMatches(in: result, range: NSRange(location: 0, length: ns.length), withTemplate: template)
            }
            return result.replacingOccurrences(of: replaceRegexStr, with: replacement)
        }
    }

    func testGoldenReplaceRegex() throws {
        let files = goldenFiles()
        if files.isEmpty { try failOrSkipWhenNoGoldenData("未找到 golden 目录"); return }
        var compared = false
        var failures: [String] = []
        for (baseName, env) in decodeAll() {
            guard let cases = env.regexReplaceResults else { continue }
            for c in cases {
                compared = true
                let swift = swiftReplaceRegex(c.input, c.regex, c.replacement, c.replaceFirst)
                if swift != c.result && !knownRegexDivergences.contains("\(c.name)") {
                    failures.append("""
                    [ReplaceRegex:\(baseName)/\(c.name)]
                      输入: \(c.input)
                      规则: regex=\(c.regex)  replacement=\(c.replacement)  first=\(c.replaceFirst)
                      Java 结果: \(c.result)
                      Swift 结果: \(swift)
                    """)
                }
            }
        }
        if !compared { try failOrSkipWhenNoGoldenData("无 replaceRegex 用例"); return }
        if !failures.isEmpty { XCTFail("发现 \(failures.count) 处 replaceRegex 不一致：\n\n" + failures.joined(separator: "\n\n")) }
    }
    private let knownRegexDivergences: Set<String> = []

    // MARK: - AnalyzeByRegex.getElement / getElements

    func testGoldenAnalyzeByRegex() throws {
        let files = goldenFiles()
        if files.isEmpty { try failOrSkipWhenNoGoldenData("未找到 golden 目录"); return }
        var compared = false
        var failures: [String] = []
        for (baseName, env) in decodeAll() {
            guard let cases = env.regexAnalyzeResults else { continue }
            for c in cases {
                compared = true
                // getElement：Java null（含组未参与导致 NPE）或抛错 -> Swift 应为 nil 或抛错
                var swiftEl: [String]? = nil
                var swiftElThrew = false
                do {
                    swiftEl = try AnalyzeByRegex.getElement(c.res, c.regs)
                } catch {
                    swiftElThrew = true
                }
                // Java 侧：getElement 为 null（含 null 元素时 Java 这里也可能列表含 null）；getElementError 非空=抛错
                let javaElNilOrThrew = (c.getElement == nil) || (c.getElementError != nil) || ((c.getElement?.contains(where: { $0 == nil })) ?? false)
                if javaElNilOrThrew {
                    // Java 无有效结果（null / 抛错 / 含 null 组）：Swift 应 nil 或抛错
                    if !(swiftEl == nil || swiftElThrew) && !knownAnalyzeRegexDivergences.contains(c.name) {
                        failures.append("""
                        [AnalyzeRegex.getElement:\(baseName)/\(c.name)] Java 无有效结果但 Swift 有
                          res: \(c.res)  regs: \(c.regs)
                          Java 结果: getElement=\(String(describing: c.getElement)) error=\(String(describing: c.getElementError))
                          Swift 结果: \(String(describing: swiftEl))
                        """)
                    }
                } else {
                    let javaEl = c.getElement!.map { $0 ?? "" }
                    if swiftElThrew || swiftEl == nil {
                        if !knownAnalyzeRegexDivergences.contains(c.name) {
                            failures.append("""
                            [AnalyzeRegex.getElement:\(baseName)/\(c.name)] Java 有结果但 Swift nil/抛错
                              res: \(c.res)  regs: \(c.regs)
                              Java 结果: \(javaEl)
                              Swift 结果: \(swiftElThrew ? "抛错" : "nil")
                            """)
                        }
                    } else if swiftEl! != javaEl && !knownAnalyzeRegexDivergences.contains(c.name) {
                        failures.append("""
                        [AnalyzeRegex.getElement:\(baseName)/\(c.name)] 不一致
                          res: \(c.res)  regs: \(c.regs)
                          Java 结果: \(javaEl)
                          Swift 结果: \(swiftEl!)
                        """)
                    }
                }
                // getElements
                var swiftEls: [[String]] = []
                var swiftElsThrew = false
                do {
                    swiftEls = try AnalyzeByRegex.getElements(c.res, c.regs)
                } catch {
                    swiftElsThrew = true
                }
                if c.getElementsError != nil {
                    if !swiftElsThrew && !swiftEls.isEmpty && !knownAnalyzeRegexDivergences.contains(c.name) {
                        failures.append("""
                        [AnalyzeRegex.getElements:\(baseName)/\(c.name)] Java 抛错但 Swift 有结果
                          res: \(c.res)  regs: \(c.regs)
                          Swift 结果: \(swiftEls)
                        """)
                    }
                } else if !swiftElsThrew && swiftEls != c.getElements && !knownAnalyzeRegexDivergences.contains(c.name) {
                    failures.append("""
                    [AnalyzeRegex.getElements:\(baseName)/\(c.name)] 不一致
                      res: \(c.res)  regs: \(c.regs)
                      Java 结果: \(c.getElements)
                      Swift 结果: \(swiftEls)
                    """)
                }
            }
        }
        if !compared { try failOrSkipWhenNoGoldenData("无 AnalyzeByRegex 用例"); return }
        if !failures.isEmpty { XCTFail("发现 \(failures.count) 处 AnalyzeByRegex 不一致：\n\n" + failures.joined(separator: "\n\n")) }
    }
    private let knownAnalyzeRegexDivergences: Set<String> = []

    // MARK: - JSONPath

    func testGoldenJSONPath() throws {
        let files = goldenFiles()
        if files.isEmpty { try failOrSkipWhenNoGoldenData("未找到 golden 目录"); return }
        var compared = false
        var failures: [String] = []
        for (baseName, env) in decodeAll() {
            guard let cases = env.jsonPathResults else { continue }
            for c in cases {
                compared = true
                let analyzer = AnalyzeByJSonPath(c.json)
                // getString
                let swiftGetString = (try? analyzer.getString(c.rule))
                // Kotlin getString 返回 "" 当读取失败（不是 nil，除非 rule 为空）。Swift 同样。
                let swiftGS = swiftGetString ?? nil
                // getStringList
                let swiftGSL = (try? analyzer.getStringList(c.rule)) ?? []

                // 比较 getString
                if swiftGS != c.getString && !knownJSONPathDivergences.contains(c.name) {
                    failures.append("""
                    [JSONPath.getString:\(baseName)/\(c.name)]
                      规则: \(c.rule)
                      输入(json key=\(c.docKey)): \(c.json)
                      Java 结果: \(String(describing: c.getString))  (threw=\(c.threw))
                      Swift 结果: \(String(describing: swiftGS))
                    """)
                }
                // 比较 getStringList
                if swiftGSL != c.getStringList && !knownJSONPathDivergences.contains(c.name) {
                    failures.append("""
                    [JSONPath.getStringList:\(baseName)/\(c.name)]
                      规则: \(c.rule)
                      输入(json key=\(c.docKey)): \(c.json)
                      Java 结果: \(c.getStringList)  (threw=\(c.threw))
                      Swift 结果: \(swiftGSL)
                    """)
                }
            }
        }
        if !compared { try failOrSkipWhenNoGoldenData("无 JSONPath 用例"); return }
        if !failures.isEmpty { XCTFail("发现 \(failures.count) 处 JSONPath 不一致：\n\n" + failures.joined(separator: "\n\n")) }
    }
    private let knownJSONPathDivergences: Set<String> = []
}
