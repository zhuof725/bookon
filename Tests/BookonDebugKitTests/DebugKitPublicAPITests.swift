//
//  DebugKitPublicAPITests.swift
//  BookonDebugKitTests
//
//  第 7 步 C 段返工：DebugKit 纯 public 接口测试（普通 import，非 @testable）。
//  覆盖：DebugTab 分页签枚举、DebugTabBarState 圆点/红点、DebugTextLimit 字符上限与截断、
//  AppBuildInfo 版本信息、SharedEnvironment 跨实例持久化、DebugSettings 字符上限持久化。
//  遵守全局规则：不崩溃、不用 @testable。
//

import XCTest
import Foundation
import BookonDebugKit
import LegadoBookSource

// MARK: - DebugTab

final class DebugTabPublicTests: XCTestCase {

    func testAllCasesOrderAndCount() {
        XCTAssertEqual(DebugTab.allCases.count, 6)
        XCTAssertEqual(DebugTab.allCases.map { $0.rawValue },
                       ["logs", "searchSource", "infoSource", "tocSource", "contentSource", "result"])
    }

    func testTitles() {
        XCTAssertEqual(DebugTab.logs.title, "日志")
        XCTAssertEqual(DebugTab.searchSource.title, "搜索源码")
        XCTAssertEqual(DebugTab.infoSource.title, "详情源码")
        XCTAssertEqual(DebugTab.tocSource.title, "目录源码")
        XCTAssertEqual(DebugTab.contentSource.title, "正文源码")
        XCTAssertEqual(DebugTab.result.title, "结果")
    }

    func testStageMapping() {
        XCTAssertNil(DebugTab.logs.stage)
        XCTAssertNil(DebugTab.result.stage)
        XCTAssertEqual(DebugTab.searchSource.stage, .search)
        XCTAssertEqual(DebugTab.infoSource.stage, .info)
        XCTAssertEqual(DebugTab.tocSource.stage, .toc)
        XCTAssertEqual(DebugTab.contentSource.stage, .content)
    }

    func testIsSourceTab() {
        XCTAssertFalse(DebugTab.logs.isSourceTab)
        XCTAssertFalse(DebugTab.result.isSourceTab)
        XCTAssertTrue(DebugTab.searchSource.isSourceTab)
        XCTAssertTrue(DebugTab.infoSource.isSourceTab)
        XCTAssertTrue(DebugTab.tocSource.isSourceTab)
        XCTAssertTrue(DebugTab.contentSource.isSourceTab)
    }

    func testPlaceholdersNonEmptyAndDistinct() {
        let placeholders = DebugTab.allCases.map { $0.placeholder }
        XCTAssertTrue(placeholders.allSatisfy { !$0.isEmpty })
        XCTAssertEqual(Set(placeholders).count, placeholders.count, "占位文案应各不相同")
    }

    func testHasCopyButtonForEveryTab() {
        XCTAssertTrue(DebugTab.allCases.allSatisfy { $0.hasCopyButton })
    }

    func testIdentifiableUsesRawValue() {
        XCTAssertEqual(DebugTab.logs.id, "logs")
        XCTAssertEqual(DebugTab.contentSource.id, "contentSource")
    }
}

// MARK: - DebugTabBarState

final class DebugTabBarStatePublicTests: XCTestCase {

    func testEmptyHasNoDots() {
        let state = DebugTabBarState.empty
        for tab in DebugTab.allCases {
            XCTAssertFalse(state.showsDot(for: tab))
            XCTAssertFalse(state.showsErrorDot(for: tab))
        }
    }

    func testDotOnlyForSourceTabsWithResponse() {
        let state = DebugTabBarState(stageHasResponse: [.search: true, .content: true], hasError: false)
        XCTAssertTrue(state.showsDot(for: .searchSource))
        XCTAssertTrue(state.showsDot(for: .contentSource))
        XCTAssertFalse(state.showsDot(for: .infoSource))
        XCTAssertFalse(state.showsDot(for: .tocSource))
        // 日志/结果标签没有阶段，永远不显示小圆点。
        XCTAssertFalse(state.showsDot(for: .logs))
        XCTAssertFalse(state.showsDot(for: .result))
    }

    func testExplicitFalseDoesNotShowDot() {
        let state = DebugTabBarState(stageHasResponse: [.search: false], hasError: false)
        XCTAssertFalse(state.showsDot(for: .searchSource))
    }

    func testErrorDotOnlyOnLogsTab() {
        let state = DebugTabBarState(stageHasResponse: [:], hasError: true)
        XCTAssertTrue(state.showsErrorDot(for: .logs))
        for tab in DebugTab.allCases where tab != .logs {
            XCTAssertFalse(state.showsErrorDot(for: tab))
        }
    }
}

// MARK: - DebugTextLimit

final class DebugTextLimitPublicTests: XCTestCase {

    func testDefaultsAndRanges() {
        XCTAssertEqual(DebugTextLimit.displayDefault, 30000)
        XCTAssertEqual(DebugTextLimit.displayRange.lowerBound, 1000)
        XCTAssertEqual(DebugTextLimit.displayRange.upperBound, 500000)
        XCTAssertEqual(DebugTextLimit.exportDefault, 5000)
        XCTAssertEqual(DebugTextLimit.exportRange.lowerBound, 0)
        XCTAssertEqual(DebugTextLimit.exportRange.upperBound, 100000)
        XCTAssertEqual(DebugTextLimit.hardByteLimit, 5 * 1024 * 1024)
    }

    func testClamp() {
        XCTAssertEqual(DebugTextLimit.clamp(500, to: 1000...5000), 1000)
        XCTAssertEqual(DebugTextLimit.clamp(99999, to: 1000...5000), 5000)
        XCTAssertEqual(DebugTextLimit.clamp(3000, to: 1000...5000), 3000)
        XCTAssertEqual(DebugTextLimit.clamp(-10, to: 0...100), 0)
    }

    func testTruncateBelowLimit() {
        let r = DebugTextLimit.truncate("abcdef", limit: 10)
        XCTAssertEqual(r.text, "abcdef")
        XCTAssertEqual(r.totalCount, 6)
        XCTAssertFalse(r.truncated)
        XCTAssertEqual(r.notice, "")
    }

    func testTruncateExactlyAtLimit() {
        let r = DebugTextLimit.truncate("abcde", limit: 5)
        XCTAssertEqual(r.text, "abcde")
        XCTAssertEqual(r.totalCount, 5)
        XCTAssertFalse(r.truncated)
        XCTAssertEqual(r.notice, "")
    }

    func testTruncateLimitPlusOne() {
        let r = DebugTextLimit.truncate("abcdef", limit: 5)
        XCTAssertEqual(r.text, "abcde")
        XCTAssertEqual(r.totalCount, 6)
        XCTAssertTrue(r.truncated)
        XCTAssertEqual(r.notice, "已截断，显示 5 / 共 6 字符")
    }

    func testTruncateEmptyString() {
        let r = DebugTextLimit.truncate("", limit: 5)
        XCTAssertEqual(r.text, "")
        XCTAssertEqual(r.totalCount, 0)
        XCTAssertFalse(r.truncated)
        XCTAssertEqual(r.notice, "")
    }

    func testTruncateZeroLimit() {
        let r = DebugTextLimit.truncate("abcdef", limit: 0)
        XCTAssertEqual(r.text, "")
        XCTAssertEqual(r.totalCount, 6)
        XCTAssertTrue(r.truncated)
        XCTAssertEqual(r.notice, "已截断，显示 0 / 共 6 字符")
    }

    func testTruncateNegativeLimitTreatedAsZero() {
        let r = DebugTextLimit.truncate("abcdef", limit: -3)
        XCTAssertEqual(r.text, "")
        XCTAssertTrue(r.truncated)
    }

    func testTruncateWithEmojiDoesNotSplitScalar() {
        // 每个 emoji 是 1 个 Character（可能由多个 scalar 组成）。
        let text = "a👍b🎉c🚀d"  // 7 个 Character
        let r = DebugTextLimit.truncate(text, limit: 3)
        XCTAssertEqual(r.text, "a👍b")
        XCTAssertEqual(r.totalCount, 7)
        XCTAssertEqual(r.text.count, 3)
        // 不应出现替换字符（说明没有从代理对中间切开）。
        XCTAssertFalse(r.text.contains("\u{FFFD}"))
    }

    func testTruncateWithCombiningCharactersKeepsGrapheme() {
        // "é" 用 e + U+0301 组合：是 1 个 Character。
        let text = "e\u{0301}xe\u{0301}y"  // é x é y = 4 Character
        XCTAssertEqual(text.count, 4)
        let r = DebugTextLimit.truncate(text, limit: 2)
        XCTAssertEqual(r.text.count, 2, "截断后仍应是完整字素簇")
        XCTAssertTrue(r.text.hasPrefix("e\u{0301}"))
    }

    func testTruncateWithSurrogatePairEmoji() {
        // 🏳️‍🌈 由多个 scalar（含 ZWJ）组成 1 个 Character。
        let flag = "🏳️‍🌈"
        XCTAssertEqual(flag.count, 1)
        let text = flag + "abc"
        let r = DebugTextLimit.truncate(text, limit: 1)
        XCTAssertEqual(r.text, flag)
        XCTAssertEqual(r.text.count, 1)
    }

    func testExportSectionZeroReturnsNil() {
        XCTAssertNil(DebugTextLimit.exportSection(for: "hello", name: "搜索源码", limit: 0))
    }

    func testExportSectionWithLimit() {
        let s = DebugTextLimit.exportSection(for: "abcdefghij", name: "搜索源码", limit: 4)
        XCTAssertNotNil(s)
        XCTAssertEqual(s, "--- 搜索源码 前 4 字符（共 10）（已截断） ---\nabcd")
    }

    func testExportSectionLimitLargerThanSource() {
        let s = DebugTextLimit.exportSection(for: "abc", name: "正文源码", limit: 100)
        XCTAssertEqual(s, "--- 正文源码 前 3 字符（共 3） ---\nabc")
    }

    func testHardByteLimitUnderLimit() {
        let r = DebugTextLimit.applyHardByteLimit("short body")
        XCTAssertFalse(r.exceeded)
        XCTAssertEqual(r.kept, "short body")
        XCTAssertEqual(r.notice, "")
    }

    func testHardByteLimitOverLimitKeepsPrefix() {
        // 构造 6MB 的 ASCII 文本（超 5MB）。
        let big = String(repeating: "a", count: 6 * 1024 * 1024)
        let r = DebugTextLimit.applyHardByteLimit(big)
        XCTAssertTrue(r.exceeded)
        XCTAssertEqual(r.notice, "响应体超过 5MB，仅保留前 5MB")
        XCTAssertLessThanOrEqual(r.kept.utf8.count, DebugTextLimit.hardByteLimit)
        XCTAssertGreaterThan(r.kept.utf8.count, DebugTextLimit.hardByteLimit - 8)
    }

    func testHardByteLimitOverLimitWithMultibyteKeepsValidUTF8() {
        // 6MB 的中文（每字 3 字节），截断点可能落在多字节中间，必须退到合法边界。
        let big = String(repeating: "书源", count: 2 * 1024 * 1024)
        let r = DebugTextLimit.applyHardByteLimit(big)
        XCTAssertTrue(r.exceeded)
        XCTAssertLessThanOrEqual(r.kept.utf8.count, DebugTextLimit.hardByteLimit)
        // 能被重新编码为 UTF-8（说明截断在合法边界）。
        XCTAssertNotNil(String(data: Data(r.kept.utf8), encoding: .utf8))
        XCTAssertFalse(r.kept.contains("\u{FFFD}"))
    }
}

// MARK: - AppBuildInfo

final class AppBuildInfoPublicTests: XCTestCase {

    func testParseFromDictionary() {
        let info = AppBuildInfo(infoDictionary: [
            "CFBundleShortVersionString": "1.2.3",
            "BuildCommit": "abc1234",
            "BuildCIRun": "37313519896"
        ])
        XCTAssertEqual(info.version, "1.2.3")
        XCTAssertEqual(info.commit, "abc1234")
        XCTAssertEqual(info.ciRun, "37313519896")
    }

    func testMissingKeysFallBackToUnknown() {
        let info = AppBuildInfo(infoDictionary: [:])
        XCTAssertEqual(info.version, AppBuildInfo.unknown)
        XCTAssertEqual(info.commit, AppBuildInfo.unknown)
        XCTAssertEqual(info.ciRun, AppBuildInfo.unknown)
    }

    func testNilDictionaryDoesNotCrash() {
        let info = AppBuildInfo(infoDictionary: nil)
        XCTAssertEqual(info.version, AppBuildInfo.unknown)
    }

    func testPlaceholderNotExpandedFallsBackToUnknown() {
        // 本地构建未注入时 plist 里可能是 "$(GIT_COMMIT)"。
        let info = AppBuildInfo(infoDictionary: [
            "CFBundleShortVersionString": "1.0.0",
            "BuildCommit": "$(GIT_COMMIT)",
            "BuildCIRun": "$(CI_RUN_ID)"
        ])
        XCTAssertEqual(info.version, "1.0.0")
        XCTAssertEqual(info.commit, AppBuildInfo.unknown)
        XCTAssertEqual(info.ciRun, AppBuildInfo.unknown)
    }

    func testWhitespaceOnlyFallsBackToUnknown() {
        let info = AppBuildInfo(infoDictionary: ["BuildCommit": "   "])
        XCTAssertEqual(info.commit, AppBuildInfo.unknown)
    }

    func testSummary() {
        let info = AppBuildInfo(version: "1.0.0", commit: "abc1234", ciRun: "999")
        XCTAssertEqual(info.summary, "1.0.0 · commit abc1234 · CI 999")
    }
}

// MARK: - SharedEnvironment（持久化）

final class SharedEnvironmentPublicTests: XCTestCase {

    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("shared-env-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testCookiePersistsAcrossInstances() throws {
        let dir = tempDir()
        let cookieURL = dir.appendingPathComponent("cookies.json")
        let cacheURL = dir.appendingPathComponent("cache.json")

        let env1 = SharedEnvironment(cookieFileURL: cookieURL, cacheFileURL: cacheURL)
        env1.cookieStore.setCookie("https://www.example.com", "token=abc")

        // 新建实例读同一文件：Cookie 仍在（模拟 App 重启）。
        let env2 = SharedEnvironment(cookieFileURL: cookieURL, cacheFileURL: cacheURL)
        XCTAssertEqual(env2.cookieStore.getCookie("https://www.example.com"), "token=abc")
    }

    func testCookieClearedAfterClear() throws {
        let dir = tempDir()
        let cookieURL = dir.appendingPathComponent("cookies.json")
        let cacheURL = dir.appendingPathComponent("cache.json")

        let env = SharedEnvironment(cookieFileURL: cookieURL, cacheFileURL: cacheURL)
        env.cookieStore.setCookie("https://www.example.com", "token=abc")
        env.clearCookies()

        // 清除后：同一实例与新建实例都读不到。
        XCTAssertEqual(env.cookieStore.getCookie("https://www.example.com"), "")
        let env2 = SharedEnvironment(cookieFileURL: cookieURL, cacheFileURL: cacheURL)
        XCTAssertEqual(env2.cookieStore.getCookie("https://www.example.com"), "")
    }

    func testCachePersistsAcrossInstances() throws {
        let dir = tempDir()
        let cookieURL = dir.appendingPathComponent("cookies.json")
        let cacheURL = dir.appendingPathComponent("cache.json")

        let env1 = SharedEnvironment(cookieFileURL: cookieURL, cacheFileURL: cacheURL)
        env1.cacheManager.put("k1", "v1", saveTime: 0)

        let env2 = SharedEnvironment(cookieFileURL: cookieURL, cacheFileURL: cacheURL)
        XCTAssertEqual(env2.cacheManager.get("k1", onlyDisk: true), "v1")
    }

    func testCacheClearedAfterClear() throws {
        let dir = tempDir()
        let cookieURL = dir.appendingPathComponent("cookies.json")
        let cacheURL = dir.appendingPathComponent("cache.json")

        let env = SharedEnvironment(cookieFileURL: cookieURL, cacheFileURL: cacheURL)
        env.cacheManager.put("k1", "v1", saveTime: 0)
        env.clearCache()

        let env2 = SharedEnvironment(cookieFileURL: cookieURL, cacheFileURL: cacheURL)
        XCTAssertNil(env2.cacheManager.get("k1", onlyDisk: true))
    }

    func testClearAllClearsBoth() throws {
        let dir = tempDir()
        let cookieURL = dir.appendingPathComponent("cookies.json")
        let cacheURL = dir.appendingPathComponent("cache.json")

        let env = SharedEnvironment(cookieFileURL: cookieURL, cacheFileURL: cacheURL)
        env.cookieStore.setCookie("https://www.example.com", "token=abc")
        env.cacheManager.put("k1", "v1", saveTime: 0)
        env.clearAll()

        let env2 = SharedEnvironment(cookieFileURL: cookieURL, cacheFileURL: cacheURL)
        XCTAssertEqual(env2.cookieStore.getCookie("https://www.example.com"), "")
        XCTAssertNil(env2.cacheManager.get("k1", onlyDisk: true))
    }

    func testDefaultPathsAreInDocuments() {
        let cookiePath = SharedEnvironment.defaultCookieFileURL().path
        let cachePath = SharedEnvironment.defaultCacheFileURL().path
        XCTAssertTrue(cookiePath.hasSuffix("cookies.json"))
        XCTAssertTrue(cachePath.hasSuffix("legado_cache.json"))
        // 同一目录（Documents 或 Linux 上的临时目录回退）。
        XCTAssertEqual(
            SharedEnvironment.defaultCookieFileURL().deletingLastPathComponent().path,
            SharedEnvironment.defaultCacheFileURL().deletingLastPathComponent().path
        )
    }
}

// MARK: - DebugSettings 字符上限

final class DebugSettingsTextLimitPublicTests: XCTestCase {

    private func makeDefaults() -> UserDefaults {
        let suite = "test-limits-\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    func testDefaultLimits() {
        let s = DebugSettings(defaults: makeDefaults())
        XCTAssertEqual(s.sourceDisplayLimit, DebugTextLimit.displayDefault)
        XCTAssertEqual(s.exportSourceLimit, DebugTextLimit.exportDefault)
    }

    func testClampOverUpperBoundOnInit() {
        let s = DebugSettings(sourceDisplayLimit: 999_999_999,
                              exportSourceLimit: 999_999_999,
                              defaults: makeDefaults())
        XCTAssertEqual(s.sourceDisplayLimit, DebugTextLimit.displayRange.upperBound)
        XCTAssertEqual(s.exportSourceLimit, DebugTextLimit.exportRange.upperBound)
    }

    func testClampNegativeOnInit() {
        let s = DebugSettings(sourceDisplayLimit: -5,
                              exportSourceLimit: -5,
                              defaults: makeDefaults())
        XCTAssertEqual(s.sourceDisplayLimit, DebugTextLimit.displayRange.lowerBound)
        XCTAssertEqual(s.exportSourceLimit, DebugTextLimit.exportRange.lowerBound)
    }

    func testLimitsPersistAcrossInstances() {
        let defaults = makeDefaults()
        let s1 = DebugSettings(sourceDisplayLimit: 12345, exportSourceLimit: 678, defaults: defaults)
        s1.save()

        let s2 = DebugSettings(defaults: defaults)
        XCTAssertEqual(s2.sourceDisplayLimit, 12345)
        XCTAssertEqual(s2.exportSourceLimit, 678)
    }

    func testOutOfRangeStoredValueIsClampedOnLoad() {
        let defaults = makeDefaults()
        // 直接塞越界值（模拟历史脏数据）。
        defaults.set(99_999_999, forKey: "sourceDisplayLimit")
        defaults.set(-1000, forKey: "exportSourceLimit")

        let s = DebugSettings(defaults: defaults)
        XCTAssertEqual(s.sourceDisplayLimit, DebugTextLimit.displayRange.upperBound)
        XCTAssertEqual(s.exportSourceLimit, DebugTextLimit.exportRange.lowerBound)
        // 并且已回写为合法值。
        XCTAssertEqual(defaults.integer(forKey: "sourceDisplayLimit"), DebugTextLimit.displayRange.upperBound)
        XCTAssertEqual(defaults.integer(forKey: "exportSourceLimit"), DebugTextLimit.exportRange.lowerBound)
    }

    func testWrongTypeStoredValueFallsBackToDefault() {
        let defaults = makeDefaults()
        defaults.set("not-a-number", forKey: "sourceDisplayLimit")

        let s = DebugSettings(defaults: defaults)
        XCTAssertEqual(s.sourceDisplayLimit, DebugTextLimit.displayDefault)
        XCTAssertEqual(defaults.integer(forKey: "sourceDisplayLimit"), DebugTextLimit.displayDefault)
    }

    func testStringNumberStoredValueIsRead() {
        let defaults = makeDefaults()
        defaults.set("25000", forKey: "sourceDisplayLimit")
        let s = DebugSettings(defaults: defaults)
        XCTAssertEqual(s.sourceDisplayLimit, 25000)
    }

    func testRestoreDefaultTextLimits() {
        let defaults = makeDefaults()
        let s = DebugSettings(sourceDisplayLimit: 200000, exportSourceLimit: 90000, defaults: defaults)
        s.restoreDefaultTextLimits()
        XCTAssertEqual(s.sourceDisplayLimit, DebugTextLimit.displayDefault)
        XCTAssertEqual(s.exportSourceLimit, DebugTextLimit.exportDefault)
        // 也已持久化。
        let s2 = DebugSettings(defaults: defaults)
        XCTAssertEqual(s2.sourceDisplayLimit, DebugTextLimit.displayDefault)
        XCTAssertEqual(s2.exportSourceLimit, DebugTextLimit.exportDefault)
    }

    func testRestoreDoesNotTouchTimeouts() {
        let defaults = makeDefaults()
        let s = DebugSettings(connectTimeout: 33, readTimeout: 44, totalTimeout: 55, defaults: defaults)
        s.restoreDefaultTextLimits()
        XCTAssertEqual(s.connectTimeout, 33)
        XCTAssertEqual(s.readTimeout, 44)
        XCTAssertEqual(s.totalTimeout, 55)
    }
}

// MARK: - DebugKeyExample（输入框示例提示）

final class DebugKeyExamplePublicTests: XCTestCase {

    func testFiveFormsInOrder() {
        let hints = DebugKeyExample.all.map { $0.hint }
        XCTAssertEqual(hints, ["关键字", "详情页网址", "::发现页", "++目录页", "--正文页"])
    }

    func testEveryHintHasNonEmptySample() {
        XCTAssertTrue(DebugKeyExample.all.allSatisfy { !$0.sample.isEmpty })
    }

    func testIdsAreUnique() {
        let ids = DebugKeyExample.all.map { $0.id }
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertEqual(ids, DebugKeyExample.all.map { $0.hint })
    }

    func testPrefixFormsMatchDebugKeySyntax() {
        // 与 Debug.startDebug 的分发前缀一致：:: 发现 / ++ 目录 / -- 正文。
        let byHint = Dictionary(uniqueKeysWithValues: DebugKeyExample.all.map { ($0.hint, $0.sample) })
        XCTAssertEqual(byHint["::发现页"]?.hasPrefix("::"), true)
        XCTAssertEqual(byHint["++目录页"]?.hasPrefix("++"), true)
        XCTAssertEqual(byHint["--正文页"]?.hasPrefix("--"), true)
        XCTAssertEqual(byHint["关键字"]?.hasPrefix("::"), false)
        XCTAssertEqual(byHint["详情页网址"]?.hasPrefix("http"), true)
    }
}

// MARK: - ImportOutcome / ImportResultSummary（导入结果弹窗文案）

final class ImportOutcomePublicTests: XCTestCase {

    func testAllSuccessHasNoFailureOrWarning() {
        let outcome = ImportOutcome(importedCount: 5, failures: [], warnings: [])
        XCTAssertTrue(outcome.isAllSuccess)
        XCTAssertEqual(outcome.failureText, "")
        XCTAssertEqual(outcome.warningText, "")

        let summary = ImportResultSummary(outcome: outcome)
        XCTAssertEqual(summary.successText, "成功导入 5 个书源")
        XCTAssertNil(summary.failureText)
        XCTAssertNil(summary.warningText)
        XCTAssertEqual(summary.detailText, "成功导入 5 个书源")
    }

    func testFailureTextFormat() {
        let outcome = ImportOutcome(
            importedCount: 2,
            failures: [
                .init(index: 0, reason: "缺少 bookSourceUrl"),
                .init(index: 3, reason: "JSON 结构不合法"),
            ],
            warnings: []
        )
        XCTAssertFalse(outcome.isAllSuccess)
        XCTAssertEqual(outcome.failureText, "#0 缺少 bookSourceUrl\n#3 JSON 结构不合法")

        let summary = ImportResultSummary(outcome: outcome)
        XCTAssertEqual(summary.failureText, "#0 缺少 bookSourceUrl\n#3 JSON 结构不合法")
        XCTAssertTrue(summary.detailText.contains("失败 2 条"))
        XCTAssertTrue(summary.detailText.contains("#0 缺少 bookSourceUrl"))
    }

    func testWarningTextWithAndWithoutField() {
        let outcome = ImportOutcome(
            importedCount: 1,
            failures: [],
            warnings: [
                .init(field: "ruleSearch", message: "内层解析失败，已置空"),
                .init(field: nil, message: "未知字段被忽略"),
                .init(field: "", message: "空字段名"),
            ]
        )
        XCTAssertEqual(outcome.warningText,
                       "ruleSearch：内层解析失败，已置空\n未知字段被忽略\n空字段名")
        let summary = ImportResultSummary(outcome: outcome)
        XCTAssertEqual(summary.warningText, outcome.warningText)
        XCTAssertTrue(summary.detailText.contains("警告："))
    }

    func testDetailTextIncludesAllThreeSections() {
        let outcome = ImportOutcome(
            importedCount: 3,
            failures: [.init(index: 1, reason: "坏条目")],
            warnings: [.init(field: "ruleToc", message: "已置空")]
        )
        let summary = ImportResultSummary(outcome: outcome)
        XCTAssertTrue(summary.detailText.contains("成功导入 3 个书源"))
        XCTAssertTrue(summary.detailText.contains("失败 1 条"))
        XCTAssertTrue(summary.detailText.contains("警告："))
        // 三段之间空行分隔。
        XCTAssertEqual(summary.detailText.components(separatedBy: "\n\n").count, 3)
    }

    func testZeroImportedAllFailure() {
        let outcome = ImportOutcome(
            importedCount: 0,
            failures: [.init(index: 0, reason: "顶层不是数组")],
            warnings: []
        )
        XCTAssertFalse(outcome.isAllSuccess)
        XCTAssertEqual(outcome.importedCount, 0)
    }
}

// MARK: - 仓库「详细导入」接口（失败原因 / 警告原样返回）

final class BookSourceRepositoryDetailedImportTests: XCTestCase {

    private func tempStorage() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("repo-\(UUID().uuidString).json")
    }

    private func repository() -> BookSourceRepository {
        BookSourceRepository(storageURL: tempStorage(), fetcher: { _ in Data() })
    }

    private func validSourceJSON(name: String, url: String) -> String {
        """
        {"bookSourceName":"\(name)","bookSourceUrl":"\(url)","enabled":true,"bookSourceType":0}
        """
    }

    func testDetailedImportCountsSuccesses() throws {
        let repo = repository()
        let json = "[\(validSourceJSON(name: "A", url: "http://a.test")),"
            + "\(validSourceJSON(name: "B", url: "http://b.test"))]"
        let outcome = try repo.importSourcesDetailed(jsonText: json)
        XCTAssertEqual(outcome.importedCount, 2)
        XCTAssertTrue(outcome.isAllSuccess)
        XCTAssertEqual(repo.sources.count, 2)
    }

    func testDetailedImportReportsFailures() throws {
        let repo = repository()
        // 第二个条目不是 JSON 对象（这里是数字）→ 该条无法序列化/解码为 BookSource，记为失败，
        // 但不影响第一条。
        // 注意：BookSourceImporter 是「逐条容错」的——**缺字段或字段类型不符都会走宽松默认值**，
        // 只有「数组元素根本不是一个对象」才真正失败。所以这里用 12345 而非缺字段条目。
        let json = "[\(validSourceJSON(name: "A", url: "http://a.test")),12345]"
        let outcome = try repo.importSourcesDetailed(jsonText: json)
        XCTAssertEqual(outcome.importedCount, 1)
        XCTAssertEqual(outcome.failures.count, 1)
        XCTAssertEqual(outcome.failures[0].index, 1)
        XCTAssertFalse(outcome.failures[0].reason.isEmpty)
        XCTAssertEqual(repo.sources.count, 1)
    }

    func testDetailedImportInvalidTopLevelThrows() {
        let repo = repository()
        XCTAssertThrowsError(try repo.importSourcesDetailed(jsonText: "not json at all"))
    }

    func testDetailedImportFromFileURL() throws {
        let repo = repository()
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("sources-\(UUID().uuidString).json")
        try Data(validSourceJSON(name: "F", url: "http://f.test").utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        let outcome = try repo.importSourcesDetailed(fileURL: file)
        XCTAssertEqual(outcome.importedCount, 1)
        XCTAssertEqual(repo.sources.first?.bookSourceName, "F")
    }

    func testDetailedImportFromURLUsesInjectedFetcher() async throws {
        let json = validSourceJSON(name: "N", url: "http://n.test")
        let repo = BookSourceRepository(
            storageURL: tempStorage(),
            fetcher: { _ in Data(json.utf8) }
        )
        let outcome = try await repo.importSourcesDetailed(url: URL(string: "http://example.test/s.json")!)
        XCTAssertEqual(outcome.importedCount, 1)
        XCTAssertEqual(repo.sources.first?.bookSourceUrl, "http://n.test")
    }
}
