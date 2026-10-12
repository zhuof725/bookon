import Foundation

var checks = 0
var failures = 0
func check(_ condition: Bool, _ message: String) {
    checks += 1
    if !condition { failures += 1 }
    print("\(condition ? "PASS" : "FAIL") \(message)")
}
func parse(_ text: String, rules: [TxtTocRule]) throws -> LocalBookData {
    try LocalBook.parseTXT(Data(text.utf8), fileName: "回归.txt", rules: rules)
}
func run() throws {
    let builtIns = TxtTocRule.builtIns
    let samples: [(String, String)] = [
        ("chapter", "第一章 出发"), ("episode", "第二话 重逢"),
        ("volume-chapter", "第一卷 第二章 归来"), ("preface", "序章"),
        ("chapter-en", "Chapter 3 Start"), ("chapter-upper", "CHAPTER 4 END"),
        ("roman", "IV. Arrival"), ("number", "12. 开始"),
        ("chinese-number", "十二、重逢"), ("bracket-chapter", "【第三章】归来"),
        ("bracket-title", "【远方】"), ("volume", "卷二 风云"),
        ("number-space", "13 新世界"), ("equals", "=== 分界 ==="),
        ("dashes", "--- 分界 ---")
    ]
    check(builtIns.count == 15, "exactly 15 bundled rules")
    check(Set(builtIns.map(\.id)) == Set(samples.map { "builtin." + $0.0 }), "stable unique builtin IDs")
    check(builtIns.allSatisfy(\.isBuiltIn), "all bundled rules are read-only")
    for (id, heading) in samples {
        guard let rule = builtIns.first(where: { $0.id == "builtin." + id }) else {
            check(false, "missing builtin \(id)"); continue
        }
        do {
            let regex = try NSRegularExpression(pattern: rule.pattern)
            let full = NSRange(location: 0, length: (heading as NSString).length)
            check(regex.firstMatch(in: heading, range: full)?.range == full, "regex compiles and matches \(id)")
            check(TxtTocRule.validationMessage(name: rule.name, pattern: rule.pattern) == nil, "builtin validates \(id)")
            check(TxtTocMatcher(rules: [rule]).isHeading(heading), "matcher recognizes \(id)")
            let book = try parse(heading + "\n正文内容。", rules: [rule])
            check(book.chapters == [LocalChapter(title: heading, text: "正文内容。")], "single heading retained \(id)")
        } catch { check(false, "builtin \(id): \(error)") }
    }
    let matcher = TxtTocMatcher(rules: builtIns)
    for prose in ["", "   ", "普通的一句话。", "他读完第一章后继续散步。", "We discussed Chapter 3 yesterday.", String(repeating: "正文", count: 100)] {
        check(!matcher.isHeading(prose), "normal prose rejected: \(prose.prefix(20))")
    }
    let headings = ["第一卷 第一章 启程", "【第二章】归来", "Chapter 3 End", "--- 尾部 ---"]
    let mixedText = headings.enumerated().map { "\($0.element)\n正文\($0.offset)" }.joined(separator: "\n")
    let mixed = try parse(mixedText, rules: builtIns)
    check(mixed.chapters.map(\.title) == headings, "overlapping mixed rules split each heading once")
    check(mixed.chapters.map(\.text) == headings.indices.map { "正文\($0)" }, "mixed bodies contain no duplicated heading")
    let largeBody = Array(repeating: String(repeating: "文", count: 100), count: 61).joined(separator: "\n")
    let single = try parse("第一章 唯一\n" + largeBody, rules: builtIns)
    check(single.chapters == [LocalChapter(title: "第一章 唯一", text: largeBody)], "single matched heading never falls back above 5000 characters")
    let fallback = try parse(largeBody, rules: builtIns)
    check(fallback.chapters.count > 1 && fallback.chapters.allSatisfy { $0.title.hasPrefix("第 ") }, "unmatched text above 5000 characters uses size fallback")
    check(fallback.chapters.map(\.text).joined(separator: "\n") == largeBody, "fallback preserves every body line")
    let disabled = try parse("第一章 不启用\n正文", rules: [])
    check(disabled.chapters.first?.title == "第 1 部分", "explicit empty snapshot disables builtins")
    let shortHead = try parse("《测试书》\n作者：张三\n第一章 出发\n正文", rules: builtIns)
    check(shortHead.author == "张三" && shortHead.chapters.map(\.title) == ["第一章 出发"], "short metadata preface trimmed without losing sole title")
    let preface = String(repeating: "这是一段较长的前言文字。", count: 12)
    let longHead = try parse(preface + "\n第一章 出发\n正文", rules: builtIns)
    check(longHead.chapters == [LocalChapter(title: "前言", text: preface), LocalChapter(title: "第一章 出发", text: "正文")], "long preface remains intact")
    let fixture = URL(fileURLWithPath: "Tools/SourceTest/Fixtures/sample-gbk.txt")
    let gbk = try LocalBook.parseTXT(Data(contentsOf: fixture), fileName: "《测试书》作者：张三.txt", rules: builtIns)
    check(gbk.title == "测试书" && gbk.author == "张三", "explicit snapshot keeps GBK book metadata")
    check(gbk.chapters.map(\.title) == ["序章", "第一章 出发", "第二章 到达"], "explicit snapshot splits GBK headings")
    check(gbk.chapters.dropFirst().first?.text == "他出发了。", "GBK body excludes heading")

    let suite = "TxtTocRuleTest." + UUID().uuidString
    guard let defaults = UserDefaults(suiteName: suite) else { check(false, "isolated defaults suite available"); return }
    defer { defaults.removePersistentDomain(forName: suite) }
    let repository = TxtTocRuleRepository(defaults: defaults)
    check(repository.customRules().isEmpty && repository.rules == builtIns, "fresh suite has builtins only")
    var custom = TxtTocRule(id: "custom.rocket", name: "火箭目录", pattern: #"^🚀\s+.+$"#, isBuiltIn: false)
    try repository.save([custom])
    guard let reloadedDefaults = UserDefaults(suiteName: suite) else { check(false, "reopen isolated suite"); return }
    let reopened = TxtTocRuleRepository(defaults: reloadedDefaults)
    check(reopened.customRules() == [custom], "custom add survives defaults and repository recreation")
    let saved = defaults.data(forKey: TxtTocRuleRepository.storageKey)
    check(saved.flatMap { try? JSONDecoder().decode([TxtTocRule].self, from: $0) } == [custom], "persisted payload contains custom rules only")
    let snapshot = reopened.rules
    let customBook = try parse("🚀 起航😀\r\n正文甲😀\r\n🚀 抵达🌙\r\n正文乙🌙\r\n", rules: snapshot)
    check(customBook.chapters.map(\.title) == ["🚀 起航😀", "🚀 抵达🌙"], "custom emoji headings use correct UTF16 ranges with CRLF")
    check(customBook.chapters.map(\.text) == ["正文甲😀", "正文乙🌙"], "CRLF normalized without damaging emoji bodies")
    custom.name = "星标目录"; custom.pattern = #"^⭐\s+.+$"#
    try repository.save([custom])
    check(reopened.customRules() == [custom], "custom update persists name and regex under same ID")
    check(repository.rules.filter(\.isBuiltIn) == builtIns, "updating custom rules leaves builtins unchanged")
    check(try parse("🚀 旧快照\n正文", rules: snapshot).chapters.first?.title == "🚀 旧快照", "explicit parse snapshot unaffected by later persistence updates")
    for pattern in ["(", "", "   ", ".*", "^$", #"^\s*$"#, "a*"] {
        check(TxtTocRule.validationMessage(name: "非法规则", pattern: pattern) != nil, "reject invalid or empty-matching regex: \(pattern)")
        let invalid = TxtTocRule(id: "custom.invalid", name: "非法规则", pattern: pattern, isBuiltIn: false)
        do { try repository.save([invalid]); check(false, "invalid save must throw: \(pattern)") }
        catch { check(true, "invalid save rejected: \(pattern)") }
        check(repository.customRules() == [custom], "failed save preserves previous custom rules")
    }
    check(TxtTocRule.validationMessage(name: " \n", pattern: "^x+$") != nil, "blank custom name rejected")
    try repository.save(builtIns + [custom])
    check(repository.customRules() == [custom] && repository.rules == builtIns + [custom], "saving bundled entries cannot duplicate or replace builtins")
    try repository.save([])
    check(repository.customRules().isEmpty && repository.rules == builtIns, "deleting custom rules preserves all builtins")
    defaults.set(Data("not valid JSON".utf8), forKey: TxtTocRuleRepository.storageKey)
    check(repository.customRules().isEmpty && repository.rules == builtIns, "corrupt custom payload falls back to bundled rules")
    // Existing default-parser fixtures exercise legacy behavior; no .standard writes.
    try LocalBookRegression.run(check)
}
do { try run() } catch { check(false, "unexpected regression error: \(error)") }
print("TXT TOC regression: \(checks) checks, \(failures) failures")
if failures > 0 { exit(1) }
