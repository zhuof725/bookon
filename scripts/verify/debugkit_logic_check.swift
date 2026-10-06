import Foundation
import BookonDebugKit
import LegadoBookSource

var pass = 0, fail = 0
func ok(_ cond: Bool, _ msg: String) {
    if cond { pass += 1 } else { fail += 1; print("FAIL: \(msg)") }
}

// DebugTab
ok(DebugTab.allCases.count == 6, "tab count")
ok(DebugTab.allCases.map{$0.rawValue} == ["logs","searchSource","infoSource","tocSource","contentSource","result"], "tab order")
ok(DebugTab.searchSource.stage == .search && DebugTab.logs.stage == nil && DebugTab.result.stage == nil, "stage map")
ok(DebugTab.allCases.allSatisfy{ !$0.placeholder.isEmpty }, "placeholders")
ok(Set(DebugTab.allCases.map{$0.placeholder}).count == 6, "placeholders distinct")

// TabBarState
let st = DebugTabBarState(stageHasResponse: [.search: true, .content: true], hasError: true)
ok(st.showsDot(for: .searchSource) && st.showsDot(for: .contentSource), "dot source")
ok(!st.showsDot(for: .infoSource) && !st.showsDot(for: .logs) && !st.showsDot(for: .result), "no dot")
ok(st.showsErrorDot(for: .logs) && !st.showsErrorDot(for: .result), "error dot")
ok(!DebugTabBarState.empty.showsDot(for: .searchSource), "empty no dot")

// DebugTextLimit
ok(DebugTextLimit.displayDefault == 30000 && DebugTextLimit.exportDefault == 5000, "defaults")
ok(DebugTextLimit.clamp(500, to: 1000...5000) == 1000, "clamp low")
ok(DebugTextLimit.clamp(99999, to: 1000...5000) == 5000, "clamp high")
let t1 = DebugTextLimit.truncate("abcdef", limit: 10)
ok(t1.text == "abcdef" && !t1.truncated && t1.notice == "", "no trunc")
let t2 = DebugTextLimit.truncate("abcdef", limit: 5)
ok(t2.text == "abcde" && t2.truncated && t2.notice == "已截断，显示 5 / 共 6 字符", "trunc")
let t3 = DebugTextLimit.truncate("abcdef", limit: 0)
ok(t3.text == "" && t3.truncated && t3.totalCount == 6, "zero limit")
let t4 = DebugTextLimit.truncate("a👍b🎉c🚀d", limit: 3)
ok(t4.text == "a👍b" && t4.text.count == 3 && !t4.text.contains("\u{FFFD}"), "emoji no split")
let t5 = DebugTextLimit.truncate("e\u{0301}xe\u{0301}y", limit: 2)
ok(t5.text.count == 2 && t5.text.hasPrefix("e\u{0301}"), "combining grapheme")
ok(DebugTextLimit.truncate("", limit: 5).totalCount == 0, "empty")
ok(DebugTextLimit.exportSection(for: "hello", name: "搜索源码", limit: 0) == nil, "export 0 nil")
ok(DebugTextLimit.exportSection(for: "abcdefghij", name: "搜索源码", limit: 4) == "--- 搜索源码 前 4 字符（共 10）（已截断） ---\nabcd", "export section")
ok(DebugTextLimit.exportSection(for: "abc", name: "正文源码", limit: 100) == "--- 正文源码 前 3 字符（共 3） ---\nabc", "export section 2")
let h1 = DebugTextLimit.applyHardByteLimit("short")
ok(!h1.exceeded && h1.kept == "short", "hard under")
let big = String(repeating: "a", count: 6*1024*1024)
let h2 = DebugTextLimit.applyHardByteLimit(big)
ok(h2.exceeded && h2.kept.utf8.count <= DebugTextLimit.hardByteLimit && h2.notice == "响应体超过 5MB，仅保留前 5MB", "hard over")
let bigCJK = String(repeating: "书源", count: 2*1024*1024)
let h3 = DebugTextLimit.applyHardByteLimit(bigCJK)
ok(h3.exceeded && h3.kept.utf8.count <= DebugTextLimit.hardByteLimit && !h3.kept.contains("\u{FFFD}"), "hard cjk")

// AppBuildInfo
let info = AppBuildInfo(infoDictionary: ["CFBundleShortVersionString":"1.2.3","BuildCommit":"abc1234","BuildCIRun":"999"])
ok(info.version == "1.2.3" && info.commit == "abc1234" && info.ciRun == "999", "buildinfo parse")
ok(AppBuildInfo(infoDictionary: nil).version == AppBuildInfo.unknown, "buildinfo nil")
let ph = AppBuildInfo(infoDictionary: ["BuildCommit":"$(GIT_COMMIT)"])
ok(ph.commit == AppBuildInfo.unknown, "buildinfo placeholder")
ok(AppBuildInfo(version:"1.0.0",commit:"abc",ciRun:"1").summary == "1.0.0 · commit abc · CI 1", "summary")

print("PASS=\(pass) FAIL=\(fail)")
exit(fail == 0 ? 0 : 1)
